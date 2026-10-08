# 인덱스: 상태판 카드 제목 = 첫 5줄 안의 첫 `# ` 줄 (`<!-- ledger -->` 주석·빈 줄 건너뜀 · 없으면 `<id> (제목 없음)`) (R52 · master#18 #65016 · 나노 1)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 원장 R52(master#18 발견 #65016 — cfo·feature 카드 제목이 ledger 주석 줄로 나옴)
- 상태: 대기
- 선행: 없음(origin/main a7fcb904bb 이후 `scripts/fable-team-bin/ft_board_collect.py` 만)
- 시험 입력: 임시 디렉터리 카드 픽스처(첫 줄 형식 4종) — 실제 카드 폴더·tmux·gh 0
- 기준값(21:5x 실측 · 9팀 정본 카드 1010장): 첫 줄 `# ` 948 · `<!-- ledger: … -->` 62(cfo 8 · feature 15 · issues 3 · planner 3 · v65 33) · 기타 8(v65 · `## 골 원문 …`) · 첫 5줄에 `# ` 없음 6(v65) — 지금은 62+8 장의 제목이 주석·절 제목으로 보인다

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터 — 오빠가 보는 상태판의 제목이 틀리게 나옴). 핵심 한 줄: 카드 제목을 «첫 줄»이 아니라 «첫 제목 줄»에서 읽는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
상태판 `ft-board.py`(PR 989 · 판정 §77)는 카드 제목을 `ft_board_collect._title` 에서 파일의 «첫 줄»로 읽는다. 그런데 팀마다 카드 첫 줄이 `<!-- ledger: design/<팀>/GOAL-<팀>.md -->` 주석인 꼴(제목은 둘째 줄)이 섞여 있어, master#18 이 명부 키를 넣고 실제 렌더를 돌리자 cfo·feature 카드 제목이 주석 줄로 나왔다. 9팀 정본 카드 1010장 실측: 주석 첫 줄 62장 · `## 절 제목` 첫 줄 8장 · 첫 5줄에 `# ` 가 아예 없는 카드 6장(v65). 고침: 첫 5줄 안에서 `# `(H1)로 시작하는 첫 줄을 제목으로 쓰고(빈 줄·`<!--` 주석·`##` 이하 절 제목은 건너뜀), 없으면 `<카드 id> (제목 없음)` — 조용히 다른 줄을 고르지 않고 없다는 사실을 보인다. 카드 파일은 고치지 않는다(읽는 쪽만).

## 사전검증
- 소환: 아니오
- 면제: 표시 전용 읽기 규칙 1개(제목 줄 선택) · 상태·계수·스냅샷 계약 무변경 · 되돌림 = 함수 1개 · 사전 DA 대상 아님(bounded_da_review 범위 밖 · 판정 §77 설계 범위 안 표시 결함) — arch 서명 byz-harness-arch-claude#17

## 조사 근거
- `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/cfo-ops-refund-order-lookup/scripts/fable-team-bin/ft_board_collect.py:18-21`(origin/main 과 cmp 같음 · ops/main-base 엔 없는 main 전용 파일) `_title` — `f.readline()` 첫 줄 하나만 읽고 `^#+\s*(인덱스:\s*)?` 를 뗀다(origin/main a7fcb904bb).
- `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/cfo-ops-refund-order-lookup/scripts/fable-team-bin/ft_board_collect.py:35` 같은 id 의 최신 파일로 `_title(newest)` 호출 — 호출부는 그대로.
- 팀별 정본 카드 폴더 = master 명부 키 표(`.fable-team/state/drafts-r21/BOARD-ROSTER-KEYS-20261008.md` · 명부 `_cards`·`_cards_wt` 기입 완료 #65016).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft_board_collect.py` `_title`(+ `scripts/harness-install/fable-team/bin/ft_board_collect.py` 사본): 파일 첫 5줄을 읽어 `# `(정확히 H1 · `## ` 아님)로 시작하는 첫 줄 → `^#\s*(인덱스:\s*)?` 를 떼고 80자 · 없으면 `f"{id} (제목 없음)"`(id = 파일 basename 확장자 제외 · 호출부에서 id 를 넘기거나 path.stem 사용). 파일 200줄 넘지 않게.
2. 시험 `tests/harness/test_board.sh` 에 단언 추가: ①첫 줄 `<!-- ledger: … -->` + 둘째 줄 `# 인덱스: 진짜 제목` → `진짜 제목` ②빈 줄 + 주석 + `# 제목` → `제목` ③첫 줄 `## 골 원문 …` · 셋째 줄 `# 인덱스: X` → `X`(`##` 건너뜀) ④첫 5줄에 `# ` 없음 → `<id> (제목 없음)` ⑤기존 첫 줄 `# 인덱스: …` 카드 결과 그대로 ⑥슬랙 렌더에 주석 문자열 `<!--` 0.
3. `tests/harness/test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 카드 파일 수정 · 다른 `ft_board_*` 수정 · 라이브 FT_BIN 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_board.sh` rc=0 · `test_kit_bin_sync.sh` PASS · 사본 cmp · `ruff check` 0.
- RESULT 에 ★시험 ①~④ 픽스처의 렌더 제목 4줄★ 복붙.
- 카드 증거 줄(필수 · RESULT 맨 끝 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_board.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp+cmp · 실제 루트 `ft-board.py render --term` 1회 — `<!--` 제목 0 · `(제목 없음)` 은 v65 6장 안팎.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: a7fcb904bbc6d3abbc78bc716ffd2e3a7bd22beb (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#17 · R52 · master#18 #65016).
- 정본 영향 없음: 하네스 도구·시험만.
- 2026-10-08 21:50 — 대기→진행 · 좌석 byz-harness-nano-r52-board-card-title#0
세트: 6a3165ca75c5c740c96f5741c063a1b2e7459d49 · 시험: bash tests/harness/test_board.sh rc=0 · 이슈: 0
