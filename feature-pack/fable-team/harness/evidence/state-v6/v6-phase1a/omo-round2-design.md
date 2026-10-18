# OMO Round 2 — design-n1-lst-v2.md
reviewed: v2

VERDICT: REJECT

yoonhwan 오빠, 전체 재리뷰를 `/tmp/n1-lst-review-r2-out.md`에 작성하고 내용까지 확인했습니다.

핵심 차단 사유:
1. A9 테스트가 실제 키 `polishDiff`가 아니라 `showPolishDiff`를 사용합니다.
2. `mut.lstActive` 추가 후에도 `stopLstLoop()` 무수정은 late PCM frame/stale buffer 위험이 남습니다.
3. C lifecycle 테스트가 stop/reset 이후 stale `lstActive`를 잡지 못합니다.
4. A8 SSR/hydration 테스트 실행 방식이 불명확합니다.
5. BTS D가 `DEFAULT = appConfig.v6LstEnabled` 의미론과 충돌합니다.
6. `ChunkerMut` typed fixture 업데이트가 변경 계획에 빠져 있습니다.

검증:
- 실제 코드 라인 대조 완료.
- 5개 review-work 레인 수집 완료: goal/QA/code/context FAIL, security PASS.
- 기존 LST 저수준 테스트 실행: `3 suites passed, 64 tests passed`.