# DA Round 2 — design-n1-lst-v2.md
reviewed: v2
session-id: 019f2437-eb00-70d3-acfe-15e09c8f9649

## VERDICT: CHANGES_REQUESTED

Codex (GPT-5.5, reasoning xhigh) reviewed design-n1-lst-v2.md via RESUME of round-1 session (019f2437-eb00-70d3-acfe-15e09c8f9649). All 3 original rejection points were checked against actual code files.

### Bullets (from codex)

1. **Test gap — wrong canonical key**: Coexistence test uses `showPolishDiff` but the actual hook (`use-conversation-settings.ts`) uses `polishDiff`. Test would never fail on a real regression.

2. **URL fix — SOUND**: No localStorage backwrite for `?lst=1`; explicit toggle only persists. Fix is correct and complete.

3. **Kill-switch fix — SOUND**: `appConfig.v6LstEnabled` remains a hard gate; URL/localStorage are ignored and the panel is hidden when flag is false. Fix is correct and complete.

4. **Wiring fix — SOUND**: Replacing both `isLstEnabled()` consumers in `use-realtime-solo-v5.ts:315,700` covers the actual consumers. Fix is correct and complete.

5. **`lstActive` snapshot — INCOMPLETE**: `ChunkerMut` is confirmed in `energy-vad-handlers.ts`, but v2 leaves `stopLstLoop()` unchanged — `lstActive` can remain `true` after stop/reset, allowing late PCM callbacks and stale LST buffer issues. Must set `lstActive = false` in stop/reset, **or** clear LST buffers at the next `start()`.

### Required Fix Before Approval

- Fix 1 (blocking): Change `showPolishDiff` → `polishDiff` in the coexistence URL-param test.
- Fix 2 (blocking): Add `mut.lstActive = false` inside `stopLstLoop()` (or equivalent reset guard at `start()`).

### Resume Note

Session successfully resumed from round-1 id `019f2437-eb00-70d3-acfe-15e09c8f9649`. No fallback needed.
