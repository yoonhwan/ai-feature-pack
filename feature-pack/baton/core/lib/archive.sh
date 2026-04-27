#!/usr/bin/env bash
# baton lib/archive.sh — 워크트리 아카이브 (프로젝트 내부 .baton/archive/, git-tracked)
# da 권고 적용: 프로젝트 내부 위치 + tar -h dereference + chmod 600 + tags 필드

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

  # 머지 여부
  local merged_to_main=false merged_pr="null"
  for mb in main master; do
    if git -C "$wt_path" merge-base --is-ancestor HEAD "$mb" 2>/dev/null; then
      merged_to_main=true; break
    fi
  done

  # 보관 대상
  local items=()
  for f in .env .env.local .env.worktree .claude .omc .worktree-info.json; do
    [[ -e "$wt_path/$f" ]] && items+=("$f")
  done
  [[ -d "$wt_path/.baton" ]] && items+=(".baton")

  # 미머지 commit diff
  local diff_file=""
  if ! $merged_to_main; then
    diff_file="$wt_path/.unmerged-changes.patch"
    git -C "$wt_path" log main..HEAD --pretty=fuller --patch > "$diff_file" 2>/dev/null || true
    [[ -s "$diff_file" ]] && items+=(".unmerged-changes.patch")
  fi

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "⚠️  no items to archive" >&2
    return 1
  fi

  # tar -h: symlink dereference (da 권고)
  tar czhf "$archive_file" -C "$wt_path" "${items[@]}" 2>/dev/null
  chmod 600 "$archive_file"  # da 권고: archive 권한 제한
  [[ -n "$diff_file" && -f "$diff_file" ]] && rm -f "$diff_file"

  local size archived_at commits files tags_json
  size=$(stat -f%z "$archive_file" 2>/dev/null || stat -c%s "$archive_file")
  archived_at=$(date +"%Y-%m-%dT%H:%M:%S%z")
  commits=$(git -C "$wt_path" log main..HEAD --pretty='%H' 2>/dev/null | head -20 | jq -R . | jq -s . 2>/dev/null || echo '[]')
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
    '{id:$id, branch:$branch, phase:$phase, archived_at:$archived_at, worktree:$worktree, commits:$commits, size_bytes:$size_bytes, merged_to_main:$merged_to_main, merged_pr:$merged_pr, files:$files, tags:$tags}' \
    >> "$index"

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
      echo "📦 archive $removed건 정리 (~$((freed/1024))KB 회수)"
    fi
  else
    rm -f "$tmp_index"
  fi
  return 0
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
