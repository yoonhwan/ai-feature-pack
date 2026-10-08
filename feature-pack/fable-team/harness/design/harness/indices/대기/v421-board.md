# 인덱스: 상태판 생성기 — ft-board.py(render --term|--slack · snapshot) · 명부 키 _cards·_cards_wt·_label · 불변 스냅샷 + 변경 단위 diff (판정 421 · 430·431 · 설계 §2-2·§2-3·§3 나노 2)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 421·430·431(오빠 「뉴스 팀트리와 작업큐를 시각화해 사용자에게 공유하는 완벽한 일반화」 · planner #62745 · master #62749)
- 상태: 대기
- 선행: 나노 1(판정 원장 ft-verdict.sh · nano/v430-verdict-ledger) 랜딩 · 나노 4(인박스 ft-inbox.sh · nano/v425-master-inbox) 랜딩 — 이 카드는 두 도구를 «호출»만 한다(fold·술어 재구현 0). 나노 3(발행)은 이 카드 뒤.
- 시험 입력: 임시 FT_ROOT(가짜 seats-*.json 3팀 · 카드 폴더 픽스처 · 가짜 verdicts.jsonl) + 스텁 env FT_BOARD_GH(gh issue list JSON 고정 출력) · FT_BOARD_TMUX(살아 있는 세션 목록 고정) · FT_BOARD_INBOX(ft-inbox.sh show 고정 출력) — 실제 gh·tmux·슬랙 호출 0
- 기준값: 지금 ft-news-tree.py 199줄 · 명부 1개(seats.json)만 읽음 · SEAT_PREFIX = FB_CFO·CFO_ 하드코딩(ft-news-tree.py:67) · 요약본 ✅ 가지 통째 소실 · 세션 상태 절 옛 좌석 25줄 · NEWS-TREE.md `[idx:]` 0개

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 「뉴스 팀트리와 작업큐를 시각화해 사용자에게 공유」). 핵심 한 줄: 손 트리를 버리고 원장 3종(명부·카드 폴더·판정 원장)에서만 팀 트리·작업큐·오늘 판정표를 생성하고, 매 생성의 불변 스냅샷과 변경 단위 diff 를 남긴다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
지금 뉴스 트리는 planner 가 손으로 쓰는 NEWS-TREE.md 와 ft-news-tree.py(명부 seats.json 하나만 읽고 CFO 접두 좌석만 보는) 조합이라 ①오늘 끝난 일(✅)이 요약본에서 통째로 빠지고 ②죽은 옛 좌석 25줄이 세션 상태 절에 남고 ③상태 글자가 손 글자라 콘솔·슬랙·트리가 서로 다르다(판정 410 감사 17건). 새 생성기 ft-board.py 는 입력을 원장 3종으로만 한다: 명부 `seats*.json`(팀 = 파일 1개 · 새 키 `_cards` 카드 폴더 리포 상대 경로 · `_cards_wt` 그 폴더가 있는 워크트리 이름 · `_label` 표시 이름) · 팀별 카드 폴더 indices/{대기,진행,완성} · 판정 원장(`ft-verdict.sh list --json`). 출력 한 장 = 세 칸(팀 트리 · 작업큐 · 오늘 판정표)이고, 같은 중간 dict 에서 `--term`/`--slack` 렌더만 다르다. `snapshot` 은 그 dict 전체를 불변 파일로 먼저 쓰고 직전 스냅샷과의 «변경 단위» 목록을 낸다 — 슬랙 chat.update(나노 3)는 최신만 보이므로 이력은 이 스냅샷이 가진다(DA N3 APPROVE). 팀이 늘어도 명부 파일 1개 추가로 끝나야 한다(코드 수정 0).

