# HANDOFF — byz-harness-arch-claude#6 → #7 (2026-10-07 20:27 · 컨텍스트 404k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: 6-b(오케 요청을 사용자와 협의해 개선) + C(배포·반영) + 원문 7(쪼개 동시에).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(16조항) Read → Serena initial_instructions → activate_project(★harness-ops 절대경로★ — 부팅 때 다른 워크트리가 잡혀 있다).
2. 골 대조 3줄 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / ★cron=<job id>★)를 현역 master(ft-harness-info.sh seats 로 확인 · 지금 byz-harness-master-claude#9)에 mbox.
3. ★같은 턴에 CronCreate 10분 체크 틱★(mbox recv + 하위 pane 실측 + 오빠 3줄) — BOOT 16 · 없으면 착수 0.

## 역할 (governance §6)
arch = 설계·검토·판정 «안» + 나노 카드 작성(design/teams/harness/indices/대기/ · lint 통과 · 미커밋). master = 집행. arch 는 코드 파일을 쓰지 않는다. 회신 = 결론 1줄 → 승인/수정/반려 + 이유 → 근거. 긴 것은 파일 → mbox relay(본문·요약에 백틱 금지).
카드 lint 는 팀 env 를 먼저 source: `source R/.fable-team/bin-harness/harness-env.sh; bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>` (안 하면 v65 골 3줄로 검사해 전부 REJECT).

## 이 세션에서 닫힌 것 (전부 master 회신·랜딩 완료)
| 원장 | 무엇 | 닫는 증거 |
|---|---|---|
| R13 | 승계 크론 미이관 — BOOT 16조항 + 승계 6단계 5번 문구 + ft-role-spawn BODY | ai-feature-pack 71e95b5·7c15014 · BYZ 0a45036e82 · 나노 d8de2910d1 |
| R10 | Tank 래퍼 issue edit + 수정 전 원문 보관 | 나노 00a120c510 |
| R8 보강 | ft-nano-close --wt/--branch 명시 모드 | 나노 0103bccf3e |
| R14 | 팀 feature 설치(seats·env·plist·goal-lines·feature-main 워크트리·master#0) | 설치 실측 확인 · PLAN-r14 |
| R14 후속 | ft-nano-close 워크트리 접두 = FT_NANO_WT_PREFIX | 나노 9a2da93134 (원장 7ee2b35855) |
| R12 | Issue 855 .env 격리(BYZ_TEST_SKIP_DOTENV) · DA APPROVE §7 | 215f52056a cherry-pick · 판정서 §31 · PR 864 병합 c0f85616b4 |
| R16 | 카드 lint ⑦사전검증 ⑧조사 근거(FT_CARD_REQUIRE_PREVERIFY=1 · feature 만) | b95f0185b0·76844c8833 · RT 설치 · feature-env.sh 15행 |
대기·진행 카드 = 0장.

## 열린 일 (순서대로)
1. **R15 press 경로 강제** — 안 승인됨(PLAN-r15-press-path-enforcement-20261007.md). master 순서: R9 동기(v65 랜딩 대기) → 하네스 게이트 카드 H(⑦역할 tester·checker 만 ⑧직전 회차 BTS 표 · 허가 파일 발급) → v65 helper 카드 V(cdp_helper PTT 누름 검사 · v65 arch 전달 대기) → 문구 T. ★H 카드는 아직 안 씀★ — R9 랜딩 확인되면 작성. 주의: realtime_multi_e2e 는 poller 를 안 띄워 V 대로면 막힘 → v65 결정.
2. **R16 feature 카드 견본** — 초안 design/teams/harness/drafts/r16/feature-card-template.md → feature-main design/feature/indices/README.md 로 master cp 요청했음(#59731) · 설치 확인 1줄 받기.
3. **CFO 팀 env 없음(별건 · #59912)** — byz-cfo-nano- 좌석이 살아 있는데 R/.fable-team/bin-cfo/cfo-env.sh 없음 → ft-nano-close 좌석명 자동 로드가 「팀 env 없음」 REJECT. CFO 가 FT_NANO_PREFIX 를 직접 주는지 master 회신 대기.
4. **855 밖 기존 실패 11건**(원장 후속 행 후보): test_poller_dom_order_version_capture 7 · test_gpu_vm_control 2 · test_cleanup_auth 1 · test_loom_contract_terminal_surfaces 1 — 로컬 REDIS_PORT=9 에서 실패(CI 는 Redis 서비스 있음). 원인 미조사.
5. **6379 오염 정리 여부** — master 첫 검증(19:02:25~19:04:49 · REDIS_PORT=6379)이 ops:account_seen_fail:20261007 일일 카운터를 부풀렸을 수 있음(flush 0 확인). 정리는 planner [HIL] — 아직 안 올림.
6. 인계문 #5 의 원장 후보 그대로: 게이트 훅 3사본 정합 · PR 쓰기 5종 가드 확장 · ft-tmux-*.sh 라이브 없음 · bin 폴더 합치기 · block-destructive 오탐.

## 함정 (실측 · 이 세션)
- ★남의 시험 출력 파일로 회귀를 판정하지 말 것★ — 내가 i855 를 HOLD 했다가 철회(그 로그는 수정 전 실행). 로그 시작 시각 vs 커밋 시각 대조 + 실패 파일만 그 커밋에서 재실행(18 s).
- ★DA 판정 단어는 APPROVE·HOLD·REJECT 셋뿐★ — 내 R16 초안이 PASS 를 허용해 PASSWORD 글자에 걸렸다.
- 나노 3장이 연속으로 카드 증거 줄 없이 올라왔다 → 카드 완료 조건에 「세트: sha · 시험: rc · 이슈: 0」 형식 필수를 적어 두면 반송이 준다.
- 로컬 Redis 6379 = v6-realtime-live 라이브 dev(운영 데이터). 시험은 REDIS_PORT=9 · LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1. flush 시험은 전부 일회용 unix 소켓 redis-server 라 안전.
- ft-role-spawn 은 v65 전용(seats.json·v65 inbox 고정) — 다른 팀 역할 좌석은 tmuxc open + seats-<팀>.json 손 등록.
- ft-index-lint 는 키트(scripts/harness-install/fable-team/bin)에만 있고 추적본 scripts/fable-team-bin 에는 없다.
