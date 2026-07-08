# Install

This first-wave package is intentionally read-only and does not install live runtime surfaces.

Local verification requires `bash`, `python3`, and `jq`.

Run it in place:

```bash
feature-pack/agent-surface-audit/core/bin/agent-surface-audit --dry-run
```

Optional local shell usage:

```bash
export PATH="$PWD/feature-pack/agent-surface-audit/core/bin:$PATH"
agent-surface-audit --dry-run
```

Do not symlink this package into `~/.claude`, `~/.codex`, `~/.agents`, or project overlay roots as part of the dry-run review. Future installers must be generated from reviewed reports and include rollback commands.
