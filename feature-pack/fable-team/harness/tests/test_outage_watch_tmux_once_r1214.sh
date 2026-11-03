#!/usr/bin/env bash
# test_outage_watch_tmux_once_r1214.sh — r1214 단계 2: ft-tick.sh outage_watch 가 tmux 를 «바퀴당 1회» 만 부른다.
#   원인: 명부 행마다 pane_of(= tmux list-panes -a 1회)를 불러 ops 220행·공용 1233행 → load 60+ 에서 단계가 70초를 넘겼다.
#   반례 W1 명부 3행·살아 있음 1 → jsonl 조회 1 · tmux 추가 호출 1 · W2 살아 있음 0 → jsonl 0 · 장애 도구 입력 빈 줄 ·
#        W3 tmux 조회 실패 → ERROR 1줄 · rc0 · 장애 도구 호출 0 · W4 명부 1000행·살아 있음 2 → tmux 추가 호출 1 · 단계 1초 안쪽 · W5 bin·kit cmp0.
#   tmux 추가 호출 = (장애 감시 켬 바퀴의 list-panes 수) − (끈 바퀴의 수) → 다른 단계의 tmux 호출과 섞이지 않는다.
#   bash tests/test_outage_watch_tmux_once_r1214.sh            # 전 칸
#   bash tests/test_outage_watch_tmux_once_r1214.sh --mutate   # 변이 1(행마다 pane_of 되살림 → W1·W4 가 무너지는지)
#   FT_TEST_OUTAGE_TICK=<ft-tick 사본> 으로 기준판(origin/main)을 돌린다. 실 tmux·실 우편함·실 좌석 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0.
[ "${FT_TEST_OUTAGE_ONCE_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_OUTAGE_ONCE_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
TICK="${FT_TEST_OUTAGE_TICK:-$BIN/ft-tick.sh}"
MUT=0; case "${1:-}" in --mutate) MUT=1;; esac
fail=0; T0="$(date +%s)"
PH() { echo "PHASE ${1} +$(( $(date +%s) - T0 ))s"; }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT

# ── 가짜 도구 ────────────────────────────────────────────────────────────────
FB="$T/fakebin"; mkdir -p "$FB"
cat > "$FB/tmux" <<'EOF'
#!/bin/bash
case "$1" in
  list-panes) printf 'LP %s\n' "$*" >> "${TMUX_LOG:-/dev/null}"
              [ "${FAKE_TMUX_FAIL:-0}" = 1 ] && exit 1
              [ -z "${FAKE_SESSIONS:-}" ] || printf '%s\n' "$FAKE_SESSIONS" | awk '{print $1}' | while read -r s; do
                case "$*" in *session_name*pane_id*) echo "$s %9";; *) echo "$s";; esac; done
              exit 0;;
  capture-pane) printf '❯ \n'; exit 0;;
esac
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$FB/mbox.sh"
# seat-status 대역 — jsonl <좌석>: 호출을 기록하고 가짜 경로를 낸다
cat > "$T/seatstatus-stub.sh" <<'EOF'
#!/bin/bash
case "$1" in
  jsonl) printf '%s\n' "$2" >> "${SS_LOG:-/dev/null}"; echo "/nonexistent/$2.jsonl"; exit 0;;
  one) echo "$2 IDLE 20000 claude"; exit 0;;
  turn) echo "IDLE 1793400000 0 no jsonl"; exit 0;;
esac
exit 0
EOF
# 장애 도구 대역 — 표준입력을 기록한다(호출 1회 = START/END 1쌍)
cat > "$T/outage-stub.py" <<'EOF'
import os, sys
data = sys.stdin.read()
with open(os.environ.get("OUT_LOG", os.devnull), "a", encoding="utf-8") as f:
    f.write("CALL\n" + data + "END\n")
EOF
printf '#!/bin/bash\nexit 0\n' > "$T/goal-stub.sh"; printf '#!/bin/bash\nexit 0\n' > "$T/alive-stub.sh"
chmod +x "$FB/tmux" "$FB/mbox.sh" "$T/seatstatus-stub.sh" "$T/goal-stub.sh" "$T/alive-stub.sh"
mkdir -p "$T/repo/.fable-team/bin"

