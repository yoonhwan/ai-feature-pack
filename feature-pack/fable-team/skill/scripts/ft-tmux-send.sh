#!/bin/bash
# ft-tmux-send.sh — 얇은 호환 shim: 본문을 파일 큐(ft-mbox.sh)로 위임 + doorbell (comm-filebased D-4).
# 도달검증 루프(구 Step4, sleep 2+4+8)는 전면 삭제 — 큐 기록이 전달 보장, doorbell은 지연 최적화(유실 non-fatal).
# Usage: ft-tmux-send.sh <sess> --from <me> [--id <op-id>] [--no-doorbell] "<msg>"
# Exit: ft-mbox.sh 그대로(큐잉 성공=0). 타겟 부재도 exit 0(doorbell=absent, fail-safe) — 늦게 뜨는 세션도 수신.
set +e
BINDIR="$(cd "$(dirname "$0")" && pwd)"
. "$BINDIR/ft-lib.sh"                        # ft_swap_guard(allowlist) 발동

SESS="$1"; shift
FROM="" OPID="" MSG="" NOTIFY=1
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="$2"; shift 2;;
    --id)   OPID="$2"; shift 2;;
    --no-doorbell) NOTIFY=0; shift;;
    *)      MSG="$1"; shift;;
  esac
done
[ -n "$SESS" ] && [ -n "$FROM" ] && [ -n "$MSG" ] || { echo "ft-tmux-send: <sess> --from <me> \"<msg>\" 필수" >&2; exit 1; }

# ⓪ allowlist 검증(py NAME_RE와 동일) — 세션명이 doorbell 명령에 삽입되므로 하드 거부.
for n in "$SESS" "$FROM"; do
  case "$n" in *[!A-Za-z0-9._#-]*|'') echo "BAD_SESSION_NAME $n" >&2; exit 1;; esac
done

# ① --id는 본문 op 태그로 강등 — 메시지 ID는 seq가 유일(PM ack 규약용 본문 태그).
BODY="$MSG"
[ -n "$OPID" ] && BODY="[op:$OPID] $MSG"

# ② ft-mbox.sh send 위임(--no-doorbell → --no-notify). 출력·exit(QUEUED … doorbell=…) 그대로 전파.
MBOX="$BINDIR/ft-mbox.sh"
if [ "$NOTIFY" = 0 ]; then
  exec bash "$MBOX" send "$SESS" "$FROM" "$BODY" --no-notify
else
  exec bash "$MBOX" send "$SESS" "$FROM" "$BODY"
fi
