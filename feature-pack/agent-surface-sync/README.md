# agent-surface-sync

`agent-surface-sync` installs or updates shared agent surfaces from `feature-pack/*` and `hooks/` into local runtime roots.

Current scope:

- shared CLI links under `~/.agents/bin`
- installable runtime skill and support-file links declared by package manifests
- shared hook source link under `~/.agents/hooks`
- dry-run by default, apply only with `--apply`

It does not modify `~/.claude/settings.json`, `~/.codex/hooks.json`, or other live private settings surfaces yet.

## Usage

```bash
feature-pack/agent-surface-sync/core/bin/agent-surface-sync
feature-pack/agent-surface-sync/core/bin/agent-surface-sync --package baton,tmuxc
feature-pack/agent-surface-sync/core/bin/agent-surface-sync --runtime claude-code --format json
feature-pack/agent-surface-sync/core/bin/agent-surface-sync --apply --package baton
```

Dry-run reports planned installs, relinks, backups, skips, and rollback commands.