mkseats() {   # $1 = 파일 · $2 = 행 수 (M#1 = 팀장 1행 포함, L#1·L#2 = 살아 있을 수 있는 행)
  python3 - "$1" "$2" <<'PY'
import json, sys
n = int(sys.argv[2])
d = {"_master": "M#1", "M#1": {"role": "master", "agent": "claude", "tick": None},
     "L#1": {"role": "nano", "agent": "claude", "tick": None}}
for i in range(2, n):
    d[f"L#{i}"] = {"role": "nano", "agent": "claude", "tick": None}
json.dump(d, open(sys.argv[1], "w"))
PY
}

# 한 바퀴(--once) → $T/<이름>/{out,tmux.log,ss.log,outage.log,rc}. $3 = 장애 감시(1|0) · $4 = 살아 있는 세션(줄바꿈 구분) · $5 = tmux 실패(0|1)
runtick() {
  local n="$1" seats="$2" on="$3" live="$4" tfail="${5:-0}"
  mkdir -p "$T/$n/state"; : > "$T/$n/tmux.log"; : > "$T/$n/ss.log"; : > "$T/$n/outage.log"
  cp "$TICK" "$T/repo/.fable-team/bin/ft-tick.$n.sh"
  ( cd "$T/repo" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      FT_TICK_SEATS="$seats" FT_TICK_MBOX="$FB/mbox.sh" FT_TICK_SEAT_STATUS="$T/seatstatus-stub.sh" \
      FT_TICK_API_OUTAGE="$on" FT_TICK_API_OUTAGE_BIN="$T/outage-stub.py" FT_TICK_API_OUTAGE_STATE="$T/$n/outage-state.json" \
      FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_HIL=0 FT_TICK_LAUNCHD=0 \
      FT_TICK_LEAK_REAP=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_QUEUE=0 FT_TICK_QUEUE_FULL=0 FT_TICK_UNPUSHED=0 \
      FT_TICK_RENAMED=0 FT_TICK_RAISED=0 FT_TICK_DRIFT=0 FT_TICK_PATH_FIRST="$FB" FT_TICK_WT_SWEEP=0 FT_TICK_AUTONOMY=0 \
      FT_TICK_ZOMBIE_CLEAN=0 FT_TICK_IDLE_LONG=0 FT_TICK_ACCT_PAUSE=0 FT_TICK_STALL_INTERVAL=9999999999 FT_TICK_STALL_MIN=15 \
      FT_TICK_MASTER_INTERVAL=99999 FT_TICK_PM_INTERVAL=99999 FT_TICK_GOAL_INTERVAL=99999 FT_TICK_GOAL_TICK="$T/goal-stub.sh" FT_TICK_AGENT_ALIVE="$T/alive-stub.sh" \
      FT_TICK_STATE_DIR="$T/$n/state" FT_TICK_STAMP_PREFIX="$T/$n/p-" FT_TICK_PIDFILE="$T/$n/pid" \
      TMUX_LOG="$T/$n/tmux.log" SS_LOG="$T/$n/ss.log" OUT_LOG="$T/$n/outage.log" FAKE_SESSIONS="$live" FAKE_TMUX_FAIL="$tfail" PATH="$FB:$PATH" \
      timeout 70 bash "$T/repo/.fable-team/bin/ft-tick.$n.sh" --once > "$T/$n/out" 2>&1; echo $? > "$T/$n/rc" )
}
lp() { grep -c '^LP ' "$T/$1/tmux.log" 2>/dev/null || true; }
extra_lp() { echo $(( $(lp "$1") - $(lp "$2") )); }     # 장애 감시 켠 바퀴 − 끈 바퀴
sscalls() { grep -c . "$T/$1/ss.log" 2>/dev/null || true; }

