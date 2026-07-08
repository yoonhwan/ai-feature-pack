#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$PKG_ROOT/../.." && pwd)"

command -v jq >/dev/null 2>&1 || {
  printf 'FAIL verify_manifest_contract requires jq on PATH\n' >&2
  exit 1
}

require_expr() {
  local manifest=$1
  local label=$2
  local expr=$3
  jq -e "$expr" "$manifest" >/dev/null || {
    printf 'FAIL %s\n' "$label"
    return 1
  }
  printf 'PASS %s\n' "$label"
}

require_sources_exist() {
  local package_root=$1
  local manifest=$2
  local label=$3
  local failed=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -e "$package_root/$rel" ]; then
      printf 'FAIL %s missing source %s\n' "$label" "$rel"
      failed=1
    fi
  done < <(
    jq -r '
      (.commands[]?.path // empty),
      (.skill_surfaces[]?.path // empty),
      (.hook_adapters[]?.path // empty),
      (.public_docs[]? // empty),
      (.runtime_targets[]? | .source? // empty)
    ' "$manifest"
  )
  if [ "$failed" -eq 0 ]; then
    printf 'PASS %s source paths exist\n' "$label"
  fi
  return "$failed"
}

require_no_undeclared_hook_files() {
  local package_root=$1
  local manifest=$2
  local label=$3
  local failed=0
  local declared_hooks
  declared_hooks="$(jq -r '.hook_adapters[]?.path // empty' "$manifest")"

  if [ -z "$declared_hooks" ]; then
    printf 'PASS %s hook directories closed\n' "$label"
    return 0
  fi

  while IFS= read -r hook_dir; do
    [ -n "$hook_dir" ] || continue
    [ -d "$package_root/$hook_dir" ] || continue
    while IFS= read -r abs_path; do
      [ -n "$abs_path" ] || continue
      local rel_path="${abs_path#"$package_root/"}"
      local base_name="${rel_path##*/}"
      case "$base_name" in
        README|README.*|*.md) continue ;;
      esac
      if ! printf '%s\n' "$declared_hooks" | grep -Fqx -- "$rel_path"; then
        printf 'FAIL %s undeclared hook asset %s\n' "$label" "$rel_path"
        failed=1
      fi
    done < <(find "$package_root/$hook_dir" -type f | sort)
  done < <(printf '%s\n' "$declared_hooks" | xargs -n1 dirname | sort -u)

  if [ "$failed" -eq 0 ]; then
    printf 'PASS %s hook directories closed\n' "$label"
  fi
  return "$failed"
}

check_contract_shape() {
  local manifest=$1
  local label=$2
  require_expr "$manifest" "$label contract-shape" '
    (.commands | type) == "array" and
    (.skill_surfaces | type) == "array" and
    (.runtime_targets | type) == "array" and
    (.hook_adapters | type) == "array" and
    (.private_state_exclusions | type) == "array" and
    (.public_docs | type) == "array"
  '
  require_expr "$manifest" "$label runtime-allowlist" '
    (
      [
        (.commands[]?.runtime // empty),
        (.skill_surfaces[]?.runtime // empty),
        (.runtime_targets[]?.runtime // empty),
        (.hook_adapters[]?.runtime // empty)
      ] - ["claude-code","codex-cli","gemini-cli","opencode","hermes","git","project","omx","cairn-runtime"]
    ) | length == 0
  '
}

BATON="$REPO_ROOT/feature-pack/baton"
CAIRN="$REPO_ROOT/feature-pack/cairn"
TMUXC="$REPO_ROOT/feature-pack/tmuxc"
FABLE_TEAM="$REPO_ROOT/feature-pack/fable-team"
AGENT_CLI="$REPO_ROOT/feature-pack/agent-cli"
AUTO="$REPO_ROOT/feature-pack/auto"

check_contract_shape "$BATON/manifest.json" "baton"
require_expr "$BATON/manifest.json" "baton mapping" '
  .commands == [
    {"name":"baton","kind":"cli-binary","path":"core/bin/baton"},
    {"name":"baton","runtime":"claude-code","kind":"slash-command-pack","path":"claude-code/commands/baton/"}
  ] and
  .skill_surfaces == [
    {"runtime":"claude-code","kind":"skill","path":"claude-code/skills/baton/SKILL.md"}
  ] and
  (.runtime_targets | length) == 8 and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="commands" and .target=="~/.claude/commands/baton/" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="skill" and .target=="~/.claude/skills/baton/SKILL.md" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="hook-config" and .target=="~/.claude/settings.json" and .status=="limited") and
  any(.runtime_targets[]; .runtime=="codex-cli" and .kind=="instructions" and .source=="adapters/codex/INSTRUCTIONS.md" and .target=="~/.codex/baton/INSTRUCTIONS.md" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="gemini-cli" and .kind=="instructions" and .source=="adapters/gemini/INSTRUCTIONS.md" and .target=="manual Gemini integration" and .status=="limited") and
  any(.runtime_targets[]; .runtime=="opencode" and .kind=="instructions" and .source=="adapters/opencode/INSTRUCTIONS.md" and .target=="manual OpenCode integration" and .status=="limited") and
  any(.runtime_targets[]; .runtime=="hermes" and .kind=="plugin" and .source=="adapters/hermes/baton.py" and .target=="~/.hermes/plugins/baton.py" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="hermes" and .kind=="install-doc" and .source=="adapters/hermes/INSTALL.md" and .target=="manual Hermes integration" and .status=="limited") and
  (.hook_adapters | length) == 5 and
  any(.hook_adapters[]; .event=="post-tool-use" and .mode=="direct-install") and
  any(.hook_adapters[]; .event=="pre-compact" and .mode=="direct-install") and
  any(.hook_adapters[]; .event=="session-end" and .mode=="direct-install") and
  any(.hook_adapters[]; .event=="session-start" and .mode=="direct-install") and
  any(.hook_adapters[]; .event=="user-prompt-submit" and .mode=="direct-install") and
  (.private_state_exclusions | contains([".baton",".omc",".omo",".omx","logs","session"])) and
  (.public_docs | contains(["README.md","INSTALL.md","core/SPEC.md","adapters/codex/INSTRUCTIONS.md","adapters/gemini/INSTRUCTIONS.md","adapters/opencode/INSTRUCTIONS.md","adapters/hermes/INSTALL.md"]))
'
require_sources_exist "$BATON" "$BATON/manifest.json" "baton"
require_no_undeclared_hook_files "$BATON" "$BATON/manifest.json" "baton"

check_contract_shape "$CAIRN/manifest.json" "cairn"
require_expr "$CAIRN/manifest.json" "cairn mapping" '
  .commands == [
    {"name":"cairn","kind":"cli-binary","path":"core/bin/cairn"},
    {"name":"cairn","runtime":"claude-code","kind":"slash-command-pack","path":"claude-code/commands/cairn/"}
  ] and
  .skill_surfaces == [
    {"runtime":"claude-code","kind":"skill","path":"claude-code/skills/cairn/SKILL.md"}
  ] and
  (.runtime_targets | length) == 6 and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="commands" and .target=="~/.claude/commands/cairn/" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="skill" and .target=="~/.claude/skills/cairn/SKILL.md" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="cairn-runtime" and .kind=="hook-script" and .source=="claude-code/hooks/cairn-auto-progress" and .target=="~/.cairn/current/hooks/cairn-auto-progress" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="git" and .kind=="hook" and .source=="claude-code/hooks/post-merge" and .target==".git/hooks/post-merge" and .status=="limited") and
  any(.runtime_targets[]; .runtime=="git" and .kind=="hook" and .source=="claude-code/hooks/post-checkout" and .target==".git/hooks/post-checkout" and .status=="limited") and
  any(.runtime_targets[]; .runtime=="codex-cli" and .kind=="execution" and .status=="intent-only") and
  (.hook_adapters | length) == 3 and
  any(.hook_adapters[]; .event=="cairn-auto-progress" and .mode=="direct-install") and
  any(.hook_adapters[]; .event=="post-checkout" and .mode=="direct-install") and
  any(.hook_adapters[]; .event=="post-merge" and .mode=="direct-install") and
  (.private_state_exclusions | contains([".cairn",".omc",".omo",".omx","logs","session"])) and
  (.public_docs | contains(["README.md","INSTALL.md","docs/cairn-design.md","docs/agent-lifecycle-hook-design.md"]))
'
require_sources_exist "$CAIRN" "$CAIRN/manifest.json" "cairn"
require_no_undeclared_hook_files "$CAIRN" "$CAIRN/manifest.json" "cairn"

check_contract_shape "$TMUXC/manifest.json" "tmuxc"
require_expr "$TMUXC/manifest.json" "tmuxc mapping" '
  .commands == [
    {"name":"tmuxc","kind":"cli-binary","path":"core/bin/tmuxc"},
    {"name":"tmuxc-restore-scan","kind":"cli-support","path":"core/libexec/tmuxc-restore-scan.py"}
  ] and
  .skill_surfaces == [
    {"runtime":"claude-code","kind":"skill","path":"claude-code/skills/tmuxc/SKILL.md"}
  ] and
  .hook_adapters == [] and
  (.runtime_targets | length) == 3 and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="skill" and .target=="~/.claude/skills/tmuxc/SKILL.md" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="codex-cli" and .kind=="execution" and .target=="tmuxc open ... --agent codex" and .status=="execution-only") and
  any(.runtime_targets[]; .runtime=="omx" and .kind=="execution" and .target=="tmuxc open ... --agent omx" and .status=="execution-only") and
  (.private_state_exclusions | contains([".tmuxc",".omc",".omo",".omx","captures","transcripts"])) and
  (.public_docs | contains(["README.md","INSTALL.md","claude-code/skills/tmuxc/COMM-GUIDE.md"]))
'
require_sources_exist "$TMUXC" "$TMUXC/manifest.json" "tmuxc"
require_no_undeclared_hook_files "$TMUXC" "$TMUXC/manifest.json" "tmuxc"

check_contract_shape "$FABLE_TEAM/manifest.json" "fable-team"
require_expr "$FABLE_TEAM/manifest.json" "fable-team mapping" '
  .commands == [] and
  .skill_surfaces == [
    {"runtime":"claude-code","kind":"skill","path":"skill/SKILL.md"}
  ] and
  (.runtime_targets | length) == 3 and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="skill" and .target=="~/.claude/skills/fable-team/SKILL.md" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="support-files" and .source=="skill/" and .target=="~/.claude/skills/fable-team/" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="codex-cli" and .kind=="policy-docs" and .source=="skill/" and .status=="limited") and
  (.hook_adapters | length) == 4 and
  any(.hook_adapters[]; .event=="context-distill-gate" and .mode=="template-only") and
  any(.hook_adapters[]; .event=="context-hygiene-clean" and .mode=="template-only") and
  any(.hook_adapters[]; .event=="orchestration-gate" and .mode=="template-only") and
  any(.hook_adapters[]; .event=="orchestration-turn-reset" and .mode=="template-only") and
  (.private_state_exclusions | contains([".fable-team",".gstack",".omc",".omo",".omx"])) and
  (.public_docs | contains(["README.md","INSTALL.md","docs/design-round-integrity.md","docs/design-ctx-management.md"]))
'
require_sources_exist "$FABLE_TEAM" "$FABLE_TEAM/manifest.json" "fable-team"
require_no_undeclared_hook_files "$FABLE_TEAM" "$FABLE_TEAM/manifest.json" "fable-team"

check_contract_shape "$AGENT_CLI/manifest.json" "agent-cli"
require_expr "$AGENT_CLI/manifest.json" "agent-cli mapping" '
  .commands == [] and
  .skill_surfaces == [
    {"runtime":"claude-code","kind":"skill","path":"SKILL.md"}
  ] and
  (.runtime_targets | length) == 4 and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="skill" and .target=="~/.claude/skills/agent-cli/SKILL.md" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="support-files" and .source=="references/" and .target=="~/.claude/skills/agent-cli/references/" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="support-files" and .source=="scripts/" and .target=="~/.claude/skills/agent-cli/scripts/" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="support-files" and .source=="config/tools-section.md" and .target=="TOOLS.md snippet registration" and .status=="limited") and
  .hook_adapters == [] and
  (.private_state_exclusions | contains([".omc",".omo",".omx","logs","session"])) and
  (.public_docs | contains(["README.md","INSTALL.md","cli/install.md","test/verify.md","CHANGELOG.md"]))
'
require_sources_exist "$AGENT_CLI" "$AGENT_CLI/manifest.json" "agent-cli"
require_no_undeclared_hook_files "$AGENT_CLI" "$AGENT_CLI/manifest.json" "agent-cli"

check_contract_shape "$AUTO/manifest.json" "auto"
require_expr "$AUTO/manifest.json" "auto mapping" '
  .commands == [] and
  .skill_surfaces == [
    {"runtime":"claude-code","kind":"skill","path":"skill/SKILL.md"}
  ] and
  (.runtime_targets | length) == 3 and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="skill" and .target=="~/.claude/skills/auto/SKILL.md" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="claude-code" and .kind=="support-files" and .source=="skill/references/" and .target=="~/.claude/skills/auto/references/" and .status=="installable") and
  any(.runtime_targets[]; .runtime=="project" and .kind=="template-copy" and .source=="config/templates/" and .target=="autoresearch/" and .status=="installable") and
  .hook_adapters == [] and
  (.private_state_exclusions | contains([".venv",".omc",".omo",".omx","results.tsv","run.log","upstream"])) and
  (.public_docs | contains(["README.md","INSTALL.md","test/verify.md"]))
'
require_sources_exist "$AUTO" "$AUTO/manifest.json" "auto"
require_no_undeclared_hook_files "$AUTO" "$AUTO/manifest.json" "auto"

printf 'verify manifest contract OK\n'
