#!/usr/bin/env bash
# baton test/verify.sh -- pakage structure + syntax + execution verify

set -euo pipefail

PACKAGE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

pass=0
fail=0

ok()   { echo "  [ok] $*"; pass=$((pass + 1)); }
warn() { echo "  [--] $*"; }
ng()   { echo "  [ng] $*"; fail=$((fail + 1)); }

echo "-----------------------------------------"
echo "baton package verify"
echo "-----------------------------------------"
echo

# [1] core/ required files
echo "[1] core/ file check"

required_files=(
  "core/VERSION"
  "core/SPEC.md"
  "core/CHANGELOG.md"
  "core/bin/baton"
  "core/lib/core.sh"
  "core/lib/version.sh"
  "core/lib/ports.sh"
  "core/lib/handoff.sh"
  "core/lib/archive.sh"
  "core/lib/archive_search.sh"
  "core/lib/harnesses.sh"
  "core/templates/PLAN.md.template"
  "core/templates/JOURNAL.md.template"
  "core/templates/CURRENT.md.template"
  "core/templates/NEXT.md.template"
  "core/templates/phase.json.template"
  "core/templates/config.json.template"
  "core/templates/.gitignore.template"
)

for f in "${required_files[@]}"; do
  if [[ -f "$PACKAGE_DIR/$f" ]]; then
    ok "$f"
  else
    ng "$f (missing)"
  fi
done

# [2] slash commands count = 20
echo
echo "[2] claude-code/commands/baton/ count"

