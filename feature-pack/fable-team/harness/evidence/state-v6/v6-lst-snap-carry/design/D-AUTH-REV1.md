# D-AUTH REV1: Gate D RED-first design authority

- Author: ft-lstsnap-architect#22
- Date: 2026-07-21
- Gate: D1 splitter/handoff, then D2 ordered projection/source conservation
- Runtime posture: C2 inactive; production consumer/provider/graph wiring HOLD
- Current implementation verdict: SHA 0bef3dbd4b963ad19b455fecff2211878925a105 is ARCHITECT REJECT under REV1B
- Review loop: architect <-> ft-lstsnap-da-fable#21 direct design adjudication

## Precedence

The binding design is REV1 plus REV1A, with REV1B overriding conflicts.

REV1B specifically overrides:
1. Projection cross-atom validation may not be deferred to D2; D1 ingress owns it.
2. D1 SplitPlan has five outcomes. CONTRACT_FATAL and ContractFatalPlan are removed from D1.
3. D1 ingress must be a true discriminator, strict tuple boundary, and model-copy-safe reconstruction boundary.
4. Pending seam offsets must be source-bounded before hashing or splitting.
5. Workspace 200 LOC hard limits apply to implementation and tests.

---

# REV1: Gate D RED-first scope

## GATE / SEQUENCE

- D is a C2-inactive, pure deterministic handoff core. Explicit HELM sequencing exception permits pure D work only.
- C2 consumer/provider, graph edge, release bridge, Redis, translate/type1/commit/publish/seal stay HOLD.
- Internal seal order is D1 then D2.
- D2 writer MUST NOT start before D1 exact-SHA checker and DA seal.
- One writer per subgate.
- D1 = validated input variants -> deterministic SplitPlan.
- D2 = SplitPlan + ordered offset projection -> final WindowHandoff.
- No incomplete public WindowHandoff escapes D1.

## SCOPE GRAPH

FrozenWindow semantic authority plus typed stored RefineDecision projection

  -> D ingress reconstruction and strict validation
  -> D1 deterministic boundary splitter, protected-tail fence, deterministic IDs
  -> D2 ordered projection partition and conservation proof
  -> READY WindowHandoff, EMPTY_PROVEN, or closed FATAL

D contains no async, provider/service/Redis/legacy graph imports, random UUID, clock, or request/source-entry/queue/timestamp identity.

## INPUT / TYPE AUTHORITY

- Do not consume the legacy contracts.py WindowHandoff, source_projection_map dict, or is_release boolean as canonical D authority.
- New D types are frozen, extra-forbid, tuple-only, and use strict SemanticInt plus canonical NFC/surrogate-free text.
- Refine input is a discriminated union:
  1. ACCEPT_CANDIDATE: source_raw, refined_raw, mandatory ordered ProjectionAtom tuple.
  2. IDENTITY_UNCHANGED, REJECT_TO_IDENTITY, UNAVAILABLE_TO_IDENTITY: refined_raw must byte-exact equal source_raw; D derives identity projection; caller projection is forbidden.
  3. DROP_PROVEN: source_raw and refined_raw are empty; effective projection is empty.
  4. FATAL_CONTRACT: upstream-fatal passthrough; splitter/projection/rows are zero.
- ProjectionAtom uses half-open Python-codepoint offsets for source/refined and the closed provenance set EXACT, REWRITE, SOURCE_ONLY, REFINED_ONLY.
- Both sides zero-length is forbidden.
- Atoms are monotonic and collectively cover both complete strings with no gap, overlap, or reorder.
- EXACT requires equal slices.
- REWRITE requires both nonempty and different slices.
- SOURCE_ONLY and REFINED_ONLY require exactly one nonempty side.
- pending_seam remains one optional FrozenPendingSeam. No list of seams.

## D1 BOUNDARY / IDENTITY

- Policy label: d-split-v1.
- Boundary candidate is the end of a maximal terminal punctuation run from the sealed table:
  . ? ! 。 ！ ？ ． ؟ ۔ । ॥ …
- A terminal run is a boundary only when followed by whitespace or end of string.
- Input is never stripped or rejoined.
- Half-open owned spans partition refined_raw exactly.
- No boundary means rows zero and residual exact.
- pending protected_tail_start_raw_offset projects conservatively to the earliest affected refined atom start.
- No completed row may intersect or follow the protected anchor.
- All deferred suffix becomes exactly one residual.
- Purpose and LST do not create a second splitter algorithm.
- Replay, process hash seed, and physical request/source-entry changes cannot change plan or IDs.
- UUID, time, and dict iteration identity are forbidden.

