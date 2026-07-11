#!/bin/bash
# ft-tmux-send.sh — COMM-GUIDE §2 4단계 검증 송신 래퍼 (§1-3②)
# Usage: ft-tmux-send.sh <sess> --from <me> [--id <msg-id>] "<msg>"
# Exit: 0 도달 검증 통과 / 1 대상 부재·미제출·도달 검증 3회 실패
set +e
LIB="$(cd "$(dirname "$0")" && pwd)/ft-lib.sh"; . "$LIB"

SESS="$1"; shift
FROM="" MSGID="" MSG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="$2"; shift 2;;
    --id)   MSGID="$2"; shift 2;;
    *)      MSG="$1"; shift;;
  esac
done
[ -n "$SESS" ] && [ -n "$FROM" ] && [ -n "$MSG" ] || { echo "ft-tmux-send: <sess> --from <me> \"<msg>\" 필수" >&2; exit 1; }
[ -z "$MSGID" ] && MSGID="$(date +%s)-$(printf '%04x' $((RANDOM)))"

PREFIX="[$FROM→$SESS] #$MSGID"
LINE="$PREFIX $MSG"

# ── 1) HARD GATE: 대상 agent 프로세스 확인 ─────────────────
if ! ft_sess_alive "$SESS"; then
  echo "ft-tmux-send: HARD GATE 실패 — 대상 세션/프로세스 부재: $SESS" >&2
  exit 1
fi

# ── 2) 상태 판독: 옵션 모드 해제(Escape) + 미제출 입력 클리어(C-u) ──
tmux send-keys -t "$SESS" Escape 2>/dev/null; sleep 0.2
tmux send-keys -t "$SESS" C-u 2>/dev/null; sleep 0.2

# ── 3) send-keys -l + sleep 0.3 + 별도 Enter ──────────────
tmux send-keys -t "$SESS" -l "$LINE" 2>/dev/null
sleep 0.3
tmux send-keys -t "$SESS" Enter 2>/dev/null

# ── 4) 도달 검증: grep -F 정확 프리픽스, backoff 2→4→8 (총 ≤15s) ──
for wait in 2 4 8; do
  sleep "$wait"
  if tmux capture-pane -p -t "$SESS" 2>/dev/null | grep -qF "$PREFIX"; then
    echo "SENT $SESS #$MSGID"
    exit 0
  fi
done
echo "ft-tmux-send: 도달 검증 3회 실패 — $SESS #$MSGID" >&2
exit 1
