# Multi-host assumption survey — `feature-pack/fable-team/skill`

Scope: `scripts/`, `templates/`, `references/`, `SKILL.md` only (no `.bak*`, no parent dirs). Every row below is a place that silently assumes the whole team shares **one host + one filesystem + one tmux server**.

| file:line | cat | what a multi-host version must change |
|---|---|---|
| `scripts/ft-mbox.py:92-102` | 1 | Mailbox is resolved from the *local* git common-dir (`git rev-parse --git-common-dir` → `<root>/.fable-team/comm`). Needs a canonical remote mailbox (host-scoped queue) or a sync/lease layer instead of a local git root. |
| `scripts/ft-mbox.py:56-62` | 1 | `mailbox.jsonl` + `mailbox.log.jsonl` use local-file rotation (`SENT_LOG_KEEP`) and `fcntl.flock`. Cross-host locking needs a distributed lock or per-host shard + merge. |
| `scripts/ft-mbox.py:18,485,525` | 1 | LIFO + per-`to` ring cap relies on one `flock`'d file; two hosts writing must be reconciled (per-host files then fan-in, or a real broker). |
| `scripts/ft-mbox.sh:178-192` | 1 | `_mailbox_dir` re-derives the mailbox path locally (①`FT_MBOX_DIR` ②`.fable-team` ancestor ③cwd git root) — identical single-FS logic. Must accept a host/remote URI and not assume the sent mailbox == local path. |
| `scripts/ft-mbox.sh:25-31` | 1 | Doorbell maps session name → **local** `pane_id` and injects via `send-keys`. Remote seats need transport (ssh/tmux -L remote) or a remote doorbell channel. |
| `scripts/ft-mbox.sh:196-203` | 1 | Self-check reads back `mailbox.log.jsonl` at the just-written local path; remote send can't verify locally. |
| `scripts/ft-role-spawn.sh:25` | 2 | `SEATS="$ROOT/.fable-team/seats.json"` — one local roster. Needs a `host` field per seat and remote row merge. |
| `scripts/ft-seat-status.sh:32-36` | 2 | Roster path also derived from local git common-dir (`FT_SEATS_JSON` override only). Needs explicit roster source + host column. |
| `scripts/ft-seat-status.sh:59-64,78` | 2/3 | Liveness enumerated via local `tmux list-sessions` / `display-message pane_current_path`. Remote seats must be probed per-host (ssh tmux). |
| `scripts/ft-lib.sh:52,58-63` | 2 | State/approvals/signals dirs are `<root>/.fable-team/state/<slug>` etc. — local FS only. Needs per-host state namespace or shared backed store. |
| `scripts/ft-nano-cherry-gate.sh:134` | 2 | Override ledger at local `.fable-team/state/...` — cross-host audit needs shared log. |
| `templates/hooks/ft-session-restore.sh:22` | 2/4 | Restore probes `$ROOT/.fable-team/state/ACTIVE` + `$ROOT/.worktrees/*/...` on local disk. Remote worktrees invisible. |
| `scripts/ft-tmux-spawn.sh:111,117` | 3 | Spawn runs `tmux new-session` / `tmuxc open "$ROOT"` on the **local** tmux server. Needs host-targeted spawn (`ssh host tmux ...` / tmux socket per host). |
| `scripts/ft-tmux-spawn.sh:157,220` | 3 | Failure cleanup `tmuxc kill "$NAME"` local only. |
| `scripts/ft-tmux-kill.sh:39` | 3 | `tmuxc kill "$sess"` — no host parameter; must resolve seat→host before kill. |
| `scripts/ft-nano-close.sh:343` | 3 | `tmux kill-session -t "$PANE"` local; remote seat close needs ssh transport. |
| `scripts/ft-tick.sh:76-83,140` | 3 | Tick does local `capture-pane` + `send-keys` to drive master/pm. Needs per-host fan-out (one tick per host or ssh dispatch). |
| `scripts/ft-pm-watchd.sh:129` | 3 | Stall hash via local `tmux capture-pane`; remote seats not observable. |
| `scripts/ft-nano-spawn.sh:95,137-140` | 4 | Worktree created by `git -C "$ROOT" worktree add "$ROOT/.worktrees/..."` on local disk. Multi-host needs worktree created *on the target host* from a shared git remote (clone/fetch), not a local path. |
| `scripts/ft-nano-close.sh:30-38,104-105,221,258` | 4 | Close checks local `$ROOT/.worktrees/v65-*`, `.worktree-info.json`, and evidence HEAD locally. Remote worktree/HEAD must be verified over ssh against the shared remote. |
| `scripts/ft-mbox.py:68-84,150` | 4 | `.worktrees` ancestry walk to derive repo root assumes the worktree layout is local. Multi-host: pass explicit repo identity, don't infer from FS path. |
| `templates/seats.json.example:4` | 2 | Schema has role/index/tick/agent but **no `host`** field — add `host` (+ transport) so roster is machine-aware. |
| `scripts/ft-tick-install.sh:5-11,23-50` | 5 | launchd install: `~/Library/LaunchAgents/com.byz.ft-tick.plist`, `plutil -lint`, `launchctl bootstrap gui/$UID`, `/opt/homebrew/bin/bash`. Needs per-host install (ssh) or Linux equivalent (systemd); Homebrew path is macOS-only. |
| `scripts/ft-tick.plist:8-13` | 5 | `ProgramArguments=/opt/homebrew/bin/bash`, `WorkingDirectory=__WORKTREE__`, macOS `EnvironmentVariables`/`KeepAlive` plist. Non-portable; needs Linux unit + remote WorkingDirectory. |
| `references/SEATBELT.md:68-70` | 5 | Docs assert `launchctl print gui/$UID/...` and `pgrep` on the local host as the survival model — multi-host needs one tick per host and a host registry. |
| `scripts/ft-tick.sh:15` / `scripts/ft-tick-install.sh:11` | 5 | Hardcoded `PATH=/opt/homebrew/bin:/usr/local/bin:...` assumes macOS/Homebrew; breaks on Linux hosts. |

Notes / gaps found:
- **`pbcopy`, `osascript`, `sysctl` had ZERO hits** anywhere in scope (`scripts/`, `templates/`, `references/`, `SKILL.md`). The only macOS-only dependency actually present is **launchd/launchctl/plutil + `/opt/homebrew`** (cat 5). If the redesign expects clipboard/notification helpers, they live outside this skill dir.
- tmux doorbell is *not* a `pbcopy/osascript` path — it's `tmux send-keys` (local socket), counted under cat 3 in `ft-mbox.sh:31` and `ft-tick.sh:79`.
- The single-filesystem coupling is concentrated in **`ft-mbox.py` (root/mailbox derivation)**, **`ft-lib.sh` (state dirs)**, and **`ft-nano-*/ft-role-spawn` (worktree + roster paths)** — those four are the highest-risk refactor points.
