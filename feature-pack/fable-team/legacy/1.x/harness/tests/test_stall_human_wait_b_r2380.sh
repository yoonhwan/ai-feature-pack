#!/usr/bin/env bash
# test_stall_human_wait_b_r2380.sh — r2380 뒷 갈래: 기록 유지(F1·F2)·6시간마다 다시 1통(DA H1)·판정 불가·desk 없음·lint 스위치.
#   본문 = tests/scripts/test_stall_human_wait_b_r2380.py (반례 ⑭~⑳ = 7 시험)
#   앞 갈래(⑥~⑬) = test_stall_human_wait_r2380.sh — 15 시험을 한 파일에 두면 70초를 넘어 반 갈래로 나눴다(하드 룰 22)
# 형제 시험(하드 룰 22): _base(기준판 Red) · _mut(변이 M4b·M5~M13) · _regress(정체 감시 기존) · _regress_cards(대기 카드 경로 기존)
# 격리: 임시 리포(bare origin + 체크아웃)·가짜 명부·tmux·mbox·lint — 네트워크 0 · 실 루트 0 · 실 좌석 깨우기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh"
guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"; PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
. "$SC/_r2380_stall_lib.sh"

run_py "$KIT" test_stall_human_wait_b_r2380.py; ck "신판 ⑭~⑳ $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
lap 신판
echo "FAIL=$fail"; [ "$fail" -eq 0 ]