Original REV1 listed the following SplitPlan variants:
- ROWS_COMPLETE
- ROWS_WITH_RESIDUAL
- RESIDUAL_ONLY
- EMPTY_PROVEN
- UPSTREAM_FATAL
- CONTRACT_FATAL

REV1B removes CONTRACT_FATAL from D1. The current D1 closed set is five outcomes.

## D2 PROJECTION / CONSERVATION

- Final WindowHandoff contains tuple rows in refined order, at most one exact residual, deterministic IDs, and per-row/residual ordered projection slices.
- String-key projection maps are forbidden.
- Exact atoms may be split by offset.
- A row boundary through REWRITE is unprovable unless input atoms already expose that boundary.
- Such failure returns a D2 typed projection/conservation fatal; it never uses nearest-match, find(), or silent no-provenance.
- REFINED_ONLY may split.
- SOURCE_ONLY attaches by deterministic order to the next slice, or previous slice only at end of string.
- Repeated identical text is distinguished only by offsets.
- Punctuation-only and multilingual punctuation are first-class.
- Output refined spans partition the full refined string exactly.
- Output source spans across rows and residual partition the full source string exactly once, monotonically, with no gap, overlap, or duplication.
- Any failed proof is fail-loud and causes rows/commit/seal zero.
- Legacy source_row_alignment/difflib nearest-boundary and legacy sentence_splitter with LLM/uuid/fallback are evidence only. Canonical D must not import or reuse them.

## FULL RED MATRIX

### D1

- Every RefineKind mapped.
- Strict discriminator, extra-forbid, frozen, tuple-only, strict integer, NFC, and surrogate invariants.
- Identity mismatch fatal.
- DROP nonempty fatal.
- FATAL passthrough with side effects zero.
- Empty, no-boundary, one boundary, multiple boundaries, trailing residual.
- Every sealed punctuation codepoint.
- Leading/inter-row/trailing whitespace exact ownership.
- pending seam bounds/max-one and boundary before/at/after protected anchor.
- Deterministic decision/handoff/segment known-answer tests.
- Replay under different PYTHONHASHSEED values.
- Physical audit IDs excluded.
- Forged/coerced/model_copy input rejected at execution ingress.

### D2

- Identity projection.
- ACCEPT full-cover projection.
- Repeated identical occurrences.
- Punctuation-only and multilingual punctuation.
- Insertion, deletion, rewrite.
- Atom gap, overlap, reorder, out-of-bounds, zero-zero, enum/slice mismatch.
- Boundary inside REWRITE fatal.
- SOURCE_ONLY end-of-string attachment.
- Full source and refined conservation.
- Rows/residual order.
- Canonical encode/decode-reencode.
- Projection failure causes commit/seal/provider zero.

### Rollout fence

- New D modules auto-enter the module-index forbidden set.
- AST transitive C0 closure plus runtime sys.modules prove no D/provider/Redis/C2 eager import.
- No graph registration or startup probe.
- Static RED proves provider await/call, translate/type1/commit/publish/seal symbols are absent from D dependency closure.

## THREAT / RISK

D1 and D2 are Tier-B deterministic gates.

Required adversaries:
- repeated text;
- Unicode normalization and surrogates;
- punctuation runs;
- whitespace ownership;
- off-by-one spans;
- ambiguous rewrite cuts;
- forged or coerced models.

No Tier-A Redis test is required because D owns no durability or concurrency boundary. Any Redis, ACK, or provider dependency discovered in D is a scope violation.

## EVIDENCE / GATES

- Writer starts with complete D1 RED files.
- D2 RED may be prepared read-only, but D2 product code cannot start before D1 seal.
- Checker gives one consolidated exact-SHA verdict per subgate.
- Tester runs an isolated venv targeted suite plus a fresh-process deterministic driver under at least two PYTHONHASHSEED values and compares canonical bytes and IDs byte-for-byte.
- Redis, browser, and service startup are not required for this Tier-B gate.
- DA seals D1 boundary/ownership, then D2 conservation/fail-loud behavior.
- ADVANCE requires checker findings zero, tester artifact, and DA exact-SHA seal.
- Rollback touches only the current D subgate writer diff.
- Sealed C1a/C1b, legacy splitter/bridge/finalizer, production graph, and unrelated dirty state are preserved.

