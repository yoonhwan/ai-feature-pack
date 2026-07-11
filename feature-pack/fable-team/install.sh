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
  project:*)
    PROJ="${TARGET_KIND#project:}"
    case "$PROJ" in
      /*) DEST="$PROJ/.claude/skills/fable-team" ;;
      *) say "usage: install.sh project:/abs/path (절대경로 필수 — 빈 경로/상대경로 거부)"; exit 2 ;;
    esac ;;
  *) say "usage: install.sh [user|project:/abs/path]"; exit 2 ;;
esac

say "[3/3] 스킬 설치 → $DEST"
mkdir -p "$DEST"
# 심링크 가드: DEST(또는 상위 경로)가 레포 소스(skill/)를 가리키는 심링크면 rm -rf가 심링크를
# 통과해 레포 원본을 삭제하고, 곧이은 cp 소스도 사라져 실패한다. 물리 경로(pwd -P) 대조로 방어.
SRC="$PKG_DIR/skill"
dest_real="$(cd "$DEST" 2>/dev/null && pwd -P || true)"
src_real="$(cd "$SRC" 2>/dev/null && pwd -P || true)"
if [ -n "$dest_real" ] && [ "$dest_real" = "$src_real" ]; then
  say "  [✓] $DEST 는 레포 skill/ 를 가리키는 심링크(라이브) — 복사 스킵, 이미 최신 반영됨."
else
  rm -rf "$DEST/references" "$DEST/templates"
  cp "$PKG_DIR/skill/SKILL.md" "$DEST/SKILL.md"
  cp -R "$PKG_DIR/skill/references" "$DEST/references"
  cp -R "$PKG_DIR/skill/templates" "$DEST/templates"
  chmod +x "$DEST/templates/install-gate.sh" "$DEST/templates/hooks/"*.sh 2>/dev/null || true
fi

say "✅ 완료. 다음 단계:"
say "  0) orchestration-gate 설치(프로젝트별): $DEST/templates/install-gate.sh --install <프로젝트>"
say "  1) 새 Claude Code 세션(ultracode 권장)에서 \"fable-team 설치 인터뷰\" 요청"
say "  2) 인터뷰가 브레인 가용성 체크 → 에이전트 .md 생성 → 프로브 검증까지 안내한다"
say "  ⚠ 에이전트 .md 생성/수정 후에는 반드시 새 세션에서 사용 (세션 시작 시 스냅샷 등록)"
