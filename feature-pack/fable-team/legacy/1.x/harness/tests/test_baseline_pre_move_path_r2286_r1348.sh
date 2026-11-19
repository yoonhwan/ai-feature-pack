#!/usr/bin/env bash
# test_baseline_pre_move_path_r2286_r1348.sh — r2286 r1348 기본 몫 — ① 기본 · ⑥ 회귀(r1348 1회 약 20초 → 켬 = _r1348_on · 변이 = _r1348_mut 로 나눔)
#   몸통 = lib/r2286_baseline_fixture.sh(clone --shared 사본 · 원 리포 쓰기 0) · 시험 1개 70초 · 동시 4개 이하 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
. "$HERE/lib/r2286_baseline_fixture.sh" && r2286_setup || exit 1
main_tree
stage 준비
run d $R1348 0; run o $R1348 0 "" "$MT"; wait
stage 실행
default_ok d && ok "① r1348 기본 rc0 · SKIP 1줄 · FAIL 0" || bad "① r1348 기본 rc=$(rc d) SKIP=$(cnt d '^SKIP 기준판 구간(') :: $(grep '^FAIL' "$T/d.log" | head -3)"
in70 d "①"
set_check r1348 d o $R1348
echo "단계별 초:$STAGES (한 회차 합계 $SECONDS 초)"
echo "RESULT fail=$fail"
[ "$fail" = 0 ]
