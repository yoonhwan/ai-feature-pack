# 전 팀 훑기 → 고침 표 (aifp-ft-arch-pi#16 · 2026-11-16 · 발주 aifp 5326 · planner 5325)

- 훑기 원본: BYZ `.fable-team/state/team-main/planner/SWEEP-all-teams-0052-20261116.md`
- 읽은 것(쓰기 0): 팩 origin/main 1757addf core 로 BYZ 데이터 루트 셈 · keeper 로그 `.fable-team/state/ft2-keeper/20261114~16.jsonl` · 팀 journal · launch intent · `seats-<팀>.json`
- 상태: 행 A~G · I 원인 판독 끝 · H 는 원문 줄 필요 · B · C · D = DA APPROVE · E 설계 r1 따로 · 코드 0

## 표

| 행 | 뿌리 | 팀 | 증거(원문 자리) | 고침 설계 | rc |
|---|---|---|---|---|---|
| A | 끝나도 안 닫힌다. 유휴 문턱이 하나(60분)뿐이다 | 전 팀 | `keeper_settle.py` 218줄 `idle = age >= PARK_IDLE(3600) and (shell or cpu idle)`. 착지한 일의 닫기(`land_ready` · `keeper_close.py` 87 · 123줄)도 같은 `look()` 을 쓴다. 11-16 00:00~00:55 로그 1910줄 중 LANDED · CLOSED · complete 줄 0. harness 는 끝난 나노 5석이 칸을 쥐어 8/8 이었다(팀장 5314) | `orders/DESIGN-pA-done-idle-threshold-20261116.md`(정본) — 착지한 좌석만 짧은 문턱 300초 · result 줄은 근거로 안 씀 | 설계 r1 · DA 전 |
| B | Slack 글 접수(dict-work)가 접수 칸을 쥔다 | planner 4 · issues 2(팀장 01:2x 실측) | `core/record.py` `capacity()` 가 «cmd:» 1칸으로 셈 · 비우는 길은 str-work 만 봄 | `orders/DESIGN-p3-slack-accept-capacity-20261116.md` · 카드 `design/aifp/indices/대기/ft2-slack-accept-capacity.md`(lint OK) | 설계 r2 · DA 대행 1/3 HOLD-DESIGN 반영 · 재판정 전 |
| C | 새 카드 투입을 멈추는 전 팀 설정이 없다 | harness(r2057 · r2058 · r2064) · 설정은 전 팀 | `keeper_next.gates()` 에 전 팀 보류 칸 0 · journal harness 2852~2854 | `orders/DESIGN-p1-new-card-hold-20261116.md` | 설계 r1 · DA 전 |
| D | 열기 실패(launch-failed)가 쉼 줄 뒤 바퀴에서 빠진다 | harness r2058 | `keeper.team_round` 302 · 305줄 `(work, attempt) in back → continue` · 00:06:37~00:44:25 줄 0 | `orders/DESIGN-p2-launch-failed-no-park-rest-20261116.md` | 설계 r1 · DA 전 |
| E | 팀장 없는 팀의 [긴급] 이 갈 곳이 없고, 못 보낸 줄을 바퀴마다 다시 찍는다 | cfo · chatbot · feature · issues · kk · knowledge · ops · room(`_master` 빈칸 8) · v65(`seats-v65.json` 파일 없음) | `keeper_report.notify` 11~22줄: `_master` 없으면 `판정 불가 쪽지 _master 없음` · 실패는 지문(sent)을 안 쓰므로 다음 바퀴에 또 찍는다. 00:00~00:55 로그 1910줄 중 `판정 불가` 1555줄 · 같은 줄이 42~43회(43바퀴) | `orders/DESIGN-pE-keeper-notify-no-recipient-20261116.md`(§E 요약은 옛 판 · 그 파일이 정본) | 설계 r1 · DA 전 |
| F | 열기가 끝나지 않은 채(intent `opening`) 멈춘 일을 keeper 가 반쪽으로 보지 않는다 | v65 8/8 | 6장(K4 · M5 4장 · M7): 11-14 12:36~12:54 accept → dispatch → deliver · intent `state: opening` · 세션 0 · owner 남음 · `HELD-NEXT v65 fill:M7-… launch rc None Command … 복구 필요`(열기 시간 초과) → 매 바퀴 `UNKNOWN owner-orphan`. 1장(v65-conn-1): result 줄 있음 · owner 0 · 세션 0 · 착지 줄 없음 → `UNKNOWN session-absent`. 1장(r1809): accept 만 → `UNKNOWN accept-only`. 8장 모두 [긴급] 이 E 에 걸려 아무에게도 안 갔다 | 아래 §F — `opening` 이 문턱을 넘으면 launch-failed 와 같은 길(D 규칙) | 설계 r1 · 새 설계 |
| G | Slack 글은 접수됐는데 desk 깨움이 실패하고 다시 깨우지 않는다 | planner(수신 팀 전부 같은 코드) | `adapters/slack/wiring.py` 52~61줄 `wake()` = `mbox.sh send` 1회 · 상한 25초 · 재시도 0. planner `slack/wire.jsonl`: 11-16 00:57:55 · 01:06:41 `rc -1 · 상한 초과 · 적재 없음`(쪽지가 우편함에 안 들어감) · `listen.log` «깨움 실패 TimeoutExpired» 19줄. 오빠 «네.» 접수 때 알림 깨움 실패(desk BYZ 309706) | 아래 §G — 적재 없음이면 다음 유휴 회차에 다시 보낸다 | 설계 r1 · 새 설계 |
| H | card_stage 의 git 호출이 7초를 넘는다 | chatbot | `adapters/pi/card_stage.py` 22줄 `subprocess.run(git …, timeout=7)` 이 `worktree add` · `worktree remove` 에도 쓰인다. BYZ 리포 `git worktree list` = 446줄(지금 실측). rc3 원문 줄은 keeper 로그에 없다 [확인 필요: 팀장이 본 rc3 줄의 자리] | 아래 §H | 판독 반쪽 · 원문 줄 필요 |
| I | 대기 카드의 «- 선행:» 이 글뿐이라 판정 불가가 바퀴마다 찍힌다 | cfo 3장(바퀴마다 3줄 · 00:00~01:1x 138줄) · harness 3장 | `keeper_next.prereq` 14~26줄: «- 선행:» 값에 카드 번호 참조가 없으면 `선행불명` → `판정 불가 <팀> <카드> 선행 줄 판독 불가 — 건너뜀` 을 매 바퀴 찍는다(cfo-pub-turnkey-atom-it-planner-rate · -sim-kosa-cost · -sim-source-links 각 46회) | 아래 §I | 설계 r1 · 새 설계 |

