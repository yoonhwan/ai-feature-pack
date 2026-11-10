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

say ""
say "상수 파일: 이 패키지는 자리를 정하지 않는다 — 부르는 쪽이 --inv-file 또는 CTX_PLAN_CAP_FILE 로 준다."
say "  견본 = $PKG_DIR/accounts.env.example (값은 비어 있다. 채우지 않으면 «0순위 문제» 로 멈춘다)"
say "  파일이 없으면 ctx-plan 은 rc3 + 1줄로 끝난다(표·계산 출력 0)."

say ""
say "설치 완료. ctx-burn 측정값을 넣어 돌린다:"
say "  ctx-burn --hours 168 --json > /tmp/burn.json"
say "  ctx-plan --from /tmp/burn.json --inventory     # 0순위 상수 점검 + 크리티컬"
say "  ctx-plan --from /tmp/burn.json --capacity --accounts 5x:5,ultra:5"
say "  ctx-plan --from /tmp/burn.json --need concurrent:40"
