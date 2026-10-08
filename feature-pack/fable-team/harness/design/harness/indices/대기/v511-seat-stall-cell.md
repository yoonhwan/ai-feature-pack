# 인덱스: 상태판 좌석 칸 = 실측 — ft-board 좌석 칸을 jsonl turn 으로 «정지 N분(턴 끝)» 기계 채움 · 기다림 추정(우편 기록 범위 안) · `ft-board.py stalled` · ⓪ `정지(3분+)` 열 + «완료 선언» 꼬리·`완료 선언` 열·받는 쪽 ⚠ (판정 511 + 514 3구분 · 나노 1 · v421 랜딩 뒤)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 511(오빠 「feature 팀 놀고있는데 전팀 절대 구라 없어야한다. 이거 완전 거짓말이자나」·「각 마스터들은 자신의 팀 하위 세션을 이걸 멍청한 짓하는지 관리하는게 메인잡」 · master#17 #64752)
- 상태: 대기 — 판정 516 보류 해제 조건 충족: 루트 지침(판정 514+532) 정본 설치 완료(governance §9 · BOOT 19 · 라이브 = `design/harness/staged-514/` cmp 같음 · 22:13 실측). 3구분 반영 = 설계 §4-r3(더하기만 · DA-root-guideline-514 r2 Q6 해소) → 구현 범위 1-⑤·시험 ⑩~㉒ 추가(arch#18).
- 선행: ①v421-board 랜딩(완료 · PR 989 a7fcb904bb) ②★설계 §4-r3 이 담긴 `DESIGN-511` 이 나노 워크트리 base 에 있어야 함★ — 지금은 브랜치 `nano/root-guideline-514`(커밋 6fdb732e1f · DESIGN-511 +38 더하기만) 에만 있음 → master 가 그 문서 커밋(ROOT-GUIDELINE·DA-root-guideline·DESIGN-511)을 랜딩한 뒤 spawn
- 시험 입력: 임시 FT_ROOT(가짜 명부 · 가짜 `comm/mailbox.log.jsonl`·`.1`·`mailbox.jsonl`) + 스텁 env `FT_BOARD_SEAT_STATUS`(좌석별 `ft-seat-status.sh turn --json` 출력·rc 고정) + `FT_BOARD_NOW`(시각 주입) — 실제 tmux·jsonl 조회 0
- 기준값: v421 좌석 칸 = 작업중/대기/정지레디/정지 «글자만»(`scripts/fable-team-bin/ft-news-tree.py:75` seat_state 복사) · 몇 분째·무엇을 기다리는지 0 · 사건: feature nano 18분·master 8분 정지가 「게이트 1 진행」으로 보고됨

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(오빠 요청 즉시 반영 — 「전팀 절대 구라 없어야한다」). 핵심 한 줄: 상태판의 좌석 상태를 사람이 쓰지 않고 jsonl 턴 끝 시각에서 기계로 채워, 멈춘 좌석이 «진행»으로 보이는 길을 없앤다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
판정 511 사건: planner 표가 feature 팀을 「게이트 1 진행」으로 적었는데 실제로는 나노 18분·master 8분 멈춰 있었다(마지막 쪽지 문장을 상태로 복사). 규칙(실측만 · 정지 3분이면 그 턴 처리)은 정본 문구로 따로 설치되고, 이 카드는 그 규칙을 도구로 강제한다: v421 상태판(`ft-board.py`)의 좌석 칸을 `ft-seat-status.sh turn <좌석> --json`(jsonl 층 · `{state, turn_end, duration_ms, reported, source}`) 결과로 채우되, 정지 분은 «state=IDLE ∧ source=jsonl ∧ turn_end 가 유효한 과거 시각»일 때만 계산하고 나머지 상태(PENDING·pane·UNKNOWN·오류·stop-ready)는 관측 그대로 적는다. «기다리는 것»은 우편 기록(로그+회전본+현재 큐를 seq 로 합침) 안의 사실만 쓰고 «추정»으로 표시하며, 「발주 필요」 같은 결론은 기계가 내지 않는다(master 몫). 정본 설계 = `design/harness/DESIGN-511-seat-stall-watch-20261008.md` — ★`## §4-r2` 가 §2·§3·§4 를 이기고, `## §4-r3`(판정 514 «완료 선언» 꼬리)는 r2 칸 글자를 바꾸지 않고 «더한다»★. 3구분: ①진행(WORKING) ②정지·미완(§4-r2 그대로 `⚠정지 N분` · 깨움 대상) ③완료·휴식(마지막 발신 `[완료·휴식]` + 증거 줄 + sha 실재 → `⚠`·stalled 에서 빼고, 10분 넘게 처리 안 되면 ⚠ 를 «받는 쪽» master 에 붙인다).

## 사전검증
- 소환: 예
- DA: `design/harness/DA-511-seat-stall-watch-20261008.md` — r1 HOLD(Q1 turn 계약 · Q2 우편 기록 범위 · Q3·Q4 APPROVE) → r2 APPROVE(Q1~Q4 · byz-harness-da-codex#0 #64794) — arch 서명 byz-harness-arch-claude#17
- §4-r3 DA: `design/harness/DA-root-guideline-514-20261008.md`(브랜치 nano/root-guideline-514) r1 HOLD 6 → r2 Q1·Q3~Q6 해소(§4-r3 = Q1 결합 판별 · Q3 원 쪽지 시계 · Q6 null turn_end·추정 표기) · Q2 는 가정·상한으로 닫음(`design/harness/DISPO-root-guideline-514-r2-20261008.md`) — arch 서명 byz-harness-arch-claude#18

## 조사 근거
- turn 계약 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin/ft-seat-status.sh:155-195` — state ∈ {WORKING, IDLE, PENDING, UNKNOWN} · jsonl 없으면 pane 판정 + turn_end null + source=pane · `--json` 키 5개.
- 기존 좌석 칸 `scripts/fable-team-bin/ft-news-tree.py:75` seat_state(v421 이 복사) — 이 카드가 v421 의 그 자리를 바꾼다.
- 우편 기록 `<FT_ROOT>/.fable-team/comm/mailbox.log.jsonl` · `mailbox.log.jsonl.1`(회전본) · `mailbox.jsonl`(소비되는 현재 큐 — 이것만으로는 이전 발신·읽힌 회신이 사라짐 · DA r1 Q2).
- 설계 `design/harness/DESIGN-511-seat-stall-watch-20261008.md:1` §1 실측 · §4(stalled·⓪ 열) · §4-r2 Q1-r2 8행 표 · Q2-r2 표시 규칙.

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-board.py`(v421 산출 · 지금 좌석 칸 = `scripts/fable-team-bin/ft-news-tree.py` seat_state 복사본을 대체 · + `scripts/harness-install/fable-team/bin/` 사본 · 200줄 넘으면 `ft_board_seat.py` 분리):
   - collect 안에서 현역 좌석마다 `${FT_BOARD_SEAT_STATUS:-<FT_BIN>/ft-seat-status.sh} turn <좌석> --json` 1회 → 설계 §4-r2 Q1-r2 8행 표 그대로 좌석 칸 문자열 + `stalled: bool`(오직 IDLE∧jsonl∧유효 과거 turn_end∧N≥3).
   - 우편 기록 3파일을 seq 로 중복 제거해 1회 읽고, 좌석마다 Q2-r2 표시(`추정: <B> 에 마지막 발신 #N(HH:MM) · 기록상 이후 <B> 회신 없음|있음 #M` · `[HIL]` 발신이면 `추정: HIL 대기 #N(<받는 좌석>)` · 기록 안 발신 없음 `추정: 기록(<시작 HH:MM> 이후)상 발신 없음` · 파일 없음/JSON 오류 `기다림 확인 불가(<사유>)`). 좌석 비교는 계보(`#` 앞).
   - 새 하위 명령 `stalled [--min 3] [--team <명부 파일>]` — 같은 dict 에서 stalled 좌석만 `정지분|좌석|턴 끝|기다림` · 명부 밖 좌석 0.
   - ⓪ 팀 요약 표에 열 `정지(3분+)` = 그 팀 stalled 수(0 아니면 첫 좌석 이름).
   - ⑤ 설계 §4-r3 그대로(판정 514 3구분): 좌석 칸 «뒤» 꼬리 ` · 완료 선언 #<seq>(HH:MM · 증거 있음|증거 없음)`(Q1-r3 표 3행 · 토큰 `[완료·휴식]`/`[완료·휴식 유지 #seq]` 본문 첫 글자 정확 일치 · 증거 줄 정규식 · sha 는 `git cat-file -e <sha>^{commit}` 1회) · `증거 있음` 이면 IDLE∧jsonl 행의 `⚠`·stalled 에서 뺌(`증거 없음` 은 그대로 ⚠) · WORKING ∧ 꼬리 → ` · ⚠완료 뒤 작업` + stalled `완료 뒤 작업|…` 행 · stalled 행 종류 `완료 선언 미처리|<받는 좌석>|<보낸 좌석> #<seq>|N분`(N = 지금 − 원 쪽지 ts ≥ `FT_BOARD_DONE_MIN` 기본 10) · ⓪ 열 `완료 선언` · 기다리는 것 줄 Q2-r3 추정 표기(「다음 일 대기」「처리 없음」 글자 0). ★r2 칸 글자·분 계산·null turn_end 취급은 한 글자도 안 바꾼다★.
2. 시험 `tests/harness/test_board_seat_cell.sh`(v421 의 `tests/harness/test_board.sh` 는 그대로 PASS): 8행 표 각각 + 미래 시각·깨진 ISO·null turn_end → 분 0·stalled 0 ┃ IDLE jsonl 2분 → `정지 2분` · 5분 → `⚠정지 5분` · stalled 출력 1줄 ┃ 기다림 6종(회신 없음 · 회신 있음 · 승계 회신 · 회전본에만 발신 · 기록 시작 이전 발신 → 「기록상 발신 없음」 · `[HIL]` 발신) + 로그 JSON 깨짐 → 확인 불가 ┃ `stalled --team` 명부 밖 0 ┃ ⓪ 열 수 = stalled 수 ┃ 스텁 호출 수 = 좌석 수 · render 2종 뒤 증가 0 ┃ 「발주 필요」 문자열 출력 0 ┃ ★§4-r3 시험 ⑩~㉒ 전부★(설계 §4-r3 「시험 추가」 절 그대로 · 가짜 리포 sha 는 임시 `git init` 커밋 1개 · `FT_BOARD_NOW` 고정).
3. `test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: `ft-seat-status.sh` 수정(호출만) · 우편 파일 쓰기 · tmux·실제 jsonl 조회 · 좌석 깨우기/닫기 · 정본 `~/.claude/skills/**` 수정(문구는 master 가 따로 설치) · planner-idle-scan.sh 삭제(planner 몫).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_board_seat_cell.sh` rc=0 · `bash tests/harness/test_board.sh` rc=0 · `test_kit_bin_sync.sh` PASS · 사본 cmp · `ruff check` 0.
- RESULT 에 ★8행 표 픽스처 렌더 출력 + ⑩·⑪·⑭·⑰ 렌더 + `stalled` 출력★ 복붙.
- 카드 증거 줄(필수 · RESULT 맨 끝 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_board_seat_cell.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN 반영 · 실제 루트 `ft-board.py stalled --min 3` 1회 실측(planner-idle-scan.sh 출력과 교차 — 보조) · planner 에 대체 알림.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#17 · 설계 §4-r2 · DA r2 APPROVE #64794 · 판정 511).
- 2026-10-08 22:2x — 판정 514 3구분 반영(§4-r3 · 범위 1-⑤ · 시험 ⑩~㉒ · 보류 해제 조건 기록) — byz-harness-arch-claude#18. spawn 은 선행 ② 랜딩 뒤 master.
- 정본 영향: 이 카드는 하네스 도구·시험만. 정본 문구(governance §8·§9 · BOOT 18·19)는 `design/harness/staged-514/` 로 설치 완료(카드 밖 · staged-511 대체).
