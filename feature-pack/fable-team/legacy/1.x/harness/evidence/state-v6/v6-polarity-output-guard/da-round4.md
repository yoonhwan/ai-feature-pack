reviewed: rev4
session: 019f544b-0e54-7d12-ad60-e0078ae2b319

## VERDICT: APPROVE w/COND

CR-pol8 봉합 확인 완료. r1~r4 순환 종결.

### Verdict detail
- Both lookbehinds `(?<!not\s)(?<!n't\s)` are valid fixed-width Python re constructs (4 chars each). All contraction traces (can't/mustn't/shouldn't/don't/needn't/won't + avoid/refrain/abstain) correctly non-match; "Avoid eating"/"Refrain from eating" (reversal) correctly matches. No structural blocker.
- **COND (nonblocking)**: Multiple spaces — "can't  avoid" (double space) defeats the single-`\s` lookbehind → branch-2 matches → triggers fail-safe rejection (return "") rather than reversal exposure. P0-safe but reduces availability.
  - Recommended: normalize whitespace in `has_en_prohibition(text)` before matching (e.g. `re.sub(r'\s+', ' ', text)`) OR add regression pin "can't  avoid" → no match. Not a landing blocker.

### Prior rounds summary
| Round | CR | Status |
|---|---|---|
| r1 | CR-pol1~4 (4-exit wiring, budget pre-check, scope §2-0, recall) | RESOLVED |
| r2 | CR-pol5~7 (inner timeout, avoid flip_verbs, MULTILINE skip) | RESOLVED |
| r3 | CR-pol8 (contraction n't gap) | RESOLVED in rev4 |
| r4 | APPROVE w/COND (double-space nonblocking) | **FINAL** |

VERDICT: APPROVE w/COND
