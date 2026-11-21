#!/usr/bin/env bash
# test_stall_human_wait_r2380.sh — r2380 K2·K2b·K3·K4: 6시간 넘은 오빠 대기 = «사람 대기 점검»(팀 master) · 줄이 풀려 지워지면 «사람 대기 풀림»(desk).
#   본문 = tests/scripts/test_stall_human_wait_r2380.py (반례 ⑥~⑬ = 8 시험) + 짝 사본·모드
#   뒷 갈래(⑭~⑳) = test_stall_human_wait_b_r2380.sh — 15 시험을 한 파일에 두면 70초를 넘어 반 갈래로 나눴다(하드 룰 22)
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

run_py "$KIT" test_stall_human_wait_r2380.py; ck "신판 ⑥~⑬ $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
for n in ft_stall_detect.py ft_stall_scan.py; do
  m1="$(stat -f %Lp "$TRK/$n")"; m2="$(stat -f %Lp "$KIT/$n")"; cmp -s "$TRK/$n" "$KIT/$n" && [ "$m1" = "$m2" ]; ck "짝 사본 $n" $?
done
for f in "$HERE/test_stall_human_wait_r2380.sh" "$SC/test_stall_human_wait_r2380.py" "$SC/_r2380_stall_lib.sh" "$SC/_r2380_world.py"; do
  m="$(stat -f %Lp "$f" 2>/dev/null)"; [ "$m" = 644 ]; ck "새 시험 모드 644 $(basename "$f") ($m)" $?
done
lap 신판
echo "FAIL=$fail"; [ "$fail" -eq 0 ]
