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

# 스냅샷은 «사용자 데이터»다 (세션 복구 정보) — 제거 대상이 아니다.
# 설치본(versions/current)만 지우고 snapshots/ 는 보존한다.
if [ -d "$GLOBAL_BASE" ]; then
  rm -rf "$GLOBAL_BASE/versions" "$GLOBAL_BASE/current"
  printf '  [✓] %s 설치본 제거
' "$GLOBAL_BASE"
  if [ -d "$GLOBAL_BASE/snapshots" ]; then
    printf '  [!] 세션 스냅샷은 보존: %s (%s개)
' "$GLOBAL_BASE/snapshots" \
      "$(find "$GLOBAL_BASE/snapshots" -name 'snapshot-*.json' -type f | wc -l | tr -d ' ')"
    printf '      완전 삭제를 원하면 직접: rm -rf %s
' "$GLOBAL_BASE"
  else
    rmdir "$GLOBAL_BASE" 2>/dev/null || true
  fi
fi

printf '✅ tmuxc 제거 완료 (기존 tmux 세션과 프로젝트 파일은 보존)
'
