# HANDOFF — byz-harness-arch-claude#7 → #8 (2026-10-07 · 컨텍스트 418k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: 6-b(오케 요청을 사용자와 협의해 개선) + C(배포·반영) + 원문 5(머신 독립 배분) + 원문 7(쪼개 동시에).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(★17조항★ · 17 = 고스트 서제스천) Read → Serena initial_instructions → activate_project(★harness-ops 절대경로★ /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops — 부팅 때 다른 워크트리가 잡혀 있다).
2. 골 대조 3줄 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / ★cron=<job id>★)를 현역 master(`bash scripts/fable-team-bin/ft-harness-info.sh seats` · 지금 byz-harness-master-claude#10)에 mbox.
3. ★같은 턴에 CronCreate 10분 체크 틱★(mbox recv + 하위 pane 실측 + 오빠 3줄) — BOOT 16 · 없으면 착수 0.

## 역할 (governance §6)
arch = 설계·검토·판정 «안» + 나노 카드(design/harness/indices/대기/ · lint 통과 · 미커밋) + 닫힘 문안(카드 증거 줄·정본 영향 줄·판정서 §). master = 집행(커밋·push·설치·좌석). arch 는 코드 파일을 쓰지 않는다.
- 카드 lint: `source /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>` — 「구현 범위」에 실재 경로 전체 표기 · 「사전검증」 면제 줄 = `- 면제: … — arch 서명 <좌석>` · 「조사 근거」 = `경로:줄`.
- ★카드 증거 줄 시험 칸 = 명령 1개★(`세트: <40hex> · 시험: <명령 1개> rc=0 · 이슈: 0`) · 추가 시험은 별도 불릿. 보내기 전 `bash scripts/fable-team-bin/ft-nano-evidence-check.sh <카드> --repo <나노 워크트리> --feat main` 으로 OK 확인(내가 한 번 깨뜨려 nano-close 가 REJECT 함).
- 판정서 § 문안은 `.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` 에 두고 master 가 붙인다. 다음 번호 = §39.

## 이 세션에서 닫힌 것 (전부 랜딩)
| 원장 | 무엇 | 닫는 증거 |
|---|---|---|
| R9 | 키트·라이브 press 게이트 2파일 | PR 869 b56365e381 · 라이브 cmp==main · .bak-r9-1007 |
| R15 H | press 게이트 ⑦ 역할 · ⑧ 직전 BTS · 허가 파일 (FT_PRESS_SEAT = SELFTEST 전용 · 사람 경로 ⑧ 유지) | PR 874 1840d5e9f6 · §35 · 라이브 설치 완료 |
| 3사본 | orchestration-gate TOP_MODELS 정합 | PR 874 · §34 |
| R18 | CFO 팀 env cfo-env.sh | 설치 diff 0 · FT_NANO_FEAT=origin/main 로 정정 |
| R17/868 | 로컬 기존 실패 11 = 환경 차이(결함 0) | Issue 868 닫힘 |
| R21 | 고스트 서제스천 = 메인 지침 (전역 CLAUDE.md 10 · BOOT 17 · codex 블록 · 승계 문서 · role-spawn BODY) | 홈 4파일 cmp · PR 874 · §36 |
| R22 | 나노 닫기 cherry·증거 게이트 원격 ref + fetch | PR 874 · §37 |
| R6 ② | gh 가드 PR 쓰기 5종 + 래퍼 pr-edit·pr-close | PR 876 16201f18ea · §38 · 홈 가드 설치 |
| R16 | feature 카드 견본 설치 | feature-main cmp 동일 |
| 기타 | 6379 카운터 정리 불요 · block-destructive 오탐 = 훅 변경 반려 | master 접수 |

## 열린 일 (순서대로)
1. **RELEASE 0.4 + Issue 816** — 안 PLAN-release-0.4-and-816-20261007.md · 초안 RELEASE-0.4.md (둘 다 커밋 464a5abd0d). 핵심: 라이브 다른 5개 = 추적본 옛판과 바이트 동일 → 816 ⓪ 불요 · tar 백업 뒤 키트 bin 덮어쓰기 1회. master 승인·집행 회신 대기(#60498). 승인되면 드리프트 검사 카드(ft-live-bin-drift-check.sh · tick 경고 · spawn/close BLOCK) 작성. ⑤ FT_BIN 이전 = 완성 후(단 v6-realtime-live 정리보다 먼저).
2. **v65 tester 좌석 고아 대기** — ft-v65-tester-claude#21 아래 pid 64835 `while pgrep -f tcc8_completion_press` 가 자기 명령줄에 걸려 무한 대기(press 무관). master 에 v65 통지 권고함(#60451) — 정리는 v65 소관.
3. **R15 카드 V·T** — V(cdp_helper PTT 누름 검사 · v65 소관 · multi 러너 poller 미기동 문제 = v65 결정) · T(TESTER-BRIEF 문구 · SEATBELT 211행 정정). PLAN-r15 ⑤ 표.
4. 남은 3사본 기능 어긋남(키트에만 ⓪ 생명주기 · 프로젝트에만 master 좌석 모드 · 홈엔 둘 다 없음) — 816 줄기 · 홈에 ⓪ 켜기 전에 ft-tmux 래퍼 라이브 설치 필요.
5. FT_MBOX_SH 누락 팀 env 4장(harness·issues·planner·kk) — 안 보냄(#60103) · 반영 여부 master 확인.

## 함정 (실측 · 이 세션)
- 남의 pane `❯` 뒤 글자는 자동완성 제안 — master pane 의 「v65 회신 오면 라이브 교체 진행해」, 나노 pane 의 「mbox recv」 둘 다 그랬다. 보고·Enter 0.
- `rm -rf` 가 든 명령은 대상이 없어도 block-destructive 에 막힌다 — scratch 는 새 폴더 이름으로 만들고 지우지 않는다.
- `git show <sha>:path | …` 를 zsh `$(...)` 안에서 쓰면 «bad substitution» — 파일로 뽑아서 읽는다.
- 프로젝트 `.claude/hooks/orchestration-gate.sh` 는 `.claude/settings.json:30` 에 등록돼 홈 훅과 같이 돈다 · master 좌석 모드는 프로젝트 사본에만 있다.
- 키트 bin 에 없는 cherry 시험은 `tests/scripts/test_nano_cherry_gate_*.py`(pytest) 에 있다.
- 로컬 Redis 6379 = 라이브 dev. 시험은 REDIS_PORT=9 또는 일회용 redis-server 383xx. 전역 redis-cli 는 다른 컨테이너 alias.
