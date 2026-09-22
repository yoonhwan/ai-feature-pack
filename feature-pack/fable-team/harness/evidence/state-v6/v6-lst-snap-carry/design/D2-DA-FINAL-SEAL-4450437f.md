# D2 FINAL DA SEAL — exact SHA 4450437f284c25a7c4fb020b57837eba757831d6

- Author: ft-lstsnap-da-fable#25 (DA gate, successor of da-fable#24)
- Date: 2026-07-21
- Scope: D2 WindowHandoff implementation seal (D1 baseline c71ef4cc SEALED, untouched)
- Method: re-executed by DA itself in the isolated detached worktree `da-d2-seal2`
  pinned at the exact SHA (clean before/after every step, `git status --short` = 0).
  Delta-verification per the ccdd54f8 REJECT contract: only K8 + the new REDs re-run
  live; all other evidence carries from the ccdd54f8 verdict
  (D2-DA-VERDICT-ccdd54f8.md) because the delta is test-only.

## VERDICT: **APPROVE — D2 FINAL DA SEAL ISSUED**

## Delta evidence (re-executed live at 4450437f)

1. **Diff audit**: ccdd54f8..4450437f = `test_v6_d2_encode_fence.py` +18 lines ONLY
   (2 new REDs: row/residual `refined_text + "?"` text-length poison — leaf-INVALID,
   conservation-CLEAN, exact-type-CLEAN). Production code byte-untouched.
2. **Fresh-process 2-seed PASS**: PYTHONHASHSEED=0 → **278 passed**; 777 → **278
   passed** (full v6 d1+d2; 276 prior + the 2 new REDs).
3. **B5 resolved — K8 no longer vacuous**: K8 knockout (`validate_python` →
   passthrough) now fails **exactly** the 2 new REDs
   (`test_encode_rejects_row_text_length_poison_no_bytes`,
   `test_encode_rejects_residual_text_length_poison_no_bytes`), 276 others green,
   worktree restored clean (0 dirty, HEAD re-confirmed). This matches the DA's own
   non-equivalence probe (intact REJECT / knockout EMITTED 877B) — the B4 fence is
   now provably non-vacuous.
4. **Static PASS on the changed file**: ruff clean; basedpyright (venv interpreter)
   0 errors, 1 warning = reportUnusedCallResult in tests (accepted category).
   No skip/xfail/type-ignore/noqa/TODO/cast (grep CLEAN).

## Carried evidence (from D2-DA-VERDICT-ccdd54f8.md — valid: test-only delta)

- A-B1/A-B2 fix-RED differential (a0ecb874 EMIT 876B ×2 → REJECT ×2), honoring the
  #24 CONCESSION mandate.
- Mutation battery K1–K15 mechanism map (K13 = ADJ-2 equivalent mutant, recorded).
- ruff/basedpyright over all 22 c71ef4cc.. files: 0 errors, warnings = 2 accepted
  categories only.
- **ADJ-1 closed set @D2 (updated)**: reportUnnecessaryComparison allowed ONLY at
  `assert_never` sentinels `d2_assembly.py:58,70,98`, `d2_codec.py:82,131`,
  `d2_handoff.py:94` (+ D1 `d1_split.py:106`) — re-check file:line each SHA; any
  occurrence outside = blocking.
- Diff hygiene (23 D2-only files vs c71ef4cc, D1 sealed files byte-untouched),
  LOC limits, C0 rollout fence (no runtime d2_* import; import-fence suite green).

## Notes
- Successor batteries at any future SHA: K1–K15 + K8-text-length + A-B1/A-B2
  differential are the minimum set; K13 stays the recorded equivalent mutant.
- HOLD unchanged: C2/provider/Redis/consumer activation, translate/type1/commit/
  publish/seal, release-bridge retirement, main merge, push. Local service startup
  HOLD until the 2026-07-22 demo — this seal used isolated pytest/mutation only.
