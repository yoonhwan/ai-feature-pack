#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEVEL="boundary"
if [[ $# -gt 0 && "${1:-}" != --* ]]; then
  LEVEL="$1"
  shift
fi

exec "$ROOT/runners/context-pressure.sh" --runtime codex-cli --level "$LEVEL" "$@"
