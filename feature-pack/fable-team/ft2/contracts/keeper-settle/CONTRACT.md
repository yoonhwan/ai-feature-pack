# ft2 keeper settle 계약 — 끝난 좌석은 한 길로 정리한다 (r2055 · 보정 3 · r2065 · 카드 ft2-done-seat-short-idle)

keeper 는 좌석마다 매 바퀴 판정 1개를 낸다. 이 문서는 그 판정과 core `park`·`capacity` 의 약속을 **파일로 고정**한 계약이다.
새 설계 판단은 없다. 설계 정본과 착지한 코드·시험에 있는 것만 옮겼다.

| 항목 | 값 |
|---|---|
| 설계 정본 | `feature-pack/fable-team/design/DESIGN-r2055-seat-settle-one-path.md`(원본 BYZ ops/main-base @457df3cdd1 · r9) |
| 착지 코드 | 팩 d88ef381(PR 1246 · settle 한 길 · core park·capacity · resolve_card) · 77511fcc(PR 1249 · 보정 3 accept_only) |
| 설치 판정기 고침 | 팩 4b0567c3(PR 1250 · r2065 · 1.x `ft_launchd_llm_gate.py`) — settle 계약 밖이고, 2.0.61 되돌림이 막힌 원인이라 사고 기록에 함께 적는다 |
| 구현 자리 | `adapters/pi/keeper_settle.py` · `adapters/pi/keeper_close.py` · `adapters/pi/keeper_land.py` · `adapters/pi/keeper_endings.py` · `core/dispatch.py`(`park`) · `core/record.py`(`capacity`) · 1.x `comm/mbox_ops.py`(`peek --rows`) |
| 사례·시험 대응 | 같은 폴더 `CASES.md` |
| 사고 기록 | `feature-pack/fable-team/troubleshoot/2026-11-15-ended-seat-not-closed-r2055.md` |
| 카드 ft2-done-seat-short-idle | 착지한 좌석은 무활동 300초에 닫고(`DONE_IDLE`), 쉼 판정에서 «닫힌 꼴 마감 쪽지» 만 뺀다(A1~A9) · 설계 = `design/DESIGN-pA-done-idle-threshold-20261116.md`(원본 sha256 700e2174…353f · DA 대행 APPROVE-DAY BYZ 310212) · 시험 = `tests/test_done_seat_short_idle.py` |
| 설계 뒤 고침(r2058) | 열기 실패(`launch-failed`)와 열기 멈춤(`opening`)의 끝 = 쉼 + `UNKNOWN` · 설계 = `feature-pack/fable-team/design/DESIGN-p2-launch-failed-no-park-rest-20261116.md` · `design/SWEEP-FIX-table-20261116.md` §F |

## 1. 판정 4개 (좌석마다 바퀴당 정확히 1개)

| 판정 | 뜻 | keeper 행동 |
|---|---|---|
| `LANDED` | 착지 끝 | 유휴 확인 → 세션 닫기 1 → complete |
| `PARKED` | 끝났고 남길 것이 안전 | 세션 닫기 1 → core `park` · 워크트리·가지·pi 세션 파일 보존 |
| `WORKING` | 일하는 중(양성 근거가 있음) | 손 0 |
| `UNKNOWN` | 위 셋을 못 채움 | 닫기 0 · [긴급] 1줄(좌석 · 사유 코드 · 다음 수) |

- `HELD` 판정 낱말은 없다. 조용히 남는 보류는 없다. 못 채우면 `UNKNOWN` 으로 드러난다.
- 행동 줄 `HELD-NEXT`·`HELD-SEAT`·`HELD-STALL`·`HELD-ORPHAN` 은 낱말을 그대로 뒀다(d88ef381 «남은 범위» · 판정 낱말이 아니라 행동 기록이다).
- 판정 줄 꼴 = `<판정> <팀> <work> <좌석> <사유 코드> · <꼬리>`. 같은 좌석의 같은 (판정, 사유)는 다시 찍지 않는다(바뀔 때만 1줄).
- 세션 닫기 조건에서 «착지» 를 뺐다. 착지는 일(work)의 상태로만 따로 센다.
- r2058 — 쉼을 실행하는 두 자리(`launch-failed`) 가운데 열기 실패·열기 멈춤은 **판정 낱말이 `UNKNOWN`** 이다. 종전 `PARKED … launch-failed` 줄은 없다(쉼은 그대로 실행한다).