## FORBIDDEN

- C2 activation or provider call.
- C1c source ACK or C1b ready XACK.
- Redis/Lua.
- Legacy splitter import.
- Random/time/audit-derived IDs.
- Mutable/list/dict projection.
- Silent fallback.
- Translate/type1/commit/publish/seal.
- Release bridge retirement.
- Main merge/push.

---

# REV1A 1/2: Exact type and name seal

## Existing authority type

- D1Request.window is the sealed C1a FrozenWindowJobIdentity.
- Do not create FrozenWindowRef or FrozenWindowSnapshot aliases.
- D does not read window.audit, request ID, source-entry ID, queue ID, or timestamps for correctness.
- Downstream derivation uses the already validated window.job_id.

## CanonicalText

CanonicalText accepts exact built-in str only.

It rejects:
- non-string coercion;
- UTF-8 surrogates or invalid Unicode;
- any value that is not already equal to its Unicode NFC form.

It never silently normalizes.

## ProjectionProvenance

Closed values:
- EXACT
- REWRITE
- SOURCE_ONLY
- REFINED_ONLY

## ProjectionAtom

Exact fields:
- source_start: SemanticInt
- source_end: SemanticInt
- refined_start: SemanticInt
- refined_end: SemanticInt
- provenance: ProjectionProvenance

Offsets are half-open Python codepoint indexes.

Per-atom rules:
- source_start <= source_end;
- refined_start <= refined_end;
- both sides zero-length forbidden.

Parent ACCEPT decision validation owns string bounds, tuple order, full coverage, and provenance-to-slice consistency.

## DRefineInput discriminated variants

### AcceptCandidateInput

- kind = ACCEPT_CANDIDATE
- source_raw: nonempty CanonicalText
- refined_raw: nonempty CanonicalText
- projection: nonempty exact tuple of ProjectionAtom

### IdentityRefineInput

- kind in IDENTITY_UNCHANGED, REJECT_TO_IDENTITY, UNAVAILABLE_TO_IDENTITY
- source_raw: nonempty CanonicalText
- refined_raw: nonempty CanonicalText
- refined_raw must byte-exact equal source_raw
- projection field must not exist
- D derives one EXACT atom from zero to string length

### DropProvenInput

- kind = DROP_PROVEN
- source_raw = empty literal
- refined_raw = empty literal
- projection field must not exist
- effective projection is empty tuple

### FatalContractInput

- kind = FATAL_CONTRACT
- failure_code: nonempty CanonicalText
- source_raw, refined_raw, and projection fields must not exist

DRefineInput is a true kind-discriminated union. All variants are frozen and extra-forbid.

## D1Request

Exact fields:
- window: FrozenWindowJobIdentity
- decision: DRefineInput
- splitter_policy_version: literal d-split-v1

pending_seam exists only at request.window.pending_seam. There is no second seam field or seam list.

## D1 output types

The D1 union name is SplitPlan. Final WindowHandoff is reserved for D2.

SplitRowPlan fields:
- row_index: SemanticInt
- refined_start: SemanticInt
- refined_end: SemanticInt
- refined_text: CanonicalText
- segment_id: string

SplitResidualPlan fields:
- refined_start: SemanticInt
- refined_end: SemanticInt
- refined_text: CanonicalText

Current REV1B D1 variants:
- RowsCompletePlan: outcome, decision_hash, handoff_id, nonempty rows tuple
- RowsWithResidualPlan: outcome, decision_hash, handoff_id, nonempty rows tuple, nonempty residual
- ResidualOnlyPlan: outcome, decision_hash, handoff_id, nonempty residual
- EmptyProvenPlan: outcome, decision_hash, handoff_id
- UpstreamFatalPlan: outcome, decision_hash, handoff_id, failure_code

No nullable rows/residual fields and no contradictory booleans.

---

# REV1A 2/2: Exact hash and boundary seal

## Effective decision projection

- ACCEPT: validated caller tuple.
- Identity/reject/unavailable: one derived EXACT atom:
  source_start=0, source_end=L, refined_start=0, refined_end=L, provenance=exact.
- DROP and FATAL: empty tuple.

## decision_hash