## §A 끝남 근거가 있으면 60분을 기다리지 않는다

> 옛 요약이다. 정본 = `orders/DESIGN-pA-done-idle-threshold-20261116.md`. 아래의 «result 줄 = 끝남 근거» 와 시험 ㉙다는 버렸다(5팀 work 187개 중 63개가 result 2줄 이상 = 단계마다 나오는 줄).

- 지금: 유휴 = pi jsonl 무활동 ≥ 60분 ∧ CPU idle 2회. 착지가 끝난 좌석도 60분을 채워야 complete · 닫기가 된다.
- 60분의 까닭(r2055 r7): pi 는 API 응답을 기다릴 때 %cpu 가 0 이다. CPU 만으로 닫으면 일하는 좌석을 죽인다. 이 약속은 지킨다.
- 고침: `look()` 의 유휴 문턱을 근거에 따라 둘로 나눈다.

| 좌석 상태 | 문턱 | 함께 채울 것(모두) |
|---|---|---|
| 끝남 근거 있음 = 착지 판독 참(`landing()[0]`) 또는 최신 attempt 에 journal `result` 줄 | `DONE_IDLE` 300초 | 마지막 턴 stopReason = `stop`(턴이 닫힘 · toolUse 대기 아님) ∧ CPU idle 2회 ∧ 그 좌석 앞 미수신 쪽지 0 ∧ uncertain · effect 표식 0 |
| 끝남 근거 없음 | 지금 그대로 `PARK_IDLE` 3600초 | 지금 그대로 |

