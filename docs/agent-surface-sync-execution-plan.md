# Agent Surface Sync Execution Plan

This document turns the Claude/Codex/OMO skill and hook sync interview into an execution-ready, public-safe plan. It is intentionally a plan artifact only: live user config, hooks, symlinks, and runtime state must not be changed until the dry-run inventory is reviewed.

## Goal

Create one recoverable source of truth for shared agent capabilities while preserving each runtime's native loading rules.

- Source of truth: `~/Project/ai-feature-pack`
- Public source: feature-pack packages, hook manifests, adapters, runners, install scripts, docs, tests
- Private runtime surfaces: `~/.claude`, `~/.codex`, local hook settings, MCP configs, sessions, logs, auth, generated state
- First executable artifact: dry-run inventory/audit script

## Whole Program Scope

This plan is not a `session-fanout` implementation plan. `session-fanout` is one utility inside a broader agent-surface synchronization program.

The execution scope has eight tracks:

1. **Public safety and recovery**: keep source public-safe, versioned, reviewable, and restorable.
2. **Source-of-truth layout**: normalize `feature-pack/<name>` packages and avoid hardcoded user paths.
3. **Runtime exposure**: generate or link Claude, Codex/OMO, and optional project-level skill surfaces from source.
4. **Hook system**: define public manifests, adapters, runners, and private generated runtime settings.
5. **Shared command layer**: expose stable wrappers under a neutral bin surface such as `~/.agents/bin`.
6. **Session rollover**: continue one task into a fresh numbered session with baton handoff and graceful close.
7. **Session fanout/fanin**: prepare bounded multi-lane tmuxc + baton + cairn workflows for parallel work.
8. **Fable-team integration**: preserve fable-team's Claude-native Agent/Workflow design while optionally giving it common helpers and policy adapters.

The first executable work must cover tracks 1-4 before building tracks 6-8.

## Execution Boundaries

Allowed before review:

- Read public source and safe metadata from runtime roots.
- Produce reports under an explicit output path or stdout.
- Render proposed files, symlinks, hook settings, and rollback commands in dry-run form.
- Tighten public-source ignore rules only after the public-safety report proves the change is necessary.

Not allowed before review:

- Modify `~/.claude/settings.json`, `~/.codex/hooks.json`, or any live user-level settings.
- Create, delete, or repoint live skill symlinks in `~/.claude`, `~/.codex`, or `~/.agents`.
- Copy private runtime state into `ai-feature-pack`.
- Print secret-bearing config contents, session transcripts, raw logs, MCP private config values, or auth material.
- Close, kill, split, or launch live agent sessions except through explicit dry-run command rendering.

## Current Evidence

Captured locally on 2026-07-05:

- `~/Project/ai-feature-pack/feature-pack/` already contains `baton`, `tmuxc`, `cairn`, `agent-cli`, `termaid`, `yt-transcribe`, `fable-team`, `tts-say`, and other packages.
- `~/.claude/skills` contains many installed skills, including `baton`, `tmuxc`, `cairn`, and `fable-team`.
- `~/.codex/skills` contains Codex/OMX-native skills and some shared symlinks.
- `~/.agents/skills` currently contains only a small subset: `k-skill-setup`, `srt-booking`.
- Local Codex/OMX doctor docs identify `~/.codex/skills` as the current canonical Codex user skill root and treat `~/.agents/skills` as legacy/historical. Do not assume Codex directly loads `~/.agents/skills` without fresh proof.
- `tmuxc --help` supports `--agent claude|codex|omx`.
- `hooks/` does not exist yet in `ai-feature-pack`; hook source still needs to be introduced.
- `feature-pack/fable-team` contains ignored local `.omc/.omx` runtime state in the working tree. It is not currently staged, but the audit must keep these excluded.
- Root `.cairn/plan.yaml` is tracked and should be treated as public project planning metadata, not runtime session state.
- `session-fanout` is not implemented yet.

## Target Architecture

### Source Layout

Use the existing feature-pack shape where possible:

