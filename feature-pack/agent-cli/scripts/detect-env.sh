#!/usr/bin/env bash
# detect-env.sh — 실행 환경 + 사용 가능 CLI 파악 → "무엇을 바로 쓸 수 있는지" 리포트
# Usage: bash detect-env.sh
# (설치/인증 변경 없음 — 읽기 전용 진단. WSL/Linux/macOS 자동 구분.)
set -uo pipefail
exec </dev/null

# ── OS 판별 ──
OS="unknown"; TAG=""
case "$(uname -s 2>/dev/null)" in
  Darwin) OS="macOS";;
  Linux)
    OS="Linux"
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
      OS="WSL"; TAG="${WSL_DISTRO_NAME:-WSL}"
    fi;;
  MINGW*|MSYS*|CYGWIN*) OS="Windows(git-bash)";;
esac

echo "🖥  환경: ${OS}${TAG:+ ($TAG)} · $(uname -m 2>/dev/null) · shell ${SHELL##*/}"
echo

# ── 런타임 ──
echo "🔧 런타임 (스크립트 동작 필수)"
for r in perl python3; do
  if command -v "$r" >/dev/null 2>&1; then echo "   ✅ $r"; else echo "   ❌ $r — 설치 필요"; fi
done
echo

# ── 에이전트 CLI ──
echo "🤖 에이전트 CLI"
have=(); miss=()
for c in claude codex gemini opencode cursor-agent; do
  if command -v "$c" >/dev/null 2>&1; then echo "   ✅ $c"; have+=("$c"); else echo "   ⬜ $c (미설치)"; miss+=("$c"); fi
done
echo

# ── 판정 ──
if [ ${#have[@]} -ge 1 ]; then
  echo "👉 지금 바로 사용 가능: ${have[*]}"
  echo "   예) bash scripts/selftest.sh ${have[*]}"
else
  echo "👉 아직 사용 가능한 CLI 없음 — 아래 설치 후 다시 실행"
fi
[ ${#miss[@]} -ge 1 ] && echo "   설치 시 추가 가능: ${miss[*]}  → 상세는 cli/install.md"
echo

# ── 환경별 설치 힌트 ──
echo "📦 설치 힌트 (${OS})"
case "$OS" in
  macOS)
    echo "   claude: npm i -g @anthropic-ai/claude-code"
    echo "   codex : npm i -g @openai/codex"
    echo "   gemini: brew install gemini-cli  (또는 npm i -g @google/gemini-cli)"
    echo "   opencode: brew install opencode"
    echo "   cursor-agent: Cursor 설치 시 동봉 (curl https://cursor.com/install | bash)"
    ;;
  WSL|Linux)
    echo "   공통: Node(nvm 또는 apt) + npm 먼저. brew 대신 npm/curl 사용."
    echo "   claude: npm i -g @anthropic-ai/claude-code"
    echo "   codex : npm i -g @openai/codex"
    echo "   gemini: npm i -g @google/gemini-cli"
    echo "   opencode: curl -fsSL https://opencode.ai/install | bash  (또는 npm)"
    echo "   cursor-agent: curl https://cursor.com/install | bash  (Linux 빌드)"
    if [ "$OS" = "WSL" ]; then
      echo "   ⚠️ WSL 주의:"
      echo "      · 로그인(OAuth)이 Windows 브라우저로 열림 — 안 열리면 출력된 URL 수동 복붙"
      echo "      · cursor-agent는 Windows측 Cursor 기반이라 WSL PATH에 없을 수 있음(없으면 selftest가 자동 SKIP)"
      echo "      · perl/python3 없으면: sudo apt update && sudo apt install -y perl python3"
      echo "      · 작업은 WSL 파일시스템(~/) 안에서 — /mnt/c 경로는 느리고 권한 이슈"
    fi
    ;;
  *)
    echo "   현재 OS 미검증 — Linux 기준으로 시도하거나 cli/install.md 참고"
    ;;
esac
echo
echo "ℹ️ 미설치 CLI는 selftest에서 자동 SKIP — 있는 것만으로 바로 시작하면 됩니다."
