# 하네스 지도 — 정본 목차 1장 (fable-team 정본 · 2026-10-07 · 오빠 «모든 세션이 하네스를 편하게 조회»)

> 모든 세션은 «어디에 뭐가 있나»를 이 1장으로 찾는다. 조회 명령: `bash <루트>/scripts/fable-team-bin/ft-harness-info.sh <map|rules|seats|requests|find 키워드>` (읽기 전용 · main 의 정본을 읽는다).
> 이 표의 경로가 어긋나면 이 파일이 아니라 «가리키는 정본»이 이긴다. 바꾸면 `ft-harness-info.sh` 의 `rules` 목록도 같이 고친다.

| 알고 싶은 것 | 정본 | 위치 |
|---|---|---|
| 하네스 골(원문 3줄 · 불변) | GOAL-harness.md | 프로젝트 `design/harness/` |
| 좌석 이름 규칙 · 메인 팀 오케 `master` 통일 | main-team-governance.md §1 | 스킬 `references/` (원문 SPEC-session-naming-20261005) |
| 이슈 진입로 3 · 컨펌 게이트 · 해제 조건 | main-team-governance.md §2·§3 | 스킬 `references/` (BYZ 적용본 `design/planner/GUIDE-planner.md`) |
| 세션 부팅 통신 12줄 · 전문 절 지도 | COMM-GUIDE-BOOT.md · COMM-GUIDE.md | `~/.claude/skills/tmuxc/` |
| 좌석 부팅 5단계 · 나노 생명주기 · 틱 | SEATBELT.md | 스킬 `references/` |
| 하네스 요청(개선요청) 원장 R1~ | REQUEST-LEDGER.md | `design/harness/` |
| 배포 판 · 머신별 「반영됨」 | RELEASE-<판>.md · MACHINES.md | `design/harness/` |
| 단위별 수락 판정(닫힘/HOLD) | OPS-VERDICTS-20261006.md | `design/harness/` |
| 랜딩 규칙 · 랜딩 원장 | LANDING-LEDGER.md · `docs/rules/single_set_testing.md` | `design/harness/` · `docs/rules/` |
| 마감(랜딩→push→CLOSEOUT→전부 닫기) | closeout-policy.md | `~/.claude/rules/` |
| 파괴·비가역 작업 HIL · 전역 규칙 | CLAUDE.md | `~/.claude/` |
| 이슈 루프·재현 e2e | `design/issues/{GOAL-issues,README,LOOP-LEDGER}.md` | 프로젝트 |
| 라이브 좌석(이름 lint 포함) | `ft-harness-info.sh seats` | tmux + `ft-name-lint.sh` |
