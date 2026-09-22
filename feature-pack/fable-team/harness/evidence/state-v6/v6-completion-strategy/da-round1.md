reviewed: v1 (.claude/plans/v6-completion-strategy.md, 2026-07-03 FB_Master#17 → ft-planner opus-4-8)
codex-session-id: 019f2880-aed0-7cb1-9b98-b1fa1ac5e0fd
verdict: CHANGES_REQUESTED

## codex 판정 원문 (xhigh reasoning, gpt-5.5)

VERDICT: CHANGES_REQUESTED

- Serial BTS makes parallel surface coding worthwhile only after common contracts freeze. N2/adapters and origloss affect every surface, so early fanout risks rework.
- COMMON-first is right but incomplete: hooks, adapters, transcript mapping, message rendering, worker events, fixtures, and log parsers are shared blast radius. Add explicit no-touch/approval rules.
- Single worktree is fragile with 4 sessions. Require clean index before BTS lock, small commits per change, and pre-task conflict checks.
- Test serialization needs recovery detail: lock artifact, timeout, cleanup, audio reset, CDP reset, backend restart policy, and log window IDs.
- 작게작게 is not fully respected: Stage 1 bundles too much. Split origloss, toggle, N2 wiring, and PTT display into separately verifiable commits.

## DA 분석 요약 (릴레이)

5개 지적 전부 구체적 실행 위험:
1. 병렬 fanout 타이밍: N2/adapters·origloss 계약이 freeze되기 전 표면 세션이 착수하면 재작업 리스크.
2. COMMON 소유 맵 불완전: hooks/fixtures/log-parsers 등 암묵적 공유 파일이 명시적 소유 맵에 없음.
3. 단일 워크트리 + 4세션 = git index 경합: BTS lock 전 clean-index 강제, pre-task 충돌 체크 미명시.
4. 직렬 BTS 복구 절차 미정의: lock timeout/cleanup/audio reset/CDP reset/backend restart policy/log window ID 부재.
5. Stage 1이 과도 번들: origloss·toggle·N2·PTT display를 4개 독립 슬라이스로 분리 커밋해야 작게작게 충족.
