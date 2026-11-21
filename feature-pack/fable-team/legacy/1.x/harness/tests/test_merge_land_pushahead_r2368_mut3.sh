#!/usr/bin/env bash
# test_merge_land_pushahead_r2368_mut3.sh — r2368 변이 M8(사본에서만 고치고 «같은 사례가 FAIL» + «원본은 PASS»)
#   M8 HPRE=ok 인데 irc 를 124 로 둠 → ⑩ FAIL(대기 파일·알림 설치 칸 124) · 사례 = ①⑩ 묶음(p1)
#   M1~M4 = _mut.sh · M5~M7 = _mut2.sh · M9 = _mut4.sh · 기준판 Red = _red.sh · 격리 = _pushahead_r2368_fixture.sh · 실 원격·실 gh·실 mbox 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_pushahead_r2368_fixture.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:800}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pa_init "$T"; pa_fix
S1=$SECONDS
mut 8 p1 ft-merge-land.sh 'irc=0; IOUT="$HPOUT"' 'irc=124; IOUT="$HPOUT"'   # M8 뒤 irc 를 124 로 → ⑩ FAIL(대기 파일·알림 설치 칸)
S2=$SECONDS
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh"
ck "키트 사본 = 추적본(bin) 과 같은 글자" $?
echo "단계별 초: M8 $((S2 - S1)) · 사본 대조 $((SECONDS - S2)) · 합계 $((SECONDS - T0))   # M9 = _mut4.sh"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
