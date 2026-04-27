#!/usr/bin/env bash
# baton user-prompt-submit hook
set -euo pipefail
BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"
[[ -d "$BATON_HOME" ]] || exit 0  # baton 미설치 시 silent skip

# shellcheck source=../../core/lib/core.sh
. "$BATON_HOME/lib/core.sh"

# ---------------------------------------------------------------------------
# stdin에서 사용자 입력 추출 (Claude Code — JSON payload)
# ---------------------------------------------------------------------------
_extract_user_message() {
  local raw="$1"
  # JSON이면 파싱, 평문이면 그대로
  if command -v jq &>/dev/null && echo "$raw" | jq -e . &>/dev/null 2>&1; then
    echo "$raw" | jq -r '.user_message // .prompt // empty'
  else
    echo "$raw"
  fi
}

# ---------------------------------------------------------------------------
# 현재 디렉토리에서 부모 방향으로 .baton/handoff/JOURNAL.md 탐색
# ---------------------------------------------------------------------------
_find_journal() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    local candidate="$dir/.baton/handoff/JOURNAL.md"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

_find_current_md() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    local candidate="$dir/.baton/handoff/CURRENT.md"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# ---------------------------------------------------------------------------
# JOURNAL.md의 마지막 Turn 번호 추출
# ---------------------------------------------------------------------------
_last_turn_number() {
  local journal="$1"
  grep -oE '^## .+ — Turn ([0-9]+)' "$journal" \
    | grep -oE '[0-9]+$' \
    | tail -1
}

# ---------------------------------------------------------------------------
# CURRENT.md frontmatter 필드 인라인 갱신
# ---------------------------------------------------------------------------
_update_frontmatter_field() {
  local file="$1" field="$2" value="$3"
  # frontmatter 내 해당 key 줄을 교체 (없으면 추가하지 않음)
  if grep -q "^${field}:" "$file"; then
    local tmp
    tmp="$(mktemp)"
    sed "s|^${field}:.*|${field}: ${value}|" "$file" > "$tmp"
    mv "$tmp" "$file"
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

# stdin 읽기 (타임아웃 0.5초 — hook은 빨라야 함)
raw_input=""
if read -t 0.5 -r raw_input 2>/dev/null; then
  :
else
  # stdin 없으면 silent skip
  exit 0
fi

user_msg="$(_extract_user_message "$raw_input")"
[[ -z "$user_msg" ]] && exit 0

# JOURNAL.md 탐색
journal=""
journal="$(_find_journal 2>/dev/null)" || exit 0

# Turn 번호 결정
last_turn="$(_last_turn_number "$journal" 2>/dev/null || echo "0")"
new_turn=$(( ${last_turn:-0} + 1 ))

# 타임스탬프
ts="$(date '+%Y-%m-%d %H:%M')"

# 입력 첫 200자로 INTENT 요약
intent="${user_msg:0:200}"
# 개행 제거 (단일 줄)
intent="${intent//$'\n'/ }"

# JOURNAL.md에 새 Turn 섹션 append
cat >> "$journal" << EOF

## ${ts} — Turn ${new_turn}
- **INTENT**: ${intent}
- **HARNESS**: -
- **ACTIONS**: -
- **TODO**: -

EOF

# CURRENT.md last_updated 갱신
current_md=""
if current_md="$(_find_current_md 2>/dev/null)"; then
  iso_ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
  _update_frontmatter_field "$current_md" "last_updated" "$iso_ts"
fi

# Claude에게 지시 주입 (stdout → 컨텍스트)
echo "[baton] 새 turn 시작. 응답 끝낼 때 .baton/handoff/JOURNAL.md 의 마지막 Turn 섹션에 ACTIONS/TODO 추가하세요."

exit 0
