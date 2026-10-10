# 인덱스: 쪽지 개선 한 건 — 오빠 대면 좌석 알림 = 세션 안 감시(Monitor) · 입력창 주입 0 · 분류 7초 룰 (R34·R57·R85 · 판정 876·877)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R34·R57·R85 합침(판정 877 · master#26 발주 #72332)
- 상태: 대기
- 선행: 없음(제안 Issue #1191 · 판정 881 오빠 ① 세션 안 감시 채택 · 임시 조치(planner doorbell 0)는 ① 설치까지 유지)
- 제안서: #1191
- 시험 입력: 임시 FT_ROOT 쪽지함 픽스처(`tests/harness/fixtures/stub-ft-inbox.py` 방식) · tmux·claude 스텁 — 실 planner pane·실 Haiku 호출 0
- 기준값: 10-10 하루 planner 앞 쪽지 200건 중 보낼 때 «무조건 알림»(①~④·미상) ≈ 170건 = planner pane 키 입력 주입(13:37 핫픽스 전) · 전 좌석 쪽지 1,025건 중 Haiku 경로 710건(`claude -p` 710회) · 분류 실패 54(20초 timeout 41 · rc=1 13) · 핫픽스 뒤 planner 수신 = 10분 크론만(최대 10분 지연)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. 오빠 직접 질책(판정 876 「알림끄기가 아니다!!!」 · 877 세 건 합치기).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
v423c(판정 423 ③)가 «①~④·미상 쪽지는 받는 좌석의 tick 과 무관하게 무조건 doorbell» 로 바꿨고, doorbell 은 받는 pane 에 `[발주 #N] recv …` 를 send-keys 로 친다. planner pane 은 오빠가 직접 치는 곳이라 그 글자가 문장 중간에 끼어 절단됐다(10-10 5회+ · R85). 규칙표가 쪽지 첫 줄의 약 60%를 못 맞혀 «미상» → 무조건 울림이 되고, 미상은 쪽지마다 `claude -p` Haiku 를 따로 띄워(20초 상한 · 7초 룰 위반) 다시 분류한다(R57). 13:37 핫픽스(`user_facing` — 오빠 대면 좌석 doorbell 0 · 큐만)로 주입은 멈췄지만 planner 는 10분 크론으로만 읽어 처음 문제(R34 늦게 올라옴)로 되돌아간다. 제안 ①(추천): planner 세션이 자기 쪽지함을 세션 안 감시(Claude Code Monitor)로 지켜보다가 새 행 1건 = 세션 안 알림 1건으로 받는다 — 키 입력 0 · 1~2초.

## 사전검증
- 소환: 아니오
- 면제: 새 감시 도구 1개(읽기 전용 · 큐 파일만 읽음) + 라이브에 이미 도는 핫픽스를 정본·시험으로 옮김(동작 변경 0) + 분류 시간 상한·규칙표 줄 추가 · 파괴 경로 0 · 키 입력 경로 신설 0 · 시험으로 닫음 — arch 서명 byz-harness-arch-claude#27

## 조사 근거 (기준 = origin/main 178bde6c9c · 2026-10-10 실측)
- `tools/comm-canonical/mbox.sh` — `inbox_must_ring`(①~④·미상) · send/relay doorbell 분기 · 라이브 `.claude/fable-team/bin/mbox.sh` 13:37 핫픽스 `user_facing`(51행) + 백업 `mbox.sh.bak-userfacing-1010`(정본에는 없음).
- `scripts/fable-team-bin/ft_inbox_core.py` `rule_class`(규칙표 · 미적중 = 미상) · `haiku`(`FT_INBOX_HAIKU_TIMEOUT` 기본 20).
- `scripts/fable-team-bin/ft-inbox.py:45` — 미상마다 `classify` 분리 실행(`claude -p`).
- 큐 `.fable-team/state/inbox/<계보>.jsonl`(행: seq·ts·from·cls·via) — 감시 대상.

## 구현 범위 (닫힌 목록 · 나노 브랜치는 origin/main 기준 · 판정 881)
1. 새 파일 `scripts/harness-install/fable-team/bin/ft-inbox-watch.sh <좌석>` (같은 바이트로 `scripts/fable-team-bin/ft-inbox-watch.sh` · 80줄 이하 · 읽기 전용):
   - 큐 경로 = `ft_inbox_core.qpath(<좌석>)`(계보 규칙 그대로 · 같은 폴더 모듈 import) · `FT_ROOT` 규약 그대로.
   - ★`tail -F` 금지★ — 분류기가 행을 갱신할 때 큐 파일을 통째로 다시 쓴다(`write_q`) → tail 이 같은 행을 다시 낸다. 대신 python `-u` 루프: `FT_INBOX_WATCH_POLL`(기본 1초)마다 큐를 읽어 «시작 시점 이후 처음 보는 seq» 만 1줄씩 낸다(시작 때 있던 seq 는 «본 것»으로 둠 · 놓친 옛 쪽지는 틱 recv 몫).
   - 출력 1줄 = `[쪽지] #<seq> <cls> <from> <본문 첫 줄 40자>`(본문은 행의 `body_path` 첫 줄 · 못 읽으면 `(본문 없음)`) · 한 줄 = Monitor 알림 1건.
   - 큐 파일 없음·깨진 줄 = stderr 경고만 하고 계속(감시가 죽으면 알림이 끊긴다 — 대신 30초마다 1번만 경고) · 종료 0 은 SIGTERM 때만.
2. `tools/comm-canonical/mbox.sh`: 라이브 핫픽스 `user_facing` 함수 + send·relay 의 `if user_facing "$to"; then notify=0; fi` 두 줄을 그대로 옮긴다(라이브 `.claude/fable-team/bin/mbox.sh` 와 바이트 동일이 목표 — 차이는 이 3곳뿐(2026-10-10 실측)) · 주석의 「planner 는 10분 cron 이 recv 한다」 → 「planner 는 세션 안 감시(ft-inbox-watch.sh + Monitor)로 받는다 · 10분 틱은 안전망」.
3. `scripts/fable-team-bin/ft_inbox_core.py`(두 벌):
   - `haiku`: 상한 `FT_INBOX_HAIKU_TIMEOUT` 기본 20 → 7 · 실패(시간 초과·rc≠0·빈 출력)면 1회 재시도 후 raise(7초 룰 · 전역 하드 룰 12) · raise 메시지에 stdout 앞 120자도 싣는다(rc=1 · stderr 빈 값 13건 추적용).
   - `RULES` 줄 추가(10-10 미상→Haiku 상위 머리말 실측): ⑤ `\A\[완료·휴식` · ⑥ `\A\[?(부팅|첫 보고|승계|발주)` · ② `\A\[HIL`(뒤에 ` · …` 가 붙는 꼴 포함) · ⑤ `\A\[Issue 등록\]` — ★새 줄은 `\A`(본문 첫머리만)★: `rule_class` 는 `re.M` 이라 `^` 를 쓰면 본문 중간 줄 머리에도 걸린다(기존 6줄은 손대지 않음). «판정 N» 머리는 ①③⑤⑥ 가 섞여 규칙으로 못 가른다 — 추가 0(Haiku 몫).
4. 시험:
   - `tests/harness/test_inbox_watch.sh` 새 파일(임시 FT_ROOT · `tests/harness/fixtures/stub-ft-inbox.py` 방식 큐): ①시작 뒤 새 행 1 → 출력 1줄(형식 일치) ②시작 전 행 → 출력 0 ③같은 큐를 통째로 다시 쓰기(cls 갱신) → 추가 출력 0 ④새 행 2개 연속 → 2줄 ⑤큐 파일 없음 → 경고·계속, 생기면 그 뒤 새 행 출력 ⑥body_path 없음 → `(본문 없음)`.
   - `tests/harness/test_mbox_inbox_notify_reply_rate.sh`(기존)에 추가: seats-planner.json `_master` = 받는 좌석이면 ①~④·미상·--urgent 모두 `doorbell=quiet` · 다른 좌석은 지금 그대로 · 명시 `ring` 은 울림.
   - `tests/harness/test_inbox.sh`(기존)에 추가: 새 RULES 4줄 각 1건 → 규칙 분류(via=rule) · Haiku 스텁이 1회 실패 후 성공 → 라벨 갱신 · 2회 실패 → 미상 유지 + 오류 로그에 stdout 조각 · 기본 상한 7.
   - 기존 시험 전부 PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 팀 master·작업 좌석 doorbell 동작 변경 · 큐 파일 형식·분류 번호 체계 변경 · 감시 도구에서 send-keys·tmux 호출 · 실 planner pane·실 Haiku 호출 · 라이브 `.claude/fable-team/bin`·`.fable-team/bin` 직접 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_inbox_watch.sh` rc=0 · `bash tests/harness/test_mbox_inbox_notify_reply_rate.sh` rc=0 · `bash tests/harness/test_inbox.sh` rc=0 · `bash -n` 새·바뀐 셸 · `ruff check` 바뀐 py 0 · 킷 두 벌 `cmp` 동일 · 정본 `tools/comm-canonical/mbox.sh` 가 라이브 `.claude/fable-team/bin/mbox.sh` 와 주석 1줄 외 동일(`diff` 출력 첨부).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_inbox_watch.sh rc=0 · 이슈: #1191`.
- 랜딩 뒤 master 집행(카드 밖 · 순서대로):
  1. 라이브 설치: `.fable-team/bin/{ft-inbox-watch.sh,ft_inbox_core.py}` · `.claude/fable-team/bin/mbox.sh` 각 `.bak-r86-<날짜>` → cp → cmp(핫픽스 백업 `mbox.sh.bak-userfacing-1010` 은 보존).
  2. planner 에 1줄: 「Monitor 무장 — command = `bash <루트>/.fable-team/bin/ft-inbox-watch.sh <현역 planner 이름>` · timeout 최대(30분) · 만료 알림마다 재무장 · 10분 틱은 감시 생존 확인 + recv 안전망」.
  3. 라이브 1회 확인(오빠 참여 · planner 경유): 오빠가 planner 입력창에 글을 치는 동안 아무 좌석이 planner 에 시험 쪽지 1통 → «입력창 글 그대로 · 세션 안 알림 1건 · 처리 1~2초» 3칸을 기록.
  4. 규칙 문서(master 집행): COMM-GUIDE-BOOT 16(부팅 직후 크론) 옆에 «오빠 대면 좌석 = 부팅 직후 ft-inbox-watch Monitor 무장» 1줄 · `main-team-governance.md` §7 에 같은 줄.
  5. 핫픽스는 위 1~3 통과 뒤에도 유지(정본에 들어갔으므로 «임시» 표식만 주석에서 뺌) · 요청 원장 R34·R57·R85 닫기.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 178bde6c9c1b4a66d8581fe13d945d9ccb3cbd4c (spawn 2026-10-10)
대기 — 확정(#1191 · 판정 881) · master spawn 대기
- 슬랙: C0C6MJGRR89 1791607544.243789

## 결과
(닫을 때 증거 줄)
- 2026-10-10 14:12 — 대기→진행 · 좌석 byz-harness-nano-r86-inbox-instant-no-inject#0
세트: dc73dcd119df3c9e6d1dbbea50e4e0598962f70b · 시험: bash tests/harness/test_inbox_watch.sh rc=0 · 이슈: #1191
- 2026-10-10 — 나노 완료(dc73dcd119[feature]) · 마스터 재실행 test_inbox_watch·notify_reply_rate ALL PASS · test_inbox fail=0 · ruff 0 · 킷 cmp 동일 · 라이브 diff = 주석 1줄 · 랜딩은 push 승인 뒤
