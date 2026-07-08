# Install

`mcp-manager` is repo-local for now.

Run it in place:

```bash
feature-pack/mcp-manager/core/bin/mcp-manager list --format human
```

Optional local shell usage:

```bash
export PATH="$PWD/feature-pack/mcp-manager/core/bin:$PATH"
mcp-manager list --format human
```

Apply mode writes only to private runtime files under `~/.codex/` and `~/.agents/state/mcp-manager/`.
For Claude runtime operations, it also updates `~/.claude.json` and reads overlay MCP maps from
`~/.claude/.mcp.json` and `~/.claude/mcp.json`.
