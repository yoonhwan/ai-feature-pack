#!/usr/bin/env bash
# baton install.sh — 인터뷰형 자동 설치
# 환경 감지 → multi-version 글로벌 설치 → 각 에이전트별 등록

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PACKAGE_DIR="$SCRIPT_DIR"
BATON_VERSION=$(cat "$PACKAGE_DIR/core/VERSION")
GLOBAL_BASE="$HOME/.baton"
TARGET="$GLOBAL_BASE/versions/$BATON_VERSION"

echo "─────────────────────────────────────────"
echo "🪃 baton $BATON_VERSION installer"
echo "─────────────────────────────────────────"
echo

# ─────────────────────────────────────────
# 1단계: 의존성 체크
# ─────────────────────────────────────────
echo "[1/7] 사전 요구사항 체크..."

_fail_missing() {
  local cmd=$1
  echo "  [✗] $cmd 누락"
  case "$cmd" in
    jq)
      echo "      macOS:  brew install jq"
      echo "      Ubuntu: sudo apt install jq" ;;
    git)
      echo "      macOS:  brew install git"
      echo "      Ubuntu: sudo apt install git" ;;
    tar)
      echo "      macOS:  brew install gnu-tar"
      echo "      Ubuntu: sudo apt install tar" ;;
  esac
}

_missing=0
for _cmd in bash git tar jq; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    _fail_missing "$_cmd"
    _missing=$((_missing + 1))
  else
    echo "  [✓] $_cmd"
  fi
done

# bash 버전 체크 (>= 4)
_bash_major="${BASH_VERSINFO[0]:-0}"
if [[ "$_bash_major" -lt 4 ]]; then
  echo "  [✗] bash >= 4 필요 (현재: ${BASH_VERSION})"
  echo "      macOS:  brew install bash"
  _missing=$((_missing + 1))
else
  echo "  [✓] bash ${BASH_VERSION}"
fi

if [[ "$_missing" -gt 0 ]]; then
  echo
  echo "❌ 필수 의존성 ${_missing}개 누락. 설치 후 재실행하세요."
  exit 2
fi

# ─────────────────────────────────────────
# 2단계: 환경 감지
# ─────────────────────────────────────────
echo
echo "[2/7] 환경 감지..."

declare -A AGENTS=()

if [[ -d "$HOME/.claude" ]]; then
  AGENTS[claude-code]=1
  echo "  [✓] Claude Code 발견"
else
  echo "  [✗] Claude Code 미설치"
fi

if [[ -d "$HOME/.gemini" ]]; then
  AGENTS[gemini]=1
  echo "  [✓] Gemini CLI 발견"
else
  echo "  [✗] Gemini CLI 미설치"
fi

if [[ -d "$HOME/.config/opencode" ]]; then
  AGENTS[opencode]=1
  echo "  [✓] OpenCode 발견"
else
  echo "  [✗] OpenCode 미설치"
fi

if [[ -d "$HOME/.hermes" ]]; then
  AGENTS[hermes]=1
  echo "  [✓] Hermes 발견"
else
  echo "  [✗] Hermes 미설치"
fi

if [[ -d "$HOME/.codex" ]]; then
  AGENTS[codex]=1
  echo "  [✓] Codex CLI / OMX 표면 발견"
fi

if [[ -d "$HOME/.openclaw" ]]; then
  AGENTS[openclaw]=1
  echo "  [⚠] OpenClaw 발견 (수동 등록 필요 — v1.0 제한적 지원)"
fi

