#!/usr/bin/env bash
# cairn 설치 — 사용자 레벨 전역 설치 (~/.cairn) + Claude Code 슬래시/스킬 등록.
# 멱등: 재실행 시 versions/<ver> 추가 + current 심링 갱신.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$PKG_DIR/core/VERSION")"
GLOBAL_BASE="$HOME/.cairn"
TARGET="$GLOBAL_BASE/versions/$VERSION"

echo "▶ cairn $VERSION 설치"

# 1) 의존성
command -v python3 >/dev/null || { echo "✘ python3 필요"; exit 1; }
command -v git >/dev/null || { echo "✘ git 필요"; exit 1; }

rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -r "$PKG_DIR/core/." "$TARGET/"
mkdir -p "$TARGET/hooks"
cp -r "$PKG_DIR/claude-code/hooks/." "$TARGET/hooks/"
chmod +x "$TARGET/bin/cairn"
chmod +x "$TARGET/hooks/post-checkout" "$TARGET/hooks/post-merge" "$TARGET/hooks/cairn-auto-progress"
ln -sfn "$TARGET" "$GLOBAL_BASE/current"
echo "  core → $TARGET"
echo "  hooks → $TARGET/hooks"

# 3) Python 의존성 (전용 venv — ruamel.yaml). baton과 달리 cairn은 Python 의존.
if [ ! -d "$GLOBAL_BASE/venv" ]; then
  python3 -m venv "$GLOBAL_BASE/venv"
fi
"$GLOBAL_BASE/venv/bin/pip" install -q --upgrade pip >/dev/null
"$GLOBAL_BASE/venv/bin/pip" install -q -r "$TARGET/requirements.txt"
echo "  venv → $GLOBAL_BASE/venv (ruamel.yaml)"

# 4) PATH 등록
RC="$HOME/.zshrc"; [ -f "$RC" ] || RC="$HOME/.bashrc"
LINE='export PATH="$HOME/.cairn/current/bin:$PATH"'
if ! grep -qF "$LINE" "$RC" 2>/dev/null; then
  echo "$LINE" >> "$RC"
  echo "  PATH → $RC (새 셸부터 적용)"
fi

# 5) Claude Code 슬래시 커맨드 + 스킬
mkdir -p "$HOME/.claude/commands/cairn"
cp -r "$PKG_DIR/claude-code/commands/cairn/." "$HOME/.claude/commands/cairn/"
mkdir -p "$HOME/.claude/skills/cairn"
ln -sfn "$PKG_DIR/claude-code/skills/cairn/SKILL.md" "$HOME/.claude/skills/cairn/SKILL.md"
echo "  claude → ~/.claude/commands/cairn + skills/cairn"

# 6) 검증
if "$GLOBAL_BASE/current/bin/cairn" self-test; then
  echo "✅ cairn $VERSION 설치 완료 — 새 프로젝트에서 'cairn status' 사용"
else
  echo "⚠ self-test 실패 — 설치는 됐으나 검증 경고"; exit 1
fi
