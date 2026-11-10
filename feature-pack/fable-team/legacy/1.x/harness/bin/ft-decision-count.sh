#!/usr/bin/env bash
# ft-decision-count.sh — planner 결정 대기열 한 줄(결정 인터뷰 N건 · 스크립트 N건 · 팀 대기 N건). 본체는 같은 디렉터리 ft_decision_count.py (R214 · 판정 1804).
exec python3 "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft_decision_count.py" "$@"
