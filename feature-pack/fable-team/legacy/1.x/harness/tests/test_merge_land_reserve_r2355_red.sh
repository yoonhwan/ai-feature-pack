#!/usr/bin/env bash
# test_merge_land_reserve_r2355_red.sh — r2355 기준판 Red: origin/main 사본에서 반례 ① · ④b · ④c · ⑤ · ⑨ · ⑪b 가 FAIL 이어야 한다(고치기 전에도 통과 = 시험 검출력 0)
#   반례 = test_merge_land_reserve_r2355.sh · _tail.sh · _k3.sh · 변이 M1~M9 = _mut.sh · M10 = _mut2.sh · M11 = _mut3.sh (70초 상한 · 하드 룰 22 로 쪼갬)
#   R2355_FAST=1 = 같은 규칙 · 짧은 초(기준판 Red 는 FAIL 만 확인하면 된다) · 실 원격·실 gh·실 mbox 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export R2355_FAST=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix; fx_base
[ -n "${BASE:-}" ] || { echo "SKIP 기준판 Red — origin/main 사본 없음"; echo "ALL PASS"; exit 0; }
red() {   # red <사례> — 기준판(origin/main 사본)에서 그 사례가 FAIL(rc≠0) 이어야 한다
  if "$1" "$BASE" >/dev/null 2>&1; then echo "FAIL $1 기준판 — 고치기 전에도 통과(시험 검출력 0)"; fail=$((fail+1)); else echo "PASS $1 기준판 Red(정상)"; fi
}
S1=$SECONDS
for c in k1 k4b k4c k5 k9 k11b; do red "$c"; done
echo "단계별 초: 기준판 Red 6 $((SECONDS - S1)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
