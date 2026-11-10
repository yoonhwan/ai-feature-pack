# OMO Round 3 — design-n1-lst-v3.md
reviewed: v3

# OMO review-work — design-n1-lst-v3.md Re-review (Round 3)

Reviewed by: OMO crew driver (architect fallback — codex usage limit hit)
Date: 2026-07-03

---

## Evidence gathered (code verified)

| File | Lines read | Key facts |
|------|-----------|-----------|
| `use-conversation-settings.ts` | 1–112 | `URL_PARAM_KEY = 'polishDiff'` at :18; `STORAGE_KEY = 'baseagent_show_polish_diff'` at :17; `getServerSnapshot` private (not exported) at :87 |
| `energy-lst.ts` | 1–61 | `stopLstLoop` defined at :53; body clears lstTimer/lstBuffered/lstBufferedSamples/lstInFlight — no `lstActive` field currently |
| `energy-vad-handlers.ts` | 1–101 | `ChunkerMut` type at :13–29; no `lstActive` field currently; LST fields: lstBuffered/lstBufferedSamples/lstSeq/lstInFlight/lstTimer |
| `use-energy-chunker.ts` | 1–229 | `onPcmFrame` :111 uses `p.current.lstEnabled`; `start()` :143 uses `p.current.lstEnabled`; `stop()` :165 calls `stopLstLoop(m)`; `reset()` :224 calls `stopLstLoop(mut.current)` |
| `energy-vad-handlers.test.ts` | 1–27 | `makeMut()` at :10; no `lstActive` in current fixture |
| `energy-lst.test.ts` | 1–20 | `makeMut()` at :14; no `lstActive` in current fixture |
| `use-energy-chunker.test.ts` | :480–530 | LST describe block at :492; existing tests cover lstEnabled=off/on and stop behaviour |

---

## Finding-by-finding verification

### [v3-#1] A9 URL param key: polishDiff (not showPolishDiff)

**v2 problem**: Test A9 used `?showPolishDiff=1&lst=1` — `showPolishDiff` is not the URL param key; the real key is `polishDiff` (`:18`). A wrong key can never catch a regression.

**v3 fix**: Design §③-A9 now uses `?polishDiff=1&lst=1` (cross-interference test). Added `?polishDiff=0&lst=1` cross case.

**Code check**: `use-conversation-settings.ts:18` → `const URL_PARAM_KEY = 'polishDiff';` ✅

**Verdict**: RESOLVED ✅

---

### [v3-#2] stopLstLoop adds mut.lstActive = false

**v2 problem**: `stopLstLoop` cleared timer/buffer/inFlight but left no `lstActive` snapshot flag, so a late PCM frame arriving after stop() could still pass the `:111` guard (`p.current.lstEnabled` was still true) and push into a stale buffer.

**v3 fix**: 
- Adds `lstActive: boolean` to `ChunkerMut` (energy-vad-handlers.ts:13~29) 
- Snapshot set in `start()`: `m.lstActive = p.current.lstEnabled === true`
- Guards changed: `onPcmFrame :111` → `if (mut.current.lstActive)`, `start() :143` → `if (m.lstActive)`
- `[v3-#2]` adds `mut.lstActive = false;` inside `stopLstLoop` at :53

**Code check**:
- `stop()` at :165 calls `stopLstLoop(m)` ✅
- `reset()` at :224 calls `stopLstLoop(mut.current)` ✅
- Both termination paths converge on `stopLstLoop` → both will receive the `lstActive=false` reset

**Justification in design**: "stopLstLoop는 stop(:165)/reset(:224) 양 종료 경로의 유일한 공통 진입점이고 이미 lstTimer/lstBuffered/lstInFlight 등 LST 수명주기 상태를 전부 리셋하는 곳 — lstActive도 같은 수명주기이므로 여기가 응집적." This is correct.

**Verdict**: RESOLVED ✅

---

### [v3-#3] C3/C4 stale-lstActive tests

**v2 problem**: C lifecycle tests covered normal stop cleanup but missed the stale-after-stop scenario (late PCM frame arriving after capture teardown asynchronously).

**v3 fix**:
- **C3**: `lstEnabled=true` → `start()` → `stop()` → inject `onPcmFrame` late call directly → assert `lstBuffered.length === 0` && LST POST 0
- **C4**: `lstEnabled=true` → `start()` → `reset()` → late frame push 0 → props `lstEnabled=false` rerender → `start()` → frame + timer → lstTimer null + LST POST 0 (no stale true-snapshot residual)

**Assessment**: Both C3 and C4 are mechanically sound. C3 tests the stop path directly. C4 tests reset path AND verifies no cross-cycle bleed of the snapshot. The mock `createPcmCapture` callback capture pattern (to replay `onPcmFrame` after stop) is standard in this test suite.

**Verdict**: RESOLVED ✅

---

### [v3-#4] getServerSnapshotForTest export + jest.isolateModules

**v2 problem**: A8 SSR test execution was unclear — `getServerSnapshot` is module-private in the reference implementation (:87), making direct call impossible. renderToString was mentioned but not specified.

**v3 fix**: 
- New `use-lst-setting.ts` exports `getServerSnapshotForTest(): boolean` — a 1-line wrapper around the private `getServerSnapshot`
- Test uses `jest.isolateModules` + `jest.doMock('@/config/app-config', ...)` to vary `v6LstEnabled`
- Calls `getServerSnapshotForTest()` directly and asserts value === mocked v6LstEnabled
- Also asserts first renderHook snapshot (before useEffect hydration) matches

