#!/usr/bin/env bash
set -euo pipefail

RETENTION_DAYS="${HEADROOM_PROXY_LOG_RETENTION_DAYS:-3}"
DEBUG_RETENTION_DAYS="${HEADROOM_DEBUG_LOG_RETENTION_DAYS:-2}"
ERROR_RETENTION_DAYS="${CLIPROXY_ERROR_LOG_RETENTION_DAYS:-7}"
MAX_ACTIVE_MB="${HEADROOM_PROXY_LOG_MAX_ACTIVE_MB:-25}"
DRY_RUN=0

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

remove_old() {
  local dir="$1"
  local days="$2"
  shift 2
  [ -d "$dir" ] || return 0
  if [ "$DRY_RUN" = "1" ]; then
    find "$dir" -type f "$@" -mtime "+$days" -print
  else
    find "$dir" -type f "$@" -mtime "+$days" -delete
  fi
}

truncate_if_large() {
  local file="$1"
  [ -f "$file" ] || return 0
  local size
  size="$(stat -f '%z' "$file" 2>/dev/null || printf 0)"
  local limit=$((MAX_ACTIVE_MB * 1024 * 1024))
  [ "$size" -gt "$limit" ] || return 0
  if [ "$DRY_RUN" = "1" ]; then
    printf 'truncate %s (%s bytes)\n' "$file" "$size"
  else
    : > "$file"
  fi
}

remove_old "$HOME/.headroom/logs" "$RETENTION_DAYS" -name 'proxy.log*'
remove_old "$HOME/.headroom/logs/debug_400" "$DEBUG_RETENTION_DAYS" -name '*.json'
remove_old "$HOME/Library/Logs/headroom" "$RETENTION_DAYS" -name '*.log*'
remove_old "$HOME/Library/Logs/cliproxy" "$RETENTION_DAYS" -name '*.log*'
remove_old "$HOME/.cli-proxy-api/logs" "$ERROR_RETENTION_DAYS" -name '*.log'
remove_old "$HOME/.cli-proxy-api/logs" "$ERROR_RETENTION_DAYS" -name 'error-v1-messages-*'

truncate_if_large "$HOME/.headroom/logs/proxy.log"
truncate_if_large "$HOME/Library/Logs/headroom/proxy.log"
truncate_if_large "$HOME/Library/Logs/headroom/proxy-error.log"
truncate_if_large "$HOME/Library/Logs/cliproxy/proxy.log"
truncate_if_large "$HOME/Library/Logs/cliproxy/proxy-error.log"
