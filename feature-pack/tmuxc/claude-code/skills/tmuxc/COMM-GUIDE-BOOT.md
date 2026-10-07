# COMM-GUIDE-BOOT — 부팅 필수 14줄 (이것만 읽으면 통신 가능)

> 전문 `COMM-GUIDE.md`(40KB ≈ 20k 토큰)는 **읽지 않는다**. 필요한 절만 아래 매핑표의 줄 범위로 `Read(offset, limit≤200)`.
> 전문 Read·cat·큰 limit 은 PreToolUse 훅(`boot-read-gate.sh`)이 막는다. (하네스 0.4 단위 5 · GOAL-harness-v2 축 A)
> 매핑표 기준 전문: COMM-GUIDE.md sha256 앞16 = `d64777274c4b371a` (2026-09-23). 전문이 바뀌면 이 값과 줄 범위를 같이 갱신한다 — 대조는 `ft-version.sh check`(단위 2).

1. **Serena**: `initial_instructions` 를 먼저 1회 호출해 `session_id` 를 받은 뒤 `activate_project(project="<현재 워크트리 절대경로>", session_id=…)` (이름 아님 · `get_current_config` 먼저 부르지 말 것 · session_id 없이 부르면 `Field required` 로 실패한다 — 2026-09-23 두 좌석 실측). 미노출이면 재시작 말고 grep 진행 + 보고에 「Serena 미사용」 명시.
2. **부팅 첫 보고 3항(+1)**: 세션명 / 모델+창 크기(`[1m]` 여부) / Serena 가부 (+ master·architect·DA·pm 은 i-have-adhd 로드 여부) — mbox 로 오케에 발신 전엔 착수하지 않는다. ★오빠에게 가는 글(pane·슬랙·인터뷰)은 GUIDE-human-report 틀(결론→할 일→바뀐 것→근거) · mbox 는 예외.★
3. **발주(오케→좌석)** = 본문은 mbox 파일 큐 + 창엔 `[발주 #seq] … recv …` 지시문 한 줄. **보고(좌석→오케)** = mbox. 도달 판정은 pane capture 가 아니라 jsonl 층(`ft-reach-check.sh`). ★재발주는 `{mbox} ring <좌석> <최초 seq>` — 다시 send 하면 좌석이 같은 발주를 2건 본다(pending=2 실측). 발주 뒤 3초에 busy 확인, 안 돌면 ring.★
4. **mbox**: `{mbox} send {to} {me} "본문"`(3~5줄 · 700자 넘으면 수신측 절단+전문경로) · `{mbox} recv {me}`(READ 라인을 화면에 인용) · `{mbox} peek {me}` · 긴 내용은 `{mbox} relay {to} {me} <파일> "요약"`. `{mbox}` 경로는 주입문의 것을 쓴다. 알림 여부는 seats.json 의 tick 유무가 정한다(`--no-notify` 는 무시·경고만, 급하면 `--urgent`). 진행보고는 mbox 가 아니라 파일에. **master 로는 두 가지만**: 집행 요청(커밋·push·좌석 개설) · 사람 판정이 필요한 것. fan-out 금지(한 값은 한 좌석) · 답 안 받은 상대에게 겹쳐 보내지 않는다.
5. **메시지 포맷**: `[{from}->{to}] 내용` — 화살표는 ASCII `->` 만.
6. **tmux 폴백**(mbox 없을 때만): `-l` 과 `Enter` 는 반드시 별도 호출 · 전송 뒤 §2 Step4 도달검증(3회 실패면 화면에 경고) — 「보냈다」≠「도착했다」.
7. **금지**: prefix 없는 메시지 · 옵션모드/미제출 입력 잔류 상태로 send-keys · **agent 미실행 pane 에 send-keys(§2 Step1 HARD GATE: `pgrep -P <pane_pid>` 0건이면 send 금지)** · 작업 중 pane 에 Escape. `❯ 텍스트` 잔류는 고스트 서제스천일 수 있다 — Enter 를 보내지 마라.
8. **「안 보내고 대기」 금지(§1.05)**: 회신·질문은 mbox `send` 로 «마쳐야» 완료. 「대기」 선언 전 peek + 상대 pane + 자기 입력줄 제출 3확인. ★**하위 좌석은 AskUserQuestion 금지**(2026-09-25 오빠) — 사용자가 그 pane 을 못 본다. 사람 판정은 mbox `[HIL]` 로 최상위 오케(메인 팀은 `_hil_route` 의 현역 planner)에 올리고 오케가 인터뷰를 띄워 값으로 내려보낸다.★
9. **i-have-adhd**: master·architect·pm·DA 기본 탑재 · implementer·tester·checker·analyst 는 로드 금지.
10. **버전 정합**(tester·checker, press 전 필수 §4c): worker/gateway/frontend 기동시각 > 최신커밋 · redis 컨테이너+잔여키 keep/flush 명시. hot reload 불신.
11. **설계·판정(§4b)**: 하네스 금지 · DA approve loop — architect 가 설계+DA 소환 여부 · DA 는 반박 게이트 · checker 는 승인 뒤 확인. 산출물은 tracked 경로에.
12. **cmd(Command Code) 세션**이면 「Command Code 특이사항」 절만 추가로 Read(부팅 3항이 다름 · `cmd status` 크레딧 확인 · 턴 중 입력을 삼킨다).
13. **좌석 이름·수신자 확인**(2026-10-07): 신규·승계 좌석 이름 = `byz-<팀>-<역할>-<에이전트>#N`(메인 팀 오케 역할 = `master` 통일 · 번호는 옛 번호 이어받음 · 검사 `ft-name-lint.sh <이름>`). ★승계로 이름이 바뀌므로 발신 전 `ft-harness-info.sh seats` 로 «현역 이름»을 확인한다★ — 옛 이름으로 보낸 쪽지는 옛 세션에 쌓인다(실측: planner arch#3→master#4). 정본 `~/.claude/skills/fable-team/references/main-team-governance.md`.
14. **하네스 조회**: 어디에 뭐가 있는지 모르면 먼저 `bash <루트>/scripts/fable-team-bin/ft-harness-info.sh map`(정본 목차 1장) · `rules`(정본 실재) · `seats`(라이브 좌석+이름 lint) · `requests`(하네스 요청 원장) · `find 키워드`. 이슈 처리는 **오빠 컨펌 전 착수 0**(진입로 3 · 컨펌 경로 = planner 인터뷰 · 하위 좌석은 `[HIL]` 로 올림) — 상세는 위 정본 §2.
15. **master 손 = 집행뿐**(2026-10-07 오빠 「코드를 왜 너가 작업해」): master 가 하는 것 = 랜딩·커밋·push·좌석 개설/닫기·명부·원장 기록·검증된 파일의 설치 복사(cp+cmp). ★코드·시안·카드 증거 줄은 직접 편집 0★ — 코드=나노 · 시안·설계=arch · 나노 증거 REJECT=그 나노에 반송(닫힌 나노면 재spawn). 게이트가 안 막아도 같다. 정본 `references/main-team-governance.md` §6.

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
