# DA Round 1 — v6-polarity-output-guard

reviewed: rev1

**codex session-id**: 019f544b-0e54-7d12-ad60-e0078ae2b319  
**tokens used**: 360,406 (cumulative)  
**date**: 2026-07-12

---

## Verdict

**CHANGES_REQUESTED**

---

## codex VERDICT (원문)

```
VERDICT: CHANGES_REQUESTED

- L1486 is not a single convergence point. Existing successful retry and fallback
  paths directly `return out` (notably ~L1396/L1442), bypassing the proposed polarity
  guard. Refactor all success exits through one validator.
- The outer 25s `wait_for` covers the entire first-call+guard-retry stack. With a
  measured 19.9s first call, retry will likely be canceled mid-flight; reversed output
  is safely discarded, but guard resolution/logging never completes. Treat
  remaining-budget exhaustion explicitly or return "" without retry.
- The regex accepts affirmative obligation forms, but has semantic false positives:
  "should not wait to eat," "do not delay taking medicine," and "cannot skip eating"
  may correctly express the obligation.
- Mixed clauses are logically unsatisfiable under the proposed validator: "must eat,
  must not drink" must retain a prohibition, yet any valid retry still matches and is
  rejected. Prompt mitigation cannot override this global lexical gate.
- Recall also misses "may not," "isn't permitted," "is not to," "abstain from," and
  "skip." Scope detection/validation to the double-negated action or clause before
  landing.
```

---

## DA Driver 종합

### Blocker 4건

**CR-pol1 (L1486 단일 수렴점 아님)**:  
기존 성공 경로(retry 성공 ~L1396, fallback ~L1442 등)가 `return out`을 직접 실행 → 폴라리티 가드를 우회. 삽입 지점이 실제로는 단일 수렴점이 아님. 설계의 핵심 전제 오류.  
→ **수정**: 모든 success exit을 단일 validator 함수로 통과시키거나, 실제 코드에서 수렴점을 재확인해 가드 삽입 위치 재정의.

**CR-pol2 (cap-재시도 예산 소진)**:  
25s `wait_for`가 first-call+guard-retry 전체 스택을 감쌈. 19.9s first-call이면 재시도가 mid-flight 취소됨 — 반전 출력은 안전 폐기되지만, guard resolution/logging 미완료. 설계 §2-2의 "14~20s < 25s" 주장은 19.9s 꼬리 케이스에서 **성립하지 않음**.  
→ **수정 방안**: ① 재시도 전 잔여 예산 확인 — `remaining = cap - elapsed`가 최소 여유(예: 3s) 미만이면 재시도 없이 즉시 `return ""`  ② 또는 guard-retry를 cap 바깥에서 별도 예산으로 실행(추가 설계 필요).

**CR-pol3 (regex 의미적 오탐 + 혼합절 불가해)**:  
- **의미적 오탐**: "should not wait to eat", "do not delay taking medicine", "cannot skip eating" — 의무 표현이지만 regex가 금지형으로 오판 → guard 오발동.  
- **혼합절 불가해**: "must eat, must not drink" — 정답이 금지절을 포함하므로 어떤 유효한 재시도 출력도 `has_en_prohibition`에 걸려 항상 rejected → `""` 강제. CRITICAL OVERRIDE의 "genuine single negation clause 유지" 병기로는 global lexical gate를 우회할 수 없음.

**CR-pol4 (recall 갭)**:  
"may not", "isn't permitted", "is not to", "abstain from", "skip" 누락 — 실제 반전 표현을 미탐. 랜딩 전 임상 반전 패턴 완전 열거 필요.  
→ 감지/검증을 전체 출력 대상 global lexical gate가 아닌 **이중부정 행위/절 스코핑 방식**으로 재설계 검토(혼합절 불가해 문제와 동시 해결).

---

## 수정 요청 요약

| CR | 대상 | 내용 |
|----|------|------|
| CR-pol1 | translate.py 삽입 지점 | 실제 수렴점 재확인 — L1396/L1442 우회 경로 봉합 |
| CR-pol2 | 재시도 예산 | 잔여 budget <min 시 retry 없이 즉시 `""` |
| CR-pol3 | regex + 혼합절 | 의미적 오탐 제거 + 혼합절 불가해 → 절 스코핑 또는 gate 재설계 |
| CR-pol4 | EN_PROHIBITION_RE | "may not"/"abstain from"/"skip" 등 recall 갭 보완 |

VERDICT

**CHANGES_REQUESTED**
