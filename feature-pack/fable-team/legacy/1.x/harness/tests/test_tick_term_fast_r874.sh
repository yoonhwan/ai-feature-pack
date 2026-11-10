#!/usr/bin/env bash
# test_tick_term_fast_r874.sh — r874: launchctl kickstart -k 는 SIGTERM 뒤 5초면 SIGKILL(-9 · 2026-10-25 launchd 로그 실측).
#   ft-tick 이 앞단 자식(wt-sweep 등)을 도는 중에도 TERM 뒤 5초 안에 자식 묶음까지 끝내고 나가는가 + 바퀴 상한 ERROR + 데몬 사이 격리.
#   ⓐ kickstart -k 대역: 바퀴 자식이 도는 중 TERM → 5초 안 종료 · 자식 0
#   ⓑ 바퀴 상한(FT_TICK_PASS_MAX_SEC) 넘으면 ERROR 1줄 + 다음 바퀴가 처음부터(조용한 끊김 0)
#   ⓒ 한 데몬의 바퀴가 묶여도 다른 데몬 바퀴는 계속(데몬 단위 격리)
# 실 좌석 0: 가짜 wt-sweep(sleep) · 가짜 mbox · 명부·pid·stamp·상태 전부 mktemp 안 · 다른 감시는 env 로 끔.
#   R874_TICK=<사본> 으로 변이판을 돌린다(증거 mutations).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TICK="${R874_TICK:-$HERE/../bin/ft-tick.sh}"
TMP="$(mktemp -d)"
PIDS=()
tree_of() { ps -axo pid=,ppid= 2>/dev/null | awk -v r="$1" '{p[$1]=$2} END {s[r]=1; do {n=0; for (k in p) if (!(k in s) && (p[k] in s)) {s[k]=1; n=1}} while (n); for (k in s) print k}'; }
cleanup() { local p; for p in ${PIDS[@]+"${PIDS[@]}"}; do kill -KILL $(tree_of "$p") 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

printf '#!/bin/bash\nexit 0\n' > "$TMP/mbox.sh"
# 가짜 wt-sweep: 실행마다 runs 에 1줄 · pid 기록 · FAKE_SLEEP 초 자식 sleep 을 wait
cat > "$TMP/sweep.sh" <<'EOF'
#!/bin/bash
[ -n "${FAKE_IGNORE_TERM:-}" ] && trap '' TERM   # TERM 무시(자식 sleep 도 물려받는다) = wt-sweep 계획 perl alarm 꼴
echo "$$" >> "$FAKE_DIR/runs"; echo "$$" > "$FAKE_DIR/sweep.pid"
sleep "$FAKE_SLEEP" & echo "$!" > "$FAKE_DIR/sleep.pid"; wait "$!"
echo "sweep 계획 0"
EOF
chmod +x "$TMP/mbox.sh" "$TMP/sweep.sh"
echo '{"_master": null}' > "$TMP/seats-t.json"

# start <이름> <FAKE_SLEEP> [상한초] [쉼초(기본 1)] [TERM 무시=1] → 배경 기동 · pid 를 PIDS 에 · 로그 $TMP/<이름>/tick.log
start() {
  local d="$TMP/$1"; mkdir -p "$d"
  ( cd "$d" && exec env FAKE_DIR="$d" FAKE_SLEEP="$2" ${3:+FT_TICK_PASS_MAX_SEC="$3"} ${5:+FAKE_IGNORE_TERM=1} \
      FT_TICK_SEATS="${TICK_SEATS:-$TMP/seats-t.json}" FT_TICK_MBOX="$TMP/mbox.sh" FT_TICK_PIDFILE="$d/tick.pid" \
      FT_TICK_STATE_DIR="$d/state" FT_TICK_STAMP_PREFIX="$d/p-" FT_TICK_LOOP_SEC="${4:-1}" \
      FT_TICK_WT_SWEEP=1 FT_TICK_WT_SWEEP_BIN="$TMP/sweep.sh" FT_TICK_SEAT_STATUS="$d/none" \
      FT_TICK_AUTONOMY=0 FT_TICK_LEAK_REAP=0 FT_TICK_HIL=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 \
      FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 FT_TICK_API_OUTAGE=0 FT_MODEL_SWAP=0 FT_TICK_DRIFT=0 \
      FT_TICK_RAISED=0 FT_TICK_RENAMED=0 FT_TICK_QUEUE_FULL=0 FT_TICK_QUEUE=0 FT_TICK_LAUNCHD=0 \
      FT_TICK_MAGAZINE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 \
      bash "$TICK" ${TICK_ONCE:+--once} > "$d/tick.log" 2>&1 ) &
  PIDS+=("$!"); LAST="$!"
}
# wait_for <초> <조건 명령…> → 0 = 조건 참
wait_for() { local n=$(( $1 * 10 )); shift; while [ "$n" -gt 0 ]; do "$@" && return 0; sleep 0.1; n=$((n-1)); done; return 1; }
alive() { kill -0 "$1" 2>/dev/null; }
dead() { ! kill -0 "$1" 2>/dev/null; }
runs() { [ -f "$1/runs" ] && wc -l < "$1/runs" | tr -d ' ' || echo 0; }
ge() { [ "$(runs "$1")" -ge "$2" ]; }

bash -n "$TICK" && ok "bash -n" || bad "bash -n"

# ⓐ kickstart -k 대역 — 바퀴 자식(sweep → sleep 30)이 도는 중 TERM
start a 30; tp="$LAST"
if wait_for 10 test -s "$TMP/a/sleep.pid"; then
  sp="$(cat "$TMP/a/sweep.pid")"; slp="$(cat "$TMP/a/sleep.pid")"
  t0="$(date +%s)"; kill -TERM "$tp"
  if wait_for 5 dead "$tp"; then ok "ⓐ TERM 뒤 5초 안 종료 ($(( $(date +%s) - t0 ))s)"; else bad "ⓐ TERM 뒤 5초 넘게 살아 있음 (launchd 라면 SIGKILL = -9)"; fi
  if wait_for 1 dead "$sp" && wait_for 1 dead "$slp"; then ok "ⓐ 자식 묶음 0 (sweep·sleep 종료)"; else bad "ⓐ 자식 남음 sweep=$(alive "$sp" && echo 살아있음) sleep=$(alive "$slp" && echo 살아있음)"; fi
  grep -q 'ft-tick stopped' "$TMP/a/tick.log" && ok "ⓐ stopped 줄(trap 이 돎)" || bad "ⓐ stopped 줄 없음"
  [ ! -f "$TMP/a/tick.pid" ] && ok "ⓐ pidfile 지움" || bad "ⓐ pidfile 남음"
else bad "ⓐ 가짜 sweep 기동 못 봄 ($(tail -3 "$TMP/a/tick.log" | tr '\n' ' '))"; fi

# ⓐ2 TERM 을 무시하는 자식(wt-sweep 계획의 perl alarm 꼴) — 그래도 5초 안 종료 · 자식 0 (KILL 로 마무리)
start a2 30 "" "" 1; tp="$LAST"
if wait_for 10 test -s "$TMP/a2/sleep.pid"; then
  sp="$(cat "$TMP/a2/sweep.pid")"; slp="$(cat "$TMP/a2/sleep.pid")"
  t0="$(date +%s)"; kill -TERM "$tp"
  if wait_for 5 dead "$tp"; then ok "ⓐ2 TERM 무시 자식이 있어도 5초 안 종료 ($(( $(date +%s) - t0 ))s)"; else bad "ⓐ2 5초 넘게 살아 있음"; fi
  if wait_for 1 dead "$sp" && wait_for 1 dead "$slp"; then ok "ⓐ2 TERM 무시 자식도 정리(KILL)"; else bad "ⓐ2 TERM 무시 자식 남음 sweep=$(alive "$sp" && echo 살아있음) sleep=$(alive "$slp" && echo 살아있음)"; fi
else bad "ⓐ2 가짜 sweep 기동 못 봄"; fi

# ⓐ3 쉼(sleep) 단계 TERM — 쉼 30초 · 바퀴는 바로 끝 → 쉼 중 TERM 도 5초 안
start a3 0 "" 30; tp="$LAST"
if wait_for 10 ge "$TMP/a3" 1 && wait_for 5 grep -q 'wt-sweep: rc=0' "$TMP/a3/tick.log"; then
  sleep 2; t0="$(date +%s)"; kill -TERM "$tp"
  if wait_for 5 dead "$tp"; then ok "ⓐ3 쉼 중 TERM 5초 안 종료 ($(( $(date +%s) - t0 ))s)"; else bad "ⓐ3 쉼 중 TERM 5초 넘게 살아 있음"; fi
else bad "ⓐ3 첫 바퀴 끝을 못 봄"; fi

# ⓑ 바퀴 상한 3초 · sweep 은 30초 → ERROR 1줄 + 다음 바퀴가 처음부터
start b 30 3; tp="$LAST"
if wait_for 12 ge "$TMP/b" 2; then ok "ⓑ 상한 뒤 다음 바퀴 시작 (runs=$(runs "$TMP/b"))"; else bad "ⓑ 다음 바퀴 없음 (runs=$(runs "$TMP/b") · 바퀴가 묶임)"; fi
n="$(grep -c 'ERROR pass over 3s' "$TMP/b/tick.log")"
[ "$n" -ge 1 ] && ok "ⓑ ERROR 줄 ${n}개" || bad "ⓑ ERROR 줄 0 (조용한 끊김/묶임)"
first="$(sed -n 1p "$TMP/b/runs" 2>/dev/null)"
[ -n "$first" ] && dead "$first" && ok "ⓑ 끊긴 바퀴의 sweep 종료(이어 돌기 0)" || bad "ⓑ 끊긴 sweep 살아 있음 ($first)"
kill -TERM "$tp"; wait_for 5 dead "$tp" || bad "ⓑ 정리 TERM 5초 초과"

# ⓒ 데몬 격리 — c1 은 sweep 30초(상한 기본) · c2 는 sweep 0초 → c1 이 묶인 동안 c2 바퀴 3번 이상
start c1 30; p1="$LAST"; start c2 0; p2="$LAST"
if wait_for 12 ge "$TMP/c2" 3; then ok "ⓒ 다른 데몬 바퀴 계속 (c2 runs=$(runs "$TMP/c2") · c1 runs=$(runs "$TMP/c1"))"; else bad "ⓒ 다른 데몬도 멈춤 (c2 runs=$(runs "$TMP/c2"))"; fi
alive "$p1" && ok "ⓒ 묶인 데몬은 살아 있음(죽지 않고 상한까지 대기)" || bad "ⓒ 묶인 데몬 죽음"
kill -TERM "$p1" "$p2"; wait_for 5 dead "$p1" && wait_for 5 dead "$p2" || bad "ⓒ 정리 TERM 5초 초과"

# ⓓ r3 stamp 원자 쓰기·빈 값 0 읽기 — 끊긴 바퀴가 남긴 «빈 stamp» 로 다음 바퀴가 죽지 않고 stall 뒤 단계(wt-sweep 표지)까지 간다.
#   빈 stamp 를 미리 둔 바퀴 2회 · 앞 판(빈 stamp = `$(( now - ))` 산술 오류)은 이 칸이 빨강이여야 의미가 있다.
# ⓓ0 1항 계약(원자 쓰기) — stamp 쓰기 리다이렉션 직접 0 · 전부 write_stamp 경유(트렁케이트 중 끊기면 빈 stamp 가 남는다).
#     «직접 쓰기 되살림» 변이가 이 칸을 빨강으로 만든다(동작만으로는 한 번의 정상 쓰기를 가를 수 없다 — write_stamp 안의 `> "$t"` 는 임시 파일이라 예외).
direct="$(grep -nE '(now|echo [^>]*) *> *"\$(stamp|wstamp|sstamp|sf|mark)' "$TICK" | grep -vE '^[0-9]+: *#' | head -2 | tr '\n' ' ')"
if [ -n "$direct" ]; then bad "ⓓ0 stamp 직접 쓰기 남음: $direct"
else ok "ⓓ0 stamp 쓰기 전부 write_stamp 경유(리다이렉션 직접 0)"; fi

for i in 1 2; do
  d="$TMP/d$i"; mkdir -p "$d"; : > "$d/p-_all.stall.last"            # 끊김으로 트렁케이트된 stamp(빈 파일) 그대로
  TICK_ONCE=1 start "d$i" 0; tp="$LAST"
  if wait_for 15 dead "$tp"; then ok "ⓓ$i 한 바퀴 종료"; else bad "ⓓ$i --once 가 끝나지 않음"; fi
  if ge "$d" 1; then ok "ⓓ$i 빈 stamp 바퀴도 stall 뒤 wt-sweep 까지 도달 (runs=$(runs "$d"))"; else bad "ⓓ$i 빈 stamp 에서 바퀴가 죽었다 (runs=$(runs "$d") · 로그: $(tail -2 "$d/tick.log" | tr '\n' ' '))"; fi
  grep -q 'WARN stamp 숫자 아님' "$d/tick.log" && ok "ⓓ$i WARN 1줄(빈값 → 0 으로 읽음)" || bad "ⓓ$i WARN 줄 0 (조용한 처리)"
  grep -qE '산술 문법|syntax error' "$d/tick.log" && bad "ⓓ$i 산술 오류 남음 ($(grep -m1 -E '산술 문법|syntax error' "$d/tick.log"))" || ok "ⓓ$i 산술 오류 0"
  case "$(cat "$d/p-_all.stall.last" 2>/dev/null)" in
    ''|*[!0-9]*) bad "ⓓ$i 바퀴 뒤에도 stamp 가 숫자 아님 ('$(cat "$d/p-_all.stall.last" 2>/dev/null)')";;
    *) ok "ⓓ$i 바퀴 뒤 stamp = 숫자($(cat "$d/p-_all.stall.last")) — 다음 바퀴 정상";;
  esac
