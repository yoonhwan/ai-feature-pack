#!/usr/bin/env bash
# install.sh — code-intel 제네릭 설치/랜딩 (claude · codex · opencode · pi · hermes)
#   · 바이너리(probe/tilth[/pylsp]) 보장
#   · 스킬 정본을 각 하네스 스킬 루트에 심링크
#   · ~/.local/bin/ci 단일 진입점 생성
#   · idempotent. `--check` 는 변경 없이 진단만.
set -uo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${CI_BIN_DIR:-$HOME/.local/bin}"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

ok=0; fail=0
step() { printf '  %-38s %s\n' "$1" "$2"; }
say()  { printf '%s\n' "$*"; }

mkdir -p "$BIN_DIR"; PATH="$BIN_DIR:$PATH"

# ---- 1. 바이너리 -----------------------------------------------------------
ensure_probe() {
  command -v probe >/dev/null 2>&1 && { step "probe" "$(probe --version 2>/dev/null | head -1)"; return; }
  [ "$CHECK" = 1 ] && { step "probe" "MISSING"; fail=$((fail+1)); return; }
  arch="$(uname -m)"; case "$arch" in arm64|aarch64) a="aarch64-apple-darwin" ;; *) a="x86_64-apple-darwin" ;; esac
  url="https://github.com/probelabs/probe/releases/download/v0.6.0-rc342/probe-v0.6.0-rc342-${a}.tar.gz"
  say "  probe 설치 중… ($a)"
  if curl -fsSL -o /tmp/ci-probe.tgz "$url" && tar xzf /tmp/ci-probe.tgz -C /tmp 2>/dev/null; then
    cp "/tmp/probe-v0.6.0-rc342-${a}/probe" "$BIN_DIR/probe" && rm -rf /tmp/ci-probe.tgz "/tmp/probe-v0.6.0-rc342-${a}"
    step "probe" "$(probe --version 2>/dev/null | head -1)  (신규 설치)"
  else step "probe" "FAILED — references/probe.md 수동 설치"; fail=$((fail+1)); fi
}

ensure_tilth() {
  command -v tilth >/dev/null 2>&1 && { step "tilth" "$(tilth --version 2>/dev/null | head -1)"; return; }
  [ "$CHECK" = 1 ] && { step "tilth" "MISSING"; fail=$((fail+1)); return; }
  if command -v npx >/dev/null 2>&1; then
    say "  tilth 설치 중… (npx 캐시 → $BIN_DIR 로 복사, Node 상주 없음)"
    npx -y tilth --version >/dev/null 2>&1
    found="$(ls -t "$HOME"/.npm/_npx/*/node_modules/tilth/bin/tilth 2>/dev/null | head -1)"
    if [ -n "$found" ]; then cp "$found" "$BIN_DIR/tilth"
      step "tilth" "$(tilth --version 2>/dev/null) (신규 설치)"
    else step "tilth" "FAILED — cargo install tilth"; fail=$((fail+1)); fi
  elif command -v cargo >/dev/null 2>&1; then
    cargo install tilth >/dev/null 2>&1 && step "tilth" "$(tilth --version 2>/dev/null) (cargo)" || { step "tilth" "FAILED"; fail=$((fail+1)); }
  else step "tilth" "MISSING (npx/cargo 없음)"; fail=$((fail+1)); fi
}

ensure_pylsp() {
  command -v pylsp >/dev/null 2>&1 && { step "pylsp(선택)" "$(pylsp --version 2>/dev/null | head -1)"; return; }
  step "pylsp(선택)" "없음 — 'ci refs' python 사용 시 필요: uv tool install python-lsp-server"
}

# ---- 2. 스킬 랜딩 (하네스 자동 감지) --------------------------------------
land() { # $1=루트  $2=하네스명
  local root="$1" name="$2" target
  [ -d "$root" ] || { step "$name" "스킵(디렉터리 없음: $root)"; return; }
  target="$root/code-intel"
  if [ "$target" = "$SKILL_DIR" ]; then
    step "$name" "OK (정본 위치)"
  elif [ -L "$target" ] && [ "$(cd "$target" 2>/dev/null && pwd -P)" = "$(cd "$SKILL_DIR" && pwd -P)" ]; then
    step "$name" "OK (심링크)"
  elif [ -e "$target" ]; then
    step "$name" "이미 존재(심링크 아님) — 수동 확인: $target"; fail=$((fail+1)); return
  elif [ "$CHECK" = 1 ]; then
    step "$name" "미랜딩 ($target)"; fail=$((fail+1)); return
  else
    ln -sfn "$SKILL_DIR" "$target" && step "$name" "랜딩 (심링크)"
  fi
}

say "== code-intel install${CHECK:+ }$([ "$CHECK" = 1 ] && echo ' (check only)') =="
say "-- 바이너리"
ensure_probe; ensure_tilth; ensure_pylsp

say "-- 스킬 랜딩 (정본: $SKILL_DIR)"
land "$HOME/.claude/skills"         "claude"
land "$HOME/.agents/skills"          "pi/hermes"
land "$HOME/.codex/skills"           "codex"
land "$HOME/.config/opencode/skills" "opencode"

say "-- 단일 진입점"
if [ "$CHECK" = 0 ]; then ln -sfn "$SKILL_DIR/scripts/ci" "$BIN_DIR/ci"; fi
if command -v ci >/dev/null 2>&1; then step "ci" "$(command -v ci)"
else step "ci" "MISSING ($BIN_DIR/ci)"; fail=$((fail+1)); fi

say "-- 진단"
"$SKILL_DIR/scripts/ci" doctor 2>&1 | sed 's/^/  /'

echo
if [ "$fail" = 0 ]; then say "RESULT: OK — 4개 하네스에서 동일하게 'ci …' 사용 가능"
else say "RESULT: $fail 항목 확인 필요 (위 step 참조)"; fi
[ "$CHECK" = 1 ] && [ "$fail" != 0 ] && exit 1 || exit 0
