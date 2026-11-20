#!/usr/bin/env bash
# test_merge_land_reserve_r2355.sh — r2355: push 앞 단계가 push 1단위(PV = F+7)를 예약한다 · 실행마다 «LAND-PHASE» 단계 초 1줄 · 크리티컬 받는 이 2(ft-merge-land 만)
#   이 파일 = K1 ①~④(fetch 상한 끊김 · 게이트 상한·시작 0 · 닫기 재시도 SKIP · 빠른 앞 단계) · ④b ④c ⑤~⑧ ⑫ = _tail.sh · K3 ⑨~⑪d = _k3.sh
#   변이 M1~M11 = test_merge_land_reserve_r2355_mut.sh(시험 1개 70초 상한 · 하드 룰 22 — 쪼갬) · 격리 = _reserve_r2355_fixture.sh(임시 origin · 가짜 gh·게이트·equiv·press·mbox · 실 원격·실 gh·실 mbox 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix; fx_base
S1=$SECONDS
for c in k1 k2a k2b k3 k4; do "$c" "$FIX"; ck "$c" $?; done
echo "단계별 초: K1 ①~④ $((SECONDS - S1)) · 합계 $((SECONDS - T0))   # ④b ④c ⑤~⑧ ⑫ = _tail.sh · K3 = _k3.sh · 변이 = _mut*.sh(70초 상한으로 쪼갬)"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
