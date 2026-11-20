#!/usr/bin/env bash
# test_merge_land_pushahead_r2368_mut2.sh — r2368 변이 M5~M7(사본에서만 고치고 «같은 사례가 FAIL» + «원본은 PASS»)
#   M5 앞 대조를 squash 갈래(:70) 안으로(--ff 에서 0) → ⑤ FAIL · M6 앞 대조 끊김을 ok 로 셈 → ⑦ FAIL · M7 HPRE 를 rc 만 보고 정함(첫 줄 확인 뺌) → ⑧ FAIL
#   M1~M4 = _mut.sh · M8 = _mut3.sh · M9 = _mut4.sh · 기준판 Red = _red.sh(70초 상한으로 쪼갬)
#   격리 = _pushahead_r2368_fixture.sh · 실 원격·실 gh·실 mbox 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_pushahead_r2368_fixture.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:800}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pa_init "$T"; pa_fix; fx_base; BASE="${BASE:-}"
S1=$SECONDS

mut 5 p5 ft-merge-land.sh 'if [ -z "$DRY" ]; then HKT=' 'if [ -z "$DRY" ] && [ -z "$FF" ]; then HKT='   # M5 앞 대조를 squash 갈래 안으로(--ff 에서 0) → ⑤ FAIL
S2=$SECONDS
mut 6 p7 ft-merge-land.sh '[ "$HPRC" = 0 ] && case "$HPLN" in "OK n=0"*) HPRE=ok;; esac' 'HPRE=ok'   # M6 끊김을 ok 로 셈 → ⑦ FAIL
mut 7 p8 ft-merge-land.sh '[ "$HPRC" = 0 ] && case "$HPLN" in "OK n=0"*) HPRE=ok;; esac' '[ "$HPRC" = 0 ] && HPRE=ok'   # M7 rc 만 보고 → ⑧ FAIL(«OK n=2» 를 ok 로 셈)
S3=$SECONDS
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh"
ck "키트 사본 = 추적본(bin) 과 같은 글자" $?
echo "단계별 초: M5 $((S2 - S1)) · M6·M7 $((S3 - S2)) · 사본 대조 $((SECONDS - S3)) · 합계 $((SECONDS - T0))   # M8 = _mut3.sh · M9 = _mut4.sh"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
