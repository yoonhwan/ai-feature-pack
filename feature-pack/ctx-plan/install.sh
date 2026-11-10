#!/usr/bin/env bash
# ctx-plan 설치 — ~/.local/bin 에 심링크만 만든다. 되돌리기는 uninstall.sh.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${CTX_PLAN_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }

say "▶ ctx-plan 설치"
command -v python3 >/dev/null 2>&1 || { say "  [✗] python3 필요"; exit 2; }
say "  [✓] python3 $(python3 -V 2>&1 | awk '{print $2}')"

mkdir -p "$BIN_DIR"
chmod +x "$PKG_DIR/bin/ctx-plan"
ln -sfn "$PKG_DIR/bin/ctx-plan" "$BIN_DIR/ctx-plan"
say "  [✓] $BIN_DIR/ctx-plan → $PKG_DIR/bin/ctx-plan"

if [ ! -f "$HOME/.claude/fable-team/state/capacity/accounts.env" ] \
   && [ ! -f "$PWD/.fable-team/state/capacity/accounts.env" ]; then
  say "  [!] 상수 파일이 없다 — 견본을 채워 놓아라:"
  say "      mkdir -p .fable-team/state/capacity && cp $PKG_DIR/accounts.env.example .fable-team/state/capacity/accounts.env"
fi

say ""
say "설치 완료. ctx-burn 측정값을 넣어 돌린다:"
say "  ctx-burn --hours 168 --json > /tmp/burn.json"
say "  ctx-plan --from /tmp/burn.json --inventory     # 0순위 상수 점검 + 크리티컬"
say "  ctx-plan --from /tmp/burn.json --capacity --accounts 5x:5,ultra:5"
say "  ctx-plan --from /tmp/burn.json --need concurrent:40"
