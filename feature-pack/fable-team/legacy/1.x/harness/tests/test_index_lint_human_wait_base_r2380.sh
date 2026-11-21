#!/usr/bin/env bash
# test_index_lint_human_wait_base_r2380.sh — r2380 기준판(팩 origin/main) 대조: 새 칸이 없던 판은 ①(ts 검사)·③(WARN 줄)에서 FAIL, ②는 PASS.
#   신판이 «기준판에 없던 것» 을 실제로 더했다는 증거 · 형제 시험 = test_index_lint_human_wait_r2380.sh(신판) · _mut(변이) · _regress(회귀).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
. "$HERE/scripts/_r2380_lint_world.sh"
r2380_lint_world "$T" || { echo "FAIL 세계"; exit 1; }

mkdir -p "$T/base"
git -C "$PACK" archive origin/main feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin | tar -x -C "$T/base" 2>/dev/null
BASE="$T/base/feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft-index-lint.sh"
if [ -f "$BASE" ]; then
  B="$(dirname "$BASE")"; rc=0
  c="$(mk '- 선행: 오빠 승인 (master#66 #340166)')"; lint_at "$B" "$c" reject; rc=$?; [ $rc -eq 0 ]; ck "기준판 ① FAIL(옛 판 = ts 검사 없음)" $?
  c="$(mk '- 선행: 오빠 승인 (master#66 #340166)')"; lint_at "$B" "$c" ""; rc=$?; { [ $rc -eq 0 ] && ! echo "$OUT" | grep -q 'thread'; }; ck "기준판 ③ FAIL(WARN 줄 없음)" $?
  c="$(mk '- 선행: 오빠 승인 (thread 1795016460.792199)')"; lint_at "$B" "$c" reject; rc=$?; { [ $rc -eq 0 ] && echo "$OUT" | grep -q '^OK '; }; ck "기준판 ② PASS(회귀 대조)" $?
else
  echo "WARN 기준판 없음(origin/main 에 팩 없음) — 대조 건너뜀"
fi
lap 기준판
echo "fail=$fail"; [ "$fail" -eq 0 ]
