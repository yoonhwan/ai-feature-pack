#!/usr/bin/env bash
# cairn 패키지 무결성 검증 (CI/설치 전). pytest는 dev venv 필요.
set -euo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check() { if eval "$2" >/dev/null 2>&1; then echo "✓ $1"; else echo "✘ $1"; fail=1; fi; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 -m venv "$tmp/venv"
"$tmp/venv/bin/pip" install -q --upgrade pip >/dev/null
"$tmp/venv/bin/pip" install -q -r "$PKG/core/requirements.txt"
PY="$tmp/venv/bin/python"

check "core/cairn.py 존재"        "[ -f '$PKG/core/cairn.py' ]"
check "core/bin/cairn 실행권한"    "[ -x '$PKG/core/bin/cairn' ]"
check "core/VERSION 존재"          "[ -f '$PKG/core/VERSION' ]"
check "manifest.json 유효"         "python3 -m json.tool '$PKG/manifest.json'"
check "슬래시 23개"                "[ \$(ls '$PKG/claude-code/commands/cairn' | wc -l) -eq 23 ]"
check "SKILL.md 존재"              "[ -f '$PKG/claude-code/skills/cairn/SKILL.md' ]"
check "hook 3개 실행권한"           "[ -x '$PKG/claude-code/hooks/post-checkout' ] && [ -x '$PKG/claude-code/hooks/post-merge' ] && [ -x '$PKG/claude-code/hooks/cairn-auto-progress' ]"
check "install.sh 문법"            "bash -n '$PKG/install.sh'"
check "auto-progress hook 문법"    "bash -n '$PKG/claude-code/hooks/cairn-auto-progress'"
check "cairn.py 문법"              "PYTHONPYCACHEPREFIX='$tmp/pycache' '$PY' -m py_compile '$PKG/core/cairn.py'"
check "self-test (golden)"         "PYTHONDONTWRITEBYTECODE=1 '$PY' '$PKG/core/cairn.py' self-test"
cp "$PKG/core/golden.yaml" "$tmp/plan.yaml"
mkdir -p "$tmp/repo/.cairn" "$tmp/repo/.baton/handoff"
cp "$tmp/plan.yaml" "$tmp/repo/.cairn/plan.yaml"
printf '%s\n' 'verification: pass' 'BTS evidence: pass' > "$tmp/repo/.baton/handoff/CURRENT.md"
check "auto-progress 후보 생성"    "cd '$tmp/repo' && git init -q && CAIRN_PYTHON='$PY' CAIRN_TASK_ID=t2 CAIRN_VERIFICATION_STATUS=pass '$PKG/claude-code/hooks/cairn-auto-progress' | grep -q '^candidate=' && ls .cairn/auto-progress/candidates/*.md"

[ "$fail" -eq 0 ] && echo "✅ verify OK" || { echo "❌ verify FAIL"; exit 1; }