if [[ ${#AGENTS[@]} -eq 0 ]]; then
  echo "  [⚠] 감지된 에이전트 없음 — CLI fallback만 설치합니다"
fi

# ─────────────────────────────────────────
# 3단계: multi-version 글로벌 설치
# ─────────────────────────────────────────
echo
echo "[3/7] 글로벌 설치 → $TARGET"

mkdir -p "$TARGET"
cp -r "$PACKAGE_DIR/core/." "$TARGET/"
# harnesses 카탈로그는 v2에서 제거됨. 구버전 패키지 호환을 위해 존재할 때만 복사.
if [[ -d "$PACKAGE_DIR/harnesses" ]]; then
  cp -r "$PACKAGE_DIR/harnesses" "$TARGET/"
fi
chmod +x "$TARGET/bin/baton"

# current 심링
ln -sfn "$TARGET" "$GLOBAL_BASE/current"

echo "  [✓] ~/.baton/versions/$BATON_VERSION/ 설치 완료"
echo "  [✓] ~/.baton/current → versions/$BATON_VERSION/ 심링"

# ─────────────────────────────────────────
# 4단계: PATH 안내
# ─────────────────────────────────────────
echo
echo "[4/7] PATH 등록"

_path_line="export PATH=\"\$HOME/.baton/current/bin:\$PATH\""
_rcfile="$HOME/.zshrc"
[[ -f "$HOME/.bashrc" && ! -f "$HOME/.zshrc" ]] && _rcfile="$HOME/.bashrc"
if echo "$PATH" | grep -q "$HOME/.baton/current/bin"; then
  echo "  [✓] PATH 이미 등록됨"
elif [[ -f "$_rcfile" ]] && grep -Fxq "$_path_line" "$_rcfile"; then
  echo "  [✓] $_rcfile 에 PATH 등록 줄이 이미 있음 (새 셸 시작 또는 source 필요)"
else
  echo "  [⚠] baton이 PATH에 없습니다."
  echo "  다음 줄을 ~/.zshrc 또는 ~/.bashrc 에 추가 권장:"
  echo
  echo "    $_path_line"
  echo
  read -r -p "  자동으로 추가할까요? [y/N] " _ans
  if [[ "${_ans:-N}" =~ ^[Yy]$ ]]; then
    echo "$_path_line" >> "$_rcfile"
    echo "  [✓] $_rcfile 에 추가됨 (새 셸 시작 또는 source 필요)"
  else
    echo "  수동 등록: echo '$_path_line' >> ~/.zshrc"
  fi
fi

# ─────────────────────────────────────────
# 5단계: 에이전트별 등록
# ─────────────────────────────────────────
echo
echo "[5/7] 에이전트별 등록"

# ── Claude Code ──
if [[ "${AGENTS[claude-code]:-0}" == "1" ]]; then
  echo
  echo "  ── Claude Code ──"

  # 슬래시 명령 등록
  mkdir -p "$HOME/.claude/commands/baton"
  cp -r "$PACKAGE_DIR/claude-code/commands/baton/." "$HOME/.claude/commands/baton/"
  echo "  [✓] ~/.claude/commands/baton/ (17개 슬래시 명령)"

  # 스킬 컨텍스트 등록 (심링)
  mkdir -p "$HOME/.claude/skills/baton"
  ln -sfn "$PACKAGE_DIR/claude-code/skills/baton/SKILL.md" "$HOME/.claude/skills/baton/SKILL.md"
  echo "  [✓] ~/.claude/skills/baton/SKILL.md (심링)"

  # 훅 인터뷰
  echo
  echo "  Claude Code 훅 설정 (Enter = 권장값 자동 선택)"
  echo
  echo "  [Q1] 세션 시작 시 paused 알림 + 환경 검증 + lazy prune (SessionStart) [Y/n]"
  read -r _q1; _q1="${_q1:-Y}"
  echo
  echo "  [Q2] 자동 dump 방식:"
  echo "    [a] UserPromptSubmit (권장) — 매 입력마다 캡처"
  echo "    [b] PreCompact만 — 컴팩트 직전만"
  echo "    [c] 비활성화"
  read -r -p "  선택 [a/b/c, 기본=a]: " _q2; _q2="${_q2:-a}"
  echo
  echo "  [Q3] 하네스 검증 (PostToolUse) [Y/n]"
  read -r _q3; _q3="${_q3:-Y}"
  echo
  echo "  [Q4] 보강 dump (PreCompact + SessionEnd) [Y/n]"
  read -r _q4; _q4="${_q4:-Y}"

  # settings.json 백업 + 패치
  _settings="$HOME/.claude/settings.json"
  [[ -f "$_settings" ]] || echo '{}' > "$_settings"
  _backup="$_settings.baton-backup-$(date +%s)"
  cp "$_settings" "$_backup"
  echo
  echo "  [✓] 백업: $_backup"

  _hook_dir="$PACKAGE_DIR/claude-code/hooks"
  _hooks_patch='{}'

  _add_hook() {
    local _event=$1 _script=$2
    _hooks_patch=$(echo "$_hooks_patch" | jq \
      --arg e "$_event" \
      --arg cmd "bash $_script" \
      '.[$e] = (.[$e] // []) + [{hooks: [{type: "command", command: $cmd, timeout: 10000}]}]')
  }

  [[ "$_q1" =~ ^[Yy]$ ]] && _add_hook "SessionStart"      "$_hook_dir/session-start.sh"
  if [[ "$_q2" == "a" ]]; then
    _add_hook "UserPromptSubmit" "$_hook_dir/user-prompt-submit.sh"
  elif [[ "$_q2" == "b" ]]; then
    _add_hook "PreCompact"       "$_hook_dir/pre-compact.sh"
  fi
  [[ "$_q3" =~ ^[Yy]$ ]] && _add_hook "PostToolUse"       "$_hook_dir/post-tool-use.sh"
  if [[ "$_q4" =~ ^[Yy]$ ]]; then
    _add_hook "PreCompact"  "$_hook_dir/pre-compact.sh"
    _add_hook "SessionEnd"  "$_hook_dir/session-end.sh"
  fi

  # 기존 hooks와 딥 머지 (이미 있는 항목 중복 추가 방지)
  _tmpf=$(mktemp)
  jq --argjson patch "$_hooks_patch" '
    .hooks = ((.hooks // {}) | to_entries) as $existing |
    ($patch | to_entries) as $new |
    ($existing + $new |
      group_by(.key) |
      map({key: .[0].key, value: (map(.value) | add)}) |
      from_entries) |
    . as $merged |
    input | .hooks = $merged
  ' "$_backup" "$_backup" > "$_tmpf" 2>/dev/null || \
    jq --argjson patch "$_hooks_patch" '.hooks = ((.hooks // {}) * $patch)' "$_backup" > "$_tmpf"
  mv "$_tmpf" "$_settings"
  echo "  [✓] ~/.claude/settings.json hooks 패치 완료"
fi

# ── Gemini CLI ──
if [[ "${AGENTS[gemini]:-0}" == "1" ]]; then
  echo
  echo "  ── Gemini CLI ──"
  if [[ -d "$PACKAGE_DIR/gemini/commands" ]]; then
    mkdir -p "$HOME/.gemini/commands/baton"
    cp -r "$PACKAGE_DIR/gemini/commands/." "$HOME/.gemini/commands/baton/"
    echo "  [✓] ~/.gemini/commands/baton/ 등록"
  else
    echo "  [⚠] Gemini 어댑터는 v1.1에서 지원 예정"
    echo "      현재: CLI fallback 사용 → baton <cmd>"
    echo "      TODO: $PACKAGE_DIR/gemini/ 디렉토리에 TOML 추가 후 재실행"
  fi
fi

# ── OpenCode ──
if [[ "${AGENTS[opencode]:-0}" == "1" ]]; then
  echo
  echo "  ── OpenCode ──"
  echo "  [⚠] OpenCode 어댑터는 v1.1에서 지원 예정"
  echo "      현재: CLI fallback 사용 → ~/.baton/current/bin/baton <cmd>"
fi

# ── Hermes ──
if [[ "${AGENTS[hermes]:-0}" == "1" ]]; then
  echo
  echo "  ── Hermes ──"
  echo "  [⚠] Hermes 어댑터는 v1.1에서 지원 예정"
  echo "      현재: CLI fallback 사용 → ~/.baton/current/bin/baton <cmd>"
fi

# ── Codex / OpenClaw ──
if [[ "${AGENTS[codex]:-0}" == "1" ]]; then
  echo
  echo "  ── Codex CLI / OMX ──"
  mkdir -p "$HOME/.codex/baton"
  cp "$PACKAGE_DIR/adapters/codex/INSTRUCTIONS.md" "$HOME/.codex/baton/INSTRUCTIONS.md"
  echo "  [✓] Codex adapter guide → ~/.codex/baton/INSTRUCTIONS.md"
  echo "  사용: BATON_AGENT=codex baton <cmd> 또는 OMX 세션에서 baton <cmd>"
fi
if [[ "${AGENTS[openclaw]:-0}" == "1" ]]; then
  echo
  echo "  ── OpenClaw (수동 등록 안내) ──"
  echo "  baton CLI 직접 호출: ~/.baton/current/bin/baton <cmd>"
fi

# ─────────────────────────────────────────
# 6단계: 검증
# ─────────────────────────────────────────
echo
echo "[6/7] 설치 검증..."
if "$GLOBAL_BASE/current/bin/baton" doctor; then
  _doctor_ok=1
else
  _doctor_ok=0
fi

# ─────────────────────────────────────────
# 7단계: 완료 메시지
# ─────────────────────────────────────────
echo
echo "[7/7] 완료"
echo
echo "─────────────────────────────────────────"
if [[ "$_doctor_ok" == "1" ]]; then
  echo "✅ baton $BATON_VERSION 설치 완료"
else
  echo "⚠️  baton $BATON_VERSION 설치됨 (doctor 경고 있음)"
fi
echo "─────────────────────────────────────────"
echo
echo "다음 단계:"
echo "  1. PATH 미등록 시 새 셸 열기 (또는 source ~/.zshrc)"
echo "  2. 워크트리 작업 시작: /baton:wt-create my-feat"
echo "  3. 도움말: /baton:help"
echo
echo "문제 발생 시: ~/.baton/current/bin/baton doctor"
echo
