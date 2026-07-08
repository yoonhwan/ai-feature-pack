# hooks - shared hook scaffold

This directory is the public source for cross-agent hook manifests, adapters, and runners.

Current scope:

- `context-pressure` warning hook
- dry-run rendering for Claude and Codex settings surfaces
- no live settings writes
- no live session rollover or fanout execution

Structure:

```text
hooks/
  manifests/
  adapters/
  runners/
  test/
```

Dry-run entrypoints:

```bash
hooks/runners/render-hook-scaffold --dry-run --format human
hooks/runners/render-hook-scaffold --dry-run --format json --runtime codex
hooks/adapters/claude-context-pressure.sh boundary --dry-run
hooks/adapters/codex-context-pressure.sh warning --dry-run
```

Notes:

- The shared install root is planned as `$HOME/.agents/hooks/`.
- Generated private targets remain `~/.claude/settings.json` and `~/.codex/hooks.json`.
- The hook only warns and prepares. User commands still trigger `session-rollover` or `session-fanout`.
- Those session lifecycle utilities are not implemented in this scaffold.
