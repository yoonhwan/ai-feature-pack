#!/usr/bin/env bash
# ft-issues-daily.sh [--dry-run] [--date YYYYMMDD]   (r1115 · 매일 00:10 이슈 일일 표 · 읽기 전용 · 쓰기 0)
#   launchd com.byz.ft-issues-daily 가 00:10 에 1회 부른다. 하는 일 = 열린 이슈 전부를 읽어 «일일 표 1장» 을 쓰고
#   planner master·issues master 에 쪽지 2통(본문 다름)을 보낸다. 라벨·배정·닫기·코멘트 쓰기 0 · 좌석 열기 0 · press 0.
#   산출 = <FT_ROOT>/design/teams/issues/daily/TABLE-daily-<YYYYMMDD>.md
#   정지·동결 표식이면 «건너뜀(사유)» 표 1장 · gh 실패면 «판정 불가» 표 + rc≠0 (빈 표로 숨김 0 · 하드 룰 20).
#   gh 호출 = 쪽마다 25초 + 재시도 1 (로컬 하네스 상한 · 판정 4114 · r1395 50건 1쪽). 쪽지 = 하루 2통(planner · issues).
#   r1434: 표를 쓴 «뒤» ft-evolve.sh --gate 로 하루 1회 세대진화 게이트를 돈다(새 크론 0 · 표 실패해도 게이트는 돈다).
#   exit 0 정상 · 5 판정 불가 · 2 usage · 1 표 쓰기 실패. 시험 = tests/test_issues_daily_r1115.sh · test_issues_daily_paging_r1395.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft_issues_daily.py" ] || { echo "REJECT ft_issues_daily.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
command -v python3 >/dev/null || { echo "REJECT python3 없음"; exit 1; }
EVOLVE_ARGS=(--gate)
for a in "$@"; do [ "$a" = "--dry-run" ] && EVOLVE_ARGS=(--dry-run); done
python3 "$HERE/ft_issues_daily.py" "$@"; rc=$?
# r1434: 세대진화 게이트 — 표 결과와 무관하게 1회. 실패해도 표 rc 를 덮지 않는다(게이트 로그만 남긴다).
if [ -x "$HERE/ft-evolve.sh" ] || [ -f "$HERE/ft-evolve.sh" ]; then
  bash "$HERE/ft-evolve.sh" "${EVOLVE_ARGS[@]}" 2>&1 | sed 's/^/[evolve] /' || echo "[evolve] 판정 불가 — ft-evolve.sh rc≠0 (표 결과와 무관)"
fi
exit "$rc"
