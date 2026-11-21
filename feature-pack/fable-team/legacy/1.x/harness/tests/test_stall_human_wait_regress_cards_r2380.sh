#!/usr/bin/env bash
# test_stall_human_wait_regress_cards_r2380.sh — r2380 회귀: 대기 카드 경로(기준 ref 트리 읽기·명부 밖 좌석) 기존 시험 2종.
#   test_ft_stall_scan_off_roster.py(7) · test_stall_waiting_cards_ref_tree_r1330.py(6) — r2380 이 그 두 길을 안 바꿨다는 증거.
# 형제 시험: test_stall_human_wait_regress_r2380.sh(정체 감시 본체) · _r2380(신판) · _base · _mut
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; SC="$HERE/scripts"; PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
. "$SC/_r2380_stall_lib.sh"
for t in test_ft_stall_scan_off_roster.py test_stall_waiting_cards_ref_tree_r1330.py; do
  run_py "$KIT" "$t"; ck "회귀 $t $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
done
lap 회귀
echo "FAIL=$fail"; [ "$fail" -eq 0 ]
