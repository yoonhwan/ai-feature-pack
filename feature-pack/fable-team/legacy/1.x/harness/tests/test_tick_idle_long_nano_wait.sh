#!/usr/bin/env bash
# test_tick_idle_long_nano_wait.sh — R597: 팀장(master) 정지 판정이 «같은 명부의 살아 있는 나노» 를 본다.
#   ⓐ master IDLE 15분(문턱 10 · 6×문턱 60 미만) + 살아 있는 nano 1 → 지금 판 = «기다리는 것 = 없음» 알림(FAIL 기준) · 고친 판 = 알림 0 + DRY «kind=idle-long-nano-wait seat=<master> nanos=1»
#   ⓑ 같은 명부 · master 70분(≥6×문턱) → 알림 1 · 문구 «기다리는 것 = 나노 1 회신(<좌석>) · 나노 대기 70분» · 같은 turn_end 재실행 = 알림 0(1회)
#   ⓒ 나노 좌석이 명부에 있으나 pane 없음(닫힘) → 지금과 같은 «기다리는 것 = 없음» 알림
#   ⓓ 나노 좌석 0 → 지금 판과 바이트 같은 알림(회귀 0)
# 모든 쓰기는 mktemp scratch — 실 tmux·실 우편함·실 /tmp 상태파일 0. tmux·mbox·seat-status 는 가짜.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KIT="$REPO/harness/bin"; INST="$REPO/harness/kit/fable-team/bin"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got=[$2])";; esac; }

bash -n "$KIT/ft-tick.sh" && ok "bash -n kit" || bad "bash -n kit"
chk "키트 두 사본 동일 ft-tick.sh" "$(cmp -s "$KIT/ft-tick.sh" "$INST/ft-tick.sh" && echo same || echo differ)" same

PANES_NANO=$'M#1 %1\nN1#1 %2\nPLAN#1 %3'
PANES_CLOSED=$'M#1 %1\nPLAN#1 %3'
export FAKE_PANES="$PANES_NANO"
mkdir -p "$TMP/repo/.fable-team/bin" "$TMP/mins"
LIVE="$TMP/repo/.fable-team/bin/ft-tick.sh"; cp "$KIT/ft-tick.sh" "$LIVE"
# 가짜 tmux — list-panes 는 pane_of 와 같은 형식('#{session_name} #{pane_id}')만 받는다.
tmux() { case "$1" in list-panes) printf '%s\n' "$FAKE_PANES";; esac; return 0; }
export -f tmux
# 가짜 seat-status — turn <seat> = «IDLE <고정 turn_end> 0 no jsonl» (분은 $TMP/mins/<seat> 파일)
cat > "$TMP/seatstatus-stub.sh" <<'STUB'
#!/bin/bash
case "$1" in
  turn) s="$2"; e="$(cat "$MINTS_DIR/$s.end" 2>/dev/null)"; [ -n "$e" ] && echo "IDLE $e 0 no jsonl"; exit 0;;
esac
exit 0
STUB
# 가짜 mbox — peek pending=0 · send 는 본문을 $SENT_LOG 에 남긴다.
cat > "$TMP/mbox-stub.sh" <<'STUB'
#!/bin/bash
case "$1" in
  peek) echo "pending=0";;
  send) shift 2; printf '%s\t%s\n' "$1" "$2" >> "$SENT_LOG"; echo "QUEUED";;
esac
exit 0
STUB
export MINTS_DIR="$TMP/mins" SENT_LOG="$TMP/sent.log"
: > "$SENT_LOG"
MEND15="$(TZ=UTC date -u -v-15M '+%Y-%m-%dT%H:%M:%S')"
MEND70="$(TZ=UTC date -u -v-70M '+%Y-%m-%dT%H:%M:%S')"
NANOWAIT15="DRY kind=idle-long-nano-wait seat=M#1 nanos=1"
OLD15="DRY kind=idle-long seat=M#1 mins=15 to=PLAN#1"
OLDBODY70="[정지 70분] M#1 role=master — IDLE 지속 · 받은 발주 0 · 기다리는 것 = 없음(할 일을 못 받았다). 다음 발주·닫기·깨우기 중 하나"
NEWBODY70="[정지 70분] M#1 role=master — 기다리는 것 = 나노 1 회신(N1#1) · 나노 대기 70분 · 나노 pane 확인·깨우기·닫기 중 하나"

