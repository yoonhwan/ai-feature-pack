#!/usr/bin/env bash
# ctx-waste 설치 — ~/.local/bin 에 심링크만 만든다. 되돌리기는 uninstall.sh.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${CTX_WASTE_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }

say "▶ ctx-waste 설치"
command -v python3 >/dev/null 2>&1 || { say "  [✗] python3 필요"; exit 2; }
say "  [✓] python3 $(python3 -V 2>&1 | awk '{print $2}')"

mkdir -p "$BIN_DIR"
chmod +x "$PKG_DIR/bin/ctx-waste"
ln -sfn "$PKG_DIR/bin/ctx-waste" "$BIN_DIR/ctx-waste"
say "  [✓] $BIN_DIR/ctx-waste → $PKG_DIR/bin/ctx-waste"

case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) say "  [!] $BIN_DIR 가 PATH 에 없다. 셸 rc 에 추가:"
     say "      export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

say ""
say "설치 완료. 프로젝트 폴더에서:"
say "  ctx-waste                 # 최근 3시간 감사"
say "  ctx-waste --hours 12      # 12시간"
say "  ctx-waste --json          # 기계 판독"
