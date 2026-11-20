#!/usr/bin/env bash
# test_seat_reap_deferred_skip_registered_r2329.sh — r2329: 미룸 소화(digest)가 «다른 좌석이 장부에 등록한 상한 전 작업»을 멈추지 않고, 멈추기 직전에 pid·출처·명령 1줄(reap-deferred-stop)을 남긴다.
#   ① 남의 좌석(B) 등록 작업(상한 전) + 그 미룸 행 → 생존 · reap-skip why=registered seat=B · reap-deferred-stop 0 (기준판 Red)
#   ② 상한 지난 등록 줄(secs=0) → 등록 거름 밖 = 지금처럼 정지(reap-kill via=⑤미룸)
#   ③ 정지하는 미룸 행마다 reap-deferred-stop pid·why=⑤미룸·file(출처)·cmd = reap-kill 보다 «앞» 줄
#   ④ 대조 = 이 좌석(A) 자기 등록 작업(상한 전) → 거름은 «남의 것»만 · 지금처럼 정지
#   ⑤ 불변 = protect-exe · service-listen 미룸 행은 그대로 보호(신호 0 · defer-stop 0)
#   ⑥ 불변 = press 진행 중(내 uid 러너) 이면 미룸 소화 자체를 안 한다(신호 0 · 파일 유지)
#   변이 M1(등록 거름 지움)·M2(상한 지난 줄도 보호)·M3(정지 기록 줄 지움) = 사본 1곳 치환 → 각각 ①·②·③ FAIL
#   픽스처 = 임시 폴더(mktemp) · 표식 r2329fx-<pid> 프로세스만 · trap 정리. 상태 폴더(미룸·장부·허가)는 전부 임시.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2329_BIN:-$HERE/../../harness/bin}"; REAP="$BIN/ft-seat-reap.sh"; BGF="$BIN/ft-bg-finite.sh"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; MK="r2329fx-$$"
A="r2329a-$$#0"; B="r2329b-$$#1"
BASH_X="$(command -v bash)"
cleanup() { local p; for p in $(pgrep -f "$MK"); do kill -9 "$p" 2>/dev/null; done; }
trap 'cleanup; rm -rf "$T0"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo dead; }
orphan() {  # orphan <FT_SEAT> <루프 본문> — ppid 1 고아 1개 · pid 출력
  ( cd "$TMP" || exit; FT_SEAT="$1" nohup "$BASH_X" -c "$2 # $MK" >/dev/null 2>&1 & )
  sleep 0.4; pgrep -f "$2 # $MK" | while read -r p; do [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && echo "$p"; done | tail -1
}
lst() { LC_ALL=C TZ=UTC ps -o lstart= -p "$1" | xargs; }   # reap·장부와 같은 꼴(LC_ALL=C TZ=UTC · 공백 1칸)
row() { printf '{"pid": %s, "lstart": "%s", "cmd": "fx", "via": "②"}\n' "$1" "$(lst "$1")"; }
reg() { FT_BG_FINITE_LEDGER="$TMP/bg-finite.tsv" bash "$BGF" register "$1" "$2" "$3" "${4:-fx}" >/dev/null 2>&1; }   # 좌석 <상한초> pid (도구가 하는 일의 대역)
mkdir -p "$TMP/defer" "$TMP/resume" "$TMP/permits" "$TMP/tests/e2e" "$TMP/pbin"
printf 'import time\nwhile True: time.sleep(0.2)\n' > "$TMP/tests/e2e/r2329_press_fx.py"
ln -sf "$BASH_X" "$TMP/pbin/headroom"
export ZC_RESUME_DIR="$TMP/resume" FT_PERMIT_DIR="$TMP/permits" FT_REAP_DEFER_DIR="$TMP/defer" FT_BG_FINITE_LEDGER="$TMP/bg-finite.tsv"
export FT_PRESS_RUNNER_RE="r2329-never-$$"   # 이 머신의 실 press 가 픽스처 판정에 섞이지 않게
DF="$TMP/defer/$A.jsonl"
fresh() { rm -f "$TMP/defer"/* "$TMP/bg-finite.tsv"; }
run() { bash "${1:-$REAP}" "$A" 2>&1; }   # 미룸 소화 + 일반 reap(A)

# case<N> <bin> → 한 줄 상태값(원본과 변이를 같은 함수로 잼)
case1() { local L out; fresh; L="$(orphan "$B" 'while true; do echo s1 >> ls1.log; sleep 1; done')"
  reg "$B" 4200 "$L" 'bash loop'; row "$L" > "$DF"; out="$(run "$1/ft-seat-reap.sh")"
  echo "$(alive "$L") $(grep -c "reap-skip pid=$L why=registered seat=$B" <<< "$out") $(grep -c "reap-deferred-stop pid=$L" <<< "$out")"; }
case2() { local L out; fresh; L="$(orphan "$B" 'while true; do echo s2 >> ls2.log; sleep 1; done')"
  reg "$B" 0 "$L" 'bash loop'; row "$L" > "$DF"; out="$(run "$1/ft-seat-reap.sh")"
  echo "$(alive "$L") $(grep -c "reap-kill pid=$L via=⑤미룸" <<< "$out")"; }
case3() { local L out stop kill; fresh; L="$(orphan "$A" 'while true; do echo s3 >> ls3.log; sleep 1; done')"
  row "$L" > "$DF"; out="$(run "$1/ft-seat-reap.sh")"; stop="$(grep -n "reap-deferred-stop pid=$L " <<< "$out" | cut -d: -f1)"; kill="$(grep -n "reap-kill pid=$L " <<< "$out" | cut -d: -f1)"
  echo "$(alive "$L") $(grep -cE "reap-deferred-stop pid=$L why=⑤미룸 file=$DF cmd=." <<< "$out") $([ -n "$stop" ] && [ -n "$kill" ] && [ "$stop" -lt "$kill" ] && echo before || echo after)"; }
case4() { local L out; fresh; L="$(orphan "$A" 'while true; do echo s4 >> ls4.log; sleep 1; done')"
  reg "$A" 4200 "$L" 'bash loop'; row "$L" > "$DF"; out="$(run "$1/ft-seat-reap.sh")"
  echo "$(alive "$L") $(grep -c "reap-skip pid=$L why=registered" <<< "$out") $(grep -c "reap-kill pid=$L via=⑤미룸" <<< "$out")"; }
case5() { local LP LS out; fresh
  ( cd "$TMP" || exit; FT_SEAT="$A" nohup "$TMP/pbin/headroom" -c "while true; do sleep 1; : prot; done # $MK" >/dev/null 2>&1 & ); sleep 0.4
  LP="$(pgrep -f "sleep 1; : prot; done # $MK" | tail -1)"
  ( nohup python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(); time.sleep(60)' "lsfx-$MK" >/dev/null 2>&1 & ); sleep 0.6
  LS="$(pgrep -f "lsfx-$MK" | tail -1)"
  { row "$LS"; row "$LP"; } > "$DF"; out="$(run "$1/ft-seat-reap.sh")"
  echo "$(alive "$LS") $(alive "$LP") $(grep -c 'reap-skip pid=.* why=service-listen' <<< "$out") $(grep -c 'reap-skip pid=.* why=protect-exe' <<< "$out") $(grep -c 'reap-deferred-stop' <<< "$out")"
  kill "$LS" "$LP" 2>/dev/null; }
case6() { local L out; fresh; L="$(orphan "$A" 'while true; do echo s6 >> ls6.log; sleep 1; done')"
  row "$L" > "$DF"; printf '999999 %s /usr/bin/python3 %s\n' "$(id -u)" "$TMP/tests/e2e/r2329_press_fx.py" > "$TMP/snapme"
  out="$(FT_PRESS_PS_SNAPSHOT="$TMP/snapme" FT_PRESS_RUNNER_RE='tests/e2e/r2329_press_fx\.py' bash "$REAP" "$A" --defer-press 2>&1)"
  echo "$(alive "$L") $(grep -c 'reap-deferred-stop' <<< "$out") $([ -f "$DF" ] && echo left || echo gone)"; }

for f in "$REAP"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done
chk "kit 사본 같은 글자" "$(cmp -s "$HERE/../../harness/bin/ft-seat-reap.sh" "$HERE/../../harness/kit/fable-team/bin/ft-seat-reap.sh" && echo same || echo diff)" same
[ -x "$BGF" ] && ok "픽스처 전제 = ft-bg-finite.sh" || bad "ft-bg-finite.sh 없음"

echo "== ①~⑥ 원본"
chk "① 남의 등록 작업(상한 전) → 생존 · why=registered seat=B · defer-stop 0" "$(case1 "$BIN")" "alive 1 0"
chk "② 상한 지난 등록 줄 → 지금처럼 정지(등록 거름 밖)" "$(case2 "$BIN")" "dead 1"
chk "③ 정지 직전 1줄 = pid·why=⑤미룸·file·cmd · reap-kill 앞" "$(case3 "$BIN")" "dead 1 before"
chk "④ 자기 좌석 등록 작업 → 거름 0 · 정지" "$(case4 "$BIN")" "dead 0 1"
chk "⑤ protect-exe·service-listen → 생존 · skip 2줄 · defer-stop 0" "$(case5 "$BIN")" "alive alive 1 1 0"
chk "⑥ press 진행 → 소화 0 · 생존 · 미룸 파일 유지" "$(case6)" "alive 0 left"

echo "== 변이 M1~M3 (사본 · 1곳 치환) — 원본 대조는 위 ①~⑥"
mut() {  # mut <이름> <옛> <새> → 사본 폴더 경로
  local d="$TMP/mb/$1"; mkdir -p "$d"; cp -R "$BIN/." "$d"/
  python3 - "$d/ft-seat-reap.sh" "$2" "$3" <<'PY'
import sys
p, o, n = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if s.count(o) != 1: print(f"mut: «{o}» 개수 {s.count(o)}"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, n))
PY
  echo "$d"; }
M1="$(mut M1 '"registered" if p in other else ' '')"; chk "M1 등록 거름 지움 → ① FAIL" "$(case1 "$M1")" "dead 0 1"
M2="$(mut M2 'allreg = registered(t, me, now)' 'allreg = {**registered(t, me, now), **registered(t, me, now, expired=True)}')"; chk "M2 상한 지난 줄도 보호 → ② FAIL" "$(case2 "$M2")" "alive 0"
M3="$(mut M3 'for p, (v, lst, c) in sorted(live.items()): print(f"reap-deferred-stop pid={p} why={v} file={f} cmd={c[:100]}")' 'pass')"; chk "M3 정지 기록 줄 지움 → ③ FAIL" "$(case3 "$M3")" "dead 0 after"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
