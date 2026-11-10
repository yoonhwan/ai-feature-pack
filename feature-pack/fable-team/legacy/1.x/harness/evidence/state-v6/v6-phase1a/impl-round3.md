# impl-round3 — design-n1-lst-v3.md
status: IMPLEMENTED

## 변경 파일 (전체 목록 + 각 1줄 요약)
1. **NEW** `clients/web/src/domains/realtime/use-lst-setting.ts` — LST 사용자 토글 스토어 훅 (useSyncExternalStore, URL 세션한정, env kill switch)
2. `clients/web/src/domains/realtime/use-realtime-solo-v5.ts` — isLstEnabled() → useLstSetting() 훅 값 교체 (:316 chunker props, :701 selectBubbles)
3. `clients/web/src/domains/audio/energy-vad-handlers.ts` — ChunkerMut 에 lstActive: boolean 필드 추가
4. `clients/web/src/domains/audio/use-energy-chunker.ts` — mut 초기값 lstActive:false, start() 시점 스냅샷, onPcmFrame/startLstLoop 가드를 mut.lstActive 로 교체
5. `clients/web/src/domains/audio/energy-lst.ts` — stopLstLoop 에 mut.lstActive=false 1줄 추가
6. `clients/web/src/components/realtime/realtime-settings-panel.tsx` — DISPLAY 섹션에 LST 토글 Switch 추가 (lstAvailable 조건부 렌더)
7. **NEW** `clients/web/__tests__/unit/domains/realtime/use-lst-setting.test.ts` — A1~A9b 10개 테스트 (기본값/localStorage/URL/kill switch/SSR/교차 param)
8. `clients/web/__tests__/unit/domains/audio/energy-vad-handlers.test.ts` — makeMut fixture 에 lstActive:false 추가
9. `clients/web/__tests__/unit/domains/audio/energy-lst.test.ts` — makeMut fixture lstActive:false + stopLstLoop lstActive=false assert
10. `clients/web/__tests__/unit/domains/audio/use-energy-chunker.test.ts` — C1~C4 스냅샷 lifecycle 테스트 추가 (hold 중 토글 무영향, stale frame 차단)
11. `clients/web/__tests__/unit/components/realtime/realtime-settings-panel.test.tsx` — D1~D3 토글 렌더/콜백/kill switch 숨김 테스트
12. `clients/web/__tests__/unit/domains/realtime/use-realtime-solo-v5.test.ts` — B1~B2 wiring 테스트 (useLstSetting mock + lstEnabled 전달 검증)

## verify 결과 (tsc + jest 요약)
- tsc --noEmit: PASS (0 errors)
- jest: 9 suites / 120 tests PASS (use-lst-setting 10, energy-chunker 21, energy-lst 5, energy-vad-handlers 11, settings-panel 9, solo-v5 22, solo-v5-inc3 14, solo-v5-inc4 21, solo-v5-q2 7)

## 설계 편차
없음

## r1 게이트 수정
### 1. Race fix — lstActive 스냅샷 pre-await 이동
`use-energy-chunker.ts` start(): `m.lstActive = p.current.lstEnabled === true;` 를 `await createPcmCapture()` 이후(~:131)에서 buffer init 직후(:121, await 전)로 이동. press-start 시점 값을 캡처해 capture 생성 중 props 변경에 대한 race 방지.

### 2. Race test C5 추가
`use-energy-chunker.test.ts`: MockAudioContext 의 addModule 을 deferred promise 로 교체해 createPcmCapture 를 정지시키는 패턴.
- C5a: start(lstEnabled=true) → capture 대기 중 props false 전환 → resolve → lstActive=true 유지 + 롤링 버퍼 push 정상
- C5b: start(lstEnabled=false) → capture 대기 중 props true 전환 → resolve → lstActive=false 유지 + 버퍼 미접근

### verify (r1 수정 후)
- tsc --noEmit: PASS (0 errors)
- jest full: 158 suites / 1496 tests PASS (energy-chunker 32 tests, 전체 회귀 0)
