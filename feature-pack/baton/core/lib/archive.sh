#!/usr/bin/env bash
# baton lib/archive.sh — 워크트리 아카이브 (프로젝트 내부 .baton/archive/, git-tracked)
# da 권고 적용: 프로젝트 내부 위치 + chmod 600 + tags 필드
# v1.2.10: tar -h 제거 (심링크 dereference가 node_modules/.venv 실체를 따라가 수백 MB tar 생성 — 2026-06-05 BYZ 실증)

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

# 프로젝트 .baton/archive/ 위치 찾기
baton_archive_dir() {
  # linked worktree에서 호출해도 main worktree 경로 반환.
  # `git worktree list --porcelain` 의 첫 entry 가 main worktree.
  # (git rev-parse --show-superproject-working-tree 는 submodule 전용이라 linked worktree 미지원)
  local main_root=""
  if main_root=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2; exit}'); then
    [[ -n "$main_root" ]] || main_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
  else
    main_root="$PWD"
  fi
  echo "$main_root/.baton/archive"
}

baton_archive_index() {
  echo "$(baton_archive_dir)/INDEX.jsonl"
}

baton_archive_init() {
  local d
  d=$(baton_archive_dir)
  mkdir -p "$d"
  chmod 700 "$d"
  [[ -f "$d/INDEX.jsonl" ]] || : > "$d/INDEX.jsonl"
}

# 미머지 패치 상한 (v1.2.17) — 넘으면 패치를 버리고 tip 메타만 남긴다
BATON_ARCHIVE_PATCH_MAX_BYTES="${BATON_ARCHIVE_PATCH_MAX_BYTES:-52428800}"

# 패치에서 뺄 경로 (v1.2.17) — 로그·증거·음성·이미지·묶음은 보관 가치 대비 크기가 크다
BATON_ARCHIVE_PATCH_EXCLUDES=(
  ':(exclude)*.log' ':(exclude,glob)**/evidence/**' ':(exclude)*.wav'
  ':(exclude)*.jsonl' ':(exclude)*.png' ':(exclude)*.tar*'
)

# 비교 기준 ref (v1.2.17 · 로컬 main 이 멈춰 있으면 main..HEAD 가 원격 역사 전체가 된다)
# 순서: ①BATON_ARCHIVE_BASE ②.worktree-info.json 의 base ③origin/main ④main — 실재하는 첫 ref
# 하나도 없으면 빈 출력 + rc1
# args: $1=worktree path
_baton_archive_base() {
  local wt_path=$1 wt_base="" ref
  if [[ -f "$wt_path/.worktree-info.json" ]]; then
    wt_base=$(jq -r '.base // empty' "$wt_path/.worktree-info.json" 2>/dev/null) || wt_base=""
  fi
  for ref in "${BATON_ARCHIVE_BASE:-}" "$wt_base" origin/main main; do
    [[ -n "$ref" ]] || continue
    if git -C "$wt_path" rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1; then
      echo "$ref"
      return 0
    fi
  done
  return 1
}

# 머지 판정 (v1.2.17): HEAD 가 origin/main·main·master 조상 ∨ 착지 sha(BATON_ARCHIVE_LANDED)가 그 조상
# squash 랜딩은 가지 tip 이 조상이 아니므로 착지 sha 로만 잡힌다
# args: $1=worktree path
_baton_archive_merged() {
  local wt_path=$1 mb sha
  for mb in origin/main main master; do
    git -C "$wt_path" rev-parse -q --verify "$mb^{commit}" >/dev/null 2>&1 || continue
    for sha in HEAD "${BATON_ARCHIVE_LANDED:-}"; do
      [[ -n "$sha" ]] || continue
      git -C "$wt_path" merge-base --is-ancestor "$sha" "$mb" 2>/dev/null && return 0
    done
  done
  if [[ -n "${BATON_ARCHIVE_LANDED:-}" ]]; then
    echo "archive: 착지 sha 가 main 조상 아님 — 미머지로 처리: $BATON_ARCHIVE_LANDED" >&2
  fi
  return 1
}

