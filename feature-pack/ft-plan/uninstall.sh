#!/usr/bin/env bash
# ft-plan 제거 — 심링크만 지운다. 저장소 파일은 건드리지 않는다. alias(ctx-sim)도 같이 지운다.
set -euo pipefail
BIN_DIR="${FT_PLAN_BIN_DIR:-$HOME/.local/bin}"
for name in ft-plan ctx-sim; do
  if [ -L "$BIN_DIR/$name" ] || [ -f "$BIN_DIR/$name" ]; then
    rm -f "$BIN_DIR/$name"
    echo "  [✓] 제거: $BIN_DIR/$name"
  else
    echo "  [–] 이미 없음: $BIN_DIR/$name"
  fi
done
