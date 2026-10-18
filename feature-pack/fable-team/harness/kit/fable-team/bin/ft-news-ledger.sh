#!/usr/bin/env bash
# ft-news-ledger.sh — 오빠 원장 «마지막 발행 뒤 바뀐 줄만» 뉴스 1개 발행 + 원장 갱신 0 판정 알림 (R125 · 판정 1437)
# 변화 0 = 발행 0 · 첫 실행 = 기준선만 · 발행 성공 뒤에만 기준선 갱신. 실행은 ft_news_ledger.py.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/ft_news_ledger.py" run "$@"
