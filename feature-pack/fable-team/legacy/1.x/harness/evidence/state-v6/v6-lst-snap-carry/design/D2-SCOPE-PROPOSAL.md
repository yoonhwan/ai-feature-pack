# D2 (WindowHandoff) RED-FIRST SCOPE PROPOSAL — DESIGN ONLY, no impl GO

> Source: ft-lstsnap-architect#22 -> V6_HELM#23, mbox #461, 2026-07-21.
> Precondition: D1 FULLY SEALED (SHA c71ef4cc365af7f6ea5e33023aadf26a4fa5f86f) — architect PASS + Checker CONSOLIDATED APPROVE(491 passed) + Tester PASS(160 D1 x2 seed) + DA(da-fable#23) final seal APPROVE.
> Gate: "Single writer after explicit HELM+user GO" — implementation NOT authorized yet.

## 1) Exact boundary / ownership
- D2 is a C2-inactive pure deterministic enrichment gate. MUST NOT split text, change D1 rows/residual, change decision_hash/handoff_id/segment_id, or call provider/Redis/ACK/graph/translate/type1/commit/publish/seal.
- Input: new exact D2Request = {d1_request: exact D1Request, split_plan: exact SplitPlan, projection_policy_version: literal d-project-v1}. D1 sealed files remain byte-untouched.
- execute_d2_handoff exact-type checks, primitive-dumps/strictly reconstructs the entire request, reruns sealed execute_d1_split(d1_request), then requires exact variant + CanonicalJSON bytes equality with supplied split_plan before projection work. Mismatch/forged/coerced input is structural fail-closed (TypeError/ValidationError or typed D2IngressConflict), not a projection fatal, produces no WindowHandoff.
- Effective input projection: ACCEPT uses D1-validated ProjectionAtom tuple; IDENTITY derives one full-span EXACT atom; DROP and FATAL carry no projection. D2 never reopens D1 cross-atom ingress ownership.

## 2) New contracts/types
- OwnedProjectionSlice (output-only): global half-open source_start/source_end/refined_start/refined_end + closed provenance; frozen, extra-forbid, strict SemanticInt, no text-key map.
- ProjectedRow: byte-exact copy of D1 row_index/refined span/refined_text/segment_id + nonempty ordered tuple[OwnedProjectionSlice,...].
- ProjectedResidual: byte-exact copy of D1 residual span/text + nonempty ordered tuple[OwnedProjectionSlice,...].
- WindowHandoff = discriminated union (never incomplete base model, never legacy contracts.py.WindowHandoff): RowsCompleteHandoff, RowsWithResidualHandoff, ResidualOnlyHandoff, EmptyProvenHandoff, UpstreamFatalHandoff, ProjectionFatalHandoff, ConservationFatalHandoff. No CONTRACT_FATAL revival, nullable rows/residual, is_release, source_projection_map, contradictory booleans.
- Ready variants: job_id, D1 decision_hash/handoff_id byte-exact, projection_policy_version, source_raw/refined_raw, exact projected rows/residual shape. Empty/upstream/projection/conservation fatal variants carry no partial rows/residual. Canonical identity = (job_id, D1 handoff_id, projection_policy_version); D1 segment IDs remain authoritative, no random/time/audit-derived D2 ID.
- ProjectionFatal closed code: REWRITE_BOUNDARY_UNPROVABLE (+ atom_index + boundary_refined_offset). ConservationFatal closed code enum: ATOM_RECONSTRUCTION_MISMATCH, ROW_REFINED_PARTITION_MISMATCH, GLOBAL_REFINED_PARTITION_MISMATCH, GLOBAL_SOURCE_PARTITION_MISMATCH. No free-form fallback reason.

## 3) Deterministic partition algorithm
- Owner spans = D1 rows in row_index order + optional residual; text/spans/IDs immutable input facts.
- EXACT may split at owner refined boundaries; source cut advances by same Python-codepoint delta.
- REFINED_ONLY may split; source coordinate stays zero-width.
- REWRITE may not be cut strictly inside its refined span — such cut returns ProjectionFatal, rows/residual zero.
- SOURCE_ONLY never split: at refined coordinate r attaches to next owner (owner of next refined codepoint; at exact owner boundary, owner starting at r). Only when r == len(refined_raw) attaches to previous/final owner. Multiple atoms preserve original tuple order.
- Nonzero-refined slices attach to unique owner fully containing that slice. No find()/difflib/nearest-match/legacy splitter-alignment import/fallback provenance/UUID/clock/dict-iteration identity.

## 4) Final proof before READY
- Rows/residual byte-exact D1 copies, ordered exactly; at most one residual.
- Within each owner, nonzero refined projection slices partition that owner's refined span exactly.
- Concatenating owner projections in owner order reconstructs each input atom from output slices and partitions refined_raw/source_raw globally exactly once, monotonically, no gap/overlap/duplication; zero-width sides obey provenance.
- Any internal proof failure -> typed ConservationFatal, no partial rows/commit/seal. EMPTY_PROVEN/UPSTREAM_FATAL pass through as closed zero-projection variants.

## 5) RED-first priority
- P0: exact ingress/reconstruction; D1Request<->SplitPlan mismatch/variant swap/model_copy/list/dict/JSON/subclass rejection; 5 D1 outcome mappings with no CONTRACT_FATAL; exact preservation of D1 rows/residual/IDs.
- P0: partition KATs for EXACT split, REFINED_ONLY split, REWRITE boundary fatal, SOURCE_ONLY at start/inter-row-boundary/end, multiple same-coordinate SOURCE_ONLY order.
- P0: full source/refined/owner conservation, fatal rows/commit/seal zero.
- P1: identity projection, ACCEPT insertion/deletion/rewrite, repeated identical occurrences, punctuation-only + every multilingual boundary class, no-boundary residual-only.
- P1: output frozen/extra-forbid/tuple-only/strict-int/NFC/surrogate + CanonicalJSON decode-reencode; fresh-process byte equality under >=2 PYTHONHASHSEED values.
- P1: rollout fence auto-index + AST transitive/runtime delta proving no C0/provider/Redis/C2/I-O/legacy eager import; static absence of translate/type1/commit/publish/seal symbols.
- Mutation/DA: knock out plan-pair fence, REWRITE cut fence, SOURCE_ONLY end rule, each conservation proof; REDs must fail for the intended mechanism.

## 6) Files/dependencies/gates
- New modules only, each <=200 LOC: d2_input_types.py, d2_projection.py, d2_output_types.py, d2_handoff.py (split further before 180); tests responsibility-split, each <180.
- Reuse sealed D1 types/entrypoint, CanonicalJSON, SemanticInt only. contracts.py legacy WindowHandoff remains untouched/unimported.
- **Single writer after explicit HELM+user GO.** Checker consolidated exact-SHA review; Tester isolated targeted suite + >=2 hash seeds + full changed-file ruff/basedpyright; DA exact-SHA conservation/fail-loud/mutation seal. No Redis/browser/service startup required (Tier-B).
- Rollback = D2 writer diff only. D1 SHA c71ef4cc, C1a/C1b, dirty/user files, legacy bridge/finalizer, production graph preserved.
- D2 product/C2/provider/Redis/ACK/consumer/translate/type1/commit/publish/seal/release bridge/main merge/push remain HOLD until separate HELM GO.
