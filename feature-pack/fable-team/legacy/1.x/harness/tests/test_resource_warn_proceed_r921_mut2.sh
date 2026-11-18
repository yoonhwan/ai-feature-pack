#!/usr/bin/env bash
# test_resource_warn_proceed_r921_mut2.sh — r921 변이2 1개(r2225 · 몸 = lib/r921_mut.sh · 판정 = DA⑥ r1 «전체 시험 재실행»).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/r921_mut.sh"
r921_mut 2
echo "fail=$fail"; [ $fail -eq 0 ]
