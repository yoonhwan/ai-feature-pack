#!/usr/bin/env bash
# test_base_run_r2377_mut.sh — r2377 변이 M1~M4: ft-base-run.sh 사본만 고쳐 그 사례가 FAIL 하는지, 원본으로 같은 사례를 한 번 더 돌려 통과하는지(대조)
#   사본은 $T/mut 아래에서만 · 실 bin 은 읽기만 · 세계 = tests/lib/r2377_fixture.sh · M5~M7 = test_base_run_r2377_mut2.sh (70초 상한으로 쪼갬)
#   R2377_BIN(기준판 모드)이면 변이 전체 SKIP — 그 판에 ft-base-run.sh 가 없다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/r2377_fixture.sh"
. "$HERE/lib/r2377_cells.sh"

if [ "$BASE_MODE" = 1 ]; then
  sk "M1~M4" "기준판 모드(R2377_BIN) — ft-base-run.sh 없음"
  echo "(0 failed)"; exit 0
fi
. "$HERE/lib/r2377_mut.sh"

mut M1 'if [ "$ARCH_RC" != 0 ]; then => if false; then';  ex M1 c4 "④"    # archive 실패 무시
mut M2 'exit "$rc" => exit 0';                             ex M2 c6 "⑥"    # rc 를 늘 0 으로
mut M3 'reap_dir end => :';                                ex M3 c8 "⑧"    # 끝 rm 지움(trap 만)
mut M4 "trap 'on_signal 15' TERM => :";                    ex M4 c9 "⑨"    # trap 에서 TERM 뺌

echo "[시간] 변이 M1~M4 $((SECONDS - T0))초"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit "$fail"
