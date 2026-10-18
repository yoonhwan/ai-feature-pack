reviewed: v1 (contract)

# V6 Shared-Pulse Contract — DA Adversarial Review (Round 1)

**Session ID**: `019f2739-f654-77a1-9315-c7856fbcbdab` (codex gpt-5.5 xhigh)

## VERDICT: CHANGES_REQUESTED

The contract structure is sound and covers the core mechanisms (INV-1..7), but five gaps remain before it can gate code:

### Findings

1. **INV-1/2/6 routing coverage incomplete**: The contract correctly identifies that solo seat attribution must be anchored to pressed button (not `source_lang`), but the verification signal for "routing is independent of source_lang" (§V, INV-2) is too abstract. Must add a concrete falsifiable log: `[press_id, pressed_side, source_lang, routed_side]` so test harness can confirm side matches pressed button regardless of reported lang.

2. **INV-3/4 verification gaps**: INV-3 (carry keyed on full per-press id) and INV-4 (polish replaces, no concat) are correctly stated, but §V §3 and §4 lack before/after carry-buffer logs keyed by full per-press id. Without worker-log visibility into `pulse_prev/pulse_residual` state at carry-load boundaries, falsification is indirect (only visible as "bubble accumulated text" downstream).

3. **INV-4/R2 unresolved collision**: Polish-REPLACES fix (§2 L63-67) must NOT break the intentional MR `_merge_utterance_buffer:685` seq-merge (SYNTHESIS Phase 2). Contract states broadcast_mode gates the two regimes (INV-5), but does not define the precise boundary: "replace confirmed within same utterance" vs "merge distinct MR release sequences." Implementer guidance needed before code; otherwise R2 risk persists.

4. **INV-6/R4 race-condition open**: The contract says "stop reverting psid on release/abort" (§2 L82) but does not address: what if a chunk posts AFTER abort with a reused psid? Current text leaves late-post-abort semantics open (should chunk be dropped, tombstoned, or trigger a new press epoch). This is explicitly flagged as R4 in §Risks but not resolved.

5. **R1+R3 tightening**: (a) INV-1's "utterance_id on every event" risks perturbing lecture/note's `segment_id+version` grouping (7bceca3d directive). Contract §2 L48 and R3 §114-118 flag the risk but do NOT explicitly state "utterance_id is ADDITIVE field only, never grouping key for lecture/note." (b) INV-3 (full per-press key) + INV-4 (polish replace) touch overlapping seams in `pulse_consumer.py`. If delivered in separate PRs, intermediate state still concats (per SYNTHESIS §3 mechanism). R1 §114-116 flags; contract should mandate atomic INV-3+INV-4 delivery or document why staged is safe.

### Recommendation

**Approval gates on clarifications**:
- Add concrete log signatures to §V (INV-2, INV-3, INV-4).
- Resolve R2 boundary (replace-same-utterance vs merge-release-seq).
- Specify R4 late-post-abort semantics (drop/tombstone/new-epoch).
- Explicitly mark utterance_id as additive (R3).
- Mandate INV-3+INV-4 atomic delivery or staged safety proof (R1).

Once these are tightened, contract becomes a strong blocking gate.
