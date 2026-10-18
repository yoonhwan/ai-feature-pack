# HANDOFF — byz-harness-arch-claude#12 → #13 (2026-10-08 · 컨텍스트 416k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md Read → Serena initial_instructions → activate_project(★/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops★ — 다른 워크트리가 잡힌다) → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(byz-harness-master-claude#14)에 mbox. 같은 턴 CronCreate 10분 틱.
3. 함정: zsh 에서 `$(` 든 grep 패턴은 변수가 비는 일 잦음 → `grep -F` 또는 python · mbox 본문 백틱 금지 · 임시 파일은 scratchpad.

## 역할 (governance §6)
arch = 설계·카드(대기/ · lint 통과 · 미커밋)·DA 소환 판단·나노 결과 «독립 재현»·판정서 초안. master = 커밋·push·설치·좌석. arch 코드 0.
- 카드 lint: `source <루트>/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>` (조사 근거 경로는 리포 상대 전체 경로 · 줄 번호 실재).
- 나노 증거 줄은 «카드 끝 맨몸 줄 · 미커밋 · 세트 = 현재 HEAD» — 나노들이 계속 빠뜨린다(R27·카드 1 두 번) → 재현 때 `ft-nano-evidence-check.sh <카드> --repo <나노 wt> --feat <base_sha>` 먼저.
- 판정서 초안 = `<루트>/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · ★다음 번호 §56★(§54 R27 · §55 판정 404 카드 1 초안 완료).
- DA = byz-harness-da-codex#0(relay · 10+10분 · 2 HOLD 면 중단 · 교정 요청 땐 스냅샷 sha 를 DA 파일에 고정하고 그 뒤 수정 0).

## 이 세션에서 닫힌 것
| 무엇 | 닫는 증거 |
|---|---|
| R21 feature 틱 뉴스 대상 | 좌석표 정정 뒤 ft-tick-feature.log 12:48:16 `master sent to byz-feature-master-claude#2` · 승계 뒤 13:26 `#3` |
| R27 틱 master = _master 하나 (§54) | PR 909 병합 13:40 · 팀 틱 5 + v65 틱 md5 = main · 나노 6dc923936d |
| 판정 404 ① 감사 | design/teams/harness/AUDIT-j404-slack-threads-20261008.md (결과 답글 있는 스레드 1/6 · 원인 = 손 hermes send + 결과 단계 부재) |
| 판정 404 ② 설계 | DESIGN-resume-index-20261008.md r1 · DA HOLD 1 → 교정 1 APPROVE · 카드 2장 |
| 판정 404 카드 1 재현 + §55 초안 | 나노 15a2081450 · 69+187 passed · 계약 10 소스 대조 · 증거 줄 OK(#62412) |
| R29 안·카드 | PLAN-r29 r1 · DA HOLD 1 → 교정 1 APPROVE · 카드 대기/r29-cherry-gate-squashed-pr.md · 나노 spawn(master) |

## 열린 일 (순서대로)
1. **§55 master 집행 대기**: 초안 전달 필요(이 승계 쪽지에 포함) → append · 카드 완성 · 랜딩 · install.sh·install-magazine 복사 · 장부 --init → 카드 2(result-reply-close-gate) spawn. 관찰 2(--bot hermes 강제 0 · check 의 카드↔장부 root_ts 일치 미검사)는 반송 아님.
2. **R30 승계 창 이관(오빠 체감 버그 · 최우선)**: 설계 DESIGN-r30-succession-window-handover-20261008.md · ★DA HOLD-1 도착(#62422 · DA 파일 §2~§4) — 교정 1회 남음★: H1 모든 클라이언트 일괄 switch 는 오빠 의도(일부러 보던 탭·archive) 구분 못 함 → 실행 직전 변경 재확인·대상 한정 필요 / H2 Stop 훅·mbox 가드의 blanket 차단은 문서 인용·HIL 원문 오탐 + 오탐 규칙(기록·허용·묶음 알림)과 충돌 / H3 tmux 옵션 @handed_over_to 는 휘발·오염 가능 → 영속 명부(seats*.json 행 관계) + 정확한 세션 검증으로. 자동 이관 목적은 수락. 교정 → 스냅샷 sha 고정 → 마지막 DA → 카드화(ft-seat-handover.sh · no-attach-to-user Stop 훅 · mbox HIL 가드 · 정본 문장 3곳 문안). 첫 적용 = feature 탭 /dev/ttys000 (#2→#3) 이관(master).
3. **R29 나노 결과 재현**(byz-harness-nano-r29-cherry-gate-squashed-pr#0) → §56 초안.
4. **판정 410 감사**(planner 콘솔 보고 ↔ 슬랙 미러 괴리): 원문 `.fable-team/comm/bodies/62351.txt` · 감사 표(콘솔 jsonl ↔ 미러 4열: 누락·요약 손실·시점 차·용어 차 · 사례 10건+ · 판정 373~409) → planner#10. R30 뒤.
5. 소급 결과 답글 7건(설계 §7)은 카드 2 랜딩 뒤 master 집행.
6. 대기 카드: gate-hook-kit-equals-home(planner 지시 대기) · r23-tank-rest-path(보류).

## 함정 (실측 · 이 세션)
- 슬랙 채널: #byz-planner = C0C6MJGRR89(yoonhwan 봇) · #byz-agent = C0ADA0XRBB2(hermes 봇 · yoonhwan 봇 미가입). 읽기 덤프 스크립트 꼴 = mirror_lib.paged(토큰 값 출력 0).
- 팀 틱 사본은 키트와 «갈라진 판» — 이제 main 에 ft-tick-team.sh 로 추적(덮어쓰기 금지).
- planner 수신처 = #10(#9 정지). feature master = #3.
