#!/bin/zsh
# 경유 조건 (모두 충족 시 8790):
#   1) 프록시 health OK
#   2) always-route ON (~/.headroom/always-route) 또는 enabled-projects 등록
#   3) disabled-projects에 현재 root 없음

REGISTRY="$HOME/.headroom/enabled-projects.json"
DISABLED="$HOME/.headroom/disabled-projects.json"
ALWAYS_ROUTE="$HOME/.headroom/always-route"
PROXY_URL="http://localhost:8790"

GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
PROJECT_ROOT="$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || pwd)"

_in_list() {
  local list_file="$1"
  [ -f "$list_file" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$list_file" "$PROJECT_ROOT" <<'PY' 2>/dev/null
import json, sys, os
try:
    reg = json.load(open(sys.argv[1]))
    root = os.path.realpath(sys.argv[2])
    paths = [os.path.realpath(p) for p in reg]
    sys.exit(0 if root in paths else 1)
except Exception:
    sys.exit(1)
PY
}

is_enabled() { _in_list "$REGISTRY"; }
is_disabled() { _in_list "$DISABLED"; }
always_route() { [ -f "$ALWAYS_ROUTE" ] || [ "${HEADROOM_ALWAYS_ROUTE:-}" = "1" ]; }

route_requested=false
if always_route || is_enabled; then
  route_requested=true
fi

if is_disabled; then
  route_requested=false
fi

if $route_requested; then
  if ! curl -sf -m1 "$PROXY_URL/health" >/dev/null 2>&1; then
    print -u2 "headroom: canonical route requested but proxy health check failed; refusing direct fallback"
    exit 69
  fi
  export ANTHROPIC_BASE_URL="$PROXY_URL"
  export ANTHROPIC_CUSTOM_HEADERS="x-headroom-cwd: $PROJECT_ROOT"
else
  unset ANTHROPIC_BASE_URL
  unset ANTHROPIC_CUSTOM_HEADERS
fi

exec ~/.local/bin/claude "$@"
