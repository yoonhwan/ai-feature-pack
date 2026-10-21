## Multi-host survey — tmm (read-only)

Search scope: only `feature-pack/tmm`. Total tmux call sites ≈96 in `core/bin/tmm` + all of `core/libexec/seat-scan.sh`. All assume the process's default tmux server on the local host.

### Table (file:line | category | what must change)

| file:line | cat | what a multi-host version must change |
|---|---|---|
| `core/libexec/seat-scan.sh:22` | 1 | `tmux list-sessions` iterates only the local server. Needs an outer host loop (`tmm-hosts` list) and host-qualified names. |
| `core/libexec/seat-scan.sh:30-31` | 1 | `capture-pane -t "$s"` runs locally. Must become `ssh HOST tmux capture-pane …` (or a per-host remote scanner) and prefix name with host. |
| `core/bin/tmm:96` | 1,2 | `cache_init` keys cache on local `tmux display -p '#{socket_path}'`. Need one cache key per host server; filename must include host. |
| `core/bin/tmm:105` | 2,4 | `STATE="${TMPDIR:-/tmp}/tmm-…"`, `RUN` — single local state dir. Need per-host subdirs under `$RUN` (or `$STATE/host-<h>`) for snapshots/`tabs`/`dead.tsv`. |
| `core/bin/tmm:459,532,539` | 2 | `ep-<ver>.cache`, `rows.snap` are per-socket but pooled across hosts once merged. Must merge with host tag or keep one cache per host. |
| `core/bin/tmm:467` | 1 | `tmux list-panes -a -F …` (activity/pane_pid) is local-only. Must be gathered per host. |
| `core/bin/tmm:491` | 1 | Second `list-panes -a -F …` (pane_current_command/cwd) local-only; remote variant needed. |
| `core/bin/tmm:257,287` | 1 | `cat_prep`/`cat_of` build `CAT_LIST` from local `tmux list-sessions`. Needs host-tagged session list (name collision risk). |
| `core/bin/tmm:479` | 1 | `list-sessions -f '#{@tmm_picker}'` to exclude picker sessions — pickers exist only on the host you're attached to; remote hosts need their own exclusion or ignore. |
| `core/bin/tmm:326` | 1 | `capture-pane -t "=$1:"` in `last_epoch`. Per-host capture. |
| `core/bin/tmm:392,406` | 1 | `tmux show-environment TMUXC_PI_THINKING/MODEL` local-only; needs remote execution for pi seats on other hosts. |
| `core/bin/tmm:388-411,894-897` | 3 | `pgrep -P`/`ps -o args=` inspect local process trees. Must run on the seat's host (via ssh) to classify agent/model/effort. |
| `core/bin/tmm:1362-1378` | 1 | `cmd_attach`: `has-session`, `set -wu`, `switch-client`, `attach-server` all local. Cross-host attach must `ssh -t HOST tmux attach -t NAME`. |
| `core/bin/tmm:1459-1473` | 1 | `cmd_kill` calls `tmuxc kill`/`tmux kill-session` locally. Needs host-routed kill. |
| `core/bin/tmm:1394-1397` | 1 | `cmd_preview` `capture-pane -p -e -J` local-only; remote preview needs ssh capture. |
| `core/bin/tmm:843` | 1,2 | `dead_tsv`: `tmux ls -F` for live-exclusion is local; also caches tsv in one `$RUN`. Must union live names per host. |
| `core/libexec/tmm-dead-scan.py:131` | 3 | `ps -eo args` scans local processes for live session uuids/lsof. Must run per host. |
| `core/libexec/tmm-dead-scan.py:139` | 3,5 | `lsof -Fn -c …` is local + macOS/BSD-flavored. Needs remote `lsof` and Linux-compatible flags (`-c` differs). |
| `core/libexec/tmm-dead-scan.py:27-28` | 4 | `HOME=expanduser("~")`, `~/.claude/projects/*/*.jsonl` (also `~/.codex`, `~/.pi`, opencode DB) — single local filesystem. Remote transcripts require ssh-path reads or per-host mount. |
| `core/bin/tmm:72` | 4,5 | `PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"` — Homebrew-first, macOS layout. Remote commands must use remote PATH. |
| `core/bin/tmm:60-64` | 5 | bash4 candidate discovery `/opt/homebrew/bin/bash /usr/local/bin/bash` — macOS-only. |
| `core/bin/tmm:78` | 5 | `readlink -f` note "macOS 12.3+/GNU" — fine locally, but per-host binary resolution needed. |
| `core/bin/tmm:295,549,842` | 5 | `stat -f %m … || stat -c %Y` macOS/GNU dual form. If state mtime is gathered remotely, keep the dual form there too. |
| `install.sh:6` + `manifest.json` | 4 | `GLOBAL_BASE="$HOME/.tmm"`, `os:[darwin,linux]` — install/version paths are single-user local; remote hosts need a deploy/install story. |

