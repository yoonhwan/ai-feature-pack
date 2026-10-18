# DESIGN — 슬랙 = 읽기 전용 공유판 · 결정 건은 «현역 세션 이름»으로 안내 (오빠 발주 · master#17 #64368 · byz-harness-arch-claude#16 · 2026-10-08)

## 골 원문 (GOAL-harness 복붙)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: A(오빠 요청 즉시 검토) + C(배포 발행(슬랙) 업그레이드·반영).

## 오빠 원문
「거기서 자꾸 답하라는데 어차피 들을것도 아니고 반영될것도 아니니 작업상황·이슈보고·변경내용·상태를 공유하고 hil이나 인터뷰가 있으면 정확히 어느 세션으로 가거나 플래너 정확한 세션을 알려주는 공유를 중점으로」

## §1 실측 — 슬랙으로 나가는 메시지 (origin/main `scripts/harness-install/slack-mirror/` = 라이브 `~/.hermes/scripts/` cmp 같음 · 채널 C0C6MJGRR89 #byz-planner)
| # | 종류 | 생성 위치 | 트리거 |
|---|---|---|---|
| 1 | mbox 보고·HIL·BLOCK 카드 | `byz_mbox_slack_mirror.py:_row:122-146` → `mirror_lib.format_row:181-192` · `resume_block.mirror_block:71-74` | launchd 5초 · planner 앞 행만 |
| 2 | 스레드 루트 | `mirror_lib.root_text:173` | 1과 같음 |
| 3 | 기록 공백 | `byz_mbox_slack_mirror.py:format_gap:27-30` | 1과 같음 |
| 4 | 질문 보드(채널 1개 · 제자리 갱신) | `mirror_questions.py:render_board:117-127` · `BOARD_HEAD:19` | 미러·inbound |
| 5 | GitHub 이슈·PR 열림·닫힘·머지·hil | `byz_github_slack_mirror.py:FACT:27` · `_item:45-60` | launchd 30초 |
| 6 | inbound 알림·되묻기 | `byz_slack_mbox_inbound.py:73-77,91,94` · `mirror_plan.py:26,29` | launchd 10초 |
| 7 | 아침 매거진 뿌리 글·실패·경고·재첨부 | `magazine_slack.py:root_text:40-48` · `failure_text:51-53` · `eli5_warning_line:34-37` · `magazine_reattach.py:23-25` | launchd 매일 08:00 |
| 8 | 제안서 뿌리 글·rN | `byz_proposal_publish.py:text_of:81-83` | 수동 CLI |
| 9 | 단위 스레드 시작·진행·결과 | `byz_thread_post.py:80,95,125` · 호출 `ft-index-move.sh:48-72` | 카드 이동 |
범위 밖(이번 설계에서 손대지 않음): 휴면 3종(`byz_zion_post_fanin_guard.py` · `byz_issue_watch_safety.py` · `byz_work_monitor_safety.py` — 스케줄 없음) · 제품 운영 웹훅 2종(`scripts/ops/credit-burn-notify.sh` · `expire-alert-notify.sh`) · 개인 cron.

## §2 답장 요구 문구 (실측 13 · 전부 고친다)
| 문구 | 위치 | 종류 |
|---|---|---|
| `답하는 법: 이 스레드에 한 줄로 답해 주세요 (질문 Q{seq})` | `mirror_questions.py:54` | 1 HIL |
| `…답하는 법: 이 스레드에 번호나 한 줄로 답해 주세요 (질문 Q{seq})` + `1) …` 선택지 | `mirror_questions.py:55` | 1 HIL |
| `답을 기다리는 질문 N건` · `답 전달됨, 좌석 확인 대기 N건` | `mirror_questions.py:19,126-127` | 4 보드 |
| `Q{n} 질문이 이 스레드에 없어요 — 열린 질문 번호를 확인해 주세요` | `mirror_plan.py:26` | 6 |
| `질문이 여러 개 열려 있어요 — 「Q질문번호 답」 형태로 다시 답해 주세요` | `mirror_plan.py:29` | 6 |
| `판정이 필요해요 — 전문을 확인해 주세요` | `mirror_lib.py:187` | 1 |
| 요약 프롬프트 「HIL이면 질문·판정 요청을 todo에 반드시 쓴다」(자유 문장 → 「답해 주세요」 류 생성) | `mirror_summary.py:26` | 1 |
| `오빠 판정이 필요해요(hil:needed 라벨)` | `byz_github_slack_mirror.py:27` | 5 |
| 블록 `다음: 오빠 판정` | `resume_block.py:74` · `byz_github_slack_mirror.py:58` | 1·5 |
| `<@U..> 오빠 할 일이 N건 있어요` · 블록 `다음: 오빠 할 일 N건` | `magazine_slack.py:45` · `magazine_block.py:20` | 7 |
| 요약 프롬프트 「오빠가 결정할 것 1개」 | `magazine_summary.py:25` | 7 |
| `오빠가 결정할 것: …` · 블록 `오빠 결정 — …` | `byz_proposal_publish.py:82,166` | 8 |
| 멘션 `<@U..>` 자체(모든 HIL 카드) | `mirror_lib.py:188` | 1 |

