#!/usr/bin/env bash
set -euo pipefail

# fable-team installer — 스킬 파일 배치까지만 담당.
# 에이전트 .md 생성은 설치 인터뷰(대화형, Claude Code 안)에서 진행된다.
PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_KIND="${1:-user}"   # user | project:<path>

say() { printf '%s\n' "$*"; }

say "▶ fable-team 0.1.0 설치"
say "[1/3] 사전 요구사항 체크"
if ! command -v claude >/dev/null 2>&1; then
  say "  [✗] claude (Claude Code CLI) 누락 — 필수"
  exit 2
fi
say "  [✓] claude"

say "[2/3] 브레인 가용성 프로브 (참고용 — 인터뷰에서 재확인)"
for c in codex cursor-agent gemini; do
  if zsh -ic "command -v $c" >/dev/null 2>&1 || command -v "$c" >/dev/null 2>&1; then
    say "  [✓] $c"
  else
    say "  [–] $c 미가용 → 설치 인터뷰에서 대체 모델 추천됨 (skill/references/brain-availability.md)"
  fi
done

case "$TARGET_KIND" in
  user) DEST="$HOME/.claude/skills/fable-team" ;;
  project:*) DEST="${TARGET_KIND#project:}/.claude/skills/fable-team" ;;
  *) say "usage: install.sh [user|project:/abs/path]"; exit 2 ;;
esac

say "[3/3] 스킬 설치 → $DEST"
mkdir -p "$DEST"
rm -rf "$DEST/references"
cp "$PKG_DIR/skill/SKILL.md" "$DEST/SKILL.md"
cp -R "$PKG_DIR/skill/references" "$DEST/references"

say "✅ 완료. 다음 단계:"
say "  1) 새 Claude Code 세션(ultracode 권장)에서 \"fable-team 설치 인터뷰\" 요청"
say "  2) 인터뷰가 브레인 가용성 체크 → 에이전트 .md 생성 → 프로브 검증까지 안내한다"
say "  ⚠ 에이전트 .md 생성/수정 후에는 반드시 새 세션에서 사용 (세션 시작 시 스냅샷 등록)"
