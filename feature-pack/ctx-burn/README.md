# Feature Pack: ctx-burn

A **read-only audit tool** that shows, with graphs, how much context your local AI coding agents waste.

> Answers "why did my $100 plan hit the rate limit 10 minutes after I paid?" with numbers from your own logs.

## Why

Agents re-send **the whole conversation + auto-loaded memory + tool definitions** on every turn.
So cost is `turns × context size`.

- Prompt cache alive → billed at `0.1x`. Cache broken → rewritten at `2x`.
- Restarting (distilling) a session pays the fixed prefix again at `2x`.
- Output is `5x`.

## Quick start

```bash
git clone https://github.com/yoonhwan/ai-feature-pack.git
cd ai-feature-pack/feature-pack/ctx-burn
bash install.sh            # symlink into ~/.local/bin (ctx-burn + ctx-waste alias)

cd ~/my-project
ctx-burn                    # last 3 hours, current folder
```

English by default. Korean: `ctx-burn --lang ko`

`ctx-waste` still works — it is a permanent alias of `ctx-burn`. This tool **only measures what was
burned**. Capacity, subscription count and goal throughput live in the sibling tool `ctx-plan`
(`ctx-burn --hours 168 --json | ctx-plan --capacity --accounts 5x:5,ultra:5`).

## Supported runtimes

Detected automatically (dirs + live processes), no config needed.

| runtime | session logs | token usage | memory / rules |
|---|---|---|---|
| `claude` | `~/.claude/projects/**/*.jsonl` | yes | `CLAUDE.md`, `rules/*.md`, project `CLAUDE.md`, `memory/MEMORY.md` |
| `codex` | `~/.codex/sessions/**/rollout-*.jsonl` | yes | `AGENTS.md`, `AGENTS.user.md` |
| `pi` | `~/.pi/agent/sessions/**/*.jsonl` | yes | `AGENTS.md` |
| `opencode` | `~/.local/share/opencode/opencode.db` | yes (sqlite) | `~/.config/opencode/AGENTS.md` |
| `hermes` | `~/.hermes/sessions/*.jsonl` | no (memory only) | `SOUL.md` |
| `openclaw` | registry only | no | `AGENTS.md` if present |
| `commandcode` | history only | no (memory only) | `AGENTS.md` |

Runtimes without token counters are still checked for **auto-loaded file size** and **live process count**.

## Reading the output

```
[0] Runtime environment
  runtime      installed running sessions last          data
  claude       yes       29      127      10:14         usage+memory
  pi           yes       20      9        10:15         usage+memory
```

```
[1] claude — auto-loaded memory — paid on every request
  !   3,876 tok ████████████████████████ ~/.claude/CLAUDE.md     9,474
  total 5,971 tokens · 15,504 chars
```
`!` marks a file over 4KB. `~/.claude/rules/*.md` is **auto-loaded**; `~/.claude/guides/*.md` is
opened only when needed. Big rule files belong in `guides/`, with a 1KB digest left in `rules/`.

```
[2] claude — burn structure (weighted · total 80.0M)
  cache full rewrite  60.8% ███████████████·········  48.7M  61
  cache read (normal) 27.6% ███████·················  22.1M
```
If **full rewrite** is above 20%, that is the primary suspect. One rewrite costs as much as
20 normal requests.

```
[3] context per request
  avg 269,470 · max 582,588 tokens
```
An average over 200k means the conversation has grown to the end of the window — distillation
is not kicking in.

```
break-even for distillation
  restart cost        3k  (prefix 12,757 x 2.0)
  saving per turn     1,947  (distill at 250,000)
  break-even 13.1 turns · avg 12.1 turns/session -> current cadence is fine
```
Tells you **where to put the threshold**. If turns per session exceed the break-even, distill more often.


## Hand it to your own agent

You do not have to run anything by hand. Paste this into Claude Code, Codex, pi, opencode or any
coding agent and it installs, runs, and explains the result itself.

```text
Install and run ctx-burn on this project, then explain the output.
https://github.com/yoonhwan/ai-feature-pack/tree/main/feature-pack/ctx-burn

1. Clone the repo and run feature-pack/ctx-burn/install.sh (creates ~/.local/bin/ctx-burn).
2. Run `ctx-burn --hours 6` in this project root. Use `--lang ko` if I speak Korean.
3. From the output, report only these: cache full-rewrite share, average context per request,
   and the top 3 auto-loaded files over 4KB.
4. If full rewrite is above 20%, find the cause from local logs (resume size, sessions starting
   together, account switching) and show the evidence line.
5. If auto-loaded files are over 4KB, propose moving them out of the auto-load path with a 1KB digest.
6. Ask me before changing any setting. The tool itself is read-only, so running it is safe.
```