```text
feature-pack/<name>/
  README.md
  INSTALL.md
  manifest.json
  skill/SKILL.md
  core/ or cli/
  test/verify.md
```

Shared scripts that are not a single skill may live under a package such as:

```text
feature-pack/session-fanout/
feature-pack/session-rollover/
hooks/
  manifests/
  adapters/
  runners/
```

### Runtime Surfaces

- Claude: `~/.claude/skills/<name>` remains the Claude runtime surface.
- Codex/OMX: `~/.codex/skills/<name>` remains the Codex runtime surface unless active Codex behavior proves otherwise.
- Neutral shared layer: `~/.agents/` may hold shared `bin`, state, install metadata, and optional compatibility links, but must not create duplicate skill entries.
- Project scope: `.claude/skills`, `.codex/skills`, and `.agents/skills` are opt-in project overlays and must be audited separately.

## Execution Phases

### 0. Public Safety Baseline

Before adding install or migration commands:

- Scan tracked and untracked candidates for credentials, auth tokens, raw session transcripts, local MCP configs, generated logs, and private settings.
- Make repo-local ignore rules explicit for `.omc/`, `.omx/`, `.baton/`, `.fable-team/`, nested feature-pack runtime state, caches, and local logs.
- Keep intentionally tracked planning files such as `.cairn/plan.yaml` only if they contain public-safe project metadata.
- Produce a public-safety report that distinguishes "tracked and safe", "ignored local state", "must never commit", and "needs manual review".

This phase is read-only except for optional `.gitignore` tightening after review.

### 1. Dry-Run Inventory

Implement a script that reads only safe metadata:

- Skill roots: `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`
- Project roots: `.claude/skills`, `.codex/skills`, `.agents/skills`
- Public package roots: `~/Project/ai-feature-pack/feature-pack/*`
- Hook config locations by path only, without printing secrets or full private contents

Classify each entry as:

- source-owned
- symlink to source
- generated runtime install surface
- native runtime skill
- private/local-only
- broken link
- duplicate exposure risk

The dry run must print proposed actions and rollback commands. It must not write files.

Minimum output:

- JSON report for tools and tests.
- Human report for review.
- Proposed installer actions without applying them.
- Proposed rollback commands for every write that a future installer would make.
- "Skipped private file" list by path class, not by sensitive content dump.

Suggested JSON shape:

```json
{
  "repo_root": "/path/to/ai-feature-pack",
  "public_safety": {
    "tracked_safe": [],
    "ignored_runtime_state": [],
    "must_not_commit": [],
    "manual_review": []
  },
  "sources": [],
  "runtime_surfaces": [],
  "project_surfaces": [],
  "hooks": [],
  "duplicates": [],
  "broken_links": [],
  "proposed_actions": [],
  "rollback": [],
  "skipped_private": []
}
```

Path policy:

- Expand `~` and env vars only internally; report paths should prefer `$HOME` or repo-relative forms when possible.
- Preserve absolute paths in rollback commands only when required for an exact local operation.
- Never infer that a runtime loads a root just because a directory exists; record it as "present, load behavior unverified."

### 2. Source Normalization

- Use `feature-pack/<name>` as source for existing packages.
- Repair broken pointers, especially `cairn`, to the live `feature-pack/cairn` source.
- Leave runtime-native Codex/OMX skills in `~/.codex/skills` unless there is a clear shared-source package.
- Import missing important skills only after checking public-safety and license/secret exposure.
- Normalize package manifests so each shareable package declares its skill surfaces, commands, hook adapters, public docs, and private state exclusions.
- Replace hardcoded absolute paths with `$HOME`, repo-root discovery, or explicit config defaults.

### 3. Shared Skill Exposure

The installer should generate runtime links, not duplicate source:

- Claude link target: source package skill or Claude adapter.
- Codex link target: Codex-compatible skill surface under `~/.codex/skills`.
- Neutral command target: `~/.agents/bin/<command>` for shared CLI wrappers.

Do not make `~/.agents/skills` the single active Codex skill root unless the active Codex version is verified to load it without duplication.

