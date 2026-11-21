#!/usr/bin/env bash
# test_base_run_r2377_mut2.sh — r2377 변이 M5~M7: 이름 머리·앞쪽 실행·린트 갈래. 사본만 고치고, 변이마다 원본으로 같은 사례를 한 번 더 돌려 통과하는지 본다(대조)
#   M5 = tmp. 뺀 이름(⑩) · M7 = & + wait 뺀 앞쪽 실행(⑨) · M6 = 린트 갈래 지움(⑪) · 세계 = tests/lib/r2377_fixture.sh · M1~M4 = test_base_run_r2377_mut.sh
#   R2377_BIN(기준판 모드)이면 변이 전체 SKIP — 그 판에 ft-base-run.sh 가 없다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/r2377_fixture.sh"
. "$HERE/lib/r2377_cells.sh"

if [ "$BASE_MODE" = 1 ]; then
  sk "M5~M7" "기준판 모드(R2377_BIN) — ft-base-run.sh 없음"
  echo "(0 failed)"; exit 0
fi
. "$HERE/lib/r2377_mut.sh"

mut M5 'tmp.ftbase.XXXXXX => ftbase.XXXXXX';               ex M5 c10 "⑩"   # 이름 머리에서 tmp. 뺌(--sweep 이 못 줍는다)
mut M7 ') & CHILD=$!; wait "$CHILD"; rc=$? => ); rc=$?';    ex M7 c9 "⑨"    # 앞쪽 실행으로 되돌림(& + wait 뺌 → TERM 이 trap 에 안 닿는다)

mutlint                                                                   # M6: 린트 갈래 지움
LINT_RUN="$MUTD/ft-test-reentry-lint.sh"; c11
if [ "$RES" = 0 ]; then echo "PASS M6 변이(린트 갈래 지움) → ⑪ FAIL"; else echo "FAIL M6 변이인데 ⑪ 이 통과 :: $MSG"; fail=$((fail+1)); fi
LINT_RUN="$BIN/ft-test-reentry-lint.sh"; c11
if [ "$RES" = 1 ]; then echo "PASS M6 원본 대조 → ⑪ 통과"; else echo "FAIL M6 원본 대조인데 ⑪ 실패 :: $MSG"; fail=$((fail+1)); fi

echo "[시간] 변이 M5~M7 $((SECONDS - T0))초"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit "$fail"
