# ⚠️ DA CONCESSION 2026-07-21 (append to retraction) — DA reproduced BOTH architect
# A-B1/A-B2 attacks at a0ecb874 and CONFIRMS the coverage gap in its own K-battery:
# A-B1 leaf-valid-but-conservation-broken poison (slice refined_end 4->3) → encoder EMITTED
# 876 bytes (no conservation fence in encode path; K8/K10 only used leaf-INVALID poisons).
# A-B2 nested ProjectedRow subclass → model_dump->validate_python LAUNDERS to base type,
# encoder EMITTED (K7/K12 covered decode-bytes + d2_handoff request gates, NOT encoder
# nested types). Same insufficiency class as D1 92c1f883. APPROVE formally WITHDRAWN by DA
# itself, not merely superseded. Next-SHA battery MUST add: encoder-side leaf-valid
# conservation poison RED + encoder nested-subclass (row/residual/slice) laundering RED,
# and knockouts for both new fences.

# ⚠️ RETRACTED 2026-07-21 — architect#22 REJECT a0ecb874 (A-B1 encoder conservation fence missing + A-B2 encoder nested exact-type fence missing) landed AFTER this seal was issued. This seal is VOID for gating. Retained evidence still valid for the next SHA: 2-seed green, D1 non-regression, RED reconciliation, ownership check, mutation K1-K13 mechanism map, ADJ-1/ADJ-2 adjudications (re-verify file:line). Next SHA gets a fresh full battery + explicit A-B1/A-B2 fix-RED verification.

# D2 FINAL DA SEAL — exact SHA a0ecb874f7bf01168f55c2451356211078e5ce76

- Author: ft-lstsnap-da-fable#24 (DA gate, successor of da-fable#23)
- Date: 2026-07-21
- Scope: D2 WindowHandoff implementation seal (D1 baseline c71ef4cc SEALED, untouched)
- Method: everything re-run by DA itself in an isolated detached worktree at the exact SHA
  (`git worktree add --detach`), never trusting prose/green/relay.

## VERDICT: **APPROVE — D2 FINAL DA SEAL ISSUED** (with 2 recorded adjudications, below)

## Evidence (all independently re-executed at a0ecb874)

1. **Fresh-process 2-seed PASS**: PYTHONHASHSEED=0 → 110 passed; PYTHONHASHSEED=777 → 110
   passed (12 D2 test files). D1 non-regression: 160 passed (sealed suite intact).
   ruff changed-files clean. basedpyright (all 21 changed files, venv-resolved):
   **0 errors**, 32 warnings (taxonomy below).
2. **RED reconciliation PASS** vs D2-SCOPE-PROPOSAL §5 + checker REJECT history:
   P0 ingress/reconstruction (poison 14 / conflict 6 / schema-coercion 3), 5 outcome
   mappings + no-CONTRACT-FATAL (7), partition KATs (8: EXACT split, REFINED_ONLY split,
   REWRITE boundary fatal + confined, SOURCE_ONLY start/inter-boundary/end, same-coordinate
   order); P1 identity/ACCEPT edges (12), output strictness incl. 2-seed byte equality (11),
   rollout fence (5: auto-forbidden index + AST transitive + runtime subprocess delta +
   legacy-WindowHandoff distinctness), codec (16), leaf integrity (11), conservation (6),
   mutation fences (11). REJECT-fix REDs present: C1 canonical re-encode byte-equality,
   C2 leaf `_span_integrity`, B3 exact-bytes decode gate, B4 encoder revalidation.
   No skip/xfail/TODO/placeholder; no type suppressions.
3. **Ownership PASS**: ProjectedRow/ProjectedResidual carry leaf self-integrity ONLY
   (nonempty + start<end + len-match, mirroring sealed D1 `_require_span_matches_text_length`);
   cross-owner/global conservation lives in d2_conservation and runs at assembly + codec
   decode — D2's own §4 output proof, no D1 leaf re-ownership, D1 sealed files byte-untouched
   (`git diff c71ef4cc..a0ecb874 -- d1_*/canonical_json/semantic_types/contracts/...` = empty).
   Full diff = 21 D2-only files, no drive-by edits. LOC: modules ≤151, tests ≤163 — limits met.
4. **Mutation mechanism PASS** (13 knockouts on the candidate SHA, each restored clean,
   each firing for the intended reason):
   - K1 plan-pair byte fence removed → 5 FAIL (ingress_conflict + mutation_fences)
   - K2 REWRITE cut fence removed → 3 FAIL; K3 SOURCE_ONLY end rule removed → 2 FAIL
   - K4 per-owner refined proof → 2 FAIL; K5 axis partition proof → 2 FAIL;
     K6 atom reconstruction proof → 1 FAIL
   - K7 (B3) decode exact-bytes gate removed → exactly the 2 bytearray/subclass REDs FAIL
   - K8 (B4) encoder revalidation removed → exactly the 2 model_copy-poisoned encode REDs FAIL
   - K9 (C1) re-encode byte-equality removed → noncanonical-whitespace RED FAIL
   - K10 (C2) leaf span integrity no-op → 7 FAIL (leaf_integrity 5 + codec encode 2)
   - K11 strict dump-reconstruct removed → 6 FAIL; K12 triple exact-type gate removed → 3 FAIL

## Adjudications (binding on successors)

- **ADJ-1 — reportUnnecessaryComparison closed set extended (5 D2 occurrences)**: D1 seal
  allowed exactly one at `d1_split.py:106` and declared further occurrences blocking pending
  adjudication. The 5 new D2 occurrences are each verified at a `case unreachable:
  assert_never(unreachable)` match-exhaustiveness sentinel — the same accepted fail-loud
  mechanism class, not a silenced dead comparison. Adjudicated closed set for D2 @a0ecb874:
  `d2_assembly.py:58,70,98`, `d2_codec.py:87`, `d2_handoff.py:94` (re-check file:line each
  SHA). Any occurrence outside this set (or D1:106) = blocking. 27 reportUnusedCallResult
  all verified inside `pytest.raises` blocks (nonblocking per D1 adjudication). No `_ =`
  silencing, no suppressions anywhere.
- **ADJ-2 — K13 equivalent mutant recorded**: removing the `type(replay_plan) is not
  type(supplied)` variant fast-path leaves all 110 green because the CanonicalJSON byte
  fence subsumes it — `outcome` is a required Literal on every SplitPlan variant (verified
  via model_fields), so distinct variants can never dump to identical bytes and the
  variant-swap RED still raises D2IngressConflict via the byte path. Observable contract
  preserved ⇒ equivalent mutant, not a coverage gap. The fast-path stays for error clarity.

## Notes
- checker "basedpyright 0 errors" claim reproduced only with the venv interpreter passed
  (`--pythonpath`); without it, 4 spurious reportMissingImports(pytest) appear — environment
  artifact, not code defect.
- HOLD unchanged: C2/provider/Redis/consumer activation, translate/type1/commit/publish/
  seal, release-bridge retirement, main merge, push.
