# mcp-manager

`mcp-manager` is a local runtime utility for auditing and trimming MCP server surfaces without dumping secret config values.

Current scope:

- list Claude/Codex MCP surfaces by server name only
- disable and re-enable Claude/Codex MCP servers with backup and restore support
- prune Claude/Codex MCP servers by keep-list
- keep disabled server fragments under `~/.agents/state/mcp-manager/disabled/`

Examples:

```bash
feature-pack/mcp-manager/core/bin/mcp-manager list --format human
feature-pack/mcp-manager/core/bin/mcp-manager disable stitch --runtime claude --dry-run
feature-pack/mcp-manager/core/bin/mcp-manager disable stitch --runtime codex --dry-run
feature-pack/mcp-manager/core/bin/mcp-manager prune --runtime claude --keep context,filesystem,think --dry-run
feature-pack/mcp-manager/core/bin/mcp-manager prune --runtime codex --keep filesystem,node_repl,serena,think --dry-run
```