Formula:

  SHA256(
    bytes domain-refine-decision-v1 + zero byte
    + CanonicalJSONBytes(variant preimage)
  )

Exact variant preimages:

ACCEPT:

  {
    "kind": "accept_candidate",
    "source_raw": S,
    "refined_raw": R,
    "projection": [
      {
        "source_start": a,
        "source_end": b,
        "refined_start": c,
        "refined_end": d,
        "provenance": p
      }
    ]
  }

IDENTITY / REJECT / UNAVAILABLE:

  {
    "kind": kind.value,
    "source_raw": S,
    "refined_raw": S,
    "projection": [derived EXACT atom object]
  }

DROP:

  {
    "kind": "drop_proven",
    "source_raw": "",
    "refined_raw": "",
    "projection": []
  }

FATAL:

  {
    "kind": "fatal_contract",
    "failure_code": failure_code
  }

Projection array order is tuple order. CanonicalJSONBytes is the existing C1a implementation and rule set. AuditTrace and derived hashes are excluded.

## handoff_id

Formula:

  SHA256(
    bytes domain-window-handoff-v1 + zero byte
    + CanonicalJSONBytes({
        "handoff_schema_version": "d-handoff-v1",
        "job_id": request.window.job_id,
        "decision_hash": decision_hash,
        "splitter_policy_version": "d-split-v1"
      })
  )

## segment_id

Formula for each completed row:

  SHA256(
    bytes domain-window-segment-v1 + zero byte
    + CanonicalJSONBytes({
        "segment_schema_version": "d-segment-v1",
        "handoff_id": handoff_id,
        "row_index": row_index,
        "refined_start": refined_start,
        "refined_end": refined_end
      })
  )

No psid, window_rev, audit field, timestamp, random value, or physical ID is duplicated outside job_id. Hash fields do not include themselves.

## d-split-v1 exact span ownership

- Terminal set is the literal codepoint set:
  . ? ! 。 ！ ？ ． ؟ ۔ । ॥ …
- Candidate boundary is the end of a maximal terminal run when the next codepoint is whitespace or end of string.
- Cursor starts at zero.
- For an accepted candidate, owned row end extends through the immediately following maximal whitespace run.
- Row span is [cursor, owned_end).
- Row text is the exact refined_raw slice.
- No strip or rejoin.
- Cursor becomes owned_end.
- The exact suffix [cursor, len(refined_raw)) is the only residual.
- No candidate yields RESIDUAL_ONLY with exact input.
- Empty input is legal only through DROP.

## protected-tail mapping

For protected source offset P, choose the earliest effective atom refined_start whose source interval touches or follows P:

- first atom where source_end > P; or
- first atom where source_start >= P and the refined side is nonempty.

If no atom matches, the anchor is len(refined_raw).

A candidate row is accepted only when owned_end <= protected_refined_anchor. Anything at or after the anchor is deferred into the single residual.

Purpose and LST do not change this policy.

---

# REV1B: Architect review and corrections after SHA 0bef3dbd

Exact SHA reviewed:

  0bef3dbd4b963ad19b455fecff2211878925a105

Verdict:

  REJECT BEFORE CHECKER

## B1. Projection ingress is D1-owned

The implementation deferred cross-atom order, full coverage, bounds, and provenance consistency to D2.

That is invalid because D1:
- hashes projection into decision_hash;
- uses projection to calculate protected-tail anchor;
- produces rows and IDs from that anchor.

AcceptCandidateInput must reject before hashing:

1. Every source/refined end is within the corresponding string.
2. First atom starts at source/refined zero.
3. Each next atom starts exactly at the preceding atom ends.
4. Final atom ends at the complete source/refined lengths.
5. No gap, overlap, or reorder.
6. EXACT has two nonempty equal slices.
7. REWRITE has two nonempty different slices.
8. SOURCE_ONLY has nonempty source and zero refined span.
9. REFINED_ONLY has zero source span and nonempty refined span.

D2 still owns final output projection slicing and conservation proof. It does not own basic D1 ingress validity.

## B2. True discriminator, strict tuple, poisoned model fence

- DRefineInput must be Annotated with Field(discriminator="kind"), not a plain trial union.
- Tuple-only means list input is rejected, not converted to tuple.
- execute_d1_split accepts only an exact D1Request and reconstructs/revalidates it from primitive dumped values before reading any field.
- Lookalikes and subclasses are rejected.
- RED must poison via model_copy:
  - splitter policy;
  - nested decision kind/text;
  - ProjectionAtom offsets/provenance;
  - FrozenWindow derived/identity fields.
