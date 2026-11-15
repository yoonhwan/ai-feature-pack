# 인덱스: ft2-slack-wake-resend — 끝: Slack 글이 접수됐는데 좌석 깨움이 실패하면 수신기가 유휴 회차에 다시 보낸다 · 처음 넣어 3회까지 · 그래도 안 되면 harness 팀장에게 [긴급] 1통 · 이미 우편함에 들어간 글은 다시 보내지 않는다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8643 — 등록 planner#324 aifp 5406(팀장 aifp-ft-master-pi#18 발주 aifp 5395 ③ · 5382 행 G · 오빠 «네.» 접수 때 알림 깨움 실패 = desk BYZ 309706)
- 제안서: 없음 — 결함 복구(새 흐름 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-pG-slack-wake-fail-resend-20261116.md(r1 sha256 da9e4849…9194 · DA 대행 byz-harness-da-codex#11 APPROVE-DESIGN BYZ 310065 · 확정 동작 반례 0 · 전문 .fable-team/state/team-main/aifp-ft/DA-pG-r1-approve-310065.md) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 실측 2026-11-16(aifp-ft-arch-pi#17 · BYZ .fable-team/teams/planner/slack/wire.jsonl·listen.log 원문 · 읽기만) — wake 551줄 = rc 0 495 · rc 3 37 · rc -1 «상한 초과 · 적재 없음» 10 · «적재 있음» 5 · 사유 칸 없음 4 · listen.log «깨움 실패 TimeoutExpired» 19줄 · 마지막 깨움이 rc ≠ 0 으로 끝난 command 334개 중 22개 · 11-16 00:57:55·01:06:41 «[Slack] 새 업무» rc -1 적재 없음(받는 곳 byz-planner-desk-pi#176) · 00:34:42~00:42:43 rc 3 9줄(mbox 가드 거부 · 사유 미기록)
- 원인 1줄: wiring.wake 는 send 를 1회 부르고 실패하면 rc 줄 1개만 쓴다 · 다시 보내는 곳이 없다 · 재기동 복구 recovered 는 실패한 wake 줄도 «넘긴 글» 로 센다 · rc ≠ 0 의 send 출력을 버려 거부 사유가 남지 않는다 · landed 는 본문 첫 줄만 맞춰 앞 시도와 새 시도를 못 가른다
- 앞 카드: r1833(깨움 상한 25초 · landed) · r1938(유휴 회차 무변화 = 읽기·쓰기 0) · r1923·r1927(Slack 채널·봇 답) · r1807(팀 wiring)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 + Slack 수신기 재기동 1회(집행 = planner) · 되돌림 = 앞 판으로 판 전환 + 재기동
- 선행: 없음 — E ft2-keeper-notify-recipient 착지 ae0c199e(PR #1282) 착지 끝 · 팀장 aifp-ft-master-pi#19 이 풂
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 wire.jsonl·route 장부·우편함 장부·명부 · 가짜 mbox(rc·출력·걸린 시간·장부에 붙일 줄을 사례가 정함) · 가짜 clock · sleep 0 · 네트워크 0 · Slack 호출 0 · 실 runtime 쓰기·읽기 0 · 사례 1개 70초 안
- 기준값: 기준판 = 깨움 실패 뒤 재전송 0 · 재기동해도 깨움 0 · rc 3 사유 기록 0 → 목표 = 적재 안 된 비알림 깨움은 60초 뒤 유휴 회차에 1통씩 · 누적 3회 · 그 뒤 [긴급] 1통 · 실패 줄에 send 출력
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 12(로컬 하네스 25초 · 늘리지 않음) · 하드 룰 20 · 하드 룰 22 · no_silent_fallback(적재 판정 불가도 1줄)
- 대상: 팩 feature-pack/fable-team/ft2/adapters/slack/wiring.py(wake·landed·recovered·재전송 후보) · feature-pack/fable-team/ft2/adapters/slack/receive.py(pass_idle 에서 재전송 1통 부름) · 새 시험 feature-pack/fable-team/ft2/tests/test_slack_wake_resend.py · 문서 = Slack 수신 계약 문서의 유휴 회차 줄(자리는 나노가 ci 로 찾아 PR 본문에 적는다)
- 정본 영향 있음: 유휴 회차 약속 «모델 호출·좌석 깨움·기록 증가 0» → «재전송 후보가 있을 때만 깨움 1통·wire 줄 1개» = 같은 PR(나노)
- 크기: 코드 2파일 · 새 시험 1파일 · 문서 1파일 · PR 1개
- 배정: 좌석 aifp-ft-nano-ft2-slack-wake-resend#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — 접수된 Slack 글이 좌석에 닿지 못한 채 조용히 남지 않는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 planner wire.jsonl 의 «rc ≠ 0 · 적재 없음» 줄 뒤 같은 command 의 rc 0 줄.

## 배경 (한 단락)
Slack 수신기는 글을 접수하면 thread 에 묶인 좌석을 쪽지로 깨운다. 깨움은 mbox send 1회이고 상한은 25초다. 좌석이 막혀 send 가 잘리거나 거부되면 수신기는 wire 장부에 실패 줄 하나를 쓰고 끝낸다. 글은 journal 에 접수됐지만 좌석은 모른다. 뒤따르는 «깨움 실패» 알림도 같은 길로 같은 좌석에 가서 같이 실패한다. 수신기를 재기동해도 실패한 깨움 줄을 «이미 넘긴 글» 로 세어 다시 깨우지 않는다. 11-16 새벽 오빠의 «네.» 가 이 길에서 닿지 않았다.

## 계약
- G1 다시 보낼 글 = 그 command 의 «알림이 아닌» wake 줄 중 마지막 줄이 rc ≠ 0 이고 적재가 «있음» 이 아닌 것 · `[Slack] 알림 …` wake 는 후보가 아니다(알림 재귀 0)
- G2 언제 = 유휴 회차(receive.pass_idle) · 한 유휴 회차에 1통 · 같은 command 는 앞 시도에서 60초 뒤에만
- G3 몇 번 = 처음 시도를 넣어 3회 · 3회째도 실패면 멈춤(4회째 0)
- G4 본문 = recovered 와 같은 길(route 장부의 그 command dispatched 행 + router.context → deliver) · 첫 줄 그대로 · 끝에 `재전송 <n>/3` 1줄
- G5 늦은 적재 확인 = 다시 보내기 전에 앞 시도의 경계(seq0) 뒤에 그 글이 장부에 있으면 send 0 · wake 줄 `rc 0 · why 늦은 적재 확인` 1줄 · 후보에서 뺌
- G6 적재 판독 = ft2-keeper-notify-recipient E7 과 같은 규칙·같은 함수 · send 바로 전 장부 끝 200줄의 최대 seq 를 wake 줄 `seq0` 에 적음 · seq 가 경계보다 큰 줄 중 «받는 곳 · 본문 첫 줄» 일치 · 시각 비교 0 · 경계 못 잡음 = `적재 판정 불가`(재전송 대상)
- G7 실패 사유 = rc ≠ 0 이면 send 출력(stdout + stderr) 마지막 줄 앞 160자를 wake 줄 `out` 칸에 · 시간 초과면 그때까지 잡힌 출력
- G8 3회 실패 뒤 = `[긴급] Slack 글 깨움 3회 실패 · thread <ts> · command <command> · 받는 곳 <좌석> · 마지막 rc <값> <out>` 을 harness _master 에게 1통 · command 마다 1회(wire alert 줄 `why 깨움 3회 실패` 로 dedup) · 명부는 ft2-keeper-notify-recipient E8 함수 · 이 1통도 실패면 listen.log 1줄(재시도 0)
- G9 recovered = «알림이 아닌 wake 줄 중 rc 0 이거나 적재 있음인 줄이 있으면 깨움 0» · 재기동해도 G1~G3 셈을 잇는다(시도 수 = wire 장부의 그 command 비알림 wake 줄 수 · 마지막 시도 시각 = 그 줄의 at) · 재기동을 간격·횟수 초기화로 구현하면 불합격(DA BYZ 310065)
- G10 기억 = 후보는 수신기 메모리 표 1개(wake 실패 때 넣고 성공·멈춤 때 뺌) · 재기동 때 wire 장부 1회 읽어 채움 · 후보 표가 비면 유휴 회차는 지금과 같다(wire·settle 읽기 0 · 쓰기 0 · send 0)
- G11 그대로: 처음 실패 때의 `[Slack] 알림 깨움 실패` 1통(재전송 실패 때는 0) · 상한 25초 · route·binding·settle 판정 · 두 좌석 동시 전송 0

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · ft2-keeper-notify-recipient 착지 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_slack_wake_resend.py(㉞가~파 13칸 + 인수 칸 ㉞하·㉞거 · M34~M38) · 기준판 FAIL 원문(㉞가·㉞다·㉞아·㉞차)을 PR 본문에 붙인다
2. 커밋 2 [fix] — G1·G3~G10 = feature-pack/fable-team/ft2/adapters/slack/wiring.py · G2 = feature-pack/fable-team/ft2/adapters/slack/receive.py(pass_idle 에 호출 1줄 · r1938 stat 서명 건너뜀은 그대로) · 다른 함수 손 0
3. G6·G8 은 앞 카드가 넣은 공용 함수(seq 경계 판독 · 명부 찾기)를 부른다 · wiring.py 안에 같은 판독을 따로 만들지 않는다 · 함수 이름은 앞 카드 PR 본문 1줄을 따른다
4. 커밋 3 [docs] — 유휴 회차 약속 문장 고침 · 설계 1쪽을 feature-pack/fable-team/design/ 로
5. 회귀 rc0: test_slack_team_wiring_r1807.py · test_core_e2e_wiring.py · test_slack_settle_live_idle_r1938.py · test_slack_listen_multi_channel_r1833.py
6. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- mbox send 가 25초를 넘는 단계 · rc 3 가드 거부의 실제 사유(G7 `out` 기록이 쌓인 뒤 따로 본다 · 확인 필요)
- 이미 실패로 끝난 옛 command 22개를 손으로 다시 깨우는 일(planner desk)
- 수신기 재기동 집행 · 설치 집행
- 알려진 한계 1(DA BYZ 310065 수용): 장부 200줄 창 밖 · 적재 판정 불가일 때 다시 보내므로 같은 글이 2통 될 수 있다 · 끝줄 `재전송 <n>/3` 과 command 로 desk 가 가른다
- 알려진 한계 2: 늦은 적재 확인 직후에 앞 시도의 자식 프로세스가 적재하는 경합은 막지 못한다(exactly-once 보증 아님)
- 알려진 한계 3: 재전송 1통은 Slack 소켓 읽기를 25초까지 막는다(처음 깨움과 같은 값)

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M34 → ㉞가·㉞마 FAIL · M35 → ㉞다 FAIL · M36 → ㉞바 FAIL · M37 → ㉞사 FAIL · M38 → ㉞차 FAIL
4. [ ] 나노: 회귀 rc0
5. [ ] arch: DA 인수 칸 4개 원문 확인 = 재기동 직후 60초 미만 send 0(㉞하) · 누적 3회 뒤 send 0(㉞거) · 알림 재귀 0(㉞자) · 빈 후보 유휴 회차 읽기·쓰기 0(㉞타)
6. [ ] 팀장: PR 착지 sha · 설치 판 · 수신기 재기동 시각(planner 집행 회신)
7. [ ] arch: 설치 뒤 planner wire.jsonl 읽기 실측 1줄(«rc ≠ 0 · 적재 없음» 뒤 같은 command rc 0 줄 · `out` 칸에 찍힌 rc 3 사유 원문)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| G1·G2 유휴 회차 재전송 | ㉞가 새 업무 wake 시간 초과 · 적재 없음 → 60초 뒤 유휴 회차 send rc 0 → 재전송 1통(끝줄 재전송 2/3) · wake 줄 2개 · 그 뒤 0 / ㉞라 실패 뒤 30초 → 0 / ㉞마 후보 2개 · 유휴 회차 1번 → send 1 · 다음 회차 1 / M34 |
| G1 적재 있음·알림은 후보 아님 | ㉞나 시간 초과 · 적재 있음 → 재전송 0 / ㉞자 `[Slack] 알림 용량 부족` wake 실패 → 재전송 0 |
| G3·G8 3회 뒤 [긴급] | ㉞다 3회 연속 실패 → send 3 · harness _master [긴급] 1통 · 4회째 0 · 둘째 [긴급] 0 / M35 |
| G5 늦은 적재 확인 | ㉞바 다시 보내기 전에 경계보다 큰 seq 로 그 글이 붙음 → send 0 · wake 줄 rc 0 늦은 적재 확인 / M36 |
| G6 seq 경계 | ㉞사 같은 초 이전 글(seq 100) · 경계 100 · 새 줄 0 → 적재 없음 · 재전송 대상 / ㉞파 장부 못 읽음 → 적재 판정 불가 · 재전송 대상 / M37 |
| G7 실패 출력 | ㉞아 send rc 3 · 출력 REJECT 사유 … → wake 줄 out 칸 · 재전송 대상 |
| G9 재기동 | ㉞차 wire 에 비알림 wake 1줄(rc -1 적재 없음) → recovered 깨움 1회 · 시도 수 2 / ㉞카 rc 0 줄 → 깨움 0 / ㉞하 마지막 실패 줄 at 이 30초 전인 채 재기동 → 그 유휴 회차 send 0 · 60초 지난 회차 send 1 / ㉞거 wire 에 비알림 실패 줄 3개인 채 재기동 → send 0 / M38 |
| G10 빈 후보 유휴 | ㉞타 후보 표 빔 · settle 서명 그대로 → wire·settle 읽기 0 · 쓰기 0 · send 0 |

## 상태
- base_sha: c786054260e7b8d0579665b03091048245817f3f (spawn 2026-11-16)
- 2026-11-16 · aifp-ft-arch-pi#17 씀(aifp 5395 ③) · 대기 · 설계 r1 = DA 대행 APPROVE-DESIGN(BYZ 310065) · 선행 = ft2-keeper-notify-recipient 착지
- 2026-11-16 03:04 — 대기→진행 · 좌석 aifp-ft-nano-ft2-slack-wake-resend#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
