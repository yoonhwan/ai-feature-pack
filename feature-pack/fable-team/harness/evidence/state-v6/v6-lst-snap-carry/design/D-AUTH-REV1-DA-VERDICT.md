# DA consolidated design verdict — D-AUTH REV1 + REV1A + REV1B

- Author: ft-lstsnap-da-fable#21 (DA gate, opus 4.8 lineage successor of da-fable#20)
- Date: 2026-07-21
- Authority reviewed: `.fable-team/state/v6-lst-snap-carry/design/D-AUTH-REV1.md` (19,418 bytes) + architect F-1/F-2 sealed ruling (mbox #452)
- Independent evidence base (read-only): rejected SHA `0bef3dbd` all 3 modules + RED `752f9e3a` (3 test files), sealed contracts `contracts.py:RefineKind`, `job_identity.py:FrozenWindowJobIdentity` (validator recompute chain), `source_snapshot.py:FrozenPendingSeam/SourceSnapshot`, `semantic_types.py:SemanticInt`
- Scope: DESIGN adjudication only. This is NOT an implementation seal — the fix SHA gets its own consolidated checker/Tester/DA round.

## VERDICT: DESIGN APPROVE WITH ONE REQUIRED AMENDMENT (DA-1)

Single-round consolidated per 8-rules rule-2. The REV1/REV1A/REV1B skeleton
(with F-1/F-2 sealed) is sound; one specification gap (DA-1) must be sealed
into the binding authority before the fix-SHA implementation seal. No second
design round required if DA-1 is amended as specified or with an equivalent
explicit ruling.

---

## Q1 — D1 ownership of full ACCEPT projection ingress validation: **YES, CORRECT**

D1 folds the caller projection into `decision_hash` (semantic identity) and
derives the protected-tail anchor (row-emission behavior) from atom ORDER and
spans. Hashing/acting on unvalidated cross-atom structure is authority
laundering: a forged-but-per-atom-valid tuple would mint a legitimate-looking
decision_hash and silently move the anchor. Validation must precede the first
hash byte — same principle as C1b F5/F6 (prevalidate before first write).

REV1B B1 rules 1–9 are complete for ingress: bounds-in-string, start-at-zero,
contiguity per side, end-at-full-length, no gap/overlap/reorder, and the four
provenance-slice consistency rules. Combined with per-atom "both sides
zero-length forbidden", the set is closed — zero-length-side atoms
(SOURCE_ONLY/REFINED_ONLY) interleave under contiguity without ambiguity.
Distinct-but-equivalent atom granularities hashing differently is accepted:
projection is caller semantic content, not derived data.

F-1 concurrence: this is a SPEC AMENDMENT, not an impl defect — 0bef3dbd's
docstring correctly cited pre-amendment REV1A ("parent decision validator owns
bounds/order/full-cover") and followed it. Not counted as an impl REJECT round.
D2 retains output-side partition/conservation proof; no double-ownership.

## Q2 — Removal of unreachable D1 CONTRACT_FATAL: **YES, CORRECT**

With strict ingress (B1/B2/B3) every malformed input is rejected as a loud
validation error BEFORE `execute_d1_split` runs, and the total d-split-v1
algorithm over validated input has no semantic-failure branch. Retaining an
unreachable variant violates transition-unmapped-0 (same class as C1b B4).
F-2 concurrence: removal must cover `ContractFatalPlan` AND
`SplitOutcome.CONTRACT_FATAL` AND union/`__all__`/tests/comments — a dangling
enum member is itself an unmapped transition. D1 closed set = exactly 5.
Contract violations surface as raised exceptions (fail-loud, side effects
zero); semantic projection/conservation failure is D2's typed fatal. No
silent-fallback path is introduced by the removal.

## Q3 — Reconstruction + true discriminator + strict tuple vs model_copy/coercion threat: **YES, SUFFICIENT — with 2 RED obligations**

The threat model (Pydantic v2): `model_copy(update=)` bypasses ALL validators
on frozen models; plain unions try members in order (no discriminator);
list→tuple silent coercion launders mutable input. The three-part fence closes
it:

1. `Field(discriminator="kind")` — deterministic variant selection, no
   trial-validation ambiguity.
2. Strict tuple (reject list, not coerce) — no mutable-origin laundering.
3. `execute_d1_split` accepts only exact `type(request) is D1Request`
   (lookalike/subclass reject) and reconstructs from primitive dumped values
   before reading any field — re-running every validator, including
   `FrozenWindowJobIdentity._reject_caller_supplied_derived_fields` (which
   recomputes source_hash/trigger_fingerprint/context_fingerprint/job_id),
   so a poisoned window forgery is also caught. This mirrors the sealed C1b
   ClaimLeaseReceipt capability pattern at the appropriate strength for a
   Tier-B pure gate.

Required RED (both already implied by REV1B "model_copy poison at every
ingress layer" — stated here explicitly so checker enforces them):
- (a) Poison-then-reconstruct must RAISE for every layer listed in B2
  (splitter policy / nested decision kind+text / atom offsets+provenance /
  window derived fields) — asserting the reconstruction path itself, not just
  direct-constructor rejection.
- (b) `execute_d1_split` must reject non-`D1Request` input (dict/JSON/
  lookalike/subclass) BEFORE any hash computation — zero preimage bytes
  hashed on the reject path.

## Q4 — d-split-v1 span ownership + protected-tail anchor: **COMPLETE AND DETERMINISTIC — with amendment DA-1 (below)**

Verified deterministic: pure function of validated input; no clock/uuid/dict-
iteration/hash-seed dependence (all preimages CanonicalJSON; scan order =
validated tuple order, which B1 makes monotonic ⇒ "earliest atom" is
well-defined). Domain separation across the three hashes is clean
(`domain-refine-decision-v1` / `domain-window-handoff-v1` /
`domain-window-segment-v1`, each + 0x00). segment_id preimage excluding
refined_text is collision-free within a handoff (spans determine text given
the decision_hash→handoff_id chain).

Boundary/anchor edges checked and closed:
- P=0 ⇒ anchor=first covering atom's refined_start=0 ⇒ zero rows, all
  residual (fully protected — correct).
- P=len(source) ⇒ no atom matches (unless a trailing REFINED_ONLY insert,
  whose refined_start then anchors) ⇒ anchor=len(refined) (nothing
  protected — correct).
- Whitespace-run extension crossing the anchor ⇒ owned_end > anchor ⇒ row
  deferred to residual (conservative, deterministic).
- SOURCE_ONLY atom past P anchors at its refined_start (zero-width marker
  position — valid).
- No-terminal-punctuation scripts ⇒ rows 0 + exact residual (policy-versioned
  d-split-v1; graceful, not a defect).
- `owned_end <= anchor` acceptance matches "no completed row may intersect or
  follow the anchor" (row ending exactly at anchor does not intersect it).

### DA-1 (REQUIRED AMENDMENT — MED, spec gap, silent-path class)

B3 scopes seam bounds to "ACCEPT and identity inputs" only. For DROP_PROVEN
(and FATAL_CONTRACT) with `window.pending_seam` present, the seam is silently
unused: a seam whose `protected_tail_start_raw_offset > 0` against DROP's
empty source is a cross-contract inconsistency that currently passes with
zero telemetry — a silent-ignore path of exactly the class this workspace
forbids ("upstream wouldn't produce it" is the reachability assumption REV1B
B4 itself rejects). Required ruling, either:
- (i) extend B3: DROP_PROVEN with pending_seam requires both seam offsets
  == 0 (== len(source_raw)="" ) else loud reject before hashing; and state
  explicitly that FATAL_CONTRACT passthrough ignores the seam BY RULE
  (passthrough owns no source semantics), with a RED asserting both; or
- (ii) an explicit architect ruling that seam consistency for DROP/FATAL is
  owned by an upstream sealed validator (name it), with a RED pinning that
  assumption.
Either resolution seals the gap; (i) is self-contained and preferred.

## Q5 — Accidental C2/provider/Redis/production activation: **NO**

Forbidden list is closed and consistent with C1b posture. D1's import closure
at the reviewed SHA is pure sealed modules only (canonical_json / contracts /
semantic_types / job_identity / source_snapshot) — no Redis/Lua/provider/
async/legacy-splitter symbol. Rollout-fence RED (module-index forbidden set +
AST transitive C0 closure + runtime sys.modules) covers regression. Nothing
in REV1B's added validation introduces I/O. Tier-B classification stands: no
durability/concurrency boundary in D1 ⇒ no real-Redis requirement (8-rules
rule-5 satisfied).

---

## Confirmed independently at code level (context for the fix SHA)

B1–B5 all real at `0bef3dbd`: B1 per-atom-only validation while
`_protected_refined_anchor` consumes cross-atom order; B2 plain union +
list→tuple coercion + model_copy bypass; B3 P>len(source) ⇒ anchor=
len(refined) ⇒ silent full split (protection silently disabled); B4
docstring-self-declared unreachable variant; B5 201/298/314 LOC.

## Gate conditions for the upcoming implementation seal (unchanged + DA-1)

1. One fix SHA; consolidated checker + Tester fresh-process KAT (≥2
   PYTHONHASHSEED) + DA seal in one round each.
2. DA-1 amendment sealed into the binding authority file BEFORE the DA
   implementation seal.
3. RED additions of REV1B "Required fix RED" + Q3 obligations (a)/(b) +
   DA-1 RED.
4. HOLD unchanged: C2/provider/Redis/D2 product/translate/type1/commit/
   publish/seal/release-bridge retirement/main merge/push.
5. DA methodology carryover applies: verification by SHA computation +
   pre-fix RED execution — green prose/docstring claims are not evidence.
