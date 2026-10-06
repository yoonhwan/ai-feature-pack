# REQ — planner 이슈 큐 · v65 대형 리스트 분할 병렬 · 병합 랜딩 실측 (ft-harness-arch#1 → ft-harness-nano#1 · 2026-10-05 · 조각 P5)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 표 A(모니터) + 표 C(커밋·푸시·반영) — 일이 큐로 들어와 메인팀에서 끝나고 랜딩까지 가는 길. 발주 = ops#2 ORDER-planner-issue-queue(#56994).

읽기 전용 · 수정 0 · Slack 0. 산출 `design/harness/issue-improvement/FACTS-planner-queue-20261005.md`(표 4개 · [사실]/[추측] · 「파일:줄」 또는 명령 1줄 인용) + 원본 `facts-raw/Q*.txt`. 측정 시각(KST) 1줄. 루트 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` · v65 정본 사본 = `.worktrees/v6-realtime-live`.

## Q1. v65 대형 리스트 분할 병렬 랜딩 실례 (10-03 main 랜딩)
- `.worktrees/v6-realtime-live/design/v65/20261003/CLOSEOUT-v65-main-landing-20261003.md` + `CHECKLIST-v65-main-landing.md`: 분해 단위(S1~S9 가 무엇인지 각 1줄) · 나노 수 · 랜딩 순서 · 막힌 곳(S10 사고 등) · 최종 main sha — 「파일:줄」 인용.
- `.worktrees/v6-realtime-live/design/v65/LANDING-POOL.md`: 역할 · 행 수 · 열 이름 · 최근 5행 상태값.
- 나노 랜딩 원장: `.fable-team/state/` 또는 `design/v65/**` 에서 `cherry-gate*.log`·`nano-ledger*`·`NANO-LEDGER*`(최신 1개) — 경로 · 행 수 · 열 · 최근 3행.
- `git -C .worktrees/v6-realtime-live log --oneline --since=2026-10-02 --until=2026-10-04 main` 중 「랜딩·squash·S\d」 포함 커밋 수 + 예 5건(sha·제목).

## Q2. 병합·랜딩 실제 절차 (기계)
- `ft-nano-cherry-gate.sh`(`.worktrees/v6-realtime-live/.fable-team/bin/`): 입력·모드(intake/close) · 「+ 커밋 0」 판정 명령(`git cherry`) · override 원장 경로 · exit 코드 — 「파일:줄」.
- `ft-nano-close.sh` ⑤ 산출물 회수 조건 + `ft-nano-freshness.sh` 4값 + `ft-nano-spawn.sh` 의 미랜딩 REJECT(:100~109) — 각 1줄 인용.
- `docs/rules/single_set_testing.md` §3(병합→시험→랜딩 순서) · `docs/rules/git-worktree-pitfalls.md` ★0·★5b·5d·7 · `~/.claude/rules/closeout-policy.md` 5(닫기 체크) · 메모리 「Main merge commit: abort if main moved(10-03 S10 사고)」 원문(`~/.claude/projects/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents/memory/feedback_main_merge_commit_tree_must_include_moved_main.md`) — 각 1~2줄 인용.
- 랜딩 집행자 규칙: STRUCTURE-main-satellite §1-4 「랜딩 집행 = 영역 소유 메인 오케」 · §2 랜딩 행 — 1줄 인용.

## Q3. planner BOARD 가 지금 큐를 다루는 방식
- `.worktrees/v6-realtime-live/design/planner/BOARD.md`(r42): 절 제목 전부 · 행 수(팀별) · 상태 어휘(✅🔄⏳⏸) 건수 · 「즉시/라이브」 류 우선 표기가 있나 · 「오빠 GO」 줄 수.
- `design/planner/GUIDE-planner.md` 3항(분류 ⓪①~④) · 4항(1통 = 1 Issue → issue-manager) 원문 · `design/issues/LOOP-LEDGER.md` 우선순위 열 값 분포.
- planner → 팀 투입 실례: mbox.log 에서 `from byz-planner-arch#*` 중 「Issue #\d+」 포함 건수 + 예 3건 첫 줄 · 「GO」 포함 건수.

## Q4. 팀별 「최종 완성 골」 파일
- v65 `design/v65/20260909/GOAL-archastra-lst-on-off-completion.md` · cfo `design/cfo/GOAL*` 또는 `00-GOAL-AND-SCOPE*.md` · ccu `design/ccu/GOAL*` · kk `design/kk/GOAL*` · harness `design/harness/GOAL-harness.md` · issues `design/issues/GOAL-issues.md` — 존재 Y/N · 경로 · 축 수(표 행 수).

회신 mbox 3줄: 경로 · 못 한 항목 · 사실/추측 비율. 커밋 0(ops#2 요청).