done

# ⓔ r3 배경 pass rc≠0 → 부모가 ERROR 1줄(같은 원인 연속은 1통) · 부모는 계속 돈다(조용한 계속 0).
#   seats.json 깨짐 = pass rc=1(유일한 비 0 경로) · 쉼 1초라 3초 동안 바퀴 여러 번 돈다.
printf '{ broken json\n' > "$TMP/seats-bad.json"
TICK_SEATS="$TMP/seats-bad.json" start e 0; tp="$LAST"
if wait_for 8 grep -q 'ERROR pass failed' "$TMP/e/tick.log"; then ok "ⓔ 배경 바퀴 rc≠0 → 부모 ERROR 줄"; else bad "ⓔ ERROR 줄 0 (조용한 계속) · 로그: $(tail -2 "$TMP/e/tick.log" | tr '\n' ' ')"; fi
sleep 3; n="$(grep -c 'ERROR pass failed' "$TMP/e/tick.log" 2>/dev/null)"
[ "${n:-0}" = 1 ] && ok "ⓔ 같은 원인(rc=1) 연속 = ERROR 1통 (바퀴 여러 번 · 줄 $n)" || bad "ⓔ ERROR 줄 ${n:-0}개 (1통 아님)"
alive "$tp" && ok "ⓔ 부모는 계속 돈다(죽지 않음)" || bad "ⓔ 부모 죽음"
kill -TERM "$tp"; wait_for 5 dead "$tp" || bad "ⓔ 정리 TERM 5초 초과"

echo "RESULT fail=$fail"
[ "$fail" -eq 0 ]
