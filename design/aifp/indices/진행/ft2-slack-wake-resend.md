# 인덱스: ft2-slack-wake-resend — 끝: Slack 글이 접수됐는데 좌석 깨움이 실패하면 수신기가 유휴 회차에 다시 보낸다 · 처음 넣어 3회까지 · 그래도 안 되면 harness 팀장에게 [긴급] 1통 · 이미 우편함에 들어간 글은 다시 보내지 않는다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8643 — 등록 planner#324 aifp 5406(팀장 aifp-ft-master-pi#18 발주 aifp 5395 ③ · 5382 행 G · 오빠 «네.» 접수 때 알림 깨움 실패 = desk BYZ 309706)
- 제안서: 없음 — 결함 복구(새 흐름 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-pG-slack-wake-fail-resend-20261116.md(r1 sha256 da9e4849…9194 · DA 대행 byz-harness-da-codex#11 APPROVE-DESIGN BYZ 310065 · 확정 동작 반례 0 · 전문 .fable-team/state/team-main/aifp-ft/DA-pG-r1-approve-310065.md) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 실측 2026-11-16(aifp-ft-arch-pi#17 · BYZ .fable-team/teams/planner/slack/wire.jsonl·listen.log 원문 · 읽기만) — wake 551줄 = rc 0 495 · rc 3 37 · rc -1 «상한 초과 · 적재 없음» 10 · «적재 있음» 5 · 사유 칸 없음 4 · listen.log «깨움 실패 TimeoutExpired» 19줄 · 마지막 깨움이 rc ≠ 0 으로 끝난 command 334개 중 22개 · 11-16 00:57:55·01:06:41 «[Slack] 새 업무» rc -1 적재 없음(받는 곳 byz-planner-desk-pi#176) · 00:34:42~00:42:43 rc 3 9줄(mbox 가드 거부 · 사유 미기록)
- 원인 1줄: wiring.wake 는 send 를 1회 부르고 실패하면 rc 줄 1개만 쓴다 · 다시 보내는 곳이 없다 · 재기동 복구 recovered 는 실패한 wake 줄도 «넘긴 글» 로 센다 · rc ≠ 0 의 send 출력을 버려 거부 사유가 남지 않는다 · landed 는 본문 첫 줄만 맞춰 앞 시도와 새 시도를 못 가른다
- 앞 카드: r1833(깨움 상한 25초 · landed) · r1938(유휴 회차 무변화 = 읽기·쓰기 0) · r1923·r1927(Slack 채널·봇 답) · r1807(팀 wiring)
- 상태: 대기
- 착지: e03072ec7dd16bb296a85ede524157f560b5e0a5(팩 main · PR #1292 squash · DA#11 APPROVE-IMPL aifp 5546 · 세트 c2f7b2a7 · 뺄 커밋 0)
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
- G12 재기동 복원 경계(회귀 고침 · 설계 pG2 r1) = `_restore` 가 후보로 넣는 command 는 G1 조건에 더해 그 마지막 비알림 깨움 줄이 (가) `seq0` 칸이 있고(G 판이 쓴 줄 · 값 null 도 칸 있음 = 참) (나) `0 ≤ 기동 시각 − 그 줄 at ≤ RESTORE_WINDOW(600초)` 를 모두 채운다 · at 못 읽음·기동 시각보다 뒤 = 창 밖 · 뺀 것이 1건 이상이면 listen.log 1줄 `[재전송] 복원 제외 <N>건 · 경계 칸 없음 <a> · 창 밖 <b>`(건별 줄 0 · wire 쓰기 0 · [긴급] 0 · 깨움 0)
- G13 재전송은 issues 입구에 쓰지 않는다(회귀 고침) = `_resend` 가 부르는 deliver 는 record_issue 를 부르지 않는다(처음 deliver 가 wake 앞에서 이미 불렀다) · 처음 깨움 길·recovered 길은 그대로

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
- 알려진 한계 4(pG2): RESTORE_WINDOW 600초는 계산 값(send 상한 25초 × 3 + 간격 60초 × 2 = 195초의 3배)이다 · 재기동이 걸리는 시간의 분포를 재지 않았다
- 알려진 한계 5(pG2): 수신기가 10분 넘게 죽어 있으면 그 앞 실패는 다시 보내지 않는다 · 처음 실패 때의 desk 알림 1통(G11)과 listen.log «복원 제외» 줄만 남는다
- 알려진 한계 6(pG2): 창 안에서 이미 응대한 command 는 가려내지 못한다 · 장부에 «응대 끝» 표식이 없다(실측 = 다시 나간 18 command 의 receive 최신 상태 settled 0)
- 2.0.66 재기동 때 생긴 것의 뒷정리(issues 입구 새 접수 15건 · 옛 좌석 이름으로 간 깨움 21통) = journal 쓰기는 HIL · 집행 = 팀장·planner
- 후속 후보(pG2 에 넣지 않음): 재전송이 mbox 가드 «5 sends/60s» 에 걸리면 그 통도 시도 1회로 센다 · 재전송의 받는 곳 = route 줄의 좌석 이름이라 승계 뒤에는 닫힌 좌석 우편함에 rc 0 으로 들어간다(recovered 도 같은 꼴)

## 완료 조건
1. [x] 나노: 커밋 1 기준판 FAIL 원문 — 기준판(c7860542 사본) `python3.11 -m pytest tests/test_slack_wake_resend.py -q` 12 failed · 8 passed 0.46초 · ㉞가 `assert '무변화' == '재전송 2/3'` · ㉞다 `assert 1 == 3` · ㉞아 `KeyError: 'out'` · ㉞차 `KeyError: '<command>'`(설계 지목 4칸 모두 FAIL · 나노 aifp 5534)
2. [x] 나노: 새 시험 전체 rc0 · 걸린 초 — 20 passed 0.31초(1a4db49e · aifp 5534) · HOLD 고침 뒤(c2f7b2a7) 23 passed 0.32초(㉞너·㉞더·㉞러 3칸 추가 · M34~M38 포함 · aifp 5538)
3. [x] 나노: 변이 M34 → ㉞가·㉞마 FAIL · M35 → ㉞다 FAIL · M36 → ㉞바 FAIL · M37 → ㉞사 FAIL · M38 → ㉞차 FAIL — 나노 원문(aifp 5534): M34 → ㉞가·㉞마 외 6칸 · M35 → ㉞다 외 6칸 · M36 → ㉞바 1칸 · M37 → ㉞사·㉞바 2칸 · M38 → ㉞차 1칸 FAIL · 원본 20 passed · DA aifp 5546 «M34~M38 포함» 재확인
4. [x] 나노: 회귀 rc0 — 고침 뒤 파일별(aifp 5538): test_slack_team_wiring_r1807 13 passed · test_core_e2e_wiring 4 passed · test_slack_listen_multi_channel_r1833 11 passed · test_keeper_notify_recipient 25 passed · 기준판과 같은 기존 FAIL 3건은 그대로(test_slack_settle_live_idle_r1938 1 failed·9 passed = 변이 M3 · test_slack_receive 2 failed·7 passed = t4 full·r1r2 · 기준판 c7860542 도 같은 사례 · 이 카드가 만든 것 아님 · DA aifp 5546 «기존 3FAIL 은 앞 기준판 대조 결과 유지»)
5. [x] arch: DA 인수 칸 4개 원문 확인 = 재기동 직후 60초 미만 send 0(㉞하) · 누적 3회 뒤 send 0(㉞거) · 알림 재귀 0(㉞자) · 빈 후보 유휴 회차 읽기·쓰기 0(㉞타) — aifp-ft-arch-pi#18(aifp 5535 = 1a4db49e 사본 20 passed · 착지 세트 c2f7b2a7 사본에서 다시 23 passed 0.56초 rc=0 · 네 사례 PASSED): ㉞하 test_ha_restart_waits_60s_from_last_attempt = 30초 시점 reason 무변화 + `bodies(run) == []` → 60초 시점 `재전송 2/3` + 1통 / ㉞거 test_geo_restart_after_three_failures_sends_nothing = `len(seat_wakes) == 3` → 재기동 뒤 `hub.candidates == {}` → 300초 뒤 `bodies(run) == []` / ㉞자 test_ja_alert_wake_failure_never_resent = `hub.candidates == {}` + `len(wakes(run)) == 1` / ㉞타 test_ta_empty_candidates_idle_reads_nothing = `reads == []` + jsonl 크기 앞뒤 같음 · 본 것: ㉞하·㉞거 의 send 0 은 planner master 앞 호출만 센다(내가 사본에 `wakes(run) == []` 를 더해 돌려 둘 다 통과 = 전체 호출 0) · ㉞타 쓰기 0 은 teams 밑 jsonl 크기만 본다 · DA 2회 = HOLD-IMPL BYZ 311009 → APPROVE-IMPL BYZ 311041
6. [x] 팀장: PR #1292 e03072ec · 설치 = ft2 2.0.66 rc 0(harness#291 · G+D+F 한 판 · 팀장 aifp 5584) · 수신기 com.byz.ft2-slack-listen 재기동 pid 49542 — arch 읽기 확인(2026-11-16 03:53): ~/.claude/fable-team/ft2/CURRENT = 2.0.66 · install-log 2026-11-15T18:47:51Z(03:47:51 KST) op install version 2.0.66 prev 2.0.65 rc 0 · launchctl list = 49542 com.byz.ft2-slack-listen · ps 시작 시각 03:48:01 · listen.log 03:48:02 «CHANNELS 있음 — --channel 무시»
7. [~] arch: 설치 뒤 planner wire.jsonl 읽기 실측 1줄(«rc ≠ 0 · 적재 없음» 뒤 같은 command rc 0 줄 · `out` 칸에 찍힌 rc 3 사유 원문) — aifp-ft-arch-pi#19(2026-11-16 04:02 · BYZ .fable-team/teams/planner/slack/wire.jsonl 읽기만): command slack:T0AC5HC4ENR:C0C9GRFHJE5:1794673169.726109 = 03:48:57 wake rc 3 · landed 없음 · seq0 311171 · out `→ BLOCKED RATE_LIMIT from=ft2-slack-listen 5 sends/60s · 정말 필요하면 --force` → 03:50:07 같은 command wake rc 0 · seq0 311181(70초 뒤 · 우편함 본문 끝줄 재전송 n/3) · 같은 꼴 2건 더(…1794756854.594659 03:50:48 → 03:51:56 · …1794538293.202419 03:52:35 → 03:53:57) · rc 3 사유 = 3건 모두 mbox 가드 RATE_LIMIT(범위 밖 «rc 3 가드 거부의 실제 사유» 의 첫 원문) · ★이 줄들은 회귀(상태 절 03:58 줄 · 옛 command 18건이 다시 나감)가 만든 것이다 = «실패 뒤 다시 보내 rc 0» 과 `out` 기록(G1·G2·G7)이 실 runtime 에서 돈 증거이지, 보낼 글을 맞게 골랐다는 증거가 아니다 · 고른 대상의 옳음은 조건 8~10 이 닫는다★ · 미룸(팀장 aifp 5609 ①): 이 증거는 보내면 안 될 옛 command 에서 나왔다 → 조건 10 뒤 실사건(맞게 고른 실패 깨움이 다시 나가 rc 0 이 되는 줄)으로 다시 재서 [x] 로 바꾼다
8. [ ] 나노(회귀 고침 pG2): 재기동 뒤 G 착지 앞 줄(`seq0` 칸 없음)·창 밖 줄의 command 재전송 0 — 기준판(54c7aa01) Red 원문 + ㉞머·㉞버·㉞서·㉞어 rc0 + 변이 M68 → ㉞머 FAIL · M69 → ㉞버·㉞서 FAIL
9. [ ] 나노(회귀 고침 pG2): 재전송은 issues 입구 기록 0 — ㉞저 rc0(재전송 때 issues submit·lookup 0 · 처음 deliver 의 record_issue 1회 그대로) + 변이 M70 → ㉞저 FAIL · 회귀 rc0(조건 4 의 파일 · 기존 FAIL 3건 그대로)
10. [ ] arch: pG2 설치·재기동 뒤 실측 1줄 — 재기동 직후 planner wire.jsonl 새 wake·issue 줄 0 · listen.log «복원 제외» 1줄 원문

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
| G12 재기동 복원 경계 | ㉞머 마지막 실패 줄에 `seq0` 칸 없음 · 5분 전 → 후보 0 · send 0 · 로그 «경계 칸 없음 1» / ㉞버 `seq0` 칸 있음 · 55시간 전 → 후보 0 · 로그 «창 밖 1» · 다시 재기동해도 0 / ㉞서 600초 전 = 후보 1 · 601초 전 = 후보 0 · at 못 읽음·기동 시각보다 뒤 = 후보 0 / ㉞어 앞 두 꼴 18건 섞임 → send 0 · wire 줄 증가 0 · issues submit 0 · 로그 1줄 / ㉞하(그대로) 30초 전 = 60초 뒤 send 1 / M68 · M69 |
| G13 재전송은 issues 기록 0 | ㉞저 새 업무 깨움 실패 → 60초 뒤 재전송 성공 → issue 줄 = 처음 1개 그대로 · 재전송 때 issues submit·lookup 0 / M70 |

## 상태
- base_sha: c786054260e7b8d0579665b03091048245817f3f (spawn 2026-11-16)
- 2026-11-16 · aifp-ft-arch-pi#17 씀(aifp 5395 ③) · 대기 · 설계 r1 = DA 대행 APPROVE-DESIGN(BYZ 310065) · 선행 = ft2-keeper-notify-recipient 착지
- 2026-11-16 03:04 — 대기→진행 · 좌석 aifp-ft-nano-ft2-slack-wake-resend#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 세트: 1a4db49e8c587b62d243dba6cab196b5c5743b44 · 시험: python3.11 -m pytest tests/test_slack_wake_resend.py -q (20 passed) rc=0 · 이슈: 0
- 완료: aifp-ft-nano-ft2-slack-wake-resend#0 · 한 일: ft2 Slack 깨움 재전송 구현 — 유휴 회차 1통·60초 간격·3회 상한·늦은 적재 확인·seq 경계 적재 판독·3회 실패 [긴급] 1통·재기동 시도 수 잇기 + 새 시험 20칸/변이 5 · 산출: nano/ft2-slack-wake-resend@1a4db49e8c · 병합 상태: 착지 전(push 전) · 남은 일: 없음
- 고침: DA HOLD-IMPL(BYZ 311009) 반례 3건 = 재기동 뒤 상한 넘김 · 성공 뒤 중복 발신 · 셋째 적재 있음인데 거짓 [긴급] → 커밋 9df40241(시험 3칸 ㉞너·㉞더·㉞러) · c2f7b2a7(adapters/slack/wiring.py · aifp 5538)
- DA 판정: HOLD-IMPL 311009(반례 3) → APPROVE-IMPL 311041(aifp 5546) · 알려진 한계 = 변이 번호 M34 가 keeper-settle CASES M34 와 겹침(문서 범위 다름)
- 세트: c2f7b2a706c63427567a64bcfb6860772b2bf990 · 시험: python3.11 -m pytest tests/test_slack_wake_resend.py -q (23 passed · 0.32초) rc=0 · 이슈: 0
- 2026-11-16 03:58 · aifp-ft-arch-pi#19 회귀 기록(팀장 aifp 5586 · planner 5582 · BYZ desk #311199): ft2 2.0.66 설치 03:47:51 · 수신기 재기동 03:48:01 뒤 `_restore` 가 wire.jsonl 전체에서 G 착지 앞 실패 줄(11-13 12:24 ~ 11-16 01:06 · `seq0`·`landed` 칸 없음) 18 command 를 후보로 넣음 → 03:48:05 ~ 03:54:26 wire 36줄 = wake rc 0 18 · rc 3 적재 없음 3(out = BLOCKED RATE_LIMIT 5 sends/60s) · issue «접수 성공» 15 · 원인 = G10 에 복원 경계 없음(설계 빈칸) + 재전송 deliver 가 record_issue 를 부름
- 2026-11-16 03:58 · 회귀 고칠 안 = 설계 .fable-team/state/team-main/aifp-ft/orders/DESIGN-pG2-slack-wake-restore-boundary-20261116.md(r1 sha256 a1d738af…38f7 · 안 1개 = G12 `seq0` 칸 + 600초 창 · G13 재전송 record_issue 0 · 버린 길 6 · 반례 표 12행 · 시험 ㉞머·㉞버·㉞서·㉞어·㉞저 · 변이 M68·M69·M70 · DA 전) · 계약 G12·G13 · 완료 조건 8~10 · 대응표 2행 · 알려진 한계 4~6 더함 · 코드 0
