# r727 — 매거진 시험 픽스처 복사목록 정정 (ft_goal_readjust_state.py 1줄)

## 원인
r714a(4006c9d7)가 `harness/bin/ft_goal_table.py:36,38` 에 `from ft_goal_readjust_state import header/row_cell` 을 추가했다.
`tests/scripts/test_magazine_goal.py` 픽스처는 판정기 파일 6개만 임시 루트 `.fable-team/bin` 으로 복사하므로
새 모듈이 없어 임시 루트 판정기가 rc=1 Traceback → 매거진 시험 3칸 빨강.
실설치(LIVE 1.1.207)에는 모듈이 같이 깔려 실운영 영향 0.

## 고침
`test_magazine_goal.py` 복사 목록에 `"ft_goal_readjust_state.py"` 1개 추가.
`ft_goal_table.py` 의 로컬 import 전수 대조 결과 빠진 모듈은 이것 하나뿐
(`ft_goal_readjust_state.py` 자체 import 는 json·os·datetime·pathlib 만 = 의존 0).

## 시험 원문 (파일)
- `a-red-before-fix.txt` — pack main 4006c9d7 그대로: **3 failed, 2 passed** (rc=1)
- `b-green-magazine.txt` — 고친 뒤: **5 passed** (rc=0)
- `c-neighbor-news.txt` — `test_ft_news_publish_import_path.py`: **5 passed** (rc=0)
- `c-neighbor-goal-table-procs.txt` — `tests/test_goal_table_procs_r644.sh`: **ALL PASS** (rc=0)

## 실행 방식
팩에는 `.venv` 가 없어, 도구용 venv(BYZ-Agents 워크트리 `.venv/bin/python`, pytest 설치본)로
팩 시험 파일 절대경로를 돌렸다. 시험 코드·입력은 팩 파일 그대로다.
ⓐ(빨강) 재현은 `git stash push -- <시험파일>` → 실행 → `git stash pop` 으로 했다(제품·bin 무변경).

## 부수 관측 (무관 · 미수정)
첫 ⓐ 캡처에서 `real_state_guard` teardown 이 `REAL-STATE-GUARD FAIL 우편함 가짜 이름 새 줄: ['byz-issues-master-claude#24']`
로 한 번 떴다 — 다른 팀 mbox 트래픽(140496)이 실행 중 `.fable-team/comm/mailbox.jsonl` 에 들어온 환경 잡음이며
이 카드 변경과 무관하다. 재실행 캡처(a-red-before-fix.txt)에는 없다.

## press
press 필요 없음 — 단위 시험만으로 닫힌다. 라이브 오디오 시험 0.
