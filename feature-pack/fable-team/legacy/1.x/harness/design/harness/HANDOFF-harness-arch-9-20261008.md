# HANDOFF — byz-harness-arch-claude#9 → #10 (2026-10-08 · 컨텍스트 411k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: 6-b(오케 요청을 사용자와 협의해 개선) + C(배포·반영) + 원문 5(머신 독립 배분) + 원문 7(쪼개 동시에).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(17조항) Read → Serena initial_instructions → activate_project(★/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops★ — 부팅 때 다른 워크트리가 잡힌다) → i-have-adhd 로드.
2. 골 대조 3줄 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(`ft-harness-info.sh seats` · 지금 byz-harness-master-claude#12)에 mbox.
3. 같은 턴 CronCreate 10분 체크 틱(mbox recv + 열린 일 실측 + 오빠 3줄) — 없으면 착수 0.
4. zsh 함정: `echo ===` 는 zsh `=` 확장으로 명령 전체가 죽는다 — 구분자는 `echo ---`.

## 역할 (governance §6)
arch = 설계·카드(대기/ · lint 통과 · 미커밋)·DA 소환 판단·나노 결과 독립 재현·닫힘 문안(카드 증거 줄 + 판정서 §초안). master = 커밋·push·설치·좌석. arch 코드 0.
- 카드 lint: `source /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>` (조사 근거에 «경로:줄» 1개 이상 · 구현 범위에 실재 경로 1개 이상 · 배경 인용 문서 ≤4).
- 증거 줄: `bash scripts/fable-team-bin/ft-nano-evidence-check.sh <카드> --repo <나노 워크트리> --feat main`.
- 판정서 초안 = `.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · ★다음 번호 §46★.
- DA = byz-harness-da-codex#0(mbox relay · 10+10분 · 2 HOLD 면 중단) · 판정문 마지막 줄 APPROVE/HOLD/REJECT 를 카드 lint 가 읽는다.

## 이 세션에서 닫힌 것
| 무엇 | 닫는 증거 |
|---|---|
| R24 tmm bash 4 가드 | §42 · main 4050da703f(#883) |
| R25 미러 요약기 cc 경로 | 라이브 설치 뒤 err 새 줄 0 · main 4050da703f(#883) |
| 아침 매거진 설계 + DA(HOLD 1 → APPROVE) | DESIGN-morning-magazine-20261008.md · DA-magazine-20261008.md · 78fa5d908f |
| 매거진 ① 수집 | §43 · 나노 0216631058 |
| 매거진 ② 출력(반송 r1: 미러 글 오인·done 순서·시험 290줄) | §44 · 나노 2a820d879e · launchd com.byz.ft-magazine 등록(판정 350) · 첫 호 ts 1791417434.528749 |
| 판정 348 md push = ops/magazine 전용 | 설계 §6 확정 · .worktrees/ops-magazine |
| 매거진 후속 「오빠 할 일」 = 계보 기준 미답 요청 + 요약 구체화 | §45 초안 · 나노 3d5fcaff2a(카드 진행/magazine-hil-pending-summary.md 증거 줄 OK) |

## 열린 일 (순서대로)
1. **제안서 흐름(판정 352) — DA APPROVE 받음(#61101 · DA-proposal-flow-20261008.md §6) · master 에 «아직 안 알림»**: 카드 2장 `대기/proposal-docs.md`·`대기/proposal-tools.md` lint OK · 설계 `DESIGN-proposal-flow-20261008.md`(r1 반영) · 셋 다 미커밋. → master#12 에 「DA APPROVE · 커밋 + 나노 2석 spawn」 1통. 나노 완료 오면 독립 재현(장애 주입: register Tank 0회 5종·create1/label1 · publish r1 추가 0 3종·불명 ERROR) → §46·§47.
2. **§45 집행 확인**: master 가 OPS-VERDICT-45 반영 + 카드 완성 이동 + 랜딩 + install-magazine.sh(복사만) — 내일 08:00 호 전. 다음 08:00 호 뒤 뿌리 글 「오빠 할 일 N건」·3줄 구체성 확인.
3. **gate-hook-kit-equals-home 카드**(대기/ · 미커밋 · 판정 343 후속 — 키트 orchestration-gate 훅에 보류된 ⓪ 생명주기 deny 가 켜진 채 남음) — planner 지시 대기(master#12 #60969).
4. 남은 오빠 결정(브리핑 65a08d106f): mac-mini homebrew bash · ~/.tmm 새 버전 설치.

## 함정 (실측 · 이 세션)
- 슬랙 미러와 매거진·제안서는 같은 봇 토큰·같은 채널 — 뿌리 글 찾기는 «첫 줄 정확 일치»만(포함 매칭은 미러 글을 오인 — §44 반송 r1).
- HIL 요청 세기: 접두 `[a->b]` 를 뗀 본문 시작 `[HIL` · 회신은 좌석 «계보»(#N 뗀 이름)로 — 승계로 회신이 #N+1 에 간다(§45).
- 키트 bin(scripts/harness-install/fable-team/bin)에 새 파일 = 드리프트 검사 BLOCK(전 팀 spawn·close) — 새 도구는 키트 bin 밖(proposal/ · slack-mirror/)에.
- weasyprint 는 pango 없음 · Chrome `--headless --print-to-pdf` 는 60초 안 끝남 → PDF 는 playwright chromium.
- main-team-governance.md 는 홈에만 있다(리포 사본 0) → tracked 초안 + master cp 설치.
