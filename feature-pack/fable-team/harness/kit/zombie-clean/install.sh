#!/usr/bin/env bash
# serena-guard·serena-mcp 설치 + 부팅 ensure launchd (R327 · 재부팅 뒤 Serena 공유 서버 자동 기동)
# 사용: bash install.sh [--apply] [--root <메인 루트>]      (기본 dry-run = 할 일만 출력 · 변경 0)
#   --apply : ①serena-guard.sh → ~/.claude/skills/zombie-clean/scripts/ ②serena-mcp.sh → ~/.claude/scripts/ (cp -p)
#             ③com.byz.serena-ensure.plist 렌더(절대경로) → ~/Library/LaunchAgents/ ④launchctl bootstrap (RunAtLoad = 부팅·로그인 때 ensure 1회)
# 멱등: 파일이 이미 같으면 cp 생략 · plist 가 같고 적재돼 있으면 ALREADY. 실 Serena 서버는 건드리지 않는다(기동은 launchd 가 부팅 때).
# 시험 주입: SERENA_INSTALL_HOME(홈 대체) · SERENA_INSTALL_LAUNCHCTL(launchctl 대체) — 실 launchctl·실 홈 0 으로 돌릴 때만 쓴다.
# 종료코드: 0 완료(또는 dry-run) · 2 사용/환경
set -uo pipefail
HERE="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${SERENA_INSTALL_HOME:-$HOME}"
LAUNCHCTL="${SERENA_INSTALL_LAUNCHCTL:-launchctl}"
LABEL="com.byz.serena-ensure"
AGENTS_DIR="$HOME_DIR/Library/LaunchAgents"
PLIST="$AGENTS_DIR/$LABEL.plist"
GUARD_DST="$HOME_DIR/.claude/skills/zombie-clean/scripts/serena-guard.sh"
MCP_DST="$HOME_DIR/.claude/scripts/serena-mcp.sh"
DOMAIN="gui/$(id -u)"
APPLY=0; ROOT=""

die() { local rc="$1"; shift; echo "$*" >&2; exit "$rc"; }
say() { if [ "$APPLY" = 1 ]; then echo "APPLY $*"; else echo "DRY $*"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --root) ROOT="${2:?--root 값 필요}"; shift 2 ;;
    *) die 2 "사용: install.sh [--apply] [--root <메인 루트>]" ;;
  esac
done

if [ -z "$ROOT" ]; then   # 워크트리에서 돌려도 메인 루트(공용 .git 의 부모)를 쓴다
  common="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die 2 "메인 루트를 못 찾음 — --root 로 지정"
  ROOT="$(dirname -- "$common")"
fi
[ -d "$ROOT" ] || die 2 "메인 루트 없음: $ROOT"

place() {  # $1=키트 파일 $2=목적지 — 같으면 생략
  [ -f "$1" ] || die 2 "키트 파일 없음: $1"
  if cmp -s "$1" "$2" 2>/dev/null; then say "same $2"; return; fi
  say "cp -p $1 → $2"
  [ "$APPLY" = 1 ] || return 0
  mkdir -p "$(dirname -- "$2")" && cp -p "$1" "$2" && chmod +x "$2" || die 2 "복사 실패: $2"
}

render_plist() {  # $1=출력 경로
  sed -e "s|__SERENA_MCP__|$MCP_DST|g" -e "s|__ROOT__|$ROOT|g" -e "s|__HOME__|$HOME_DIR|g" \
      "$HERE/com.byz.serena-ensure.plist.template" > "$1"
}

place "$HERE/serena-guard.sh" "$GUARD_DST"
place "$HERE/serena-mcp.sh" "$MCP_DST"

tmp="$(mktemp)"; trap 'rm -rf "$tmp"' EXIT
render_plist "$tmp"
if command -v plutil >/dev/null 2>&1; then plutil -lint "$tmp" >/dev/null || die 2 "plist lint 실패"; fi
loaded=0; "$LAUNCHCTL" print "$DOMAIN/$LABEL" >/dev/null 2>&1 && loaded=1
if cmp -s "$tmp" "$PLIST" 2>/dev/null && [ "$loaded" = 1 ]; then say "ALREADY $LABEL 적재됨 (ensure root=$ROOT)"; exit 0; fi
say "plist $PLIST (ensure root=$ROOT)"
[ "$APPLY" = 1 ] || { say "launchctl bootstrap $DOMAIN $PLIST"; exit 0; }
mkdir -p "$AGENTS_DIR" "$HOME_DIR/.claude/logs" && cp "$tmp" "$PLIST" || die 2 "plist 쓰기 실패"
[ "$loaded" = 1 ] && "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
"$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST" || die 2 "launchctl bootstrap 실패: $PLIST"
echo "INSTALLED $LABEL plist=$PLIST root=$ROOT"
