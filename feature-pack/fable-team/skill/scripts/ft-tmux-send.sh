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
#
# ★--dispatch 는 «발주는 절대 막지 않는다» 는 뜻이다★ (2026-09-01 회귀 대응).
# 여기는 «발주» 경로다. ft-mbox.sh 의 발신 가드는 «보고» 채널을 겨냥한 것인데, 이 shim 이
# 본문을 같은 send 로 위임하는 바람에 발주까지 걸렸다 — BLOCKED(exit 3) 면 큐에도 안 들어가고
# doorbell 도 안 울려 ★좌석 창에 아무것도 안 뜬 채 조용히 사라진다★. 자율 루프가 통째로
# 멈춘 원인이 이것이었다.
#
# ★길이(700자)는 더 이상 이 면제의 이유가 아니다★ (2026-09-05, B1).
#   BODY_TOO_LONG 자체가 사라졌다 — 길이는 이제 발신 차단이 아니라 «수신 절단» 기준이고,
#   긴 발주 본문은 누구에게나 그냥 통과한다. 그러니 «발주는 700자를 넘으므로 면제가 필요하다»
#   는 근거는 폐기한다.
# ★그런데도 --dispatch 를 유지하는 이유는 «남은 세 가드» 다★:
#   · FANOUT   — 발주는 여러 좌석에 «같은 본문»을 연속 주입하는 것이 정상 동작이다.
#                보고 채널이라면 뿌리기지만 발주에선 그게 일이다.
#   · RATE     — 라운드 시작 때 좌석 수만큼의 발주가 60초 안에 몰린다(정상 버스트).
#   · RESEND   — 같은 발주를 좌석 A·B 에 거푸 넣는 것이 pending 중복으로 잡힌다.
#   셋 다 «보고 홍수»를 막으려는 것이고, 발주에 걸리면 그 좌석은 일을 못 받는다.
# 규율(짧게 쓰기)은 사람과 문서가 지킨다 — ★가드가 발주를 삼키게 두지 않는다★.
MBOX="$BINDIR/ft-mbox.sh"
if [ "$NOTIFY" = 0 ]; then
  exec bash "$MBOX" send "$SESS" "$FROM" "$BODY" --no-notify --dispatch
else
  exec bash "$MBOX" send "$SESS" "$FROM" "$BODY" --dispatch
fi
