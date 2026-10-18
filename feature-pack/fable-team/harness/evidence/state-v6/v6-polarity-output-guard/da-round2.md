# DA Round 2 — v6-polarity-output-guard (rev2)

reviewed: rev2

**codex session-id**: 019f544b-0e54-7d12-ad60-e0078ae2b319  
**tokens used**: 375,771 (cumulative)  
**date**: 2026-07-12

---

## Verdict

**CHANGES_REQUESTED**

---

## codex VERDICT (원문)

```
VERDICT: CHANGES_REQUESTED

- E1-E4 cover current nonempty success exits; each retry-loop iteration reaches E1
  only when returning success. _UNAVAILABLE_MESSAGE contains no prohibition language
  and is safely excluded.
- The 5s check does not solve cap preemption. With measured ~19.9s pro latency,
  starting a retry with 6-19s remaining can still be canceled by the outer 25s cap
  before validator logging/return. Wrap retry in an internal timeout bounded by
  remaining budget minus margin.
- "cannot avoid eating" is falsely rejected: `cannot` matches the first alternative
  because `avoid` is absent from `_EN_OBLIGATION_FLIP_VERBS`; the later lookbehind
  cannot undo that match. Add avoid/refrain/abstain to the flip set as appropriate.
- Without re.MULTILINE, `^\s*skip` matches only the entire string start, not a later
  sentence such as "You must eat. Skip alcohol." Document or expand the boundary.
- Returning empty for acknowledged mixed-clause ambiguity is consistent with the
  stated P0 invariant.
```

---

## DA Driver 종합

### 통과 항목
- **CR-pol1 4-exit 완전성**: E1~E4 현재 nonempty success exit 전수 커버. retry 루프 각 iteration은 성공 시에만 E1 도달. `_UNAVAILABLE_MESSAGE`="[Translation unavailable]" — 금지형 어휘 없음, 제외 안전 ✅
- **혼합절 `""` 수용**: P0 불변식("번역 없음 > 반전 번역") 정합 ✅

### Blocker 3건

**CR-pol5 (CR-pol2 잔존 — retry mid-flight cap 취소)**:  
5s 사전 검사(`elapsed > cap-5s → skip retry`)가 재시도를 시작하지 않는 것은 막지만, 재시도 시작 **후** outer 25s cap이 취소할 수 없음. 19.9s first-call → 잔여 5.1s로 재시도 시작 → outer cap이 0.1s 내 전체 스택 취소 → logging/return 미완료. **5s 검사를 통과한 재시도도 여전히 cap에 의해 취소 가능**.  
→ **수정**: 재시도 자체에 **내부 timeout = `remaining_budget - margin`** 적용. 예: `asyncio.wait_for(_pol_resp = service.generate(...), timeout=_cap - _elapsed - 1.0)`. budget 부족 시 `TimeoutError → return ""`로 처리.

**CR-pol6 (regex — "cannot avoid eating" 오탐)**:  
`cannot`이 `_EN_NEG_MARKERS` 첫 번째 alternative에 매칭 후 lookahead는 `_EN_OBLIGATION_FLIP_VERBS`(현재 `wait|delay|skip|...`)를 확인하는데 `avoid`가 없어서 매칭 통과 → "cannot avoid eating"(의무: "must eat") 오탐으로 가드 발동.  
→ **수정**: `avoid`, `refrain`, `abstain`을 `_EN_OBLIGATION_FLIP_VERBS`에 추가. `cannot avoid eating` → lookahead가 "avoid" 차단 → 비매치(의무형 보존).

**CR-pol7 (regex — `^\s*skip` MULTILINE 부재)**:  
`re.MULTILINE` 없으면 `^`는 전체 문자열 시작만 매칭. "You must eat. Skip alcohol." 같은 다중 문장에서 중간 `Skip`은 미매치 — 잔존 반전 미탐.  
→ **수정 방안 A**: `re.MULTILINE` 플래그 추가(각 줄 시작에 매칭). **수정 방안 B**: `^\s*skip` 대신 `\bskip\b`로 변경하되 flip_verbs lookahead 적용으로 "cannot skip eating" 비매치 보장. 설계에 범위 명문화.

---

## 수정 요청 요약

| CR | 대상 | 내용 |
|----|------|------|
| CR-pol5 | _polarity_validated retry | 내부 `asyncio.wait_for(timeout=remaining-margin)` 추가 |
| CR-pol6 | _EN_OBLIGATION_FLIP_VERBS | avoid/refrain/abstain 추가 |
| CR-pol7 | `^\s*skip` | re.MULTILINE 추가 또는 `\bskip\b`+lookahead 방식 |

VERDICT

**CHANGES_REQUESTED**
