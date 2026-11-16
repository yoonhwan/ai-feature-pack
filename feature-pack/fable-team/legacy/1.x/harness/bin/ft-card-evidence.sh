#!/usr/bin/env bash
# ft-card-evidence.sh — r2087(설계 r1944 §3): D2 좌석(팀 master · 팀장 빈칸이면 planner)이 카드 ref «## 상태» 끝에 `- 세트: <A> · 시험: <test> · 이슈: 0` 1줄만 쓴다.
#   --card <stem> --set <A 40hex> --pr <N> --test "<명령> rc=0" · PR 리포 = cwd · 루트 = env FT_ROOT · A 가 OPEN PR head 의 조상 아님·나노 좌석 = REJECT(쓰기 0)
#   rc 0 = DONE|ALREADY · 1 = REJECT · 2 = usage · 3 = 판정 불가(git·gh·잠금 실패 · 쓰기 0) · 본체 = 같은 폴더 ft_card_evidence.py
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft_card_evidence.py" ] || { echo "판정 불가 ft_card_evidence.py 없음($HERE) rc=1"; exit 3; }
exec python3 "$HERE/ft_card_evidence.py" "$@"
