#!/usr/bin/env bash
# test_merge_land_tail_deadline_r2320_mut.sh — r2320 변이 M1~M7: 사본에서만 고치고 «같은 사례가 FAIL» + «원본은 PASS» = 반대 결과 대조
#   M1 기본 100 그대로 → ① FAIL · M2 알림을 shim 뒤로 되돌림 → ③ FAIL · M3 LAND-TAIL 문턱 지움(늘 씀) → ⑤ FAIL
#   M4 skip 칸 지움 → ④ FAIL · M5 지정값 상한 100 깎기 지움 → ② FAIL · M6 deadline()·REM 에서 env 마감 뺌 → ⑩ FAIL · M7 try-auto 마감 export 지움 → ⑨ FAIL
#   반례 본체 = test_merge_land_tail_deadline_r2320.sh(시험 1개 70초 상한 · 하드 룰 22 — 쪼갬) · 실 원격·실 gh·실 mbox 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_tail_deadline_r2320_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix
patch1() { python3 -c 'import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
if s.count(sys.argv[2])!=1: sys.exit(1)
open(p,"w",encoding="utf-8").write(s.replace(sys.argv[2],sys.argv[3]))' "$1" "$2" "$3"; }
mut() {  # mut <이름> <사례> <파일> <옛> <새> [<파일2> <옛2> <새2>] — 사본 1벌 재사용 · 사례 FAIL 이어야 · 원본 같은 사례 = PASS
  local m="$T/mut"; if [ ! -d "$m" ]; then mkbin "$m" || { echo "FAIL M 사본"; fail=$((fail+1)); return; }; fi
  cp "$FIX/$3" "$m/$3"; [ -z "${6:-}" ] || cp "$FIX/$6" "$m/$6"
  if ! patch1 "$m/$3" "$4" "$5"; then echo "FAIL M$1 :: 변이 글자 1곳 아님"; fail=$((fail+1)); return; fi
  if [ -n "${6:-}" ] && ! patch1 "$m/$6" "$7" "$8"; then echo "FAIL M$1 :: 변이 글자 2 1곳 아님"; fail=$((fail+1)); return; fi
  if "$2" "$m"; then echo "FAIL M$1 :: 변이가 $2 를 통과"; fail=$((fail+1)); else echo "PASS M$1 ($2 FAIL)"; fi
  "$2" "$FIX"; ck "M$1-원본" $?; }
S1=$SECONDS
mut 1 k1 ft-merge-land.sh 'LIM="${FT_LAND_TOTAL_S:-67}"' 'LIM="${FT_LAND_TOTAL_S:-100}"'
mut 2 k3 ft-merge-land.sh 'fm_land_notify_land "$ROOT" "$PR" "${Q:0:10}" "$(pf title)" "$irc" "$IOUT" "$(pf headRefName)"   # r2320 T2: 착지 알림 = 설치 대조 «바로 뒤» · 루트 shim 앞(바깥 70초에 잘릴 때 알림부터 잃지 않게) · 인자·실패 WARN 그대로 · 착지 rc 불변' ':' \
      ft-merge-land.sh 'HLTO="$(fm_tail_s "${FT_HEAD_LAG_EVENT_S:-25}")"; HLO=""' 'fm_land_notify_land "$ROOT" "$PR" "${Q:0:10}" "$(pf title)" "$irc" "$IOUT" "$(pf headRefName)"; HLTO="$(fm_tail_s "${FT_HEAD_LAG_EVENT_S:-25}")"; HLO=""'
mut 3 k5 ft-merge-land.sh 'lt_line() { [ "$LTH" = 1 ] || return 0;' 'lt_line() { [ 1 = 1 ] || return 0;'
mut 4 k4 ft-merge-land.sh 'skip=$LTK' 'skip='
mut 5 k2 ft-merge-land.sh '[ "$LIM" -le 100 ]' '[ "$LIM" -le 10000 ]'
mut 6 k10 ft-merge-land.sh '"$((a < b ? a : b))"' '"$a"'
mut 7 k12 ft-autonomy-try.sh '; [ -n "${FT_LAND_DEADLINE:-}" ] || { FT_LAND_DEADLINE=$(( $(date +%s) + 67 )); export FT_LAND_DEADLINE; }' ';'
echo "단계별 초: 변이 M1~M7 + 원본 대조 $((SECONDS - S1)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
