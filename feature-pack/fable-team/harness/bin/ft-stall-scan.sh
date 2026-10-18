#!/usr/bin/env bash
# ft-stall-scan.sh [--dry-run]   (R320b · 오빠 판정 2170 «한 세션이라도 멈춰 있으면 하네스 전체 정지»)
#   멈춤 4종을 숫자로 센다 — a 대기 카드 있는데 master IDLE · b 선언 뒤 IDLE · c 정책 정지 · d 답 기다리며 3분+ — 그리고 찾은 그 실행에서 처리한다(보고만 하는 경로 0).
#   출력 1줄째 `stall=N a=.. b=.. c=.. d=.. seats=.. ts=..` · 그 뒤 좌석별 1줄. 로그 `.fable-team/state/stall-scan.log`(마지막 줄 = 요약 · 뉴스가 읽는다).
#   같은 멈춤을 처리 뒤 다음 실행에도 또 감지하면 ft-penalty.sh on (판정·한계 = ft_stall_scan.py 머리). --dry-run = 처리·기록 0.
#   launchd com.byz.ft-stall-scan 이 120초마다 1회 실행(상시 프로세스 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft_stall_scan.py" ] && [ -f "$HERE/ft_stall_detect.py" ] && [ -f "$HERE/ft_penalty.py" ] || { echo "REJECT ft_stall_*.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
exec python3 "$HERE/ft_stall_scan.py" "$@"
