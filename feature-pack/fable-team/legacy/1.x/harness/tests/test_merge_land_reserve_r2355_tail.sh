#!/usr/bin/env bash
# test_merge_land_reserve_r2355_tail.sh — r2355 나머지 반례: ④b equiv 끊김 · ④c press 끊김(+rc 1 짝·press 칸) · ⑤⑥⑦⑧ LAND-PHASE 단계 초 1줄 · ⑫ 기준판 PB·AB·rc 대조
#   계약 K1(push 몫 예약) · K2(단계 초 1줄) · K4(다른 길 그대로) · ①~④ = test_merge_land_reserve_r2355.sh · K3 = _k3.sh · 변이 = _mut*.sh
#   격리 = _reserve_r2355_fixture.sh(임시 origin · 가짜 gh·게이트·equiv·press · 실 원격·실 gh·실 mbox 0) · 시험 1개 70초 상한(하드 룰 22 로 쪼갬)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix; fx_base
S1=$SECONDS
for c in k4b k4c; do "$c" "$FIX"; ck "$c" $?; done
S2=$SECONDS
for c in k5 k6 k7 k8 k12; do "$c" "$FIX"; ck "$c" $?; done
echo "단계별 초: ④b④c $((S2 - S1)) · ⑤~⑧⑫ $((SECONDS - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
