#!/usr/bin/env bash
# test_news_html.sh — 뉴스 HTML 모드(r478) 시험 ⓐ~ⓗ (가짜 opencode·가짜 Slack · 실 호출 0) — 본문 = tests/scripts/test_ft_news_html.py
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
exec pytest -q -p no:cacheprovider harness/tests/scripts/test_ft_news_html.py "$@"
