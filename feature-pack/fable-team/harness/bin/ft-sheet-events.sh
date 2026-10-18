#!/usr/bin/env bash
# ft-sheet-events.sh key|prepare|commit|abort|append|reconcile [--confirm]|pending|gh-state … — 사건 원장 sheet-events.jsonl 훅 (PLAN-status-sheet §3-1). 본체 = ft_sheet_events.py
exec python3 "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft_sheet_events.py" "$@"
