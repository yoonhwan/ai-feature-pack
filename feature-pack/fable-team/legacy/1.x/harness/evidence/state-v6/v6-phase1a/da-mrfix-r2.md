# DA mr-guest-connect-fix Round 2 — design v2
reviewed: mrfix-v2
session-id: 019f25dd-8123-7ef3-aa0d-599090231e0d
resume-chain: FALLBACK (resume 019f2437-eb00-70d3-acfe-15e09c8f9649 failed — codex resume does not support -C flag; proceeded as one-shot with full context inline)

## VERDICT: APPROVE

- **[v2-#1] timer effect cleanup verified**: `guestLang !== null` in deps causes React cleanup to cancel the timeout when seed restoration lands — no false-trigger.
- **[v2-#1] re-entry path verified**: `onGuestStaleClear` at :88-93 clears persisted guest state + reloads; after reload `guest=null` → `isGuest && !guest` branch at :394 shows `GuestEntryDialog`.
- **[v2-#1] normal dialog join safe**: timer skips because `guest=null` before entry; `onEnter` sets `guestLang` before `guest` is resolved, so timer condition remains false.
- **[v2-#2] back-compat confirmed**: ignored boolean return at handleConnect:365 is harmless; `undefined !== false` preserves void/mock latch behavior; `false` return leaves latch unset → retry on dep change.
- **Minor hardening (non-blocking)**: timeout callback could re-check latest `guestLang` via ref to avoid edge race at 10s boundary — not a blocker.
