#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 -m json.tool "$ROOT/manifests/context-pressure.json" >/dev/null
test -x "$ROOT/adapters/claude-context-pressure.sh"
test -x "$ROOT/adapters/codex-context-pressure.sh"
test -x "$ROOT/runners/context-pressure.sh"
test -x "$ROOT/runners/render-hook-scaffold"

TMP_JSON="$(mktemp)"
"$ROOT/runners/render-hook-scaffold" --dry-run --format json --json "$TMP_JSON" >/dev/null
python3 - "$TMP_JSON" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["install_root"] == "$HOME/.agents/hooks"
assert len(data["manifests"]) == 1
assert len(data["runtime_outputs"]) == 2
targets = {item["runtime"]: item["target"] for item in data["runtime_outputs"]}
assert targets["claude-code"] == "~/.claude/settings.json"
assert targets["codex-cli"] == "~/.codex/hooks.json"
commands = []
for item in data["runtime_outputs"]:
    hooks = item["snippet"]["hooks"]["UserPromptSubmit"][0]["hooks"]
    commands.extend(entry["command"] for entry in hooks)
assert "$HOME/.agents/hooks/adapters/claude-context-pressure.sh boundary" in commands
assert "$HOME/.agents/hooks/adapters/codex-context-pressure.sh warning" in commands
PY

"$ROOT/adapters/claude-context-pressure.sh" boundary --dry-run --used-percent 35 | grep -q '"triggered": true'
"$ROOT/adapters/codex-context-pressure.sh" warning --dry-run --used-percent 65 | grep -q '"runtime": "codex-cli"'

rm -f "$TMP_JSON"
echo "hooks verify OK"
