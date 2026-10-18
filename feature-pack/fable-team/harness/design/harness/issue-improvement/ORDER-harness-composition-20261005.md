# ORDER — Slack 제외, 하네스 구성 기획 (ft-harness-ops#1 → arch#0 · 2026-10-05 · 오빠 직접 지시)

## 골 원문 (복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 오빠 지시 원문
> 일단 슬랙을 제외해버리고 하네스 구성 기획

## 바뀐 범위
- **Slack 은 이번 기획에서 뺀다.** 슬랙 미러·역방향·보드·FACTS 사실표는 «후속 층» 으로 보류(데몬 3 은 bootout 유지 · PR 824 미머지 유지). 슬랙 홀 정리는 하지 않는다.
- 기획 대상 = **하네스 구성 자체**: `tmm > tmuxc > tmux > cc/opencode/codex` 위에서 오빠의 군집 비전(BRIEF 의 오빠 원문)이 돌아가는 뼈대.
  - 층 구분(누가 무엇을 소유): 오빠(HIL) · 최상위 오케 · 메인 하네스(v65·cfo·…) · 위성(ccu·kk) · issue-manager · harness-ops · 좌석(arch·da·nano·impl) · 기계(멀티 머신).
  - 흐름: GitHub Issue 등록 → issue-manager 가 메인 하네스에 배분 → 작업·검증 → 완료 시 Issue 닫힘 → 누구나 확인. 사람(HIL)은 «인터뷰를 놓치지 않는 것» 에만 쓰이고 병목이 되지 않게.
  - 지금 tmux pane 인터뷰(AskUserQuestion)가 잘 되는 이유와, 좌석 수가 늘면 어디서 막히는지(오빠 병목 지점).
  - 멀티 머신: `메인 하네스를 머신에 독립 배분` 이 지금 어디까지 되어 있고(라이브 bin 1:1 #816/#818 포함) 무엇이 비어 있는지.

## 오빠 추가 지시 (같은 날 · 원문)
> 이슈와 하네스 포함

→ **GitHub Issue 체계(등록·라벨·카테고리·issue-manager 배분·상태 전이·close·누구나 확인)를 하네스 구성의 1급 구성요소로 함께 기획한다.** 실측 대상: Issue 전체 목록(상태·라벨·needs-triage 고정 여부·close 0 건 등 H13·H14), issue-manager 좌석의 출범 발주 흐름, 이슈→메인 하네스→PR→Closes 연결의 끊긴 곳.

## 일 (구현 아님)
| 좌석 | 일 |
|---|---|
| ft-harness-arch#0 | 위 범위의 **하네스 구성 설계 1장** `design/teams/harness/issue-improvement/DESIGN-harness-composition-20261005.md` — ① 현재 구성 지도(실측 근거) ② 병목·홀 목록(증거·빈도·닫는 증거) ③ 목표 구성(층·소유·흐름) ④ 오빠께 물을 질문 5개 이내(번호 선택지). 기존 WIP(`WIP-swarm-control-research-20261004.md`)와 리서치 3/4 를 이어 쓴다 |
| ft-harness-nano#1 | arch 가 요청하는 **읽기 전용 실측**: `seats-*.json`·`.fable-team/` 구조·tmuxc 세션 목록·mbox 흐름·issue-manager 와 GitHub Issue 상태(라벨·전이)·`~/.tmuxc` 등. Slack 은 읽지 않는다. 산출은 `design/teams/harness/issue-improvement/FACTS-composition-20261005.md` |
| ft-harness-da#1 | arch 설계와 nano 사실표를 적대 검증(근거 없는 단정·건수 불일치) → 번호 목록 + APPROVE/HOLD |

## 규칙
- 하위 좌석 AskUserQuestion 금지 — 오빠 인터뷰는 ft-harness-ops#1 이 대신. 크론·Monitor·폴링 금지. 라이브 파일·launchd·main 변경 금지. 산출은 tracked 경로 + 경로·sha 만 mbox.
- 약어로 부르지 않는다 — 이름과 증거로.
