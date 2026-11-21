#!/usr/bin/env bash
# test_stall_human_wait_regress_b_r2380.sh — r2380 회귀 나: test_ft_stall_scan.py 뒤 절반(19 시험).
#   앞 절반 = test_stall_human_wait_regress_r2380.sh — 39 시험을 한 파일에서 돌리면 부하에 따라 70초를 넘는다(하드 룰 22).
# 형제 시험: _regress_cards(대기 카드 경로 기존) · _r2380(신판) · _b · _base · _mut
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; SC="$HERE/scripts"; PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
. "$SC/_r2380_stall_lib.sh"
( cd "$SC" && timeout 40 python3.11 -m pytest -q -p no:cacheprovider --collect-only test_ft_stall_scan.py 2>/dev/null ) \
  | sed -nE 's/^.*(test_ft_stall_scan\.py::)/\1/p' > "$T/ids"
N="$(wc -l < "$T/ids" | tr -d ' ')"; H=$(( (N + 1) / 2 ))
[ "$N" -ge 20 ] || { echo "FAIL 수집 목록이 짧다($N) — 시험 이름 규칙 확인"; fail=$((fail+1)); }
IDS="$(sed -n "$((H + 1)),\$p" "$T/ids" | tr '\n' ' ')"
[ -n "$IDS" ] || { echo "FAIL 목록 비었다 — 수집 실패"; fail=$((fail+1)); }
(ulimit -u 2000; cd "$SC" && R2380_BIN="$KIT" timeout 70 python3.11 -m pytest -q -p no:cacheprovider $IDS >"$T/py.log" 2>&1)
ck "회귀 test_ft_stall_scan.py 뒤 절반($((N - H)) 시험) $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
lap 회귀
echo "FAIL=$fail"; [ "$fail" -eq 0 ]
