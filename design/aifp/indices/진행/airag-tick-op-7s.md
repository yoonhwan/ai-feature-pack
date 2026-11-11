# 인덱스: airag-tick-op-7s — 끝: tick.py op 호출 상한을 런타임 7초 룰(판정 4114)에 맞춘다 — 실측 p95 확인 뒤 tick.py:48-49 두 값만 시도 7초 + 재시도 1(합 14초)로 바꾸고 · 7초 넘는 가짜 op 시험이 재시도 1 뒤 실패 raise + ERROR 1줄 · 기존 tick 시험 통과
<!-- ledger: design/aifp/GOAL-LEDGER-airag.md -->
- Issue: 없음 — 2026-11-05 airag 팀 카드(이 카드 r1410 정본 꼴 재작성 · 내용·범위 그대로)
- 제안서: 없음 — 새 안 0 · DA r2 판정 처분 별건(da-20261105-appB-r2.md 끝 2줄)
- 담당: airag (aifp-airag-master-claude#10) · 줄 주인: master#10
- 연 근거: planner arch#41 #3530 (2026-11-05) · DA r2 판정 처분 별건(feature-pack/rag/docs/artifacts/da-20261105-appB-r2.md 끝 2줄 · 커밋 35347c52)
- 분리: build.sh(make-identity·sign) 카드와 범위·DA 회차가 따로다. build.sh 는 로컬 도구라 10.5초 유지(판정 4114 로컬 25초)
- 선행: h-S1(인증서 만들기) 뒤에 착수한다
- 개설 필수조건: 나노를 연다면 `ft-nano-spawn … --base feature/rag-transplant` 만 쓴다(판단 여지 0). origin/main 개설은 금지다 — origin/main 에는 tick.py 가 없다(git cat-file -e rc128 · feature/rag-transplant 는 rc0 · DA aifp 4096 R1). 단 코드는 이미 끝났다(아래 «현재 상태») → 구현 나노 개설 0
- 쓰기 자리: 새 나노 worktree(feature/rag-transplant 에서 갈라진 것)뿐 · 읽기 출처(쓰기 0) = /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant(feature/rag-transplant @ 835f2d6f)
- 기준값(과거 · 카드 작성 때): `feature-pack/rag-consumer/src/airag_consumer/tick.py:48` `OP_ATTEMPT_TIMEOUT_S = 10.5` · `:49` `OP_CALL_DEADLINE_S = 21.0` · 기준 sha feature/rag-transplant @ 35347c52
- 현재 상태(구현 끝 · 재구현 발주 금지): feature/rag-transplant @ 835f2d6f tick.py:48-49 = `7.0` · `14.0`(코드 069e64a8 · DA D2 APPROVE · wip 해제 835f2d6f) · 남은 것 = 설치뿐(origin/main design/aifp/CLOSEOUT-airag-20261109.md:21 «코드 끝 · 설치만 남음» · h51 설치 → 전·후 값 7.0/14.0 확인 → 끝 줄 5·6)
- 상태: 진행(구현 끝 · 설치 h51 보류 · 완성 0 — 설치 증거 뒤에만 완성 이동) · 2026-11-05 airag master#10 작성 · 2026-11-12 정본 꼴 재작성(aifp-ft-arch-pi#1 · aifp 4093) · 2026-11-12 대기→진행(aifp-ft-arch-pi#2 · aifp 4119 · DA 4116)
- 설치: 있음 — 설치된 runtime 의 tick.py 교체는 사람 승인 h 로만(끝 줄 6 · 이 카드 범위 밖이면 «알려진 한계» 1줄)
- 정본 영향 없음: 런타임 상수 2개 · 정본 문서 변경 0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
airag 골 원장(design/aifp/GOAL-LEDGER-airag.md) A03 / 닫는 증거(원장 복붙): 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 · 원래 카드 닫는 증거: C12(consumer 상시 서비스 회복 · 안 B AIRAG.app) · C13(KakaoBot 통합 보고서 published 칸) · 골의 축: A03 C12 — 앱이 5분마다 부르는 tick 의 op 호출이 런타임 7초 절대 룰(판정 4114)을 지킨다.

## 배경 (한 단락)
원래 골(airag 원장): «최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.» 위 «골 원문» 3줄은 aifp 팀 env 의 골(r1410 · 하네스 골)이라 lint 가 요구하는 문면이다. 카드 작성 때(35347c52) tick.py 의 op 호출은 시도 10.5초 · 마감 21초라 런타임 7초 절대 룰을 넘었다(과거 기준값). 지금 feature/rag-transplant 는 7.0/14.0 으로 고쳐져 있고 설치만 남았다. DA r2 판정이 이 처분을 별건으로 남겼다.

## 구현 범위 (구현 끝 · 835f2d6f 에 들어감 · 재구현 0 · 아래는 원래 범위 기록)
- /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/tick.py:48-49 두 값만(읽기 출처 · 쓰기 0)(`OP_ATTEMPT_TIMEOUT_S` · `OP_CALL_DEADLINE_S`)
- 시험 1개(7초 넘는 가짜 op · 70초 이내) + 기존 tick 시험 회귀

## 완료 조건 (끝 줄 · 전부 채워야 완성)
1. [ ] 실측: 지금 tick 로그에서 op 1회 소요 분포(p50·p95·최대 · 최근 N회 · 로그 경로·기간 명시)
2. [ ] 멈춤 관문: 실측 p95 가 7초를 넘으면 구현 전에 멈추고 `[HIL]` 1통(planner master 경유 · 7초 안으로 쪼갤 방법 또는 예외 질문)
3. [ ] 상한: 시도 7초 + 재시도 1(합 14초) · tick.py:48-49 두 값만 바꾼다
4. [ ] 시험: 7초 넘는 가짜 op(sleep) → 재시도 1 → 실패 raise · ERROR 로그 1줄(조용한 성공 0) · 시험 1개 70초 이내
5. [ ] 회귀: 기존 tick 시험 통과(느린 파일은 쪼개 돌림)
6. [ ] 설치본 반영 여부: 설치된 runtime 의 tick.py 교체는 사람 승인 h 로만(이 카드 범위 밖이면 «알려진 한계» 1줄)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| 실측 p95 를 먼저 본다 | 끝 줄 1 분포 원문 |
| p95 > 7초면 구현 전 멈춤 | 끝 줄 2 [HIL] 1통 |
| 시도 7초 + 재시도 1 | 끝 줄 3 diff 2줄 |
| 7초 넘는 op = 실패 raise + ERROR 1줄 | 끝 줄 4 가짜 op 시험 |
| 기존 동작 유지 | 끝 줄 5 tick 회귀 |

## 증거 줄 (진행 중에 채운다)
- 코드 끝: 069e64a8(7.0/14.0) · 회귀 tick 9파일 737 통과·실패 0(nano#3 #3642) · D2 APPROVE · wip 해제 835f2d6f — 출처 origin/main design/aifp/CLOSEOUT-airag-20261109.md:21
- 남은 것: h51 설치 → 전·후 값 7.0/14.0 확인 → 끝 줄 5·6(같은 줄)

## 상태
- 2026-11-05 · airag master#10 카드 작성(대기)
- 2026-11-12 · 정본 꼴 재작성 — aifp-ft-arch-pi#1(aifp 4093 · harness#207 4092 · r1410 실사건 선행) · 끝 줄 6개·기준값·분리·순서 = 원래 카드 그대로 · 새 범위 0
- 2026-11-12 · DA REJECT 보정(aifp 4096 R1·R2) — aifp-ft-arch-pi#2 · base = feature/rag-transplant 필수 · 10.5/21 = 과거 기준값 표시 · 현재 7.0/14.0 구현 끝·설치만 남음 증거 보존
- 2026-11-12 08:15 — 대기→진행 · 좌석 aifp-ft-master-pi#6
