#!/usr/bin/env bash
# ft-evolve.sh — 세대진화(evolve) 하루 1회 게이트 · 스캐폴드 (r1434)
#   새 크론 0 — 기존 00:10 ft-issues-daily 끝에서 --gate 로 1회만 돈다(state/evolution/last-run).
#   모드: --dry-run(기본 · 파일 변경 0) | --apply(후보 파일 + last-run 기록) | --gate(하루 1회 판정)
#   출력 1줄: EVOLVE dry-run date=YYYYMMDD 학습 후보 k · 폐기 후보 m (파일 변경 0)
#   LLM 호출 0 — 규칙 기반 집계만. 모델 판단은 사람이 후보 목록을 보고 한다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft_evolve.py" ] || { echo "REJECT ft_evolve.py 없음: $HERE"; exit 1; }
command -v python3 >/dev/null || { echo "REJECT python3 없음"; exit 1; }
exec python3 "$HERE/ft_evolve.py" "$@"
