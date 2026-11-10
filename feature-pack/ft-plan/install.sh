#!/usr/bin/env bash
# ft-plan 설치 — ~/.local/bin 에 심링크만 만든다. 되돌리기는 uninstall.sh.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${FT_PLAN_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }

say "▶ ft-plan 설치"
command -v python3 >/dev/null 2>&1 || { say "  [✗] python3 필요"; exit 2; }
say "  [✓] python3 $(python3 -V 2>&1 | awk '{print $2}')"

mkdir -p "$BIN_DIR"
chmod +x "$PKG_DIR/bin/ft-plan"
ln -sfn "$PKG_DIR/bin/ft-plan" "$BIN_DIR/ft-plan"
say "  [✓] $BIN_DIR/ft-plan → $PKG_DIR/bin/ft-plan"
# alias — 옛 이름(ctx-sim)은 영구 유지한다(오빠 승인 #278848).
ln -sfn "$PKG_DIR/bin/ft-plan" "$BIN_DIR/ctx-sim"
say "  [✓] $BIN_DIR/ctx-sim → $PKG_DIR/bin/ft-plan (alias)"

if [ ! -f "$HOME/.claude/fable-team/state/capacity/accounts.env" ] \
   && [ ! -f "$PWD/.fable-team/state/capacity/accounts.env" ]; then
  say "  [!] 상수 파일이 없다 — 견본을 채워 놓아라:"
  say "      mkdir -p .fable-team/state/capacity && cp $PKG_DIR/accounts.env.example .fable-team/state/capacity/accounts.env"
fi

say ""
say "설치 완료. ft-burn 측정값을 넣어 돌린다:"
say "  ft-burn --hours 168 --json > /tmp/burn.json"
say "  ft-plan --from /tmp/burn.json --inventory     # 0순위 상수 점검 + 크리티컬"
say "  ft-plan --from /tmp/burn.json --capacity --accounts 5x:5,ultra:5"
say "  ft-plan --from /tmp/burn.json --need concurrent:40"