cmd_count=$(find "$PACKAGE_DIR/claude-code/commands/baton/" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
cmd_count="${cmd_count:-0}"
# 20 = 14 root cmds (digest/doctor/finish/help/hotfix-mode/install/migrate/plan/resume/save/status/upgrade/wt-clean/wt-create) + 6 archive subs (close/extract/list/prune/search/show)
if [[ "$cmd_count" == "20" ]]; then
  ok "20 files"
else
  ng "$cmd_count files found (expected 20)"
fi

# [3] hooks count = 5
echo
echo "[3] claude-code/hooks/ count"

hook_count=$(find "$PACKAGE_DIR/claude-code/hooks/" -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
hook_count="${hook_count:-0}"
if [[ "$hook_count" == "5" ]]; then
  ok "5 files"
else
  ng "$hook_count files found (expected 5)"
fi

# [4] harnesses 폐기됨 (v2 SIMPLIFY) — yaml 카탈로그 없음, 표준 instruction은 lib/harnesses.sh에 코드 상수로
echo
echo "[4] harnesses (v2 — yaml 폐기, lib/harnesses.sh 표준 instruction 사용)"

if [[ ! -d "$PACKAGE_DIR/harnesses" ]]; then
  ok "harnesses/ 디렉토리 없음 (의도됨)"
else
  ng "harnesses/ 잔존 (삭제 필요)"
fi
if [[ -f "$PACKAGE_DIR/core/lib/harnesses.sh" ]] && grep -q "BATON_PLAN_INSTRUCTION" "$PACKAGE_DIR/core/lib/harnesses.sh"; then
  ok "lib/harnesses.sh 표준 instruction 정의됨"
else
  ng "lib/harnesses.sh 표준 instruction 누락"
fi

# [5] flows count = 8 (excluding _index)
echo
echo "[5] flows/ count (excluding _index)"

flow_count=$(find "$PACKAGE_DIR/flows/" -name "*.md" 2>/dev/null | grep -v "_index" | wc -l | tr -d ' ')
if [[ "$flow_count" == "8" ]]; then
  ok "8 files"
else
  ng "$flow_count files found (expected 8)"
fi

# [6] bash syntax check
echo
echo "[6] bash syntax check"

check_syntax() {
  local file=$1 label=$2
  if bash -n "$file" 2>/dev/null; then
    ok "$label"
  else
    ng "$label (syntax error)"
  fi
}

check_syntax "$PACKAGE_DIR/core/bin/baton"  "bin/baton"
check_syntax "$PACKAGE_DIR/install.sh"       "install.sh"
check_syntax "$PACKAGE_DIR/uninstall.sh"     "uninstall.sh"

for sh in "$PACKAGE_DIR/core/lib/"*.sh; do
  check_syntax "$sh" "lib/$(basename "$sh")"
done

for sh in "$PACKAGE_DIR/claude-code/hooks/"*.sh; do
  check_syntax "$sh" "hooks/$(basename "$sh")"
done

# [7] JSON validity
echo
echo "[7] JSON validity"

if command -v jq >/dev/null 2>&1; then
  if jq empty "$PACKAGE_DIR/manifest.json" 2>/dev/null; then
    ok "manifest.json"
  else
    ng "manifest.json (parse error)"
  fi
else
  warn "jq not found -- JSON check skipped"
fi

# [8] baton help execution
echo
echo "[8] baton help execution"

help_out=$(mktemp)
if BATON_HOME="$PACKAGE_DIR/core" bash "$PACKAGE_DIR/core/bin/baton" help > "$help_out" 2>&1; then
  ok "help command succeeded"
else
  ng "help command failed"
  sed 's/^/    /' "$help_out"
fi
rm -f "$help_out"

# [9] lifecycle smoke — wt-create must persist deterministic ports in phase.json
echo
echo "[9] lifecycle smoke"

smoke_dir=$(mktemp -d /tmp/baton-verify-XXXXXX)
if (
  set -euo pipefail
  cd "$smoke_dir"
  git init -q
  git config user.email baton-verify@example.local
  git config user.name "baton verify"
  printf 'smoke\n' > README.md
  git add README.md
  git commit -q -m init
  BATON_HOME="$PACKAGE_DIR/core" BATON_TMUX_DISABLE=true bash "$PACKAGE_DIR/core/bin/baton" wt-create smoke >/dev/null
  jq -e '.ports.WEB_PORT == 3011 and .ports.MOBILE_PORT == 3012 and .ports.GATEWAY_PORT == 8090' \
    .worktrees/smoke/.baton/phase.json >/dev/null
); then
  ok "wt-create phase.json includes deterministic ports"
else
  ng "wt-create phase.json missing deterministic ports"
fi
rm -rf "$smoke_dir"

# [10] v1.2.5+ — RESUME_MSG.md builder + last_commit field + resume guard
echo
echo "[10] v1.2.5 신규 검증"

if grep -q "^baton_resume_msg_build" "$PACKAGE_DIR/core/lib/handoff.sh"; then
  ok "baton_resume_msg_build (handoff.sh)"
else
  ng "baton_resume_msg_build missing"
fi
if grep -q "^baton_resume_msg_print" "$PACKAGE_DIR/core/lib/handoff.sh"; then
  ok "baton_resume_msg_print (handoff.sh)"
else
  ng "baton_resume_msg_print missing"
fi
if grep -q "^baton_resume_msg_footer_append" "$PACKAGE_DIR/core/lib/handoff.sh"; then
  ok "baton_resume_msg_footer_append (handoff.sh)"
else
  ng "baton_resume_msg_footer_append missing"
fi
if grep -q "^last_commit:" "$PACKAGE_DIR/core/templates/CURRENT.md.template"; then
  ok "CURRENT.md.template last_commit field"
else
  ng "CURRENT.md.template last_commit field missing"
fi
if grep -q "baton-extracted" "$PACKAGE_DIR/core/lib/core.sh"; then
  ok "baton_cmd_resume archive extract abort"
else
  ng "baton_cmd_resume archive extract abort missing"
fi
if grep -q "baton_resume_msg_build" "$PACKAGE_DIR/claude-code/hooks/session-end.sh"; then
  ok "session-end.sh RESUME_MSG.md 갱신"
else
  ng "session-end.sh RESUME_MSG.md 갱신 missing"
fi

# [11] post-install state (optional)
echo
echo "[11] post-install state (requires install.sh)"

if [[ -L "$HOME/.baton/current" ]] && [[ -d "$HOME/.baton/current" ]]; then
  ok "~/.baton/current symlink exists"
  if [[ -x "$HOME/.baton/current/bin/baton" ]]; then
    ok "~/.baton/current/bin/baton is executable"
  else
    ng "~/.baton/current/bin/baton not executable"
  fi
else
  warn "~/.baton/current not found (install.sh not run -- skipped)"
fi

# summary
echo
echo "-----------------------------------------"
echo "Result: ${pass} passed / ${fail} failed"

if [[ "$fail" -gt 0 ]]; then
  echo "FAIL"
  echo "-----------------------------------------"
  exit 1
else
  echo "PASS -- baton package verified"
  echo "-----------------------------------------"
fi
echo
