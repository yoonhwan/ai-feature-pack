#!/usr/bin/env bash
# baton lib/handoff.sh — 4-template 핸드오프 (PLAN/JOURNAL/CURRENT/NEXT)

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

baton_iso_now() { date +"%Y-%m-%dT%H:%M:%S%z"; }
baton_human_now() { date +"%Y-%m-%d %H:%M"; }
baton_session_id() { date +"%Y-%m-%d_%H%M"; }

# 4-template 일괄 초기화
baton_init_handoff() {
  local handoff_dir=$1
  local phase_id=$2
  local title="${3:-$phase_id}"
  local branch="${4:-$(git branch --show-current 2>/dev/null || echo unknown)}"
  local worktree="${5:-.}"
  local agent="${6:-claude-code}"
  mkdir -p "$handoff_dir"
  local sid
  sid=$(baton_session_id)
  local now
  now=$(baton_iso_now)
  local human
  human=$(baton_human_now)

  for tpl in PLAN JOURNAL CURRENT NEXT; do
    sed -e "s|{{SESSION_ID}}|$sid|g" \
        -e "s|{{PHASE_ID}}|$phase_id|g" \
        -e "s|{{PHASE_TITLE}}|$title|g" \
        -e "s|{{BRANCH}}|$branch|g" \
        -e "s|{{WORKTREE}}|$worktree|g" \
        -e "s|{{AGENT}}|$agent|g" \
        -e "s|{{STARTED_AT}}|$now|g" \
        -e "s|{{STARTED_AT_HUMAN}}|$human|g" \
        -e "s|{{LAST_HARNESS}}|null|g" \
        "$BATON_HOME/templates/${tpl}.md.template" > "$handoff_dir/${tpl}.md"
  done
}

# phase.json 초기화
baton_init_phase_json() {
  local target=$1
  local phase_id=$2
  local title="${3:-$phase_id}"
  local branch="${4:-$(git branch --show-current 2>/dev/null || echo unknown)}"
  local worktree="${5:-.}"
  local ports_json="${6:-{\}}"
  local now
  now=$(baton_iso_now)
  mkdir -p "$(dirname "$target")"
  sed -e "s|{{PHASE_ID}}|$phase_id|g" \
      -e "s|{{PHASE_TITLE}}|$title|g" \
      -e "s|{{BRANCH}}|$branch|g" \
      -e "s|{{WORKTREE}}|$worktree|g" \
      -e "s|{{PORTS_JSON}}|$ports_json|g" \
      -e "s|{{STARTED_AT}}|$now|g" \
      "$BATON_HOME/templates/phase.json.template" > "$target"
}

# CURRENT.md frontmatter 필드 읽기
baton_current_field() {
  local field=$1
  local current="${2:-./.baton/handoff/CURRENT.md}"
  [[ -f "$current" ]] || return 1
  awk -v f="$field" '
    /^---$/ { fm = !fm; next }
    fm && $0 ~ "^"f":" { sub("^"f":[[:space:]]*", ""); print; exit }
  ' "$current"
}

# CURRENT.md frontmatter 필드 갱신 (status, last_updated, last_harness)
baton_current_set() {
  local field=$1 value=$2
  local current="${3:-./.baton/handoff/CURRENT.md}"
  [[ -f "$current" ]] || return 1
  local tmp
  tmp=$(mktemp)
  awk -v f="$field" -v v="$value" '
    /^---$/ { fm = !fm; print; next }
    fm && $0 ~ "^"f":" { print f": "v; next }
    { print }
  ' "$current" > "$tmp"
  mv "$tmp" "$current"
}

# CURRENT.md status + last_updated 동시 갱신
baton_current_set_status() {
  local status=$1
  local current="${2:-./.baton/handoff/CURRENT.md}"
  baton_current_set status "$status" "$current"
  baton_current_set last_updated "$(baton_iso_now)" "$current"
}

# JOURNAL.md에 INTENT (사용자 입력) append (UserPromptSubmit 훅이 호출)
baton_journal_append_intent() {
  local intent=$1
  local journal="${2:-./.baton/handoff/JOURNAL.md}"
  [[ -f "$journal" ]] || return 1
  local human
  human=$(baton_human_now)
  cat >> "$journal" <<EOF

## $human — Turn $(baton_journal_next_turn "$journal")
- **INTENT**: $intent
- **HARNESS**: -
- **ACTIONS**: -
- **TODO**: -
EOF
}

# JOURNAL.md에 HARNESS 사용 추가 (PostToolUse 훅이 호출)
baton_journal_set_last_harness() {
  local harness=$1
  local journal="${2:-./.baton/handoff/JOURNAL.md}"
  [[ -f "$journal" ]] || return 1
  # 마지막 Turn의 HARNESS: - 라인을 갱신
  local tmp
  tmp=$(mktemp)
  awk -v h="$harness" '
    /^- \*\*HARNESS\*\*: -$/ { last=NR }
    { lines[NR]=$0 }
    END {
      for(i=1;i<=NR;i++) {
        if (i==last) print "- **HARNESS**: " h
        else print lines[i]
      }
    }
  ' "$journal" > "$tmp"
  mv "$tmp" "$journal"
  # CURRENT.md last_harness 도 갱신
  baton_current_set last_harness "$harness" "$(dirname "$journal")/CURRENT.md" 2>/dev/null || true
}

baton_journal_next_turn() {
  local journal=$1
  [[ -f "$journal" ]] || { echo 1; return; }
  local n
  n=$(grep -cE '^## .* — Turn ' "$journal" 2>/dev/null || echo 0)
  echo $((n + 1))
}

# /baton:resume — NEXT.md 출력
baton_handoff_resume() {
  local next="${1:-./.baton/handoff/NEXT.md}"
  if [[ ! -f "$next" ]]; then
    echo "📌 일시정지된 핸드오프 없음 (NEXT.md 부재)"
    return 1
  fi
  echo "─────────────────────────────────────────"
  echo "📌 핸드오프 재개"
  echo "─────────────────────────────────────────"
  cat "$next"
  echo
  echo "─────────────────────────────────────────"
  echo "참고: PLAN.md 와 JOURNAL.md 도 확인하세요."
  return 0
}

# SessionStart 알림 (자동 주입 X)
baton_handoff_alert() {
  local current="${1:-./.baton/handoff/CURRENT.md}"
  [[ -f "$current" ]] || return 0
  local status phase branch agent updated last_harness
  status=$(baton_current_field status "$current")
  [[ "$status" != "paused" ]] && return 0
  phase=$(baton_current_field phase "$current")
  branch=$(baton_current_field branch "$current")
  agent=$(baton_current_field agent "$current")
  updated=$(baton_current_field last_updated "$current")
  last_harness=$(baton_current_field last_harness "$current")
  cat <<EOF
─────────────────────────────────────────
📌 일시정지된 페이즈가 있어요
  Phase: $phase (paused, by $agent)
  Branch: $branch
  Last updated: $updated
  Last harness: $last_harness

이어서: "이어서" / "진행" / "go" / "continue" / "next"
다른 작업: 무시하고 새 요청 입력
─────────────────────────────────────────
EOF
}
