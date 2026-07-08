#!/usr/bin/env bash
set -euo pipefail

PKG="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    printf 'PASS %s\n' "$1"
  else
    printf 'FAIL %s\n' "$1"
    fail=1
  fi
}

check "README exists" "[ -f '$PKG/README.md' ]"
check "INSTALL exists" "[ -f '$PKG/INSTALL.md' ]"
check "manifest valid" "python3 -m json.tool '$PKG/manifest.json'"
check "CLI executable" "[ -x '$PKG/core/bin/mcp-manager' ]"
check "Python tests" "PYTHONDONTWRITEBYTECODE=1 python3 '$PKG/test/test_mcp_manager.py'"

if [ "$fail" -eq 0 ]; then
  printf 'verify OK\n'
else
  printf 'verify FAIL\n'
  exit 1
fi