### How seat-scan.sh should iterate hosts

Current shape (`seat-scan.sh:22`):

```
for s in $(tmux list-sessions -F '#S'); do capture-pane …; done
```

Minimal multi-host redesign (keeps the per-seat state machine untouched):

1. Add a host list source, e.g. `TMM_HOSTS` (file with `host<TAB>label`) plus implicit `local`.
2. Outer loop over hosts; inner loop over that host's sessions, and prefix every emitted line with the host as the first field:
   `HOST <TAB> SESSION <TAB> STATE <TAB> last`
3. For `local` keep current `tmux …`; for remote run a single batched ssh per host that returns `session`, `capture-pane` now+hist (one round trip using `tmux list-sessions` then `capture-pane` per session inside the remote shell). Keep output line-compatible by re-printing host first.
4. Preserve the parallel budget: today it's `xargs -P 8` over seats (`tmm:470`). With N hosts, run one worker per host in parallel, then `sort -k2,2`, so latency ≈ slowest host, not sum.
5. Never let a slow/unreachable host block the board: wrap ssh in `timeout`, and emit `HOST <TAB> <TAB> UNREACHABLE` so the UI can show a dead host rather than silently dropping it.

Corresponding caller changes: `scan_cached` (`tmm:291`) gets a cache keyed per host or a merged cache plus host column; `cmd_rows`/`cmd_dead_rows` must parse the extra leading field.

### Where the HOST column goes in picker rows

- Row is built in `cmd_rows` (`tmm:496-498`) as one display string + `\t$s\t$cat`. Add host as the **leading display token** or a compact 3–5 char label right before the live dot/name, e.g. `teamA ● web #3 …`, and add a hidden **host field** next to the session key (`$s` → `host` + `$s`).
- The key field (field 2) drives preview/attach/cursor tracking (`--nth=1,3`, `{2}` in preview/attach binds, `screen_pos` at `tmm:523`, `TMM_CUR`). So the correct change is: field 2 becomes `HOST<US>SESSION` (or a separate field kept in sync), and every `{2}` consumer splits it before calling tmux.
- `cmd_dead_rows` (`tmm:849-870`) has the same layout — add host after the `◌`/source badge.
- Headers: `tab_rows`/`cmd_catrows` (`tmm:713-750`, `cmd_catrows` at 610) group by category only; if hosts should be filterable, either add a second tree dimension (host → category) or a `^`-toggled host tab — but AGENTS.md fixes the tab tree to project→team, so a host label/badge in the row plus sort is lower-risk.
- Watch the ≤58 display-width rule (AGENTS.md): a 3–5 char host token plus the existing `team + ● + name + state + model + time + age + cwd` will overflow at 60 cols — host likely needs to be a 2–3 char abbreviation or shown only in narrow-mode header, not per row.

Key risks: session-name collisions across hosts (currently name is the sole key everywhere: `=NAME` targets, `dead_row` matching, `tabcur`), and the dead-view live-exclusion (`tmm:843`, `dead-scan.py:131`) which is host-local and will misreport a session as "dead" if it is alive on another host.
