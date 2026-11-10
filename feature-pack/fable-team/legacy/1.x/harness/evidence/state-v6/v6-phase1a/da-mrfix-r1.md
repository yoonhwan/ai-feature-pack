# DA mr-guest-connect-fix Round 1 — design v1
reviewed: mrfix-v1
session-id: 019f2437-eb00-70d3-acfe-15e09c8f9649

---

VERDICT: CHANGES_REQUESTED

- 5b gating is sound: strict `guestConnectReady === false` + dep reruns false→true with updated `connectConfig`; omitted prop stays back-compatible.
- `guestLang` is the right gate for normal join and reload restore; `effectiveGuestLang` would preserve the wrong fallback-lock bug.
- Blocker: "seed absent → dialog re-entry" is false. Restored `guest` skips `GuestEntryDialog`, and guest dock hides connect, so missing `roomLangSeed[self]` can silently never connect.
- SessionKey derivation is OK via `wsUserId=user?token=...`; guard error is visible, but don't latch `guestConnected` before a guarded no-op if recovery matters.
- Moving `fetchHeaders()` into transport `try` blocks is correct; host/solo/lecture only change is header failures now reach `onError`.
