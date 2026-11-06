#!/usr/bin/env bash
# ctx-waste 제거 — 심링크만 지운다. 저장소 파일은 건드리지 않는다.
set -euo pipefail
BIN_DIR="${CTX_WASTE_BIN_DIR:-$HOME/.local/bin}"
if [ -L "$BIN_DIR/ctx-waste" ] || [ -f "$BIN_DIR/ctx-waste" ]; then
  rm -f "$BIN_DIR/ctx-waste"
  echo "  [✓] 제거: $BIN_DIR/ctx-waste"
else
  echo "  [–] 이미 없음: $BIN_DIR/ctx-waste"
fi
