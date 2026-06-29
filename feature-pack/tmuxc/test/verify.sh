#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/core/bin/tmuxc" --help >/dev/null
"$ROOT/core/bin/tmuxc" open "$ROOT" --name TMUXC_VERIFY --agent codex --role worker --dry-run | grep -q 'session=TMUXC_VERIFY'
python3 -m json.tool "$ROOT/manifest.json" >/dev/null
bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"
test -f "$ROOT/claude-code/skills/tmuxc/SKILL.md"
test -f "$ROOT/claude-code/skills/tmuxc/COMM-GUIDE.md"

echo "tmuxc verify OK"
