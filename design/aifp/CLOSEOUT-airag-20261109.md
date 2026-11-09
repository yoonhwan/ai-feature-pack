# CLOSEOUT airag — 재부팅 대비 정지 (2026-11-09)

> 쓴 좌석: aifp-airag-master-claude#14 · 발주 = planner pi#244 #3784(오빠 11:3x 직접 «다른 팀은 재부팅 준비 → 모두 종료 대비 → 준비 끝나면 종료 · FT 2.0 완성 뒤 재시작» · desk#124 #275173)
> 이 장이 airag 재시작의 정본이다. 다시 열 때 이 장만 먼저 읽는다.

## 1. 골 원문

최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.

A03 닫는 증거: C12(consumer 상시 서비스 회복 · 안 B AIRAG.app) · C13(KakaoBot 통합 보고서 published 칸).

## 2. 정지 직전 상태

- 정지 전부터 보류였다: 오빠 «h49·h51 둘 다 보류»(11-08 10:5x · planner #3767 · desk#121 #273483 hold). 하네스 감사 판정(BYZ #273314) 뒤 재개 예정이었다.
- 자율 OFF · 세션 cron 0(팀장 81eff223 삭제 · planner #3783 · 하위 좌석은 CronCreate 기록 0).

## 3. 카드

| 카드 | 상태 | 닫는 증거 · 남은 것 |
|---|---|---|
| airag-tick-op-7s (`indices/대기/airag-tick-op-7s.md`) | 진행 · 코드 끝 · 설치만 남음 | 코드 069e64a8(7.0/14.0) · R-H·R-F DA r1 569405f2 → b193b054 → r2 2febb4ce → [범위 밖] 1(arch#43 #3637) → 회귀 9파일 737/0(nano#3 #3642) → D2 APPROVE → wip 해제 835f2d6f. 남은 것 = h51 설치 → 전·후 값 7.0/14.0 확인 → 끝 줄 5·6 |
| C12-h-S1 인증서(h8) → h-S2 서명만(h49) | 진행 · h49 발급, 미실행 | h8 창 = 안 뜸(오빠 11-07 10:3x · `.fable-team/state/team-main/airag/facts-h8-h9-20261107.md`). 남은 것 = h49 결과로 `feature-pack/rag/docs/artifacts/arch-20261107-appB-fix-r2.md` §3 표 14행 판정 |
| C12-카드 2 탐지기 S0·S1(h9) (`indices/대기/airag-detector-s0s1.md`) | 판정 불가 확정 · 안 B 그대로 | 끝 줄 3 채움 → 완성(카드 PR 때) |
| C12-h-A·h-B 앱 설치·로그인 항목 | 대기 | 선행 = h51 끝 ∧ h49 새 행 통과 |
| C12 회복 관찰(U2) | 대기 | 선행 = h-A·h-B |
| C13 KakaoBot 통합 보고서 published 칸 | 대기 | 선행 = C12 회복 관찰 |
| (후보) build.sh op_call 상한 10.5·21 → 7·14 | 후보 · 안 엶 | h-A 뒤 master 판단 |
| 팩 PR 761 | 완성 | — |

## 4. 대기 h (오빠 손 · 둘 다 보류)

| h | 내용 | 계획 파일 | 결과 확인 |
|---|---|---|---|
| h51 | 설치본 tick 교체(COMMIT=835f2d6f · 점검 rc 0) | `.worktrees/rag-transplant/.fable-team/state/airag/tick-install-plan.sh` | `/tmp/h51.ran`·`.out` |
| h49 | 서명만(h-S2) | `.worktrees/rag-transplant/.fable-team/state/airag/h-s2-sign-only.sh` | `/tmp/h49.ran`·`.out` |

- 재부팅하면 `/tmp/h49`·`/tmp/h51` 이 지워진다. 재개 때 `ft-hil.sh --add` 로 재등록하고 머리 `# ft-hil-request seat=` 를 새 좌석으로 바꾼다.

## 5. 가지 · PR · 미커밋

| 가지 | 로컬 = 원격 sha | 미커밋 |
|---|---|---|
| feature/rag-transplant | 835f2d6f = origin 835f2d6f | 0 (`.claude/`·`CLAUDE.md` 미추적 = 하네스 배포물 · airag 것 아님) |
| airag/ops | 이 장 커밋 sha(push 뒤 [정지 레디] 에 적음) | 0 (카드 증거 줄 5줄을 이 장과 같은 커밋에 실음) |

- 열린 PR 0(feature/rag-transplant PR 없음 · airag/ops PR 761 CLOSED).
- airag/ops 는 origin/main 보다 71 커밋 뒤다. 재개 때 main 위로 다시 올리고 카드 PR 을 연다.

## 6. 좌석

| 좌석 | 모델 | 상태 | kill |
|---|---|---|---|
| aifp-airag-master-claude#14 | Opus 5.5 | 이 장을 쓰고 [정지 레디] 를 보낸 뒤 유휴 | 필요(h 묶음) |
| aifp-airag-master-claude#13 | Opus 5.5 | 명부 retire 끝(#14 승계) · 유휴 | 필요(h 묶음) |
| aifp-airag-nano-claude#1·#3·#4 | Sonnet 5.5 | 유휴 · cron 0 | 필요(h 묶음) |
| aifp-airag-da-codex#5 | GPT-6.1 Sol | 유휴 · DA 3회 중 2회 사용 | 필요(h 묶음) |

- 하위 좌석 닫기 도구는 이번에 쓰지 못했다: `ft-nano-close.sh` 는 `aifp-` 이름을 «나노 좌석 이름이 아니다» 로 REJECT 한다(규칙 `byz-<팀>-nano-<키>#N`). `ft-seat-close.sh` 는 닫으면서 세션을 kill 해서 «kill 은 h 묶음» 지시와 어긋난다. 명부 표기는 kill h 와 함께 정리한다.

## 7. 나중에 볼 것

- **다른 트랙 랜딩 때**: 하네스 감사 판정(BYZ #273314) · FT 2.0 완성 · nano-close 의 `aifp-` 좌석 이름 지원.
- **완성 후(재개 뒤)**: h51 → h49 → h-A·h-B → U2 관찰 → C13. build.sh 상한 후보는 h-A 뒤에 판단한다.

## 8. 다시 여는 법

1. 이 장과 `.fable-team/state/team-main/airag/HANDOVER-master13-to-14-20261108.md` §2 를 읽는다.
2. 최신 origin/main 에서 새 팀장 좌석을 연다. airag/ops 를 main 위로 다시 올린다.
3. h49·h51 을 재등록하고 오빠께 실행 줄을 올린다(보류 해제를 먼저 확인).
4. 세션 cron 은 오빠 «틱 금지»(11-08 16:2x·20:3x)가 풀렸는지 확인한 뒤에만 건다.
