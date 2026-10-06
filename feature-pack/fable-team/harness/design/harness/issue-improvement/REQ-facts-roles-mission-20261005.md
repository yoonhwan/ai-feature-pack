# REQ — planner·issue-manager 역할 + 병렬 발주·처리 + 미션 클리어 실측 (ft-harness-arch#1 → ft-harness-nano#1 · 2026-10-05)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 표 A(모니터) 둘째 단위 「각 오케가 일을 어떻게 받고 병렬로 처리·클리어하는지」. 발주 = ops#2 `ORDER-roles-mission-flow-20261005.md`(eb5ca07b0e).

읽기 전용 · 코드·명부 수정 0 · Slack 0. 산출 `design/harness/issue-improvement/FACTS-roles-mission-20261005.md`(표 4개 · 각 행 [사실]/[추측] · 「파일:줄」 또는 명령 1줄 인용) + 원본 `facts-raw/R*.txt`. 측정 시각(KST) 1줄. 경로는 전부 루트 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` 기준(워크트리 안이면 그 경로 그대로 적는다).

## R1. planner · issue-manager 가 «실제로» 하는 일
- `design/planner/{GOAL-planner,GUIDE-planner,STRUCTURE-main-satellite,BOARD,NEWS-TREE,README}.md` — 각 파일에서 「planner 가 하는 일 / 하지 않는 일 / 출력 정본」 문장을 「파일:줄」로 인용(파일당 ≤3줄). BOARD.md 의 행 수·열 이름·상태값 종류.
- `design/issues/{GOAL-issues,README,LOOP-LEDGER}.md` + `design/issues/indices/` 구조(폴더·건수) — issue-manager 루프 단계(폴링→수정→테스트→랜딩→클린업)가 적힌 줄 인용 · LOOP-LEDGER 행 수 · 최근 3행 상태값.
- `.fable-team/seats-planner.json`·`seats-issues.json` 의 `_doc`·`_hil_route`·행 수.

## R2. planner → 메인팀 발주 실측 (mbox 로그)
- `.fable-team/comm/mailbox.log.jsonl`(없으면 `.fable-team/mailbox/` 아래)에서 `from` 이 `byz-planner-arch#*` 인 행 전수: 건수 · to 별 건수(v65/cfo/ccu/kk/harness-ops/issue-manager) · 최초·최근 시각 · 본문 첫 줄 형식 3건 예시(태그·번호 매김 방식).
- 반대 방향(`to` = planner): 팀별 건수 · `[HIL]` 포함 건수.
- 같은 to 에 답 안 받고 겹쳐 보낸 흔적(연속 send 2건 이상 · ring 아닌)이 있나 — 있으면 seq 쌍 3개.

## R3. 나노·세션 병렬 처리 기계
- 스크립트 위치 확정: `.worktrees/v6-realtime-live/.fable-team/bin/ft-nano-{slots,spawn,close,freshness,cherry-gate}.sh` 와 `scripts/fable-team-bin/` · `~/.claude/fable-team/` 중 어디에 있나(`ls` 결과 그대로 · 심링크면 target).
- `ft-nano-slots.sh`: `FT_NANO_SLOTS` 기본값 · 「슬롯 찬」 판정 기준(세션? 카드? 워크트리?) · 출력 형식 1줄 인용.
- `ft-nano-spawn.sh`: 입력(카드 경로·브랜치) · 만드는 것(워크트리·세션·카드 이동 대기→진행) · 린트(`## 배경` 필수 등) — 「파일:줄」.
- `ft-nano-close.sh`: 닫는 조건·순서(wip 커밋→워크트리 정리→태그 해제→세션 kill) — 「파일:줄」.
- `ft-nano-freshness.sh`: 보는 4값(base·뒤처짐·겹침·미랜딩) 「파일:줄」.
- GPU·오디오 press 직렬 규칙이 적힌 곳: `docs/rules/single_set_testing.md` · `.worktrees/ccu-stress/design/ccu/DESIGN-ccu-stress-infra.md` §GPU 공유 — 각 1줄 인용.

## R4. 팀별 미션 큐 현재값 (대기·진행·완성)
| 팀 | indices 경로 | 대기 | 진행 | 완성 | 진행 카드 ↔ 살아 있는 tmux 세션 대조 |
- v65: `design/v65/indices/{inbox,대기,진행,완성}` 건수 · 진행/ 카드마다 세션명 → `tmux ls` 에 있나 Y/N.
- cfo: `.worktrees/c-level-planning/design/cfo/{indices,orders}` 구조·건수.
- ccu: `.worktrees/ccu-stress/design/ccu/` 에서 ORDERS·CLOSEOUT·진행 표시 파일 — 큐 구조가 있나 없나(없으면 「없음」).
- harness-ops: `design/harness/indices` · `REQUEST-LEDGER.md` 행 수·상태값.
- 「클리어」표시 방식: 각 팀이 완성을 어떻게 표시하나(완성/ 이동 · CLOSEOUT 파일 · LEDGER 행 상태) — 파일명 1개씩 예시.

회신 mbox 3줄: 경로 · 못 한 항목 · 사실/추측 비율. 커밋은 ops#2 에 요청(나노는 커밋 0).
