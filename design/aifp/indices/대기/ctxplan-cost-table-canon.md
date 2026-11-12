# 인덱스: ctxplan-cost-table-canon — 끝: ctx-plan 패키지에 원고 제목 그대로의 «Claude Opus 5.5 — 구독 요금제 vs API 비용 (하루 기준)» 표가 문서 정본 1파일로 있고, README 에서 1줄로 찾아간다. 숫자는 원고 그대로이고, 근거가 없는 칸은 [확인 필요] 로 남는다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8356 (byz-agents · team:harness-ops)
- 지시: 오빠 desk 원문 «이거 ctx-plan 프로젝트에 정본화 기준으로 랜딩»(2026-11-11 18:5x) → planner 3930 → aifp master #3931
- 원고: /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/team-main/planner/ctx-plan-plan-cost-table-src-20261111.md (desk#132 작성 · 이 카드 기준 판 = 36줄 · sha256 앞 12자 4fe0900bd354 · 수정 2026-11-11T19:04 · planner 3943 · 오빠 «이것도 기록» desk #285362) · 착수 때 sha 가 다르면 멈추고 arch 1통
- 나노: r1675 나노 좌석에 이어 준다(r1675 닫힌 뒤 · master #3931)
- 중복 확인: 팩 origin/main feature-pack/ctx-plan/ 에 docs/ 폴더 0 · 비용 비교 문서 0 · manifest public_docs = README.md 1개뿐 → 같은 문서 0
- 제안서: 없음 — 오빠 직접 지시이고 고칠 안이 1개(문서 1파일 + README 1줄)다
- 상태: 대기 · 2026-11-11 · aifp-ft-arch-pi#0 초안(#3931)
- 설치: 없음 — 문서만 · 코드 0
- 선행: r1675 닫힘(같은 나노 좌석)
- 시험 입력: 원고 파일(읽기만) · 팩 가지 사본 · 실 HOME 쓰기 0
- 수용 기준:
  - ⓐ 문서 1파일 `feature-pack/ctx-plan/docs/plan-cost-table.md` · 원고의 표·표 아래 참고 줄·핵심·기준 절을 그대로 옮긴다(행·열 수 고정 0 · 원고 판을 따른다) · 문서 제목 = 원고 제목에서 «· 정본 후보 원고» 만 뺀 글 그대로 · 머리에 출처(오빠 desk 원문 · 2026-11-11)와 «숫자는 원고 그대로 · 다시 계산하지 않음» 1줄
  - ⓑ 숫자 대조: 원고의 표·핵심·기준 절에서 뽑은 숫자 토큰 목록과 문서의 같은 절 숫자 토큰 목록이 같다(새 숫자 0 · 빠진 숫자 0) · 대조 명령 1줄과 결과를 증거로 남긴다
  - ⓒ 근거 없는 칸 표시: 기준 절에 출처가 없는 숫자는 값 옆에 «[확인 필요: 근거]» 를 붙인다 · 지금 원고 기준 = 월 구독료 3칸(Pro·Max 5x·Max 20x)에 «[확인 필요: 요금 출처·기준일]» · 값은 바꾸지 않는다
  - ⓓ 경로 표기: 원고의 «design/harness/ANALYSIS-token-waste-and-reload-cost-20261110.md 14행» 은 BYZ 리포 경로다 · 문서에는 «BYZ-Agents» 리포 이름을 앞에 붙인다(팩 안 경로로 오해 0)
  - ⓔ README 링크 1줄: `feature-pack/ctx-plan/README.md` 머리 설명 단락(7줄) 다음, «## Quick start» 앞에 원고 꼴 1줄 = «<문서 제목(ⓐ 와 같은 글)> 표 = docs/plan-cost-table.md» · 새 낱말·새 숫자 0 · 링크 경로 실재
  - ⓕ 회귀: `bash feature-pack/ctx-plan/test/contract.sh` · `bash feature-pack/ctx-plan/test/acceptance.sh` rc 가 앞 판과 같다
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 11(측정 조작 금지 · 숫자 새로 만들기 0) · VOICE 40(사실·수치 지어내기 0 · 없으면 [확인 필요])
- 팩 파일 owner: aifp 정본화 팀(feature-pack/ctx-plan)
- 대상(쓰기 = 나노 · 팩 1곳): feature-pack/ctx-plan/docs/plan-cost-table.md(새) · feature-pack/ctx-plan/README.md(1줄)
- 크기: 문서 1파일(원고 36줄 안팎) · README 1줄 · 코드 0
- 정본 영향 있음: ctx-plan 문서 정본 1파일 새로 만듦
- 배정: 대기(선행 · 2026-11-11T18:56)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」 · 골의 축: A(모니터·오빠 요청 — 오빠 요청을 받아 바로 확인 검토) · 이 카드의 증거 = 문서 착지 sha + 숫자 대조 1줄(ⓑ) + README 링크 1줄(ⓔ).

## 배경 (한 단락)
오빠가 desk 에서 구독 요금제와 API 비용 비교 표를 ctx-plan 정본으로 남기라고 했다. 지금 ctx-plan 은 감당량(정원·필요 장수)만 내고, 비용 비교 문서는 없다. 표 원고는 BYZ planner 폴더에 36줄로 있지만 팩에는 없다. 그래서 다른 좌석이 같은 숫자를 다시 계산하거나 다른 숫자를 쓸 수 있다. 이 카드는 원고를 팩 문서 1파일로 옮기고 README 에서 찾게 만든다.

## 고칠 안 1개
- 원고를 `feature-pack/ctx-plan/docs/plan-cost-table.md` 로 옮기고 README 에 링크 1줄을 더한다.

## 구현 범위 (나노 1 · 팩 가지 커밋 1)
- 새 파일: `feature-pack/ctx-plan/docs/plan-cost-table.md` (ⓐ~ⓓ)
- 고칠 파일: `feature-pack/ctx-plan/README.md` 1줄 (ⓔ)
- 산출: 팩 가지 1커밋 · 숫자 대조 1줄 · RUN 줄(단계별 초) · arch 1통

## 범위 밖
- ctx-plan 출력에 표 넣기 → 다음 카드 후보 1줄: «ctx-plan 에 비용 모드를 더해 ctx-burn 실사용과 정가 상수로 이 표를 매번 계산해 낸다(문서 숫자 = 시점 고정 값)»
- manifest public_docs 등록 · 설치 · 요금·환율 갱신 주기 · 숫자 다시 계산

## 완료 조건
- ⓐ~ⓕ

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| 문서 1파일 · 원고 절 그대로 | ⓐ 절·제목 대조 |
| 새 숫자 0 · 빠진 숫자 0 | ⓑ 숫자 토큰 대조 |
| 근거 없는 칸 표시 | ⓒ [확인 필요] 3칸 |
| BYZ 경로 오해 0 | ⓓ 리포 이름 |
| README 에서 찾는다 | ⓔ 링크 경로 실재 |
| 기존 시험 그대로 | ⓕ rc 대조 |

## 사전검증
- 소환: 예
- DA: aifp-ft-da-codex#0 · 사전검증 대기(master 발주)

## 조사 근거
- feature-pack/ctx-plan/README.md:9 «## Quick start» — 링크 1줄 자리(앞 설명 단락 1~7줄)
- feature-pack/ctx-plan/manifest.json:67 «public_docs» = README.md 1개(docs/ 0)

## 상태
- base_sha: 696eea7f89a2ea7ffaaed3970fe088712550c5fd
- 2026-11-11 · aifp-ft-arch-pi#0 카드 초안(#3931) · 대기
- 2026-11-11 19:07 · 원고 바뀜 반영(#3944 · planner 3943): API 열 제거 · 토큰 M 표기 · «구독이 API보다 N배 저렴» 줄 · 주간 최대 3행 · 상한 계산 순서 → ⓐ 행·열 고정 풀고 원고 판(sha) 고정 · ⓔ README 문구 = 원고 제목
