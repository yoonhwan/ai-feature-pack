#!/usr/bin/env bash
# ft-da-metrics.sh — 하네스 카드별 DA 반송(HOLD)·호출·회차 간격·벽시계·재spawn·범위 항목·30일 되돌림 «전» 값을 한 번에 (r983).
#   읽기 전용 · 게이트 0 · 상태 줄 쓰기 0 · 외부 호출 0. 본체 = 같은 디렉터리 ft_da_metrics.py.
#   인자: [<루트>] [--root R] [--team harness] [--since YYYY-MM-DD]  (그대로 넘긴다)
#   rc: 0 정상 · 3 읽기 실패(«확인 불가» — 0 으로 보이지 않는다) · 2 인자 오류
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BODY="$HERE/ft_da_metrics.py"
[ -f "$BODY" ] || { echo "확인 불가: 본체 없음 $BODY"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "확인 불가: python3 없음"; exit 3; }
exec python3 "$BODY" "$@"
