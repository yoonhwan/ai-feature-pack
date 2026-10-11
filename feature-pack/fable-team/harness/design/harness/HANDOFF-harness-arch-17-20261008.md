# HANDOFF — byz-harness-arch-claude#17 → #18 (2026-10-08 · 컨텍스트 401k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` Read → Serena `initial_instructions` → `activate_project(project="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops", session_id=…)`(session_id 없이 부르면 다른 워크트리가 잡힘) → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(지금 byz-harness-master-claude#18 — 발신 전 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/seats-harness.json` `_master` 확인)에 mbox. 같은 턴 CronCreate 10분 틱(mbox recv + 하네스 나노 `ft-seat-status.sh turn` 실측 + 오빠 보고).
3. master 에 부탁: `bash .fable-team/bin/ft-seat-retire.sh byz-harness-arch-claude#17 byz-harness-arch-claude#18 --seats .fable-team/seats-harness.json`.
- planner 현역 = byz-planner-master-claude#13(#12 정지레디 · #64964).

## ★지금 할 일 (master#18 #65042)★ — R52 나노 독립 재현 + 닫힘 초안
- 세트: 브랜치 `nano/r52-board-card-title` 커밋 `6a3165ca75c5c740c96f5741c063a1b2e7459d49` · RESULT 전문 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/bodies/65041.txt`.
- 카드: `design/harness/indices/진행/r52-board-card-title.md`(사전 DA 면제 · 표시 전용). 재현: `git -C <나노 워크트리> archive 6a3165ca75 scripts tests/harness tools/comm-canonical | tar -x -C <스크래치 새 폴더>` → `test_board.sh` · `test_kit_bin_sync.sh` · 사본 cmp(`scripts/fable-team-bin/ft_board_*.py` ↔ `scripts/harness-install/fable-team/bin/`) · ruff · 범위 밖 파일 0(`git diff --stat origin/main...6a3165ca75`). 실데이터 확인: 9팀 정본 카드(`.fable-team/state/drafts-r21/BOARD-ROSTER-KEYS-20261008.md` 표)에서 주석 첫 줄 62장이 제목으로 바뀌는지 `_title` 직접 호출로.
- 닫힘 초안 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/OPS-VERDICT-78.md`(§78 · 「대상 카드: r52-board-card-title」 · 형식은 OPS-VERDICT-77.md 참조) → master#18 에 경로.

## 이 세션에서 닫힌 것
| 단위 | 판정 | 반영 |
|---|---|---|
| 슬랙 = 읽기 전용 공유판(답장 요구 0 · 머리표 · 결정 자리 = live_planner · inbound @planner) | §76 | PR 983 a752a987d3 · 라이브 설치(스크립트 12 cmp) |
| 상태판 ft-board(v421 + 판정 496 ⓪팀 요약·①완성 트리 · 오빠 컨펌 502) | §77 | PR 989 a7fcb904bb · 라이브 FT_BIN · 명부 9개 `_cards`·`_cards_wt`·`_label`·`_tree` 4팀 기입(#65016) |

## 대기 카드 (순서 = master 한 번에 하나)
- `대기/r49-question-board.md` — 슬랙 질문 보드 UTF-8 3500 바이트 상한 + 닫는 사건 = planner 인박스 `미닫힘=`(DA r2 APPROVE · 설계 `design/harness/DESIGN-r49-question-board-20261008.md` §2-r2 가 이김). 라이브는 지금도 `chat.update msg_too_long` 반복(실측 거부선 3909~4073 바이트).
- `대기/v511-seat-stall-cell.md` — ★보류(판정 516)★: 정본 문구는 판정 514 와 합쳐 Fable 루트 지침 좌석(byz-harness-nano-root-guideline-514#0 · RESULT 커밋 6f24b266ff · seq 64968)이 다시 씀(상태 3구분: 진행 / 정지·미완=깨움 / 완료·휴식=다음 일 질문). 그 지침이 정본으로 확정되면 카드의 좌석 칸 8행 표(설계 `design/harness/DESIGN-511-seat-stall-watch-20261008.md` §4-r2)를 3구분에 맞춰 고친 뒤 master 에 spawn 요청. `design/harness/staged-511/` 는 설치 보류(HOLD-516.md).
- `대기/v423-publish-report-hooks.md`(판정 421 나노 3 · 발행·ft-news-tick 호출부 교체) — 선행 v421 랜딩 끝 → 착수 가능 여부는 master/planner 순서.

## 함정 (실측 · 이 세션)
- 카드 머리줄 기준값은 정확히 `- 기준값:` — 괄호 붙이면(`- 기준값(…):`) 도구가 «기준값 없음» 경고(master#18 #65028).
- ops/main-base 에 없는 main 전용 파일(ft_board_* 등)은 카드 lint 가 «경로 없음» → main 과 cmp 같은 다른 워크트리 절대경로로 인용(`for w in .worktrees/*; cmp …`).
- codex DA 좌석은 `ft-seat-status.sh turn` 이 pane 기준 «IDLE»로 찍어도 실제 `Working` 인 경우 2회 — 상태는 pane `Working (… esc to interrupt)` 줄로 교차 확인. ring 전에 그 줄부터 본다(불필요 ring = 같은 발주 큐 2건).
- 설계에서 «검사에 걸리면 어떻게 하는가»를 비워 두면 나노가 raise 로 채운다 — 슬랙 출력 검사 경계는 «최종 출력 문자열 하나 + 부분 치환»(v421 반송 2회 교훈 · REJECT-v421-board-r1/r2.md).
- 파일 mtime 으로 정본 판단 금지 — 나노 워크트리 체크아웃이 같은 시각을 찍는다(정본 = 팀 env `FT_NANO_LEDGER_WT`·`FT_NEWS_TREE`).
- zsh 에서 `echo ===` 는 `== not found` 오류 — 구분선은 `echo "---"`.
- 판정서 초안 자리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · 다음 번호 §78.
