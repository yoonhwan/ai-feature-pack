# DA Round 2 — v6-quality-cap-regression (cap hotfix rev2)

reviewed: rev2

**codex session-id**: 019f544b-0e54-7d12-ad60-e0078ae2b319  
**tokens used**: 345,168 (cumulative)  
**date**: 2026-07-12

---

## Verdict

**CHANGES_REQUESTED**

---

## codex VERDICT (원문)

```
VERDICT: CHANGES_REQUESTED

- Rescue skipping correctly removes the empty-_rescue_segments mismatch and the second
  14s HOL block; non-double-neg rescue remains unchanged at 7s.
- D2 is not terminally guaranteed: receipt of `segment.confirmed` clears
  `processingSide`, canceling the release+8s timer before `segments.force_confirm`
  fires. A fast empty result or short forced cap can therefore commit
  confirmed-without-translations and remain `finalizing` forever.
- S-cap2 with `QUALITY_CAP=0.5` should expose this exact failure: confirmed arrives
  around 0.5s, the 8s timer is canceled, and no `capForced` sweep occurs. Use a
  finalizing watchdog independent of `processing`, or mark confirmed-zero-translation
  during confirmed/error handling.
- n>=20 p95 calibration improves the cap basis but does not bound sequential-consumer
  HOL. Add a deployment gate for queue depth/next-press latency and define an
  acceptable maximum cap; otherwise consecutive QUALITY presses can accumulate linearly.
```

---

## DA Driver 종합

### 통과 항목
- **D3 rescue skip**: CR-cap1(confirmed_so_far 미스매치)+CR-cap2(rescue 14s HOL) 동시 해소 ✅  
  비이중부정 rescue 7s 무회귀 ✅
- **CR-cap3 캘리브레이션 게이트**: §2 D1 수렴조건 격상·n≥20·prod 배포 금지 명문화 ✅

### Blocker 2건

**CR-cap4 (D2 — capForced 스윕 타이머 취소 경쟁조건)**:  
`segment.confirmed` 수신 시 `processingSide`가 클리어되면서 **release+8s 타이머가 취소**된다. `FINAL_CAP_EXCEEDED → committing without translations` 직후 confirmed가 빠르게(수백ms~수초 내) 도달하면 타이머 취소 → `segments.force_confirm` 미발동 → capForced 스윕 없음 → `finalizing` 영구 체류. 설계에서 D2를 "정본 안전망"으로 정의했으나 이 경쟁조건으로 **결정적(deterministic) 보장 불성립**.  
- S-cap2(`QUALITY_CAP=0.5`)로 재현 가능: 0.5s에 confirmed 도착 → 8s 타이머 즉시 취소 → capForced 없음 → stuck.  
- **수정 방안**: ① `segment.confirmed` 핸들러에서 번역0 세그를 직접 capForced 마킹(타이머 독립) ② 또는 `processing` 상태와 독립된 finalizing watchdog 추가.

**CR-cap5 (D1 — 연속 QUALITY press HOL 상한 미정의)**:  
캘리브레이션 n≥20이 cap 값 근거를 강화하지만 sequential consumer의 HOL 누적을 차단하지 않는다. 연속 이중부정 press 시 HOL이 선형 누적(cap×N) → 스트림 전체 지연. 최대 허용 cap + 큐 깊이/후속 press 레이턴시 게이트가 배포 조건에 없음.  
- **수정 방안**: §2 D1 수렴조건에 추가 — "(a) p95 cap 값, (b) 연속 2 press 처리 레이턴시≤X초(X=정의 필요)" 측정 후 배포.

---

## 수정 요청 요약

| CR | 대상 | 내용 |
|----|------|------|
| CR-cap4 | D2 v5-segment-reducer.ts | confirmed-번역0 세그 capForced를 타이머 독립으로 마킹(confirmed 핸들러 직접 또는 독립 watchdog) |
| CR-cap5 | D1 §2 수렴조건 | 연속 QUALITY press HOL 상한(큐 깊이/후속 레이턴시 게이트) 정의+측정 배포 게이트 추가 |

VERDICT

**CHANGES_REQUESTED**