Recommended default:

- Keep `~/.claude/skills` as the Claude runtime skill root.
- Keep `~/.codex/skills` as the Codex/OMO runtime skill root.
- Use `~/.agents` as neutral shared infrastructure: `bin`, `state`, install manifests, reports, and command wrappers.
- Use `.agents/skills` only as a compatibility or project overlay after runtime behavior is proven.

### 4. Hook Architecture

Move toward:

```text
hooks/manifests/<hook>.json
hooks/adapters/claude-<hook>.sh
hooks/adapters/codex-<hook>.sh
hooks/runners/<hook>.sh
```

Rules:

- Public source stores manifests, adapters, runners, tests, and docs.
- Local `~/.claude/settings.json` and `~/.codex/hooks.json` remain generated private install surfaces.
- Existing fable-team context/orchestration hooks are reference implementations, not the final cross-agent contract.
- Hooks warn and prepare at thresholds; user command triggers rollover/fanout.

Threshold policy:

- 30-40% remaining context: boundary warning and next-session preparation hint.
- 60-70% remaining context pressure: stronger warning and rollover recommendation.
- The hook does not perform destructive cleanup or forced session moves.
- Rollover executes only when the user requests it through aliases or explicit natural language.

Hook implementation policy:

- Manifest describes event, thresholds, commands, and safety class.
- Adapter translates a manifest to each runtime's local hook format.
- Runner performs the actual local command with dry-run support.
- Generated local settings must be backed up and reversible.

### 5. Session Lifecycle Utilities

Implement separately:

- `session-rollover`: one next numbered session, baton handoff, old-session graceful close.
- `session-fanout`: multi-lane split, fan-in, and cleanup.

Trigger split:

- Rollover aliases: `세션증류`, `증류`, `세션만들기`, `신규세션`
- Fanout alias: `분리`

Safety:

- Default cleanup is non-destructive.
- `--fast-cleanup` shortens waiting but still writes baton handoff.
- Force kill requires `--force-close` or explicit user instruction.
- Default old-session behavior is "recommend close, verify idle, then close gracefully."
- If there is no previous baton state, create a new session by default and prepare baton resume from the current context.
- If the user explicitly asks to continue the current session, support baton save, cleanup, and resume without creating a new session.

### 6. Session-Fanout Contract

Default six lanes:

- `implementer`
- `code-reviewer`
- `log-reviewer`
- `architect-reviewer` or `doc-reviewer`
- `researcher`
- `e2e`

Default topology:

- The invoking session is the main coordinator.
- `main-orchestrator` is not created unless explicitly requested.
- If requested, it is the seventh lane and receives the coordination message.

Naming:

- Generate one UUID per fanout run.
- Derive a stable uppercase 3- or 4-character suffix, preferably 4 characters.
- Apply the same suffix to all lane names, for example `implementer-4DG8`, `e2e-4DG8`.

Command contract:

```bash
session-fanout start [--lanes <csv>] [--with-main-orchestrator] [--suffix <id>] [--dry-run]
session-fanout status <suffix>
session-fanout fan-in <suffix> [--to invoking|main-orchestrator]
session-fanout cleanup <suffix> [--fast-cleanup] [--force-close]
```

State:

- Store private run state outside public source, for example `~/.agents/state/session-fanout/runs/<suffix>.json`.
- State must allow `status`, `fan-in`, and `cleanup` after the invoking session restarts.
- State may include local paths/session IDs and must not be committed.

### 7. Fable-Team Integration

Keep fable-team's native Claude design intact:

- fable-team owns its Claude Agent/Workflow worker orchestration.
- fable-team owns `.fable-team/state/` when it is the active policy.
- `session-fanout` is an optional helper, not a required backend.
- Codex/OMO should consume fable-team as policy/docs/presets/adapters unless a future Codex-compatible implementation is explicitly built.
- Do not claim Claude Agent/Workflow parity in Codex/OMO.

Integration direction:

