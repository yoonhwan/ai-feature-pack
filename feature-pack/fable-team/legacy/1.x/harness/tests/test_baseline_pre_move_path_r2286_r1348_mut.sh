#!/usr/bin/env bash
# test_baseline_pre_move_path_r2286_r1348_mut.sh — r2286 r1348 변이 몫 — M1 · M2(원본 짝 = _r1348 의 ① · _r1348_on 의 ②)
#   몸통 = lib/r2286_baseline_fixture.sh(clone --shared 사본 · 원 리포 쓰기 0) · 시험 1개 70초 · 동시 4개 이하 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
. "$HERE/lib/r2286_baseline_fixture.sh" && r2286_setup || exit 1
variant $R1348 _r2286_m1_$R1348 '\[ "\$\{FT_TEST_BASELINE:-\}" = 1 \]' '[ "${FT_TEST_BASELINE:-}" != 1 ]'
variant $R1348 _r2286_m2_$R1348 '"\$\{2/legacy\\/1\.x\\//\}"' '"$2"'
stage 준비
run m1 _r2286_m1_$R1348 0; run m2 _r2286_m2_$R1348 1; wait
stage 실행
default_ok m1 && bad "M1 r1348 SKIP 조건 뒤집어도 ① 통과(변이 못 잡음)" || ok "M1 r1348 SKIP 조건 뒤집음 → ① FAIL(rc=$(rc m1) · SKIP $(cnt m1 '^SKIP 기준판 구간(')줄)"
in70 m1 "M1"
baseline_ok m2 && bad "M2 r1348 이동 전 경로 갈래 지워도 ② 통과(변이 못 잡음)" || ok "M2 r1348 이동 전 경로 갈래 제거 → ② FAIL(«사본 못 뜸» $(cnt m2 '사본 못 뜸')줄)"
in70 m2 "M2"
echo "단계별 초:$STAGES (한 회차 합계 $SECONDS 초)"
echo "RESULT fail=$fail"
[ "$fail" = 0 ]
