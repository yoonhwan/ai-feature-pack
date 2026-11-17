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

## `ctx-share` — 조율 몫과 주간 환산 보드

`ctx-burn` 이 «쓴 양» 을 재면 `ctx-share` 는 «그중 조율이 얼마인지» 와 «주간 한도의 몇 %인지» 를
보드 한 장에 쓴다. 정의 정본 = `design/aifp/indices/진행/usage-monitor-coord-weekly.md`.

```bash
ctx-share                                  # 48시간 창을 재서 보드 폴더에 쓴다
ctx-share --hours 24 --json                # 기계 판독(보드 쓰기 0)
ctx-share --now 2026-11-17T13:00:00 --force # 시험·재측정
```

### 정의 1 — 조율/구현 분류 = 좌석 이름의 역할 칸

세션 파일이 스스로 가진 이름(`session_info.name`, 없으면 seat-resume 기록의 `jsonl` → `name`)을
문법 `<프로젝트>-<팀>-<역할>[-<꼬리>]#<N>` 로 가른다. `#` 뒤가 숫자뿐이고, `#` 앞을 `-` 로 갈라
토큰이 3개 이상(빈 토큰 0)이면 **셋째 토큰이 역할**이다. 팀 이름·카드 slug 는 읽지 않는다.

| 갈래 | 역할 토큰 |
|---|---|
| 구현 | `nano` · `tester` · `qa` · `repro` · `tool` · `implementer` · `worker` |
| 조율 | `master` · `arch` · `da` · `desk` · `pm` · `checker` · `analyst` · `lead` · `architect` · `orch` |
| 못 가림 | 이름 없음 · 문법으로 안 풀리는 이름 · 표에 없는 역할 |

조율 몫 % = 조율 ÷ (조율 + 구현). 못 가림은 분모에서 빼고 따로 보인다. 10% 를 넘으면 판정 불가다.

### 정의 2 — 주간 환산 사용률

주간 % = (창 안 claude 모델 가중 합 × 168 ÷ 창 시간)
÷ ((5x 장수 × `FT_CAP_WK_5X` + ultra 장수 × `FT_CAP_WK_ULTRA`) × `FT_CAP_TARGET_UTIL`) × 100

가중 = `input` + 1.25 × (cacheWrite − cacheWrite1h) + 2.0 × cacheWrite1h + 0.1 × cacheRead + 5 × output
(`ctx-burn` 과 같은 상수). 상수는 `accounts.env` 에서 읽고, 하나라도 비면 % 를 내지 않는다.
보드에는 낮은 앵커(`WK_*_LOW`) 값도 괄호로 함께 쓴다.

### 정의 2-2 — 계정 실측 %(대조 값)

`anchor-snapshots.jsonl` 의 마지막 표본으로 Σ(w × 계정 한도) ÷ Σ 계정 한도를 낸다(`TARGET_UTIL` 0).
차 = 계정 실측 − 로컬 W 환산. +20%p 이상이면 «다른 머신·밖 경로 의심», −20%p 이하이면
«로컬이 더 큼 · 자 차» 표지를 붙인다. 판정(목표 안)은 두 값 모두 ≤ 100% 일 때만이다.

### 정의 3 — 보드 자리와 갱신 주기

보드 = `<out>/board.md`(사람) · `last.json`(기계) · `samples.tsv`(갱신마다 1줄) · 기본 `out` =
`$FT_ROOT/.fable-team/state/usage-monitor`(없으면 BYZ 루트). 30분 안에 잰 값이 있으면 스스로
건너뛰고 rc 0(`--force` 로 바로 잼). 보드는 임시 파일에 쓴 뒤 이름을 바꾼다.

`board.md` 줄 순서 = ① 잰 시각·창 ② 조율·구현(목표 ≤ 50%) ③ 로컬 W 환산(낮은 앵커)·계정 실측·차·표지
④ 못 가림 ⑤ 24시간·168시간 참고 ⑥ 조율 상위 5좌석 ⑦ 판정(목표 안 / 목표 밖 / 판정 불가 <사유>).
rc 0 = 쟀다(목표 안·밖), rc 1 = 판정 불가(세션 폴더 없음 · 상수 결손 · 계정 표본 문제 · 못 가림 초과).
보드 폴더 밖 쓰기 0 · 네트워크 0 · 세션 로그·좌석 기록·상수·계정 표본은 읽기만 한다.

| option | default | meaning |
|---|---|---|
| `--hours N` | 48 | 창 시간 |
| `--now ISO` | 지금 | 재는 시각(시험) |
| `--sessions-dir` / `--resume-dir` | `~/.pi/agent/sessions` · `~/.claude/state/seat-resume` | 읽을 곳 |
| `--inv-file` | `accounts.env`(`$CTX_PLAN_CAP_FILE`) | 상수 |
| `--acct-file` | `anchor-snapshots.jsonl` | 계정 표본 |
| `--out` | 위 «정의 3» | 보드 폴더 |
| `--json` | off | 기계 판독 · 보드 쓰기 0 |
| `--force` | off | 30분 건너뜀 무시 |

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
