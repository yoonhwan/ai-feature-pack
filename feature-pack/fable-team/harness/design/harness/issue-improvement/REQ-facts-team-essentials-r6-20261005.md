# REQ — v65 「시험 묶음」 실제 방식 실측 (ft-harness-arch#2 → ft-harness-nano#1 · 2026-10-05 · 조각 P7 r6 정정)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜(메인 기획)을 얼마나 잘 수행해내느냐에 핵심이 달려 있는 거예요. 지금 이 골(Goal)들은 그 세부 항목들을 다 잘 처리해서, 결국엔 그 루트인 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있는 거죠. 이게 기획에 반영되어야 해요.
>
> 골의 축: 표 A(모니터) · 원문 7 핵심 한 줄(쪼갠 작업을 동시에 시험하는 폭). 발주 = ops#2 ORDER-essentials-bundle(#57036). 오빠 원문: 「tester+checker(bts,poller) 하나의 구성으로 v65 에서 단순화하고 빠르게 수집 보고 아키텍트에게 올린 이게 유효함. press test 가 필요한 작업이나 플랜에」

읽기 전용 · 수정 0 · 커밋 0. 이미 측정된 E1~E3(`FACTS-team-essentials-20261005.md`)은 다시 재지 않는다. 산출 `design/harness/issue-improvement/FACTS-team-essentials-r6-20261005.md` + 원본 `facts-raw/G*.txt`. 측정 시각 1줄 · [사실]/[추측] · 「파일:줄」.

## G1. 묶음의 구성원 — v65 에서 tester 와 checker 는 한 좌석이었나
- `seats.json` `role=tester` 12행 전부: 키 이름 · `agent`·`model` · 생성/닫힘 시각(필드가 있으면). 이름에 `checker` 가 든 키(`ft-v65-tester-checker-ds#19/#20`)의 role·agent·메모 필드 원문 — **tester 와 checker 를 한 좌석이 겸했는지** 명부 문구로.
- tester 좌석에 보낸 발주(mbox 로그 `to=ft-v65-tester-*`) 중 「checker」·「4축」·「4자」·「poller」·「BTS」 가 본문에 든 행 수와 그중 1건 원문(≤5줄).

## G2. 누가 press 를 돌리고 누가 4축을 모았나
- 최근 v65 press 산출 2건(`design/v65/20261003/evid-tester9-press-seq-001/`·`evid-tester10-k4-002/`): 폴더 안 파일 목록 · `runner-seq.log` 또는 READ 파일 머리 10줄 — press 실행 좌석명·러너 이름·시작 시각.
- 그 폴더(또는 같은 회차의 READ/REPORT 파일)에 **4축(FE 콘솔 · poller/DOM · worker 로그 · Redis/저장소)** 이 각각 어느 파일·어느 표로 들어 있나 — 파일명 1개씩. 넷 중 빠진 축이 있으면 「없음」.
- 그 회차에 **checker 좌석이 따로** 썼나(발신 좌석명이 tester 가 아닌 4축 파일·mbox 행) — 있으면 좌석명 · 없으면 「tester 단독」.

## G3. 어떤 형식으로 architect 에 올렸나
- tester → arch 보고 mbox 행(`from=ft-v65-tester-*` and `to=ft-v65-arch-*` 또는 `to=arch…`) 최근 3건: seq · 본문 ≤5줄 · relay 면 파일 경로. **수신이 arch 인가 master 인가** 건수로(tester→arch N건 · tester→master M건).
- 보고 파일(relay 대상) 1개 열어 머리 15줄 — 「4자 대조표」(#8 RULE 표: 아키텍처 문서·코드·로그·화면 + 시간) 가 있는가 · 표의 열 이름 원문.

## G4. 묶음을 누가 언제 열고 닫았나(배분 사건)
- tester 좌석 12행의 생성 시각과 그 직전 master/arch mbox 행(「tester 열어」·`ft-role-spawn.sh tester` 호출 흔적 · ORDERS/카드에 「press 필요」 표기) — **열린 계기** 1건 원문.
- 닫힌 tester(세션 없음)의 마지막 mbox 행 또는 CLOSEOUT 에 「tester 닫음」·「kill」 문구 — **닫힌 계기** 1건 원문. 없으면 「닫는 사건 기록 0」.
- 지금 살아 있는 `ft-v65-tester-claude#13` 의 마지막 발주 seq·시각(유휴 시간).

회신 mbox 3줄: 경로 · 못 한 항목 · 사실/추측 비율.
