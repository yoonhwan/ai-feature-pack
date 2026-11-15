# 인덱스: ft2-launch-failed-end — 끝: 열기 실패(launch-failed)와 열기 멈춤(intent opening)이 쉼 줄 뒤에 조용히 남지 않는다 · 착지했으면 keeper 가 complete 로 닫고 아니면 사람 판정 [긴급] 1줄이 뜬다 · keeper 는 이미 착지한 카드를 새로 넣지 않는다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8633 — 등록 planner#323 aifp 5348(팀장 aifp-ft-master-pi#17 발주 aifp 5310 ② · 5326 행 D·F · 5346 · planner#323 aifp 5308 · 오빠 Slack 11-16 00:42 «페이블이 해결 · 끝까지 책임»)
- 제안서: 없음 — 결함 복구(새 안 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-p2-launch-failed-no-park-rest-20261116.md(p3 sha256 7b12eb7f…b328 · DA 대행 byz-harness-da-codex#11 = r1 APPROVE-DESIGN aifp 5339 · 고칠 칸 0 / p3 덧 규칙 6·7·명부 찾기 APPROVE-DESIGN BYZ 309947 · 새 동작 반례 0 · 전문 .fable-team/state/team-main/aifp-ft/DA-pDF-p3-approve-309947.md) + 훑기 표 orders/SWEEP-FIX-table-20261116.md §F(opening 멈춤 · L6·㉛·M16 = DA 대행 APPROVE-DESIGN BYZ 310141 · 전문 .fable-team/state/team-main/aifp-ft/DA-pDF-L6-approve-310141.md) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 실측 2026-11-16(aifp-ft-arch-pi#16 · 읽기만) — harness r2058: journal 2852 accept → 2853 dispatch a1 → 2854 deliver → intent state failed(step git add · worktree 가 이미 있음) → 00:06:36 PARKED launch-failed(2855 parked) → 00:44:25 손 complete(2863 · harness arch#377 · BYZ #309621)까지 keeper 줄 0 · v65 6장(K4 · M5 4장 · M7): 11-14 12:36~12:54 dispatch·deliver · intent state opening · 세션 0 · owner 남음 · HELD-NEXT «launch rc None Command … 복구 필요» → 매 바퀴 UNKNOWN owner-orphan · v65 capacity 8/8 · harness r2057 = 착지 끝 카드가 대기/ 에 남아 다시 발주됨(팀장 5341 답)
- 근거 덧(harness 문제 목록 A · r2078 넘겨받음 · harness#288 aifp 5376 «harness 쓰기 0 · 이 카드가 맡음» · 팀장 #18 aifp 5378): BYZ .fable-team/state/team-main/harness/a378/keeper-r2057.log 원문(aifp-ft-arch-pi#17 읽기만) — 11-15 23:57:32 LAUNCHING a1 → 23:58:47 UNKNOWN «착지했지만 complete 0 · 남은 범위 줄 없음» → 23:58:49 PARKED launch-failed(git add) → 11-16 00:00:42 LAUNCHING a2 → 00:03:13~01:10:47 WORKING «옛 착지 줄(attempt 전) 4ccf2a67» 13줄 = 착지 줄 있는 대기/ 카드를 fill 이 두 번 다시 엶 · 조사 메모 = BYZ .fable-team/state/team-main/harness/HANDOFF-pi378-to-next-20261116.md 1절(choose :126~152 는 착지 줄을 안 봄 · 착지 판정은 keeper_land.landing :136~176) · r2058 도 같은 꼴(00:05 launch-failed) · 맡는 계약 = L5(착지 카드 제외) + L1~L3(launch-failed 쉼 뒤 재판독)
- 원인 1줄: keeper.team_round 는 최신 attempt 에 parked 줄이 있으면 그 work 를 건너뛴다(302·305줄) · fill 은 열기 실패 카드를 fill_hold 에 넣어 자동 재시도 0 · 반쪽 판정은 intent failed·closed 만 봐서 opening 에 멈춘 열기는 영영 owner-orphan · choose 는 착지 여부를 안 본다
- 앞 카드: r2055(팩 d88ef381 · settle 한 길 · park launch-failed) · r1913·r1939(fill) · r1968·r1973(반쪽) · 계약 feature-pack/fable-team/ft2/contracts/keeper-settle/CONTRACT.md §3
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회(팩 착지 뒤 팀장·harness 설치 묶음) · 되돌림 = 앞 판으로 판 전환
- 선행: 없음 — B ft2-slack-accept-capacity 착지 09c02c0a(PR #1270) + E ft2-keeper-notify-recipient 착지 ae0c199e(PR #1282) 착지 끝 · 팀장 aifp-ft-master-pi#19 이 풂
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 journal·launch intent·카드 파일 · 가짜 tmux(세션 부재 rc1 «can't find session») · 가짜 clock · 가짜 mbox · sleep 0 · 네트워크 0 · 실 runtime 쓰기·읽기 0 · 사례 1개 70초 안
- 기준값: 기준판 = launch-failed 쉼 뒤 그 work 판정 줄 0 · opening 20분 = UNKNOWN owner-orphan 반복 · 착지 카드 fill submit 1 → 목표 = 매 바퀴 재판독(착지면 complete · 아니면 UNKNOWN launch-failed 1줄) · opening 15분 넘음 = park + UNKNOWN launch-failed · 착지 카드 submit 0
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 2(닫기·kill 은 keeper 기존 가드 그대로) · 하드 룰 20 · 하드 룰 22 · r2055 계약 §1(조용히 남는 보류는 없다)
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper.py(team_round 건너뜀 조건) · feature-pack/fable-team/ft2/adapters/pi/keeper_settle.py(settle_nano 판정 · opening 분기) · feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(choose 착지 카드 제외) · 새 시험 feature-pack/fable-team/ft2/tests/test_launch_failed_end.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md·CASES.md
- 정본 영향 있음: CONTRACT.md §3 «PARKED launch-failed» 행 → «UNKNOWN launch-failed»(park 실행 · 판정 UNKNOWN · 매 바퀴 재판독) · CASES.md ③·⑫ 기대값 · ㉘·㉛ 행 = 같은 PR(나노)
- 크기: 코드 3파일 · 새 시험 1파일 · 회귀 기대 고침 1파일 · 문서 2파일 · PR 1개
- 배정: 없음

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — 열기에 실패한 일이 조용히 남지 않고 정해진 끝으로 간다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 v65 capacity 실측 줄 + harness 사실 줄(r2058 complete a1 rc0 rev 2864 · BYZ #309621).

## 배경 (한 단락)
r2055 는 열기에 실패한 일을 쉼(park · 사유 launch-failed)으로 돌려 자원을 풀게 했다. 그런데 keeper 는 쉼 줄이 있는 최신 attempt 를 바퀴에서 건너뛴다. 끝났고 안전한 쉼(idle-done)에는 맞지만 열기 실패에는 틀리다. 일이 시작도 못 했거나, r2058 처럼 다른 손이 이미 끝낸 상태이기 때문이다. fill 은 그 카드를 자동으로 다시 시도하지 않는다. 그래서 판정도 재시도도 없이 남는다. v65 6장은 열기 명령이 시간 초과로 죽어 intent 가 opening 에 멈췄다. 반쪽 판정은 failed·closed 만 보므로 이 6장은 owner 와 칸을 쥔 채 UNKNOWN 만 되풀이한다. r2057 과 r2058 은 이미 착지한 카드가 대기/ 에 남아 fill 이 다시 넣은 것이다.

## 계약
- L1 `keeper.team_round` — 최신 attempt 의 쉼 사유가 launch-failed 이면 건너뛰지 않는다 · idle-done 쉼·returned 는 지금처럼 건너뜀
- L2 그 work 의 바퀴 순서 = 착지 판독 → 착지면 complete(세션이 없으니 닫기 호출 0) → 카드 끝 표식이면 close 길 → 둘 다 아니면 L3
- L3 `keeper_settle.settle_nano` — intent failed·closed ∧ 세션 부재 ∧ owner 남음 = core park(reason launch-failed · 1회 멱등)는 그대로 · 판정 줄 = `UNKNOWN <팀> <work> <좌석> launch-failed · <intent step · reason 앞 80자>` + [긴급] 1통(지문 하루 1회 · 다음 수 = 원인 고친 뒤 원장 갱신 → fill 재시도 · 필요 없으면 return 또는 카드 끝 표식) · `PARKED … launch-failed` 줄 0
- L4 L3 뒤 그 work 에 stall 깨움·재배정·hold 검사 0
- L5 `keeper_next.choose` — 착지 판독이 참인 카드는 fill·닫기 뒤 pick 둘 다 고르지 않는다 · `NEXT-SKIP <팀> <카드> 이미 착지 — 카드 정리 필요` 1줄(값이 바뀔 때만) · 착지 판독은 바퀴 캐시(once)로 카드당 바퀴 1회
- L6(§F · DA APPROVE BYZ 310141) 세션 부재(tmux rc1 «can't find session» 으로 확인 · tmux 조회 실패는 부재가 아니라 판정 불가로 남김) ∧ owner 남음 ∧ intent state opening ∧ intent at 이 OPEN_STALE(900초) 넘음 ∧ 그 열기가 fill_open(잇는 중)에 없음 = 넷이 모두 참일 때만 L3 과 같은 길(park launch-failed + `UNKNOWN … launch-failed · opening <분>분`) · 살아 있는 세션·잇는 중인 열기는 손 0 · 하는 일은 이미 없는 좌석의 core park 이고 kill 0 · park 는 L3 처럼 1회 멱등 · 다음 바퀴는 L2 착지 판독
- L7 경계: 보는 것은 keeper 가 dispatch 한 work 의 launch intent 뿐 · 팀장·arch·desk 개설(ft-successor-open · 팀장 열기 길)은 dispatch·intent 를 만들지 않으므로 판정·park·[긴급] 대상이 아니다
- L10(p3 · DA APPROVE BYZ 309947) 명부 = 이 카드가 내는 [긴급] 의 받는 곳과 다시 뜬 나노의 명부 행은 행 E 의 명부 찾기 한 함수(seats-<팀>.json → 없고 v65 면 seats.json)를 부른다 · 명부 경로를 새로 만들지 않는다 · 함수가 있는 것만으로는 안 된다 = notify 와 enroll 호출부가 그 함수를 실제로 부르는지 인수 때 본다(완료 조건 8)
- L9(p3 · DA APPROVE BYZ 309947) 나노 불가 표식 = 카드 머리 `- 배정: 대기(<사유> · <시각>)` 의 사유가 사람·정지·DA·lint·면제대기·선행 → fill·닫기 뒤 pick 둘 다 고르지 않는다(지금은 선행만 읽음 · 카드 줄 `대기(석` 은 새 표식에서 뺀다 = 막지 않음 · 배정 원장 reason `석` 은 지금 BLOCK 규칙대로 막는다 · 둘을 섞지 않는다) · 판정 근거 순서 = 배정 원장 seat·owner → 배정 원장 reason ∈ BLOCK → 카드 배정 줄 → 카드 선행 줄 · 원장·카드 중 하나만 막아도 막힘 · owner 가 풀려도 다시 띄우지 않는다(재발주 0)
- L8 그대로: core park·capacity·remaining · idle-done 쉼 · fill_hold(자동 재시도 0) · 닫기 직전 가드 · 보정 3

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · ft2-slack-accept-capacity 착지 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_launch_failed_end.py(㉘가~카 · ㉘타·㉘파·㉘하 · ㉛가~라 · M11·M12·M13·M16·M30·M31) · 기준판 FAIL 원문(㉘가·㉘나·㉘다·㉘라·㉘바·㉛가)을 PR 본문에 붙인다
2. 커밋 2 [fix] — L1·L2 = feature-pack/fable-team/ft2/adapters/pi/keeper.py · L3·L4·L6 = feature-pack/fable-team/ft2/adapters/pi/keeper_settle.py · L5 = feature-pack/fable-team/ft2/adapters/pi/keeper_next.py · 다른 함수 손 0
3. 커밋 2 에 같이 — feature-pack/fable-team/ft2/tests/test_settle_one_path_r2055.py ③·⑫ 기대값 = «park 1회 · 용량 −1» 그대로 + 판정 낱말 UNKNOWN launch-failed(삭제 0 · PR 본문에 사례 이름)
4. 커밋 3 [docs] — feature-pack/fable-team/ft2/contracts/keeper-settle/CONTRACT.md §3 행 옮김·머리 표에 «설계 뒤 고침» 1줄 · CASES.md ③·⑫ 문구·㉘·㉛·변이 행 · 설계 2쪽을 feature-pack/fable-team/design/ 로
5. 회귀 rc0: test_core_park_capacity_r2055.py · r1913·r1939 fill 시험 · test_pi_keeper_next_card_r1871.py
6. L6·L9·L10 을 모두 넣는다(DA APPROVE BYZ 309947 · BYZ 310141) · ㉛가~라·M16 포함 · L9 자리 = feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(prereq·choose)
7. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- v65 6장·다른 팀 남은 일의 손 정리(journal 쓰기 = HIL) · 설치 집행
- 열기 실패의 자동 재시도(버린 길 · r1913 «자동 재시도 0» 유지)
- 결과(result) 뒤 세션 0 인 일의 칸 풀기(훑기 표 §F 끝 · 행 A 카드에서 다룸) · 결과 줄만 있고 owner 0·세션 0 인 일과 accept 만 있는 접수는 L6 으로 닫지 않는다
- 알려진 한계(DA BYZ 310141): 정상 pi 열기가 걸리는 시간의 분포를 새로 재지 않았다 · OPEN_STALE 900초가 실측 p99 보다 길다고 주장하지 않는다 · 안전 근거는 시간 값이 아니라 «세션 부재 + 잇는 중 열기 제외» 결합이다 · 실제 capacity 가 줄었는지는 설치 뒤 따로 본다(완료 조건 6)
- 팀장 없는 팀의 [긴급] 받는 곳(행 E 카드)
- 알려진 한계(DA BYZ 309947): 카드 배정 줄과 배정 원장이 둘 다 없던 v65 K4 의 원래 입력은 이 카드 뒤에도 자동으로 막히지 않는다 · 추적 카드에 정지 표식(`- 배정: 대기(정지 · <시각>)`)을 적는 집행은 v65 팀장 몫 · 표식 없는 카드를 모두 막는 고침은 하지 않는다(정상 카드까지 막힌다) · 실제 K4 자동 재개설 중단·실상태 정리는 이 카드의 증거로 주장하지 않는다

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M11 → ㉘나·㉘다·㉘라 FAIL · M12 → ㉘가 FAIL · M13 → ㉘바 FAIL · M16 → ㉛가 FAIL · M30 → ㉘아·㉘자·㉘차 FAIL · M31 → ㉘차 FAIL
4. [ ] 나노: 회귀 rc0 · 고친 기대값 사례 이름
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] arch: 설치 뒤 읽기 실측 1줄(v65 capacity · parked 줄 수)
7. [ ] 팀장: harness 사실 줄 받아 적음(r2058 complete a1 rc0 rev 2864 · BYZ #309621)
8. [ ] arch: notify 와 v65 enroll 호출부가 공용 명부 함수를 실제로 부르는지 확인 1줄(ci refs 원문 · 하드코딩 seats-<팀>.json 경로가 호출부에 남아 있으면 반송)
9. [ ] 나노: DA 인수 칸 ㉘아~카 + 양성 3칸 ㉘타·㉘파·㉘하 rc0 원문

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| L3 park 는 하고 판정은 UNKNOWN | ㉘가 intent failed · 세션 부재 · owner 있음 · 착지 0 → park 1줄 · UNKNOWN launch-failed 1줄 · [긴급] 1 · PARKED 줄 0 / M12 |
| L1·L4 다음 바퀴에도 본다 | ㉘나 ㉘가 다음 바퀴 → 건너뛰지 않음 · park 다시 0 · 판정 줄 반복 0 · stall 깨움 0 / M11 |
| L2 착지면 complete | ㉘다 ㉘가 뒤 카드에 착지 줄 + «남은 범위: 없음» → 다음 바퀴 complete 1 · 닫기 호출 0 · 그 뒤 줄 0 / ㉘라 r2058 꼴(착지 봄 · «남은 범위» 줄 없음) → 매 바퀴 판정 대상 · UNKNOWN 남은 범위 줄 없음 유지 · 카드 고치면 complete |
| L1 idle-done 은 그대로 | ㉘마 idle-done 쉼 → 건너뜀 · 줄 0 |
| L5 착지 카드 제외 | ㉘바 fill 후보 = 착지한 카드 1 + 안 한 카드 1 → 안 한 카드만 submit · NEXT-SKIP 1줄 · 닫기 뒤 pick 도 같음 / M13 |
| L7 팀장 개설은 대상 아님 | ㉘사 팀장 좌석 세션 0 · launch intent 없음 → 판정 줄 0 · park 0 · [긴급] 0 |
| L9 나노 불가 표식 | ㉘아 대기 카드 2장 중 한 장 `- 배정: 대기(사람 · …)` → 그 카드 submit 0 / ㉘자 그 카드뿐 → [다음 없음] 막힌 사유별 사람 1 / ㉘차 표식 카드 · a1 launch-failed 쉼 · 원장 없음 → a2 dispatch 0 / ㉘카 원장 정지 = 막힘 · 카드 `- 배정: 좌석 …`·`없음` = 안 막음 / ㉘타 원장 없음 · 카드 배정 줄 없음 · 선행 없음 → 고름(submit 1) / ㉘파 원장 없음 · 카드 `- 배정: 대기(석 · …)` → 고름(새 표식이 아님) / ㉘하 `- 배정: 대기(사람 · …)` 로 막힌 카드에서 그 줄을 `- 배정: 없음` 으로 바꾼 다음 바퀴 → 다시 고름 / M30 · M31 |
| L10 명부 함수를 부른다 | 인수 확인(완료 조건 8) · 시험은 행 E 카드 ㉚타(v65 = seats.json)가 맡는다 |
| L6 opening 멈춤 | ㉛가 intent opening 20분 · 세션 0(rc1 can't find session) · owner 있음 → park 1 · UNKNOWN launch-failed 1 / ㉛나 opening 5분 → 손 0 / ㉛다 opening 20분인데 fill_open 에 있음 → 손 0 / ㉛라 opening 20분 · tmux 조회 실패(rc ≠ 1 또는 다른 글) → park 0 · 판정 불가 1줄 / M16(opening 분기 뺌) → ㉛가 FAIL |

## 상태
- 2026-11-16 · aifp-ft-arch-pi#16 초안(aifp 5346) · 대기 · L1~L5·L7 = DA 대행 APPROVE-DESIGN(5339) · L6 = DA 전
- 2026-11-16 · aifp-ft-arch-pi#17 마감(aifp 5388) · p3 덧 = DA#11 APPROVE-DESIGN(BYZ 309947) → L9·L10 확정 · 인수 칸(양성 3칸 · enroll 호출 확인) · 알려진 한계 1줄 · L6(§F opening)은 DA 판정 근거를 못 찾아 조건부 그대로
- 2026-11-16 · aifp-ft-arch-pi#17 근거 덧(aifp 5378 · harness 목록 A 의 «착지 끝 카드 다시 엶» 을 이 카드가 맡음 · 계약·시험 변경 0)
- 2026-11-16 · aifp-ft-arch-pi#16 p3 덧(aifp 5364 · planner 5363 v65 K4 a2 다시 띄움) · L9 나노 불가 표식 · DA 전
- 2026-11-16 · aifp-ft-arch-pi#17 L6 확정(aifp 5410 ①) · §F opening = DA#11 APPROVE-DESIGN(BYZ 310141) → 조건부 문구 지움 · tmux 조회 실패 = 판정 불가 칸 ㉛라 더함 · 한계 1줄 · Issue #8633
