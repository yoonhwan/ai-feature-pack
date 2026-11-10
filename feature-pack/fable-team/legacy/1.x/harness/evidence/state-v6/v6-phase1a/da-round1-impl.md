# DA Impl Gate Round 1 — design-n1-lst-v3.md implementation
reviewed: v3-impl
session-id: 019f2437-eb00-70d3-acfe-15e09c8f9649

## VERDICT: CHANGES_REQUESTED

### Blocking Issue (must fix before APPROVED)

**Race condition in `use-energy-chunker.ts:131`**: `m.lstActive` is snapshotted from `p.current.lstEnabled` *after* the `await createPcmCapture()` call at `:122`. A user toggle during the async startup window therefore changes `lstActive` mid-press, silently activating or skipping LST against the user's intent at press time.

**Required fix**: Move `m.lstActive = p.current.lstEnabled` (snapshot) to *before* the first `await`, next to the buffer reset — so it captures the state at press-start, not at capture-ready.

### Test Gap (blocking — design mandates race coverage)

Tests C1/C2 only exercise the post-`start()` resolved path. There is no test case with a deferred `createPcmCapture` that toggles `lstEnabled` before resolution. This gap means the blocking race above is not caught by the test suite.

**Required fix**: Add a test that resolves `createPcmCapture` manually (deferred promise) and toggles `lstEnabled` between `start()` call and resolution, asserting `lstActive` reflects the snapshot at press-start.

### Passing Checks

- **`use-lst-setting.ts`**: URL-source path avoids localStorage write ✅; KILL forces `lstEnabled=false` + no-op setter + `lstAvailable=false` ✅; `hydrated` guard prevents pre-hydration flicker ✅; `getServerSnapshotForTest` wrapper present ✅; `[conversation:settings]` log emitted with source tags (hydrate/toggle/url) ✅
- **`lstActive` lifecycle**: initialized `false` ✅; `start()` snapshots into `mut.lstActive` ✅; frame guards (`:111`/`:143`) read `mut.lstActive` (not `p.current.lstEnabled`) ✅; `stopLstLoop()` sets `lstActive = false` ✅; reset path calls `stopLstLoop` ✅
- **Consumer replacement**: no `isLstEnabled()` calls remain outside `app-config` ✅
- **Settings panel**: `{lstAvailable && ...}` conditional renders LST row ✅; `useMemo` deps array includes `lstEnabled`, `lstAvailable`, `setLstEnabled` ✅

### Non-Blocking Coverage Gaps (informational)

- A9 verifies `polishDiff` only through the LST branch; `useConversationSettings` `showPolishDiff` cross-param path not independently asserted.
- B2 does not spy `selectBubbles`; snapshot call count unverified.

### Evidence Source

codex resume session `019f2437-eb00-70d3-acfe-15e09c8f9649`, tokens used: 292,508, reasoning effort: xhigh.
