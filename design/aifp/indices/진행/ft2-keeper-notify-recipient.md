# 인덱스: ft2-keeper-notify-recipient — 끝: keeper 쪽지가 팀장 없는 팀에서도 받는 곳 한 곳에 닿는다 · 보내기 실패는 그날 1회만 찍고 다시 시도하지 않는다 · 7초를 넘겨도 우편함에 들어갔으면 성공으로 세어 같은 글이 2통 가지 않는다 · 한 바퀴에 3통까지만 보낸다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8640 — 등록 planner#324 aifp 5402(팀장 aifp-ft-master-pi#18 발주 aifp 5395 ① · 5368 · 5359 · 5347 · 5326 행 E · 오빠 Slack 11-16 00:42 «페이블이 해결 · 끝까지 책임»)
- 제안서: 없음 — 결함 복구(새 흐름 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-pE-keeper-notify-no-recipient-20261116.md(r3 sha256 28bde8c6…c778 · DA 대행 byz-harness-da-codex#11 APPROVE-DESIGN BYZ 310019 · 전문 .fable-team/state/team-main/aifp-ft/DA-pE-r3-approve-310019.md · 앞 판 r2 REJECT 1/3 = 초 단위 시각 비교 반례 → seq 경계로 닫힘) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 실측 2026-11-16(aifp-ft-arch-pi#16·#17 · BYZ .fable-team/state/ft2-keeper/20261116.jsonl 원문 · 읽기만) — 00:00~01:1x «판정 불가 <팀> 쪽지 _master 없음» 1384줄(v65 360 · chatbot 270 · room 220 · knowledge 172 · kk 90 · cfo 88 · ops 86 · issues 53 · feature 45) · send rc 3 53줄 · 01:07 바퀴 chatbot stall 43.7초 중 mbox send 41.3초(6회 · rc None 4회) → ROUND 112.8초 · 같은 글 2통 = BYZ 장부 309818(ts 01:10:16)·309820(ts 01:10:23) 둘 다 from ft2-keeper · to byz-feature-master-pi#75 · 본문 [다음 없음] feature … · v65 명부는 seats.json 인데 seats-v65.json 만 찾아 «_master 없음» 360줄 · BYZ 장부 6374줄 중 seq 가 거꾸로 간 곳 0
- 원인 1줄: keeper_report.notify 가 그 팀 seats-<팀>.json 의 _master 한 곳만 본다 · 실패하면 지문을 쓰지 않아 바퀴마다 다시 시도하고 같은 줄을 찍는다 · 7초를 넘긴 send 를 실패로 보고 재시도 1 이 같은 글을 한 번 더 적재한다 · 바퀴 안 통 수에 상한이 없다
- 앞 카드: r2055(팩 d88ef381 · settle 한 길 · alert 지문) · r1812(keeper 보고) · r1886(꽉 참 알림) · r1833(Slack 깨움 적재 판독 landed)
- 상태: 대기
- 착지: ae0c199eafa2b061034a2169d673bb3bb8cceff6(팩 main · PR #1282 squash · DA#11 APPROVE-IMPL aifp 5510 · 세트 8ba57455 · 뺄 커밋 0)
- 설치: 있음 — ft2 판 올림 1회(팩 착지 뒤 팀장·harness 설치 묶음) · 되돌림 = 앞 판으로 판 전환
- 선행: 없음 — ft2-slack-accept-capacity 착지 끝(팩 main 09c02c0a · PR #1270 · 팀장 aifp-ft-master-pi#18 이 풂)
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 명부·우편함 장부(mailbox.log.jsonl)·keeper 상태 · 가짜 mbox(rc·걸린 시간·장부에 붙일 줄을 사례가 정함) · 가짜 clock · sleep 0 · 네트워크 0 · 실 runtime 쓰기·읽기 0 · 사례 1개 70초 안
- 기준값: 기준판 = _master 빈칸이면 바퀴마다 판정 불가 1줄 · 7초 초과 뒤 재시도로 같은 글 2통 · 6통이 한 바퀴에 → 목표 = 대신 받는 곳에 팀당 하루 1통 묶음 · 실패 줄 그날 1줄 · 같은 글 1통 · 바퀴 3통
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 12(7초 · 이 카드에서 재시도 1 → 0) · 하드 룰 20 · 하드 룰 22 · no_silent_fallback(받는 곳 없음·도착 판독 불가도 1줄)
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper_report.py(notify 받는 곳 차례·지문·도착 확인·바퀴 상한) · feature-pack/fable-team/ft2/adapters/pi/keeper_settle.py(alert 지문) · feature-pack/fable-team/ft2/adapters/pi/launch_roster.py(명부 찾기 한 함수) · 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_notify_recipient.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md·CASES.md
- 정본 영향 없음: aifp 정본(docs/architect · docs/rules · design 팀 GUIDE·README) 변경 0 — 바뀐 것은 팩 ft2 계약 문서(contracts/keeper-settle/CONTRACT.md · CASES.md)뿐이고 착지 PR #1282(ae0c199e)에 같이 들어갔다 · 원래 줄 «정본 영향 있음: CONTRACT.md «전송 실패 = 지문 미소비» 문장 → «실패도 그날 지문» · 쪽지 받는 곳 차례·도착 확인·바퀴 3통 절 1개 · CASES.md ㉚·변이 행 = 같은 PR(나노)»
- 크기: 코드 3파일 · 새 시험 1파일 · 회귀 기대 고침 1파일 · 문서 2파일 · PR 1개
- 배정: 좌석 aifp-ft-nano-ft2-keeper-notify-recipient#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — keeper 가 낸 판정이 사람에게 한 번 닿고 같은 줄을 되풀이하지 않는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 1시간 keeper 로그의 «판정 불가 … 쪽지» 줄 수 + 같은 1시간 ROUND 줄의 쪽지 stall.

## 배경 (한 단락)
keeper 는 판정을 팀장에게 쪽지로 알린다. 받는 곳을 그 팀 명부의 _master 한 칸에서만 찾는다. 11-16 새벽에 8팀의 _master 가 빈칸이었고 v65 는 명부 파일 이름이 달라 팀장이 있어도 못 찾았다. 보내기에 실패하면 지문을 남기지 않아 다음 바퀴에 또 시도했고, 55분 동안 같은 줄이 1384번 찍혔다. 팀장이 막 열린 chatbot 에는 밀린 [긴급] 여섯 통이 한 바퀴에 몰려 바퀴가 112.8초로 늘었다. mbox send 는 우편함 적재를 끝낸 뒤 도어벨 단계에서 시간이 걸리므로, 7초에 잘려도 쪽지는 이미 들어가 있다. 그 상태에서 재시도가 같은 글을 한 번 더 넣었다.

## 계약
- E1 받는 곳 차례 = 그 팀 _master → 그 팀 _desk → harness _master · 처음으로 값이 있는 한 곳에만 보낸다(두 곳 동시 0) · 명부 파일이 없거나 못 읽어도 다음 칸으로 간다
- E2 대신 받는 곳(_desk·harness _master)에는 글마다 보내지 않는다 · 팀당 하루 1통 묶음 `[긴급] <팀> 팀장 없음 · 못 전한 keeper 판정 <n>건 · 앞 3건: …` · 그날 뒤에 생긴 판정은 state["undelivered"][<팀>] 에만 쌓고 다음 날 묶음에 넣는다
- E3 실패 지문 = 실패도 지문을 쓴다 · 열쇠 = 지금 sent 열쇠 그대로 · 값 `fail|<날짜>|<rc>` · 같은 열쇠는 그날 다시 시도하지 않고 `판정 불가` 줄도 그날 1회 · 날짜가 바뀌면 1회 다시 시도
- E4 keeper_settle.alert 는 notify 가 «그날 실패 지문 있음» 을 돌려주면 alerts 지문도 그날 값으로 쓴다(재시도 0)
- E5 보내기 상한 = 통마다 7초 · 재시도 0 · 한 바퀴 3통 · 넘는 것은 지문을 쓰지 않고 다음 바퀴(`NOTIFY-DEFER <팀> <n>통 · 다음 바퀴` 1줄 · 값이 바뀔 때만)
- E6 받는 곳이 끝내 없음(세 칸 모두 빈칸) = `판정 불가 <팀> 쪽지 받는 곳 없음` 그날 1줄 · E3 과 같은 실패 지문
- E7 도착 확인 = send 가 rc ≠ 0 또는 7초 초과(rc None)면 우편함 장부(comm/mailbox.log.jsonl 끝 200줄 · 읽기만)에서 seq 가 경계보다 큰 줄 중 «보낸 이 ft2-keeper · 받는 곳 · 본문 첫 줄» 이 같은 줄을 찾는다 · 있으면 성공 지문 + `NOTIFIED <받는 곳> (도착 확인 · rc <값>)` · 없으면 E3 · 시각(ts)은 비교에 쓰지 않는다
- E7-1 경계 = send 를 부르기 바로 전에 읽은 장부 끝 200줄의 정수 seq 최댓값 · seq 없는 줄은 건너뜀 · 통마다 따로 잡는다(바퀴 시작에 한 번 잡지 않는다)
- E7-2 경계를 못 잡음(장부 없음·못 읽음·seq 줄 0) = send 는 한다 · rc 0 이면 성공 · 아니면 실패 지문 + `판정 불가 … 도착 판독 불가` 1줄
- E7-3 창 밖 = send 뒤 읽은 200줄의 가장 작은 seq 가 경계+1 보다 크고 맞는 줄 0 → «없음» 이 아니라 `도착 판독 불가`(실패 지문은 같음)
- E7-4 rc 0 인 send 는 뒤 장부 읽기 0(경계 읽기 1회만)
- E8 명부 찾기 = 한 함수(launch_roster.py): seats-<팀>.json 이 있으면 그 파일 · 없고 팀이 v65 면 seats.json · 그 밖 = 명부 없음(E1 다음 칸) · notify 의 팀 명부·harness 명부 읽기가 이 함수를 부른다
- E9 그대로: full_alert 의 받는 곳(팀 + harness 두 곳) · rc 0 길의 NOTIFIED 줄·지문 · 쪽지 본문 꼴

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · ft2-slack-accept-capacity 착지 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_notify_recipient.py(㉚가~거 15칸 · M17·M18·M19·M23·M24·M25·M32·M33) · 기준판 FAIL 원문(㉚가·㉚라·㉚사·㉚자·㉚타·㉚하)을 PR 본문에 붙인다
2. 커밋 2 [fix] — E1~E3·E5~E7 = feature-pack/fable-team/ft2/adapters/pi/keeper_report.py · E4 = feature-pack/fable-team/ft2/adapters/pi/keeper_settle.py(alert 만) · E8 = feature-pack/fable-team/ft2/adapters/pi/launch_roster.py · 다른 함수 손 0
3. 커밋 2 에 같이 — feature-pack/fable-team/ft2/tests/test_settle_one_path_r2055.py 의 «실패 = 지문 미소비» 기대 사례를 «실패도 그날 지문» 으로 고친다(삭제 0 · PR 본문에 사례 이름)
4. 커밋 3 [docs] — feature-pack/fable-team/ft2/contracts/keeper-settle/CONTRACT.md 쪽지 절·CASES.md ㉚·변이 행 · 운영 1줄(팀장을 다시 세운 날 바로 받게 하려면 state["sent"] 의 그 팀 fail| 값을 사람이 지운다) · 설계 1쪽을 feature-pack/fable-team/design/ 로
5. 회귀 rc0: test_settle_one_path_r2055.py · r1812 keeper 보고 시험 · r1886 꽉 참 알림 시험
6. E8 함수는 다른 카드(ft2-launch-failed-end L10 · Slack 깨움 재전송 카드)가 부른다 · 함수 이름·인자·반환을 PR 본문에 1줄로 적는다
7. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- 명부를 한 꼴로만 찾는 나머지 자리(core/execution.py · tools/goal_close.py · adapters/pi/full_alert.py · adapters/pi/launch_plan.py · adapters/slack/channels.py · adapters/slack/wiring.py · 1.x ft-team-tidy) = 후속 1장
- mbox send 의 어느 단계가 5~8초인지(확인 필요 · mbox 쪽 계측)
- 팀장 없는 팀에 팀장을 세우는 일(planner 집행) · 설치 집행
- 알려진 한계 1(DA BYZ 310019 승인 범위): 7초 안에 장부가 200줄 넘게 늘어 창이 경계를 지나면 도착했어도 `도착 판독 불가` 로 남는다
- 알려진 한계 2(DA BYZ 310019 승인 범위): 한계 1 의 글은 실패 지문이라 다음 날 1회 다시 간다 = 같은 글이 2통 될 수 있다 · 장부 seq 가 늘 커진다는 것은 전제이고 실행 보증이 아니다 · 이 카드는 live 중복 해소를 증거로 주장하지 않는다

## 완료 조건
1. [x] 나노: 커밋 1 기준판 FAIL 원문 — 79ff6fb6(시험만) 에 기준판 코드로 돌린 원문: ㉚가 `[]`(쪽지 0) · ㉚라 `['판정 불가 harness 쪽지 3 — …']`(시도 2) · ㉚사 6통이 다 나감(상한 0) · ㉚자 `['판정 불가 harness 쪽지 None — …']`(7초 초과를 실패로 봄 · NOTIFIED 0) · ㉚타 `[]`(v65 명부 못 찾음) · ㉚하 같음 · 22 failed 1 passed(㉚아 = 지금과 같은 rc 0 길 = 양성 대조)
2. [x] 나노: 새 시험 전체 rc0 · 걸린 초 — `python3.11 -m pytest ft2/tests/test_keeper_notify_recipient.py` 23 passed · 17.1초 · 고침 뒤(8ba57455) 25 passed 24.21초 rc=0(사례 16 + 변이 9 · ㉚더·M34 포함 · aifp 5505)
3. [x] 나노: 변이 8개 — `test_mutant[...]` 8칸 rc0(변이 사본에서 그 사례가 FAIL · 원본에서 PASS): M17 → ㉚가·㉚나·㉚다 · M18 → ㉚라·㉚마·㉚바 · M19 → ㉚사 · M23 → ㉚자·㉚차 · M24 → ㉚타 · M25 → ㉚자·㉚마 · M32 → ㉚파 · M33 → ㉚하 · 고침 뒤 M34(열쇠를 seats[0] 로) → ㉚더 = 9개(aifp 5505 · DA aifp 5510 «M34 old-key 변이 검출»)
4. [x] 나노: 회귀 rc0 · 고친 기대값 사례 이름 — `test_settle_one_path_r2055.py` 29 passed 43.0초(⑤ «전송 실패 뒤 = 다시 전송» → «실패도 그날 지문») · `test_pi_keeper_r1812.py` 31 passed 78.3초 · `test_pi_keeper_followup_r2000.py` 26 passed 41.5초(숫자 정정 aifp 5484) ⑧′ «쪽지 실패 → 다음 바퀴 다시» 를 «실패도 그날 지문» 으로(카드 밖 두 번째 기대 고침 파일 · r2000 소유) · `test_full_critical_alert_r1886.py` 4 passed 1 failed = c7 journal 꽉 참인데 기준판(0de903a2)에서도 같은 FAIL(무관 · master 재판정)
5. [x] arch: ㉚파·㉚하·㉚거 와 M32·M33 을 따로 다시 돌려 확인(DA BYZ 310019 인수 칸) — aifp-ft-arch-pi#18 재실행(세트 8ba57455 의 git archive 사본 · `python3.11 -m pytest ft2/tests/test_keeper_notify_recipient.py -v`): 25 passed 24.76초 rc=0 · test_case[㉚파]·[㉚하]·[㉚거] PASSED · test_mutant[M32]·[M33] PASSED(M32 = seq 경계를 ts >= 로 → ㉚파 · M33 = ts > 로 → ㉚하) · DA 두 번 확인 원문 = BYZ 310738 «요청한 ㉚파·㉚하·㉚거와 M32/M33 포함» · BYZ 310812 «기존㉚파/하/거 및 M32/M33도 함께통과»
6. [x] 팀장: PR #1282 ae0c199e · 설치 2.0.65 rc0 POSTCHECK OK Traceback 0(harness#290 aifp 5521 · install-log 2026-11-15T18:07:51Z = KST 11-16 03:07:51)
7. [x] arch: 설치 뒤 1시간 keeper 로그 실측 1줄(«판정 불가 … 쪽지» 줄 수 · 쪽지 stall 21초 넘는 바퀴 수) — aifp-ft-arch-pi#19(2026-11-16 04:12 · BYZ .fable-team/state/ft2-keeper/20261116.jsonl 읽기만 · 줄 꼴 `판정 불가 <팀> 쪽지 …` · stall = ROUND 줄의 `stall=` 칸) · 창 = 40분씩(팀장 aifp 5609 ② · 03:47:51 에 ft2 2.0.66 이 설치돼 2.0.65 만 돈 구간이 40분이다 · 카드 원문 «1시간» 과 다른 곳)
   - 기준 창 02:27:51~03:07:51 KST(40분 · 491줄): «판정 불가 … 쪽지» 115줄 = kk 56 · v65 56(둘 다 «_master 없음» · 바퀴마다 [긴급] 1 + [다음 없음] 1) · harness 2 · planner 1(send rc 3) · ROUND 29줄 중 stall 21초 넘음 0(최대 6.3초)
   - 설치 뒤 창 03:07:51~03:47:51 KST(40분 · 410줄 · 설치 ft2 2.0.65 install-log 2026-11-15T18:07:51Z): «판정 불가 … 쪽지» 4줄 = kk 2 · v65 2(03:08:03 · 03:08:06 «_master 없음») · ROUND 29줄 중 stall 21초 넘음 0(최대 5.1초)
   - 비교: 115줄 → 4줄 · «_master 없음» 112줄 → 4줄이고 그 4줄은 03:08:07 에 끝난 바퀴(s=16.6 = 03:07:50 시작 · 설치 기록 1초 앞)에만 있다 · 다음 바퀴(03:09:25~03:09:31)부터 `NOTIFIED v65 byz-v65-master-pi#294 …` 2통 · `NOTIFIED kk byz-harness-master-pi#290 [긴급] kk 팀장 없음 · 못 전한 keeper 판정 2건 …` 1통(대신 받는 곳 묶음)으로 바뀌고 «_master 없음» 줄 0 = 설계 수용 기준 «둘째 바퀴부터 0» 과 맞다 · stall 21초 넘는 바퀴는 두 창 모두 0 이라 이 칸은 앞뒤 차이로 보이지 않는다(기준 창에 01:07 같은 몰림이 없었다) [확인 필요: 03:08:07 바퀴가 어느 판으로 돌았는지 — 줄에 판 표식 없음 · 시작 시각으로만 봄]
   - 03:47:51 뒤(따로 · 견줌에 넣지 않음): ft2 2.0.66(G + D+F 한 판 · 이 카드 코드 포함) 20분 03:47:51~04:07:51 = «판정 불가 … 쪽지» 1줄(harness 04:03:59 «쪽지 None» = send 7초 초과) · ROUND 12줄 중 stall 21초 넘음 0(최대 10.4초)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| E1·E2 받는 곳 차례·묶음 | ㉚가 _master·_desk 빈칸 · harness _master 있음 · [긴급] 3건 → harness 팀장에게 묶음 1통 · 둘째 바퀴 0통 · 판정 불가 0줄 / ㉚나 명부 파일 없음 → 같음 / ㉚다 _desk 있음 → desk 1통 · harness 0통 / M17 |
| E3·E4 실패 지문 | ㉚라 send rc 3 → 판정 불가 1줄 · 둘째 바퀴 send 0 · 줄 0 · 날짜 바뀐 바퀴 send 1 / ㉚마 7초 초과 · 장부에 경계보다 큰 그 글 없음 → send 1회 · ㉚라와 같음 / M18 |
| E6 받는 곳 없음 | ㉚바 세 칸 빈칸 → 받는 곳 없음 1줄 · 둘째 바퀴 0줄 |
| E5 바퀴 3통·재시도 0 | ㉚사 [긴급] 6건 → send 3 · NOTIFY-DEFER 1줄 · 다음 바퀴 send 3 · 지문 6 / M19 / M25 |
| E9 rc 0 그대로 | ㉚아 send rc 0 → NOTIFIED 1줄 · 지문 |
| E7 도착 확인 | ㉚자 7초 초과 · 경계보다 큰 seq 로 그 글 있음 → send 1회 · NOTIFIED(도착 확인 · rc None) · 성공 지문 · 같은 글 1통 / ㉚차 rc 3 · 그 글 있음 → 같음 / M23 |
| E7-1 seq 경계 | ㉚파 같은 초 이전 글(seq 100 · 같은 ts) · 경계 100 · 새 줄 0 → 도착 아님 · 실패 지문 · NOTIFIED 0 / ㉚하 같은 초 새 글(seq 101 · 같은 ts) → 도착 · 성공 지문 / M32(ts ≥ 비교) → ㉚파 FAIL / M33(ts > 비교) → ㉚하 FAIL |
| E7-2 경계 못 잡음 | ㉚카 7초 초과 · 장부 못 읽음 → 실패 지문 · 도착 판독 불가 1줄 · 재시도 0 |
| E7-3 창 밖 | ㉚거 경계 100 · 다른 글 250줄(seq 101~350) · 같은 글 0 → 도착 판독 불가 1줄(«없음» 아님) · 실패 지문 |
| E8 명부 찾기 | ㉚타 팀 v65 · seats-v65.json 없음 · seats.json 에 _master → 그 팀장에게 1통 / 팀 cfo · seats-cfo.json 없음 → 명부 없음 → 다음 칸 / M24 |

## 상태
- base_sha: 0de903a252e7f632c3020b44d6c63dc67adb357f (spawn 2026-11-16)
- 2026-11-16 · aifp-ft-arch-pi#17 씀(aifp 5395 ①) · 대기 · 설계 r3 = DA 대행 APPROVE-DESIGN(BYZ 310019) · 선행 = ft2-slack-accept-capacity 착지
- 2026-11-16 02:18 — 대기→진행 · 좌석 aifp-ft-nano-ft2-keeper-notify-recipient#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 2026-11-16 — 나노 aifp-ft-nano-ft2-keeper-notify-recipient#0 · E1~E8 구현(커밋 3개 · push 0 · 가지 nano/ft2-keeper-notify-recipient) · `ft-nano-record.sh done` = 판정 불가「명부 읽기(ft) rc=1」(좌석 이름 `aifp-ft-*` → `seats-ft.json` 을 찾는다 · aifp 명부는 `seats-aifp.json`) → 증거 줄은 카드에 직접 썼다
- 세트: 8b2e647e30f4c7160ecac17d4a37083631d4451b · 시험: python3.11 -m pytest ft2/tests/test_keeper_notify_recipient.py — (23 passed · 17.1초) rc=0 · 이슈: 0
- 회귀: python3.11 -m pytest ft2/tests/test_settle_one_path_r2055.py ft2/tests/test_pi_keeper_r1812.py ft2/tests/test_pi_keeper_followup_r2000.py — (29 · 31 · 26 passed · 정정 aifp 5484: 앞서 106·16 으로 잘못 적음) rc=0 · ruff check rc=0 · ft-test-reentry-lint.sh rc=0
- 산출: adapters/pi/keeper_report.py(notify·recipients·cells·budget·send·arrived·boundary·finish·stand_in·flush) · adapters/pi/launch_roster.py(roster_path(root, team) → 경로|None · 인자 (루트, 팀) · E8 한 함수) · adapters/pi/keeper_settle.py(alert 독스트링만) · 새 시험 test_keeper_notify_recipient.py · 기대 고침 2파일 · CONTRACT.md §4·§9 · CASES.md §5 · design/DESIGN-r2065-keeper-notify-recipient.md(사본)
- 남은 일: 착지 PR·설치 판(팀장) · ㉚파·하·거+M32·M33 따로 재확인(arch) · 설치 뒤 1시간 실측(arch) · press 필요: keeper 로그에서 «판정 불가 … 쪽지» 줄 수와 ROUND 쪽지 stall 이 21초를 넘는 바퀴 수(라이브 1시간 · 나노는 press 0)
- 고침: DA HOLD-IMPL(BYZ 310738) 반례 1건 = A 알림 뒤 새 후보 B 가 그날 안 나감 → 커밋 8ba57455(keeper_report.report 쪽지 열쇠 seats[0] → fresh[0] · 사례 ㉚더 · 변이 M34 · .worktree-info.json 되돌림 · aifp 5505)
- DA 판정: HOLD-IMPL 310738 → APPROVE-IMPL 310812(aifp 5510) · 구현 2/3 · c7 별건
- 세트: 8ba5745547a313233c59c8ff1a58d033c543fce9 · 시험: python3.11 -m pytest ft2/tests/test_keeper_notify_recipient.py (25 passed · 24.21초) rc=0 · 이슈: 0
- 남은 범위: 없음
