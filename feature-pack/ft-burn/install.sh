#!/usr/bin/env bash
# ft-burn 설치 — ~/.local/bin 에 심링크만 만든다. 되돌리기는 uninstall.sh.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${FT_BURN_BIN_DIR:-${CTX_WASTE_BIN_DIR:-$HOME/.local/bin}}"

say() { printf '%s\n' "$*"; }

say "▶ ft-burn 설치"
command -v python3 >/dev/null 2>&1 || { say "  [✗] python3 필요"; exit 2; }
say "  [✓] python3 $(python3 -V 2>&1 | awk '{print $2}')"

mkdir -p "$BIN_DIR"
chmod +x "$PKG_DIR/bin/ft-burn"
ln -sfn "$PKG_DIR/bin/ft-burn" "$BIN_DIR/ft-burn"
say "  [✓] $BIN_DIR/ft-burn → $PKG_DIR/bin/ft-burn"
# alias — 옛 이름(ctx-waste)은 영구 유지한다(오빠 승인 #278848). 부르는 쪽 스크립트를 고치지 않는다.
ln -sfn "$PKG_DIR/bin/ft-burn" "$BIN_DIR/ctx-waste"
say "  [✓] $BIN_DIR/ctx-waste → $PKG_DIR/bin/ft-burn (alias)"

case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) say "  [!] $BIN_DIR 가 PATH 에 없다. 셸 rc 에 추가:"
     say "      export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

say ""
say "설치 완료. 프로젝트 폴더에서:"
say "  ft-burn                 # 최근 3시간 감사"
say "  ft-burn --hours 12      # 12시간"
say "  ft-burn --json          # 기계 판독 (계약 burn.v1 · plan_input)"
say "용량·구독 산정(--capacity·--inventory·--need)은 ft-plan 이 한다."
