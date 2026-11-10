# COMM-GUIDE-BOOT — 부팅 필수 19줄 (이것만 읽으면 통신 가능)

> 전문 `COMM-GUIDE.md`(40KB ≈ 20k 토큰)는 **읽지 않는다**. 필요한 절만 아래 매핑표의 줄 범위로 `Read(offset, limit≤200)`.
> 전문 Read·cat·큰 limit 은 PreToolUse 훅(`boot-read-gate.sh`)이 막는다. (하네스 0.4 단위 5 · GOAL-harness-v2 축 A)
> 매핑표 기준 전문: COMM-GUIDE.md sha256 앞16 = `d64777274c4b371a` (2026-09-23). 전문이 바뀌면 이 값과 줄 범위를 같이 갱신한다 — 대조는 `ft-version.sh check`(단위 2).

1. **Serena**: `initial_instructions` 를 먼저 1회 호출해 `session_id` 를 받은 뒤 `activate_project(project="<현재 워크트리 절대경로>", session_id=…)` (이름 아님 · `get_current_config` 먼저 부르지 말 것 · session_id 없이 부르면 `Field required` 로 실패한다 — 2026-09-23 두 좌석 실측). 미노출이면 재시작 말고 grep 진행 + 보고에 「Serena 미사용」 명시. ★codex 좌석(`--agent codex`)은 Serena 고정 옛 판이라 session_id 가 없다 — `initial_instructions`·`get_current_config` 없이 `activate_project(project="<워크트리 절대경로>")` 만 부른다. 도구 출력이 CCR 참조로 접혀 보이면 `headroom_retrieve` 로 원문을 받는다(헤드룸 압축 · 2026-10-09 R66)★
2. **부팅 첫 보고 3항(+1)**: 세션명 / 모델+창 크기(`[1m]` 여부) / Serena 가부 (+ master·architect·DA·pm 은 i-have-adhd 로드 여부) — mbox 로 오케에 발신 전엔 착수하지 않는다. ★오빠에게 가는 글(pane·슬랙·인터뷰)은 GUIDE-human-report 틀(결론→할 일→바뀐 것→근거) · mbox 는 예외.★
3. **발주(오케→좌석)** = 본문은 mbox 파일 큐 + 창엔 `[발주 #seq] … recv …` 지시문 한 줄. **보고(좌석→오케)** = mbox. 도달 판정은 pane capture 가 아니라 jsonl 층(`ft-reach-check.sh`). ★재발주는 `{mbox} ring <좌석> <최초 seq>` — 다시 send 하면 좌석이 같은 발주를 2건 본다(pending=2 실측). 발주 뒤 3초에 busy 확인, 안 돌면 ring.★
4. **mbox**: `{mbox} send {to} {me} "본문"`(3~5줄 · 700자 넘으면 수신측 절단+전문경로) · `{mbox} recv {me}`(READ 라인을 화면에 인용) · `{mbox} peek {me}` · 긴 내용은 `{mbox} relay {to} {me} <파일> "요약"`. `{mbox}` 경로는 주입문의 것을 쓴다. 알림 여부는 seats.json 의 tick 유무가 정한다(`--no-notify` 는 무시·경고만, 급하면 `--urgent`). 진행보고는 mbox 가 아니라 파일에. **master 로는 두 가지만**: 집행 요청(커밋·push·좌석 개설) · 사람 판정이 필요한 것. fan-out 금지(한 값은 한 좌석) · 답 안 받은 상대에게 겹쳐 보내지 않는다.
5. **메시지 포맷**: `[{from}->{to}] 내용` — 화살표는 ASCII `->` 만.
6. **tmux 폴백**(mbox 없을 때만): `-l` 과 `Enter` 는 반드시 별도 호출 · 전송 뒤 §2 Step4 도달검증(3회 실패면 화면에 경고) — 「보냈다」≠「도착했다」.
7. **금지**: prefix 없는 메시지 · 옵션모드/미제출 입력 잔류 상태로 send-keys · **agent 미실행 pane 에 send-keys(§2 Step1 HARD GATE: `pgrep -P <pane_pid>` 0건이면 send 금지)** · 작업 중 pane 에 Escape · `❯` 뒤 잔류 글자에 Enter(→ 17).
8. **「안 보내고 대기」 금지(§1.05)**: 회신·질문은 mbox `send` 로 «마쳐야» 완료. 「대기」 선언 전 peek + 상대 pane + 자기 입력줄 제출 3확인. ★**하위 좌석은 AskUserQuestion 금지**(2026-09-25 오빠) — 사용자가 그 pane 을 못 본다. 사람 판정은 mbox `[HIL]` 로 최상위 오케(메인 팀은 `_hil_route` 의 현역 planner)에 올리고 오케가 인터뷰를 띄워 값으로 내려보낸다.★
9. **i-have-adhd**: master·architect·pm·DA 기본 탑재 · implementer·tester·checker·analyst 는 로드 금지.
10. **버전 정합**(tester·checker, press 전 필수 §4c): worker/gateway/frontend 기동시각 > 최신커밋 · redis 컨테이너+잔여키 keep/flush 명시. hot reload 불신.
11. **설계·판정(§4b)**: 하네스 금지 · DA approve loop — architect 가 설계+DA 소환 여부 · DA 는 반박 게이트 · checker 는 승인 뒤 확인. 산출물은 tracked 경로에.
12. **cmd(Command Code) 세션**이면 「Command Code 특이사항」 절만 추가로 Read(부팅 3항이 다름 · `cmd status` 크레딧 확인 · 턴 중 입력을 삼킨다).
13. **좌석 이름·수신자 확인**(2026-10-07): 신규·승계 좌석 이름 = `byz-<팀>-<역할>-<에이전트>#N`(메인 팀 오케 역할 = `master` 통일 · 번호는 옛 번호 이어받음 · 검사 `ft-name-lint.sh <이름>`). ★승계로 이름이 바뀌므로 발신 전 `ft-harness-info.sh seats` 로 «현역 이름»을 확인한다★ — 옛 이름으로 보낸 쪽지는 옛 세션에 쌓인다(실측: planner arch#3→master#4). 정본 `~/.claude/skills/fable-team/references/main-team-governance.md`. ★옛 이름(명부에 `_replaced_by`·`closed`·`stopped`)으로 보낸 쪽지는 mbox 가 REJECT 하고 REJECT 줄에 후계 이름을 적는다 · 승계 = 후계 부팅 보고 도달 → `ft-seat-retire.sh <구> <후계>` 1명령(등록+route+은퇴 원자 교체) → 그 뒤 옛 이름 폐기 · `[HIL]`·`[긴급]` 은 명부 상태와 무관하게 전송된다(판정 1079 · PLAN-harness-networking D3)★
14. **하네스 조회**: 어디에 뭐가 있는지 모르면 먼저 `bash <루트>/scripts/fable-team-bin/ft-harness-info.sh map`(정본 목차 1장) · `rules`(정본 실재) · `seats`(라이브 좌석+이름 lint) · `requests`(하네스 요청 원장) · `find 키워드`. 이슈 처리는 **오빠 컨펌 전 착수 0**(진입로 3 · 컨펌 경로 = planner 인터뷰 · 하위 좌석은 `[HIL]` 로 올림) — 상세는 위 정본 §2.
15. **master 손 = 집행뿐**(2026-10-07 오빠 「코드를 왜 너가 작업해」): master 가 하는 것 = 랜딩·커밋·push·좌석 개설/닫기·명부·원장 기록·검증된 파일의 설치 복사(cp+cmp). ★코드·시안·카드 증거 줄은 직접 편집 0★ — 코드=나노 · 시안·설계=arch · 나노 증거 REJECT=그 나노에 반송(닫힌 나노면 재spawn). 게이트가 안 막아도 같다. 정본 `references/main-team-governance.md` §6.
16. **체크 크론 = 부팅 보고 직후 · 틱 = 밖에서 재고 안에는 한 줄**(2026-10-07 오빠 「크론 이관받았어? 못받았으면 버그」 · 원장 R13 · 2026-10-12 판정 1079 PLAN-harness-networking D2 — 실측: 오케 좌석 ctx 의 73% 가 틱이었다): master·planner·arch 좌석(신규·승계 전부)은 부팅 보고를 보낸 그 턴에 `CronCreate` 10분 틱을 건다 — ★없으면 착수 0★. ★틱 프롬프트 = `bash <FT_BIN>/ft-tick-line.sh <me>` 1회뿐★: 첫 줄(`TICK <me> @<ISO> src=turn-live(<n>)+snapshot@<ISO> …`)이 「할 일 없음」이면 그 한 줄로 턴을 끝낸다(보고·재측정·정리 0) · `UNKNOWN` 은 0 이 아니다(recv + 확인) · 상태·정지 분·기다리는 것은 그 출력을 복붙한다(문장 작성 0) · 좌석을 깨우거나 닫기 «직전» 그 좌석만 `ft-seat-status.sh turn` 로 다시 잰다 · 틱 안에서 pane 캡처·`recv --all`·보고문 작성 금지(할 일이 나오면 그때 recv). 크론은 세션 종속이라 승계로 «옮겨지지 않는다»(launchd 뉴스 틱 `ft-tick` 과 별개). 부팅 보고에 `cron=<job id>` 를 적고, 받는 오케는 그 칸이 비면 그 턴에 되묻는다. 닫는 세션은 `CronDelete` 후 닫는다.
17. **고스트 서제스천 = 메인 지침**(2026-10-07 오빠 「심각하네 그거 서제스천인데 … 착각하지 마라」 · 원장 R21): 남의 pane `❯` 뒤에 남은 글자 = 자동완성 제안이다. ★사용자 입력·미제출 명령으로 착각 금지★ — 그 줄을 근거로 보고·인터뷰·Enter 0. 좌석 상태 판단 근거는 jsonl 이력(`ft-reach-check.sh`)과 `✻ … done` 줄뿐. 유휴 좌석을 깨울 땐 Escape 1회 → `{mbox} ring`(작업 중 pane 은 Escape 금지 · 7). 전역 `~/.claude/CLAUDE.md` 하드 룰 10 과 같은 문장.
18. **상태 칸 = 실측 · 정지 3분 = 그 턴에 처리**(2026-10-08 오빠 「전팀 절대 구라 없어야한다」 · 판정 511): 좌석 상태는 `ft-seat-status.sh turn`(jsonl)·`✻ … done` 줄·프로세스만 근거 — 쪽지 문장 복사 금지. 멈춘 좌석은 「정지 N분 · 기다리는 것 = <좌석> 의 <값>」으로 쓰고, 3분 넘으면 그 턴에 깨우기·닫기·다음 발주·HIL 확인 중 하나 — 경계는 7·17 그대로. master·planner 본업 = 자기 하위 좌석 이 감시(정본 main-team-governance §8).
19. **골을 끝내면 멈추고 다음 일은 묻는다**(2026-10-08 오빠 「골을 줬으면 끝내고 놀아」 · 판정 514): 받은 골을 끝낸 좌석은 상위 1단에 머리 `[완료·휴식]` 1통(끝났음 + 증거 줄 `세트: <40hex> · 시험: … rc=<n> · 이슈: …` + 다음 일 요청)을 보내고 쉰다(완료 조건 충족 = 그 턴에 증거 줄 + 발신 · 미루면 ② — 판정 532) — 그 뒤 파일·커밋·press 0, 틱·ring 에는 `[완료·휴식 유지 #seq]` 1줄만. jsonl IDLE ∧ 그 토큰 ∧ 증거 줄(sha 실재) 셋이 다 있는 좌석만 18 의 깨움 대상에서 빠진다 — 토큰만 있으면 그대로 18 이다. 끝난 단위에 추가 확인·재측정·옛 인계서 승계·스스로 정한 다음 일 0. 받는 쪽은 그 틱에 닫기 또는 큐의 다음 발주, 큐가 비면 planner → 오빠께 묻는다(정본 governance §9). (tester·checker·press 산출은 turbopack 칸(`:3001/_next/mcp get_errors`) 없으면 미완 — 판정 522.)
20. **측정 금지 2가지 = 오빠 절대지침**(2026-10-09 오빠 「임의 레디스랑 말풍선 dom 밀어넣기를 절대 하지 말라는걸 하고있지?」 · 판정 · 원장 R63): tester·checker·press·나노 전 좌석 — ★임의 Redis 쓰기(redis-cli SET/HSET 등 직접 주입)와 말풍선 DOM 주입(재생 하네스·`/dev/bubble-replay`·`appendChild`)으로 만든 결과는 증거가 아니다(무효 후보)★. 측정은 trusted 클릭(CDP `Input.dispatchMouseEvent`) + 기존 e2e 러너(`tests/e2e/realtime_multi_e2e.py`)의 «실제 음성 경로»로만. 격리 Redis 픽스처 시험(`isolated_redis_server`)은 별개. 이미 그 방식을 썼다면 상위에 `[HIL]` 로 «쓴 키·주입 경로·회차·그 결과로 낸 판정» 을 올린다.
21. **외부 호출 시간 상한 = 7초 룰 기본값**(2026-10-09 오빠 「600초 절대 안된다 앞으로도 600 300 초가 보이면 그냥」「넘기지말고 7초룰」 · 판정 666 · 전역 하드 룰 12): 외부 호출(LLM·임베딩·STT·HTTP·DB 원격)의 시간 상한은 ★기본 1회 7초 + 재시도 1회★(`shared/config/external_call.py` `EXTERNAL_CALL_TIMEOUT_S=7.0`·`MAX_RETRIES=1`). 설계·코드·리뷰·DA 어디서든 600 s·300 s(SDK 기본값 포함)가 보이면 넘기지 않고 그 단위 안에서 7초 룰로 바꾼다 — 묻지 않음 · 판정 대기 0.
22. **비밀 파일 내용 출력 0**(2026-10-09 오빠 판정 676 · 시험 계정 비밀번호가 arch 좌석 jsonl 에 1회 노출): 조사·진단 중 `secrets/`·`*.cred`·토큰 파일은 «키 이름·존재·크기»만 확인한다 — `cat`·`awk`·`grep -v` 로 줄 전체를 화면에 찍지 않는다(값은 세션 기록에 영구 잔류). 확인이 필요하면 `cut -d= -f1`·`wc -c`·`test -s` — ★JSON cred 는 `=` 가 없어 `cut -d= -f1` 이 줄 전체를 찍는다(arch#24 노출 원인) → `python3 -c 'import json,sys;print(list(json.load(open(sys.argv[1]))))' <파일>` 로 키 이름만★.
23. **운영 계정 토큰 = 사람에게 복사를 청하지 않는다**(2026-10-09 오빠 「토큰 안된다 매번 이렇게 멍청하게 해야되냐」 · 판정 675): 만료되면 `bash <루트>/.fable-team/bin/ft-op-token.sh <email>` 로 새로 받는다(출력 `OK <email> exp=… file=…` · 실패 `ERR …`). cred 가 없으면(`exit 2`) `--init <email>` 1회만 사람 손(클립보드 비밀번호) — 그 뒤는 도구가 매번 발급. 토큰·비밀번호 원문은 화면·로그·쪽지에 쓰지 않는다 — 좌석 조사·시험에서 secrets/·*.cred·토큰 파일 내용 출력 0, 키 이름·존재·크기만(`cut -d= -f1` · `wc -c` · `test -s`). ★JSON cred 는 `=` 가 없어 `cut -d= -f1` 이 줄 전체를 찍는다★ → `python3 -c 'import json,sys;print(sorted(json.load(open(sys.argv[1]))))' <파일>` 로 키 이름만.

## 절 → 전문 매핑표 (COMM-GUIDE.md · 줄 = Read offset · «BOOT» 열은 조항 단위: 그 절의 «읽기 전에 실행되는 계약» 이 위 12줄에 본문으로 실렸는가)

| 절 | 줄 | HARD | BOOT (조항 단위) |
|---|---|---|---|
| Serena 활성화 | 8–31 | | O(1) |
| Command Code 특이사항 | 33–61 | | 포인터(12) — 계약 아님 |
| i-have-adhd | 63–71 | | O(9) |
| §1 채널 선택 · #seq · ring 재발주 · 3초 busy | 73–99 | HARD | O(3): 채널·ring·3초 전부 실림 |
| jsonl 도달판정 | 101–107 | HARD | O(3) |
| §1.05 안 보내고 대기 금지 · 3확인 | 109–117 | HARD | O(8) |
| §1.1 mbox 명령·규약 | 119–155 | | O(4): 명령 5종 · notify 규칙 · READ 인용 |
| §1.5 발신 규율 5조항 | 157–199 | HARD | O(4): fan-out 금지 · 3~5줄 · 진행보고 파일 · master 두 가지 · 연속 발신 자제 — 5/5 |
| relay 정본 절차 | 201–219 | HARD | O(4): relay 명령. EMPTY_SUMMARY 는 코드 강제 |
| §0 보냈다≠도착했다 | 221–235 | | O(6) |
| §1 메시지 포맷 | 237–254 | | O(5) |
| §2 검증 송신 4스텝 · Step1 HARD GATE | 256–297 | HARD | O(6·7): 별도 호출 · 도달검증 · pgrep 게이트 |
| §3 수신 · §4 보고 · §4a 파일 우선 | 299–330 | | O(4) |
| §4b DA approve loop | 332–359 | | O(11) |
| §4c 버전 정합 | 361–401 | | O(10) |
| §5 금지 요약 | 403–411 | | O(7) |

★HARD 6곳 전부 조항 단위 O(DA-harness-0.4-unit5 r1 발견 2 반영: §1 ring·3초, §1.5 master 두 가지·연속 발신, notify 규칙 추가). BOOT 밖에 남은 «읽기 전에 실행되는 계약» 이 생기면 이 표에 X 를 적는다 — X 가 곧 경보다.★
