#!/usr/bin/env bash
# test_merge_land_pushahead_r2368_mut4.sh — r2368 변이 M9(사본에서만 고치고 «같은 사례가 FAIL» + «원본은 PASS»)
#   M9 호출 0 안내 줄을 지금 글자(«설치 검사 0초 초과»)로 되돌림 → ⑪ FAIL · 사례 = p11(팩 리포 · 뒤 단계 남은 0)
#   M1~M4 = _mut.sh · M5~M7 = _mut2.sh · M8 = _mut3.sh · 기준판 Red = _red.sh · 격리 = _pushahead_r2368_fixture.sh · 실 원격·실 gh·실 mbox 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_pushahead_r2368_fixture.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:800}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pa_init "$T"; pa_fix
S1=$SECONDS
mut 9 p11 ft-merge-land.sh 'else echo "INSTALL-PENDING 판정 불가 — 설치 검사 호출 0(남은 ${ITO}초) · 손으로: ' 'else echo "INSTALL-PENDING 설치 검사 ${ITO}초 초과 — 손으로: '   # M9 호출 0 줄을 지금 글자로 → ⑪ FAIL
S2=$SECONDS
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh"
ck "키트 사본 = 추적본(bin) 과 같은 글자" $?
echo "단계별 초: M9 $((S2 - S1)) · 사본 대조 $((SECONDS - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
