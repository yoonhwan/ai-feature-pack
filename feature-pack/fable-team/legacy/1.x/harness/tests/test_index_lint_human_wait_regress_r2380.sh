#!/usr/bin/env bash
# test_index_lint_human_wait_regress_r2380.sh — r2380 회귀 가: ft-index-lint 기존 시험 2종.
#   test_index_lint_conditional.sh = r2380 이전부터 3 FAIL(r984 대응표 없는 옛 시험 카드 · 기준판 lint 로 같은 값 실측) — «늘리지 않았나» 만 본다(기준값 3).
#   test_index_lint.sh 는 21 FAIL(같은 이유 · 44초) 이라 넣지 않는다 — 실측값은 카드 결과에 적는다.
# 형제 시험: test_index_lint_human_wait_regress_card_r2380.sh(ft-card-commit 기존) · _r2380(신판) · _base · _mut
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
lap() { echo "단계 $1 $((SECONDS-R2380_T0))초"; R2380_T0=$SECONDS; }
reg() { ( cd "$HERE" && timeout 70 bash "$1" >"$T/reg.$1.log" 2>&1 ); RC=$?; LAST="$(tail -1 "$T/reg.$1.log")"; }
reg test_index_lint_team_env_r1734.sh; ck "회귀 test_index_lint_team_env_r1734.sh ($LAST)" $RC
reg test_index_lint_conditional.sh; [ "$LAST" = "fail=3" ]; ck "회귀 test_index_lint_conditional.sh 기준값 유지 ($LAST)" $?
lap 회귀
echo "fail=$fail"; [ "$fail" -eq 0 ]
