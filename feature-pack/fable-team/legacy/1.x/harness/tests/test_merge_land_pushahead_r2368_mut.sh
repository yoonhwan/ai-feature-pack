#!/usr/bin/env bash
# test_merge_land_pushahead_r2368_mut.sh — r2368 변이 M1~M4(사본에서만 고치고 «같은 사례가 FAIL» + «원본은 PASS» = 반대 결과 대조)
#   M1 앞 대조 지움(①) · M2 앞 대조 상한에서 PV 빼기 지움(②) · M3 팩 리포에도 앞 대조(③) · M4 --dry 에서도 앞 대조(④)
#   M5~M7 = _mut2.sh · M8 = _mut3.sh · M9 = _mut4.sh · 기준판 Red = _red.sh(70초 상한으로 쪼갬) · 반례 본체 = test_merge_land_pushahead_r2368.sh · _k2.sh
#   격리 = _pushahead_r2368_fixture.sh · 실 원격·실 gh·실 mbox 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_pushahead_r2368_fixture.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:800}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pa_init "$T"; pa_fix
S1=$SECONDS

mut 1 p1 ft-merge-land.sh 'if [ -n "$HTB" ]; then HT=' 'if [ 1 = 0 ]; then HT='   # M1 앞 대조 지움 → ① FAIL(대기 파일)
mut 2 p2 ft-merge-land.sh 'HP=$(( $(land_left) - RU ))' 'HP=$(( $(land_left) ))'   # M2 상한에서 PV 빼기 지움 → ② FAIL(K1 이 부른다)
S2=$SECONDS
mut 3 p3 ft-merge-land.sh '[ "$HIN" = 0 ] && [ "$HRK" != "$HRE" ] && [ -n "$HTB" ] || HTB=""' '[ -n "$HTB" ] || HTB=""'   # M3 팩 리포에도 앞 대조 → ③ FAIL
mut 4 p4 ft-merge-land.sh 'if [ -z "$DRY" ]; then HKT=' 'if [ 1 = 1 ]; then HKT='   # M4 --dry 에서도 앞 대조 → ④ FAIL
S3=$SECONDS
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh"
ck "키트 사본 = 추적본(bin) 과 같은 글자" $?
echo "단계별 초: M1·M2 $((S2 - S1)) · M3·M4 $((S3 - S2)) · 사본 대조 $((SECONDS - S3)) · 합계 $((SECONDS - T0))   # M5~M7 = _mut2.sh · M8 = _mut3.sh · M9 = _mut4.sh"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
