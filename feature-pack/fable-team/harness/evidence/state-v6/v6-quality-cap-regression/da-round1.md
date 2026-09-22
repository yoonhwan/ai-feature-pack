# DA Round 1 — v6-quality-cap-regression (cap hotfix design)

reviewed: rev1

**codex session-id**: 019f544b-0e54-7d12-ad60-e0078ae2b319  
**tokens used**: 336,214 (cumulative)  
**date**: 2026-07-12

---

## Verdict

**CHANGES_REQUESTED**

---

## codex VERDICT (원문)

```
VERDICT: CHANGES_REQUESTED

- D1 detection is aligned for normal per-sentence translation: identical source language,
  sentence text, and SSOT regex select QUALITY. Mixed presses conservatively receive 14s.
- D3 has a cap mismatch: `_rescue_segments` can be empty, after which
  `retranslate_polished_node` translates `confirmed_so_far`. If that text is
  double-negation, translate.py routes pro while rescue still selects 7s. Detect
  `_rescue_segments` or fallback `confirmed_so_far`.
- "28s background" is false. `pulse_consumer.consume()` processes entries sequentially
  and awaits rescue inline; one request can head-of-line block the stream for ~28s,
  violating its documented <=5s processing objective. Skip identical QUALITY rescue or
  detach it safely.
- D2 is correct only with the documented `ctx.side` filter. Empty translations are
  marked; translated/opposite-side segments remain unchanged, and `applyTranslate`
  accepts late results despite `capForced`.
- 14s is an initial guess, not a calibrated p95. Environment tuning is acceptable only
  with measured completion-time distribution; five samples cannot substantiate p95.
```

---

## DA Driver 종합

### 통과 항목
- **D1 cap 분기 감지 정합**: `has_ko_double_negation(s)` SSOT가 translate.py 내부 라우팅과 동일 텍스트/언어 기반 → 결정적 정합 ✅ (혼합 press는 보수적으로 14s 적용)
- **D2 FE 스윕 정확성**: `ctx.side` 필터+번역 보유 세그 미변경+`applyTranslate`가 capForced 후 지연 번역 흡수 — 기존 계약 무침해 ✅

### Blocker 3건

**CR-cap1 (D3 — rescue cap 미스매치)**:  
`_rescue_segments`가 비어있으면 `retranslate_polished_node`는 `confirmed_so_far` 전체 텍스트로 번역 → 이중부정 포함 시 translate.py는 pro 라우팅하지만 rescue는 여전히 7s cap 적용 → 동일 실패 반복. 설계가 `_rescue_segments`에만 감지를 적용하고 폴백 텍스트(`confirmed_so_far`)를 누락.  
→ **수정**: rescue cap 선택 시 `_rescue_segments` OR `confirmed_so_far` 양쪽에 이중부정 감지 적용.

**CR-cap2 (D3 — "28s 백그라운드" 전제 오류)**:  
`pulse_consumer.consume()`은 entries를 **순차** 처리하며 rescue를 인라인 await — pro 1차(14s)+rescue(14s)=28s 동안 스트림 HOL 블록. 설계 §3 `≤5s processing objective` 위반.  
→ **수정 방안**: ① 이중부정 QUALITY rescue를 skip(이미 pro 실패 → 동일 실패 재반복이므로 rescue 불필요, `""` 즉시 종착) ② 또는 rescue를 `asyncio.create_task`로 분리(별도 검토 필요).

**CR-cap3 (D1 — 14s 초기값 미검증 위험)**:  
"3/3>7s + 2배 규칙" = 하한 증거 기반 추정값, p95 실측 아님. 5샘플로 p95 주장 불가.  
→ **수정**: 설계 §3 S-cap1 캘리브레이션을 **선행 필수 게이트**로 명시 — 분포 측정 전 14s를 prod 배포하는 것은 cap 과소(pro p95가 14s 초과 가능) 또는 과대(큐 점유 낭비) 위험. 단 dev 환경 실측 후 env 조정이면 런타임 수정 가능 — 캘리브레이션 선행 요건을 §4 리스크 항목이 아닌 **D1 수렴 조건**으로 격상.

---

## 수정 요청 요약

| CR | 대상 | 내용 |
|----|------|------|
| CR-cap1 | D3 pulse_consumer.py | rescue cap 감지를 `_rescue_segments` OR `confirmed_so_far` 양쪽 적용 |
| CR-cap2 | D3 구조 | rescue HOL 차단 — skip(권장) 또는 detach(재검토 필요) |
| CR-cap3 | D1 §4→§3 | 14s를 캘리브레이션 선행 게이트로 격상(리스크 항목 강등 아님) |

VERDICT

**CHANGES_REQUESTED**
