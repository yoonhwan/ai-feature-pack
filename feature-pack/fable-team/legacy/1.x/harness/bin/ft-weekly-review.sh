#!/usr/bin/env bash
# ft-weekly-review.sh — 주간 점검표 2장(planner · 하네스)의 사실 칸을 채우고 두 master 에 `[주간 점검] <경로>` 1통씩 (R131 · 판정 1483·1487)
# 같은 주 재실행 = 파일 덮어쓰기 0 · «재측정» 절만 추가 · 쪽지 0. 도구는 판단 0 — 결정 칸은 비운다. 실행은 ft_weekly_review.py.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/ft_weekly_review.py" "$@"
