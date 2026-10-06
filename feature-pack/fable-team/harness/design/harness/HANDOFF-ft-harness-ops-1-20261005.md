# HANDOFF — ft-harness-ops#1 → #2 (2026-10-05 · 컨텍스트 404k 증류)

## ★골 원문 3줄 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

★승계 첫 일 = 골 대조 보고★: 위 원문과 아래 열린 단위 각각이 «골의 어느 줄·GOAL-harness.md 표 A/B/C 의 어느 닫는 증거» 인지 3줄로 planner(`seats-harness.json` 의 `_hil_route` = byz-planner-arch#3)에 mbox 보고한 뒤에만 착수.

## 내 자리
- 세션 ft-harness-ops#2 · 워크트리 .worktrees/harness-ops(브랜치 feat/slack-inbound-820 · PR #824 열림) · mbox = /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh · 보고 3줄(경로+sha+남은 일)·[HIL] 은 planner · **이 단위(오빠가 harness-ops pane 에서 직접 확정)는 AskUserQuestion 허용** — 끝나면 원복.
- 하위 좌석(전부 이 워크트리·읽기/설계 전용): ft-harness-arch#0(claude-fable-5-1 · 기획) · ft-harness-da#1(codex gpt-6.1-sol low · 대기형) · ft-harness-nano#1(opencode openrouter deepseek-flash-latest). ★opencode 는 시작할 때 자동 업데이트 모달로 꺼진다 — 모달을 Esc 로 닫고 `opencode --auto --model 'openrouter/~deepseek/deepseek-flash-latest' -s <세션id>` 로 재기동 후 `tmuxc send` + Enter.
- 크론·Monitor·ScheduleWakeup 0(오빠 지시 「크론도 정지」) — 재개 신호 전까지 새로 만들지 않는다.

## 이번 세션에서 한 일 (main 에 있는 것 / 브랜치에만 있는 것)
- main: PR #822(GitHub 미러 본체 · 9ca9a5d1d9) 머지.
- 브랜치 feat/slack-inbound-820(PR #824 · **미머지**): 미러 3결함 수정(relay 전문·키 정규식·URL 줄) · HIL 질문 카드 · Slack→mbox 역방향(DA 2차 반영) · 파일 길이 200줄 맞춤 · 지시서/브리프/값/설계 문서. PR #824 CI: File Size·Web Test 통과, Python Test 107건 실패(옛 main 1195건과 다른 묶음 — main #823 미병합 기준선 차이로 추정, 미확인). 병합→CI→머지는 **보류**(오빠 지시: 슬랙 제외).
- 슬랙 launchd 3개(역방향·보고 미러·GitHub 미러)는 planner 가 bootout — plist 보존, 재개 시 `bash scripts/harness-install/slack-mirror/install*.sh`.

## 지금 단위 = 「슬랙 제외 · 이슈+하네스 구성 기획」 (오빠 직접 지시 2026-10-05)
- 지시서 `design/harness/ORDER-harness-composition-20261005.md` · 오빠 값 `VALUES-harness-composition-20261005.md`(Q1 만 추천과 다름: **Issue # 는 메인 오케 소유 · 나노는 작업 워커 · spawn 게이트 삭제** / Q2 planner pane 1곳+tmm / Q3 경과 표시+상위 알림 / Q4 당분간 1대·설치 키트 먼저 / Q5 seats-*.json 설정 행만 남기고 상태 파생·구조 커밋 1).
- 설계 `DESIGN-harness-composition-20261005.md` r3(b1c3883341) — arch 작성. DA r1·r2 = HOLD(r2 쟁점은 Q1 미반영뿐 → r3 가 닫음). DA 가 «직렬 문서 DA 중단 · 통합 수락(DESIGN+VALUES+FACTS)은 ops 소유» 권고.
- 남은 것: ①nano `FACTS-composition-20261005.md`(+facts-raw/) 수신 → arch 2차 대조 1회 ②통합 수락(ops 가 DESIGN r3 + VALUES + FACTS 를 한 번에 검토) ③§3-6 순서 1(질문 원장 `ft-hil-ask/answer` + tmm h) 구현 발주 — **오빠 확정 뒤에만**.

## 열린 단위 (이전 #0 → #1 인계분 중 남은 것)
1. 라이브 하네스 bin = main 1:1 (Issue #816 · 설계 PR #818 DESIGN-live-bin-sync.md) — DA 결과 파일 `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/dbda6986-6c61-450e-b348-4b6c5109de04/scratchpad/da-livebin-out.md` 는 끝내 안 열림 → 재실행(`da-livebin-prompt.md`) 필요. 새 설계의 §3-4 선행 = 이 단위.
2. PR #815(ⓔ 설계)·#818 머지 판정 대기(planner/오빠).
3. 닫는 5확인 뒤 ft-harness-ops#0 좌석 종료 판단(오빠) · 아직 안 닫음(하위 에이전트 10개 + 최근 2개 보존 하한).

## 함정 (실측)
- `block-destructive` 훅: `rm -rf`·`git add -A`·`git push --force` 차단 → 경로 지정 add · 새 브랜치명. 백틱+mbox.sh 같은 줄 금지 · `gh` 는 `unset GH_TOKEN`.
- `ft-role-spawn.sh` 는 v65 전용(harness 팀에서 실행 금지). 하위 좌석은 `tmuxc open <워크트리> --name … --agent … --model … --prompt …`(claude 는 `zsh -lc` 로 감싸 `[1m]` 보존).
- Serena: `initial_instructions` 로 session_id → `activate_project(<harness-ops 절대경로>)`. `.serena/project.yml` 은 커밋 전 `git restore`.
- 파일 길이 CI 한도 200줄(신규·증가 금지) · main CI 의 Python/Web Test 는 #823 으로 복구됨 — 새 PR 은 main 병합 뒤 CI 비교.
- 도어벨 `absent`/`noagent` = 좌석 pane 에 에이전트 없음 → pane 확인.
