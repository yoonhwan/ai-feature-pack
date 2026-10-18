# DA mr-guest-connect-fix Impl Gate Round 1
reviewed: mrfix-v2-impl
session-id: 019f25dd-8123-7ef3-aa0d-599090231e0d

## VERDICT: CHANGES_REQUESTED

### Codex (GPT-5.5 xhigh) Judgment

- 5b semantics are correct: `guestConnectReady === false` blocks, `onSttConnect(...) !== false` is the only latch path, and `undefined` remains back-compatible.
- Station/STT code matches v2: ready formula, timer cleanup/ref re-check, stale-clear reload path, boolean `connect`, visible errors, fetchHeaders guest guard.
- Transport change is scoped: 3 `fetchHeaders` calls moved inside `try`, no other logic drift found.
- No source caller break found; `useRealtimeStt`/lifecycle are only wired by station. Targeted tests and `tsc --noEmit` pass.
- **Blocker**: `realtime-room-station-seed-timeout.test.ts` tests a copied local hook, not the station path, and misses normal dialog join + unmount cleanup. Add a station-level test pinning reload-restore timeout and non-fire on normal join.

### Resume info
- resume used: `019f25dd-8123-7ef3-aa0d-599090231e0d` (succeeded — no fallback needed)
- tokens: 79,536
