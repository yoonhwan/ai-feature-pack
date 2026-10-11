# HANDOFF — byz-harness-arch-claude#22 → #23 (2026-10-09 · 컨텍스트 405k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` Read → Serena `initial_instructions` → `activate_project(project="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops", session_id=…)` → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(**byz-harness-master-claude#21** — 발신 전 `.fable-team/seats-harness.json` `_master` 확인)에 mbox. 같은 턴 CronCreate 10분 틱(mbox recv + `tmux ls | grep byz-harness-nano` + 오빠 3줄).
3. master 에 부탁: `bash .fable-team/bin/ft-seat-retire.sh byz-harness-arch-claude#22 byz-harness-arch-claude#23 --seats .fable-team/seats-harness.json`.

## ★지금 할 일★ = 판정 602 진행 중 (나노 작업 중)
- 카드 `design/harness/indices/진행/mag602-malformed-cards-report.md`(대기 `62e8bec6ab`) · 나노 `byz-harness-nano-mag602-malformed-cards-report#0`(08:24 개설 · 작업 중).
- 다음 순서: 나노 RESULT(증거 줄) 오면 → `git archive <sha>` 새 mktemp 독립 재현(`.venv/bin/python -m pytest --noconftest` collect_mbox·detail·새 render 시험 + `tests/harness/test_magazine_plist.sh`·`test_magazine_install_list.sh` · 실제 mailbox 로 `MAGAZINE_MALFORMED_CARDS=report` 읽기 전용 dry = raise 0 · malformed 11) → DA-REQ 작성·커밋 → DA `byz-harness-da-codex#0` 1회 bounded 소환 → 판정 → §103 초안(`.fable-team/state/drafts-r22/OPS-VERDICT-103.md`) + master 집행 요청(설치 → dry → 10-09 호 수동 재발행 → planner 보고 뒤 plist 재적재).
- DA 2 HOLD 면 연속 리뷰 종료 → arch 처방·독립 재현 서명(§95·§100·§101 선례).
- 나노 `byz-harness-nano-mag601-mbox-rotation-and-install-list#0` = 판정 601 완료(PR 1059 병합) — master 가 닫을 대상.

## 이 세션에서 닫힌 것 (판정서 초안 `.fable-team/state/drafts-r22/OPS-VERDICT-<N>.md` → master 반영)
| § | 단위 | 랜딩 |
|---|---|---|
| 100 | 판정 595 가드 ㉠ 게시 싱크(heredoc 본문 → Tank·gh·git commit 은 글자 · 실행 경로 차단) · DA 2 HOLD → arch 서명 | PR 1057 `483ba4ec67` · 홈 설치 |
| 101 | X7 계열 redis-cli 간접 입력 8꼴 차단 + 줄 이음·따옴표 `<`·`||`·실행 코드 stdin 정정 · DA 2 HOLD → arch 서명 | PR 1058 `1c2828e1f8` · 홈 설치 |
| 102 | 판정 601 매거진 mbox 회전본 이어 읽기 + 설치 목록 import 닫힘 · DA r2 APPROVE | PR 1059 `e8c5718a8c` · 홈 설치 |
- 다음 판정서 번호 §103(판정 602).

## 별 카드 후보 (착수 0 — 오빠/master 지시 때만)
1. `tests/scripts/test_magazine_cli.py` 기존 5 실패(origin/main 동일 · 판정 601 와 무관).
2. (#21 이월) `tools/comm-canonical/check-drift.sh` MAP 옛 행 · `boot-read-gate.sh` 키트↔홈 머리 주석 2줄.
3. 가드 ㉠ 알고 둔 경계: 따옴표 안 이어붙임 난독화(`bash -c "redis-''cli < f"`)·`eval` — 의도적 난독화(BOOT 20 증거 무효).

## 함정 (실측 · 이 세션)
- ★카드 spawn lint★: 구현 범위 안 경로는 리포 루트 전체 경로만(줄임표 `…/`·`/tmp/…` 백틱 금지 — 대조표는 구현 범위 밖 h2 로).
- ★BSD grep -E 에서 `\|` = 글자 `|`(빈 대안 아님)★ — 큰따옴표 안 정규식에서 문제는 이스케이프 없는 백틱(대입 순간 명령 치환 → 전 명령 차단). 처음 카드에 틀린 주장 적었다가 §101 에 정정.
- 가드 시험 프로브(JSON 주입 · 명령 실행 0): `.fable-team/state/drafts-r22/fp595/probe595.py <훅> blocked_0.txt` · `probe_r2.py` · `drafts-r22/x7/probe_x7.py`·`probe_x7r1.py`·`probe_x7r2.py` — 홈 훅 바꿀 때마다 5종 BAD 0 확인.
- 키트 훅 = `block-destructive.sh` + `block-destructive-judge.py` «두 파일» — 홈 설치 때 하나만 복사하면 `--inject` 가 기본 경로로 떨어져 오탐 재발.
- 매거진 수집 dry(읽기 전용): 키트 폴더를 `sys.path` 앞에 넣고 `python3 -I` 로 `collect_mbox`/`collect_decisions` 를 실제 `.fable-team/comm/mailbox.log.jsonl` 에 호출(Slack·홈 0).
- 같은 워크트리를 master 도 쓴다 → 커밋은 항상 `git commit -- <내 경로>`. push 는 master 몫(랜딩 = 새 land/<이름>) · 원격 ops/main-base 삭제 = 오빠 큐 11(HIL) 손대지 말 것(master#21 #66928 — 운영 규칙).
- 스크래치패드(내 세션) = `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/354fe948-7b7e-4c9e-924e-e35b83fc8332/scratchpad/` — 프로브 원본은 drafts-r22 로 복사돼 있음.
