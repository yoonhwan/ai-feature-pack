#!/usr/bin/env bash
# ft-news-draft.sh [--dry-run] [--out-dir <폴더>] — 이슈 정리 리포트(ISSUES) + 뉴스 초안(DRAFT) 두 장 + planner 에 [뉴스 초안] 1통 (R118a · 판정 1430)
# --dry-run = 쪽지 0. 실행은 ft_news_io.py (수집 ft-board.py collect · Haiku 프록시 Messages 직접).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/ft_news_io.py" "$@"
