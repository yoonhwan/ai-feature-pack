## tmuxc multi-host assumptions survey

Scoped to `feature-pack/tmuxc/` (excluded `.omx`, `.omc`, `.serena`). **Cat 5 (pbcopy/osascript/sysctl/launchctl): zero matches.** No `/Users/`, `/home/`, or `/tmp` in runtime code — only `/tmp/mbox` in docs (row 22). `/tmp` references in `test/` are fixtures.

| file:line | cat | what a multi-host version must change |
|---|---|---|
| `core/bin/tmuxc:50,62,65` | 1 | `tmux set-environment` / `new-session` / `set window-size` all hit default local socket; needs `--host` → `ssh host tmux …` or `tmux -L/-S` socket param |
| `core/bin/tmuxc:541,543,569-571` | 1 | `has-session`/`list-panes`/`send-keys` run against local server; wrap each in host-dispatch helper |
| `core/bin/tmuxc:920,928,939` | 1 | `list-sessions`, `capture-pane`, verify-send grep assume local server; route per-host |
| `core/bin/tmuxc:952` | 1 | `list-panes -a` enumerates only local sessions; needs fan-out across hosts + host column in output |
| `core/bin/tmuxc:1833` | 1 | `attach` is `tmux attach -t` locally; must become `ssh -t host tmux attach` for remote |
| `core/bin/tmuxc:1861` | 1 | `kill-session` local-only; host-scoped kill |
| `core/bin/tmuxc:713,715,717` | 1 | Prompt injection calls `tmux display-message -p '#S'` locally to derive parent session; needs host context |
| `core/bin/tmuxc:957` | 2 | `SNAP_DIR=$HOME/.tmuxc/snapshots` — local per-machine store; needs shared/remote store or host-namespaced dir |
| `core/bin/tmuxc:964-965` | 2 | Snapshot helper resolution probes `$HOME/.tmuxc/current/...`; must resolve on target host |
| `core/bin/tmuxc:1213-1214` | 2 | Restore-scan helper same `$HOME/.tmuxc/current` assumption |
| `core/bin/tmuxc:88,107,117` | 2 | `~/.claude.json` and `~/.serena/bridges/{port}.json` read locally for MCP/serena discovery; must read from owning host |
| `core/bin/tmuxc:139-141` | 2 | `$HOME/.claude/scripts/serena-mcp.sh` executed locally; host-aware path |
| `core/bin/tmuxc:235,245` | 2 | `$HOME/.headroom/claude-hr.sh` launcher hard-coded to local home |
| `uninstall.sh:4` | 2 | `GLOBAL_BASE="$HOME/.tmuxc"` — single-machine install root; multi-host needs per-host install awareness |
| `core/libexec/tmuxc-snapshot.py:31-38` | 2,4 | Hard-coded transcript globs (`~/.claude/projects`, `~/.codex`, `~/.commandcode`, `~/.local/share/opencode`); must be host-resolved/RSYNC'd |
| `core/libexec/tmuxc-restore-scan.py:22-24` | 2,4 | Same globs + `~/.codex/session_index.jsonl`; local-only forensic source |
| `core/libexec/tmuxc-snapshot.py:552` | 2 | Records `socket.gethostname()` in snapshot but nothing consumes it — restore must filter/route by host field |
| `core/bin/tmuxc:546` | 3 | `pgrep -P` / `pgrep -g` / `ps -o command=` on local pids; must run inside `ssh host` |
| `core/bin/tmuxc:731-732` | 3 | `pgrep -P ${pane_pid}` + `ps eww` proxy-bypass check — local pid namespace only |
| `core/bin/tmuxc:981,1013` | 3 | `pane_descendant_pids` BFS with `pgrep -P`/`ps` — pid inspection needs remote execution |
| `claude-code/skills/tmuxc/SKILL.md:315,353,657` | 3 | Documented `pgrep -P {pane_pid}` hard gate + `ps %cpu` idle check assume local process table |
| `claude-code/skills/tmuxc/COMM-GUIDE.md:129,211` | 4 | `/tmp/mbox/` relay dir (`FT_MBOX_RELAY_DIR`) fixed to local `/tmp`; cross-host needs shared path or scp |
| `claude-code/skills/tmuxc/references/tmuxc-disaster-recovery.md:60` | 2 | Restore example uses `--from ~/.tmuxc/snapshots/...` local absolute path; needs host-qualified store |

**Summary of risk:** the core binary has **no host/ssh abstraction** — every `tmux` call, `pgrep/ps` process inspection, `SNAP_DIR`, helper lookup, and MCP/serena/headroom path resolves the local machine. Multi-host needs (a) a `--host` dispatch wrapper around all `tmux`/`pgrep`/`ps` calls, (b) host-namespaced or shared snapshot store, and (c) host-aware transcript-glob resolution in the two `libexec` Python helpers. Category 5 macOS calls are entirely absent, so no portability work there.
