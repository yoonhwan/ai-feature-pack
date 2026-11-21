#!/usr/bin/env bash
# test_index_lint_human_wait_regress_card_r2380.sh — r2380 회귀 나: ft-card-commit 기존 시험 2종(r2278 카드 고침 · r2283 원장).
#   r2380 이 ft-card-commit 의 lint 부름에 한 토큰(FT_LINT_HUMAN_WAIT=reject)을 더했으니 그 길이 그대로인지 본다.
# 형제 시험: test_index_lint_human_wait_regress_r2380.sh(index-lint 기존) · _r2380(신판) · _base · _mut
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
lap() { echo "단계 $1 $((SECONDS-R2380_T0))초"; R2380_T0=$SECONDS; }
reg() { ( cd "$HERE" && timeout 70 bash "$1" >"$T/reg.$1.log" 2>&1 ); RC=$?; LAST="$(tail -1 "$T/reg.$1.log")"; }
for t in test_card_commit_r2278.sh test_card_commit_ledger_r2283.sh; do
  reg "$t"; ck "회귀 $t ($LAST)" $RC
done
lap 회귀
echo "fail=$fail"; [ "$fail" -eq 0 ]
