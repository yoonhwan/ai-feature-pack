# HANDOFF — byz-harness-arch-claude#5 → #6 (2026-10-07 · 컨텍스트 406k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: 6-b(오케 요청을 사용자와 협의해 개선) + C(배포·반영) + 원문 7(쪼개 동시에).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항(세션명/모델·창/Serena + i-have-adhd)을 byz-harness-master-claude#8 에 mbox — 그 뒤 착수.★

## 역할 (governance §6 · 오빠 10-07 「작업들 arch 검토 받고 결정 진행. 독단으로 하지 말고」)
- arch = 설계·검토·판정 «안» + 나노 카드 작성(design/harness/indices/대기/ · ft-index-lint 통과 · 미커밋). master = 집행(커밋·push·설치·좌석). arch 는 코드 파일을 쓰지 않는다.
- 회신 형식: 결론 1줄 → 승인/수정/반려 + 이유 → 근거 경로. 긴 것은 scratchpad 파일 → mbox relay(본문·요약 인자에 백틱 금지 — 훅 차단).
- 하위 좌석 AskUserQuestion 금지 · 오빠 값은 master → planner [HIL].
- 판정 전에 «실측» — 이 세션에서 내 가정이 두 번 틀렸다(kit-bin-adopt 의 «추적본=뒤처짐» 가정 · 58444 의 «master 직접 수정 한도 안»). 카드 전제는 파일 바이트로 확인하고 쓴다.

## 이 세션에서 닫힌 것 (전부 master 에 회신 완료)
- 사후 검토(58408) · arch 상시 지침 초안(design/harness/DRAFT-harness-arch-standing-guide-20261007.md · 미커밋 · master 가 governance §6 반영) · HIL 차단 지침(§7) 검토 · 게이트 원인(master 좌석이 모델 판별로 면제 + .worktrees 경로 제외) · Tank write 위험·main 보호 · C 축 계획(58611: 설치=사용 아님 · 슬랙 발행 단계 · 사본 4곳 · 닫힘 = 오빠 명부 전 머신 반영 행).
- 카드 → 나노 → 랜딩: gh-guard-scope-main-prcreate · orch-gate-master-role(#843) · kit-hooks-install-check(7ed51c846e) · kit-bin-adopt(7889dec525) · nano-spawn-close-team-env(45a1ee516a) · role-spawn-byz-default(86d77d5f6a). 라이브 ft-role-spawn 은 master 가 키트 바이트로 교체(59232 · 닫힘).
- 오빠 값(10-07): 운용 머신 명부 = 이 Mac + byzs-mac-mini(jarvis 명부 밖) · FT_BIN 전환 승인(옛 폴더 보존·일감 사이) · mac-mini 설치 승인(tailscale ssh · 홈 복사만) · Tank write 부여됨 · main 만 삭제·재작성 금지.

## 열린 일 (순서대로)
1. **Issue 855**(로컬 CI 5건) — 내 회신 59321: 원인 = shared/config/settings.py 48행 import 시 루트 .env load_dotenv. GPU 3건 정확 재현(APP_ENV=local + DEV_GPU_STATUS_URL → gpu.py 62~69행 dev 프록시가 prod status 를 HTTP 로 읽음). pulse 2건은 .env 붙이면 실 번역 문장이 나옴(실 과금 경로 가능) — 원인 키 미확정(단일 변수 V6_LST·V6_AUTHORITATIVE_STT_MODE·APP_ENV 각각은 재현 안 됨). master 가 카드를 원하면 이 내용으로 카드 작성(tests/conftest.py 에서 .env 로드 차단 스위치 + 픽스처 방어 · 닫는 증거 = ci.yml 145행 묶음 로컬 0 fail). 재현 사본: scratchpad m855full(git archive origin/main 01bfc82454 · Redis 죽은 포트 9 로 실행 · 실 Redis 접촉 0).
2. **#59309 R13** — 승계 시 체크 크론(CronCreate 10분) 미이관 → 승계 템플릿·BOOT 고정 단계 안. 전문 /tmp/mbox/20261007T181613-byz-harness-master-claude#8-to-byz-harness-arch-claude#5-order-arch-cron.md. 미착수.
3. 대기 카드 nano-close-named-wt(design/harness/indices/대기/) — base = 45a1ee516a 랜딩 뒤. master 가 나노 발주 예정.
4. R11(v65 세션 신규 검사) — 내 판정 58946: 발생 위치 = v65 러너 tests/e2e/tcc8_completion_press.py 4336~4359(PRESS_REUSE_TAB 이 TAB_URL 프로필을 조용히 무시) → v65 로 반송 권고. R9 는 main 반영 PR 에 키트 사본 2개 동봉 필수.
4b. 요청 원장(design/harness/REQUEST-LEDGER.md) 대응표: R9 = 834 press-gate 런타임 동기(v65→main 반영 PR 에 키트 사본 2개 동봉 · 58946) · R10 = Tank 래퍼에 Issue 본문·제목 edit 동작 추가(issues #58849 · ★arch 안 아직 0 — 후계 착수 대상★ · R6·R7 과 같은 래퍼 파일 scripts/fable-team-bin/ft-gh-as-tank.sh + 키트 사본) · R11 = 반송(위 4) · R12 = Issue 855(위 1) · R13 = 크론 이관(위 2). 대기 카드는 지금 nano-close-named-wt 1장뿐(나머지는 랜딩·이동됨).
5. 원장 행 후보(다음 단위): 게이트 훅 3사본(홈·프로젝트·키트) 정합 · PR 쓰기 5종(pr review·pr close -c·pr edit·pulls API·graphql) 가드 확장 · ft-tmux-*.sh 래퍼가 라이브 bin 에 없음 · 추적본/키트 bin 폴더 하나로 합치기 · block-destructive 오탐 처리(오빠 값 대기).
6. C 축: RELEASE 0.4 동작 변화 칸 — nano-slots 기본 6→5 · 후보 필터 머리줄 4줄 · 이번 나노 수정들은 FT_BIN 전환 뒤 적용 · 라이브 개별 교체 시 nano-spawn·close·evidence-check 는 한 세트.

## 함정 (실측)
- 공유 Serena: 부팅 때 initial_instructions 가 다른 워크트리(planner-decisions-api-e2c)를 활성으로 잡았다 → activate_project 를 harness-ops «절대경로»로 다시.
- mbox send 본문에 백틱 → 훅 차단(같은 Bash 명령 안 다른 부분의 백틱도 걸림 — 파일 편집과 send 를 한 명령에 섞지 말 것).
- ft-index-lint ⑥: 구현 범위에 «실재하는» 확장자 있는 경로가 최소 1개 있어야 OK(신규 파일만 적으면 REJECT).
- pkill 은 block-destructive 에 막힌다 — 내가 띄운 백그라운드는 TaskStop 이 정상 경로.
- 로컬 Redis 6379 = v6-realtime-live 컨테이너(라이브 dev). 시험은 REDIS_PORT=9 등 죽은 포트로.
