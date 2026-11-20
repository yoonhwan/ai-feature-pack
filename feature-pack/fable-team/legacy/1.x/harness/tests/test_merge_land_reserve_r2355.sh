#!/usr/bin/env bash
# test_merge_land_reserve_r2355.sh — r2355: push 앞 단계가 push 1단위(PV = F+7)를 예약한다 · 실행마다 «LAND-PHASE» 단계 초 1줄 · 크리티컬 받는 이 2(ft-merge-land 만)
#   계약 K1 push 몫 예약(①~④ · ④b · ④c) · K2 단계 초 1줄(⑤⑥⑦⑧) · K3 받는 이 2(⑨⑩⑪⑪b⑪c⑪d) · K4 다른 길 그대로(⑫) · 반례 ⑫ 는 기준판과 PB·AB·rc 대조
#   변이 M1~M11 = test_merge_land_reserve_r2355_mut.sh(시험 1개 70초 상한 · 하드 룰 22 — 쪼갬) · 격리 = _reserve_r2355_fixture.sh(임시 origin · 가짜 gh·게이트·equiv·press·mbox · 실 원격·실 gh·실 mbox 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix; fx_base
S1=$SECONDS
for c in k1 k2a k2b k3 k4 k4b k4c; do "$c" "$FIX"; ck "$c" $?; done
S2=$SECONDS
for c in k5 k6 k7 k8 k12; do "$c" "$FIX"; ck "$c" $?; done
S3=$SECONDS
for c in k9 k10 k11 k11b k11c k11d; do "$c" "$FIX"; ck "$c" $?; done
S4=$SECONDS
echo "단계별 초: K1 ①~④c $((S2 - S1)) · K2·⑫ $((S3 - S2)) · K3 ⑨~⑪d $((S4 - S3)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
