# Linux-portability survey — `tmm/`, `tmuxc/`, `fable-team/skill/`

Target: Ubuntu aarch64 (GNU coreutils, bash 5). Priorities are constructs that **fail outright** on Linux vs. ones already guarded with `|| stat -c` fallbacks. Nothing modified.

| file:line | construct | Linux fix |
|---|---|---|
| `fable-team/skill/scripts/ft-nano-spawn.sh:148` | `/usr/bin/sed -i '' -E ...` (BSD empty-suffix form) | GNU `sed -i -E ...` (or `sed -i.bak -E`); empty-string arg errors on GNU |
| `tmm/test/verify.sh:813` | `date -r "$mt" +...` with epoch value (BSD) | GNU `date -d "@$mt" +...`; GNU `date -r` means reference-file |
| `tmm/test/perf.sh:137` | `stat -f %m "$cache"` — **unguarded** | `stat -c %Y "$cache"` (no fallback present) |
| `fable-team/skill/scripts/ft-nano-close.sh:125` | `stat -f '%z'` — no `stat -c` fallback | `stat -c %s` |
| `fable-team/skill/scripts/ft-nano-close.sh:226` | `stat -f '%m %N'` — no fallback (BSD name field) | `stat -c '%Y %n'` |
| `fable-team/skill/scripts/ft-nano-close.sh:232` | `stat -f %m` — no fallback | `stat -c %Y` |
| `fable-team/skill/scripts/ft-mbox.sh:78` | `stat -f %m ... 2>/dev/null || echo 0` — no `stat -c` | `stat -c %Y ... || echo 0` |
| `fable-team/skill/scripts/ft-mbox.sh:79` | `stat -f %m ... 2>/dev/null || echo 0` — no `stat -c` | `stat -c %Y ... || echo 0` |
| `fable-team/skill/scripts/ft-press-gate.sh:143` | `date -j -f '%a %b %e %T %Y' "$(ps -o lstart= ...)" +%s` (BSD `date -j`) | `date -d "$(ps -o lstart= -p $1)" +%s`; GNU `ps lstart` format also differs |
| `fable-team/skill/scripts/ft-press-gate.sh:91` | `date -r "$cp" '+%m-%d %H:%M:%S'` (BSD epoch) | `date -d "@$cp" '+...'` |
| `tmuxc/core/bin/tmuxc:391` | `exec /opt/homebrew/bin/uvx ...` hard-coded Homebrew path | `command -v uvx` / `exec uvx ...` |
| `fable-team/skill/scripts/ft-nano-close.sh:52` | `LSOF="${FT_LSOF_BIN:-/usr/sbin/lsof}"`; tmux fallback `/opt/homebrew/bin/tmux` | use `command -v lsof` (Linux `/usr/bin/lsof`) and `command -v tmux` |
| `fable-team/skill/scripts/ft-tick-install.sh:35` | `[ -x /opt/homebrew/bin/bash ]` required; whole script uses `launchctl` (lines 6–50) and plist | macOS/launchd-only by design; Linux needs systemd user unit + `/bin/bash` |
| `fable-team/skill/scripts/ft-tick.plist:9,14` | `<string>/opt/homebrew/bin/bash</string>` + PATH | systemd unit `ExecStart=/bin/bash`, Linux PATH — not usable via launchd |
| `fable-team/skill/scripts/ft-tick.sh:15` / `ft-tick-install.sh:11` | `PATH="/opt/homebrew/bin:/usr/local/bin:..."` hard-coded | prepend standard Linux paths or rely on inherited PATH |
| `tmm/core/bin/tmm:64` | bash4 re-exec candidates `TMM_BASH4_CANDIDATES:-/opt/homebrew/bin/bash /usr/local/bin/bash` | harmless on Linux (bash 5) but add `/bin/bash`; fine functionally |
| `tmm/core/bin/tmm:72` | `export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"` | drop Homebrew prefixes on Linux (cosmetic; unknown dirs ignored) |
| `tmm/core/bin/tmm:346` | `date -v0H -v0M -v0S +%s` (BSD) **but has** `|| date -d 'today 00:00'` | already guarded — works on Linux via fallback |
| `tmm/core/bin/tmm:347` | `date -r "$1"` (BSD) with `|| date -d "@$1"` fallback | already guarded |
| `tmm/core/bin/tmm:295,549,842` | `stat -f %m ... \|\| stat -c %Y` | already guarded — OK |
| `fable-team/skill/scripts/ft-lib.sh:269`, `ft-gzip.sh:40`, `ft-pm-watchd.sh:88,172`, `templates/hooks/*.sh:20,23,25,28` | `stat -f %m \|\| stat -c %Y` | already guarded — OK |
| `tmuxc/uninstall.sh:11,20`; `tmm/uninstall.sh:11`; `tmuxc/core/bin/tmuxc:1635`; `tmm/core/bin/tmm:1498` | bare `readlink "$link"` (one hop; no `-f`) | consistent on both, but multi-hop symlinks only resolve one level; use `readlink -f` where chain matters |
| `tmuxc/core/bin/tmuxc:962,1208`; `tmm/core/bin/tmm:78` | `readlink -f "$0" 2>/dev/null || ...` | GNU `readlink -f` present; fine on Linux (doc note re macOS <12.3) |
| `tmm/core/bin/tmm:447,458,237–283` | `declare -A`, `${var,,}` (bash 4+) | fine on Linux bash 5; guarded by re-exec for macOS 3.2 (line 60–71) |
| `tmuxc/claude-code/skills/tmuxc/COMM-GUIDE.md:378` | `ps -o lstart=,command=` (doc example) | GNU `ps` lstart format differs; doc-only, no runtime break |

**Summary of true Linux breakers (must fix):** `ft-nano-spawn.sh:148` (sed), `tmm/test/verify.sh:813` & `ft-press-gate.sh:91,143` (BSD date), unguarded `stat -f` in `tmm/test/perf.sh:137`, `ft-nano-close.sh:125/226/232`, `ft-mbox.sh:78/79`, and hard-coded `/opt/homebrew` in `tmuxc:391`, `ft-nano-close.sh:52`, `ft-tick*` (launchd-only). Everything else is already `stat -c`/`date -d` guarded or unaffected on bash 5.