## §3 실측 결함 — 결정 자리가 «낡은 이름»
- inbound 수신자 = 명부 `_hil_route`(`mirror_inbound.py:50-57`). 라이브 값: seats-harness·loom·ops = `byz-planner-master-claude#11` · seats-feature·issues = `#12` · planner 명부 `_master` = **#12**(현역). → 하드코딩 값이 승계마다 낡는다(R43 의 retire 도구도 «같은 파일의 같은 값»만 바꾼다).
- HIL 카드의 「담당」 = 질문 올린 좌석(`from`) — 결정을 받는 planner 이름은 카드에 없다(`resume_block.py:73`).
- 영향 실측: 10-04 이후 slack→mbox 전달 3건뿐(`mailbox.log.jsonl` from=slack-oppa) — 오빠 원문 「어차피 들을 것도 아니고」와 일치.

## §4 새 틀 (문구 규칙 · 모든 종류 공통)
1. **첫 줄 머리표 4개 중 하나**: `[작업상황]` · `[이슈보고]` · `[변경내용]` · `[상태]`. 매핑: 1 mbox 보고 = `[작업상황]`(HIL·BLOCK 이면 `[이슈보고]`) · 2 루트 = 머리표 없이 지금대로 · 3 기록 공백 = `[상태]` · 4 보드 = `[상태]` · 5 GitHub 열림 = `[이슈보고]` · 머지·닫힘 = `[변경내용]` · 7 매거진 = `[상태]` · 8 제안서 = `[작업상황]` · 9 시작·진행 = `[작업상황]` · 결과 = `[변경내용]`.
2. **답장 요구 0**: §2 의 13 문구 삭제·대체. 슬랙 스레드에 답하라는 안내·번호 선택 안내·`Q{n}` 표기를 내보내지 않는다. 선택지가 있으면 `선택지(참고): 1) … 2) …` 로만 싣는다(답하는 법 줄 0).
3. **결정 필요 건 = 자리 안내 1줄**: `결정 자리: <현역 planner 세션 이름> (그 세션이 인터뷰를 띄웁니다) · 질문 올린 좌석: <from>`. GitHub hil·매거진 «할 일»·제안서 «결정할 것» 도 같은 줄. 멘션 `<@U..>` 는 이 줄이 있는 메시지에만 남긴다(알림은 받되 답은 세션에서).
4. **현역 이름 자동 조회(하드코딩 0)** — 공용 함수 `live_planner()` 1개(`mirror_lib.py`): `<루트>/.fable-team/seats-planner.json` 의 `_master` 를 읽고 `tmux has-session -t =<이름>` 로 살아 있는지 확인. 살아 있으면 그 이름 · 아니면 `결정 자리: 확인 불가(planner 명부 _master=<값> 세션 없음) — 하네스 master 에 알림` 을 그대로 싣는다(조용한 대체 이름 0 · #0 RULE). `_hil_route` 는 읽지 않는다(§3). 호출 때마다 조회(캐시 0 · 메시지 빈도 5초~매일이라 부하 무시 가능 — tmux 호출 1회).
5. **inbound 수신자도 같은 함수**(`mirror_inbound.py:50-57`): 슬랙 새 글·답글 전달 대상 = `live_planner()`. 확인 불가면 전달 0 + 채널에 `[상태] 전달 못 함 — planner 현역 세션 확인 불가` 1줄(지금 `:91` 문구 꼴). inbound 데몬 자체는 유지(끄기는 오빠 판단 — 아래 §6).
6. **보드**: 제목 `[상태] 결정 대기 N건 — 결정 자리: <현역 planner>` · 행 = `키 요지 (분)` 그대로 · 「답 전달됨, 좌석 확인 대기」 행은 `planner 전달됨 N건` 으로.
7. 요약 프롬프트 2곳(`mirror_summary.py:26` · `magazine_summary.py:25`): 「질문·판정 요청을 todo 에」 → 「결정이 필요하면 무엇을 정해야 하는지 한 문장 · 답하라는 요청 문장 금지」.

## §5 구현 단위 (카드 1장 · 나노 1)
- 고칠 파일(정본 `scripts/harness-install/slack-mirror/` · 라이브 `~/.hermes/scripts/` 설치는 master): `mirror_lib.py`(live_planner · format_row 머리표·결정 자리 줄·멘션 조건) · `mirror_questions.py`(format_options · 보드) · `mirror_plan.py`(되묻기 2문구 → `[상태]` 안내) · `mirror_inbound.py`(수신자) · `mirror_summary.py` · `resume_block.py`(`다음:` 줄) · `byz_github_slack_mirror.py`(FACT·블록) · `byz_mbox_slack_mirror.py`(format_gap 머리표) · `magazine_slack.py`·`magazine_block.py`·`magazine_summary.py` · `byz_proposal_publish.py` · `byz_thread_post.py`(머리표).
- 시험(새 `tests/harness/test_slack_readonly_share.sh` · 네트워크·슬랙 API 0 · 함수 직접 호출): ①13 문구 전부 출력에 0(grep 단언: `답하는 법`·`답해 주세요`·`다시 답해`·`Q[0-9]` 질문 표기·`확인해 주세요`) ②종류별 첫 줄 머리표 ③HIL 카드에 `결정 자리: <가짜 명부 _master>` · 가짜 tmux 스텁으로 «살아 있음»/«없음» 두 경우(없음 = 확인 불가 문구 · 대체 이름 0) ④`_hil_route` 가 다른 값이어도 `_master` 를 씀 ⑤멘션은 결정 자리 줄이 있는 메시지에만 ⑥inbound 수신자 = live_planner · 확인 불가 = 전달 0 ⑦기존 `tests/harness/test_slack_mirror_signature.sh`·`test_index_move_slack.sh`·`test_magazine_plist.sh`·`test_proposal_register*.sh` PASS.
- 랜딩 뒤 master: 라이브 `~/.hermes/scripts/` cp + cmp · launchd 미러 3종(mbox·github·inbound) 재기동 · 매거진은 다음 08:00 에 반영 · 실측 1건(새 HIL 카드 1개 문구 캡처).

## §4-r2 DA r1 HOLD 교정 (Q1·Q2·Q3 · Q4 APPROVE) — §4·§5 와 다르면 이 절이 이긴다

### A. 표시 경계 검사(Q1) — 프롬프트가 아니라 «내보내기 직전» 결정적 검사
- `mirror_lib.share_guard(s) -> str | None`: 답장 요구 정규식 `REPLY_ASK`(`답해\s*주|답장|회신해\s*주|답을\s*(주|달)|댓글|번호(나|로)?\s*답|이\s*스레드에\s*(답|한\s*줄)|reply`, 대소문자 무시)에 걸리면 None.
- 적용 지점(우리가 쓰는 줄 전부): `format_row` 의 what·todo(요약 성공 경로) · `first_sentence(text)`(요약 실패 경로 · `mirror_lib.py:184`) · 매거진 요약 줄(`magazine_summary.py` LLM 3줄) · 제안서 `결론`·`오빠가 결정할 것` 값 · GitHub 제목은 제외(원문 제목 = 사실).
- None 일 때 결정적 대체: what → `first_sentence(text)` 를 다시 검사 → 또 None 이면 `원문 요약 생략 — 아래 전문 참고` · todo → HIL 이면 `정할 것: 전문 참고` · 아니면 줄 생략. 대체 사실은 줄 끝 `(요약 문구 교정)` 1개로 표시(조용한 교정 0).
- 전문 인용 블록(`format_full` · `mirror_lib.py:143-148`)은 «원문 보존» 예외: 머리 줄을 `전문(원문 그대로 · 이 스레드는 답을 받지 않습니다)` 로 바꾸고 본문은 손대지 않는다.
- `magazine_summary.deterministic_lines`(`:63-68`) 3번째 줄 → `팀 쪽지는 N건이고, 결정 대기는 M건이에요 — 결정 자리: <live_planner>`.
- §5 시험에 추가: 요약 성공(가짜 LLM 이 「이 스레드에 답해 주세요」 출력) → 교정 표시 · 요약 실패 + 원문 첫 문장이 답장 요구 → 대체 문구 · 전문 블록 원문 보존 + 머리 줄 · 매거진 결정적 줄.

### B. inbound 원문 유실 0(Q2)
- 수신자는 «이름»이 아니라 «역할»로 저장: `plan()` 의 `recips` 에 planner 대신 표식 `@planner`(질문 좌석·추정 좌석 이름은 지금대로 이름). 이름 결정은 `_deliver` 가 «매 패스» `live_planner()` 로 한다 — 승계 뒤 미전달 건도 현역에게 간다.
- `live_planner()` 반환 = `(이름 | None, 사유)` · 사유 5종 구분: `명부 없음` · `JSON 오류` · `_master 없음` · `tmux 실행 실패` · `세션 없음`.
- `@planner` 가 None: 그 수신자 «건너뜀(done 아님)» · `_notice(e, "planner_missing_notified", "[상태] 오빠 글 전달 대기 — planner 현역 세션 확인 불가(<사유>) · 원문 보관됨")` 1회(같은 사유면 중복 0) · 항목은 unfinished 유지(지금 원장이 plan 을 deliver «전»에 저장 · `byz_slack_mbox_inbound.py:125-135` 의 미완료 독립 재개 그대로).
- 전달 표식: `done["@planner"] = <보낸 이름>` · 토큰 `slack:{ts}:@planner`(이름 아님) → 승계로 이름이 바뀌어도 `marker_seen` 이 «이미 보낸 건»을 찾는다(옛 이름 큐까지 검사 — 시도 기록 `attempt["@planner"]` 에 보낸 이름 목록).
- 빈 수신자 방지: `recips` 가 비면 finished 금지 + `[상태] 오빠 글 수신자 0 — 원문 보관됨` 알림(`all([])` 참 결함 · `:104-113`).
- 되묻기 2문구(`mirror_plan.py:26,29`) 삭제: 번호 없음·여러 질문이면 되묻지 않고 `@planner` 에 원문 그대로(질문 번호 해석 실패 사실을 본문 1줄로) — 슬랙에 질문을 되던지지 않는다.
- §5 시험에 추가: planner 사유 5종 각각 → 전달 0·unfinished·알림 1회 · 다음 패스 현역 생김 → 그 이름으로 1회 전달 · 첫 시도 뒤 승계(이름 변경) → 중복 전달 0(토큰 기준) · recips 빈 경우 finished 0 · 원문 바이트 보존.

### C. 머리표 행렬(Q3) — 예외 없음
| 종류 | 첫 줄 머리표 |
|---|---|
| 1 mbox 보고 · BLOCK · HIL | 보고 `[작업상황]` · BLOCK·HIL `[이슈보고]` |
| 2 스레드 루트 `#N 시작 — …` | `[작업상황]` (예외 삭제) |
| 3 기록 공백 | `[상태]` |
| 4 질문 보드 | `[상태]` |
| 5 GitHub 열림 · hil | `[이슈보고]` · 머지·닫힘 `[변경내용]` |
| 6 inbound 알림(전달 대기·막힘·가득 참·수신자 0) | `[상태]` |
| 7 매거진 뿌리 · 실패 · 재첨부(`magazine_reattach.first_line`) | `[상태]` (쉬운 판 경고는 본문 줄이라 머리표 없음) |
| 8 제안서 뿌리 · rN | `[작업상황]` |
| 9 단위 시작·진행 · 결과 | `[작업상황]` · `[변경내용]` |
- 중복 방지 호환: 첫 줄 «정확 일치»로 기존 글을 찾는 4곳(`magazine_slack.find_first_line:56` · `find_root:63` · `find_reply_first_line:94` · 호출 `byz_proposal_publish.py:97,121` · `byz_thread_post.py`)은 비교 전에 양쪽에서 머리표 `^\[(작업상황|이슈보고|변경내용|상태)\] ` 를 떼고 비교(`mirror_lib.strip_head`) — 개편 전에 올라간 글도 찾아 재발행 0.
- §5 시험에 추가: 9종 + 실패·재첨부·inbound 알림 첫 줄 머리표 단언 · 머리표 없는 옛 첫 줄과 새 첫 줄이 같은 글로 찾아짐(가짜 history).

### A-r3 (DA r2 Q1 잔여) — 검사 정규식 완결
`REPLY_ASK` 에 `확인해\s*주` · 표시용 질문 번호 `(?<![A-Za-z0-9])Q\d+(?!\d)` 추가(§2 13문구 전부를 한 정규식이 덮는다). ★`\bQ\d+\b` 금지(arch#17)★ — 파이썬 유니코드에서 한글도 `\w` 라 `Q3에`·`질문Q3` 의 경계가 안 잡힌다. 오탐(분기 표기 `Q4` 등)은 유실이 아니라 `(요약 문구 교정)` 표시 + 전문 원문 보존이라 수락. 시험 반례: 가짜 요약 `{"what":"전문을 확인해 주세요","todo":null}` → 교정 · 요약 실패 + 원문 첫 문장 「…확인해 주세요」 → 대체 문구 · `Q3` · `Q3에 대해` · `(질문Q12)` 표기 → 교정 · `Q` 단독·`FAQ3`(앞 영문) → 통과.

### B-r3 (DA r2 Q2 잔여) — 기존 원장 미완료 건 이관
`run_pass` 의 미완료 재개 직전(`byz_slack_mbox_inbound.py:125-126`) 1회 이관: 항목 `recips` 중 이름이 planner 팀 접두 `byz-planner-` 로 시작하는 것(★`_master` 계보 일치 아님 — planner 는 `byz-planner-arch-claude#3 → byz-planner-master-claude#4` 처럼 역할명까지 바뀐 실측이 있어 계보 일치는 옛 원장을 놓친다 · arch#17★ · 다른 팀 질문 좌석·추정 좌석은 접두가 달라 혼동 0 · planner 좌석이 질문 좌석이었던 건도 현역 planner 로 가는 것이 맞다)을 `@planner` 로 바꾸고, 그 이름의 `done`·`attempt` 를 `done["@planner"]`·`attempt["@planner"]`(보낸 이름 목록에 옛 이름 포함)로 옮긴다. 이미 done 이면 재발송 0. `marker_seen` 은 새 토큰 `slack:{ts}:@planner` 와 옛 토큰 `slack:{ts}:<옛 이름>` 둘 다 본다. 시험 fixture: «옛 이름 pending 원장 → 새 현역 1회 전달» · «옛 이름 첫 시도 뒤 crash(attempt 1·marker 있음) → 재발송 0» · «옛 이름 첫 시도 뒤 crash(marker 없음) → 현역 1회» · 질문 좌석 이름은 이관 0.

### D. 파일 목록 추가(Q4 조건)
§5 목록에 `byz_slack_mbox_inbound.py`(`_deliver` 역할 수신자·빈 수신자) · `magazine_reattach.py`(first_line) · `magazine_slack.py` 의 find 3함수 · `byz_proposal_publish.py`·`byz_thread_post.py` 의 첫 줄 생성 추가. 설치·launchd 재기동은 master 단계 유지.

## §6 범위 밖 · 오빠 판단 후보
- inbound 데몬 끄기(슬랙 글을 아예 안 받기) — 지금은 유지(되돌릴 수 있는 쪽). 끄면 slack-oppa 경로·질문 저장소가 같이 쉬어야 함.
- 질문 저장소(`byz_slack_questions…json`) 폐기 — 유지(보드가 씀).

## §7 DA 질문 (사전 1회 · 10+10분)
- Q1 13 문구 외에 «답하라»로 읽히는 출력이 남는가(LLM 자유 문장 포함)?
- Q2 `live_planner()` 의 «확인 불가» 처리가 #0 RULE(조용한 대체 0)과 맞고, inbound 전달 0 이 메시지 유실로 이어지지 않는가(보관·재시도 필요?)?
- Q3 머리표 매핑이 오빠 4분류(작업상황·이슈보고·변경내용·상태)를 빠짐없이 덮는가?
- Q4 단위 크기(13파일 · 나노 1)가 적정한가 — 쪼개야 하면 어디서?

## §8 판정 496 — 뉴스 = 팀 요약 표 + 완성 트리 + 세션 트리 + 큐 (byz-harness-arch-claude#17 · v421-board 델타)

### 오빠 원문 (20:3x · 20:4x · master#17 #64447)
「뉴스 공유시 메인팀 현재 상황과 메인팀 큐를 같이 정리 공유. 개편.」 · 「기획에 물어봐 뉴스 트리와 세션과 큐를 정리공유하는 개편 / da도 같이」
골의 축: A(모니터 — 오빠에게 공유) + C(배포 발행(슬랙)). 범위(master): 뉴스 = ①완성 트리(골 축별) ②세션 트리(메인 팀 좌석·상태) ③큐(팀별 다음 순서) · 슬랙·pane 공통 · ft-news-tick ⑥ 관계 정리 · DA 필수.

### 8-1 실측
| 사실 | 값 | 근거 |
|---|---|---|
| 이미 있는 설계 | 판정 421 상태판 `ft-board.py` — 팀 트리(현역 좌석만) · 작업큐 · 오늘 판정표 · `render --term/--slack` 같은 dict · `snapshot` | 카드 `design/teams/harness/indices/대기/v421-board.md` · 설계 `design/teams/harness/DESIGN-news-tree-workqueue-viz-20261009.md` · DA N3 APPROVE · 오빠 컨펌 430·431 |
| 그 카드의 선행 | 나노 1 판정 원장 · 나노 4 인박스 — 둘 다 `완성/` (main b8275bf997 #929) → 지금 착수 가능 | `design/teams/harness/indices/완성/v430-verdict-ledger.md` · `완성/v425-master-inbox.md` |
| 발행 | 판정 421 나노 3 `v423-publish-report-hooks`(대기) — `ft-board-publish.sh` · 랜딩 뒤 master 가 ft-news-tick 호출부 교체 | `design/teams/harness/indices/대기/v423-publish-report-hooks.md:35,63` |
| ⑥ 지금 | `ft-news-tick.sh:48` 기본 원본 = `design/v65/NEWS-TREE.md` «하나» · `ft-news-tree.py:151` 요약본은 ✅ 가지 통째로 뺌 · 전체 = `FT_NEWS_FULL=1`(오빠 10-01) | `scripts/fable-team-bin/ft-news-tick.sh:47-49` |
| v421 에 «없는» 것 | ①완성 트리(골 축별) — v421 은 NEWS-TREE 상태 글자 읽기를 금지(손 상태 ⓓ-3)해서 축별 트리 칸이 없다 · ②팀 한 줄 요약 표 — planner#12 가 지금 손으로 쓰는 「8팀 × 지금 하는 것 · 큐 · 오빠 할 일」(#64440) | v421 카드 금지 줄 |
| 카드에서 축을 뽑을 수 있나 | ★없다★ — `## 골좌표` 절은 거의 전부 있으나(feature 17/17 · loom 21/21 · ops 23/23 · v65 732/734 · harness 82/83) 축 표기 형식이 팀마다 다름(`M4 /` · `단위 =` · `「①…」` · `축 =` · `골의 축: A`) · `골의 축:` 줄은 harness 83 만 | 카드 폴더 9개 python 실측 |
| 팀 NEWS-TREE | 있음 4팀(cfo · kk · planner · v65) · 없음 5팀(harness · feature · issues · loom · ops) · planner 트리 = 손 상태 글자 다수 + `[idx:]` 4줄 · v65 = `[idx:]` 24줄 | 워크트리 실측 |
| cfo 카드 폴더 | 명부 `_doc` = `design/cfo/indices/` 인데 루트·v6-realtime-live 에 없음 · `c-level-planning` 등 워크트리에만 → `_cards_wt` 기입 때 master 확인 | `ls` 실측 |

### 8-2 안 — v421 dict 에 두 칸을 «더하고» 렌더 순서를 고정한다 (입력 원장 추가 0 · 명부 키 1개 추가)
**⓪ 팀 요약 표 (맨 위 · 오빠 원문 「메인팀 현재 상황과 메인팀 큐를 같이」)** — 명부 1개 = 1행. 열 = 팀(`_label`) · 지금(진행 카드 수 + 첫 1장 제목 · 그 좌석 상태) · 큐(대기 카드 수 + 상위 1장 제목) · 오빠 할 일(그 팀 판정 open ∧ oppa_todo 수) · 결정 자리(현역 planner 이름 — 슬랙 공유판 `live_planner` 와 같은 규칙: `seats-planner.json` `_master` + tmux 생존 · 아니면 «확인 불가(사유)» · 대체 이름 0). 입력은 v421 `collect()` dict 그대로(새 입력 0). planner 의 손 표를 대체한다.

**① 완성 트리 (골 축별)** — 명부 새 키 `_tree`(그 팀 NEWS-TREE.md 의 `_cards_wt` 기준 리포 상대 경로). 읽는 것은 «구조»만: 들여쓰기 · 줄 글 · `[idx:<카드>]`.
- 상태 = `[idx:]` 줄만 그 팀 `_cards` 폴더에서(완성 ✅ · 진행 🔄 + 좌석 · 대기 ⏳ · 없음 `카드 없음`).
- `[idx:]` 없는 줄 = 제목(축·묶음 이름) — ★손 상태 글자(`[✅]` 등)는 읽지 않고 렌더에서 지운다★(v421 ⓓ-3 유지). 손 글자가 있던 줄 끝에는 `(카드 미연결)` 을 붙인다 — 그 표시가 남는 한 그 팀 트리는 «손 상태»가 섞여 있다는 경보다.
- 축 = 트리 최상위 줄. 카드에 축 필드를 새로 강제하지 않는다(카드 734장 이관 0 · 8-1 실측대로 형식이 달라 기계 추출 불가).
- `_tree` 없는 팀 = `완성 트리 미지정` 1줄(빠지지 않음). 5팀 트리 작성은 각 팀 master 몫(카드 밖 · 축 제목 = 그 팀 GOAL 축 표 복붙 + 진행·대기 카드 `[idx:]`).
- 요약(기본) = 축 줄은 항상 보임 · 그 아래 ✅ 는 `완성 n(마지막 1장 제목)` 으로 접음 · 🔄⏳ 는 행 상한(축당 5) 안에서. `--full` = 상한 해제 + ✅ 펼침.

**② 세션 트리 = v421 팀 트리 그대로**(현역만 · 옛 좌석 0). **③ 큐 = v421 작업큐 그대로.** **④ 오늘 판정표 = v421 그대로.**

**렌더 순서(term·slack 공통 · 같은 dict)**: ⓪ 팀 요약 표 → ① 완성 트리 → ② 세션 트리 → ③ 큐 → ④ 오늘 판정표. 슬랙 렌더 첫 줄 = `[상태] 메인팀 보드 <HH:MM>` · 답장 요구 문구 0 · `결정 자리:` 줄 1개(슬랙 공유판 §4-r2 규칙과 같음 — 같은 정규식 검사를 렌더 끝에 1회).

### 8-3 ft-news-tick ⑥ 와의 관계
- ⑥(ft-news-tree.py + v65 NEWS-TREE 하나)는 ①의 «v65 1팀 판»이다. v423 랜딩 뒤 master 가 호출부를 `ft-board-publish.sh`(slack) / `ft-board.py render --term`(pane)으로 바꾸면 ⑥ 은 ①에 흡수된다.
- `FT_NEWS_FULL=1` → `ft-board.py --full` 로 그대로 넘긴다. 오빠 10-01 「기본은 진행중·열린 것만, 전체는 요청 때」 와 v421 「✅ 소실 0」 을 둘 다 지킨다: 기본 = ✅ 를 «수와 마지막 1장»으로 접음(줄은 사라지지 않음) · 전체 = 펼침.
- `ft-news-tree.py` · `ft-news-tick-cfo.sh` 는 호출부 교체가 끝날 때까지 그대로 둔다(삭제는 그 뒤 별 카드 · 이번 범위 밖).
- pane 뉴스 = planner·각 팀 master 가 보고에 손 표 대신 `ft-board.py render --term` 출력을 붙인다 — 보고 규칙 변경은 planner 몫(설계는 도구만).

### 8-4 구현 단위 (Q8)
- 제안: v421-board 카드에 ⓪·①·렌더 순서·`--full` 을 «접어 넣는다»(아직 spawn 전 · 선행 2 완성 · 같은 dict 를 쓰므로 카드를 둘로 나누면 두 나노가 `collect()` 를 같이 고친다). 파일 200줄 넘으면 `ft_board_tree.py`(① 파서·접기) · `ft_board_summary.py`(⓪) 로 분리(카드 이미 허용).
- 시험 추가(`tests/harness/test_board.sh`): ⓪ 팀 수 = 명부 수 · 행 값 = 가짜 카드·판정 수 · planner 세션 없음 → 확인 불가 문구(대체 0) / ① `[idx:]` 3상태 + `카드 없음` · 손 상태 글자 줄 → 글자 제거 + `(카드 미연결)` · `_tree` 없는 팀 → `완성 트리 미지정` · 기본 렌더에서 ✅ 접힘(`완성 n`) · `--full`·`FT_NEWS_FULL=1` 에서 펼침 / 렌더 순서 ⓪→④ · 슬랙 렌더 첫 줄 `[상태]` · 답장 요구 정규식 0.
- 순서: 슬랙 공유판 나노(진행 중) 랜딩 → v421(+496) 나노 → v423 나노(발행·호출부 교체). master 집행 추가: 명부에 `_tree` 기입(4팀) · 5팀 트리 작성 요청.

### 8-5 DA 질문 (판정 496 사전 · 10+10분 · Q5~Q8)
- Q5 ①을 «NEWS-TREE 구조 + `[idx:]` 상태만»으로 두는 것이 v421 의 «손 상태 금지»와 모순 없이 «골 축별 완성 트리»를 만드는가(손 글자 제거 + `(카드 미연결)` 경보로 충분한가)?
- Q6 기본 렌더의 ✅ 접기(`완성 n + 마지막 1장`)가 오빠 10-01 「기본 요약」과 v421 「✅ 소실 0」을 동시에 만족하는가?
- Q7 ⓪ 의 «오빠 할 일» 열과 `결정 자리` 줄이 슬랙 공유판의 «답장 요구 0»·`live_planner` 규칙과 충돌 없는가(같은 사실을 두 곳에서 다르게 계산하는 길이 있는가)?
- Q8 v421 카드에 접어 넣기(나노 1) vs 별 카드(나노 2) — 단위 크기 적정한가?

### 8-2-r2 DA 496 r1 교정 (Q5·Q6 HOLD · Q7·Q8 APPROVE) — 8-2·8-4 와 다르면 이 절이 이긴다
**A. 전체 대조(Q5·Q6) — 분모 = 카드 폴더, 트리는 «배치»만 정한다**
- 팀 카드 집합 `C` = 그 팀 `_cards` 의 `{대기,진행,완성}/*.md` basename(확장자 제외) 고유 집합 · 상태 = 그 파일이 있는 폴더. 같은 id 가 두 폴더에 있으면 1장으로 세고 상태 = `⚠폴더 중복(<폴더들>)` (어느 쪽도 버리지 않고 표시).
- 트리 idx 집합 `T` = NEWS-TREE `[idx:]` 값. 배치 = 트리 위에서 아래로 «첫 등장» 위치 1곳. 같은 idx 의 두 번째 이후 등장 = 그 자리에 `(중복 링크 — 첫 위치: <축 줄>)` 만 표시하고 «세지 않는다».
- 미연결 = `C − T` → 완성 트리 맨 끝 합성 축 `축 미연결` 아래에 상태별로 둔다(완성·진행·대기 모두 · ✅ 포함). `T − C` = 지금처럼 그 줄에 `카드 없음`.
- ★불변식(시험 단언)★: 팀마다 상태별로 `Σ(축별 계수) + 미연결 계수 = |C 의 그 상태|` — 기본 렌더·`--full` 둘 다. 트리가 없는 팀(`_tree` 미지정)은 전부 `축 미연결` 로 가므로 «완성 트리 미지정» 줄 + 미연결 축 = 그 팀 카드 전부(소실 0).
- 5팀 트리 작성 지시에서 «진행·대기만 연결» 을 지운다 — 연결은 선택이고 소실은 미연결 축이 막는다.

**B. 접기·«마지막» 기준(Q6)**
- 기본 렌더: 각 축(미연결 축 포함) 아래 ✅ = `완성 n(최근: <제목>)` 한 줄 — n = 그 축에 «센» 카드 수(중복 링크 제외) · 최근 = 그 n 장 중 완성 폴더 파일 mtime 최대(같으면 basename 오름차순 첫째).
- 세션 트리(v421)의 `오늘 완성 n(마지막 1개 제목)` 은 «오늘 mtime» 만 세는 다른 값이다 — 이름을 `오늘 완성` / 축 칸은 `완성(누적)` 으로 갈라 표기해 혼동 0.
- `--full`(= `FT_NEWS_FULL=1`) = 접기 해제 · 행 상한 해제 · 미연결 축도 전부 나열.

**C. 한 번 수집(Q7 조건)** — planner 생존 확인·판정 fold·카드 집합은 `collect()` 에서 1회만. `render --term` · `render --slack` 은 그 dict 만 읽는다(재조회·재계산 0).

**D. 배포 잔여(Q8 조건)** — 도구 승인 ≠ 실환경 팀 커버리지. 카드 닫힘 = 도구 시험 통과까지 · 명부 `_tree` 기입과 5팀 트리 작성은 master 집행 잔여로 따로 적고, 그 전까지 보드는 그 팀을 «완성 트리 미지정 + 미연결 축»으로 보인다(소실 0 이라 착수를 막지 않는다).

**시험 추가(8-4 에 더함)**: ①DA 반례 — 완성 폴더 A·B · 트리 idx A 만 → 기본: 축 `완성 1(최근: A)` + 미연결 `완성 1(최근: B)` · full: A·B 모두 줄로 · 불변식 성립 ②같은 idx 를 두 축에 링크 → 첫 축에서만 셈 · 둘째 자리 `(중복 링크 — 첫 위치: …)` · 불변식 성립 ③같은 id 가 진행·완성 두 폴더 → 1장 · `⚠폴더 중복` ④`_tree` 없는 팀 → 그 팀 카드 전부 미연결 축 · 불변식 ⑤«최근» = mtime 최대(가짜 mtime 주입 2장) · 세션 트리 `오늘 완성` 과 값이 다른 픽스처에서 둘이 따로 찍힘 ⑥tmux 스텁 호출 수 = collect 1회당 1 · render 2종 호출 뒤 증가 0.