- Invalid/forged input reaches provider/Redis/graph side effects zero.

## B3. Pending seam source bounds

For ACCEPT and identity inputs:
- weak_terminal_raw_offset <= len(source_raw)
- protected_tail_start_raw_offset <= len(source_raw)

The implementation currently lets P > len(source) map to len(refined), which silently disables protection. It must reject before hashing and splitting.

## B4. Remove unreachable D1 CONTRACT_FATAL

ContractFatalPlan and CONTRACT_FATAL are removed from D1 SplitOutcome/SplitPlan.

Reason:
- strict valid ingress plus the total d-split-v1 algorithm leaves no valid D1 semantic-failure transition;
- deliberately retaining an unreachable variant violates transition-unmapped-zero;
- D2 will own a typed ProjectionFatal or ConservationFatal final handoff when projection proof fails.

D1 has exactly five outcomes:
- ROWS_COMPLETE
- ROWS_WITH_RESIDUAL
- RESIDUAL_ONLY
- EMPTY_PROVEN
- UPSTREAM_FATAL

## B5. Workspace file-size hard limit

The reviewed SHA contained:
- d1_split.py: 201 LOC
- test_v6_d1_types.py: 298 LOC
- test_v6_d1_split.py: 314 LOC

Workspace hard rule:
- 200 LOC maximum including whitespace
- split at 180 LOC before continuing

Split by responsibility without behavior change or unrelated cleanup.

## Required fix RED

Add independent RED for:
- all B1 projection failures;
- plain-union ambiguity;
- list-to-tuple coercion;
- model_copy poison at every ingress layer;
- pending offsets beyond source length;
- absence of ContractFatal symbols.

Keep existing:
- hash known-answer tests;
- boundary matrix;
- deterministic fresh-process evidence;
- rollout fence;
- ruff.

D2 product code remains HOLD.

Do not submit SHA 0bef3dbd to checker, Tester, or DA as an implementation candidate. Produce one fix SHA, then request consolidated checker, Tester fresh-process KAT, and DA implementation seal.

---

# DA review questions

Please return one consolidated design verdict against the current binding authority:

1. Is D1 ownership of full ACCEPT projection ingress validation correct, given D1 hashes and uses projection for protected-tail anchoring?
2. Is removal of unreachable D1 CONTRACT_FATAL correct, with projection/conservation fatal deferred to D2 final handoff?
3. Are exact D1Request reconstruction, true discriminated union, and strict tuple rejection sufficient for the known Pydantic model_copy/coercion threat?
4. Are d-split-v1 span ownership and protected-tail anchor rules complete and deterministic?
5. Does any rule accidentally activate C2/provider/Redis/production behavior?

Production consumer/provider, C2, Redis/ACK, D2 implementation, translate/type1/commit/publish/seal, release bridge retirement, main merge, and push remain HOLD.

---

# DA preliminary rulings: F-1 and F-2

Date: 2026-07-21
Ruling owner: ft-lstsnap-architect#22

## F-1. Projection ownership wording

RULING: ACCEPTED AS AUTHORITY CLARIFICATION / SPEC AMENDMENT, not counted as an implementation REJECT cycle.

The original materials contained an ownership ambiguity:
- REV1 and REV1A required a parent decision validator to enforce bounds/order/full-cover/provenance consistency.
- The D2 RED matrix also listed projection gap/overlap/reorder and conservation.
- The implementation interpreted all cross-atom validation as D2 HOLD.

Binding ownership is now explicit:

D1 AcceptCandidateInput ingress owns:
- atom bounds relative to source_raw/refined_raw;
- exact tuple order;
- complete source/refined coverage;
- gap/overlap/reorder rejection;
- provenance-to-slice consistency;
- validation before decision_hash and protected-tail anchor use.

D2 owns:
- partitioning already-valid input atoms across SplitPlan row/residual spans;
- boundary-inside-REWRITE proof;
- final per-row/residual source projection;
- final source/refined conservation proof;
- typed projection/conservation fatal outcome.

Therefore B1 is a required implementation delta under amended authority, but it is not charged as an implementation failure against the earlier ambiguous wording.

