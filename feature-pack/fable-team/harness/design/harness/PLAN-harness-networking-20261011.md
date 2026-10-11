# PLAN — 팀 운영 구조 근원 수정 (근원 5 × 채택안 A~D) · arch#29 · 2026-10-11 · r2

골 원문(3줄 · GOAL-harness 상위 제약 = CLAUDE.md ACTIVE TRACK GOAL):
「목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.」
「LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.」
「단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.」
골의 어느 축: planner 원문 2(팀 배정·운영 · 베이스 팀과 위성팀 연결 관리 정리) — 그 골을 집행하는 «팀 운영 구조»가 오빠 시간을 잡아먹는 근원 5 제거. 하네스 GOAL 표로는 B(개선요청 접수·협의)+C(업그레이드·설치).
오빠 원문(10-11 · 판정 1069·1070): 「그래 하니스 마스터에 arch fable 구동하서 문제 근원 수정 개선 da 기획 완성 보완후 정지 래디」 — 「그래」 = REVIEW §6 정리안 A~D 채택.
발주: master#29 #76136 · planner#26 ORDER(/tmp/mbox/20261011T230957-…ORDER-harness-networking-20261011.md) · 정본 REVIEW `v6-realtime-live/design/planner/REVIEW-4days-networking-20261011.md` §4·§6.

