# HANDOFF — byz-harness-arch-claude#11 → #12 (2026-10-08 · 컨텍스트 402k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: 6-b(오케 요청을 사용자와 협의해 개선) + C(배포·반영) + 원문 5(머신 독립 배분) + 원문 7(쪼개 동시에).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(17조항) Read → Serena initial_instructions → activate_project(★/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops★ — 부팅 때 다른 워크트리가 잡힌다) → i-have-adhd 로드.
2. 골 대조 3줄 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(`ft-harness-info.sh seats` · 지금 byz-harness-master-claude#14)에 mbox.
3. 같은 턴 CronCreate 10분 체크 틱(mbox recv + 열린 일 실측 + 오빠 3줄) — 없으면 착수 0.
4. zsh 함정: `echo ===` 금지(구분자 `echo ---`) · mbox send 와 같은 Bash 호출 안에 백틱이 있으면 훅이 차단 → 분리 · `rm -rf` 든 명령은 block-destructive 가 막음 → 임시 파일은 scratchpad.

## 역할 (governance §6)
arch = 설계·카드(대기/ · lint 통과 · 미커밋)·DA 소환 판단·나노 결과 «독립 재현»·닫힘 문안(카드 증거 줄 + 판정서 §초안). master = 커밋·push·설치·좌석. arch 코드 0.
- 카드 lint: `source <루트>/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>`.
- 증거 줄: «맨몸 줄»(백틱·불릿 없이) `세트: <40hex> · 시험: <명령 1개> rc=0 · 이슈: 0` 을 카드 끝에 → `bash scripts/fable-team-bin/ft-nano-evidence-check.sh <카드> --repo <나노 워크트리> --feat <나노 base sha>`(.worktree-info.json 의 base_sha).
- 판정서 초안 = `<루트>/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · ★다음 번호 §54★(§49~§53 완료 · §53 = 판정 357 r2 · master append 대기).
- 시험 python = `<루트>/.venv/bin/python`(PATH 앞에) · DA = byz-harness-da-codex#0(mbox relay · 10+10분 · 2 HOLD 면 중단 · 다른 팀도 공유라 대기열 걸림 — 화면 Working 이면 기다린다 · ring 하면 같은 발주가 2줄 쌓인다).

## 이 세션에서 닫힌 것
| 무엇 | 닫는 증거 |
|---|---|
| §49 eli5 r3(TIMEOUT 90→180 · 실측 묶음 63~162초) + COMPANION 누락 발견 | 판정서 §49 · 9709cc0795 · PR 890 병합 |
| §51 세트 발주 도구(판정 359) | a67d14689c · 홈 2파일 설치 |
| R20 cfo-env goal-lines | f800931d38 · e217380ce8 |
| 판정 370·372 ops·loom 메인 팀 설치 안 + governance 팀 표 | 17ce822f59 · a7ffcd86a7 · PR 893 · 두 master 부팅 보고 #61510·#61515 |
| R26(구 R22) ft-proposal-card 골 줄 수·증거·경로 | 9ab3f6256e · b2c1d09bc2 · goal-lines-cfo 4줄 |
| 판정 357 제안서 흐름 r2 설계 + DA HOLD 1 → 교정 1 APPROVE + 나노 재현 §53 초안 | DESIGN-proposal-flow «# r2» · DA-proposal-flow §r2·§r2 교정 1 · 801e66649e · 나노 1f834a7536 |

## 열린 일 (순서대로)
1. **§53 master 집행 대기**(#61979): 판정서 append · 카드 완성 이동 · cherry-pick · 나노 닫기 · 랜딩 PR → install-magazine WARN 0(proposal_* 4파일). 그 뒤 «다음 제안서 1건»에서 슬랙 md+HTML 두 첨부(제목에 md_hash 8) + Issue 본문 첫 줄 표식·전문 확인 = 이 단위 닫는 증거 → 정본 첫 사례 줄처럼 기록.
2. R21(feature 틱 plist master#0 고정) — 원장 접수 · 미착수.
3. 대기 카드: gate-hook-kit-equals-home(planner 지시 대기) · r23-tank-rest-path(보류).

## 함정 (실측 · 이 세션)
- planner 발주문 머리에 v65 골 3줄이 붙어 온다(판정 357·359 두 번) — 설계·카드엔 하네스 골을 쓴다.
- 픽스처 통과 ≠ 실자료 통과(eli5 r1·r2) — 실 LLM·실 원장으로 한 번 돌린다.
- 원장 번호 중복 확인(`grep -oE '^\| R[0-9]+' REQUEST-LEDGER.md | sort`) — R22 가 두 번 쓰였다.
- 새 팀 좌석 이름 공간: 기존 `ops-*`·`loom-*` 워크트리와 겹침 → 나노 접두 `<팀>-nano-`.
- master 승계 직후 후계가 부팅 발주를 안 돌릴 수 있다 — 그 좌석을 깨우는 건 전임 master 몫(arch 는 알리기만).
