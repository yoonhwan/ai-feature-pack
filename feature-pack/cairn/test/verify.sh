#!/usr/bin/env bash
# cairn 패키지 무결성 검증 (CI/설치 전). pytest는 dev venv 필요.
set -euo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check() { if eval "$2" >/dev/null 2>&1; then echo "✓ $1"; else echo "✘ $1"; fail=1; fi; }

check "core/cairn.py 존재"        "[ -f '$PKG/core/cairn.py' ]"
check "core/bin/cairn 실행권한"    "[ -x '$PKG/core/bin/cairn' ]"
check "core/VERSION 존재"          "[ -f '$PKG/core/VERSION' ]"
check "manifest.json 유효"         "command -v jq >/dev/null && jq -e . '$PKG/manifest.json'"
check "슬래시 22개"                "[ \$(ls '$PKG/claude-code/commands/cairn' | wc -l) -eq 22 ]"
check "SKILL.md 존재"              "[ -f '$PKG/claude-code/skills/cairn/SKILL.md' ]"
check "install.sh 문법"            "bash -n '$PKG/install.sh'"
check "cairn.py 문법"              "python3 -m py_compile '$PKG/core/cairn.py'"
check "self-test (golden)"         "python3 '$PKG/core/cairn.py' self-test"

[ "$fail" -eq 0 ] && echo "✅ verify OK" || { echo "❌ verify FAIL"; exit 1; }
