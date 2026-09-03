#!/bin/bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: tools/comm-canonical/ · 드리프트 확인: tools/comm-canonical/check-drift.sh
# Claude 좌석의 tmux 이름을 세션 JSONL usage에 결속해 ctx 사용률을 계산한다.

set -uo pipefail

SESSION="${1:?session name}"
CLAUDE_ROOT="${FT_CTX_CLAUDE_ROOT:-$HOME/.claude}"
SESSIONS_DIR="$CLAUDE_ROOT/sessions"
WINDOW_TOKENS="${FT_CTX_CLAUDE_WINDOW_TOKENS:-1000000}"
BEST_FILE=""
BEST_UPDATED="0"

for FILE in "$SESSIONS_DIR"/*.json; do
  [ -f "$FILE" ] || continue
  LC_ALL=C grep -qF "\"tmux\":\"${SESSION}:" "$FILE" || continue
  PID=$(basename "$FILE" .json)
  kill -0 "$PID" 2>/dev/null || continue
  UPDATED=$(jq -r '.updatedAt // 0' "$FILE" 2>/dev/null || echo 0)
  if [ "$UPDATED" -gt "$BEST_UPDATED" ]; then
    BEST_UPDATED="$UPDATED"
    BEST_FILE="$FILE"
  fi
done

[ -n "$BEST_FILE" ] || exit 1
SESSION_ID=$(jq -r '.sessionId // empty' "$BEST_FILE")
CWD=$(jq -r '.cwd // empty' "$BEST_FILE")
[ -n "$SESSION_ID" ] && [ -n "$CWD" ] || exit 1

CACHE="$CLAUDE_ROOT/hud/cache/statusline.${SESSION_ID}.txt"
if [ -f "$CACHE" ]; then
  TOKEN=$(LC_ALL=C grep -oE 'ctx:[^%]*[0-9]{1,3}%' "$CACHE" | tail -1 || true)
  if [ -n "$TOKEN" ]; then
    printf '%s\n' "$(printf '%s' "$TOKEN" | LC_ALL=C grep -oE '[0-9]{1,3}%$' | tr -d '%')"
    exit 0
  fi
fi

PROJECT_KEY=$(printf '%s' "$CWD" | tr '/.' '--')
PROJECT_DIR="$CLAUDE_ROOT/projects/$PROJECT_KEY"
TRANSCRIPT="$PROJECT_DIR/${SESSION_ID}.jsonl"
[ -f "$TRANSCRIPT" ] || exit 1
TOTAL=$(tail -600 "$TRANSCRIPT" \
  | jq -Rr 'fromjson? | select(.message.usage != null) | [(.message.usage.input_tokens // 0), (.message.usage.cache_creation_input_tokens // 0), (.message.usage.cache_read_input_tokens // 0)] | add' \
  | tail -1)
case "$TOTAL" in
  ''|*[!0-9]*) exit 1 ;;
esac

PCT=$(( (TOTAL * 100 + WINDOW_TOKENS / 2) / WINDOW_TOKENS ))
[ "$PCT" -le 100 ] || PCT=100
printf '%s\n' "$PCT"