# 브랜치가 리포에 남아 있나 (있으면 패치는 리포 내용의 복제다)
# args: $1=worktree path, $2=branch
_baton_archive_branch_kept() {
  local wt_path=$1 branch=$2
  [[ -n "$branch" && "$branch" != "unknown" ]] || return 1
  git -C "$wt_path" show-ref -q --verify "refs/heads/$branch" && return 0
  git -C "$wt_path" show-ref -q --verify "refs/archive/$branch"
}

# 미머지 패치 작성 — 결과 상태를 stdout 1단어(included|empty|oversize)로
# args: $1=worktree path, $2=merge-base sha, $3=patch file
_baton_archive_write_patch() {
  local wt_path=$1 base_sha=$2 diff_file=$3 size
  git -C "$wt_path" log "$base_sha"..HEAD --pretty=fuller --patch --no-textconv --no-ext-diff \
    -- . "${BATON_ARCHIVE_PATCH_EXCLUDES[@]}" > "$diff_file" 2>/dev/null || true
  if [[ ! -s "$diff_file" ]]; then
    rm -f "$diff_file"; echo "empty"; return
  fi
  size=$(stat -f%z "$diff_file" 2>/dev/null || stat -c%s "$diff_file")
  if [[ "$size" -gt "$BATON_ARCHIVE_PATCH_MAX_BYTES" ]]; then
    rm -f "$diff_file"; echo "oversize"; return
  fi
  echo "included"
}

# 워크트리 → tar.gz + INDEX append
# args: $1=worktree path, $2 (optional)=tags(comma)
baton_archive_create() {
  local wt_path=$1
  local tags="${2:-}"
  command -v jq >/dev/null || { echo "❌ jq required" >&2; return 2; }
  baton_archive_init
  local archive_root
  archive_root=$(baton_archive_dir)
  local index
  index=$(baton_archive_index)

  local branch phase ts id_safe
  branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "unknown")
  phase=$(awk '/^phase:/ {print $2; exit}' "$wt_path/.baton/handoff/CURRENT.md" 2>/dev/null || echo "$branch")
  ts=$(date +"%Y%m%d_%H%M")
  id_safe="${phase//\//_}_${ts}"
  local archive_file="$archive_root/${id_safe}.tar.gz"

  local merged_to_main=false merged_pr="null"
  _baton_archive_merged "$wt_path" && merged_to_main=true

  # 보관 대상 — 핸드오프만 (소스는 git에 있음)
  # v1.2.10: .env/.claude/.omc/.baton 전체 → .baton/handoff + .worktree-info.json 축소
  # (심링크 구조 워크트리에서 tar 폭발 방지 + 시크릿이 git-tracked archive에 들어가는 문제 해소)
  local items=()
  [[ -d "$wt_path/.baton/handoff" ]] && items+=(".baton/handoff")
  [[ -e "$wt_path/.worktree-info.json" ]] && items+=(".worktree-info.json")

  # 미머지 패치 (v1.2.17): merged → 0 · 브랜치 남음 → 0 · 기준 없음 → 0 · 그 외 merge-base..HEAD (상한 초과면 0)
  local tip base_ref="" base_sha="" patch diff_file="$wt_path/.unmerged-changes.patch"
  tip=$(git -C "$wt_path" rev-parse HEAD 2>/dev/null || echo "unknown")
  if base_ref=$(_baton_archive_base "$wt_path"); then
    base_sha=$(git -C "$wt_path" merge-base "$base_ref" HEAD 2>/dev/null || true)
  fi
  if $merged_to_main; then
    patch="merged"
  elif _baton_archive_branch_kept "$wt_path" "$branch"; then
    patch="skipped"
  elif [[ -z "$base_sha" ]]; then
    patch="nobase"
  else
    patch=$(_baton_archive_write_patch "$wt_path" "$base_sha" "$diff_file")
  fi
  [[ "$patch" == "included" ]] && items+=(".unmerged-changes.patch")
  local patch_meta="patch=$patch branch=$branch tip=$tip"

  # 끝 커밋 1줄 — 패치가 없어도 tar 안에서 «어디까지였나» 가 보인다
  local meta_file="$wt_path/.archive-meta.txt"
  printf '%s base=%s merge_base=%s\n' "$patch_meta" "${base_ref:-none}" "${base_sha:-none}" > "$meta_file"
  items+=(".archive-meta.txt")

  # 심링크는 링크 그대로 보관 (-h 금지: 실체 추적 시 수백 MB tar — v1.2.10)
  tar czf "$archive_file" -C "$wt_path" "${items[@]}" 2>/dev/null
  chmod 600 "$archive_file"  # da 권고: archive 권한 제한
  rm -f "$diff_file" "$meta_file"

  local size archived_at commits files tags_json
  size=$(stat -f%z "$archive_file" 2>/dev/null || stat -c%s "$archive_file")
  archived_at=$(date +"%Y-%m-%dT%H:%M:%S%z")
  # `| head -20` 은 git log 를 SIGPIPE(141)로 끊어 pipefail 이 `|| echo '[]'` 를 배열 뒤에 덧붙였다 → `-n 20`
  commits='[]'
  if [[ -n "$base_sha" ]]; then
    commits=$(git -C "$wt_path" log -n 20 "$base_sha"..HEAD --pretty='%H' 2>/dev/null | jq -R . | jq -s .) || commits='[]'
  fi
  files=$(printf '%s\n' "${items[@]}" | jq -R . | jq -s .)
  if [[ -z "$tags" ]]; then
    tags_json='[]'
  else
    tags_json=$(echo "$tags" | tr ',' '\n' | jq -R . | jq -s .)
  fi

  jq -nc \
    --arg id "$id_safe" \
    --arg branch "$branch" \
    --arg phase "$phase" \
    --arg archived_at "$archived_at" \
    --arg worktree "$wt_path" \
    --argjson commits "$commits" \
    --argjson size_bytes "$size" \
    --argjson merged_to_main "$merged_to_main" \
    --arg merged_pr "$merged_pr" \
    --argjson files "$files" \
    --argjson tags "$tags_json" \
    --arg patch "$patch" \
    --arg tip "$tip" \
    --arg patch_meta "$patch_meta" \
    '{id:$id, branch:$branch, phase:$phase, archived_at:$archived_at, worktree:$worktree, commits:$commits, size_bytes:$size_bytes, merged_to_main:$merged_to_main, merged_pr:$merged_pr, files:$files, tags:$tags, patch:$patch, tip:$tip, patch_meta:$patch_meta}' \
    >> "$index" || { echo "❌ archive INDEX append 실패: $index ($archive_file)" >&2; return 1; }

  echo "$archive_file"
}

