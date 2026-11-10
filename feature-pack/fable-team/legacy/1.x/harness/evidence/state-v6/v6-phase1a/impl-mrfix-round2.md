# impl-mrfix-round2 — design-mr-guest-connect-fix-v2.md
status: IMPLEMENTED

## 변경 파일 (4 source + 3 test)
1. `clients/web/src/domains/realtime/use-realtime-station-lifecycle.ts` — `guestConnectReady?: boolean` prop + 5b 가드(`=== false` 시 return) + latch 성공시에만 세팅(`!== false`) + onSttConnect 반환형 `boolean | void`
2. `clients/web/src/components/room/realtime-room-station.tsx` — `guestConnectReady` 계산(`!isGuest || Boolean(guest && guestLang)`) + lifecycle 전달 + stt `isGuest` 전달 + [v2-#1] reload-restore 10s seed-timeout effect(guestLangRef hardening 포함)
3. `clients/web/src/domains/realtime/use-realtime-stt.ts` — `isGuest?: boolean` 옵션 + isGuestRef 미러 + connect() sessionKey 가드(return false) + connect 반환형 boolean + fetchHeaders sessionKey 가드(throw)
4. `clients/web/src/domains/audio/energy-chunk-transport.ts` — `await fetchHeaders()` 3곳을 try 블록 안으로 이동(로직 변경 0)
5. `__tests__/unit/domains/realtime/use-realtime-station-lifecycle-mr-guest-connect.test.ts` — 5 cases (a,b,c,g,h)
6. `__tests__/unit/domains/realtime/use-realtime-stt-mr-guest-guard.test.ts` — 3 cases (d,e,f)
7. `__tests__/unit/domains/realtime/realtime-room-station-seed-timeout.test.ts` — 3 cases (i-a,i-b,i-c)

## verify
- tsc: PASS (0 errors)
- jest: 161/161 suites, 1507/1507 tests — all GREEN

## 설계 편차
없음 — 설계 §①~§③ 그대로 구현.

## hardening 포함 여부
포함 (≤3줄): guestLangRef + setTimeout 콜백 내 `if (guestLangRef.current !== null) return;` 재확인 — 타이머 만료 직전 seed 도착 시 불필요 재입장 방지.

## impl-gate r1 수정
- blocker: seed-timeout 테스트가 로직 복사 hook → fake coverage. DA CHANGES_REQUESTED.
- fix: [structure] `useGuestSeedTimeout` 을 `realtime-room-station.tsx` 하단에 실제 exported hook 으로 추출(동작 변경 0). 테스트가 real import 로 검증.
- approach: extract (component 전체 render 는 150+ lines mock 필요 → 비실용적).
- 테스트 4케이스: ①reload-restore 10s fire ②normal join 미호출 ③unmount cleanup 미호출 ④timer-boundary 9.9s hardening 미호출.
- verify: tsc=PASS, jest=161/161 suites, 1508/1508 tests — all GREEN.
