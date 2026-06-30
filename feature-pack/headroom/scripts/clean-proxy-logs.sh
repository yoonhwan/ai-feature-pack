#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

RETENTION_DAYS="${HEADROOM_LOG_RETENTION_DAYS:-3}"
PROXY_ROTATED_RETENTION_DAYS="${HEADROOM_PROXY_LOG_RETENTION_DAYS:-2}"
PROXY_ROTATED_KEEP="${HEADROOM_PROXY_LOG_KEEP:-2}"
DEBUG_RETENTION_DAYS="${HEADROOM_DEBUG400_RETENTION_DAYS:-1}"
DEBUG_KEEP="${HEADROOM_DEBUG400_KEEP:-10}"
MAX_BYTES="${HEADROOM_LOG_MAX_BYTES:-26214400}"

delete_old() {
  local dir="$1"
  local pattern="$2"
  local days="$3"
  [ -d "$dir" ] || return 0
  if [ "$DRY_RUN" = "1" ]; then
    find "$dir" -type f -name "$pattern" -mtime "+$days" -print
  else
    find "$dir" -type f -name "$pattern" -mtime "+$days" -delete
  fi
}

delete_file() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s\n' "$1"
  else
    rm -f "$1"
  fi
}

prune_count() {
  local dir="$1"
  local pattern="$2"
  local keep="$3"
  [ -d "$dir" ] || return 0
  find "$dir" -type f -name "$pattern" -print0 \
    | xargs -0 stat -f '%m %N' 2>/dev/null \
    | sort -rn \
    | tail -n "+$((keep + 1))" \
    | cut -d ' ' -f 2- \
    | while IFS= read -r file; do
        [ -n "$file" ] && delete_file "$file"
      done
}

truncate_large() {
  local file="$1"
  [ -f "$file" ] || return 0
  local size
  size="$(stat -f '%z' "$file" 2>/dev/null || printf '0')"
  [ "$size" -le "$MAX_BYTES" ] && return 0
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s size=%s truncate\n' "$file" "$size"
  else
    : > "$file"
  fi
}

delete_old "$HOME/.headroom/logs" "proxy.log.*" "$PROXY_ROTATED_RETENTION_DAYS"
delete_old "$HOME/.headroom/logs/debug_400" "*.json" "$DEBUG_RETENTION_DAYS"
delete_old "$HOME/.headroom/logs/codex-wire" "*" "$DEBUG_RETENTION_DAYS"
delete_old "$HOME/Library/Logs/headroom" "*.log*" "$RETENTION_DAYS"
delete_old "$HOME/Library/Logs/cliproxy" "*.log*" "$RETENTION_DAYS"
delete_old "$HOME/.cli-proxy-api/logs" "*.log" "$RETENTION_DAYS"
delete_old "$HOME/.cli-proxy-api/logs" "error-*" "$RETENTION_DAYS"

prune_count "$HOME/.headroom/logs" "proxy.log.*" "$PROXY_ROTATED_KEEP"
prune_count "$HOME/.headroom/logs/debug_400" "*.json" "$DEBUG_KEEP"

truncate_large "$HOME/.headroom/logs/proxy.log"
truncate_large "$HOME/Library/Logs/headroom/proxy.log"
truncate_large "$HOME/Library/Logs/headroom/proxy-error.log"
truncate_large "$HOME/Library/Logs/cliproxy/proxy.log"
truncate_large "$HOME/Library/Logs/cliproxy/proxy-error.log"