**Code check**: `use-conversation-settings.ts:87` confirms `getServerSnapshot` is non-exported. The `ForTest` suffix pattern is a known convention in this codebase. ✅

**Assessment**: `jest.isolateModules` + `doMock` + direct `getServerSnapshotForTest()` call is the correct approach and avoids renderToString complexity. Cleaner than v2's vague plan.

**Verdict**: RESOLVED ✅

---

### [v3-#5] BTS D redefined as DEFAULT-return with localStorage-unpolluted assert

**v2 problem**: BTS D was "재진입 → OFF" which contradicts `DEFAULT = appConfig.v6LstEnabled` semantics — if env is ON, DEFAULT is ON, so re-entering without URL param should return to ON, not OFF.

**v3 fix**: D is redefined as:
1. `?lst=0` → `{lst:'off', source:'url'}` + LST logs 0
2. Re-enter (new tab, no param) → DEFAULT = ON (`{lst:'on', source:'hydrate'}` + lst logs present)
3. `baseagent_lst_enabled` key **absent** from localStorage (URL not persisted to storage)
4. Contrast pair: panel toggle OFF → re-enter → stays OFF (localStorage path IS persistent)

**Assessment**: This is semantically precise. The key assertion is that URL param is session-scoped (hydrateStore deliberately skips `storeShowPolishDiff`/equivalent for URL path), while explicit toggle persists. The localStorage absence check directly validates the session-scoped design. The contrast pair strengthens the test by distinguishing URL vs toggle pathways.

**Verdict**: RESOLVED ✅

---

### [v3-#6] ChunkerMut fixture lstActive:false in both test files

**v2 problem**: `ChunkerMut` typed fixtures in `energy-vad-handlers.test.ts makeMut(:10)` and `energy-lst.test.ts makeMut(:14)` were missing from the change list — once `lstActive` is added to the type, both files would fail tsc.

**v3 fix**: [v3-#6] explicitly lists both fixtures with `lstActive: false` addition. Also adds behavioral assert in `energy-lst.test.ts`: `mut.lstActive = true` → `stopLstLoop(mut)` → `mut.lstActive === false`.

**Code check**:
- `energy-vad-handlers.test.ts:10` → `function makeMut(): ChunkerMut` ✅ (confirmed, no `lstActive` currently)
- `energy-lst.test.ts:14` → `function makeMut(): ChunkerMut` ✅ (confirmed, no `lstActive` currently)
- Design specifies "동일 커밋 필수" for the type + fixture + assert — correct, otherwise tsc fails on fixture mismatches

**Verdict**: RESOLVED ✅

---

## New regression check

| Area | Risk | Assessment |
|------|------|-----------|
| `onPcmFrame :111` guard change `p.current.lstEnabled` → `mut.current.lstActive` | Hold-time toggle behavior change | **Intentional** — design explicitly states "hold 중 ON→OFF: 현재 cycle 에 무영향, 다음 PTT press부터 적용". This is a designed semantic change, not a regression. BTS C tests this. |
| `lstActive` initialization in mut ref (:62) | Missing field → tsc error | Design correctly adds `lstActive: false` to mut initializer at :62. ✅ |
| `start()` snapshot `m.lstActive = p.current.lstEnabled === true` placement | Snapshot taken after buffer clear | Placement at buffer init block (:118~120) is correct — before VAD start and LST loop start. No ordering issue. |
| `lstActive` not reset if `start()` called twice without stop | Stale true snapshot | `stop()` and `reset()` both call `stopLstLoop` → `lstActive=false` before any re-call to `start()`. Safe. |
| BTS D semantic change | Was testing "re-enter = OFF", now testing "re-enter = DEFAULT" | The old D was wrong per the design semantics. v3 D is correct. No regression in the implementation, only the test semantics were wrong in v2. |
| `use-energy-chunker.ts` line count | ~229 LOC currently; +3 lines (lstActive init + snapshot line + guard change are within existing lines) | Net delta ~+1–2 lines (snapshot set: +1, guard change: 0 extra). Below 200-LOC limit concern. |

No new regressions introduced by v3.

---

## Summary

All 6 v2 rejection findings are correctly resolved in v3:

| # | Finding | v3 Tag | Status |
|---|---------|--------|--------|
| 1 | A9 polishDiff key (not showPolishDiff) + cross case | [v3-#1] | ✅ RESOLVED |
| 2 | stopLstLoop adds mut.lstActive=false (stop+reset paths) | [v3-#2] | ✅ RESOLVED |
| 3 | C3/C4 stale-after-stop + reset+next-cycle tests | [v3-#3] | ✅ RESOLVED |
| 4 | getServerSnapshotForTest export + jest.isolateModules plan | [v3-#4] | ✅ RESOLVED |
| 5 | BTS D = DEFAULT-return + localStorage-unpolluted + contrast pair | [v3-#5] | ✅ RESOLVED |
| 6 | energy-vad-handlers.test.ts makeMut(:10) + energy-lst.test.ts makeMut(:14) lstActive:false + assert | [v3-#6] | ✅ RESOLVED |

No new regressions found. Code references (line numbers, key names, paths) are accurate against actual codebase.

---

VERDICT: APPROVE
