#!/usr/bin/env bash
# ft-news-publish.sh <POLISHED 파일> [--draft <DRAFT 이름>] — 다듬은 뉴스를 바뀐 것만 Slack 채널에 새 글(최상위 1개)로 발행 + 처리 기록 1줄 (R118b · 판정 1430)
# 같은 판(머리 시각만 다름) = 발행 0 · 다른 판 = 새 글 1개(스레드·답글 0 · 판정 1438). 실행은 ft_news_publish.py.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/ft_news_publish.py" publish "$@"
