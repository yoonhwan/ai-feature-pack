#!/usr/bin/env bash
# test_merge_land_pushahead_r2368_red.sh — r2368 기준판 Red: origin/main 사본에서 반례 ① · ⑪ 이 FAIL 이어야 한다(고치기 전에도 통과 = 시험 검출력 0)
#   반례 = test_merge_land_pushahead_r2368.sh(①) · _k2.sh(⑪) · 변이 M1~M4 = _mut.sh · M5~M7 = _mut2.sh · M8 = _mut3.sh · M9 = _mut4.sh(70초 상한 · 하드 룰 22 로 쪼갬)
#   실 원격·실 gh·실 mbox 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_pushahead_r2368_fixture.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pa_init "$T"; pa_fix; fx_base; BASE="${BASE:-}"
[ -n "${BASE:-}" ] || { echo "SKIP 기준판 Red — origin/main 사본 없음"; echo "ALL PASS"; exit 0; }
red() {   # red <사례> — 기준판(origin/main 사본)에서 그 사례가 FAIL(rc≠0) 이어야 한다
  if ( "$1" "$BASE" ) >/dev/null 2>&1; then echo "FAIL $1 기준판 — 고치기 전에도 통과(시험 검출력 0)"; fail=$((fail+1)); else echo "PASS $1 기준판 Red(정상)"; fi
}
S1=$SECONDS
red p1
S2=$SECONDS
red p11
S3=$SECONDS
echo "단계별 초: ① $((S2 - S1)) · ⑪ $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
