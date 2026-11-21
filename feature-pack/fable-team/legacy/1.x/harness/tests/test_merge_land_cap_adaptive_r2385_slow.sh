#!/usr/bin/env bash
# test_merge_land_cap_adaptive_r2385_slow.sh — r2385 ⑯(고친 판): 앞 단계가 54초 쓴 판이 실측 표본(앞 합 54)으로 늘어난 상한 75 안에서 push 까지 간다
#   표본 = land-phase.tsv 20행(repo 칸 없음 = 옛 행 꼴 · 모든 repo 에 셈) 앞 합 54 · push 7 → LAND-CAP lim=75 push=14 출처=p90 · 판은 gate 한 단계에서 54초를 쓴다(= 표본의 앞 합 54)
#   같은 입력의 기준판 Red = test_merge_land_cap_adaptive_r2385_red.sh — 고정 67 이라 gate 상한 51초에 걸려 끊긴다(이 판은 75 라 gate 상한 60초 안 · push 까지 간다) · 함수 반례 = _r2385.sh · 판정 1판에 실 54초를 쓴다(하드 룰 22 · 70초 상한 = 파일을 쪼갬)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:400}"; fail=$((fail+1)); fi; }
mland() {   # mland <bin> <PR> <바깥 상한초> [KEY=VAL…] — land() 와 같되 land-phase.tsv 를 «안 지운다»(표본을 미리 심는다)
  local b="$1" n="$2" o="$3" s; shift 3
  mkpr "$n"; apv --approve-sha "${APSH:-$PRSHA}"; : > "$STUB_LOG"
  s=$SECONDS
  out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"; rc=$?; el=$((SECONDS - s))
}
SLP=54   # gate 한 단계가 54초 — 기준판(67)은 gate 상한 51초에 걸려 끊기고, 이 판(75)은 gate 상한 60초 안이라 끝까지 간다
tsa() { python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - int(sys.argv[1]))))' "${1:-0}"; }
rm -f "$PFILE"; TS="$(tsa 300)"
for i in $(seq 1 18); do printf '%s pr=%s close=3 view=1 fetch=2 gate=2 overlap=0 equiv=0 press=0 lint=0 push=1 etc=0 total=0 left=40\n' "$TS" "$((800 + i))" >> "$PFILE"; done
for i in 19 20; do printf '%s pr=%s close=3 view=1 fetch=2 gate=48 overlap=0 equiv=0 press=0 lint=0 push=7 etc=0 total=0 left=40\n' "$TS" "$((800 + i))" >> "$PFILE"; done
mland "$FIX" 601 60 FT_PUSH_FIXED_S=$F GATE_SLEEP=$SLP
lc() { grep -m1 '^LAND-CAP ' <<<"$out"; }
lcv() { tr ' ' '\n' <<<"$(lc)" | sed -n "s/^$1=//p"; }
ok=0
{ [ "$rc" = 0 ] && grep -q '^LANDED pr=601 ' <<<"$out" && [ "$(lcv lim)" = 75 ] && [ "$(lcv push)" = 14 ] && \
  [ "$(lcv 출처)" = p90 ] && [ "$(lcv n)" = 20 ] && [ "$(lcv pre90)" = 54 ] && [ "$(lcv push90)" = 7 ] && \
  [ "$(grep -c . "$TSV")" = 1 ] && ! grep -qE '^REJECT (push 몫 예약|총 마감|gate 가 상한)' <<<"$out"; } && ok=1
ck "⑯ 고친 판 · gate 가 ${SLP}초 씀 → LAND-CAP lim=75(표본 20행) · push 시도 1 · 착지 rc 0" $((1 - ok))
echo "판 1회 ${el}초 · 합계 $SECONDS"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