## F-2. CONTRACT_FATAL removal extent

RULING: CONFIRMED.

D1 must delete all of:
- ContractFatalPlan class;
- SplitOutcome.CONTRACT_FATAL enum member;
- ContractFatalPlan membership in SplitPlan;
- exports, tests, comments, and branches referring to D1 CONTRACT_FATAL.

D1 SplitOutcome contains exactly five enum members:
- ROWS_COMPLETE
- ROWS_WITH_RESIDUAL
- RESIDUAL_ONLY
- EMPTY_PROVEN
- UPSTREAM_FATAL

D2 will define separately named projection/conservation fatal output variants. It must not revive a D1 CONTRACT_FATAL enum member.

---

# DA first-pass finding resolution: upstream FATAL_CONTRACT vs removed D1 CONTRACT_FATAL

Date: 2026-07-21
Ruling owner: ft-lstsnap-architect#22

These are distinct concepts and must not share a route name.

## Legal upstream input

FatalContractInput represents the already-closed C2 RefineKind.FATAL_CONTRACT decision.

Its deterministic D1 transition is:

  FatalContractInput
  -> decision_hash using {"kind":"fatal_contract","failure_code":failure_code}
  -> handoff_id using the normal D1 formula
  -> UpstreamFatalPlan(outcome=UPSTREAM_FATAL, decision_hash, handoff_id, failure_code)

Side effects:
- splitter execution: zero
- projection execution: zero
- rows/residual: zero
- provider/Redis/translate/type1/commit/publish/seal: zero

FatalContractInput remains a legal DRefineInput variant.

## Removed D1 internal outcome

The removed CONTRACT_FATAL / ContractFatalPlan represented a hypothetical failure created inside D1 after a valid request.

It is removed because strict D1 ingress plus total d-split-v1 has no such valid transition. Its removal does not alter the upstream FATAL_CONTRACT route.

## Closed D1 transition table

- ACCEPT_CANDIDATE -> ROWS_COMPLETE, ROWS_WITH_RESIDUAL, or RESIDUAL_ONLY
- IDENTITY_UNCHANGED -> ROWS_COMPLETE, ROWS_WITH_RESIDUAL, or RESIDUAL_ONLY
- REJECT_TO_IDENTITY -> ROWS_COMPLETE, ROWS_WITH_RESIDUAL, or RESIDUAL_ONLY
- UNAVAILABLE_TO_IDENTITY -> ROWS_COMPLETE, ROWS_WITH_RESIDUAL, or RESIDUAL_ONLY
- DROP_PROVEN -> EMPTY_PROVEN
- FATAL_CONTRACT -> UPSTREAM_FATAL

Unknown discriminator, malformed variant, invalid projection, forged/coerced model, or invalid pending-seam bounds fail at strict D1 ingress before SplitPlan creation.

This table has no silent identity/drop fallback and no unmapped legal RefineKind.

---

# DA-1 architect amendment: DROP/FATAL pending-seam routing

Date: 2026-07-21
Ruling owner: ft-lstsnap-architect#22
Authoritative DA session for final verdict: ft-lstsnap-da-fable#20

## DROP_PROVEN

Binding rule is stricter than the preliminary suggested zero-offset allowance:

  DropProvenInput requires request.window.pending_seam is None.

Reason:
- DROP_PROVEN is the strict proof that both source_raw and refined_raw are empty.
- Even a zero-offset FrozenPendingSeam carries semantic seam existence, role, and evidence that D1 would otherwise ignore.
- Rejecting every DROP+seam combination removes the silent-ignore path completely.

The rejection occurs during exact D1Request reconstruction/validation before:
- decision_hash bytes;
- handoff_id bytes;
- splitter execution;
- SplitPlan creation.

Required RED:
- direct DROP plus pending seam at offsets zero raises;
- direct DROP plus pending seam at nonzero offsets raises;
- model_copy-poisoned DROP/window seam raises during execute_d1_split reconstruction;
- hash helper is not reached on each reject path.

## FATAL_CONTRACT

FatalContractInput may carry a FrozenWindowJobIdentity whose pending_seam is present.

Binding rule:

  FATAL_CONTRACT ignores pending_seam for splitting BY RULE,
  but does not erase it from semantic identity.

