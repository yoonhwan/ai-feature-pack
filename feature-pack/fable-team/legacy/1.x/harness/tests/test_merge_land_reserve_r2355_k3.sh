#!/usr/bin/env bash
# test_merge_land_reserve_r2355_k3.sh — r2355 K3 크리티컬 받는 이 2: ft-merge-land 사건만 _desk + _master 같은 본문 1통씩 · 받는 이마다 몫 · pending 받는 이/보냄 칸 · drain 은 못 받은 이에게만
#   반례 ⑨ _desk ≠ _master / ⑩ _desk = _master / ⑪ _master 없음 / ⑪b master 실패 → pending → drain / ⑪c ft-nano-close 는 desk 하나 / ⑪d 몫 경계
#   K1·K2 반례 = test_merge_land_reserve_r2355.sh · 변이·기준판 Red = test_merge_land_reserve_r2355_mut.sh (시험 1개 70초 상한 · 하드 룰 22 로 셋으로 쪼갬)
#   격리 = _reserve_r2355_fixture.sh(가짜 우편함 · 실 mbox 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix
S1=$SECONDS
for c in k9 k10 k11 k11b k11c k11d; do "$c" "$FIX"; ck "$c" $?; done
echo "단계별 초: K3 ⑨~⑪d $((SECONDS - S1)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
