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

delete_key() {
  "$PLIST_BUDDY" -c "Delete :$2" "$1" >/dev/null 2>&1 || true
}

reload_agent() {
  local label="$1"
  local plist="$2"
  local attempt=1
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
  launchctl kickstart -k "gui/$UID_NUM/$label" >/dev/null 2>&1 || true
  launchctl print "gui/$UID_NUM/$label" >/dev/null
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
  mkdir -p "$(dirname "$HR_OUT")" "$(dirname "$CPA_OUT")"
  set_key "$HR_PLIST" StandardOutPath "$HR_OUT"
  set_key "$HR_PLIST" StandardErrorPath "$HR_ERR"
  set_key "$CPA_PLIST" StandardOutPath "$CPA_OUT"
  set_key "$CPA_PLIST" StandardErrorPath "$CPA_ERR"
  reload_stack
  printf 'file logs enabled\nheadroom: %s %s\ncliproxy: %s %s\n' "$HR_OUT" "$HR_ERR" "$CPA_OUT" "$CPA_ERR"
}

disable_file_logs() {
  delete_key "$HR_PLIST" StandardOutPath
  delete_key "$HR_PLIST" StandardErrorPath
  delete_key "$CPA_PLIST" StandardOutPath
  delete_key "$CPA_PLIST" StandardErrorPath
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
