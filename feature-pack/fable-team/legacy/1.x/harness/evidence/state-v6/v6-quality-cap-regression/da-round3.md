# DA Round 3 — v6-quality-cap-regression (cap hotfix rev3)

reviewed: rev3

**codex session-id**: 019f544b-0e54-7d12-ad60-e0078ae2b319  
**tokens used**: 348,944 (cumulative)  
**date**: 2026-07-12

---

## Verdict

**CHANGES_REQUESTED**

---

## codex VERDICT (원문)

```
VERDICT: CHANGES_REQUESTED

- G4 is replaced by a new starvation race: depending on `state.segments` clears and
  restarts the timer on every segment mutation while the same stuck segment remains.
  A chatty session can postpone `capForced` indefinitely.
- Use per-segment deadlines/timer refs, or depend on a stable stuck-ID signature while
  preserving each ID's first-seen timestamp. Adding another stuck segment must not
  reset older deadlines.
- Normal-path cancellation is otherwise correct: translation arrival removes the segment
  from `stuck`, the effect cleanup cancels its pending timer, and no cap marker is
  applied.
- Reducer idempotency is sound: the first sweep sets `capForced`; later sweeps skip it,
  and `upsertSegment` preserves the marker during late events.
- The `cap+5s` gate is valid only when measured from the second press enqueue/release
  timestamp, thereby including queue wait. State that anchor explicitly; process-start
  latency would not measure HOL.
```

---

## DA Driver 종합

### 통과 항목
- **정상경로 무간섭**: 번역 도착 시 stuck 소멸 → cleanup이 타이머 취소 → capForced 미부여 ✅
- **reducer idempotency**: capForced 세그에 두 번째 스윕 no-op, `upsertSegment`가 late event에도 마커 보존 ✅
- **D1/D3/CR-cap3**: r1/r2 통과 사항 무변경 ✅

### Blocker 2건

**CR-cap6 (D2 watchdog — starvation race, G4 대체 신규 결함)**:  
`useEffect([state.segments])`는 state.segments 변경마다 cleanup 재실행 → 타이머 **초기화 재스케줄**. 채팅이 활발한 세션(SSE 이벤트 빈번)에서 stuck 세그가 살아있는 동안 새 SSE 이벤트마다 8s 타이머가 초기화 → 8s 데드라인이 무한 연기 → capForced 영구 미발동. G4(release 타이머 취소)를 제거했지만 동일 등급의 starvation race로 대체됨.  
- **수정 방안**: ① **세그 ID별 타이머 ref** — stuck 세그마다 `timerRef[segId]`를 독립 관리, 해당 segId의 첫 감지 시각에서 8s 후 발동(새 세그 추가 시 기존 타이머 미초기화). ② 또는 **first-seen 타임스탬프** 방식 — stuck ID 첫 노출 시각을 ref에 기록, effect 재실행마다 now-firstSeen이 8s 초과이면 즉시 force_confirm(타이머 불필요).

**CR-cap5b (D1 HOL 게이트 — 앵커 미명시)**:  
`cap+5s` 게이트가 유효하려면 2번째 press의 **enqueue/release 타임스탬프 기준**으로 측정해야 큐 대기 포함. process-start 기준으로 측정하면 HOL을 반영 못 함. 설계에 앵커 명시 없음.  
- **수정 방안**: §2 (b) 게이트에 "2nd press commit 레이턴시 = press-2 enqueue(또는 release) 타임스탬프 기준" 명문화.

---

## 수정 요청 요약

| CR | 대상 | 내용 |
|----|------|------|
| CR-cap6 | D2 use-realtime-solo-v5.ts | useEffect watchdog를 세그 ID별 독립 타이머 ref 또는 first-seen 타임스탬프 방식으로 교체 |
| CR-cap5b | D1 §2-(b) | HOL 게이트 측정 앵커를 "2nd press enqueue/release 기준" 명문화 |

VERDICT

**CHANGES_REQUESTED**
