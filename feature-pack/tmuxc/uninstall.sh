#!/usr/bin/env bash
set -euo pipefail

GLOBAL_BASE="$HOME/.tmuxc"
LOCAL_LINK="$HOME/.local/bin/tmuxc"
SKILL_LINK="$HOME/.claude/skills/tmuxc"

printf '▶ tmuxc 제거
'

if [ -L "$LOCAL_LINK" ] && readlink "$LOCAL_LINK" | grep -q '\.tmuxc'; then
  rm -f "$LOCAL_LINK"
  printf '  [✓] %s 제거
' "$LOCAL_LINK"
else
  printf '  [!] %s 는 tmuxc 설치본 심링이 아니어서 보존
' "$LOCAL_LINK"
fi

if [ -L "$SKILL_LINK" ] && readlink "$SKILL_LINK" | grep -q '\.tmuxc'; then
  rm -f "$SKILL_LINK"
  printf '  [✓] %s 제거
' "$SKILL_LINK"
else
  printf '  [!] %s 는 tmuxc 설치본 심링이 아니어서 보존
' "$SKILL_LINK"
fi

if [ -d "$GLOBAL_BASE" ]; then
  rm -rf "$GLOBAL_BASE"
  printf '  [✓] %s 제거
' "$GLOBAL_BASE"
fi

printf '✅ tmuxc 제거 완료 (기존 tmux 세션과 프로젝트 파일은 보존)
'
