#!/usr/bin/env bash
# baton lib/core.sh — 명령 디스패처 + 옵션 B 가드 + 워크트리 lifecycle

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

. "$BATON_HOME/lib/version.sh"
. "$BATON_HOME/lib/ports.sh"
. "$BATON_HOME/lib/handoff.sh"
. "$BATON_HOME/lib/archive.sh"
. "$BATON_HOME/lib/archive_search.sh"
. "$BATON_HOME/lib/harnesses.sh"
. "$BATON_HOME/lib/verify.sh"

# === 프로젝트 root 찾기 — main worktree 항상 반환 ===
# linked worktree에서 호출해도 main worktree 경로 반환 (archive 위치 일관성).
baton_project_root() {
  # 1순위: git worktree list --porcelain 첫 entry = main worktree
  local main_root
  main_root=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2; exit}')
  if [[ -n "$main_root" && -d "$main_root" ]]; then
    echo "$main_root"
    return
  fi
  # fallback: 부모 방향으로 .baton/config.json 또는 .git 찾기 (git 환경 외)
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -f "$d/.baton/config.json" ]] && { echo "$d"; return; }
    [[ -d "$d/.git" || -f "$d/.git" ]] && { echo "$d"; return; }
    d=$(dirname "$d")
  done
  echo "$PWD"
}

# 워크트리에서 호출되면 그 워크트리 root, main이면 project root
baton_active_root() {
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -d "$d/.baton/handoff" ]] && { echo "$d"; return; }
    d=$(dirname "$d")
  done
  baton_project_root
}

# === 프로젝트 .baton/ 초기화 ===
baton_init_project() {
  local root="${1:-$(baton_project_root)}"
  mkdir -p "$root/.baton/archive"
  if [[ ! -f "$root/.baton/config.json" ]]; then
    local proj
    proj=$(basename "$root")
    sed "s|{{PROJECT_NAME}}|$proj|g" \
      "$BATON_HOME/templates/config.json.template" > "$root/.baton/config.json"
    echo "✓ .baton/config.json 생성"
  fi
  if [[ ! -f "$root/.baton/version.lock" ]]; then
    baton_write_version_lock "$root/.baton/version.lock"
    echo "✓ .baton/version.lock 생성"
  fi
}

# === /baton:plan ===
baton_cmd_plan() {
  baton_guard_main_root plan || return 1
  local phase_id="${1:-}"
  local root
  root=$(baton_active_root)

  # phase.json 없으면 wt-create 안 거치고 워크트리 진입한 케이스 — stub 생성
  if [[ ! -f "$root/.baton/phase.json" ]]; then
    if [[ -z "$phase_id" ]]; then
      echo "사용법: /baton:plan <phase-id> [title]"
      echo "  (phase.json 미존재. /baton:wt-create 안 거쳤다면 phase-id 필수)"
      return 1
    fi
    local title="${2:-$phase_id}"
    baton_init_phase_json "$root/.baton/phase.json" "$phase_id" "$title"
    [[ ! -d "$root/.baton/handoff" ]] && baton_init_handoff "$root/.baton/handoff" "$phase_id" "$title" \
      "$(git -C "$root" branch --show-current 2>/dev/null || echo unknown)" "$root" \
      "${BATON_AGENT:-claude-code}"
    echo "✓ phase.json + 4-template 생성: $phase_id"
  else
    # 이미 활성 phase — 그대로 통과
    local existing
    existing=$(jq -r '.phase_id' "$root/.baton/phase.json" 2>/dev/null)
    echo "📌 활성 phase: $existing (그대로 사용)"
  fi

  echo

  # PLAN.md 상태로 분기
  local plan_md="$root/.baton/handoff/PLAN.md"
  local has_real_plan=false
  if [[ -f "$plan_md" ]]; then
    # stub은 "Plan v0 (stub)" 만 있고 실제 내용 없음
    if grep -qE '^## .* — Plan v[1-9]' "$plan_md" 2>/dev/null; then
      has_real_plan=true
    fi
  fi

  if $has_real_plan; then
    echo "✓ PLAN.md 에 이미 작성된 plan 있음:"
    grep -E '^## ' "$plan_md" | head -5 | sed 's/^/    /'
    echo
    echo "다음 plan 추가 작성하려면 외부 하네스 다시 호출:"
  else
    echo "📝 PLAN.md 비어 있음 (stub). 외부 하네스로 채우세요:"
  fi
  echo
  baton_plan_recommend "$root/.baton/config.json" || true
  echo
}