## 2. 근거 순서 (먼저 채워진 판정을 낸다)

| 순서 | 판정 | 근거(읽기만) |
|---|---|---|
| 1 | `LANDED` | 카드 «- 착지:» 줄 sha 가 base 조상 · `nano/<work>` merged PR · 카드 머리 끝 표식(완성후·아카이브·중단·대체) · 넓힌 근거 = 원장 done ∧ 카드 완성 폴더 · 가지 커밋이 base 에 이미 있음(`git cherry` 전부 `-`) |
| 2 | `WORKING` | 양성 근거만: pane `Working`·스피너 · jsonl 이 `PARK_IDLE` 안에 늘어남 · CPU busy(pane 후손 에이전트 %cpu ≥ 0.3) |
| 3 | `PARKED` | 유휴 ≥ `PARK_IDLE` ∧ 워크트리 clean ∧ 가지 HEAD = origin 같은 가지(또는 base 위 커밋 0) ∧ 그 좌석 앞 미수신 쪽지 0 ∧ 그 work 에 uncertain·effect 표식 없음 |
| 4 | `UNKNOWN` | 위 셋 다 못 채움 |

지켜야 하는 약속:

- **착지한 좌석만 짧은 문턱을 쓴다**(A1·A2). `landing()` 이 참인 좌석(카드 착지 줄 · 넓힌 근거)의 닫기 길은 `DONE_IDLE` 300초다. 조건은 마지막 pi 턴 `stopReason=stop` ∧ CPU idle 2회 ∧ 막는 미읽음 0 이다. 착지 0 좌석·셸만 남은 pane 의 park 길은 지금과 같다(`PARK_IDLE` 3600초 · 셸은 CPU 무관). 문턱이 짧아도 턴이 안 닫혔으면 `WORKING landed-wait` 다(닫기 0).
- **쉼 판정에서 빼는 미읽음 = «닫힌 꼴 마감 쪽지» 뿐이다**(A5~A8). 읽는 대상은 keeper 가 부르는 `mbox.sh peek <좌석>` 의 그 집합이고, `peek --rows` 로 미읽음마다 JSON 1줄(seq·ts·to·from·body)을 받는다. 한 통이 아래 셋을 모두 채워야 빼고, 하나라도 못 채우면 그 좌석은 `UNKNOWN mail-pending` 이다. ① 본문이 닫힌 꼴이다 — `골좌표:` 로 시작하는 줄과 빈 줄을 뺀 나머지가 정확히 1줄이고 그 줄 전체가 `[마감 #<숫자>] 할 일 0` 또는 `[마감] 할 일 0` 이며 꼬리는 ` · 착지 <7~40자 hex>` 하나만 된다(자유 글은 안 읽는다) ② 보낸 이가 그 팀 명부의 역할 칸(`_master`·`_arch`·`_desk`)에 지금 적힌 좌석이다(명부를 못 읽으면 막는다) ③ 쪽지 `ts` 가 그 좌석에 쓰는 유휴 문턱보다 오래됐다. 빼는 쪽지는 큐에 그대로 둔다(keeper 는 mark·recv 하지 않는다). 근거 줄 꼬리 = `· 미읽음 마감 <n>통 제외(seq <앞 3개> · 가장 오래된 <분>분)`.
- `peek --rows` 판독 실패는 이렇게 가른다 — rc ≠ 0 · 머리줄에 `pending=` 없음 · JSON 깨짐 · `0 < 줄 수 ≠ pending` = `mail-unknown` · 머리줄은 읽혔는데 줄이 0 이고 `pending > 0` = 옛 mbox(`--rows` 모름) → `mail-pending`. 착지 좌석은 `peek --rows` 한 번, 그 밖 좌석은 `peek` 으로 pending 을 먼저 보고 0 이 아니면 `--rows` 로 내용을 읽는다(옛 mbox 호환).
- **CPU idle 단독은 유휴·닫기 근거가 아니다.** 유휴 = jsonl 무활동 ≥ `PARK_IDLE` ∧ CPU idle 2회 둘 다. pi 는 API 응답을 기다리는 동안 %cpu 가 0.0 이다. 셸만 남은 pane 은 CPU 와 무관하게 에이전트 종료 근거다.
- **판독 실패를 `WORKING` 으로 두지 않는다.** 근거를 못 읽으면 `UNKNOWN` 이다.
- **끝남 판독 순서**(설계 §13): 1차 = `tmuxc clean` 바퀴당 1회(실행 파일 호출 · import 0)와 CPU 규칙. 1차를 못 세운 좌석만 2차 = pane 끝 줄 읽기. 입력줄 `❯`·`›` 뒤 글자는 근거가 아니다. 둘 다 못 세우면 `UNKNOWN probe-fail`.
- **세션 부재 확정** = raw `tmux has-session` rc 1 + «can't find session» 뿐이다.
- 상수(`adapters/pi/keeper_settle.py`): `PARK_IDLE` 3600초 · 착지 좌석 닫기 `DONE_IDLE` 300초 · 질문 창 `WAIT_S` 900초 · `CPU_IDLE` 0.3 · `CPU_GAP` 30초 · `CPU_DEPTH` 8 · 셸 목록 `zsh`·`bash`·`fish`. CPU 문턱·간격·후손 깊이·셸 목록은 tmuxc 규칙과 같은 값이다.