baton_archive_list() {
  local days="${1:-30}"
  local index
  index=$(baton_archive_index)
  [[ -s "$index" ]] || { echo "(아카이브 없음)"; return; }
  command -v jq >/dev/null || { cat "$index"; return; }
  local cutoff
  cutoff=$(date -v-${days}d +"%Y-%m-%d" 2>/dev/null || date -d "-${days} days" +"%Y-%m-%d")
  jq -r --arg c "$cutoff" '
    select(.archived_at >= $c)
    | "\(.id)\t\(.branch)\t\(if .merged_to_main then "✓ merged " + (.merged_pr // "") else "✗ unmerged" end)\t\(.size_bytes)B\t\(.tags | join(","))"
  ' "$index" | column -t -s $'\t'
}

baton_archive_show() {
  local id=$1
  local index
  index=$(baton_archive_index)
  jq -r --arg id "$id" 'select(.id == $id)' "$index"
}

baton_archive_path() {
  local id=$1
  echo "$(baton_archive_dir)/${id}.tar.gz"
}

baton_archive_extract() {
  local id=$1
  local archive_file
  archive_file=$(baton_archive_path "$id")
  [[ -f "$archive_file" ]] || { echo "❌ not found: $id" >&2; return 1; }
  # 고정 경로 /tmp/baton-extracted/<id>/ — 스킬 도움말 일관성 (macOS $TMPDIR 우회)
  local target="/tmp/baton-extracted/$id"
  mkdir -p "$target"
  tar xzf "$archive_file" -C "$target"
  echo "$target"
}

baton_archive_close() {
  local id=$1
  local target="/tmp/baton-extracted/$id"
  if [[ -d "$target" ]]; then
    rm -rf "$target"
    echo "✓ 정리: $target"
  fi
}