# === /baton:wt-create ===
baton_cmd_wt_create() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "사용법: /baton:wt-create <name>"
    return 1
  fi
  local root
  root=$(baton_project_root)
  baton_init_project "$root"
  local branch="feat/$name"
  local wt_dir="$root/.worktrees/$name"
  if [[ -d "$wt_dir" ]]; then
    echo "❌ 이미 존재: $wt_dir" >&2
    return 1
  fi
  local idx
  idx=$(baton_next_worktree_index "$root")
  if git -C "$root" rev-parse --verify "$branch" >/dev/null 2>&1; then
    git -C "$root" worktree add "$wt_dir" "$branch"
  else
    git -C "$root" worktree add -b "$branch" "$wt_dir"
  fi
  local now
  now=$(date +"%Y-%m-%d")
  cat > "$wt_dir/.worktree-info.json" <<EOF
{
  "branch": "$branch",
  "created_at": "$now",
  "purpose": "$name",
  "index": $idx
}
EOF
  mkdir -p "$wt_dir/.baton/handoff"
  ln -sf "$root/.baton/config.json" "$wt_dir/.baton/config.json"
  ln -sf "$root/.baton/version.lock" "$wt_dir/.baton/version.lock"
  ln -sf "$root/.baton/archive" "$wt_dir/.baton/archive"

  # 심링
  local cfg="$root/.baton/config.json"
  local links
  links=$(jq -r '.shared_links[]?' "$cfg" 2>/dev/null)
  for l in $links; do
    if [[ -e "$root/$l" && ! -e "$wt_dir/$l" ]]; then
      ln -s "$root/$l" "$wt_dir/$l"
    fi
  done

  # 포트
  baton_write_worktree_env "$wt_dir" "$idx" "$cfg"

  # phase.json 이전 또는 stub
  if [[ -f "$root/.baton/phase.json" ]]; then
    mv "$root/.baton/phase.json" "$wt_dir/.baton/phase.json"
    [[ -d "$root/.baton/handoff" ]] && {
      cp -r "$root/.baton/handoff/." "$wt_dir/.baton/handoff/"
      rm -rf "$root/.baton/handoff"
    }
  else
    baton_init_phase_json "$wt_dir/.baton/phase.json" "$name" "$name" "$branch" ".worktrees/$name"
    baton_init_handoff "$wt_dir/.baton/handoff" "$name" "$name" "$branch" \
      ".worktrees/$name" "${BATON_AGENT:-claude-code}"
  fi

  # gitignore 추가
  cat "$BATON_HOME/templates/.gitignore.template" > "$wt_dir/.baton/.gitignore"

  echo "✓ 워크트리 생성: $wt_dir"
  echo "  Branch: $branch"
  echo "  Index: $idx"
  echo "  Ports:"
  grep _PORT= "$wt_dir/.env.worktree" | sed 's/^/    /'
  echo
  echo "다음: cd $wt_dir"
  echo "       그 후 작업 시작 (예: /oh-my-claudecode:autopilot, codex exec)"
}

# === /baton:save ===
baton_cmd_save() {
  baton_guard_main_root save || return 1
  local root
  root=$(baton_active_root)
  local current="$root/.baton/handoff/CURRENT.md"
  [[ -f "$current" ]] || { echo "❌ CURRENT.md 없음. /baton:wt-create 또는 /baton:plan 먼저"; return 1; }
  baton_current_set_status paused "$current"
  echo "✓ status → paused, last_updated 갱신"
  echo
  echo "에이전트는 다음을 갱신해야 합니다:"
  echo "  - JOURNAL.md 의 마지막 turn ACTIONS/TODO 채우기"
  echo "  - CURRENT.md 의 ⚠️ 블로커 / 📌 핵심 결정 / 🔗 핵심 파일 갱신"
  echo "  - NEXT.md 1페이지 갱신 (다음 세션 첫 컨텍스트)"
}

