# HANDOFF — byz-harness-arch-claude#15 → #16 (2026-10-08 · 컨텍스트 414k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md Read → Serena initial_instructions → activate_project(★/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops★ · session_id 필수 — 안 주면 다른 워크트리가 잡힌다) → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(★byz-harness-master-claude#16★ — 발신 전 `bash scripts/fable-team-bin/ft-harness-info.sh seats` 로 현역 이름 확인)에 mbox. 같은 턴 CronCreate 10분 틱.
3. ★명부 `_arch` 를 #16 으로 바꿔 달라고 master 에 부탁★(지금 `.fable-team/seats-harness.json` `_arch` = #15 — ft-index-move 정본 쪽지 수신자).
4. 함정: mbox 명령 줄에 백틱 금지(훅) · `git add -A` 금지(훅 · 경로 지정) · 카드·문서는 Write 도구 · 긴 쪽지는 relay · 임시 파일은 scratchpad/$TMPDIR · 남의 pane `❯` 뒤 글자 = 자동완성 제안(근거 금지).

## 역할 (governance §6)
arch = 설계·카드(대기/ · lint 통과 · 미커밋)·DA 소환 판단·나노 결과 «독립 재현»·판정서 초안. master = 커밋·push·설치·좌석. arch 코드 0.
- 카드 lint: `source /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>` — 구현 범위에 실재 경로 1개 이상(ops/main-base 에 없는 main 전용 파일은 라이브 절대경로로 인용).
- 증거 줄 검사: `bash scripts/harness-install/fable-team/bin/ft-nano-evidence-check.sh <카드> --repo <나노 wt> --feat origin/main` — ★하네스 나노도 이제 origin/main 기준(판정 444 ②)★. 증거 줄은 나노가 카드 «끝» 에 1줄(arch 가 대신 쓰지 않음).
- ★판정 절에 「대상 카드: <카드 basename>」 줄 필수★(새 ft-index-move 결속 규칙 · PR #944) — 없으면 완성 이동 REJECT.
- 판정서 초안 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · §63~§69 반영 끝(§68 = v442 · §69 = 판정 460 master 기록) · ★다음 번호 §70★(master 가 쓴 번호와 겹치지 않게 OPS-VERDICTS 파일 마지막 §N 확인).
- DA = byz-harness-da-codex#0(relay · 10+10분 · 2 HOLD 면 종료) · ★DA 가 판정을 relay 사본(/tmp/mbox/…)에 쓰는 일이 있음 — 추적 파일 경로를 쪽지에 절대경로로 명시★.
- 하네스 나노 base·랜딩 = origin/main(판정 444 ②) · ops/main-base 는 작업 브랜치.

## 이 세션에서 닫힌 것
| 무엇 | 닫는 증거 |
|---|---|
| 판정 440 랜딩 정본화 설계 | DA r2 APPROVE #63184 · 오빠 결정 판정 444(정본 = 구현 나노 같은 PR · 하네스 문서 = main) |
| 판정 438 pytest fixture | §62 · PR #935 5785530bea · CI 21m37s→8m53s |
| 444-3 PR 템플릿 | §63 · PR #941 0cb14f7d39 |
| 444-1 index-move 정본 랜딩 검사 + R37 | §64 · PR #944 1140076188 · 라이브 설치 cmp · 재판정 (가) 엄격·소급 없음 |
| 451 Mobile Test 변경 감지 | §65 · PR #945 4108c1f531 |
| 444-2 issue-close 6항 정본 | §66 · PR #943 eb0a9263a0 |
| 446 pytest-xdist | §67 · PR #951 cec6f0f8c8 · 잡 7m15s(2 워커) · arch 컨테이너 재현 nodeid diff 0 |
| 판정 438 6분 목표 | 오빠 판정 460: 목표 7분 반 · 7m15s 로 닫힘 · 추가 단축 0 |

## 열린 일 (순서대로)
1. **v461 인박스 큐 행 via 필드** — 카드 `design/teams/harness/indices/진행/v461-inbox-row-via.md`(진행 · 나노 좌석 spawn 됨/될 것) → 결과 오면 `tests/harness/test_inbox.sh` arch 재현 + 증거 줄 확인 + §70 초안.
2. **R42 sha base 나노 닫기** — 카드 `design/teams/harness/indices/진행/r42-nano-close-sha-base.md`(진행) · arch 판정 = 게이트 sha 수용 기각 · close 가 랜딩 브랜치로 환원(조상 아니면 REJECT) + spawn 이 base=브랜치·base_sha=sha → 결과 오면 `tests/harness/test_nano_close_sha_base.sh` 재현 + 초안.
3. **R41 소음 카드**(지시 오면 작성): ft-index-move 가 «정본 영향 없음» 카드 완성에도 [정본 갱신 요청] 쪽지 → 「정본 갱신:」 줄 카드만 쪽지(master 에 개선요청 #63686 · 실례 #63684·#63707·#63747).
4. **harness-env FT_NANO_FEAT=ops/main-base stale 여부** — master 에 판단 요청(#63795) · 회신 확인.
5. 대기(planner 우선순위): 훅 오탐 통합 · R35 · mbox-sh-split · r23 · v421/v423 · gate-hook-kit-equals-home.

## 함정 (실측 · 이 세션)
- master 가 나노 브랜치에 origin/main 을 병합하면 CI 경로에 새 시험이 들어온다 — 그룹 마커 같은 «목록 기반» 변경은 병합 뒤 재측정(446 실례).
- CI 1회 통과는 «간헐 충돌 없음» 증거가 아니다 — 측정 값으로 판정.
- 비공개 리포 러너 = 2 vCPU · branch protection·rulesets API 403(무료 플랜) = 필수 검사 없음.
- actionlint 는 main 에 기존 SC2086 2건 — 완료 조건은 «findings main 과 동일 + `-shellcheck=` rc=0».
- `find /` 금지(오래 걸림) · docker 일회용 컨테이너는 `--network none` + 자체 redis(개발 Redis = 라이브).
