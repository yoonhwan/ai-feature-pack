#!/bin/bash
# ft-tmux-poll.sh — 오케 수신 1줄 판정 (§1-3③)
# Usage: ft-tmux-poll.sh <slug> <sess> [--timeout S] [--consume]
# 출력(1줄): DONE <path> | MSG <내용> | NEEDS_INPUT <hil-id> | RUNNING | HANG
# capture는 상태 판독(grep -q) 전용 — capture 텍스트를 명령/지시로 재사용하지 않는다(§6).
set +e
LIB="$(cd "$(dirname "$0")" && pwd)/ft-lib.sh"; . "$LIB"

SLUG="$1"; SESS="$2"; shift 2 2>/dev/null
TIMEOUT=0; CONSUME=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2;;
    --consume) CONSUME=1; shift;;
    *) shift;;
  esac
done
[ -n "$SLUG" ] && [ -n "$SESS" ] || { echo "ft-tmux-poll: <slug> <sess> 필수" >&2; exit 1; }

ROOT="$(ft_resolve_root "")"
SIG="$(ft_feat_signals "$ROOT" "$SLUG")"
mkdir -p "$SIG/archive" 2>/dev/null

poll_once() {
  # ① done 센티널
  local done_f="$SIG/$SESS.done"
  if [ -f "$done_f" ]; then
    local path; path="$(head -1 "$done_f" 2>/dev/null)"
    printf 'DONE %s\n' "$path"
    if [ "$CONSUME" = "1" ]; then
      mv "$done_f" "$SIG/archive/$SESS.done.$(date +%s)" 2>/dev/null
    fi
    return 0
  fi
  # ② .msg 신규 append (seen 바이트 오프셋 추적)
  local msg_f="$SIG/$SESS.msg" seen_f="$SIG/.$SESS.msg.seen"
  if [ -f "$msg_f" ]; then
    local sz seen; sz="$(wc -c < "$msg_f" 2>/dev/null | tr -d ' ')"
    seen="$(cat "$seen_f" 2>/dev/null || echo 0)"
    if [ "${sz:-0}" -gt "${seen:-0}" ] 2>/dev/null; then
      local new; new="$(tail -c "+$((seen+1))" "$msg_f" 2>/dev/null | tail -1)"
      printf '%s' "$sz" > "$seen_f" 2>/dev/null
      printf 'MSG %s\n' "$new"
      return 0
    fi
  fi
  # ③ pending hil-* 중 sess 매치
  local h
  for h in "$SIG"/hil-*; do
    [ -f "$h" ] || continue
    if grep -qE "sess=$SESS( |\$)" "$h" 2>/dev/null; then   # MINOR-1: 정확 매치(ft-x#1 이 ft-x#10에 오매치 방지)
      printf 'NEEDS_INPUT %s\n' "$(basename "$h" | sed 's/^hil-//')"
      return 0
    fi
  done
  # ④/⑤ CPU 판정 (2회 연속 저CPU=HANG, 카운터는 폴 호출 간 유지)
  local cpu cnt_f cnt fable=0
  ft_parse_sess "$SESS"; [ "$FT_ROLE" = "planner" ] && fable=1
  cpu="$(ft_sess_cpu "$SESS")"
  cnt_f="$SIG/.$SESS.lowcpu"
  if [ -z "$cpu" ]; then
    printf 'HANG\n'; return 0   # 세션/프로세스 부재 — 정지로 간주
  fi
  if awk -v c="$cpu" 'BEGIN{exit !(c+0 >= 0.3)}'; then
    rm -f "$cnt_f" 2>/dev/null
    printf 'RUNNING\n'; return 0
  fi
  cnt="$(cat "$cnt_f" 2>/dev/null || echo 0)"; cnt=$((cnt+1))
  printf '%s' "$cnt" > "$cnt_f" 2>/dev/null
  if [ "$cnt" -ge 2 ]; then printf 'HANG\n'; else printf 'RUNNING\n'; fi
  return 0
}

# --timeout: DONE/MSG/NEEDS_INPUT 이 나올 때까지 5초 간격 재시도(상한 timeout)
if [ "${TIMEOUT:-0}" -gt 0 ] 2>/dev/null; then
  waited=0
  while :; do
    out="$(poll_once)"
    case "$out" in DONE*|MSG*|NEEDS_INPUT*) printf '%s\n' "$out"; exit 0;; esac
    [ "$waited" -ge "$TIMEOUT" ] && { printf '%s\n' "$out"; exit 0; }
    sleep 5; waited=$((waited+5))
  done
else
  poll_once
fi
exit 0