# === /baton:resume ===
baton_cmd_resume() {
  baton_guard_main_root resume || return 1
  local root
  root=$(baton_active_root)
  baton_handoff_resume "$root/.baton/handoff/NEXT.md"
}

# === /baton:status ===
baton_cmd_status() {
  local root
  root=$(baton_active_root)
  echo "─────────────────────────────────────────"
  echo "📊 baton status — $root"
  echo "─────────────────────────────────────────"
  if [[ -f "$root/.baton/phase.json" ]] && command -v jq >/dev/null; then
    jq -r '"  Phase: \(.phase_id) — \(.title)\n  Branch: \(.branch)\n  Worktree: \(.worktree)\n  Started: \(.started_at)\n  Sessions: \(.sessions | length)"' "$root/.baton/phase.json"
  else
    echo "  (활성 phase.json 없음)"
  fi
  if [[ -f "$root/.baton/handoff/CURRENT.md" ]]; then
    echo
    local s a u h
    s=$(baton_current_field status "$root/.baton/handoff/CURRENT.md")
    a=$(baton_current_field agent "$root/.baton/handoff/CURRENT.md")
    u=$(baton_current_field last_updated "$root/.baton/handoff/CURRENT.md")
    h=$(baton_current_field last_harness "$root/.baton/handoff/CURRENT.md")
    echo "  Handoff: $s (by $a, $u)"
    echo "  Last harness: $h"
  fi
  # main root에서 호출되면 활성 워크트리 목록
  if baton_is_main_root "$PWD"; then
    echo
    echo "  활성 워크트리:"
    if [[ -d "$root/.worktrees" ]]; then
      for wt in "$root/.worktrees"/*; do
        [[ -d "$wt" ]] || continue
        local wb
        wb=$(git -C "$wt" branch --show-current 2>/dev/null)
        echo "    - $(basename "$wt") ($wb)"
      done
    else
      echo "    (없음)"
    fi
  fi
  baton_archive_lazy_prune 7 || true
}

# === /baton:wt-clean ===
baton_cmd_wt_clean() {
  local target="${1:-}"
  local merged_only=false
  if [[ "$target" == "--merged" ]]; then
    merged_only=true; target=""
  fi
  local root
  root=$(baton_project_root)
  if $merged_only; then
    for wt in "$root/.worktrees"/*; do
      [[ -d "$wt" ]] || continue
      for mb in main master; do
        if git -C "$wt" merge-base --is-ancestor HEAD "$mb" 2>/dev/null; then
          baton_wt_clean_one "$wt" "$root"; break
        fi
      done
    done
    return
  fi
  [[ -z "$target" ]] && target="$PWD"
  # 인자 정규화: 절대경로 아니면 .worktrees/<name>/ 으로 자동 매핑
  if [[ "$target" != /* ]]; then
    if [[ "$target" == .worktrees/* ]]; then
      target="$root/$target"
    elif [[ -d "$root/.worktrees/$target" ]]; then
      target="$root/.worktrees/$target"
    fi
  fi
  # cwd 무효화 방지: archive_create 호출 전에 main worktree로 이동
  cd "$root"
  baton_wt_clean_one "$target" "$root"
  baton_archive_prune 30 false
}

baton_wt_clean_one() {
  local wt_path=$1 root=$2
  # 안전장치: 호출 시점에 cwd 가 wt_path 안이면 root 로 탈출 (archive 생성 시 git 명령 안전)
  case "$PWD" in
    "$wt_path"|"$wt_path"/*) cd "$root" ;;
  esac
  local branch
  branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "unknown")
  echo "─────────────────────────────────────────"
  echo "🗄️  워크트리 정리 — Archive 자동 보관"
  echo "─────────────────────────────────────────"
  echo "대상: $wt_path"
  echo "브랜치: $branch"
  local merged_status="✗ 미머지"
  for mb in main master; do
    if git -C "$wt_path" merge-base --is-ancestor HEAD "$mb" 2>/dev/null; then
      merged_status="✓ $mb 머지됨"; break
    fi
  done
  echo "머지 상태: $merged_status"
  echo
  echo "📦 아카이브 생성 중..."
  local archive_file
  archive_file=$(baton_archive_create "$wt_path" "")
  echo "📍 위치: $archive_file"
  echo "⏳ 보관: 30일"
  echo "🔍 검색: /baton:archive search [keyword]"
  echo
  echo "🗑️  워크트리 삭제..."
  git -C "$root" worktree remove --force "$wt_path"
  echo "✓ 정리 완료"
}

# === /baton:finish ===
baton_cmd_finish() {
  baton_guard_main_root finish || return 1
  local root
  root=$(baton_active_root)
  local current="$root/.baton/handoff/CURRENT.md"
  [[ -f "$current" ]] && baton_current_set_status done "$current"
  echo "✓ status → done"
  echo
  echo "다음 단계 (사용자가 직접):"
  echo "  1. verify (예: /oh-my-claudecode:verify)"
  echo "  2. PR 생성·머지: gh pr create / gh pr merge"
  echo "  3. /baton:wt-clean  # archive 자동 보관"
}

# === /baton:hotfix-mode ===
baton_cmd_hotfix_mode() {
  if ! baton_is_main_root "$PWD"; then
    echo "❌ hotfix-mode는 main/master 브랜치 root에서만"
    return 1
  fi
  echo "─────────────────────────────────────────"
  echo "🚨 hotfix-mode 활성화"
  echo "─────────────────────────────────────────"
  echo "main에서 직접 작업 모드입니다. baton 메모리 비활성."
  echo "종료 시: /baton:hotfix-mode finish (archive에 tag:hotfix 만 남김)"
  if [[ "${1:-}" == "finish" ]]; then
    local root
    root=$(baton_project_root)
    baton_archive_init
    # 가벼운 archive: 최근 commit + diff 만
    local ts
    ts=$(date +"%Y%m%d_%H%M")
    local archive_file
    archive_file="$(baton_archive_dir)/hotfix_${ts}.tar.gz"
    # HEAD~5 안전화: commit 수가 5 미만이면 첫 commit까지만
    local commit_count base
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo 1)
    if [[ "$commit_count" -le 1 ]]; then
      base=$(git rev-list --max-parents=0 HEAD 2>/dev/null || echo HEAD)
      git diff "$base..HEAD" > /tmp/baton-hotfix-${ts}.patch 2>/dev/null || true
    else
      local n=$((commit_count > 5 ? 5 : commit_count - 1))
      git diff "HEAD~${n}..HEAD" > /tmp/baton-hotfix-${ts}.patch 2>/dev/null || true
    fi
    tar czhf "$archive_file" -C /tmp "baton-hotfix-${ts}.patch" 2>/dev/null || true
    chmod 600 "$archive_file"
    rm -f /tmp/baton-hotfix-${ts}.patch
    echo "✓ hotfix archive: $archive_file (tag:hotfix)"
    # INDEX append
    jq -nc \
      --arg id "hotfix_${ts}" \
      --arg ts "$(date +"%Y-%m-%dT%H:%M:%S%z")" \
      '{id:$id, branch:"main", phase:"hotfix", archived_at:$ts, worktree:".", commits:[], size_bytes:0, merged_to_main:true, tags:["hotfix"]}' \
      >> "$(baton_archive_index)"
  fi
}

# === /baton:help ===
baton_cmd_help() {
  cat <<'HELP'
─────────────────────────────────────────────────────────────────
baton — Universal Standard Workflow
─────────────────────────────────────────────────────────────────

핵심 원칙:
  - 워크트리 + 아카이브 + 작업 메모리 표준화
  - 작업의 앞/뒤만 baton, 중간은 외부 하네스 (superpowers/OMC/...)
  - main/master root에서는 baton 거부 (옵션 B strict)

라이프사이클 시퀀스:
  사용자        baton             외부 하네스           Git
    │             │                   │                  │
    │ /plan ID    │                   │                  │
    ├────────────▶│ phase.json + 4-template            │
    │             │                                      │
    │ /wt-create  │                                      │
    ├────────────▶│ 워크트리 + 포트 + 심링 + 메모리 이전 │
    │             ├─────────────────────────────────────▶│
    │                                                    │
    │ (작업: /oh-my-claudecode:autopilot, codex 등)      │
    │             │                   │                  │
    │ Stop / Compact / UserPrompt                        │
    │             │ ◀── dump 지시 ───┤                  │
    │             │ JOURNAL/CURRENT/NEXT 갱신           │
    │             │                                      │
    │ [새 세션] "이어서"                                  │
    ├────────────▶│ resume → NEXT.md 출력               │
    │                                                    │
    │ /finish     │                                      │
    ├────────────▶│ status=done                         │
    │ /wt-clean   │                                      │
    ├────────────▶│ archive 보관 + 워크트리 삭제        │
    │             ├─────────────────────────────────────▶│

명령 (17개):
  /baton:plan <id>              phase.json + 4-template (워크트리에서만)
  /baton:wt-create <name>       워크트리 생성
  /baton:save                   핸드오프 dump
  /baton:resume                 NEXT.md 출력
  /baton:finish                 페이즈 완료
  /baton:wt-clean [path?] [--merged]  정리 + archive
  /baton:status                 상태
  /baton:help                   이 화면
  /baton:install                인터뷰형 설치
  /baton:doctor                 진단
  /baton:upgrade                새 버전 설치
  /baton:hotfix-mode [finish]   main 직접 작업 모드
  /baton:archive list [--days N] [--global]
  /baton:archive search <q> [--global]
  /baton:archive show <id>
  /baton:archive extract <id>
  /baton:archive close <id>
  /baton:archive prune [--dry-run] [--days N]

키워드 트리거:
  "이어서" / "진행" / "go" / "continue" / "next"  →  resume

옵션 B (main strict):
  main/master root에서 plan/save/resume/finish 거부.
  허용: wt-create, status, archive list/search, hotfix-mode, install/doctor/upgrade.

자동 정책:
  - SessionStart: paused 알림 + 환경 체크 + lazy prune (7일)
  - UserPromptSubmit: INTENTS → JOURNAL.md
  - PostToolUse: 하네스 사용 자동 추출 + verification
  - PreCompact / SessionEnd: 백업 dump
  - wt-clean 시 archive 자동 + 30일 prune
─────────────────────────────────────────────────────────────────
HELP
}

# === /baton:doctor ===
baton_cmd_doctor() {
  local root
  root=$(baton_project_root)
  echo "─────────────────────────────────────────"
  echo "🩺 baton doctor"
  echo "─────────────────────────────────────────"
  echo "  baton version: $(baton_version)"
  echo "  spec version:  $(baton_spec_version)"
  echo "  HOME:          $BATON_HOME"
  echo "  project root:  $root"
  echo "  archive dir:   $(baton_archive_dir 2>/dev/null || echo "-")"
  echo
  if command -v jq >/dev/null; then
    echo "  ✓ jq"
  else
    echo "  ❌ jq missing — brew install jq (REQUIRED)"
  fi
  if [[ -f "$root/.baton/version.lock" ]]; then
    if baton_check_compat "$root/.baton/version.lock"; then
      echo "  ✓ 호환성 OK"
    fi
  else
    echo "  (version.lock 없음 — 신규 프로젝트?)"
  fi
  if baton_is_main_root "$PWD"; then
    echo "  ⚠️  현재 main/master root — phase 작업 비활성 (옵션 B)"
  fi
  echo
  baton_archive_lazy_prune 7 || true
}