Any agent can do this because every number comes from files on the machine: session logs and
rule files. No API key, no network.


## The core lever: start budget, not window size

A 1M window is not usable if you distill at 300k. What matters is **how much of the gate is left
for actual conversation** when a session starts.

```
gate 300,000 · measured prefix 48,551 · handover 5,000
fresh distill (handover)   ▒▒▒▒▒▒██████████████████████████  remaining 246,449 (82%) · rewrite 107k
resume 200k                ▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███████████  remaining 100,000 (33%) · rewrite 400k
resume 250k                ▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█████  remaining  50,000 (17%) · rewrite 500k
prefix ▒ · carried ▓ · remaining █
fresh start: 4.9x the working room · 4.7x less rewrite cost (vs resume 250k)
```

**Resuming a 250k conversation leaves 50k of room and costs 500k to re-write. Starting fresh with a
5k handover leaves 246k and costs 107k.** That single ratio is the biggest lever in agent cost, and
it is why `ctx-burn` prints this table before the break-even section.

Tune with `--gate` and `--resume-caps` (comma separated).

## Options

| option | default | meaning |
|---|---|---|
| `--lang en\|ko` | `en` | output language |
| `--runtime auto\|all\|<name>` | `auto` | which runtimes to detail (`auto` = all with data) |
| `--hours N` | 3 | window in hours |
| `--project PATH` | cwd | project root for CLAUDE.md / rules / memory lookup |
| `--request FILE` | none | dissect one captured **request body** log (tool sizes, `defer_loading`) |
| `--rewrite-tokens N` | 150000 | what counts as a full rewrite |
| `--budget N` | 250000 | proposed distill threshold |
| `--top N` | 6 | session rows per runtime |
| `--json` | off | machine readable · adds the `plan_input` block (contract `ctx.v1`) consumed by `ctx-plan` |

`--capacity` / `--inventory` / `--need` / `--scales` are **not** here — they moved to `ctx-plan`.

### `--request` — see tool definitions too

```bash
ctx-burn --request ~/.cli-proxy-api/logs/error-v1-messages-*.log
```

Any file containing a JSON request body works (a `=== REQUEST BODY ===` marker is also understood).

`ctx-burn --json` adds one block that is a **contract**: `plan_input` with `schema: ctx.v1`
(`window_hours` · `pools{req, usage0, ctx_per_req, active_hours, cache_reuse, cache_reuse_of_input,
w_per_session_hour, samples, sessions, w_total}` · `rate_claude`). `ctx-plan` refuses anything else.

```bash
ctx-burn --hours 168 --json > /tmp/burn.json
ctx-plan --from /tmp/burn.json --inventory                     # 0순위 상수 점검
ctx-plan --from /tmp/burn.json --capacity --accounts 5x:5,ultra:5
```

## How to fix what you find

| priority | action | how |
|---|---|---|
| 1 | turn off unused built-in tools | `settings.json` → `env`: `CLAUDE_CODE_DISABLE_ARTIFACT=1`, `CLAUDE_CODE_DISABLE_WORKFLOWS=1` |
| 2 | slim auto-loaded rules | move big files to `~/.claude/guides/`, keep a 1KB digest in `rules/` |
| 3 | lower the distill threshold | to the break-even turn count, usually 50% of average context |
| 4 | cap resume context | hand over a summary + the last few turns, not a 500k conversation |
| 5 | spread session starts | do not start a cron/tick herd in the same minute (jitter) |

`defer_loading` keeps a tool definition at 0 tokens until it is loaded, but it is not a
user-facing switch — so the practical fix for unused tools is turning the feature off.

## Safety

- **Reads only.** Never writes settings or files. No network calls.
- Session logs stay local. Only token counters are read, never conversation text.
- Weights (read 0.1 / write 2.0 / output 5) follow public price ratios as an **approximation**.
  Real limit formulas are not public, so use the numbers for **relative** comparison.

## Requirements

- python3 (3.8+), standard library only
- macOS · Linux
