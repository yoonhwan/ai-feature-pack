#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$PKG_DIR/core/VERSION")"
GLOBAL_BASE="$HOME/.tmuxc"
TARGET="$GLOBAL_BASE/versions/$VERSION"
LOCAL_BIN="$HOME/.local/bin"

say() { printf '%s\n' "$*"; }
missing=0

say "▶ tmuxc $VERSION 설치"
say "[1/5] 사전 요구사항 체크"
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  say "  [✗] bash >= 4 필요"
  missing=$((missing + 1))
fi
for cmd in bash git tmux; do
  if command -v "$cmd" >/dev/null 2>&1; then
    say "  [✓] $cmd"
  else
    say "  [✗] $cmd 누락"
    case "$cmd" in
      tmux) say "      macOS: brew install tmux / Ubuntu: sudo apt install tmux" ;;
      git) say "      macOS: brew install git / Ubuntu: sudo apt install git" ;;
    esac
    missing=$((missing + 1))
  fi
done

if [ "$missing" -gt 0 ]; then
  say "❌ 필수 의존성 ${missing}개 누락. 설치 후 재실행하세요."
  exit 2
fi

say "[2/5] core 설치 → $TARGET"
mkdir -p "$TARGET"
rm -rf "$TARGET/core" "$TARGET/claude-code"
cp -R "$PKG_DIR/core" "$TARGET/core"
cp -R "$PKG_DIR/claude-code" "$TARGET/claude-code"
chmod +x "$TARGET/core/bin/tmuxc"
ln -sfn "$TARGET" "$GLOBAL_BASE/current"
say "  [✓] ~/.tmuxc/current 갱신"

say "[3/5] PATH 링크 → $LOCAL_BIN/tmuxc"
mkdir -p "$LOCAL_BIN"
ln -sfn "$GLOBAL_BASE/current/core/bin/tmuxc" "$LOCAL_BIN/tmuxc"
say "  [✓] ~/.local/bin/tmuxc"

rcfile="$HOME/.zshrc"
[ -f "$rcfile" ] || rcfile="$HOME/.bashrc"
line='export PATH="$HOME/.local/bin:$PATH"'
if printf '%s' ":$PATH:" | grep -q ":$LOCAL_BIN:"; then
  say "  [✓] PATH 이미 활성화됨"
elif [ -f "$rcfile" ] && grep -qF "$line" "$rcfile"; then
  say "  [✓] $rcfile 에 PATH 등록 줄이 이미 있음"
else
  printf '
%s
' "$line" >> "$rcfile"
  say "  [✓] $rcfile 에 PATH 등록 (새 셸부터 적용)"
fi

say "[4/5] Claude Code skill 연결"
if [ -d "$HOME/.claude" ]; then
  mkdir -p "$HOME/.claude/skills"
  skill_target="$HOME/.claude/skills/tmuxc"
  if [ -L "$skill_target" ]; then
    rm -f "$skill_target"
  elif [ -e "$skill_target" ]; then
    backup="$HOME/.claude/skills/tmuxc.backup-$(date +%Y%m%d%H%M%S)"
    mv "$skill_target" "$backup"
    say "  [!] 기존 ~/.claude/skills/tmuxc 백업 → $backup"
  fi
  ln -sfn "$GLOBAL_BASE/current/claude-code/skills/tmuxc" "$skill_target"
  say "  [✓] ~/.claude/skills/tmuxc"
else
  say "  [!] ~/.claude 없음 — CLI만 설치"
fi

say "[5/5] 검증"
"$LOCAL_BIN/tmuxc" --help >/dev/null
"$LOCAL_BIN/tmuxc" list >/dev/null || true
say "✅ tmuxc $VERSION 설치 완료"
say '   smoke: tmuxc open "$PWD" --name TMUXC_SMOKE --agent codex --role worker --dry-run'
