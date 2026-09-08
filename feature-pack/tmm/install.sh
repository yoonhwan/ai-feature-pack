#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$PKG_DIR/core/VERSION")"
GLOBAL_BASE="$HOME/.tmm"
TARGET="$GLOBAL_BASE/versions/$VERSION"
LOCAL_BIN="$HOME/.local/bin"

say() { printf '%s\n' "$*"; }
missing=0

say "▶ tmm $VERSION 설치 (모바일 SSH용 tmux 좌석 TUI)"
say "[1/5] 사전 요구사항 체크"
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  say "  [✗] bash >= 4 필요 (macOS 기본 bash 3 — brew install bash)"
  missing=$((missing + 1))
fi
for cmd in bash tmux fzf; do
  if command -v "$cmd" >/dev/null 2>&1; then
    say "  [✓] $cmd"
  else
    say "  [✗] $cmd 누락"
    case "$cmd" in
      tmux) say "      macOS: brew install tmux / Ubuntu: sudo apt install tmux" ;;
      fzf)  say "      macOS: brew install fzf  / Ubuntu: sudo apt install fzf (>=0.54 필요 — 자동 갱신·벨)" ;;
    esac
    missing=$((missing + 1))
  fi
done
if command -v tmuxc >/dev/null 2>&1; then
  say "  [✓] tmuxc (선택 — send 도달확인·save 연동)"
else
  say "  [!] tmuxc 없음 (선택) — send 는 tmux send-keys 폴백, 'tmm save' 불가. feature-pack/tmuxc 설치 권장"
fi

if [ "$missing" -gt 0 ]; then
  say "❌ 필수 의존성 ${missing}개 누락. 설치 후 재실행하세요."
  exit 2
fi

say "[2/5] core 설치 → $TARGET"
mkdir -p "$TARGET"
rm -rf "$TARGET/core"
cp -R "$PKG_DIR/core" "$TARGET/core"
chmod +x "$TARGET/core/bin/tmm" "$TARGET/core/libexec/"*.sh
ln -sfn "$TARGET" "$GLOBAL_BASE/current"
say "  [✓] ~/.tmm/current 갱신"

say "[3/5] PATH 링크 → $LOCAL_BIN/tmm"
mkdir -p "$LOCAL_BIN"
if [ -e "$LOCAL_BIN/tmm" ] && [ ! -L "$LOCAL_BIN/tmm" ]; then
  backup="$LOCAL_BIN/tmm.backup-$(date +%Y%m%d%H%M%S)"
  mv "$LOCAL_BIN/tmm" "$backup"
  say "  [!] 기존 $LOCAL_BIN/tmm 백업 → $backup"
fi
ln -sfn "$GLOBAL_BASE/current/core/bin/tmm" "$LOCAL_BIN/tmm"
say "  [✓] ~/.local/bin/tmm"

rcfile="$HOME/.zshrc"
[ -f "$rcfile" ] || rcfile="$HOME/.bashrc"
line='export PATH="$HOME/.local/bin:$PATH"'
if printf '%s' ":$PATH:" | grep -q ":$LOCAL_BIN:"; then
  say "  [✓] PATH 이미 활성화됨"
elif [ -f "$rcfile" ] && grep -qF "$line" "$rcfile"; then
  say "  [✓] $rcfile 에 PATH 등록 줄이 이미 있음"
else
  printf '\n%s\n' "$line" >> "$rcfile"
  say "  [✓] $rcfile 에 PATH 등록 (새 셸부터 적용)"
fi
# ★alias 충돌 경고★: zshrc 에 alias tm/tmm 이 있으면 우리 바이너리보다 우선된다.
if [ -f "$HOME/.zshrc" ] && grep -qE "^\s*alias tmm=" "$HOME/.zshrc"; then
  say "  [✗] ~/.zshrc 에 'alias tmm=' 이 있어 tmm 실행이 가로채집니다 — alias 제거 필요"
fi

say "[4/5] 카테고리 규칙"
if [ -f "$GLOBAL_BASE/categories" ]; then
  say "  [✓] $GLOBAL_BASE/categories 유지 (기존 규칙)"
else
  cp "$PKG_DIR/core/categories.example" "$GLOBAL_BASE/categories"
  say "  [✓] $GLOBAL_BASE/categories 생성 (예시 — 세션명 접두에 맞게 편집)"
fi

say "[5/5] 검증"
"$LOCAL_BIN/tmm" doctor || true
say "✅ tmm $VERSION 설치 완료"
say '   smoke:  tmm ls        (텍스트 목록)   /   tmm  (TUI)'
say '   모바일: Termius 호스트의 Startup command 에 tmm — 접속 즉시 좌석 피커'
