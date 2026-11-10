reviewed: rev3
session: 019f544b-0e54-7d12-ad60-e0078ae2b319

## VERDICT: CHANGES_REQUESTED

**CR-pol8 (BLOCKER)**: Branch-2 contraction gap — `(?<!not\s)` lookbehind does NOT cover `n't ` form.
- "can't avoid eating": branch-1 blocked (avoid in flip_verbs), but branch-2 `(?<!not\s)` only looks for literal `not `. The preceding `n't ` is not matched → `avoid` fires → false positive.
- Same for "mustn't avoid eating", "shouldn't avoid eating", "needn't refrain".
- Fix: expand lookbehind to cover both forms, e.g. `(?<!not\s)(?<!n't\s)`, or combine into alternation-based negative lookbehind. Add unit tests for can't/mustn't/shouldn't + avoid/refrain/abstain.

## CR-pol5 disposition
Not a reversal-safety blocker. `asyncio.wait_for` cancellation is cooperative — slow provider may consume the 1s margin and trigger outer cap before inner log fires. Impact = log observability only (outer TimeoutError still propagates → return "" path). Recommend documenting inner logger as best-effort; no structural change required.

## CR-pol6 disposition
"cannot avoid eating" double-branch: VERIFIED correct (branch-1 blocks via flip_verbs lookahead; branch-2 blocked by `(?<!not\s)` since "cannot " ends with `ot `). However CR-pol8 (contractions) is the gap.

## CR-pol7 disposition
re.MULTILINE + sentence-boundary lookbehind for `skip` is structurally sound. `^` matching per-line with MULTILINE is correct semantics for this guard. Adverb interposition ("cannot absolutely avoid eating") is accepted documented §2-0 false-positive class — not a blocker.

## Required before re-review
- Rev4: extend branch-2 lookbehind from `(?<!not\s)` to `(?<!not\s)(?<!n't\s)` (or equivalent).
- Add tests: "can't avoid eating" → no match; "mustn't refrain from eating" → no match; "shouldn't abstain" → no match; "Avoid eating" → MATCH; "Refrain from eating" → MATCH.