- Add `session-fanout` as an optional helper/preset, not as fable-team's required backend.
- Let fable-team decide at runtime whether to use its own ultracode/team workflow, Claude subagents, panes, or the common fanout helper.
- For Codex/OMO, ship fable-team-compatible policy docs and presets first; only claim executable support after a verified Codex/OMO harness exists.

## Readiness Gates

Before any live migration:

- Public-safety scan is clean or every finding is intentionally ignored with a reason.
- Dry-run inventory exists and runs without writing.
- Public source scan excludes auth, tokens, session transcripts, raw logs, MCP private configs, local settings, and generated runtime state.
- Every proposed symlink has a valid target and rollback command.
- Broken `cairn` link is detected and mapped to `feature-pack/cairn`.
- Codex exposure decision is based on active behavior, not the old `~/.agents/skills` assumption.
- Hook adapter dry run shows exact edits for Claude and Codex without applying them.
- `session-rollover --dry-run` exists before live session rollover.
- `session-fanout start --dry-run` exists before live session fanout.

## Verification Plan

Minimum dry-run checks:

```bash
agent-surface-audit --dry-run
agent-surface-audit --dry-run --public-safety
agent-surface-audit --dry-run --json /tmp/agent-surface-audit.json
session-rollover --dry-run
session-fanout start --dry-run
session-fanout start --dry-run --with-main-orchestrator
session-fanout start --dry-run --lanes implementer,e2e
```

Expected results:

- No writes to user config.
- No private secrets in stdout.
- Six fanout lanes by default.
- Seven lanes only with `--with-main-orchestrator`.
- All fanout lanes share one suffix.
- Codex dry run generates `tmuxc open ... --agent codex`.
- OMX dry run generates `tmuxc open ... --agent omx`.
- Cleanup dry run does not force-kill sessions unless `--force-close` is present.

## Execution Preparation Backlog

Build in this order:

1. `agent-surface-audit --dry-run`: inventory, public safety, proposed actions, rollback commands.
2. Source manifest normalization: package metadata for skills, commands, hooks, exclusions, and runtime targets.
3. Hook scaffold: `hooks/manifests`, `hooks/adapters`, `hooks/runners`, with dry-run rendering for Claude and Codex.
4. Shared installer dry run: generate proposed links/wrappers/settings without writing.
5. `session-rollover --dry-run`: baton handoff, tmuxc next-session command, graceful close plan.
6. `session-fanout start/status/fan-in/cleanup --dry-run`: six-lane default, optional main-orchestrator, suffix state.
7. Fable-team adapter docs/presets: optional use of common helpers without replacing native fable-team.
8. Live apply mode only after the reports are reviewed and the rollback plan is acceptable.

## Immediate Ready-To-Run Checklist

Before writing `agent-surface-audit`:

- Choose its package location, preferably `feature-pack/agent-surface-audit/` unless it belongs under a broader installer package.
- Decide the public command name, defaulting to `agent-surface-audit`.
- Define read-only probes for `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`, project overlays, `feature-pack/*`, and hook config paths.
- Define private-file classifiers before reading file contents.
- Add fixture-based tests with fake home/repo directories so no test touches real user config.
- Add a manual dry-run command that prints no secrets and exits non-zero only for tool errors, not for findings.

Acceptance criteria for the first implementation:

- Running the command with `--dry-run` performs no writes.
- Running it with fake fixtures detects source packages, runtime links, duplicate names, broken links, skipped private files, and proposed rollback commands.
- Running it in the real repo can inspect metadata without dumping private settings.
- The report clearly says Codex skill exposure remains `~/.codex/skills` until active load behavior proves otherwise.
- All paths and defaults are configurable; no user-specific absolute path is hardcoded.

## First Implementation Target

Implement `agent-surface-audit --dry-run` first. It should produce a JSON and human-readable report with:

- discovered sources
- runtime surfaces
- broken links
- duplicate risks
- proposed link/create/update actions
- skipped private files
- rollback commands

Only after that report is reviewed should any live symlink, hook config, or runtime command be changed.
