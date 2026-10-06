# REQ — 메인 오케 리스트·하위 트리 실측 (ft-harness-arch#0 → ft-harness-nano#1 · 2026-10-05)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 축 A(모니터) 첫 단위 「누가 메인 오케이고 그 밑이 어떤 구성인지」. 발주 = ops#2 ORDER-main-orch-list-20261005 (mbox #56946).

읽기 전용 · Slack 0 · 산출 `design/harness/issue-improvement/FACTS-orch-tree-20261005.md`(짧게 · 표 3개) + 원본은 `facts-raw/T*.txt`. [사실]/[추측] 구분. 측정 시각(KST) 1줄.

## T1. 오케 후보 전수 — 한 행 = 세션 1
`tmux list-panes -a -F '#{session_name}\t#{pane_pid}\t#{pane_current_command}\t#{session_created}'` 전 세션 + `pgrep -P <pane_pid> -l`(에이전트 실재) + 각 세션의 `tmux display -p -t <s> '#{pane_current_path}'`(워크트리).
열: 세션명 · 생성시각 · 에이전트(claude/codex/opencode/없음) · 워크트리 경로 · **역할 추정 근거**(세션명 접두: master/arch/da/nano/temp/tester/ops/planner/issue-manager/repro/helm/KakaoBot/tmm).

## T2. 명부가 말하는 «오케»
6파일 `.fable-team/seats{,-harness,-issues,-planner,-kk,-cfo}.json` 의 `_master` · `_hil_route` · `_name` · `_version` 값을 표로. 각 `_master` 세션이 T1 에 있나(살아 있나) Y/N. seats.json(v65) 는 `_master` 없음 → `role:"master"` 이고 `_replaced_by` 없는 행 중 세션명이 T1 에 있는 것만 나열.
+ kakao·airag·ccu 좌석의 명부 파일이 어디 있나: `ls /Users/yoonhwan/Project/Agent/*/.fable-team/seats*.json /Users/yoonhwan/Project/*/.fable-team/seats*.json 2>/dev/null` (다른 프로젝트 루트 포함 · 못 찾으면 「6파일 밖 · 미발견」).

## T3. mbox 실측 (명령 5 + 도어벨 + 도달)
`.fable-team/comm/mbox.sh` 를 읽고: ①usage 한 줄 ②send 가 쓰는 파일(큐 경로·사본 로그·bodies·seq 파일) ③700자 초과 처리 ④도어벨 = tmux send-keys 로 보내는 정확한 한 줄 포맷(`[발주 #seq] … recv …`) + `--no-notify`/`--urgent` 동작 ⑤recv 의 consume 여부·`--all` ⑥ring 이 하는 일 ⑦relay 가 만드는 파일 경로 ⑧`ft-reach-check.sh` 가 보는 jsonl 경로(도달 판정). 각 항목 = 「파일:줄」 + 1줄 인용.

회신 mbox 3줄: 경로 · 못 한 항목 · 사실/추측 비율. 커밋은 ops#2 에 요청.
