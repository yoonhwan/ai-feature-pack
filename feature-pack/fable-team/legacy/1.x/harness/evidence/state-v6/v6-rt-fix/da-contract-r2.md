reviewed: v2 (contract rev2)

# V6 Shared-Pulse Contract — DA Adversarial Review (Round 2 — APPROVE)

**Session ID**: `019f2739-f654-77a1-9315-c7856fbcbdab` (codex gpt-5.5 xhigh, **RESUMED** from R1)
**Path used**: `codex exec resume <session-id>` (session persisted context across rounds)

## VERDICT: APPROVE ✅

All 5 Round-1 findings are **CLOSED** in contract rev2. The contract is now ready to gate code.

### Closure Summary

1. **#1 CLOSED — Logging concreteness (r1 finding #1)**:
   - §V INV-2/3/4 rows now specify canonical grep-able log signatures: `[pulse.route] press_id/pressed_side/source_lang/routed_side`, `[pulse.carry] load/store pulse_prev_len/pulse_residual_len`, `[pulse.confirm] action=replace|append`, `[pulse.guard] force_finalize residual_len>=20`.
   - Assertions are directly falsifiable: routed_side == pressed_side for ALL langs (incl. forced-ko-on-EN), press N load shows previous_text_len=0, zero raw+polished adjacency grep hits, guard fires for residual>=20.
   - ✅ Witness-able before/after in worker logs; FE can confirm via gateway log inspection.

2. **#2 CLOSED — R2 boundary (r1 finding #2)**:
   - INV-4 [T-boundary] defines the precise REPLACE-vs-MERGE gate: same `utterance_id` ⇒ REPLACE (raw+polished of one press, never concat); distinct release seqs under `broadcast_mode=="release"` ⇒ MERGE (intentional room stitch).
   - Decision rule is unambiguous for the implementer: identity-equal → replace, identity-distinct under release-mode → merge.
   - The `:685` seq-merge path MUST REPLACE within each seq before merging identity-distinct seqs — solo concat fix + MR seq-join can never collide.
   - ✅ Boundary prevents silent R2 risk of breaking MR seq-merge; implementer has clear precedence.

3. **#3 CLOSED — R4 late-post-abort (r1 finding #3)**:
   - INV-6 [T-abort] specifies TOMBSTONE for late-post-after-abort: aborted psid is retired (never reused), post-abort chunks are dropped-with-ERROR-log `[pulse.tombstone]`, next press mints fresh psid.
   - Rationale provided (vs drop=silent #0-RULE breach; vs new-press-epoch=resurrects cancelled audio).
   - ✅ Resolves R4 race-condition; preserves per-PTT identity without losing legitimate trailing audio.

4. **#4 CLOSED — R3 additive-only (r1 finding #4)**:
   - INV-1 [T-additive] explicitly states `utterance_id` is ADDITIVE field ONLY, never a grouping key for lecture/note.
   - Lecture / instructor / notetaker keep `segment_id+version` grouping per `7bceca3d`; `groupByUtterance` stays solo/MR-only.
   - Falsification method stated: Phase 3/4 lecture/note grouping must be byte-identical pre/post INV-1 emit change.
   - ✅ Protects lecture/note surfaces from unintended re-grouping; scope is explicit and verifiable.

5. **#5 CLOSED — R1 atomicity (r1 finding #5)**:
   - INV-3 [T-atomicity] mandates INV-3 (full per-press key) + INV-4 (polish REPLACE) ship in ONE atomic worker pass (same PR, same commit).
   - Proof provided that both staged orderings leave live concat/accumulation window: (i) INV-3 first, INV-4 lags → intra-utterance raw+polished concat persists; (ii) INV-4 first, INV-3 lags → cross-press accumulation persists.
   - ✅ Atomic mandate blocks unsafe staged PRs; no intermediate-state risk.

### New Risk Assessment (rev2 vs rev1)

**New risk from [T-boundary] gate (codex flagged):** The REPLACE-vs-MERGE logic depends on `utterance_id` uniqueness per press and per release-seq. If `utterance_id` is accidentally reused across presses or release sequences in MR, the boundary gate breaks silently (two distinct seqs get same `utterance_id` → incorrectly REPLACE when should MERGE, or vice versa).

**Mitigation (codex recommendation + contract):** Log seq identity in MR to catch accidental `utterance_id` reuse. The contract's existing [V] signals for INV-1 include "N PTT presses → N distinct `utterance_id`" — extend this to MR: "each release seq gets a distinct `utterance_id` within the release window" (can be logged in gateway emit path).

**Residual R5** (source_lang display-consumer audit): remains deferred to the implementer as a pre-code task (audit who reads `ev.lang` for non-routing; INV-2/C3 permit the field but forbid routing on it). Contract flags it; implementer must audit before deletion.

---

## Recommendation

**CONTRACT APPROVED FOR CODE GATE.** All 5 findings are closed. Implement per the §V BTS signals and §2 invariants. Atomic INV-3+INV-4 delivery is mandatory; Phase 0 contract authoring is complete; proceed to Phase 1 code (RT solo) with live BTS (5+ repeats, trusted-click, headed).

**Pre-code checklist**:
- ☑ All 5 r1 findings closed in rev2.
- ☑ Log signatures are concrete and grep-able.
- ☑ Boundaries are unambiguous (R2 gate, R4 tombstone).
- ☑ Additive-only scope is explicit (R3).
- ☑ Atomicity is mandated (R1).
- ⚠️ Pre-code task: audit display consumers of `source_lang` (R5).
- ⚠️ Pre-code task: plan MR seq-identity logging to guard [T-boundary] gate uniqueness.