# Prune (30일 + LAST_PRUNE 갱신)
baton_archive_prune() {
  local retention="${1:-30}"
  local dry_run="${2:-false}"
  local index
  index=$(baton_archive_index)
  local archive_root
  archive_root=$(baton_archive_dir)
  local last_prune="$archive_root/.last_prune"

  [[ -s "$index" ]] || { date +"%s" > "$last_prune"; echo "(없음)"; return; }
  command -v jq >/dev/null || { echo "❌ jq required" >&2; return 2; }

  local cutoff
  cutoff=$(date -v-${retention}d +"%Y-%m-%d" 2>/dev/null || date -d "-${retention} days" +"%Y-%m-%d")
  local removed=0 freed=0
  local tmp_index
  tmp_index=$(mktemp)

  while IFS= read -r line; do
    local id ts size
    id=$(echo "$line" | jq -r '.id')
    ts=$(echo "$line" | jq -r '.archived_at' | cut -d'T' -f1)
    size=$(echo "$line" | jq -r '.size_bytes')
    if [[ "$ts" < "$cutoff" ]]; then
      local f="$archive_root/${id}.tar.gz"
      if $dry_run; then
        echo "[dry] would delete: $f (${size}B)"
      else
        rm -f "$f"
        removed=$((removed + 1)); freed=$((freed + size))
      fi
    else
      echo "$line" >> "$tmp_index"
    fi
  done < "$index"

  if ! $dry_run; then
    mv "$tmp_index" "$index"
    date +"%s" > "$last_prune"
    if [[ "$removed" -gt 0 ]]; then
      echo "📦 archive ${removed}건 정리 (~$((freed/1024))KB 회수)"
    fi
  else
    rm -f "$tmp_index"
  fi
  return 0
}

# 독립 prune (v1.2.17 · wt-clean 밖 — launchd 일 1회용): 기간 prune + 0B tar + tar 없는 INDEX 행
# 지우는 것: 기간 지난 보관본(기존 prune) · 크기 0 인 *.tar/*.tar.gz · 가리키는 tar 가 없는 INDEX 행
# 안 지우는 것: INDEX 에 없는 tar(크기 > 0)
# args: $1=retention days, $2=dry_run(true|false)
baton_archive_prune_standalone() {
  local retention="${1:-30}" dry_run="${2:-false}"
  command -v jq >/dev/null || { echo "❌ jq required" >&2; return 2; }
  baton_archive_prune "$retention" "$dry_run"
  local archive_root index f empty=0
  archive_root=$(baton_archive_dir)
  index=$(baton_archive_index)
  [[ -d "$archive_root" ]] || { echo "(archive 폴더 없음)"; return 0; }

  for f in "$archive_root"/*.tar "$archive_root"/*.tar.gz; do
    [[ -f "$f" && ! -s "$f" ]] || continue
    if $dry_run; then echo "[dry] would delete empty: $f"; else rm -f "$f"; fi
    empty=$((empty + 1))
  done

  local orphan=0 kept=0 tmp_index line id
  if [[ -s "$index" ]]; then
    tmp_index=$(mktemp)
    while IFS= read -r line; do
      id=$(jq -r '.id // empty' <<< "$line" 2>/dev/null) || id=""
      if [[ -n "$id" && -s "$archive_root/${id}.tar.gz" ]]; then
        echo "$line" >> "$tmp_index"; kept=$((kept + 1))
      else
        orphan=$((orphan + 1))
      fi
    done < "$index"
    if $dry_run; then rm -f "$tmp_index"; else mv "$tmp_index" "$index"; chmod 600 "$index"; fi
  fi
  echo "📦 standalone prune: 빈 tar ${empty}건 · 고아 INDEX 행 ${orphan}건 정리 · 남은 행 ${kept}건$($dry_run && echo ' (dry-run)')"
}

# Lazy prune (7일 경과 시)
baton_archive_lazy_prune() {
  local interval="${1:-7}"
  local archive_root
  archive_root=$(baton_archive_dir) 2>/dev/null || return 0
  [[ -d "$archive_root" ]] || return 0
  local last_prune="$archive_root/.last_prune"
  if [[ ! -f "$last_prune" ]]; then
    date +"%s" > "$last_prune"
    return
  fi
  local last_ts now_ts diff
  last_ts=$(cat "$last_prune")
  now_ts=$(date +"%s")
  diff=$(( (now_ts - last_ts) / 86400 ))
  if [[ "$diff" -ge "$interval" ]]; then
    baton_archive_prune 30 false
  fi
}
