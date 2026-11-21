#!/usr/bin/env bash
# test_base_run_r2377_reg.sh — r2377 회귀: r2377 이 손댄 린트·러너의 «기존 시험 그대로» (reentry-lint fail=0 · r1234 시험 러너 ALL PASS)
#   무거워서(≈20초) 반례 파일(test_base_run_r2377.sh) 밖에 둔다 — 시험 1개 70초 상한 여유 · 세계 = tests/lib/r2377_fixture.sh
#   R2377_BIN(기준판 모드)에서도 그대로 돈다 — 회귀는 판에 상관없이 같은 시험이다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/r2377_fixture.sh"
. "$HERE/lib/r2377_cells.sh"

c14; ck "⑭ 기존 린트 시험 그대로 (reentry-lint fail=0 · r1234 ALL PASS)" "$RES" "$MSG"

echo "[시간] 회귀 ⑭ $((SECONDS - T0))초"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit "$fail"
