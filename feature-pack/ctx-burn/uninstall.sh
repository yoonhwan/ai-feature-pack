#!/usr/bin/env bash
# ctx-burn 제거 — 심링크만 지운다. 저장소 파일은 건드리지 않는다. alias(ctx-waste)도 같이 지운다.
set -euo pipefail
BIN_DIR="${CTX_BURN_BIN_DIR:-${CTX_WASTE_BIN_DIR:-$HOME/.local/bin}}"
for name in ctx-burn ctx-waste; do
  if [ -L "$BIN_DIR/$name" ] || [ -f "$BIN_DIR/$name" ]; then
    rm -f "$BIN_DIR/$name"
    echo "  [✓] 제거: $BIN_DIR/$name"
  else
    echo "  [–] 이미 없음: $BIN_DIR/$name"
  fi
done
