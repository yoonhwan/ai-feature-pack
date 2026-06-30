#!/usr/bin/env bash
set -euo pipefail

UID_NUM="$(id -u)"
HR_PLIST="$HOME/Library/LaunchAgents/com.headroom.proxy.plist"
CPA_PLIST="$HOME/Library/LaunchAgents/com.cliproxy.api.plist"
HR_LABEL="com.headroom.proxy"
CPA_LABEL="com.cliproxy.api"
HR_OUT="$HOME/Library/Logs/headroom/proxy.log"
HR_ERR="$HOME/Library/Logs/headroom/proxy-error.log"
CPA_OUT="$HOME/Library/Logs/cliproxy/proxy.log"
CPA_ERR="$HOME/Library/Logs/cliproxy/proxy-error.log"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

usage() {
  printf 'usage: %s on|off|status|tail\n' "$0"
  printf '       HEADROOM_FILE_LOGS_FORCE=1 %s on|off   # restart live stack anyway\n' "$0"
}

key_exists() {
  "$PLIST_BUDDY" -c "Print :$2" "$1" >/dev/null 2>&1
}

set_key() {
  if key_exists "$1" "$2"; then
    "$PLIST_BUDDY" -c "Set :$2 $3" "$1" >/dev/null
  else
    "$PLIST_BUDDY" -c "Add :$2 string $3" "$1" >/dev/null
  fi
}

set_env_key() {
  if ! key_exists "$1" EnvironmentVariables; then
    "$PLIST_BUDDY" -c "Add :EnvironmentVariables dict" "$1" >/dev/null
  fi
  if "$PLIST_BUDDY" -c "Print :EnvironmentVariables:$2" "$1" >/dev/null 2>&1; then
    "$PLIST_BUDDY" -c "Set :EnvironmentVariables:$2 $3" "$1" >/dev/null
  else
    "$PLIST_BUDDY" -c "Add :EnvironmentVariables:$2 string $3" "$1" >/dev/null
  fi
}

delete_key() {
  "$PLIST_BUDDY" -c "Delete :$2" "$1" >/dev/null 2>&1 || true
}

logs_enabled() {
  local hr_out
  local hr_err
  local cpa_out
  local cpa_err
  hr_out="$("$PLIST_BUDDY" -c 'Print :StandardOutPath' "$HR_PLIST" 2>/dev/null || true)"
  hr_err="$("$PLIST_BUDDY" -c 'Print :StandardErrorPath' "$HR_PLIST" 2>/dev/null || true)"
  cpa_out="$("$PLIST_BUDDY" -c 'Print :StandardOutPath' "$CPA_PLIST" 2>/dev/null || true)"
  cpa_err="$("$PLIST_BUDDY" -c 'Print :StandardErrorPath' "$CPA_PLIST" 2>/dev/null || true)"
  [ -n "$hr_out$hr_err$cpa_out$cpa_err" ]
}

reload_agent() {
  local label="$1"
  local plist="$2"
  local attempt=1
  plutil -lint "$plist" >/dev/null
  launchctl bootout "gui/$UID_NUM/$label" >/dev/null 2>&1 || true
  while launchctl print "gui/$UID_NUM/$label" >/dev/null 2>&1; do
    if [ "$attempt" -ge 10 ]; then
      break
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  attempt=1
  while ! launchctl bootstrap "gui/$UID_NUM" "$plist"; do
    if [ "$attempt" -ge 12 ]; then
      printf 'failed to bootstrap %s from %s\n' "$label" "$plist" >&2
      return 1
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  launchctl enable "gui/$UID_NUM/$label" >/dev/null 2>&1 || true
  launchctl print "gui/$UID_NUM/$label" >/dev/null
}

active_stack_connections() {
  lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null \
    | awk '$9 ~ /:(8790|8317)(->|$)/ { print }'
}

require_restart_window() {
  if [ "${HEADROOM_FILE_LOGS_FORCE:-0}" = "1" ]; then
    return 0
  fi
  if active_stack_connections | grep -q .; then
    printf 'refusing to restart proxy stack while active connections exist.\n' >&2
    printf 'This prevents Claude Code ConnectionRefused stalls during live work.\n' >&2
    printf 'Wait for sessions to go idle, or run with HEADROOM_FILE_LOGS_FORCE=1 for incident capture.\n' >&2
    return 1
  fi
}

