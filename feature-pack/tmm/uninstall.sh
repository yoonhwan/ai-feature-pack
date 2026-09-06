#!/usr/bin/env bash
set -euo pipefail

GLOBAL_BASE="$HOME/.tmm"
LOCAL_LINK="$HOME/.local/bin/tmm"
CACHE="${TMPDIR:-/tmp}/tmm-scan-$(id -u).cache"

printf '▶ tmm 제거
'

if [ -L "$LOCAL_LINK" ] && readlink "$LOCAL_LINK" | grep -q '\.tmm'; then
  rm -f "$LOCAL_LINK"
  printf '  [✓] %s 제거
' "$LOCAL_LINK"
else
  printf '  [!] %s 는 tmm 설치본 심링이 아니어서 보존
' "$LOCAL_LINK"
fi

# 설치본(versions/current)만 지운다. categories 는 «사용자 데이터»(카테고리 규칙)라 보존.
if [ -d "$GLOBAL_BASE" ]; then
  rm -rf "$GLOBAL_BASE/versions" "$GLOBAL_BASE/current"
  printf '  [✓] %s 설치본 제거 (versions/current)
' "$GLOBAL_BASE"
  if [ -f "$GLOBAL_BASE/categories" ]; then
    printf '  [!] 카테고리 규칙은 보존: %s
' "$GLOBAL_BASE/categories"
    printf '      완전 삭제를 원하면 직접: rm -rf %s
' "$GLOBAL_BASE"
  else
    rmdir "$GLOBAL_BASE" 2>/dev/null || true
  fi
fi

if [ -f "$CACHE" ]; then
  rm -f "$CACHE"
  printf '  [✓] 스캔 캐시 제거: %s
' "$CACHE"
fi

printf '✅ tmm 제거 완료 (기존 tmux 세션과 카테고리 규칙은 보존)
'