- 닫기 직전 가드(`idle()` 마지막 확인 · tmuxc 대조 · attached 보류)는 그대로다.
- 장기 좌석 보존(`keep-recent` · `keep-last-2` · `ready-wait`)은 그대로다.
- 시험: ㉙가 착지 + stop + 무활동 6분 → complete · 닫기 / ㉙나 착지 + 마지막 줄 toolUse + 무활동 6분 → WORKING / ㉙다 result 줄 + stop + 무활동 6분 + clean → PARKED idle-done / ㉙라 근거 0 + 무활동 6분 → WORKING / ㉙마 착지 + 미수신 쪽지 1 → UNKNOWN mail-pending / 변이 = 문턱 분기 빼기 → ㉙가 · ㉙다 FAIL.
- 닫는 증거: 설치 뒤 끝난 나노 실사건 1건의 «result 또는 착지 시각 → keeper 닫힘 시각» 이 10분 안인 로그 줄.
- DA 에게: `DONE_IDLE` 300초 값 · `result` 줄을 끝남 근거로 써도 되는지(나노가 중간 결과를 result 로 내는 길이 있는지).

## §E 팀장 없는 팀의 쪽지 (옛 요약 · 정본 = `orders/DESIGN-pE-keeper-notify-no-recipient-20261116.md` · 받는 곳 차례가 팀장 기준 5347 로 바뀜: _master → _desk → harness _master · 실패도 하루 1회 지문 · 바퀴 3통)

| # | 규칙 |
|---|---|
| 1 | 받는 곳 차례 = 그 팀 `_master` → 그 팀 `_desk` → planner 명부 `_hil_route` → planner `_master`. 처음으로 살아 있는 좌석 1곳에 보낸다. 팀 명부 파일이 없어도(v65) 3번째부터 본다 |
| 2 | 대신 받는 좌석(3 · 4번째)에는 글마다 보내지 않는다. 팀당 하루 1통 묶음 `[긴급] <팀> 팀장 없음 · 못 전한 keeper 판정 <n>건 · 앞 3건 …` |
| 3 | 받는 곳을 끝내 못 찾으면 `판정 불가 <팀> 쪽지 받는 곳 없음` 을 같은 열쇠로 하루 1줄만 찍는다(지금은 바퀴마다) |
| 4 | 보내기 실패(rc ≠ 0)는 지금처럼 지문을 쓰지 않고 다음 바퀴에 다시 보낸다. 로그 줄만 같은 열쇠 · 같은 rc 는 하루 1줄 |

- 팀장을 다시 세우는 일(`_master` 채우기)은 운영 몫이다(planner). 이 규칙은 팀장이 없어도 판정이 사람에게 닿게 한다.
- 시험: ㉚가 `_master` 빈칸 · planner `_hil_route` 있음 → 묶음 1통 · 둘째 바퀴 0통 0줄 / ㉚나 명부 파일 없음 → 같은 결과 / ㉚다 받는 곳 0 → `판정 불가` 1줄 · 둘째 바퀴 0줄 / ㉚라 `_master` 있음 → 지금과 같음 / 변이 = 차례 3 · 4번째 빼기 → ㉚가 FAIL.
- 닫는 증거: 설치 뒤 한 시간 로그의 `판정 불가 … _master 없음` 줄 수(지금 1555줄/55분 → 팀 수 이하).

## §F 열기가 끝나지 않은 일(intent `opening`)

