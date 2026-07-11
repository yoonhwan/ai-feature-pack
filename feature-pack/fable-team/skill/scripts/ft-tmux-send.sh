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

# 구분자는 순수 ASCII '->'. 유니코드 화살표(→)는 tmux pane/Claude TUI 렌더링 단계에서 U+FFFD로
# 손상돼(보낸 바이트는 정상이나 pane 저장 바이트가 깨짐, V3 재현 3/3) 도달검증이 영구 실패했다.
PREFIX="[$FROM->$SESS] #$MSGID"
LINE="$PREFIX $MSG"

# ── 1) HARD GATE: 대상 agent 프로세스 확인 ─────────────────
if ! ft_sess_alive "$SESS"; then
  echo "ft-tmux-send: HARD GATE 실패 — 대상 세션/프로세스 부재: $SESS" >&2
  exit 1
fi

# ── 2) 상태 판독: 옵션 모드일 때만 Escape, 미제출 잔류일 때만 C-u (COMM-GUIDE §2 Step2, M-1) ──
# 무조건 Escape는 busy 타겟의 진행 중 턴을 "Interrupted"로 중단시킨다(COMM-GUIDE 금지사항) →
# capture로 옵션모드/미제출을 판별해 필요한 키만 보낸다. 감지 실패 시 아무것도 안 보내고 본문 send(안전측).
# capture-pane 출력엔 TUI 박스문자·ANSI·잘린 멀티바이트 등 invalid UTF-8이 섞여, UTF-8 로케일
# grep은 입력을 binary로 판정해 스킵하거나 illegal byte sequence로 오판한다(V3) → LC_ALL=C grep -a로 바이트매치.
_cap="$(tmux capture-pane -p -t "$SESS" 2>/dev/null)"
if printf '%s\n' "$_cap" | LC_ALL=C grep -aq 'Enter to select'; then
  tmux send-keys -t "$SESS" Escape 2>/dev/null; sleep 0.2   # 옵션 모드 탈출
fi
if printf '%s\n' "$_cap" | LC_ALL=C grep -aqE '❯[[:space:]]+[^[:space:]]'; then
  tmux send-keys -t "$SESS" C-u 2>/dev/null; sleep 0.2      # 미제출 입력(❯ 텍스트) 클리어
fi

# ── 3) send-keys -l + sleep 0.3 + 별도 Enter ──────────────
tmux send-keys -t "$SESS" -l "$LINE" 2>/dev/null
sleep 0.3
tmux send-keys -t "$SESS" Enter 2>/dev/null

# ── 4) 도달 검증: ASCII msg-id(#$MSGID)로 매치, backoff 2->4->8 (총 ≤15s) ──
# 프리픽스 전체가 아니라 순수 ASCII인 #$MSGID(고유)만 확인한다 — pane 프리픽스 렌더링에
# 무관하게 견고. LC_ALL=C grep -a로 capture의 잔여 invalid UTF-8도 바이트매치.
for wait in 2 4 8; do
  sleep "$wait"
  if tmux capture-pane -p -t "$SESS" 2>/dev/null | LC_ALL=C grep -aqF "#$MSGID"; then
    echo "SENT $SESS #$MSGID"
    exit 0
  fi
done
echo "ft-tmux-send: 도달 검증 3회 실패 — $SESS #$MSGID" >&2
exit 1
