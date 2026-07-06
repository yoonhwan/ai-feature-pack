# agent-surface-audit

`agent-surface-audit` is a public-safe dry-run inventory tool for agent skill and hook surfaces.

It reads only safe metadata from source packages, user skill roots, project overlays, and hook config paths. It does not modify live `~/.claude`, `~/.codex`, `~/.agents`, project overlay settings, symlinks, hooks, sessions, logs, or auth material.

## Usage

```bash
feature-pack/agent-surface-audit/core/bin/agent-surface-audit --dry-run
feature-pack/agent-surface-audit/core/bin/agent-surface-audit --dry-run --repo-root "$PWD" --home "$HOME" --json report.json
feature-pack/agent-surface-audit/core/bin/agent-surface-audit --dry-run --format json
feature-pack/agent-surface-audit/core/bin/agent-surface-audit --dry-run --public-safety --format json
```

`--dry-run` is required. Findings are report data, not process failures. The command exits non-zero only for invalid arguments or runtime/tool errors.

## Report Scope

The report includes:

- public safety buckets
- source packages under `feature-pack/*`
- user runtime skill roots under `$HOME/.claude/skills`, `$HOME/.codex/skills`, and `$HOME/.agents/skills`
- project overlays under `.claude/skills`, `.codex/skills`, and `.agents/skills`
- hook config path existence metadata only
- duplicate exposure risks
- broken symlinks
- proposed future actions and rollback commands
- skipped private paths by class only

Codex/OMO skill exposure remains `~/.codex/skills` until active load behavior proves otherwise. `~/.agents/skills` is compatibility/overlay only.
