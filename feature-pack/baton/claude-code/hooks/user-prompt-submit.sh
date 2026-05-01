#!/usr/bin/env bash
# baton user-prompt-submit hook (v1.2.4+)
# sidecar 전용 — lib/handoff.sh의 baton_events_append 사용 (schema 통일)

set -euo pipefail

[[ -n "${BATON_SKIP_HOOKS:-}" ]] && exit 0

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"
[[ -d "$BATON_HOME" ]] || exit 0
[[ -f "$BATON_HOME/lib/handoff.sh" ]] || exit 0

# shellcheck source=../../core/lib/handoff.sh
. "$BATON_HOME/lib/handoff.sh"

_extract_user_message() {
  local raw="$1"
  if command -v jq &>/dev/null && echo "$raw" | jq -e . &>/dev/null 2>&1; then
    echo "$raw" | jq -r '.user_message // .prompt // empty'
  else
    echo "$raw"
  fi
}

_find_handoff_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.baton/handoff" ]]; then
      echo "$dir/.baton/handoff"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

raw_input=""
if ! IFS= read -t 0.5 -r raw_input 2>/dev/null; then
  exit 0
fi

user_msg="$(_extract_user_message "$raw_input")"
[[ -z "$user_msg" ]] && exit 0

handoff_dir=""
handoff_dir="$(_find_handoff_dir 2>/dev/null)" || exit 0

# 2KB cap
truncated="${user_msg:0:2000}"

# baton_events_append 통일 (jq 필수)
if command -v jq &>/dev/null; then
  baton_events_append "$handoff_dir" intent "$truncated" 2>/dev/null || true
fi

exit 0
