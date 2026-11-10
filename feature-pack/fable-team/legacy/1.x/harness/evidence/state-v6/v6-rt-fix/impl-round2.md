# IMPL Round 2 — FE half of RT-solo regression fix (COMMIT 2)

**Status: IMPLEMENTED** · tsc PASS · full web jest PASS (161 suites / 1508 tests) · eslint 0 errors.
Worktree `feat/v6-realtime-live`. Worker half (INV-3/4/1/5) already landed = `b2752f53`.

## Changed files (4)
- `clients/web/src/domains/realtime/use-realtime-solo-v5.ts` — PART A + PART B (hook).
- `clients/web/src/domains/realtime/v5-segment-reducer.ts` — INV-6 reducer default removal.
- `clients/web/__tests__/unit/domains/realtime/use-realtime-solo-v5.test.ts` — regression-guard test rewritten to new contract.
- `clients/web/__tests__/unit/domains/realtime/v5-transcripts.test.ts` — 2 reducer tests updated to new contract.

(NOT committed: `tests/e2e/.../multi_realtime_corpus.jsonl` — pre-existing dirty file from session start, unrelated.)

## PART A — per-press id persistence (INV-6 + [T-abort]) — DONE
- `:361` (`${sessionId}:ptt:${uuid}`) is now the **SOLE (re)assignment point** of `pulseSessionIdRef` per press.
- Removed ALL 5 bare-session reverts (`= sessionIdRef.current`): onToggleStop (`:343`), press initError (`:404`), press !stream (`:410`), release (`:546`), reset (`:594`). Each replaced with an explanatory comment.
- Net: every chunk of press N — including the trailing/final flush that POSTs after release — carries press N's `:ptt:` id. The next press re-mints fresh. Toggle-stop keeps the same id (guarded by `isToggleStopClick`, unchanged). Aborted/late chunks are the worker's tombstone concern (INV-6 [T-abort]).
- `buildParams` unchanged (`pulseSessionIdRef.current || sessionIdRef.current`); the `||` covers the pre-first-press empty-string only.

## PART B — routing (INV-2 / INV-6) — DONE (implemented as the contract's preferred option i)
- **Attribution is now seat-anchored, never lang-derived.** `sideForLang(ev.lang)` deleted (helper + call + `V5Side` import + `press` dep). `ev.lang`/`source_lang` retained ONLY for display (`segCtx.lang`) per R5 audit.
- **Primary anchor = per-`pulse_session_id` side map** (`sideByPsidRef`): populated at press mint (`psid → pressed side`), looked up by the event's `utterance_id ?? pulse_session_id`. Fallback chain: `map → activeSideRef → lastPressedSideRef`. Cleared on reset.
- `lastPressedSideRef` added (set at press, never nulled) = the "last-pressed seat" null-fallback the contract mandates (replaces the hard `'self'`). Pre-first-press only → `'self'`.
- `v5-segment-reducer.ts:108`: removed the hard `?? 'self'` last-resort → `(current?.side ?? ctx?.side) as V5Side`. Seat is now authoritative from the hook's `ctx.side` (always defined for seat-bearing events; `applyV5Event` is solo-only — verified sole consumer).

## DEVIATION from the literal note (rationale — please review)
Team-lead PART B said "anchor to the PRESSED seat (**activeSideRef**)" + ":547 stop nulling activeSideRef" + "null-fallback = last-pressed seat". I implemented the **contract's INV-6 [T] option (i): per-`pulse_session_id` side map** as the PRIMARY, with `activeSideRef → lastPressedSideRef` as the fallback, and did NOT change the `activeSideRef = null` nulling at release/abort (kept surgical; the map + `lastPressedSideRef` make the nulling harmless).

**Why:** the existing unit test `use-realtime-solo-v5.test.ts` "다중 in-flight press 늦은 confirmed 오귀속 방지" is a **deliberate regression guard**. With `lastPressedSideRef` ALONE, an earlier LEFT press's late `segment.confirmed` (arriving after a later RIGHT press) attributes to the LAST-pressed seat (RIGHT/self) — **re-introducing the exact cross-press misattribution the guard protects against** (and INV-6 §V requires correct attribution across "alternating seats" + "post-release-stamped confirmed"). The per-psid map resolves each event to ITS OWN press's seat (race-free), which is why the contract lists it FIRST. Events now carry the id (INV-1 landed), so the map is viable. This is a superset of the literal note (still seat-anchored, still zero `ev.lang` routing) that also passes the regression guard.

## Tests updated (contract changed → tests follow, not "made to pass")
1. `use-realtime-solo-v5.test.ts` interleave guard — rewritten: stamps events with `pulse_session_id` (captured via `buildParams().pulseSessionId`), asserts s1(left psid)→`other` and s2(right psid)→`self` with **`ev.lang=ko` forced on s1** (proves seat wins over lang = INV-2). Also asserts `psid1 !== psid2` (PART A per-press mint) and finds bubbles via `segmentIds[]` (grouping is now cycle/psid-keyed because `groupByUtterance`+`cycleId` went LIVE — the intended INV-1 effect).
2. `v5-transcripts.test.ts (6)` — was "reducer 기본 self"; now asserts seat comes from `ctx.side` (both directions).
3. `v5-transcripts.test.ts (ctx 미지정)` — was "ctx 없으면 self"; now asserts NO independent `'self'` default (side `undefined` in the degenerate ctx-less path that production never exercises — hook always supplies `ctx.side`).

## Verify
- `npx tsc --noEmit` → exit 0 (tsconfig includes `**/*.ts`, tests covered).
- `npx eslint <4 files>` → 0 errors, 2 warnings (pre-existing `arrivalIntervalMsRef.current` ref-in-render at the return object, lines shifted +10, NOT introduced here).
- `npx jest` (full) → 161 suites / 1508 tests PASS.

## End-to-end coherence / residual risk for live BTS
- Primary BTS (5 same-side ko presses → 5 distinct bubbles): PART A gives distinct `press_id=…:ptt:<uuid>` per press; worker (INV-3) loads `previous_text_len=0` at each new press; cycleId=psid → 5 cycles → 5 bubbles. Seat map trivially correct (same side).
- Map key match depends on worker echoing `utterance_id` = the FULL FE-minted psid (INV-1 + INV-3 no-strip, landed in `b2752f53`). On any format mismatch the map misses and falls back to `activeSideRef/lastPressedSideRef` — still correct for same-side presses; only interleaved presses would misattribute. Live BTS to confirm the `[pulse.route] routed_side == pressed_side` signature and the `dom_original_delta > 0` (5 bubbles).