## 3. 사유 코드

| 판정 | 사유 코드 | 뜻 |
|---|---|---|
| `PARKED` | `idle-done` | 끝났고 유휴 · 남길 것 안전(park 사유) |
| `UNKNOWN` | `launch-failed` | intent failed·closed ∧ 세션 부재 ∧ owner 남음 = core `park`(사유 `launch-failed`) 1회(멱등) + 판정은 `UNKNOWN`·[긴급] 1통(r2058 L3) · `PARKED … launch-failed` 줄 0 · 흐름은 PARKED(깨움·재배정·hold 검사 0 · L4) · 매 바퀴 다시 본다(L1·L2) |
| `UNKNOWN` | `launch-failed` | 열기 멈춤 — intent `opening` ∧ `OPEN_STALE`(900초) 넘음 ∧ `fill_open`(잇는 중) 아님 ∧ owner 남음 ∧ 세션 부재(`tmux` rc1 «can't find session») 넷 다 참 = L3 과 같은 길(r2058 L6) · tmux 조회 실패는 부재가 아니라 «판정 불가» 1줄(park 0) · 문턱 안쪽·잇는 중 = `WORKING launch-pending`/`launch-joining`(손 0) |
| `PARKED` | `session-absent` | 끝남 ∧ 세션 없음 ∧ 카드 0 |
| `WORKING` | `pane-working` · `pane-pending` · `cpu-busy` · `jsonl-active` · `cpu-<값>` · `turn-open` | 양성 근거 또는 유휴 문턱 전 |
| `WORKING` | `keep-recent` · `keep-last-2` · `ready-wait` | 장기 좌석 보존(닫기 0 · [긴급] 0 · 정상 보존) · 후계 [레디] 영수 0 |
| `UNKNOWN` | `waiting-input` | 마지막 줄 toolUse ∧ jsonl 무활동 ≥ 15분 ∧ CPU idle 2회 = 사람 답 대기 |
| `UNKNOWN` | `dirty` · `unpushed` · `git-error` | 남길 것이 안전하지 않음 |
| `UNKNOWN` | `mail-pending` · `mail-unknown` | 그 좌석 앞 «막는 미읽음» 이 있음(빼는 마감 쪽지 밖) · 판독 실패(§2 약속 · A5~A8) |
| `UNKNOWN` | `shell-only-unsafe` | 셸만 남았는데 남길 것이 안전하지 않음 |
| `UNKNOWN` | `owner-orphan` · `session-absent` | 세션 없음 · owner 판독이 반쪽 꼴과 다름 |
| `UNKNOWN` | `intent-bad` | intent 에 worktree 칸 없음 등 새 꼴 |
| `UNKNOWN` | `accept-only` | 접수만 있고 dispatch 0 이 `PARK_IDLE` 을 넘음 |
| `UNKNOWN` | `roster-outside` · `name-bad` | 어느 명부에도 없는 `byz-*` 세션 · 이름 lint 실패 |
| `UNKNOWN` | `tmuxc-mismatch` | 1차가 쉼인데 닫기 직전 가드가 Working 을 봄 |
| `UNKNOWN` | `probe-fail` · `session-none` · `tmux-error` · `turn-open` | 판독 실패 · pi 세션 파일 없음 · tmux 실패 · 턴 끝 근거 없음 |
| `UNKNOWN` | `kill-failed` · `park-refused` | 닫기 실패 · core `park` 거절 |

- `park` 가 받는 사유는 `idle-done`·`launch-failed` 둘뿐이다. 그 밖의 값은 거절이다.
- `WORKING` 과 `UNKNOWN` 의 사유 코드 목록은 닫힌 집합이 아니다. 새 꼴은 새 코드로 `UNKNOWN` 에 드러난다. 위 표는 77511fcc 시점 코드에서 읽은 값이다.

## 4. [긴급] 드러냄과 쪽지

- 본문 꼴 = `[긴급] UNKNOWN <팀> <work> <좌석> <사유 코드> · <꼬리 80자> · 다음 수 <행동>`.
- 지문 = (team, work, attempt, reason). 같은 지문은 하루 1회다. 새 사유·새 attempt 는 첫 1회 즉시 보낸다.
- **실패도 그날 지문이다**(r2065 · 값 `fail|<날짜>|<rc>`). 같은 열쇠로 그날 다시 보내지 않고 `판정 불가` 줄도 그날 1회다. 날짜가 바뀌면 1회 다시 시도한다.
- 받는 곳 차례 = 그 팀 `_master` → 그 팀 `_desk` → harness `_master`. 처음으로 값이 있는 한 곳에만 보낸다(두 곳 동시 0).
- 대신 받는 곳(`_desk`·harness `_master`)에는 글마다 보내지 않는다. 팀당 하루 1통 묶음 `[긴급] <팀> 팀장 없음 · 못 전한 keeper 판정 <n>건 · 앞 3건: …` 이고, 그날 뒤에 생긴 판정은 `state.undelivered[<팀>]` 에만 쌓여 다음 날 묶음에 들어간다.
- 세 칸이 다 빈칸 = `판정 불가 <팀> 쪽지 받는 곳 없음` 그날 1줄 + 같은 실패 지문.
- 통마다 7초 · 재시도 0 · 한 바퀴 3통. 넘는 것은 지문을 쓰지 않고 다음 바퀴로 넘긴다(`NOTIFY-DEFER <팀> <n>통 · 다음 바퀴` 1줄 · 값이 바뀔 때만).
- 7초를 넘겨 rc None 이거나 rc≠0 이면 우편함 장부(`<루트>/.fable-team/comm/mailbox.log.jsonl` 끝 200줄 · 읽기만)에서 도착을 확인한다. 경계 = send 직전 장부 끝 200줄의 정수 seq 최댓값이고, 경계보다 큰 seq 줄 중 «보낸 이 ft2-keeper · 받는 곳 · 본문 첫 줄» 이 같은 줄이 있으면 도착이다(성공 지문 + `NOTIFIED <받는 곳> (도착 확인 · rc <값>)`). 시각(`ts`)은 비교에 쓰지 않는다.
- 경계를 못 잡으면(장부 없음·못 읽음·seq 줄 0) send 결과만 본다. 경계와 창 사이를 못 봤으면(창 밖) «없음» 이 아니라 `도착 판독 불가` 로 적는다.
- rc 0 인 send 는 장부를 다시 읽지 않는다(경계 읽기 1회만 든다).
- 명부 찾기 = `launch_roster.roster_path(root, team)` 한 함수. `seats-<팀>.json` 이 있으면 그 파일 · 없고 팀이 v65 면 `seats.json` · 그 밖은 명부 없음(차례의 다음 칸).
- 운영 1줄: 팀장을 다시 세운 날 바로 받게 하려면 `state.json` 의 `sent` 에서 그 팀 `fail|` 값을 사람이 지운다.
- `full_alert` 의 받는 곳(팀 master + harness master 두 곳)은 이 절과 별개다(r1927 그대로).
- 바퀴마다 `ROUND` 줄에 `unknown=N` 을 적는다.

## 5. core `park` — owner·예약 해제를 한 줄로

- 호출 = `cli park --work <work> --attempt <attempt> --reason <idle-done|launch-failed> --root <루트> --team <팀>`.
- 쓰는 줄 = journal `parked` 1줄 `{reason, released:[자원], owner_released:{holder, gen}}`.
- 효과 = owners 에서 그 work 제거 · reservations 에서 그 work 행 제거 · `state.parked[work] = {attempt, at, reason, released}`.
- 거절(쓰기 0) = 낡은 attempt · 완료 기록 · 결과 미확정(uncertain · 효과 의도 뒤 결과 0).
- 같은 attempt 가 이미 쉼이면 `HOLD` 멱등(쓰기 0).
- journal 줄 뒤 state 쓰기 전에 죽으면 복구가 같은 fold 로 앞선다. 다시 부르면 멱등 `HOLD` 다.
- 같은 work 의 새 dispatch 가 쉼을 지운다. 예약이 풀려 있어 같은 자원으로 배정된다.
- done 을 꾸며 예약을 푸는 길은 없다. 자동 길에서 `result` → `return` 을 쓰지 않는다(예약이 남는다).

## 6. 셈 두 벌 — 의무 장부와 용량

| 셈 | 함수 | 보는 곳 | 쉼(parked) work |
|---|---|---|---|
| 의무 장부 | `record.remaining` | 마감 gate · 재개 queue · 투영 | 센다(끝나지 않은 일이 숨지 않는다) |
| 용량 | `record.capacity` | 접수 상한 · keeper fill · 투영 `capacity` 칸 | 안 센다 |

- 용량은 work 단위다. 같은 work 의 command 2개 = 의무 2줄 · 용량 1칸. work 없는 command 는 command 하나가 1칸이다.
- accept 줄의 work 가 dict(Slack 글 영수)인 command 는 용량 단위가 아니다(r2089 · 카드 ft2-slack-accept-capacity). 그 글에서 나온 일은 str-work 접수로 따로 칸을 쥔다 · 의무 장부에서는 그대로 센다(dict-work 도 remaining 1줄).
- `accept_only` 는 work 가 문자열인 접수만 본다. work 가 dict·None 인 접수(Slack 접수 등)는 대상 밖이다(보정 3 · 77511fcc).

## 7. 정지 신호 한 벌

- keeper 는 매 바퀴 `.fable-team/state/ALL_STOP.json` 을 읽는다. 있고 해제 표식이 없으면 정지다.
- 정지 중 = 판정·[긴급]·«예정» 줄만 낸다. 세션 닫기·`park`·깨움·fill 은 0 이다.
- 못 읽으면(JSON 깨짐) 정지로 보고 판정 불가 1줄을 낸다.

## 8. 카드 찾기와 장기 좌석

- `resolve_card(team, work)` = 짝 표 → 팀 폴더 → 발주 본문 카드 경로 3단계다. 0 이면 «판정 불가 · 카드 후보 0» 꼬리가 붙고(설계 낱말 `card-none`), 카드를 못 찾아도 `PARKED` 길은 막히지 않는다. 카드 끝 표식 판독(`keeper_endings`)도 같은 `resolve_card` 를 쓴다.
- 1.x `resolve_owner`(차례 나노가 어느 명부에 있나)와는 역할이 다르다. 한 함수로 합치지 않는다.
- 장기 좌석(master·arch·DA·desk·tester)은 `PARKED` 대상이 아니다. 끝남 근거(명부 `_replaced_by` ∧ 후계 ready 영수 · 또는 close 영수)와 닫기 자격(`~/.claude/guides/hil.md` «tmux 세션 정리 표준승인» 보존 조건)을 둘 다 채울 때만 닫는다.
- 자동 닫기가 남긴 세션을 손으로 닫는 일은 이 계약 밖이다 → `~/.claude/guides/hil.md` «수동 닫기 지원 표준승인»(판정 4180).

## 9. 알려진 한계 (d88ef381 PR 본문 «남은 범위·한계» 중 지금 코드에 남은 것)

- 행동 줄 `HELD-NEXT`·`HELD-SEAT`·`HELD-STALL`·`HELD-ORPHAN` 은 낱말을 그대로 뒀다.
- intent 없는 master 좌석이 holder 이면 `UNKNOWN intent-bad` 와 [긴급]이 나간다(닫기 0).
- noland 목록 내용이 바뀌면 판정 줄을 다시 1줄 낸다(verdict 장부 키를 지운다 · r1841 ⑥).
- PR 본문의 두 한계는 77511fcc 시점 코드에서 풀려 있다(코드 읽기): keeper 가 `tmuxc clean` 을 부른다(`keeper_settle.py` `tmuxc_status`) · `keeper_endings` 가 `resolve_card` 를 쓴다.
- r2065 행 E 의 두 한계(DA BYZ 310019 승인 범위): ① 7초 안에 장부가 200줄 넘게 늘면 창이 경계를 지나 도착했어도 `도착 판독 불가` 로 남는다 ② 그 글은 실패 지문이라 다음 날 1회 다시 가서 같은 글이 2통이 될 수 있다. 장부 seq 가 늘 커진다는 것은 전제이고 실행 보증이 아니다.
- 이 계약은 시험 4개가 묶는 값만 적었다. 실사건 관측 값은 담지 않는다.

## 10. 전 세션 정지 재개 전 팀 (`PENALTY_STOP` · r2073 · 카드 ft2-penalty-team-no-new-pick)

- 무엇을 막나 = 새 카드를 넣는 두 자리뿐이다. `keeper_next.fill()` 의 새 pick 과 `keeper_next.close()` 의 닫기 뒤 pick. 꼴은 `gates(k, team) and penalty_open(k, team)` 이고 `gates()` 가 거짓이면 판정기를 부르지 않는다.
- 안 막는 것 = 이미 연 열기 잇기(`fill_open` · `reconcile`) · 복구 launch 직전 가드(`reconcile` 의 `pick is None and not gates(k, team)` 그대로) · settle · 착지 complete · 닫기 영수 · 깨움 · 사람 손 `ft2 submit/assign/deliver` · 팀장 개설·승계.
- 판정기 자리 = env `FT2_PENALTY_BIN` → 없으면 `dirname(close_bin)/ft-penalty.sh`(SPAWN_HOLD·ACCT_PAUSE 와 같은 폴더 규칙). 부르는 꼴 = `bash <판정기> check <팀>` · env `FT_ROOT = k.root` · 상한 7초(하드 룰 12). 팀당 바퀴 1회만 부른다(`once` 캐시).
- keeper 는 `state/PENALTY_STOP` JSON 을 직접 풀지 않는다. 재개 규칙·면제 팀은 1.x `ft_penalty.py` 한 곳이 한다.
- 판정 = 표식 파일 `state/PENALTY_STOP` 자체가 없으면 참(판정기 호출 0) · 있으면 판정기 rc 로: `0` = 참(재개됨) · `3` = 거짓(재개 전) · 그 밖(`1`·`2`·도구 없음·시간 초과) = 거짓 + 판정 불가. 판정 불가도 새 카드 0 이다.
- 줄 꼴(값이 바뀔 때만 1줄): `NEXT-HOLD <팀> PENALTY_STOP 재개 전 — 다음 카드 0` · `판정 불가 <팀> PENALTY_STOP 판독 rc <값> — 다음 카드 0` · 풀리면 `NEXT-OPEN <팀> PENALTY_STOP 풀림`.
- 상태 키 = keeper 상태 파일 `state/ft2-keeper/state.json` 의 `penalty_seen[<팀>]`. 값은 마지막으로 찍은 표식(`hold` 또는 `rc <값>`)이고 열림이면 키가 없다. 메모리에만 두지 않는다 — 재기동해도 같은 줄을 다시 찍지 않는다.
- 알려진 한계 = 바퀴 캐시 안에서 바뀐 정지·재개는 다음 관측(다음 바퀴)에 반영된다. 사람 손 발주는 이 계약이 막지 않는다.

## 11. 새 카드 보류 설정 (`NEW_CARD_HOLD` · r2101 · 카드 ft2-new-card-hold)

- 설정 자리 = `<데이터 루트>/.fable-team/state/NEW_CARD_HOLD.json` 1개(전 팀 공통). 꼴 = `{"reason": "<10자 이상>", "by": "<좌석>", "at": "<시각>", "until": "<사람이 읽는 조건>"}`.
- 판독 = keeper 가 바퀴당 1회(`once` 캐시 · 팀 사이 공유). 없음 = 열림 · 있음 = 보류 · 깨짐(빈 파일 · JSON 아님 · `reason` 없음) = 보류 + `판정 불가` 1줄. 깨진 파일을 «꺼짐» 으로 읽지 않는다.
- 막는 곳 = 새 카드를 스스로 고르는 두 자리뿐이다. `keeper_next.fill()` 의 새 pick 과 `keeper_next.close()` 의 닫기 뒤 pick.
- 안 막는 것 = 이미 연 열기 잇기(`fill_open` · `reconcile`) · 복구 launch 직전 가드 · settle · 착지 complete · 닫기 영수(`close_receipt`) · 깨움 · 사람 손 `ft2 submit/assign/deliver` · 팀장 개설·승계·사람 손 나노 개설.
- 이 파일을 읽는 곳은 `adapters/pi/keeper_next.py` 뿐이다. `gates()` 본문 · ALL_STOP · 팀별 `PAUSED` · `ft-successor-open.sh` · `ft-nano-spawn.sh` · `tmuxc open` 은 이 파일을 읽지 않는다(시험 ㉗사 = 실행 파일 문자열 검색).
- 줄 꼴(값이 바뀔 때만): `NEW-CARD-HOLD <팀> <reason> · until <until>` · 깨짐이면 `판정 불가 <팀> NEW_CARD_HOLD 판독 불가(빈 파일·JSON 아님·reason 없음) — 새 카드 0` · 풀리면 `NEW-CARD-OPEN <팀>`.
- 상태 키 = keeper 상태 파일 `state/ft2-keeper/state.json` 의 `new_card_hold_seen[<팀>]`. 값은 마지막으로 찍은 표식(`<reason>|<until>` 또는 `깨짐`)이고 열림이면 키가 없다. 메모리에만 두지 않는다 — 재기동해도 같은 줄을 다시 찍지 않는다.
- 풀기 = 파일을 `NEW_CARD_HOLD.released-<시각>` 으로 이름 바꾼다(ALL_STOP 과 같은 손). «2.0 완료» 같은 기간의 끝은 기계가 판정하지 않는다 — 사람이 둔 파일이 기준이다.
- 알려진 한계 = 판독이 바퀴 캐시 안이라 파일을 두거나 치운 뒤 첫 반영은 다음 바퀴다. 보류 중에도 `[다음 없음]` 쪽지는 나가지 않는다(고르기를 아예 부르지 않는다).

