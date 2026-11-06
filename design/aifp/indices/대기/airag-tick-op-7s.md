# airag-tick-op-7s — tick.py op 호출 상한을 런타임 7초 룰에 맞춘다

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: C12(consumer 상시 서비스 회복 · 안 B AIRAG.app) · C13(KakaoBot 통합 보고서 published 칸).
골의 어느 축인가: A03 C12 — 앱이 5분마다 부르는 tick 의 op 호출이 런타임 7초 절대 룰(판정 4114)을 지킨다.

담당: airag (aifp-airag-master-claude#10) · 줄 주인: master#10
연 근거: planner arch#41 #3530 (2026-11-05) · DA r2 판정 처분 별건(feature-pack/rag/docs/artifacts/da-20261105-appB-r2.md 끝 2줄 · 커밋 35347c52)
분리: build.sh(make-identity·sign) 카드와 범위·DA 회차가 따로다. build.sh 는 로컬 도구라 10.5초 유지(판정 4114 로컬 25초).
순서: h-S1(인증서 만들기) 뒤에 착수한다.

## 기준값

- `feature-pack/rag-consumer/src/airag_consumer/tick.py:48` `OP_ATTEMPT_TIMEOUT_S = 10.5`
- `feature-pack/rag-consumer/src/airag_consumer/tick.py:49` `OP_CALL_DEADLINE_S = 21.0`
- 기준 sha: feature/rag-transplant @ 35347c52

## 끝 줄 (전부 채워야 완성)

1. [ ] 실측: 지금 tick 로그에서 op 1회 소요 분포(p50·p95·최대 · 최근 N회 · 로그 경로·기간 명시)
2. [ ] 멈춤 관문: 실측 p95 가 7초를 넘으면 구현 전에 멈추고 `[HIL]` 1통(planner master 경유 · 7초 안으로 쪼갤 방법 또는 예외 질문)
3. [ ] 상한: 시도 7초 + 재시도 1(합 14초) · tick.py:48-49 두 값만 바꾼다
4. [ ] 시험: 7초 넘는 가짜 op(sleep) → 재시도 1 → 실패 raise · ERROR 로그 1줄(조용한 성공 0) · 시험 1개 70초 이내
5. [ ] 회귀: 기존 tick 시험 통과(느린 파일은 쪼개 돌림)
6. [ ] 설치본 반영 여부: 설치된 runtime 의 tick.py 교체는 사람 승인 h 로만(이 카드 범위 밖이면 «알려진 한계» 1줄)

## 증거 줄 (진행 중에 채운다)

- (없음)
