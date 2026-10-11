# 인덱스: 슬랙 채널이 이슈마다 뿌리 글 1개(24시간 207개)로 넘침 — 팀별 하루 뿌리 글 1개 + 그 아래 스레드 + 뿌리 글에 이슈 시작·끝 목록 (판정 623 · 오빠 직접 지시 10-09 10:0x · planner#15 → master#22 #67439)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 623(오빠 원문 「슬랙 메세지 여전히 유효성이 많이 떨어진다. 메인팀별 하는일을 하나 공유해줘서 내가 읽게하고 그팀의 세부 작업과 지금공유되는 상태 메세지를 팀별 이슈생성해서 그 하위 스레드로 공유해주는게 어떨까? 팀별 이슈인덱스 시작과 끝을 알수있게하고」)
- 상태: 대기
- 선행: 판정 609(쉬운 판 · 본문 인덱스 토큰 목록 — 이 카드가 같은 토큰 목록 함수를 쓴다 · 609 랜딩 뒤 spawn)
- 시험 입력: 가짜 Slack 대상(기존 미러 시험의 fake API) + 픽스처 이슈(라벨 포함) · mbox 행
- 기준값(arch#23 실측 · Slack conversations.history 읽기 전용 · 채널 C0C6MJGRR89 · 10-08 10:1x~10-09 10:1x): 뿌리 글 207 · 그중 이슈 하나당 뿌리 글 196(`#N 시작 — …` 108 · `[작업상황] #N 시작 — …` 88 — 둘 다 `scripts/harness-install/slack-mirror/mirror_deliver.py` `Deliverer.thread_ts` 가 키 `#N`(`scripts/harness-install/slack-mirror/mirror_lib.py` `thread_key` = Issue 번호 > 좌석 계보 > 기타)마다 `root_text` 로 새 뿌리 글) · 좌석 뿌리 글 5(`byz-<팀>-master-claude 시작 — …`) · [상태] 4(매거진·보드) · 제안서 2. 답글 853.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터) + C(배포 발행(슬랙) — 오빠가 슬랙 한 화면에서 팀별 지금 하는 일·이슈 시작과 끝을 읽는다).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
슬랙 미러 두 개(GitHub 미러 `scripts/harness-install/slack-mirror/byz_github_slack_mirror.py` · mbox 미러 `scripts/harness-install/slack-mirror/byz_mbox_slack_mirror.py`)는 공용 `Deliverer`(`scripts/harness-install/slack-mirror/mirror_deliver.py`)로 글을 낸다. `Deliverer.thread_ts` 는 키(이슈 `#N` · 좌석 계보 · 기타)마다 뿌리 글을 하나씩 만든다 — 그래서 하루 이슈 수만큼 채널 본문에 뿌리 글이 쌓인다. 오빠는 «팀마다 하나»를 읽고, 세부는 그 아래 스레드로, 이슈의 시작과 끝은 목록으로 보고 싶다. 이 카드는 키를 «팀·날짜»로 바꾸고, 팀 뿌리 글을 «지금 하는 일 + 이슈 시작·끝 목록»으로 계속 고쳐 쓴다(chat.update). 이슈 생성은 지금처럼 issues 마스터 경유(미러는 GitHub 를 읽기만).

## 사전검증
- 소환: ★예 1회(설계 DA · 착수 전) · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 · arch 서명★ — Q1 팀 판정(라벨·좌석)이 조용한 누락 없이 모든 글을 어느 뿌리 글엔가 넣는가 · Q2 결정 요청(HIL) 질문을 팀 스레드로 합칠 때 오빠 답글 라우팅이 깨지지 않는가(설계 5) · Q3 뿌리 글 고쳐 쓰기 실패·재시작·날짜 경계에서 목록이 틀리거나 사라지지 않는가.
- 구현 DA: 아니오(설계 DA 1회 · arch 독립 재현 + 가짜 Slack 시험 + 실 슬랙 1회로 닫음).

## 설계 (닫힌 목록)
1. **스레드 키 = 팀·날짜**: `Deliverer.thread_ts` 의 키를 `team:<팀>:<날짜>` 로 바꾼다. 날짜 = KST 08:00 경계(매거진 창과 같음 · 08:00 전 글은 전날). 팀 = 아래 2. 맵 파일·flock·MAX_THREADS·resume 마커 검사는 그대로(키 문자열만 바뀜).
2. **팀 판정**(새 파일 `scripts/harness-install/slack-mirror/mirror_team.py`):
   - 대상 팀 = cfo · harness · issues · feature · ops · loom · v65 · planner(상위 요약) + `기타`.
   - 이슈 키 `#N`: 그 이슈의 GitHub 라벨 `team:<x>` → `team:shared-harness`·`team:harness-ops` = harness · `team:planner` = planner · 목록 안 이름 = 그 팀 · 그 밖(ccu·kk 등 위성) = 기타. 라벨 조회는 GitHub REST(미러가 이미 쓰는 저장소 인자·토큰) + 캐시 파일(`~/.hermes/state/byz_issue_team.json` · 키 = 번호). 라벨 없음 = `기타` + 그 답글 첫 줄 「팀 라벨 없음」. 조회 실패 = ERROR + 그 글은 `기타` 뿌리 글로(조용한 누락 0 · 다음 글에서 다시 조회).
   - 좌석 키 `byz-<팀>-…`: 이름의 팀 칸. `기타` 키(GAP 등) = planner.
3. **팀 뿌리 글**(하루·팀 1개 · 처음 글이 올 때 만들고 이후 `chat.update` 로 통째로 다시 씀 · 새 상태 파일 `~/.hermes/state/byz_team_roots.json` = {키: {root_ts, now, issues: {N: {title, opened, updates, closed}}}} 가 정본 · 뿌리 글은 매번 상태에서 전부 다시 그림):
   - 1줄: 「<팀 이름> · <날짜> — 지금 하는 일」 · 2~3줄: 지금 하는 일(그 팀 최근 글의 요약 `what` 1~2개 · 결론 먼저) — 609 의 본문 인덱스 토큰 검사 통과한 문장만(걸리면 토큰을 걷어 «이슈 목록»으로).
   - «이슈 목록»(번호 허용 영역 · 뿌리 글 끝): 이슈마다 1줄 「쉬운 제목 — 열림 HH:MM · 진행 n · 닫힘 <PR 번호> <sha 7자> HH:MM」(닫힘 전이면 「진행 중」). 열림 = 그날 그 이슈 첫 글 · 닫힘 = GitHub 미러의 closed/merged 사건(PR 병합 sha). 이슈 아닌 좌석 글은 목록에 넣지 않고 «지금 하는 일»만 갱신.
   - planner 뿌리 글 = 「오늘 메인 팀 7 한눈에」 — 팀마다 1줄(그 팀 뿌리 글의 지금 하는 일 첫 줄 + 열린/닫힌 이슈 수) · 팀 뿌리 글이 바뀔 때 같이 다시 씀.
4. **세부 글 = 팀 뿌리 글의 답글**: 지금 `format_row` 글 그대로 + 첫 줄 앞에 「<쉬운 이슈 제목> ·」(이슈 글일 때) — 같은 스레드 안에서 이슈를 구분. `reply_only` = 그날 그 팀 뿌리 글이 있을 때만(없으면 지금처럼 WARN · 안 올림).
5. **결정 요청(HIL) 질문은 따로 뿌리 글 유지**: 오빠 답글 라우팅(`scripts/harness-install/slack-mirror/mirror_questions.py` · `scripts/harness-install/slack-mirror/byz_slack_mbox_inbound.py` 가 스레드 1개 = 질문 키 1개로 찾는다)이 한 스레드에 질문 여럿이면 갈린다 → HIL 은 지금처럼 이슈 키 뿌리 글(채널 본문)에 남기고, 팀 뿌리 글 목록에 「결정 기다림」 1줄 + 그 질문 링크. 채널 본문의 낱개 글 = HIL 질문만.
6. **뿌리 글 고쳐 쓰기 실패**: `chat.update` 실패 = stderr ERROR + 답글 끝에 「(팀 목록 갱신 실패 — 다음 글에서 다시 그림)」 1줄 · 상태 파일은 이미 갱신됐으므로 다음 성공 때 통째로 맞춰진다(조용한 누락 0). 상태 파일 읽기 실패 = raise(지금 맵 파일과 같음).
7. **그대로 두는 것**: 매거진(하루 1) · 보드 발행(`com.byz.ft-board-publish`) · 제안서 뿌리 글 · `byz_thread_post.py` 카드 단위 스레드 · 역방향 inbound(답글 읽기). 이슈 생성 경로(issues 마스터) 변경 0.
8. 200줄 규칙 · 새 파일은 `scripts/harness-install/slack-mirror/install.sh`·`scripts/harness-install/slack-mirror/install-github.sh` 설치 목록에 추가.

## 설계 r2 (설계 DA r1 HOLD Q2·Q3 반영 — 위 설계 3·5·6 을 이 절이 «대체»한다 · 설계 1·2·4·7·8 은 유지)
- **r2-A 키 둘로 분리(Q2)**: 글 항목의 `key`(이슈 `#N`·좌석 계보·기타)는 지금 뜻 그대로 둔다 — 질문 등록(`mirror_questions`)·`_close_answered`·`delivered_for` 는 계속 원래 key 를 쓴다. 새 칸 `post_key` 만 `team:<팀>:<날짜>` 로 정하고 `Deliverer` 가 «게시 스레드»를 고를 때만 쓴다.
  - HIL 글: `post_key` = 원래 key(지금처럼 이슈 뿌리 글) → 질문 등록 thread_ts 와 HIL 게시 thread_ts 가 같은 `ensure_thread(원래 key)` 에서 나온다(동일성 고정).
  - 팀 뿌리 글 스레드의 오빠 답글: 질문이 없는 스레드이므로 inbound 는 «마지막 봇 글에서 좌석 추정»을 하지 않고 planner 에게만 원문+스레드 링크로 보낸다(팀 뿌리 글 판별 = 스레드 맵 키가 `team:` 로 시작).
- **r2-B 팀 목록 = 이벤트 원장에서 매번 다시 그림 · 공용 잠금 1개(Q3)**:
  - 상태 = 원자 교체 JSON `~/.hermes/state/byz_team_roots.json` = {team-date: {events: {이벤트 id: {issue, kind, at, title, pr, sha, what}}}} · 이벤트 id = 미러 글 id(`github #N closed` · mbox `#seq`) — 같은 id 는 두 번 반영되지 않는다(멱등).
  - 공용 잠금 `~/.hermes/state/byz_team_roots.lock`(flock · 두 미러 공용) 안에서만: ①상태 읽기 ②이벤트 id 없으면 추가 ③원자 저장(tmp+fsync+replace · 실패 = raise · 그 글 처리 중단 · pending 남아 재시도) ④상태 «전체»로 팀 뿌리 글 다시 그림 → `chat.update` ⑤planner 뿌리 글 다시 그림 → `chat.update`. 렌더와 update 가 잠금 안이므로 늦은 update 가 새 화면을 덮는 역전 0.
  - 뿌리 글 ts 정본 = 기존 스레드 맵(`ensure_thread(post_key)` · 자기 flock). 순서: 스레드 맵 잠금(뿌리 글 확보) → 해제 → 답글 게시(`Deliverer.send` · resume 마커 그대로) → 공용 잠금(①~⑤). 두 잠금은 중첩하지 않는다(교착 0).
  - 재시작: `Deliverer.send` 가 resume 마커로 일찍 돌아와도 ①~⑤ 는 «항상» 실행(이벤트 id 멱등이라 두 번 와도 1회 반영) → 답글 뒤·update 전 종료가 다음 실행에서 복구. 이벤트 저장 뒤·update 전 종료 = 다음 아무 글의 ④⑤ 가 전체를 다시 그려 복구.
  - `chat.update` 실패 = ERROR + 다음 답글 꼬리 1줄(설계 6 문구) · 상태는 이미 저장 → 다음 렌더가 맞춤.
- **r2 시험 추가**: T5a 같은 이슈 질문 2 → 이슈 뿌리 글 1 · 기존 «질문 여럿 → planner 원문» 동작 그대로 · T5b HIL 답 뒤 같은 이슈 일반 보고(팀 스레드 게시) → 원래 key 로 질문 닫힘 · T5c 두 좌석 보고가 섞인 팀 스레드에 오빠 답글 → planner 만 · T9 두 writer 교차(가짜 API · 같은 상태에서 A·B 동시) → 이벤트 2 모두 남음 · T10 늦은 update 시뮬레이션 → 최종 화면 = 최신 상태 · T11 상태 저장 뒤 종료 / 답글 뒤 종료 → 재시작 후 진행 수 중복 0 · 화면 복구.

## 구현 범위 (닫힌 목록)
1. 위 설계 1~8.
2. 시험(새 파일 `tests/scripts/test_mirror_team_roots.py` · 파일당 120줄 이하 · 넘으면 `tests/scripts/test_mirror_team_index.py`·`tests/scripts/test_mirror_team_concurrency.py` 로 나눔 · r2 시험 T5a~c·T9~T11 포함): T1 같은 팀 이슈 2개 + 좌석 글 1 → 뿌리 글 1 · 답글 3 · T2 라벨 `team:shared-harness` → harness · 라벨 없음 → 기타 + 「팀 라벨 없음」 · 조회 실패 → 기타 + ERROR · T3 날짜 경계(07:59 → 전날 · 08:00 → 당일 새 뿌리 글) · T4 이슈 목록: 열림 시각·진행 수·닫힘 PR·sha · T5 HIL 질문 → 따로 뿌리 글 + 팀 목록 「결정 기다림」 · T6 chat.update 실패 → ERROR + 답글 꼬리 1줄 · 다음 글에서 목록 전부 맞음 · T7 재시작(상태 파일·맵 다시 읽기) 뒤 같은 날 뿌리 글 재사용(새 뿌리 글 0) · T8 planner 뿌리 글 팀 7줄.
3. 기존 PASS: `tests/scripts/test_byz_github_slack_mirror.py` · `tests/scripts/test_byz_mbox_slack_mirror.py` · `tests/scripts/test_byz_slack_mbox_inbound.py`(키 기대값이 바뀐 행은 새 계약으로 고치고 그 행을 RESULT 에 적는다).
커밋은 자기 브랜치, **push 금지**. **금지**: 실 Slack 게시(가짜 대상만) · 홈 `~/.hermes/` 쓰기 · launchd · GitHub 쓰기(라벨 조회는 시험에서 가짜).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · arch 독립 재현.
- 카드 증거 줄: `세트: <40hex> · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_mirror_team_roots.py rc=0 · 이슈: 0`.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#23 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행★: install(미러 2종 재기동) → 실 슬랙 1회(다음 글부터 팀 뿌리 글) → 오빠 화면 확인(채널 본문 = 팀 뿌리 글 + planner 1 + HIL 질문 + 매거진·보드·제안서) → planner 보고.

## 상태
- base_sha: 7a60f4fba0e0391a96843b165f557e144b8d711b (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#23 · 판정 623 · master#22 #67439).
- 정본 영향 없음: 하네스 슬랙 미러 키트·시험만.
- 2026-10-09 10:07 — 대기→진행 · 좌석 byz-harness-nano-slack623-team-roots#0
- 2026-10-09 10:2x — 반송 r1 #67597(«지금 하는 일» 번호 든 요약 건너뜀 → 609 strip_tokens) → 나노 [완료·휴식] #67606 · 세트 `6ea1fd5cc1`(609 랜딩 `7fbbff9353` 위 rebase).
- 2026-10-09 — arch#24 독립 재현: 새 시험 16 passed · 기존 미러 시험 FAILED 목록 base `7fbbff9353` 과 diff 0(12 · inbound 13) · ruff clean · 설치 목록 import 닫힘 OK → arch 서명 · 판정서 초안 §106 → master 집행 요청.

## 결과
세트: 6ea1fd5cc1b416d3ac6297111aa1a84479197231 · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_mirror_team_roots.py rc=0 · 이슈: 0
회귀: 새 시험 4파일 16 passed · 기존 미러 실패 목록 base diff 0 · ruff clean · 설치 import 닫힘 OK
정본 영향 없음: 하네스 슬랙 미러 키트·시험만.
- 2026-10-09 10:40 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§106
