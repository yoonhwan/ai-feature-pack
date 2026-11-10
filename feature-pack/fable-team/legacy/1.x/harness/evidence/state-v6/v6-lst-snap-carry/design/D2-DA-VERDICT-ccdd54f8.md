# D2 DA VERDICT — exact SHA ccdd54f843374000df37b65c43c449d805f67548

- Author: ft-lstsnap-da-fable#25 (DA gate, successor of da-fable#24 — killed without baton)
- Date: 2026-07-21
- Scope: D2 WindowHandoff seal candidate (D1 baseline c71ef4cc SEALED, untouched)
- Method: everything re-executed by DA itself in the isolated detached worktree
  `da-d2-seal2` pinned at the exact SHA (clean before AND after every knockout,
  `git status --short` = 0 verified each time). Never trusted prose/green/relay.
  Honors the #24 CONCESSION mandate: fresh full battery + K14/K15 + A-B1/A-B2
  fix-RED differential.

## VERDICT: **REJECT — one blocker (B5), everything else PASS**

### B5 (blocker) — B4 encoder-revalidation fence is now TEST-VACUOUS

The A-B1 conservation fence **subsumed both former K8 discriminators**. The two
model_copy-poisoned encode REDs (`test_encode_rejects_model_copy_poisoned_row/`
`residual_emits_no_bytes`, poison = `refined_end + 1`) break owner tiling, so the
NEW `_revalidate_ready` conservation proof catches them even with B4 removed.

Evidence (all at ccdd54f8, isolated worktree):
1. **K8 knockout** (`revalidated = _ADAPTER.validate_python(handoff.model_dump())`
   → `revalidated = handoff`) → **276 passed, 0 failed** — no test in the entire
   v6 d1+d2 suite discriminates the fence. (At a0ecb874 the same knockout killed
   exactly 2 REDs — the subsumption is new to this SHA.)
2. **Non-equivalence probe** — leaf-INVALID but conservation-CLEAN,
   exact-type-CLEAN poison: `row0.model_copy(update={"refined_text":
   row0.refined_text + "?"})` (spans untouched ⇒ conservation proofs blind;
   types untouched ⇒ A-B2 walk blind; only `_span_integrity` end−start==len(text)
   can see it).
   - intact: `REJECTED WindowHandoffCodecError: refusing to encode an invalid WindowHandoff`
   - K8 knocked out: **EMITTED 877 bytes** ⇒ NOT an equivalent mutant.
3. Same insufficiency class as D1 92c1f883 and the #24 CONCESSION (fence present
   in code but unprovable by the suite). Per `docs/rules/da_verification.md` §3,
   mutation verification must prove the guard non-vacuous — it does not.

Required fix (small): add RED(s) to `test_v6_d2_encode_fence.py` — text-length
model_copy poison on row AND residual (leaf-invalid / conservation-clean /
exact-type-clean) → encode raises `WindowHandoffCodecError`, no bytes. Then K8
knockout must kill exactly those REDs. No production-code change expected.

## PASS evidence (carries forward to the fix SHA; re-verify only K8 + new REDs)

1. **Fresh-process 2-seed PASS**: PYTHONHASHSEED=0 → 276 passed; 777 → 276
   passed (full v6 d1+d2, 14 D2 + 16 D1 files; D1 non-regression included).
2. **A-B1/A-B2 fix-RED differential PASS** (the #24 CONCESSION mandate):
   - @a0ecb874 (worktree `da-d2-repro`): A-B1 conservation-broken poison
     **EMITTED 876 bytes**; A-B2 nested `_SubRow` **EMITTED 876 bytes**
     (architect finding reproduced byte-for-byte).
   - @ccdd54f8: A-B1 → `REJECTED … row_refined_partition_mismatch`;
     A-B2 → `REJECTED … row must be exact ProjectedRow, got _SubRow`. No bytes.
3. **Mutation battery K1–K15** (each knockout target asserted present, suite
   re-run, worktree restored clean):
   - K1 → 5 FAIL (ingress_conflict 4 + mutation_fences 1); K2 → 3 FAIL;
     K3 → 2 FAIL; K4 → 2 FAIL; K5 → 2 FAIL; K6 → 1 FAIL; K7 (B3) → exactly the
     2 bytearray/bytes-subclass REDs; K9 (C1) → noncanonical-whitespace RED;
     K10 (C2) → 5 FAIL (leaf_integrity); K11 → 6 FAIL (ingress_poison);
     K12 → 3 FAIL (lookalike subclass); **K14 (A-B1) → exactly
     `test_encode_rejects_leaf_valid_conservation_broken_poison_no_bytes`**;
     **K15 (A-B2) → exactly the 3 nested-subclass REDs** (list rows/projection
     REDs still covered by the sealed D1 `require_exact_tuple` path).
   - K13 → all green = the recorded ADJ-2 equivalent mutant (unchanged).
   - K8 → all green = **B5 above**.
4. **Static PASS**: ruff clean (note: run with explicit file args; a newline-joined
   single-arg invocation yields a spurious `E902 File name too long`, environment
   artifact). basedpyright (venv interpreter, all 22 c71ef4cc..ccdd54f8 files):
   **0 errors**, 34 warnings = exactly 2 accepted categories.
5. **ADJ-1 re-verification @ccdd54f8**: 6 reportUnnecessaryComparison, each
   line-read as a `case unreachable: assert_never(unreachable)` sentinel —
   `d2_assembly.py:58,70,98`, `d2_codec.py:82,131`, `d2_handoff.py:94`. The 6th
   (codec `_revalidate_ready`) is the same accepted mechanism class; adjudicated
   closed set extended accordingly. Any occurrence outside this set (or D1:106)
   = blocking. 28 reportUnusedCallResult all in tests (nonblocking per D1
   adjudication). No `_ =` silencing; no skip/xfail/TODO/type-ignore/noqa/cast
   anywhere in the 22 files (grep CLEAN).
6. **Diff hygiene PASS**: a0ecb874..ccdd54f8 touches only `d2_codec.py` +
   `test_v6_d2_encode_fence.py`. Full c71ef4cc..ccdd54f8 = 22 D2-only files;
   D1 sealed files (d1_*/canonical_json/semantic_types/contracts) byte-untouched
   (empty diff). LOC: modules ≤158, tests ≤163.
7. **C0 rollout fence PASS**: no d2_* import in graph.py/graph_runtime.py/nodes/
   (grep CLEAN); import-fence + output-strictness suites re-run green.

## HOLD unchanged
C2/provider/Redis/consumer activation, translate/type1/commit/publish/seal,
release-bridge retirement, main merge, push. Local service startup HOLD until
2026-07-22 demo (only isolated pytest/mutation used here — no server/Redis/browser).