> r1→r2 (DA r1 HOLD(2회째) #76265 · F1·F4·F5 교정 확인 · 남은 3건 반영): F3 D2 = 내 팀 좌석은 매 틱 «라이브 turn»(jsonl 턴 끝 시각 → 지금 기준 재계산) · 스냅샷은 타 팀 요약 전용 · 「신규 부하 0」 주장 철회 → «좌석당 jsonl 1회 읽기» 로 정정 + 회귀 픽스처 · F2 D3 수신 판정의 authoritative 명부 = 수신자 팀 파일 하나 · 타 파일 파싱 실패 = WARN · `[HIL]`·`[긴급]` 은 어떤 명부 상태에서도 전송(무손실 · 로그) · F6 §9 = raw 부팅 / 승계(불변 쪽지 로그 안 같은 계보 선행 부팅) / 개설(append-only `team-events.jsonl`) 세 지표 분리 · baseline·사후 같은 필터 · 정규식 명시.
> r0→r1 (DA r0 HOLD #76217 · 원인군 F1~F6 전부 반영 · A~D 채택값 무변경): F1 D1 을 admission/정리/검증 3단으로 분리 + `_master` 확정 사건 + 보존 좌석 WORKING 이면 닫힘 거부 · F2 `[HIL]`·`[긴급]` 은 기존 §7 경로 그대로 통과(머리만 바꾸게 하지 않음) + D7·D8 같은 예외 · F3 틱 줄에 관측 시각·age·UNKNOWN + 개입 직전 라이브 재측정 + 잘림 건수 · F4 수신 가능 상태를 필드로 확정 + 원자적 명부 교체 + 파싱 실패 ≠ 미등록 · F5 nano-close 원격 fetch 7초+1 · F6 §9 지표를 시각 있는 사건으로 재정의 + baseline 실측값(추정 표시 분리).

## 0. 실측 (이 설계의 전제 · 2026-10-11 23:3x · 바이트로 확인한 것만)

| # | 사실 | 값 · 출처 |
|---|---|---|
| 0-1 | 세션이 400k 까지 차는 «속도»의 주범 = 10분 체크 틱 | harness master#28 jsonl(8257a049…): 16.5h · 프롬프트 128 중 **크론 틱 94(73%)** · 4.28MB(assistant 2.2MB · tool_result 0.7MB) → ctx 402k 증류. planner#26: 4h · 49 중 틱 14 · 3.0MB. v65 master#169: 1h · 28 중 틱 9 · 1.35MB. loom#18: 2h · 41 중 틱 13 · 1.87MB. **틱마다 recv+pane 순회+보고를 세션 «안»에서 돌리니 시간당 0.75~1.3MB 가 쌓인다 — 일감이 없어도 찬다** |
| 0-2 | 쪽지 하루 2,164건(10-11 · mailbox.log.jsonl) | to: v65 master 391 · loom master 283 · **planner 238** · loom arch 177 · v65 arch 148 · cfo master 124 · feature master 122 … from: ft-tick 163 |
| 0-3 | 머리말 분포(10-11) | 머리 없음 1,067 · `[idle-detected]` 158 · `[완료·휴식]` 116 · `[HIL]` 87 · `[Seatbelt 발주]` 50 · `[정지 레디]` 20 · `[부팅 보고]` 18 · `[HIL·merge]` 13 · `[승계 발주]` 12 |
| 0-4 | planner 인박스 분류(10-11 · 222건) | ② HIL 77 · ⑥ 진행·참고 76 · ⑤ 결과 50 · ③ 판정 요청 9 · ④ 막힘 8 · 미상 2 → **planner 로 오는 것의 57%(⑥+⑤)는 쪽지일 필요가 없다** |
| 0-5 | 살아 있는 tmux 세션 85개 | 계보별: v65 arch 10 · v65 master 8 · loom arch 8 · loom master 6 · harness master 5 · cfo master 5 · planner 4 · … — 옛 좌석이 keep-last-2 를 넘겨 남아 있다(좌석 kill 은 HIL 이라 planner 큐에 쌓임) |
| 0-6 | 상태 실측 도구는 이미 있다 | `ft-board.py stalled`(v6-realtime-live/.fable-team/bin · 명부·jsonl·pane 만 읽음 · launchd `com.byz.ft-board-publish` 300초) — 지금 출력 10행(cfo arch#17 20분 · ops master#7 403분 · loom master#16 «완료 선언 미처리» 376분 …). **도구는 있는데 틱 프롬프트가 안 쓴다**. `ft_board_seat.py` 45~65행은 관측 row + now 로 분을 계산 · 109~119행은 정지 외 «완료 뒤 작업»·«완료 선언 미처리»를 따로 낸다 |
| 0-7 | 명부 교체 도구는 이미 있다 | `ft-seat-retire.sh <구> <후계>`(R43 · `_master`·`_hil_route` 등 최상위 키 일괄 교체 · 구 행 = `role=stop-ready`+`_retired_role`+`_replaced_by`) — 손으로 부를 때만 돈다 · 38행은 `open(p,'w')` 직접 쓰기(원자적 교체 아님). 수신자 검증은 0(R97 접수분) → 옛 이름으로 보낸 쪽지가 옛 세션에 쌓인다 |
| 0-8 | 팀 «열기·닫기» 도구는 없다 | STRUCTURE §2 개설 6항·종료 4항이 글로만 있다(`ls scripts/fable-team-bin \| grep team` = ft-tick-team.sh 뿐). 팀 신설 3건(ops·loom·graphics)이 전부 손 작업(명부·env·plist·좌석·BOARD 행) |
| 0-9 | 승인 게이트·닫기 게이트는 랜딩됨 | 근원 ③ = 제안서 Issue+`approved` 라벨(REVIEW §6 C 「이미 도입」 · PROPOSAL-proposal-approval-gate r1) · 근원 ④ = R102 `15b8920236`(래퍼 close 거절 → 관찰 중) |
| 0-10 | planner 입력창 주입 0 | R85 핫픽스(mbox.sh `user_facing` → doorbell 0) 적용 중 · 세션 안 감시 `ft-inbox-watch.sh` 실재(PROPOSAL-inbox-instant-no-inject ① · 판정 881) |
| 0-11 | 선례 원장은 흩어져 있다 | VERDICTS-planner-NN(판정 ~1075) · `.fable-team/state/hil-approvals.log` · `design/harness/HIL-LEDGER.md` · REQUEST-LEDGER · MERGE-QUEUE — 한 명령으로 긁는 도구 0 → 「선례를 안 찾음」(REVIEW §4 ②) |
| 0-12 | 외부 호출 | 인박스 Haiku 분류 `FT_INBOX_HAIKU_TIMEOUT` 기본 20초(7초 룰 위반 · PROPOSAL-inbox §4) · ft-board gh 조회는 gh-cache.json 경유 · **`ft-nano-close.sh` 361~373행 `_fetch_remote_feat` 의 `git fetch` 에 상한 0**(DA r0 F5) |
| 0-13 | **승계·인터뷰 baseline(시각 있는 사건 · 재현 가능 · DA r0 F6)** | ⓐ 역할 좌석 **부팅 보고** 쪽지(from = `byz-<팀>-<역할>-<agent>#N` · 본문 머리 `[부팅 보고]`/`[첫 보고]`/`[부팅]`) · mailbox.log.jsonl(.1) 창 **10-08 21:04 ~ 10-11 23:35(약 3.1일)** = **179건 / 계보 26**(v65 arch 23 · v65 master 21 · loom arch 18 · planner 16 · cfo master 13 · v65 tester 13 · harness arch 11 …) → **약 58건/일**. REVIEW 의 「4일 128회」는 추정이었고 같은 자로 재면 더 많다. ⓑ **AskUserQuestion tool_use** 사건(BYZ 프로젝트 전 세션 jsonl · tool_use id 중복 제거 · timestamp 일자) 10-08 110 · 10-09 167 · 10-10 104 · 10-11 79 = **460건/4일(115/일)**. REVIEW 의 「238줄」은 판정문 줄 수(추정) — 같은 자가 아니다 |

## 1. 근원 5 ↔ 채택안 A~D ↔ 장치 (한눈표)

| 근원(REVIEW §4) | 왜 재발하나(0 실측) | 채택안 | 장치(코드) | 규칙 문장(정본) |
|---|---|---|---|---|
| ① 승계 128회 | 팀 8이 상시 + 틱이 세션 안에서 ctx 를 먹음 + 승계 때 수신자·명부·크론 샘 | **A** | D1 `ft-team-open.sh`/`ft-team-close.sh` · D2 `ft-tick-line.sh`(틱 = 밖에서 재고 안엔 한 줄) · D3 mbox 수신자 «은퇴 좌석» REJECT | R-A 팀 수명 = 일감 단위 · R-B 틱 한 줄 · R-C 승계는 상시 3 팀만 |
| ② 오빠 질문 과다 | 되돌릴 수 있는 것까지 [HIL] · 선례 미조회 · 합치기 1건씩 | **B** | D4 mbox «planner 앞 머리» 게이트 · D5 `ft-precedent.sh`(선례 1명령) + `[결정]` 본문 lint · D6 `ft-merge-queue.sh add` | R-D [결정] = 비가역만 · R-E 되돌릴 수 있는 것 = 팀 master 결정 + 하루 묶음 · **R-H `[HIL]`(훅 차단·사람 손) 은 기존 §7 경로 그대로** |
| ③ 안 본 것이 승인 | 인터뷰가 요약+경로만 | **C** | D7 AskUserQuestion PreToolUse lint(종류별 필수 줄 · 질문 1개 · 선례 줄) · D8 상태판 ⑤ «오빠가 정할 것» 칸 | R-F 오빠께는 링크 1 + 쉬운 말 1장 · 그 칸이 비면 그날 질문 0(단 HIL·긴급은 칸에 즉시 실린다) |
| ④ 닫았는데 재발 | — R102 로 막힘 | (유지) | 신규 0 · D8 에 «관찰 중 N건» 1줄 | 변경 0(확인만) |
| ⑤ 상태·수신 거짓/누락 | 상태를 쪽지 문장으로 · 명부 손 갱신 · 알림이 입력창에 | **D** | D2(틱 = `ft-board stalled` 출력만 · 관측 시각 포함) · D9 `ft-seats-lint.sh`(tmux ↔ 명부 불일치) · D3 · D10 planner 세션 안 감시(기존 제안 ① 그대로) | R-G 상태 칸 = 실측 도구 출력 복붙만(판정 511 그대로 · 문장 금지를 «도구 출력 외 입력 불가»로) |

## 2. 장치 설계 (무엇을 코드로 · 무엇을 글로 · 정본 어디를 · 부하/메모리)

공통 원칙: ①가드는 «보내는 쪽»에서 막는다(받는 쪽 판정기·면제 목록 0 — feedback_no_gatekeeper) ②새 데몬 0 — 전부 1회 실행 스크립트 또는 이미 도는 launchd(ft-board-publish 300초) 안의 한 줄 ③설치는 «영향 0»이 증명된 순서로(§3) ④외부 호출은 7초+재시도 1 — **새 도구가 부르는 기존 도구의 원격 경로까지**(§4) ⑤**모름·실패·오래됨은 0 이 아니다** — 도구 출력에 `UNKNOWN(<이유>)` 로 드러낸다(#0 RULE).

### D1 팀 열기·닫기 한 명령 (근원 ① · A · r1 F1)
- `ft-team-open.sh <팀> --goal <GOAL 경로> --master-model <ID> [--arch <ID>] [--from <planner 좌석>]` — STRUCTURE §2 개설 6항을 순서대로 ①GOAL 파일 실재 ②`seats-<팀>.json`(없으면 템플릿 · `_hil_route`=현역 planner `_master` 값 · `_master`=**빈 값(개설 중)** · `_cards`·`_label`) ③`bin-<팀>/<팀>-env.sh`(kk 꼴 복제) ④tick plist = 상시 팀만(비상시 팀은 plist 0 — 틱은 D2 세션 크론 한 줄) ⑤master 좌석 `tmuxc open`(zsh -lc · --model 명시) + 명부 행 등록(role master · tick null) ⑥부팅 쪽지 relay(골 원문 3줄 선두 · 발주 카드 경로) → **확정 사건 ⑦: 후계 부팅 보고가 planner 큐에 도달(`ft-reach-check` 7초 창 + 1회 재확인)한 뒤에만 `_master`=그 좌석 · `_opened=<UTC>` 를 원자적으로 쓴다(tmp+rename)** → BOARD 행 «<팀> 열림 · 좌석 · 카드» 1줄. ⑦ 전에는 `_master` 가 비어 있고 D3 는 그 팀 `_master` 수신을 `UNKNOWN(개설 중)` WARN 으로 통과시킨다(planner 가 아니라 좌석 이름으로 직접 보내면 정상 경로). 각 단계 실패 = raise(앞 단계 되돌림 목록 stdout).
- `ft-team-close.sh <팀>` — **3단으로 분리(F1)**:
  - **①admission(닫기 시작 조건 · 전부 참이어야 ②로)**: CLOSEOUT 파일 실재(`design/<팀>/CLOSEOUT-*.md` 최신 · 골 원문 3줄 포함 · **커밋됨 + 배포 브랜치 원격 sha 줄 실재**) · 워크트리·나노 워크트리 전부 `git status --short` 0 · `design/<팀>/indices/진행/` 0 · **역할 좌석(master·arch·tester·DA) 전부 jsonl 턴 상태 IDLE**(`ft-seat-status.sh turn <좌석>` · WORKING 1석이라도 있으면 rc 3 `REJECT close <팀> — <좌석> WORKING(턴 끝 <ISO>) · 명부 문구·프롬프트 잔상으로 대신하지 않는다`). 거절 시 어느 항이 거짓인지 1줄 + rc 3 · 쓰기 0.
  - **②정리 실행(순서 고정 · 단계별 결과 stdout · 실패 = 그 단계에서 멈춤 rc 1 · 성공한 앞 단계는 되돌리지 않음(재실행이 이어서 함))**: 나노 `ft-nano-close.sh`(표준승인 · §4 fetch 7초) → 팀 tick plist `.disabled` + `launchctl unload`(상시 팀이 아닌데 plist 가 있으면 여기서 제거 · 어느 plist 를 지웠는지 출력) → 역할 좌석 **계보당 최근 2 보존 + 그 밖 `tmux kill-session`**(2026-07-11 표준승인 범위 · 좌석마다 CronDelete 는 그 좌석 자신의 닫기 절차 — 세션 kill 로 세션 크론은 함께 사라진다) → 명부 전 행 `role=closed`(보존 2 는 `role=stopped` + `_kept=true`) + `_closed=<UTC>` **원자적 쓰기**.
  - **③종료 검증(STRUCTURE §2 4항 = 수락 증거 · 기계 대조)**: 미커밋 0 · 명부 전 행 종결 + `_closed` · `launchctl list` 에 `com.byz.ft-tick-<팀>` 없음 · 진행 카드 0 ∧ 나노 세션 0 ∧ 보존 좌석 IDLE(재측정) → BOARD 행 «닫힘 · CLOSEOUT 경로 · 원격 sha · 보존 좌석 2» → 보존 2 좌석의 kill 계획은 `/tmp/h<N>`(R83 꼴) 1줄 출력(사람 손 · HIL 그대로 · 팀 닫힘을 막지 않음).
  - **D9 와의 규약**: `_closed` 팀의 `_kept=true` 좌석은 «의도된 보존»이라 불일치가 아니다(D9 가 그 플래그를 읽는다) · 닫힌 팀 명부는 D1 open 이 다시 열 때만 바뀐다.
- 규칙 문장(governance 신설 §11 「팀 수명 = 일감 단위」): 「상시 팀 = planner · harness · v65(완성 전까지). 그 밖(cfo·loom·ops·feature·graphics·issues)은 planner 가 일감(카드 묶음) 단위로 `ft-team-open` 으로 열고, 랜딩·CLOSEOUT(커밋·push) 뒤 `ft-team-close` 로 닫는다. 비상시 팀은 승계하지 않는다 — ctx 가 차면 CLOSEOUT 쓰고 닫고, 남은 카드는 새 열기로 간다. 닫기는 admission → 정리 → 검증 3단이고 역할 좌석이 WORKING 이면 시작하지 않는다. 이슈 처리는 issues 팀 대신 각 팀 master 가 Tank 래퍼로 직접(R102 게이트 그대로).」
- 고칠 정본: `~/.claude/skills/fable-team/references/main-team-governance.md` §1-1 표에 «수명» 열(상시/일감) + §11 신설 · STRUCTURE §2 표 «누가» 열에 도구명 + 종료 행에 「admission(좌석 IDLE 포함) → 정리 → 4항 검증」 · closeout-policy 5 「좌석 kill(nano-close 경로)」→「좌석 kill(`ft-team-close` 경로 · 보존 2 는 HIL)」 1줄.
- 부하·메모리: 1회 실행 셸+python(≤2초 · ≤30MB · 좌석 IDLE 검사 = jsonl mtime+마지막 레코드 읽기) · 데몬 0 · 비상시 팀의 launchd 틱 plist 가 **줄어든다**(지금 ft-tick-{loom,feature,ops,cfo} 4개 → 상시 3 팀만).

### D2 틱 = 밖에서 재고 안에는 한 줄 (근원 ①·⑤ · A·D · r1 F3)
- `ft-tick-line.sh <좌석>` — 출력 ≤5줄·≤500자 · **첫 줄 머리 = `TICK <좌석> @<관측 ISO> age=<초>s src=<snapshot|live>`**: ①`mbox peek` 건수(머리별) ②`ft-board.py stalled --team <내 명부>` 행(정지·완료 뒤 작업·완료 선언 미처리 전부 · 없으면 0) ③`ft-seats-lint.sh --team` 불일치 수 ④내 큐에 `[결정]`/`[HIL]`/`[긴급]`/`[합치기]`/`[정지 레디]`/`[완료]` 가 있으면 그 seq 만. 행이 5줄을 넘으면 `… 전체 <N>행 → <스냅샷 경로>` 1줄로 잘림을 드러낸다(0 으로 접지 않는다).
- **신선도 규칙(F3 · r2 재설계)**: 정지 판정의 «경계»는 스냅샷 값을 쓰지 않는다. **내 팀 명부의 역할·나노 좌석(≤8석)은 매 틱 `ft-seat-status.sh turn <좌석>` 로 라이브 측정**(jsonl 마지막 턴 끝 시각 `TURN_END_ISO` · 상태 WORKING|IDLE) → 정지 분 = `now − TURN_END_ISO` 를 **틱 시점에 재계산**(ft_board_seat 의 cell 과 같은 식 · 3분 경계). 스냅샷(launchd 300초)은 **타 팀 요약·큐 건수·관찰 중 건수 등 «개입 대상이 아닌» 정보에만** 쓰고 그 줄에 `(snapshot @ISO age=<초>)` 를 붙인다. src 칸 = `turn-live(<n>석)+snapshot@<ISO>`. 좌석 jsonl 을 못 찾거나 못 읽으면 그 좌석은 `UNKNOWN(<이유>)` 행으로 나오고 첫 줄도 UNKNOWN(「할 일 없음」 금지). 개입(ring·kill·닫기·반송) 직전 재측정은 그대로(같은 명령 1회 더).
  - DA r1 F3 반례 회귀(픽스처 `tests/harness/test_tick_line.sh`): 스냅샷 150초 IDLE·정지 행 0 → 45초 뒤 틱 = 라이브 turn 이 195초 → 정지 3분 행 **1** 출력(스냅샷 0 에 속지 않음) · 스냅샷 WORKING → 틱 때 IDLE 240초 → 행 1 · 스냅샷 IDLE 500초 → 틱 때 WORKING(새 턴 시작) → 행 0(깨우지 않음).
  - 부하 정정(DA r1 F3): 「신규 부하 0」 철회 → **틱당 좌석 jsonl 읽기 ≤8회(파일 끝 레코드 1~2KB씩 · 합 ≤100ms · 메모리 ≤20MB)** + 스냅샷 1파일 읽기. 라이브 `ft-board.py stalled` 전체 실행은 하지 않는다(폴백 경로 삭제 — 경계 재계산이 이미 라이브라 필요 없음).
- 내 팀 좌석 전부 라이브 측정 성공 ∧ 정지·완료 뒤 작업·완료 선언 미처리 0 ∧ 큐 0 ∧ 불일치 0 일 때만 한 줄 `TICK <좌석> @… turn-live(<n>) 0/0/0 — 할 일 없음`.
- BOOT 16 의 크론 프롬프트를 **이 한 명령 + 「첫 줄이 ‘할 일 없음’ 이면 그 턴은 그 한 줄로 끝낸다(보고·재측정·정리 0) · UNKNOWN 이면 recv + 수동 확인」** 로 교체. 틱 턴 상한 = 도구 1회(+UNKNOWN 시 recv 1회) + 3줄. ★틱 안에서 pane 캡처·recv --all·보고문 작성 금지★ — 할 일이 나오면 그때 recv.
- 효과 추정(0-1 기준): 틱 1회 ≈ 15~30KB → ≤2KB(출력 ≤500자 + 도구 호출 1회). 하루 144틱 × 2KB ≈ 0.3MB(지금 2~4MB). 세션 수명이 틱으로 결정되지 않게 된다(남는 것은 실제 일감 — 그건 D1 의 «일감 단위 닫기»가 받는다).
- 규칙 문장(BOOT 16 개정): 「틱 = `ft-tick-line.sh <me>` 1회. 첫 줄의 관측 시각·age 를 함께 복붙한다. ‘할 일 없음’이면 그 한 줄로 턴을 끝낸다 · UNKNOWN 은 0 이 아니다 — recv 하고 확인한다. 상태·정지 분·기다리는 것은 이 출력을 복붙한다(문장 작성 0). 좌석을 깨우거나 닫기 전에는 그 좌석만 `ft-seat-status.sh turn` 로 다시 잰다.」
- 부하·메모리: 좌석 jsonl 끝 읽기 ≤8회(≤100ms · ≤20MB) + 스냅샷 1파일 · 새 데몬 0 · ft-board 전체 collect 는 launchd 만(틱 안 0).

### D3 mbox 수신자 = 현역만 (근원 ①·⑤ · A·D · R97 흡수 · r1 F4)
- **수신 가능(deliverable) 의 정의 = 필드로 확정**: 어느 `seats*.json` 에 행이 있고 ∧ `_replaced_by` 없음 ∧ `role ∉ {closed, stopped}`. 판정표:

| 명부 상태 | mbox send/relay |
|---|---|
| 행 있음 · `_replaced_by` 있음 | **REJECT rc 3** `→ 현역 <후계>`(후계 체인 끝까지 따라가 마지막 현역 이름) · 전송 0 |
| 행 있음 · `role ∈ {closed, stopped}` | **REJECT rc 3** `닫힌 좌석(<팀> _closed=<UTC>)` · 전송 0 |
| 행 있음 · `role=stop-ready` · `_replaced_by` 없음 | WARN + 전송(정지 레디 좌석은 닫기 지시를 받을 수 있어야 한다) |
| 행 있음 · 현역 | 전송 |
| 행 없음(어느 명부에도) | WARN `미등록` + 전송(나노·외부 세션·개설 중 후계 — 지금과 같음) |
| 같은 키가 명부 2개 이상에 있음 | **REJECT rc 3** `명부 충돌 <파일들>`(authoritative 를 고르지 않는다 — master 가 정정) |
| **authoritative 명부 파싱 실패**(수신자 팀 파일 · 아래 규칙) | **REJECT rc 3** `명부 읽기 실패 <파일> — 다시 보내라`(미등록으로 접지 않는다 · fail-closed) — 단 `[HIL]`·`[긴급]` 머리는 예외(아래) |
| **다른 팀 명부 파싱 실패** | WARN 1줄(`명부 <파일> 읽기 실패 · 이 판정에는 미사용`) + 판정은 authoritative 파일로 계속 |
- **authoritative 명부 = 수신자 이름의 팀 글자로 정한 파일 하나(DA r1 F2)**: `byz-<팀>-…` → `seats-<팀>.json`(`byz-v65-`·옛 `ft-v65-` → `seats.json` · `ft-airag-`·외부 → 없음=미등록 경로). 판정표의 모든 행은 그 파일 하나에서 읽는다 — 같은 키가 다른 파일에도 있으면 «중복 키 REJECT», 다른 파일이 깨져 있으면 WARN 만. planner `_master` 해석도 `seats-planner.json` 하나에서만.
- **안전 보고 우선순위(DA r1 F2 · 무손실)**: 머리 `[HIL]`·`[긴급]` 은 **어떤 명부 상태에서도 REJECT 하지 않는다** — authoritative 파일이 깨졌거나 `_master` 를 못 읽으면 보낸 쪽이 쓴 `to` 이름 그대로 큐에 적재 + stderr `WARN 명부 미확인 — 명시 이름으로 전송` + `.fable-team/state/mbox-guard.log` 1줄. 은퇴(`_replaced_by`)가 확실히 읽히는 경우만 후계 이름으로 **자동 재지정해 전송**(REJECT 가 아니라 전달 — 안전 경로는 막지 않는다 · 로그 1줄). 복합 픽스처: planner 명부 정상 · 현역 수신자 · 다른 팀 JSON 깨짐 → 일반 쪽지 전송+WARN · `[HIL]` 전송 / planner 명부 깨짐 → 일반 쪽지 REJECT · `[HIL]`·`[긴급]` 전송+WARN / 수신자 은퇴 + `[HIL]` → 후계로 전달.
- **승계 원자성(F4)**: 순서 = ①후계 세션 열림·부팅 보고 도달 확인 → ②`ft-seat-retire.sh <구> <후계>` **1회 쓰기 = 후계 행 등록 + 최상위 route 키 전환 + 구 행 은퇴(`_replaced_by`)** — 쓰기는 tmp 파일 + `os.replace`(원자적 · 0-7 의 직접 쓰기 교체) → ③그 뒤에만 구 이름이 REJECT 된다. ①~② 사이 구 이름 발신은 기존대로 구 큐로 간다(창 = 부팅 보고 도달 ~ retire 1명령 · 승계 발주문에 「부팅 보고 받은 그 턴에 retire」 고정 · 미실행은 D9 가 다음 틱 «불일치 1»로 드러냄). `ft-role-spawn.sh`(v65) 는 도달 확인 뒤 retire 를 코드로 호출 · 손 승계(BOOT 13 템플릿)는 문장으로.
- 정본: COMM-GUIDE-BOOT 13 조항에 「옛 이름 send 는 REJECT 된다 — 후계 이름은 REJECT 줄에 있다 · 승계 = 부팅 보고 도달 → retire 1명령 → 그 뒤 옛 이름 폐기」 · `tools/comm-canonical/mbox.sh` + 시험 `tests/harness/test_mbox_guard.sh` 픽스처: 정상 승계 전/후 · 명부 쓰기 중간(깨진 JSON) · `stop-ready`/`closed`/`stopped`/`_retired_role` · 닫힌 팀 보존 좌석 · 중복 키.
- 부하: 명부 json 10개 읽기(≤50ms).

### D4 planner 앞 쪽지 = 허용 머리 집합 (근원 ② · B · r1 F2)
- `mbox.sh send|relay`: `to` == `seats-planner.json._master` 일 때 본문 첫 줄 머리가 아래 집합 밖이면 **REJECT rc 3**(reject 모드) — 집합:

| 머리 | 뜻 | 통과 조건(본문 lint) |
|---|---|---|
| `[결정]` | **비가역 판단**(사람 손 불필요 · 되돌릴 수 없음) | 필수 줄 3: `비가역: <무엇이 되돌릴 수 없나>` · `선례: 판정 <N> \| 없음(ft-precedent "<검색어>" 0건)` · `선택지: <2~3 · 추천 먼저>` |
| `[HIL]` | **기존 §7 경로 그대로**(훅·승인 창이 막은 명령 · 오빠 손이 필요한 것 · 오빠 값과 다르게 가자는 안) — 내용 무관 · 가역성 무관 | §7 의 4항(①막힌 명령 원문 ②막은 훅·사유 ③영향·되돌림 ④선택지) 중 ①②④ 줄 실재 — 없으면 **WARN 만**(전송은 한다 · 안전 경로를 머리 때문에 막지 않는다) |
| `[긴급]` | 라이브 장애 · 인증·토큰 복구 · 결제 중단 등 즉시 사람 | lint 0 · 전송 · D7·D8 같은 예외 |
| `[합치기]` | MERGE-QUEUE 행(D6) | `ft-merge-queue.sh add` 가 만든 1줄 꼴(팀·PR/브랜치·head) |
| `[정지 레디]` · `[완료]`(`[완료·휴식]` 포함) | 1줄 + 증거 줄 | `세트: … · 시험: … rc= · 이슈:` 1줄(없으면 WARN) |
| `[부팅 보고]` | BOOT 2 의 3항(+cron=) | 1줄 |
- 그 밖(진행 보고·마일스톤·참고·`[idle-detected]`·`[Seatbelt 발주]` 류)은 REJECT: `REJECT planner 앞 쪽지는 [결정]·[HIL]·[긴급]·[합치기]·[정지 레디]·[완료]·[부팅 보고] 만 — 진행·참고·마일스톤은 상태판(ft-board)이 나른다. 되돌릴 수 있고 사람 손도 안 필요한 것은 팀 master 가 선례(ft-precedent)로 결정한다(R-E).` 전환기 별칭: `[HIL·merge]`→`[합치기]` 자동 치환(2주 · 로그 1줄).
- **F2 정합**: 이 표는 governance §7(훅 차단·사람 손 = `[HIL]` 내용 무관)과 전역 하드 룰 2 를 바꾸지 않는다. B 의 「3종」 중 `[결정]` 은 «사람 손이 필요 없는 비가역 판단»이고, `[HIL]` 은 그 전부터 있던 «사람 손» 경로다 — 둘을 가역성 하나로 합치지 않는다(DA r0 F2). `[긴급]` 은 셋째 사람 경로(상태판 갱신·warn 기간·정지 레디와 무관하게 항상 통과).
- 설치 모드: 첫 7일 `FT_PLANNER_HEAD_MODE=warn`(로그 `.fable-team/state/planner-head.log` + stderr WARN · 전송은 함) → planner 가 로그로 «막혔을 쪽지» 수를 보고 `reject` 로 전환(값 1개 · `queues.conf` 키). `[HIL]`·`[긴급]` 은 어느 모드에서도 전송된다.
- 규칙 문장(governance §12 「planner 로 가는 쪽지」): B 원문 4줄 + 위 표 + 「비가역 = 실서비스 DB 구조·데이터 삭제 · 클라우드/결제 설정 · 비용 발생 · 브랜치 삭제·force push · 오빠가 준 값과 다르게 가는 것(→ `[결정]` · 단 훅이 막았거나 오빠 손이 필요하면 `[HIL]`). 그 밖은 팀 master 가 선례(D5)로 결정하고 상태판 «오늘 결정» 칸에 1줄 — planner 는 하루 1회 묶음으로 오빠께.」 · 전역 CLAUDE.md 하드 룰 13 신설(한 줄: 「최상위 오케 앞 쪽지 = [결정](비가역)·[HIL](훅 차단·사람 손 · 하드 룰 2 경로)·[긴급]·[합치기]·[정지 레디]·[완료] — 진행 보고는 상태판 · 되돌릴 수 있고 사람 손 없는 것은 묻지 않는다」) + CLAUDE_MASTER_SYNC 블록 재생성(`~/.codex/AGENTS.md`·`~/.hermes/SOUL.md` v=2026-10-12).
- 부하: 정규식 수 회.

### D5 선례 1명령 (근원 ② · B)
- `ft-precedent.sh "<검색어>" [--since 10-01]` — VERDICTS-planner-*.md(판정 줄) · hil-approvals.log · HIL-LEDGER.md · REQUEST-LEDGER.md · MERGE-QUEUE.md 를 한 번에 grep → `판정 N · 날짜 · 한 줄 · 파일:행` 표(최신 위 · ≤20행 · 넘치면 `… 전체 <N>행`). 0건이면 `0건` 1줄(그 문자열이 D4 의 `선례: 없음(…)` 에 들어간다).
- 규칙: [결정]·[HIL]·인터뷰 전 첫 수 = 이 명령(feedback_check_the_ledger_before_asking_the_human 을 도구로).
- 부하: grep 5파일(≤100ms).

### D6 합치기 큐 1명령 (근원 ② · B)
- `ft-merge-queue.sh add --team <팀> --pr <N>|--branch <b> --head <sha> --line "<한 줄>" [--blocks "<막힘>"]` — planner 워크트리의 `design/planner/MERGE-QUEUE.md` 에 행 1 추가(flock · 절대 경로 · 형식 = 지금 표 8열) + `[합치기] <팀> <PR> <head> — 큐 행 추가` 1줄 mbox(D4 통과형). `ft-merge-queue.sh list|measure` = planner 가 인터뷰 전 행마다 checks·head·CLEAN 실측(`gh pr checks` 7초+1 · 로컬 `git merge-tree`) — 실패 행은 `실측 실패(<이유>)` 로 표기(빈 값·통과 추정 0).
- 규칙: 합치기 요청은 이 명령만(손 쪽지 0) · planner 인터뷰 1회 = 큐 전체 · 「막힘」 행만 즉시(판정 1058 예외 그대로).
- 부하: 파일 append · gh 조회는 measure 때만.

### D7 인터뷰 lint 훅 (근원 ③ · C · r1 F2)
- PreToolUse(AskUserQuestion) 훅 `interview-lint.sh`(planner 세션에만 · settings.json hooks · fail-open·로그). **인터뷰 종류를 머리로 가르고 종류별 필수 줄만 본다**:

| 종류(질문 첫 줄 머리) | 필수 | 면제 |
|---|---|---|
| `[제안]`·`[이슈]`·`[합치기]` | GitHub 링크 정확히 1개(제안 Issue · 이슈 · PR/큐) · `선례:` 줄 1 · 질문 1(questions 배열 길이 1 · 물음표 1) · 본문 `#\d+` 가 있으면 각주 표(governance §4) | — |
| `[HIL]` (훅 차단·사람 손) | 막힌 명령 **원문 줄** 1 · 영향·되돌림 줄 1 · 선택지 · 질문 1 | GitHub 링크 불요 |
| `[긴급]` | 질문 1 | 링크·선례·각주 전부 면제 · 로그 1줄 |
| `[결정]` | `비가역:`·`선례:`·`선택지:` 줄(D4 와 같은 3줄) · 질문 1 | 링크 불요(있으면 1개) |
| 머리 없음 | **exit 2** `인터뷰 머리 [제안]·[이슈]·[합치기]·[HIL]·[긴급]·[결정] 중 하나` | — |
- 어긋나면 exit 2 + 어느 항인지. 훅 자체 오류(JSON 못 읽음 등)는 fail-open + `~/.claude/logs/interview-lint.log` 1줄.
- D8 과 짝: 「쉬운 말 1장」 = Issue 본문(템플릿 필수 칸 · 이미 도입) — 인터뷰는 그 링크 + 결론 1줄 + 선택지만.
- 정본: governance §2 표 «컨펌» 열에 「인터뷰 = 종류 머리 + 종류별 필수 줄 + 질문 1(훅 강제) · HIL·긴급은 링크 없이 통과」 · GUIDE-human-report 에 1줄.
- 부하: JSON 파싱 1회.

### D8 상태판 ⑤ «오빠가 정할 것» (근원 ③·④ · C · r1 F2·F3)
- `ft-board.py render` 에 ⑤ 절 추가: **HIL-LEDGER open 행 + 큐의 `[HIL]`·`[긴급]` 미처리 쪽지(즉시 · 상태판 갱신을 기다리지 않는 사람 경로 — 쪽지 자체가 planner 세션 안 감시 D10 으로 바로 뜬다)** · MERGE-QUEUE 「대기」 행 · 제안 Issue 중 `approved`·`rejected` 둘 다 없는 것(gh-cache) · `status:observing` 이슈 수(근원 ④ 확인용 1줄). **캐시가 오래됐거나(> 600초) 실패면 그 줄은 `(캐시 <시각> · 미확인)` 이고 ⑤ 칸을 「없음」으로 접지 않는다**. 전부 0 이고 전부 신선할 때만 `오빠가 정할 것: 없음 — 오늘 질문 0`. 슬랙 뉴스(`--slack`)와 term 둘 다.
- 규칙(governance §12): 「매일 쉬운 말 뉴스의 ⑤ 칸이 비면 그날 오빠 질문 0 — 칸에 없는 질문은 하지 않는다. 단 `[HIL]`·`[긴급]` 은 칸과 무관하게 그 즉시 planner 가 올린다(§7).」
- 부하: 기존 collect 안 파일 3개 더 읽기 · gh 는 캐시(7초+1 · 300초 1회).

### D9 명부 lint (근원 ⑤ · D · r1 F1·F4)
- `ft-seats-lint.sh [--team <명부>]` — tmux ls ↔ seats*.json 대조: ⓐ살아 있는 세션인데 명부 행 없음(**`_closed` 팀의 `_kept=true` 보존 좌석은 제외**) ⓑ`_master`/`_hil_route` 가 가리키는 좌석이 죽음·은퇴·`closed/stopped`(개설 중 빈 `_master` 는 `OPENING` 표기 · 불일치 아님 · 단 `_opened` 없이 30분 넘으면 불일치) ⓒrole 활성인데 세션 없음 ⓓ계보당 살아 있는 세션 > 2(keep-last-2 초과 · kill 후보 목록 → `/tmp/h<N>` 계획) ⓔ같은 키가 명부 2개 이상 ⓕ명부 파싱 실패(`UNKNOWN <파일>` — 0 이 아님). 출력 = `불일치 N (UNKNOWN M)` + 행. D2 틱 줄에 N·M 이 실린다 → 0 이 아니면 그 틱에 master 가 정정(ft-seat-retire 또는 행 추가 · 닫힌 팀 보존 좌석은 «살리지» 않는다).
- 규칙(governance §8 에 1줄): 「명부 정정은 틱 줄의 불일치 N 이 0 이 될 때까지 그 틱에 — 보고에 N 을 쓴다. 닫힌 팀의 보존 좌석은 불일치가 아니다.」
- 부하: tmux ls + json 10개(≤100ms).

### D10 planner 세션 안 감시 (근원 ⑤ · 기존 제안 ① 유지)
- PROPOSAL-inbox-instant-no-inject ①(ft-inbox-watch.sh + Monitor · 입력창 주입 0) 그대로 — 이 PLAN 은 변경 0. D4 로 planner 앞 쪽지가 238→약 40/일로 줄면 감시 알림도 그만큼 준다. Haiku 분류 상한 20→7초+재시도 1 은 §4 에 포함(코드 1줄).

## 3. 설치 순서 · «지금 마감 중인 팀을 멈추지 않는다» 증명

| 단계 | 설치물 | v65·loom·graphics 영향 | 시점 |
|---|---|---|---|
| S1 읽기 전용 도구 | D5 precedent · D9 seats-lint · D2 tick-line(스냅샷+라이브 폴백) · D8 render ⑤ · D6 list/measure | 0 — 아무 전송·파일도 안 바꿈. 기존 틱·쪽지 경로 무변경 | 즉시(DA⑥ 뒤) |
| S2 열기·닫기 | D1 team-open/close(+ nano-close fetch 7초 1 hunk) | 0 — 호출될 때만 동작 · 지금 열린 팀은 호출 0. 첫 사용 = 다음에 planner 가 여는 팀 / 마감 끝난 팀 닫기 | 즉시 |
| S3 mbox 가드 | D3 은퇴 수신자 REJECT · D4 planner 머리(**warn 모드**) | D3: 옛 이름으로 보내는 쪽지만 막힘(지금도 «죽은 큐»로 가던 것 — 막히는 편이 낫다 · REJECT 줄에 후계 이름 · 파싱 실패 REJECT 는 재시도 1줄) · D4 warn: 전송은 그대로 + 로그 · `[HIL]`·`[긴급]` 은 어느 모드든 전송 | 즉시(warn) |
| S4 D4 reject 전환 · D7 인터뷰 훅 · BOOT 16 교체 | planner `queues.conf` 키 1개 · settings.json hooks 1행 · BOOT 1조항 | 마감 중인 팀의 `[HIL]`·`[HIL·merge]`·`[정지 레디]`·`[완료]` 는 통과형이라 영향 0. 진행 보고형만 막힌다 → **v65·loom·graphics 정지 레디 뒤** 또는 warn 로그에 그 세 팀 발신이 7일간 0 이면 그 전이라도 | 그 팀들 정지 레디 뒤 |
| S5 정본 갱신 | governance §1-1 열·§11·§12 · §2 컨펌 열 · §7 1줄(`[결정]`·`[긴급]` 과의 경계) · §8 1줄 · STRUCTURE §2 · closeout-policy 5 · BOOT 13·16 · 전역 CLAUDE.md 하드 룰 13 + SYNC 2곳 v=2026-10-12 · GUIDE-human-report 1줄 | 글 — 0 | S4 와 같은 묶음(선복사 규칙) |

되돌림: 각 도구는 신규 파일(삭제 = 되돌림) · mbox.sh·ft-nano-close.sh·ft-seat-retire.sh 는 `.bak-networking-<ts>` · BOOT/governance 는 `.bak` + 키트 revert · settings.json hooks 1행 제거.

## 4. 7초 룰 적용 지점 (판정 666 · 하드 룰 12 · r1 F5 — 간접 호출 포함)

| 호출 | 지금 | 이 PLAN |
|---|---|---|
| 인박스 Haiku 분류 `claude -p` | 20초 | `FT_INBOX_HAIKU_TIMEOUT=7` + 재시도 1(코드 기본값 변경 · PROPOSAL-inbox §4 그대로) |
| **`ft-nano-close.sh` `_fetch_remote_feat` `git fetch`(361~373행 · D1 close 가 간접 호출)** | 상한 0 | `timeout 7 git fetch …` + 재시도 1 · 실패 = 기존 `bad+=` 그대로(닫기 거절 · 성공으로 접지 않음) — N2 카드 1 hunk |
| D6 measure `gh pr checks`/`gh pr view` | — | `timeout 7` + 재시도 1 · 실패 = 행에 `실측 실패` 표기(폴백 값 0) |
| D8 제안 Issue 라벨 조회 | gh-cache | 캐시 갱신 시 `timeout 7`+1 · 실패 = 캐시 유지 + `(캐시 <시각> · 미확인)` 표기 |
| D1 team-open 의 `tmuxc open`·도달 확인 | — | 로컬(tmux·jsonl) — 외부 호출 아님 · 도달 확인 `ft-reach-check` 7초 창 + 1회 재확인 |
| D2 라이브 폴백 `ft-board.py stalled` | — | 로컬(jsonl·pane) · gh 는 캐시만(갱신 0) |
| 600/300 초 | 0 발견 | — |

## 5. DA 사전검증 — 소환 «예» (bounded · da-codex#1)

- r0 HOLD #76217(원인군 6) → r1 78da81d284 → **r1 HOLD(2회째) #76265**: F1·F4·F5 교정 확인 · 남은 F2(D3 우선순위)·F3(D2 경계 재계산)·F6(§9 불변 분류) 3건 → r2 반영(위 머리말).
- **2 HOLD 도달 → bounded 규칙대로 연속 검토 중단.** 3차 1회는 planner 허가(판정 1060 선례 · 「F 문장만 · 10+10분 · 다시 HOLD 면 arch Fable 5.1 r4」) — master#29 경유 `[허가 요청]` 1통. 3차 범위 = **DA r1 이 남긴 F2·F3·F6 문장만**(D1·D4 전체 재검토 0 · 새 경계 0).

## 6. 카드 분할 (나노 ≤5 · master 집행 · 전부 origin/main 기준 · 한 번에 하나)

| 카드 | 내용 | 시험(빨강 먼저) | 닫는 증거 |
|---|---|---|---|
| N1 `r-net-tick-line` | D2 ft-tick-line(스냅샷 age·라이브 폴백·UNKNOWN·잘림 건수) + D9 ft-seats-lint(ⓐ~ⓕ · `_kept`·OPENING) + D8 render ⑤(HIL·긴급 즉시 · 캐시 미확인 표기 · 관찰 중 1줄) | `tests/harness/test_tick_line.sh` 픽스처: 신선 스냅샷 0행 → ‘할 일 없음’ · 오래된(>120s) 스냅샷 → src=live · 스냅샷 없음+라이브 실패 → UNKNOWN · 6행 → 5행+잘림 줄 · 닫힌 팀 보존 좌석 → 불일치 0 · 깨진 명부 → UNKNOWN | 틱 1회 출력 실측 ≤5줄 · 첫 줄에 @ISO·age · 틱 뒤 좌석 jsonl 증가 ≤4KB(0-1 대비) |
| N2 `r-net-team-open-close` | D1 두 명령(open ⑦ 확정 사건 · close 3단 · 좌석 IDLE 검사 · 원자 쓰기) + `ft-nano-close.sh` fetch `timeout 7`+1(1 hunk) + `ft-seat-retire.sh` tmp+replace(1 hunk) | 임시 리포 + 가짜 tmux/launchctl 스텁 · admission 각 항 거짓 rc 3(특히 역할 좌석 WORKING 픽스처) · 정리 중 실패 → 재실행 이어서 · 검증 4항 · fetch 실패 → 닫기 거절 | 다음에 여는 팀 1건이 `ft-team-open` 1명령으로 열리고(`_master` 확정 사건 로그 + BOARD 행) · 마감 끝난 팀 1건이 `ft-team-close` 3단 로그로 닫힘(보존 2 `_kept` · kill 계획 /tmp/h) |
| N3 `r-net-mbox-guard` | D3 수신 가능 판정표 7행(REJECT·WARN·fail-closed) + D4 허용 머리 표(warn/reject 키 · `[HIL]`·`[긴급]` 상시 통과 · `[결정]` 3줄 lint · `[HIL]` 4항 WARN · `[HIL·merge]` 별칭) | `tests/harness/test_mbox_guard.sh` 명부 픽스처(승계 전/후 · 깨진 JSON · stop-ready/closed/stopped · 중복 키 · 닫힌 팀 보존) × 머리별 rc | 은퇴 이름 send 가 REJECT+후계 이름 · 깨진 명부 REJECT · `[HIL]` 전송 100% · planner 앞 쪽지/일 ≤60(7일 평균 · 0-2 238 대비) |
| N4 `r-net-precedent-queue` | D5 ft-precedent + D6 ft-merge-queue add/list/measure(실측 실패 표기) + Haiku 7초 | 원장 픽스처 grep · 큐 append flock 2중 호출 · measure gh 스텁 실패 → `실측 실패` | [결정] 쪽지 100% 에 `선례:` 줄 · MERGE-QUEUE 행이 손 쪽지 0 으로 쌓임 |
| N5 `r-net-interview-hook` | D7 interview-lint.sh(종류 6 · 종류별 필수 줄) + settings.json 등록(planner 세션 한정 · 키트 templates/hooks 사본) | 훅 입력 JSON 픽스처 8종(머리 없음 · 제안 링크 0/2 · HIL 원문 줄 0 · 긴급 · 결정 3줄 · 질문 2 · 정상) | planner 인터뷰 1건 실측 = 머리 + 필수 줄 + 질문 1 · `[HIL]` 인터뷰가 링크 없이 통과 |
| (arch 초안 · master cp+cmp) | §3 S5 정본 글 | `ft-version.sh check`(BOOT sha) · `wc -c`(전역 한도) | 정본 7곳 sha + SYNC v=2026-10-12 두 파일 |

순서: N1 → N3(warn) → N2 → N4 → N5 → S4 전환 + S5 글. N1·N3 만으로 0-1(틱 ctx)·0-7(옛 이름 큐) 두 재발 자리가 닫힌다.

## 7. 결정이 필요한 것 → master#29 [결정] 0건

가정으로 진행(오빠 「그래」 = A~D 채택 · 판정 1069·1070): ①v65 는 «완성 전»이라 상시(REVIEW §6 A 원문) ②보존 2 좌석 kill 은 기존 HIL 그대로(새 승인 요청 0) ③D4 는 warn 7일 뒤 reject(planner 값 1개 · 오빠 인터뷰 0) ④`[HIL]`·`[긴급]` 통과는 기존 하드 룰 2·governance §7 의 유지이지 새 값이 아니다. 이 넷 중 어느 것도 오빠 값과 다르게 가는 안이 아니다. 설치 S4 시점만 §3 의 «정지 레디 뒤 또는 7일 0건» 조건으로 자동 결정.

## 8. 닫는 증거 (이 PLAN 단위 · CLOSEOUT 에 복붙할 줄)

- DA APPROVE 쪽지 seq + 이 파일 sha · 카드 N1~N5 랜딩 sha 5개 · 정본 7곳 sha · SYNC v=2026-10-12
- 숫자 3(설치 7일 뒤 재측정 · 같은 스크립트 · 측정 정의는 §9): 승계(①-b · 같은 계보 선행 부팅 있음)/일(50 → ≤3) · planner 앞 쪽지/일(238 → ≤60) · 오케 좌석 틱 1회당 jsonl 증가(15~30KB → ≤4KB)

## 9. 효과 측정 칸 (판정 1073·1075 · r1 F6 — 시각 있는 사건 · 같은 창 · 같은 명령)

| 숫자 | 사건 정의(중복 제거 · 시각 = 사건 자체의 ts) | 정리 전 baseline(실측 · 0-13) | REVIEW 의 추정값(참고 · 같은 자 아님) | 정리 후(설치 7일 뒤 · 같은 명령 · 4일 창) | 목표 |
|---|---|---|---|---|---|
| ①-a raw 부팅 | **역할 좌석 부팅 보고 쪽지** = mailbox.log.jsonl(+.1) 행 중 `from` ~ `^(byz|ft)-[a-z0-9]+-(master|arch|da|tester|pm|checker)-[a-z]+#\d+$` ∧ `body` ~ `^\s*(\[(byz|ft)[^\]]*\]\s*)?\[?(부팅 보고|첫 보고|부팅)\b` · 같은 from 은 1건 · 창 = 쪽지 ts | **180건 / 3.1일(10-08 21:04~10-11 23:45) · 계보 26 → 58/일** | 「4일 약 128회」(명부 `_replaced_by` 수 · 추정) | (빈 칸) | — (분모) |
| ①-b 승계 | ①-a 중 **같은 계보(`#N` 뗀 이름)의 선행 부팅이 같은 불변 로그 창 안에 있는 것**(ts 오름차순 · 계보 첫 부팅은 «분류 불가»로 따로 센다 · 현재 명부·`_opened` 같은 가변 값은 쓰지 않는다 — DA r1 F6) | **154건 / 3.1일 = 50/일 · 계보 첫 부팅 26(분류 불가)** | — | (빈 칸) | ≤ 3/일 |
| ①-c 개설 | `ft-team-open`/`ft-team-close` 가 쓰는 **append-only** `.fable-team/state/team-events.jsonl`(`{ts, team, event: open|close, seat, by}` · 수정·삭제 0 · 재개도 새 open 행) 의 open 행 수 | 0(도구 설치 전 · baseline 없음 — 사후만) | — | (빈 칸) | 일감 수와 같음(목표 아님 · 분모) |
| ② 오빠 인터뷰 | **AskUserQuestion tool_use 사건** = BYZ 프로젝트(`~/.claude/projects/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents*`) 전 세션 jsonl 의 assistant 레코드 `tool_use.name=="AskUserQuestion"` · `tool_use.id` 로 중복 제거 · timestamp 일자 | **460건 / 4일(10-08 110 · 10-09 167 · 10-10 104 · 10-11 79) = 115/일** | 「238줄」(판정문 «오빠 인터뷰» 줄 수 · 추정) | (빈 칸) | ≤ 15/일 · 그중 `[합치기]` ≤ 1/일(묶음) |
| ③ planner 앞 쪽지 | mailbox.log.jsonl 행 중 to = 현역 planner `_master`(그날 명부 값) · 1행 1건 | 238/일(10-11) | — | (빈 칸) | ≤ 60/일 |

- 로그 회전·명부 재생성에 흔들리지 않는 이유: ①-a·①-b·②·③ 모두 사건 자체에 ts 가 있고(쪽지 ts · jsonl timestamp · team-events ts) 상태 파일 개수·현재 명부 값·`_opened` 를 세지 않는다 — **baseline 과 사후 집계는 같은 정규식·같은 분류 규칙(위 표 문구)으로만 돈다**(`ft-measure-net.sh` 가 그 문구를 코드로 고정 · N1 카드 · 시험 = 이 표의 baseline 숫자 재현). mailbox.log 가 회전해도 `.1` 까지 읽으면 4일 창이 들어온다(지금 span 10-08 21:04~ · 더 오래 보관하려면 N1 카드에서 `ft-measure-net.sh` 가 4일 창 집계를 `.fable-team/state/measure/<날짜>.json` 으로 매일 스냅샷 — 새 데몬 0 · board-publish launchd 안 1줄).
- 측정 주체 = harness master(틱 밖 · 1회 명령) · 결과는 이 표에 기입 + CLOSEOUT 「닫는 증거」에 복붙. 목표 미달이면 D1~D9 중 어느 장치가 안 먹었는지 §0 실측을 같은 스크립트로 다시 떠서 1회 보정(새 장치 추가 0). baseline 이 «추정»인 값(REVIEW 128·238)과는 비교하지 않는다 — 효과 선언은 0-13 실측 baseline 대비로만.
- **정리 끝난 뒤 복귀 지점 1줄**: 이 PLAN 의 CLOSEOUT 뒤 하네스는 `[정지 레디]` → planner 는 v65 골 **K4**(`design/v65/20260910/LIST-v65-lst-completion-MERGED.md` §0 · «사용자 최우선 · 미해결» · v65 master#169 015 긴 녹음 판독)로 복귀 — 하네스 좌석은 열어 두지 않는다(승계 0 · 재개는 버그·요청 때 CLOSEOUT 읽고 새 좌석).

## 변경 이력
- r0 2026-10-11 23:1x arch#29 · 커밋 ca65722ee1 · §9 보충 a3e7056358(판정 1073·1075)
- r1 2026-10-11 23:5x arch#29 · DA r0 HOLD #76217 F1~F6 반영(0-7·0-12·0-13 실측 추가 · D1 3단 · D3 판정표 · D4 머리 표 · D7 종류 표 · D8 즉시 경로 · D9 `_kept` · §4 fetch · §9 재정의) · 커밋 78da81d284
- r2 2026-10-12 00:0x arch#29 · DA r1 HOLD(2회째) #76265 F2·F3·F6 반영(D2 라이브 turn 경계 재계산 + 부하 정정 · D3 authoritative 명부·안전 보고 우선순위 · §9 ①-a/①-b/①-c 분리 + 정규식 + team-events.jsonl) · 3차 DA 는 planner 허가 대기 · 커밋 sha 는 master 보충
