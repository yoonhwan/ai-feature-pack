# 인덱스: 질문 보드 — UTF-8 3500 바이트 상한(게시 문자열 전체) · 건수+결정 자리+가장 오래된 5건+외 n · 닫는 사건 = planner 인박스 `미닫힘=` (R49 · master#17 #64702 ①안 · 나노 1)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 원장 R49(master#17 발견 #64682) · 결정 master#17 #64702(①안 · 하네스 내부 표시 정책 · 오빠 판단 불요)
- 상태: 대기
- 선행: 없음(origin/main 의 `scripts/harness-install/slack-mirror/` 만 · a61bb85864 기준 참조 줄 재확인 arch#18 22:19) · 순서 = v421(+496) 랜딩 → 판정 511 카드 → 이 카드(master 한 번에 하나)
- 시험 입력: 임시 디렉터리(가짜 질문 저장소 · 가짜 인박스 큐 파일 `<계보>.jsonl`) + 스텁 `ft-inbox.sh`(show·ingest 출력·rc 고정) + 슬랙 스텁(받은 `text` 기록) + 가짜 tmux(live_planner) — 실제 슬랙·인박스·tmux 호출 0
- 기준값: `chat.update ok=false: msg_too_long` mbox 미러 473회·inbound 6회(카드 생성 때) → **595회·128회(22:19 재실측 · `~/.hermes/logs/byz_mbox_slack_mirror.err`·`byz_slack_mbox_inbound.err` · 계속 증가)** · 마지막 성공 board_text 2107자/3909 UTF-8 바이트 · 실패 2208자/4073 바이트 · 열린 질문 36(delivered 0 · resolved 1 · 4~17시간) · 인박스에 있는 것 9(mark 0) · 없는 것 27(인박스 도입 전)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(배포 발행(슬랙) — 발행물이 거부돼 멈춤) + A(모니터). 핵심 한 줄: 보드 글을 실측 거부선 아래로 묶고, 열린 질문이 planner 인박스에서 닫히면 보드에서도 닫는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
슬랙 질문 보드(`mirror_questions.render_board` · 채널 메시지 1개를 `chat.update` 로 제자리 갱신)는 열린 질문 «전부»를 한 줄에 이어 붙여 2208자(4073 UTF-8 바이트)가 되자 슬랙이 `msg_too_long` 으로 거부하고 미러가 종료코드 1 로 반복 재기동된다(마지막 성공 3909 바이트 → 거부선 ~4000 바이트 · 한글 1자 3바이트). 근본은 질문이 닫히지 않는 것이다: 수명 = add → 슬랙 답장으로 delivered → 같은 key·같은 좌석 «이름»의 다음 보고로 close 인데, 슬랙이 읽기 전용이 된 뒤 delivered 가 안 생기고 승계로 이름이 바뀌어 close 도 안 맞는다. 고침 두 가지: ①보드 = 첫 줄(건수 + 결정 자리 + 경고) + 가장 오래된 5건 + `… 외 n건`, 실제 게시 문자열 전체를 UTF-8 3500 바이트 이하로(접기 표식 예산 선예약 · UTF-8 안전 절단 · 최종 단언) ②미러 패스당 1회 planner 인박스(`ft-inbox.sh`)를 조회해, 인박스 큐에 있고 `show` 의 `미닫힘=` 에 없는 질문을 닫는다(정본 술어 재구현 0 · 인박스에 없는 열린 질문은 `ingest` 로 1회 적재 · 해석 실패는 fail-closed). 정본 설계 = `design/harness/DESIGN-r49-question-board-20261008.md` — ★`## §2-r2` 가 §2 를 이긴다★.

## 사전검증
- 소환: 예
- DA: `design/harness/DA-r49-question-board-20261008.md` — r1 HOLD(Q1 바이트 예산 · Q2 show 파싱 · Q3·Q4 APPROVE) → r2 APPROVE(Q1~Q4 · byz-harness-da-codex#0 #64756) — arch 서명 byz-harness-arch-claude#17

## 조사 근거
- `scripts/harness-install/slack-mirror/mirror_questions.py:117` render_board(전부 이어 붙임) · `scripts/harness-install/slack-mirror/mirror_questions.py:130` update_board(chat.update · 글 같으면 API 0) · `scripts/harness-install/slack-mirror/mirror_questions.py:111` delivered_for(state=delivered 만) · `scripts/harness-install/slack-mirror/mirror_questions.py:97` close(멱등 · tombstone).
- `scripts/harness-install/slack-mirror/byz_mbox_slack_mirror.py:98` run_pass(패스당 1회 호출 자리) · `scripts/harness-install/slack-mirror/byz_slack_mbox_inbound.py:120` update_board 호출.
- 인박스 계약 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin/ft-inbox.py:70-89` view·cmd_show — 정상 출력 = `EMPTY` 한 줄 또는 줄마다 `[<cls>] <group> seq=<그룹 전체> 미닫힘=<안 닫힌 seq> from=…` · `:22-40` ingest 멱등(이미 있으면 SKIP · 원문 수신 계보 큐로).
- 설계 §1 실측표 · §2-r2 A-r2(바이트 절차 ①~④) · B-r2(파싱 정규식 · fail-closed · 닫기 조건).

## 구현 범위 (닫힌 목록 · 정본 `scripts/harness-install/slack-mirror/` 만)
1. `scripts/harness-install/slack-mirror/mirror_questions.py`(200줄 넘으면 `scripts/harness-install/slack-mirror/mirror_board.py` 로 분리): `fit_board(parts, cap=3500)`(A-r2 ①~④ · 잴 대상 = `lib.esc` 뒤 실제 게시 문자열 전체 · 마지막 단언 거짓이면 raise) · render_board 가 결정 대기·전달됨 두 목록을 `asked_at` 오름차순 최대 5줄 + `… 외 n건` 으로 · 첫 줄 끝 경고 `인박스 밖 k건` · `정리 확인 불가(<사유>)` · `close_from_inbox(qpath, inbox_bin, planner_name) -> 경고 문자열|None`(B-r2: 큐 파일에 없는 열린 seq → `ingest` · `show` 비compact 파싱 → U = `미닫힘=` 합집합 · 큐에 있음 ∧ ∉ U → close · rc≠0·빈 출력·정규식 불일치·숫자 아님·planner None·큐 JSON 오류 → 닫기 0 + stderr `ERROR:` + 경고 사유).
2. `scripts/harness-install/slack-mirror/byz_mbox_slack_mirror.py`(지금 193줄)·`scripts/harness-install/slack-mirror/byz_slack_mbox_inbound.py`(지금 189줄 · 둘 다 200줄 넘으면 인자 정의·호출을 `mirror_board.py` 쪽 함수 1개로 옮겨 호출 1줄만 남김): 새 인자 `--inbox-bin`(없으면 시작 시 exit 1) · run_pass 시작에 `close_from_inbox` 1회 → 경고를 보드 렌더에 넘김(보드 갱신·다른 카드 발행은 계속 · 실제 chat.update 실패는 지금처럼 raise).
3. installer `scripts/harness-install/slack-mirror/install.sh`·`scripts/harness-install/slack-mirror/install-inbound.sh` + plist 템플릿: `--inbox-bin` 을 env `FT_INBOX_BIN`(없으면 exit 1 · 조용한 기본값 0)에서 채움.
4. 시험 새 `tests/harness/test_question_board.sh`: 설계 §3 ①~⑨ + §2-r2 추가분 — 열린 36건(실측 길이 한글 요지) → 슬랙 스텁이 받은 `text` ≤ 3500 바이트 · 오래된 5 + `… 외 31건` ┃ 최종 바이트 3499·3500·3501 경계 ┃ 첫 줄만 3500 초과 → ≤ 3500 + `…` · decode 성공 ┃ 두 목록 + 경고 2종 동시 ┃ `&<>` 이스케이프 요지 ┃ 혼합 그룹 `seq=10,11 미닫힘=11` → 10 닫힘·11 open ┃ `EMPTY` → 큐에 있는 열린 질문 전부 닫힘 ┃ rc=0 빈 출력 · 깨진 줄 섞임 · `미닫힘=x` · rc=1 · planner None · 큐 JSON 오류 → 닫기 0 + 경고 + ERROR + 보드 갱신 진행 ┃ 큐에 없는 seq → ingest 1회 · 다음 패스 0 ┃ ingest 실패 → `인박스 밖 1건` ┃ 패스당 show 호출 = 1 ┃ `--inbox-bin` 없으면 exit 1 ┃ 변이 대조: `seq=` 첫 값만 뽑는 파서로 바꾸면 FAIL.
5. 기존 시험 PASS: `tests/harness/test_slack_readonly_share.sh` · `test_slack_mirror_signature.sh` · `test_index_move_slack.sh` · `test_magazine_plist.sh` · `test_proposal_register.sh` · `test_proposal_register_r2.sh` · `test_proposal_card.sh` · `test_slack_post_guard.sh`.

커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 `~/.hermes/` 설치·launchd 재기동(master) · 실제 슬랙·인박스(ingest/mark)·tmux 호출 · 질문 저장소 항목 삭제(보드에서 빠질 뿐) · 인박스 obligation_closed 술어 재구현(`show` 출력만) · `ft-inbox.*` 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_question_board.sh` rc=0 · 위 5 기존 시험 PASS · `ruff check scripts/harness-install/slack-mirror/` 0 · 고친 파일 200줄 이하.
- RESULT 에 ★36건 픽스처 보드 `text` 전문 + 바이트 수★ 와 ★혼합 그룹 닫힘 결과★ 복붙.
- 카드 증거 줄(필수 · RESULT 맨 끝 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_question_board.sh rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다(그 뒤 커밋·추가 확인 0).
- 랜딩 뒤 master 집행(카드 밖): 라이브 설치(`FT_INBOX_BIN=<FT_BIN>/ft-inbox.sh`) · 미러 2종 재기동 · err 로그 `msg_too_long` 증가 0 확인 · 보드 1회 캡처(바이트 수 함께) · 첫 패스 ingest 27건 결과 1줄을 planner 에 알림(인박스에 옛 HIL 이 들어감).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 4d3fabed97680dd36d154fbb3c5f58182fa9e36c (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#17 · 설계 §2-r2 · DA r2 APPROVE #64756 · master 결정 #64702).
- 2026-10-08 22:2x — spawn 전 재확인(byz-harness-arch-claude#18 · master#18 #65296): origin/main a61bb85864 에서 참조 줄(mirror_questions :97·:111·:117·:130 · mirror run_pass :98 · inbound update_board :120·:148)·기존 시험 8개·plist 템플릿 2·`ft-inbox.py` view/cmd_show 계약(`EMPTY` 또는 `seq=… 미닫힘=…`) 그대로 · 기준값 갱신 · 200줄 분리 지시 · 루트 지침 완료 줄 추가. 설계·DA 범위 변경 0.
- 정본 영향 없음: 하네스 슬랙 미러 스크립트·설치기·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 22:19 — 대기→진행 · 좌석 byz-harness-nano-r49-question-board#0
세트: 101e7af897bc1b65ca1488f14e7998130706590e · 시험: bash tests/harness/test_question_board.sh rc=0 · 이슈: 0
세트: 8d60794af705afa05166561ca3965e6e6b30952b · 시험: bash tests/harness/test_question_board.sh rc=0 · 이슈: 0
- 정본 영향 없음: 하네스 슬랙 미러 스크립트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 22:40 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§81
