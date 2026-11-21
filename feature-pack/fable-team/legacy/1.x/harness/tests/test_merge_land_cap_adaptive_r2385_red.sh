#!/usr/bin/env bash
# test_merge_land_cap_adaptive_r2385_red.sh — r2385 ⑯(기준판 Red): 고정 상한 67 인 origin/main 판은 같은 54초 판에서 push 1단위(14)를 남기지 못해 예산 거절한다(고친 판 = _slow.sh 착지)
#   표본 = land-phase.tsv 20행(앞 합 54 · push 7) — 기준판은 표본을 안 읽으므로 lim 은 67 그대로 · 거절 = «gate 가 상한»/«push 몫 예약»/«총 마감 … push 를 끝낼 수 없음»
#   격리 = _reserve_r2355_fixture.sh · 기준판 = fx_base(origin/main 사본) · 판정 1판에 실 54초를 쓴다(하드 룰 22 · 70초 상한 = 파일을 쪼갬)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix; fx_base
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:400}"; fail=$((fail+1)); fi; }
mland() {   # mland <bin> <PR> <바깥 상한초> [KEY=VAL…] — land() 와 같되 land-phase.tsv 를 «안 지운다»(표본을 미리 심는다)
  local b="$1" n="$2" o="$3" s; shift 3
  mkpr "$n"; apv --approve-sha "${APSH:-$PRSHA}"; : > "$STUB_LOG"
  s=$SECONDS
  out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"; rc=$?; el=$((SECONDS - s))
}
SLP=54   # 고친 판(_slow.sh)과 같은 입력 — 기준판 gate 상한 = 67 − 2 − push 1단위 14 ≈ 51초 < 54초
tsa() { python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - int(sys.argv[1]))))' "${1:-0}"; }
[ -n "${BASE:-}" ] || { echo "SKIP 기준판(origin/main 사본) 못 만듦 — 판정 불가"; exit 0; }
rm -f "$PFILE"; TS="$(tsa 300)"
for i in $(seq 1 18); do printf '%s pr=%s close=3 view=1 fetch=2 gate=2 overlap=0 equiv=0 press=0 lint=0 push=1 etc=0 total=0 left=40\n' "$TS" "$((800 + i))" >> "$PFILE"; done
for i in 19 20; do printf '%s pr=%s close=3 view=1 fetch=2 gate=48 overlap=0 equiv=0 press=0 lint=0 push=7 etc=0 total=0 left=40\n' "$TS" "$((800 + i))" >> "$PFILE"; done
mland "$BASE" 602 60 FT_PUSH_FIXED_S=$F GATE_SLEEP=$SLP
ok=0
{ [ "$rc" = 1 ] && grep -qE '^REJECT (gate 가 상한|push 몫 예약|총 마감)' <<<"$out"; } && ! grep -q '^LANDED' <<<"$out" && ok=1
ck "⑯ 기준판(lim 67 고정) · gate 가 ${SLP}초 씀 → 예산 거절 rc 1 · 착지 0" $((1 - ok))
echo "판 1회 ${el}초 · 합계 $SECONDS"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