## 사전검증
- 소환: 아니오
- 면제: 사전 DA 는 소환됐고 2 HOLD 로 리뷰 종료(bounded_da_review · 판정문 design/harness/DA-news-board-20261009.md §2~§8 · N3(스냅샷→update→변경 단위 diff) APPROVE · 이 카드는 N3 범위) → 오빠 컨펌 GO 판정 430·431(planner #62745 · master #62749) · 잔여는 완료 조건 시험으로 닫고 구현 DA 에서 재확인 — arch 서명 byz-harness-arch-claude#14

## 조사 근거
- `design/harness/DESIGN-news-tree-workqueue-viz-20261009.md:28` 명부 새 키 3개 · `:33`~`:41` 생성기 세 칸·행 수 상한·옛 좌석 제거·렌더 2종 · `:45` 스냅샷 → update → 변경 단위 diff · 실패 순서 · 날짜 동결 · `:56` 보드 작업큐 칸 수신 대기 n 과 미보고 n 분리 · `:71` 나노 2 시험 목록 · `:139` N3 APPROVE(누락 답글 복구는 입력 해시가 같아도 막히지 않게).
- `scripts/fable-team-bin/ft-news-tree.py:67` SEAT_PREFIX 하드코딩 · `:75` seat_state(재사용 대상) · `:89` session_block(삭제 대상 — 옛 좌석) · `:149` render(full=False 가 ✅ 가지를 뺌).
- `scripts/fable-team-bin/ft-news-tick.sh` · `scripts/fable-team-bin/ft-news-tick-cfo.sh` — 지금 ft-news-tree.py 를 부르는 곳(이 카드는 호출부를 바꾸지 않는다 · 전환은 나노 3).
- 나노 1 산출 `nano/v430-verdict-ledger:scripts/fable-team-bin/ft-verdict.sh` — `list [--today] [--json]` 이 n 으로 fold 한 결과(state open/done · oppa_todo 최신)를 낸다. 이 카드는 그 출력만 읽는다.
- 나노 4 계약 `design/harness/indices/진행/v425-master-inbox.md` — `ft-inbox.sh show <좌석>` 은 정본 술어 obligation_closed 가 거짓인 줄만 낸다. 미보고 수 = 그 줄 수(술어 재작성 0).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-board.py` 신설(+ `scripts/harness-install/fable-team/bin/ft-board.py` 사본 · 파일 200줄 넘으면 같은 디렉터리 `ft_board_*.py` 로 분리 허용 · ft-news-tree.py 는 그대로 둔다):
   - 입력 수집 `collect() -> dict`: ①`<FT_ROOT>/.fable-team/seats*.json` 전부 — `_cards` 없는 명부는 팀 트리에 «카드 폴더 미지정» 1줄로 보이고 빠지지 않음 ②카드 폴더 = `<FT_ROOT>/.worktrees/<_cards_wt>/<_cards>/{대기,진행,완성}`(`_cards_wt` 가 비면 루트) · 파일 수 + 첫 줄 제목 · 완성은 mtime 오늘분만 «오늘 완성» ③`ft-verdict.sh list --json`(env FT_VERDICT_BIN 으로 경로 주입) ④`${FT_BOARD_GH:-<Tank 래퍼> gh issue list --json number,title,labels,updatedAt,state}` — 캐시 `<FT_ROOT>/.fable-team/state/board/gh-cache.json` 10분 ⑤살아 있는 tmux 세션(`${FT_BOARD_TMUX:-tmux ls -F '#S'}`) ⑥인박스 미보고 = `ft-inbox.sh show <팀 _master>` 줄 수 · 수신 대기 = mailbox pending(따로 셈 · 설계 :56).
   - 현역 좌석 = tmux 살아 있음 ∧ 행 `_replaced_by` 없음 · master/arch 는 명부 `_master`/`_arch` 와 같은 이름만 · 진행 카드마다 행 `index` 가 같은 좌석 1줄(좌석 상태 = `scripts/fable-team-bin/ft-news-tree.py:75` seat_state 와 같은 규칙 · 함수 복사 허용 · 그 파일은 수정 0).
   - 세 칸: ①팀 트리(팀 → master·arch → 진행 카드별 나노 1줄 → 「대기 n · 오늘 완성 n(마지막 1개 제목)」) ②작업큐(오빠 손 대기 = 판정 open ∧ oppa_todo 비지 않음 → 열린 Issue(라벨 hil:needed 먼저) → 팀별 대기 카드 상위 5 · 「수신 대기 n」 「미보고 n · 가장 오래된 m분」 따로) ③오늘 판정표(`n · 제목 · open/done · 팀` — done 도 표시).
   - 행 수 상한(팀당 5줄 · 큐 10줄)만으로 요약 — 넘치면 「… 외 n」 · ✅/done 을 통째로 빼는 분기 0.
   - `render --term | --slack`: 같은 dict · slack 은 mrkdwn 문자열만 stdout(발행 0).
   - `snapshot`: dict 를 정렬 JSON 으로 `<FT_ROOT>/.fable-team/state/board/<YYYY-MM-DD>/<HHMMSS>-<hash8>.json`(hash8 = 본문 sha256 앞 8) 에 «먼저» 쓰고(fsync) → 같은 날 직전 스냅샷과 비교한 변경 단위 목록 + `snap=<전 hash8>→<후 hash8>` 를 stdout JSON `{snap, prev, changes[], prev_day_last}` 으로. 변경 단위 = 카드 이동 `<팀>/<카드> 진행→완성` · Issue `#N open→closed` · 판정 `N new/done` · 오빠 손 ±. 카드·Issue 만 바뀌어도 changes 가 비지 않는다. 쓰기 실패 = raise(rc≠0 · stderr 사유) — 나노 3 은 rc=0 일 때만 발행. 날짜 첫 스냅샷이면 `prev_day_last` = 전날 마지막 스냅샷 hash8(뿌리 글 동결용).
   - 입력이 직전과 같아도 `snapshot` 은 막지 않는다(설계 :139 누락 답글 복구) — 같으면 changes 빈 배열 + 같은 hash8.
   - 30일 정리는 `prune --days 30` 명시 명령만(자동 삭제 0).
2. 시험 `tests/harness/test_board.sh`(가짜 FT_ROOT · 스텁 env 4종):
   - 팀 추가 = 명부 파일 1개 추가만으로 팀 트리에 나타남(코드 0) · `_cards` 없는 명부 = 「카드 폴더 미지정」 줄.
   - 옛 좌석 0: tmux 죽은 좌석 · `_replaced_by` 있는 좌석은 어떤 칸에도 안 나옴.
   - 오늘 done 판정 · 오늘 완성 카드가 요약 렌더에도 보임(✅ 소실 0).
   - snapshot 1회 → 카드 1장 진행→완성 이동 → snapshot 2회: changes 에 그 이동 1건 + snap 전·후 id · 판정 변화 0 이어도 changes 비지 않음.
   - Issue 만 open→closed 바뀐 경우 changes 1건.
   - 스냅샷 디렉터리 쓰기 불가(chmod) → rc≠0 · stdout 빈 값.
   - 날짜 바뀜(env FT_BOARD_NOW 로 시각 주입) → prev_day_last = 전날 마지막 hash8.
   - 같은 입력 2회 snapshot → 둘 다 rc 0 · changes 빈 배열.
   - 미보고 n 과 수신 대기 n 이 다른 칸에 따로 찍힘.
   - `test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 슬랙 호출·발행(나노 3) · ft-news-tick*.sh 호출부 교체(나노 3) · 명부 실제 파일에 키 추가(master 집행) · 판정 fold·obligation_closed 재구현 · NEWS-TREE.md 상태 글자 읽기 · 라이브 .fable-team/state 쓰기 · ft-news-tree.py 삭제.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_board.sh` rc=0 · `test_kit_bin_sync.sh` PASS · 사본 cmp · `ruff check` 0.
- RESULT 에 ★「카드만 바뀐 두 번째 snapshot 의 changes 1건 + snap 전→후」★ 출력 복붙 — 구현 DA 가 재확인.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_board.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 명부 9개에 `_cards`·`_cards_wt`·`_label` 기입 · 라이브 FT_BIN 반영 · 실제 루트에서 `ft-board.py render --term` 1회 실측(옛 좌석 0 · 팀 수 = 명부 수).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#14 · 판정 421 설계 r2 §2-2·§2-3·§3 나노 2 · 오빠 컨펌 판정 430·431 · master #62749).
- 정본 영향 없음: 하네스 도구·시험만 — docs/architect 제품 정본 변경 없음.