# ── 명부 3종 ──
printf '{"_master":"M#1","_hil_route":"PLAN#1","M#1":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"N1#1":{"role":"nano","agent":"pi","model":"m","tick":null},"PLAN#1":{"role":"planner","agent":"claude","model":"m","tick":"ft-master-tick"}}' > "$TMP/seats-nano.json"
printf '{"_master":"M#1","_hil_route":"PLAN#1","M#1":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"N1#1":{"role":"nano","agent":"pi","model":"m","tick":null},"PLAN#1":{"role":"planner","agent":"claude","model":"m","tick":"ft-master-tick"}}' > "$TMP/seats-nano-closed.json"
printf '{"_master":"M#1","_hil_route":"PLAN#1","M#1":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"PLAN#1":{"role":"planner","agent":"claude","model":"m","tick":"ft-master-tick"}}' > "$TMP/seats-nonano.json"
BASE=(FT_TICK_SEATS="$TMP/seats-nano.json" FT_TICK_MBOX="$TMP/mbox-stub.sh" FT_TICK_SEAT_STATUS="$TMP/seatstatus-stub.sh"
  FT_TICK_SEAT_STATUS="$TMP/seatstatus-stub.sh" FT_TICK_TURN_FIXTURE_DIR= FT_TICK_IDLE_LONG=1 FT_TICK_IDLE_STALL_MIN=10
  FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_API_OUTAGE=0 FT_TICK_HIL=0 FT_TICK_LAUNCHD=0
  FT_TICK_LEAK_REAP=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_QUEUE=0 FT_TICK_RENAMED=0 FT_TICK_RAISED=0
  FT_TICK_DRIFT=0 FT_TICK_WT_SWEEP=0 FT_TICK_AUTONOMY=0 FT_TICK_STALL_INTERVAL=0 FT_TICK_MASTER_INTERVAL=0
  FT_TICK_PM_INTERVAL=0 FT_TICK_GOAL_INTERVAL=0 FT_TICK_ZOMBIE_CLEAN=0 FT_TICK_RESUME_ATTEMPT="$TMP/no-resume-attempt"
  FT_TICK_MASTER_MSG=x FT_TICK_PM_MSG=x FT_TICK_GOAL_TICK="$TMP/none" FAKE_PANES="$FAKE_PANES")
runtick() {  # runtick <이름> <KEY=VAL...> · RT_FLAGS = --once [--dry-run]
  local n="$1"; shift; mkdir -p "$TMP/$n/state"
  ( cd "$TMP/repo" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      "${BASE[@]}" FT_TICK_STATE_DIR="$TMP/$n/state" FT_TICK_STAMP_PREFIX="$TMP/$n/p-" FT_TICK_PIDFILE="$TMP/$n/pid" \
      FAKE_PANES="$FAKE_PANES" "$@" bash "$LIVE" ${RT_FLAGS:---once} > "$TMP/$n/out" 2>&1 )
}
stops()  { grep -c '정지 ' "$SENT_LOG" 2>/dev/null; }        # idle-long 쪽지 수(다른 감시 쪽지는 정지 문구가 없다)
stopbody() { grep -F '정지 ' "$SENT_LOG" 2>/dev/null | sed 's/^[^	]*	//' | paste -sd'|' -; }

# ── ⓐ master 15분 · 살아 있는 나노 1 (문턱 60 미만) ──
echo "$MEND15" > "$TMP/mins/M#1.end"
RT_FLAGS="--once --dry-run" runtick a1
chk "ⓐ DRY: «나노 회신 대기» 줄 1 (알림 0)" "$(grep -c 'idle-long-nano-wait' "$TMP/a1/out") $(grep -c 'kind=idle-long seat=M#1' "$TMP/a1/out")" "1 0"
has "ⓐ DRY 문구" "$(grep 'idle-long-nano-wait' "$TMP/a1/out")" "$NANOWAIT15"
RT_FLAGS="--once" runtick a2
chk "ⓐ 실전: master 정지 쪽지 0(나노 회신 대기)" "$(stops)" 0
chk "ⓐ 로그 1줄" "$(grep -c 'idle_long_watch: M#1 정지 15분 — 나노 1 회신 대기(N1#1)' "$TMP/a2/out")" 1

# ── ⓑ master 70분(≥6×문턱) · 살아 있는 나노 1 → 알림 1회 ──
echo "$MEND70" > "$TMP/mins/M#1.end"
: > "$SENT_LOG"
RT_FLAGS="--once" runtick b1
chk "ⓑ 알림 1" "$(stops)" 1
chk "ⓑ 문구" "$(stopbody)" "$NEWBODY70"
RT_FLAGS="--once" runtick b1
chk "ⓑ 같은 turn_end 재실행 = 알림 0" "$(stops)" 1

# ── ⓒ 나노 좌석은 명부에 있으나 pane 없음(닫힘) → 지금과 같은 «없음» 알림 ──
echo "$MEND70" > "$TMP/mins/M#1.end"
: > "$SENT_LOG"
RT_FLAGS="--once" FAKE_PANES="$PANES_CLOSED" runtick c1 "FT_TICK_SEATS=$TMP/seats-nano-closed.json"       # 환경변수 접두 = 서브셸에 그대로 전달
chk "ⓒ 알림 1" "$(stops)" 1
chk "ⓒ 문구 = 없음" "$(stopbody)" "$OLDBODY70"

# ── ⓓ 나노 좌석 0 → 지금 판과 바이트 같은 알림(회귀 0) ──
: > "$SENT_LOG"
RT_FLAGS="--once" runtick d1 "FT_TICK_SEATS=$TMP/seats-nonano.json" "FAKE_PANES=$PANES_NANO"
chk "ⓓ 알림 1" "$(stops)" 1
chk "ⓓ 문구 = base 바이트" "$(stopbody)" "$OLDBODY70"
RT_FLAGS="--once --dry-run" runtick d2 "FT_TICK_SEATS=$TMP/seats-nonano.json" "FAKE_PANES=$PANES_NANO"
chk "ⓓ DRY 줄 = base 줄(나노 키 0)" "$(grep -c 'kind=idle-long seat=M#1 mins=70 to=PLAN#1' "$TMP/d2/out") $(grep -c 'nanos=' "$TMP/d2/out")" "1 0"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
