#!/usr/bin/env bash
# ft-penalty.sh on [--reason <사유>]|status|resume <팀>|off|check [<팀>]   (R320b · 오빠 판정 2170)
#   오빠 원문: «한 세션이라도 멈춰 있으면 하네스 전체 정지다 … 전 세션 정지 때려 … 완전히 해결될 때까지 멈춰서 뚫을 때 뚫고 다시 시작하고 하나씩 팀 정정하고 다시 간다»
#   on     : <리포 루트>/.fable-team/state/PENALTY_STOP 생성 + 전 팀 master 에 [페널티] 1통(--urgent)
#   resume : 그 팀의 마지막 stall-scan(10분 안)에 b·d·c 가 0 일 때만 «재개됨» 칸에 추가 · 전 팀 재개면 파일 삭제 (a 는 정지 중 정의상 남아 뺀다 — ft_penalty.py 머리)
#   check  : nano·role spawn 이 부른다 — 정지 중이고 그 팀이 재개 전이면 `REJECT penalty …` rc 3 (successor 는 안 부른다)
#   off    : 파일 삭제(사람 손 · 오빠 판단) · 자동 발동 끄기 = env FT_STALL_PENALTY_AUTO=0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft_penalty.py" ] || { echo "REJECT ft_penalty.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
exec python3 "$HERE/ft_penalty.py" "$@"