# 판정: 실패한 칸 이름들을 stdout 으로 (W1·W2·W3·W4)
judge() {
  local f="" r
  mkseats "$T/s3.json" 3; mkseats "$T/s1000.json" 1000
  # W1
  runtick w1on "$T/s3.json" 1 "L#1"; runtick w1off "$T/s3.json" 0 "L#1"
  [ "$(sscalls w1on)" = 1 ] || f="$f W1-jsonl조회"
  [ "$(extra_lp w1on w1off)" = 1 ] || f="$f W1-tmux호출"
  [ "$(grep -c '^CALL' "$T/w1on/outage.log")" = 1 ] && grep -q '^L#1	/nonexistent/L#1.jsonl$' "$T/w1on/outage.log" || f="$f W1-장애입력"
  # W2
  runtick w2 "$T/s3.json" 1 ""
  [ "$(sscalls w2)" = 0 ] || f="$f W2-jsonl조회"
  [ "$(grep -c '^CALL' "$T/w2/outage.log")" = 1 ] && [ "$(awk '/^CALL/{c=1;next} /^END/{c=0} c' "$T/w2/outage.log" | grep -c .)" = 0 ] || f="$f W2-빈입력"
  # W3
  runtick w3 "$T/s3.json" 1 "L#1" 1
  [ "$(grep -c 'outage_watch: ERROR tmux list-panes' "$T/w3/out")" = 1 ] || f="$f W3-ERROR줄"
  [ "$(cat "$T/w3/rc")" = 0 ] || f="$f W3-rc"
  [ "$(grep -c '^CALL' "$T/w3/outage.log")" = 0 ] || f="$f W3-장애도구호출"
  # W4
  runtick w4on "$T/s1000.json" 1 "L#1
L#7"; runtick w4off "$T/s1000.json" 0 "L#1
L#7"
  [ "$(extra_lp w4on w4off)" = 1 ] || f="$f W4-tmux호출"
  [ "$(sscalls w4on)" = 2 ] || f="$f W4-jsonl조회"
  local sec; sec="$(grep -o 'outage_watch=[0-9]*' "$T/w4on/out" | head -1 | cut -d= -f2)"
  { [ -n "$sec" ] && [ "$sec" -le 1 ]; } || f="$f W4-단계시간(${sec:-없음})"
  echo "${f# }"
}

PH "spec"
bash -n "$TICK" && ok "bash -n ft-tick.sh" || bad "bash -n"
if [ -z "${FT_TEST_OUTAGE_TICK:-}" ]; then
  cmp -s "$BIN/ft-tick.sh" "$KIT/ft-tick.sh" && ok "W5 bin·kit cmp0 ft-tick.sh" || bad "W5 bin·kit 어긋남 ft-tick.sh"
  [ ! -x "$HERE/test_outage_watch_tmux_once_r1214.sh" ] && ok "신설 시험 0o644(실행 비트 0)" || bad "신설 시험에 실행 비트"
fi

if [ "$MUT" = 0 ]; then
  PH "W1-W4"
  r="$(judge)"
  [ -z "$r" ] && ok "W1~W4 전 칸(tmux 1회 · 결과 같음 · 실패 ERROR 1줄 · 1000행 1초 안쪽)" || bad "W1~W4 실패: $r"
else
  PH "mutate"
  python3 - "$BIN/ft-tick.sh" "$T/mut-1.sh" <<'PY'
import sys
src, dst = sys.argv[1:3]
a = "    case \"$live\" in *$'\\n'\"$seat\"$'\\n'*) ;; *) continue;; esac\n"
b = "    [ -n \"$(pane_of \"$seat\")\" ] || continue\n"
t = open(src, encoding="utf-8").read()
if a not in t:
    sys.exit("변이 대상 줄 없음")
open(dst, "w", encoding="utf-8").write(t.replace(a, b, 1))
PY
  if [ $? != 0 ]; then bad "변이 1 적용 실패"; else
    TICK="$T/mut-1.sh"; r="$(judge)"
    case " $r " in *" W1-tmux호출 "*) case " $r " in *" W4-tmux호출 "*) ok "변이 1(행마다 pane_of) → W1·W4 tmux호출 FAIL ($r)";; *) bad "변이 1 이 W4 를 못 무너뜨림 (실패 칸: ${r:-없음})";; esac;; *) bad "변이 1 이 W1 을 못 무너뜨림 (실패 칸: ${r:-없음})";; esac
  fi
fi
echo "RESULT fail=$fail total=$(( $(date +%s) - T0 ))s"
[ "$fail" = 0 ]
