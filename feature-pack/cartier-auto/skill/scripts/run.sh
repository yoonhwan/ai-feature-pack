#!/usr/bin/env bash
# cartier-auto 런처 — 스킬 venv(playwright 포함)로 CLI 실행
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 커맨드 구성
COMMAND=("$DIR/cartier_auto.py")
while [[ $# -gt 0 ]]; do
  COMMAND+=("$1"); shift
done

# 설치된 venv 우선, 없으면 현재 python3
PYBIN=""
STATE_DIR="${CARTIER_AUTO_STATE:-$HOME/.local/state/cartier-auto}"
VENV="$STATE_DIR/.venv/bin/python"
if [ -x "$VENV" ]; then
  PYBIN="$VENV"
elif command -v python3 >/dev/null 2>&1; then
  PYBIN="python3"
else
  echo "ERROR: Python 3.11+ 필요" >&2
  exit 2
fi

exec "$PYBIN" "${COMMAND[@]}"
