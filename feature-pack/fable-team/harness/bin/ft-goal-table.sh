#!/usr/bin/env bash
# ft-goal-table.sh [render] | check <본문 파일|-> [--block-only] — 자율 골 표(A6) 렌더 + 판정기 (R362). 실행은 ft_goal_table.py.
# 상태 칸 = planner 원장 `## 메인 골 6줄` 표를 행 순번으로 자동 읽음(env FT_GOAL_A6_LEDGER · R371).
# render 출력 = 마커 2줄 사이 표 1개(≤1600B) · check rc 0 = GOAL-OK · rc 3 = REJECT 골 없음 · 정본 이상 = ERROR rc 1.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "${1:-}" = render ] && shift
[ "${1:-}" = notify ] && exec python3 "$HERE/ft_goal_gate.py" "$@"   # notify <루트> <진입점> <사유> — 무장 거절 planner [긴급] 1통(다른 프로세스용 · 10분 중복 억제)
exec python3 "$HERE/ft_goal_table.py" "$@"