wait_http() {
  local url="$1"
  local seconds="$2"
  local elapsed=0
  while [ "$elapsed" -lt "$seconds" ]; do
    curl -sf -m2 "$url" >/dev/null 2>&1 && return 0
    elapsed=$((elapsed + 1))
    sleep 1
  done
  printf 'timeout waiting for %s\n' "$url" >&2
  return 1
}

reload_stack() {
  reload_agent "$CPA_LABEL" "$CPA_PLIST"
  wait_http "http://127.0.0.1:8317/v1/models" 25
  reload_agent "$HR_LABEL" "$HR_PLIST"
  wait_http "http://127.0.0.1:8790/health" 60
}

enable_file_logs() {
  if logs_enabled; then
    printf 'file logs already enabled\n'
    print_status
    return 0
  fi
  require_restart_window
  mkdir -p "$(dirname "$HR_OUT")" "$(dirname "$CPA_OUT")"
  set_env_key "$HR_PLIST" HEADROOM_FILE_LOGGING off
  set_env_key "$HR_PLIST" HEADROOM_LOG_FILE /dev/stdout
  set_key "$HR_PLIST" StandardOutPath "$HR_OUT"
  set_key "$HR_PLIST" StandardErrorPath "$HR_ERR"
  set_key "$CPA_PLIST" StandardOutPath "$CPA_OUT"
  set_key "$CPA_PLIST" StandardErrorPath "$CPA_ERR"
  reload_stack
  printf 'file logs enabled\nheadroom: %s %s\ncliproxy: %s %s\n' "$HR_OUT" "$HR_ERR" "$CPA_OUT" "$CPA_ERR"
}

disable_file_logs() {
  if ! logs_enabled; then
    set_env_key "$HR_PLIST" HEADROOM_FILE_LOGGING off
    set_env_key "$HR_PLIST" HEADROOM_LOG_FILE /dev/stdout
    printf 'file logs already disabled\n'
    return 0
  fi
  set_env_key "$HR_PLIST" HEADROOM_FILE_LOGGING off
  set_env_key "$HR_PLIST" HEADROOM_LOG_FILE /dev/stdout
  delete_key "$HR_PLIST" StandardOutPath
  delete_key "$HR_PLIST" StandardErrorPath
  delete_key "$CPA_PLIST" StandardOutPath
  delete_key "$CPA_PLIST" StandardErrorPath
  if [ "${HEADROOM_FILE_LOGS_FORCE:-0}" != "1" ] && active_stack_connections | grep -q .; then
    printf 'file logs disabled in LaunchAgent plists; active processes keep current file descriptors until the next idle restart.\n'
    printf 'No proxy restart performed because live connections exist.\n'
    return 0
  fi
  reload_stack
  printf 'file logs disabled\n'
}

print_status() {
  for item in "$HR_PLIST:$HR_LABEL" "$CPA_PLIST:$CPA_LABEL"; do
    plist="${item%%:*}"
    label="${item##*:}"
    out="$("$PLIST_BUDDY" -c 'Print :StandardOutPath' "$plist" 2>/dev/null || true)"
    err="$("$PLIST_BUDDY" -c 'Print :StandardErrorPath' "$plist" 2>/dev/null || true)"
    if [ -n "$out$err" ]; then
      printf '%s: file logs on stdout=%s stderr=%s\n' "$label" "${out:-none}" "${err:-none}"
    else
      printf '%s: file logs off\n' "$label"
    fi
  done
}

tail_logs() {
  touch "$HR_OUT" "$HR_ERR" "$CPA_OUT" "$CPA_ERR"
  tail -n 120 -F "$HR_OUT" "$HR_ERR" "$CPA_OUT" "$CPA_ERR"
}

case "${1:-}" in
  on) enable_file_logs ;;
  off) disable_file_logs ;;
  status) print_status ;;
  tail) tail_logs ;;
  *) usage; exit 2 ;;
esac