- 지금: 반쪽 판정은 intent `failed` · `closed` 만 본다(`keeper_settle.py` 180줄). 열기 명령이 시간 초과로 죽으면 intent 는 `opening` 으로 남는다. 세션 0 · owner 남음 = `UNKNOWN owner-orphan` 이 영영 되풀이된다. 칸 · owner · 예약도 그대로다.
- 고침: 세션 부재(rc1 «can't find session») ∧ owner 남음 ∧ intent `opening` ∧ intent `at` 이 `OPEN_STALE`(900초) 넘음 = 열기 실패로 본다. D 규칙 그대로 간다: core `park`(reason launch-failed) 1회로 자원을 풀고 `UNKNOWN launch-failed · opening <분>분` [긴급] 1통. 그 뒤 매 바퀴 착지 판독.
- `fill_open` 에 있는 열기(지금 잇는 중)는 대상이 아니다(`opening` 이 정상인 동안).
- v65-conn-1 꼴(result 있음 · owner 0 · 세션 0 · 착지 줄 없음): 규칙 추가 0. 지금처럼 `UNKNOWN session-absent` 다(착지 여부는 사람이 본다). result 줄은 끝남 근거가 아니라서 칸을 자동으로 풀지 않는다. E 가 고쳐지면 사람에게 닿는다.
- r1809 꼴(accept 만 · str-work): 이미 `UNKNOWN accept-only` 다. E 가 고쳐지면 사람에게 닿는다. 규칙 추가 0.
- 시험: ㉛가 intent opening 20분 · 세션 0 · owner 있음 → park 1 · `UNKNOWN launch-failed` 1 / ㉛나 opening 5분 → 손 0 / ㉛다 opening 20분인데 `fill_open` 에 있음 → 손 0 / 변이 = opening 분기 빼기 → ㉛가 FAIL.
- 닫는 증거: 설치 뒤 v65 capacity 가 8 → 2 이하(읽기 실측 1줄) + v65 6장의 parked 줄.
- 지금 v65 6장을 손으로 푸는 일(journal 쓰기)은 하지 않았다(HIL).

## §G Slack 접수 뒤 깨움 실패

- 지금: `wake()` 가 25초를 넘기면 `rc -1` 을 적고 끝난다. «적재 없음» 이면 그 글은 journal 에 접수만 되고 desk 는 모른다. 뒤따르는 알림 깨움(`[Slack] 알림 깨움 실패`)도 같은 길이라 같이 실패할 수 있다(00:58:26 rc -1).
- 고침: wire 장부의 마지막 wake 가 «rc ≠ 0 ∧ 적재 없음» 인 command 는 다음 유휴 회차(`pass_idle`)에 1회씩 다시 보낸다. 적재가 확인되면 멈춘다. 3회 넘게 실패하면 그 command 를 `[긴급] Slack 글 깨움 3회 실패` 로 harness 팀장에게 1통(하루 1회). «적재 있음» 인 시간 초과는 다시 보내지 않는다(이미 우편함에 있다).
- `mbox.sh send` 가 왜 25초를 넘는지는 안 봤다 [확인 필요: 받는 좌석 busy 확인 단계인지 · 우편함 잠금인지 — mbox 쪽 판독은 따로].
- 시험: ㉜가 wake 시간 초과 · 적재 없음 → 다음 유휴 회차 재전송 1 → rc0 뒤 재전송 0 / ㉜나 시간 초과 · 적재 있음 → 재전송 0 / ㉜다 3회 연속 실패 → [긴급] 1통 · 4회째 0 / 변이 = 재전송 빼기 → ㉜가 FAIL.
- 닫는 증거: 설치 뒤 wire.jsonl 에서 «rc -1 · 적재 없음» 뒤 같은 command 의 rc 0 줄.

## §H card_stage git 7초

- 본 것: card_stage 는 임시 detached worktree 를 만들어 카드를 옮긴다. git 호출마다 7초 상한이다. BYZ 리포에 worktree 가 446개라 `git worktree add` 가 느릴 수 있다.
- 못 본 것: rc3 원문 줄. 오늘 keeper 로그에 `card_stage` 낱말이 없다. 원문 자리를 받으면 걸린 git 명령(worktree add · fetch · push 중 어느 것)을 가른다.
- 고침 방향(원문 확인 뒤 확정): ⓐ worktree 대신 `git worktree` 없이 임시 index 로 커밋을 만든다(`GIT_INDEX_FILE` + `commit-tree` · 작업 폴더 0) 또는 ⓑ worktree add 만 로컬 하네스 상한 25초로 둔다(하드 룰 12). 끝난 worktree 446개 정리는 운영 손(HIL)이다.

## §I 글로 된 «- 선행:»

- 지금: 번호 참조가 없는 선행 글은 `선행불명` 이다. 고르지 않는 것은 맞다(추측 0). 문제는 같은 줄을 바퀴마다 찍는 것이다.
- 고침: `판정 불가 <팀> <카드> 선행 줄 판독 불가` 는 카드마다 값(선행 글)이 바뀔 때만 1줄. 팀장에게는 `[다음 막힘] <팀> 선행불명 <n>장 — «- 선행:» 을 카드 번호 또는 «없음» 으로` 를 하루 1통(이미 있는 «막힌 사유별 … 선행불명 n» 줄에 카드 이름 앞 3개를 붙인다).
- 카드 고침(운영 손): cfo 3장의 «- 선행:» 을 번호 또는 «없음» 으로 고치는 일은 cfo 팀장 몫이다.
- 시험: ㉝가 선행 글뿐인 카드 1 · 두 바퀴 → 판정 불가 1줄(둘째 0줄) / ㉝나 선행 글을 바꿈 → 1줄 다시 / 변이 = 값 기억 빼기 → ㉝가 FAIL.

## 카드 묶음 제안 (문제마다 카드 1 · 나노 1석씩)

| 카드 | 행 | 닿는 파일 |
|---|---|---|
| ft2-slack-accept-capacity(썼음 · r2) | B | core/record.py · slack/reply_done.py · pi/full_alert.py |
| 답 없는 Slack 접수 드러냄 1줄(후속 · DA Q2) | B 뒤 | pi/keeper_settle.py |
| 새 카드 보류 | C | pi/keeper_next.py · pi/keeper_settle.py(판독) |
| 열기 실패의 끝 | D + F | pi/keeper.py · pi/keeper_settle.py · pi/keeper_next.py |
| 끝남 문턱 | A | pi/keeper_settle.py · pi/keeper_close.py |
| 팀장 없는 팀 쪽지 | E | pi/keeper_report.py · pi/keeper_settle.py(alert) |
| Slack 깨움 재전송 | G | slack/wiring.py · slack/receive.py(pass_idle) |
| 선행불명 줄 1회 | I | pi/keeper_next.py |
| card_stage git | H | pi/card_stage.py(원문 확인 뒤) |

- `keeper_settle.py` · `keeper_next.py` 를 여러 카드가 만진다. 순서 = B → E → D+F → A → C(뒤 카드는 앞 카드 착지 위에서 시작 · C 는 planner 5337 로 우선 낮춤 · D+F 가 A 앞인 까닭 = r2057 꼴 «착지 끝 카드 재발주» 가 A 의 닫기를 다시 깨움 · 팀장 5346).
- 카드 파일: B = `design/aifp/indices/대기/ft2-slack-accept-capacity.md`(착지 ad8bb410) · D+F = `ft2-launch-failed-end.md` · C = `ft2-new-card-hold.md`(둘 다 lint OK · 미커밋) · E · A · G · I = 카드 전.
- E 를 앞에 둔 까닭: E 가 없으면 D · F · A 가 내는 판정이 9팀에서 사람에게 닿지 않는다.

## 명부 찾기 규칙 (행 E · F 공통 · planner 5353)

- 팀 명부 = `seats-<팀>.json` 이 있으면 그 파일 · 없고 팀이 v65 면 `seats.json` · 그 밖 = 명부 없음. 한 함수로 찾는다(정본 = `orders/DESIGN-pE-…` §3 규칙 8).
- 정정: 앞에서 «v65 는 명부 파일이 없다» 고 적은 것은 틀렸다. v65 명부는 `.fable-team/seats.json` 이고 `_master` = byz-v65-master-pi#294 가 있다. v65 의 «_master 없음» 360줄은 팀장이 없어서가 아니라 keeper 가 명부를 한 꼴(`seats-v65.json`)로만 찾아서다.
- 행 F 에 닿는 것: v65 6장의 `UNKNOWN owner-orphan` [긴급] 은 이 규칙이 들어가면 v65 팀장에게 바로 간다(대신 받는 곳 0).

## 훑기 숫자와 다른 곳

- 훑기의 «숨은 칸» 은 추정값이다. 실측으로 dict-work 인 것은 planner 4 · issues 2 뿐이다(팀장 01:2x). chatbot 은 str-work accept-only 4 + deliver 1 이다.
- `_master` 칸 v65 «?» = 명부가 `seats.json` 이다(`seats-v65.json` 없음 · 팀장은 있음).