Specifically:
- no source/refined/projection fields exist on FatalContractInput;
- D1 performs no seam-bound computation;
- outcome is UPSTREAM_FATAL;
- splitter/projection/rows/provider/Redis/translate/type1/commit/publish/seal are zero;
- window.job_id was already computed from the C1a semantic payload, whose source_hash includes pending_seam;
- therefore a different pending seam can change job_id and handoff_id even though the fatal split route remains UPSTREAM_FATAL.

Required RED:
- FATAL with no seam and FATAL with a valid sealed seam both route UPSTREAM_FATAL;
- neither calls boundary/projection logic;
- their handoff IDs differ when their validated window.job_id differs;
- malformed/poisoned FrozenWindow identity still fails reconstruction before hashing.

## ACCEPT / identity kinds

The existing B3 rule remains:
- weak_terminal_raw_offset <= len(source_raw)
- protected_tail_start_raw_offset <= len(source_raw)

Violation rejects before hashing/splitting.

## DA authority correction

The design observations from ft-lstsnap-da-fable#21 are not a final gate verdict because HELM designated ft-lstsnap-da-fable#20 as the sole authoritative DA session. This amendment is adopted as architect design authority. Final consolidated design approval must come from ft-lstsnap-da-fable#20.

---

# Authoritative DA#20 design verdict pins

Date: 2026-07-21
DA verdict source: ft-lstsnap-da-fable#20 mbox #461
Verdict: DESIGN APPROVED, implementation seal separate

The following pins are binding implementation requirements.

## PIN-1. Strict reconstruction

execute_d1_split must:

1. Reject before hashing unless type(request) is exactly D1Request.
2. Dump the exact request to primitive Python values.
3. Reconstruct D1Request with strict validation and coercion disabled.
4. Read no decision/window/policy field before reconstruction succeeds.
5. Compute zero hash preimage bytes on rejection.

RED must prove model_copy-forged values fail through this execute ingress for:
- splitter policy;
- nested decision kind and text;
- ProjectionAtom offsets and provenance;
- FrozenWindow identity and derived fields;
- list-origin projection;
- lookalike, dict, JSON, and subclass requests.

## PIN-2. d-split-v1 boundary edges

The RED matrix must independently prove:
- terminal run at end of string;
- consecutive terminal punctuation such as ?!;
- punctuation not followed by whitespace, including decimal 3.14, is not an early boundary;
- boundary ending exactly at protected anchor is accepted;
- boundary whose whitespace-owned span crosses the protected anchor is deferred;
- each case leaves refined spans total and disjoint, with no hole or overlap.

## PIN-3. C1a-style import and rollout fence

The D fence must reuse the sealed C1a mechanism, not comments alone:

- AST-transitive static closure from C0 runtime cannot reach D modules.
- Runtime sys.modules evidence shows feature-off C0 startup imports/instantiates/probes no D/C2/provider/Redis module.
- D dependency closure imports no legacy sentence_splitter, source_row_alignment/difflib, LLM service, uuid/random/time, Redis/Lua, translate/type1/commit/publish/seal path.
- Importing the C refine decision enum/type surface consumed by D is proven side-effect-free: provider calls zero, Redis probes zero, startup registration zero.

These pins are required for checker, Tester, and DA implementation seal at the fixed SHA.

---

# Final D design authority seal

Date: 2026-07-21
Authoritative DA: ft-lstsnap-da-fable#20
DA evidence: consolidated verdict mbox #461 plus DA-1 concurrence mbox #453
Status: DESIGN AUTHORITY SEALED

Binding design consists of:
- REV1 scope, sequence, RED matrix, purity, and evidence gates;
- REV1A exact types, hash preimages, and d-split-v1 rules;
- REV1B ownership corrections B1-B5;
- F-1/F-2 rulings;
- upstream FATAL_CONTRACT versus removed internal CONTRACT_FATAL taxonomy;
- DA-1 DROP/FATAL pending-seam amendment;
- authoritative DA pins 1-3.

Implementation status is separate:
- SHA 0bef3dbd4b963ad19b455fecff2211878925a105 remains architect REJECT.
- D1 advances only on one fixed exact SHA with consolidated checker verdict, Tester isolated/fresh-process evidence including at least two PYTHONHASHSEED values, and authoritative DA#20 implementation seal.
- D2 product implementation cannot start before D1 implementation seal.
- D activation, C2, provider, Redis, production graph, main merge, and push remain HOLD.
