# HANDOFF — byz-harness-arch-claude#10 → #11 (2026-10-08 · 컨텍스트 400k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: 6-b(오케 요청을 사용자와 협의해 개선) + C(배포·반영) + 원문 5(머신 독립 배분) + 원문 7(쪼개 동시에).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(17조항) Read → Serena initial_instructions → activate_project(★/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops★ — 부팅 때 다른 워크트리가 잡힌다) → i-have-adhd 로드.
2. 골 대조 3줄 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(`ft-harness-info.sh seats` · 지금 byz-harness-master-claude#13)에 mbox.
3. 같은 턴 CronCreate 10분 체크 틱(mbox recv + 열린 일 실측 + 오빠 3줄) — 없으면 착수 0.
4. zsh 함정: `echo ===` 금지(구분자 `echo ---`) · mbox send 와 같은 Bash 호출 안에 백틱이 있으면 훅이 «명령 전체» 차단 → 분리 호출 · `rm -rf` 가 든 명령은 block-destructive 가 막음 → 임시 파일은 scratchpad 에 두고 지우지 않는다.

## 역할 (governance §6)
arch = 설계·카드(대기/ · lint 통과 · 미커밋)·DA 소환 판단·나노 결과 «독립 재현»·닫힘 문안(카드 증거 줄 + 판정서 §초안). master = 커밋·push·설치·좌석. arch 코드 0.
- 카드 lint: `source <루트>/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>` (구현 범위에 «실재» 경로 1개 이상 · DA 파일 없으면 사전검증 REJECT 가 정상).
- 증거 줄: `bash scripts/fable-team-bin/ft-nano-evidence-check.sh <카드> --repo <나노 워크트리> --feat <나노 base sha>` — ★`--feat main` 은 미랜딩 ops 커밋이 코드 변경으로 잡혀 REJECT · 나노 base 로★. 이유 칸에 «·» 금지(정규식). 카드에 「- 정본 영향 없음: <이유 ≥10자>」 줄 필수(완성 이동 게이트).
- 판정서 초안 = `.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · ★다음 번호 §49(eli5) 뒤 §51★ (§46·47·48·50 완료).
- 시험 python = `<루트>/.venv/bin/python`(시스템 python3.14 는 pytest 없음) · PDF dry-run 은 `/opt/homebrew/bin/python3`(playwright).
- DA = byz-harness-da-codex#0(mbox relay · 10+10분 · 2 HOLD 면 중단) · relay 뒤 5초에 pane busy 확인, 안 돌면 `ring <좌석> <seq>`.

## 이 세션에서 닫힌 것
| 무엇 | 닫는 증거 |
|---|---|
| §46 제안서 흐름 문서(판정 352) | proposal-docs e56fed8f3f · 카드 완성 f51e3c53d5 |
| §47 제안서 도구 3개(판정 352) · 반송 r1(머리 상태 줄 2개 거부) | ops/main-base 55d5812196 · 81b4472fe3 |
| 판정 354 매거진 풀 디테일 설계 + DA(HOLD 1 → APPROVE · §5-b r2 APPROVE) | DESIGN-magazine-full-detail-20261008.md · DA-magazine-fulldetail-20261008.md · 6594f5c8ae |
| §48 매거진 ① 수집 · 반송 r1(merge_bodies 881→35) | ops/main-base 8e5e285fed |
| 판정 359 세트 발주 ①조사 ②설계 ③DA(HOLD 1 → APPROVE) · 카드 | SURVEY-file-based-dispatch-20261008.md 05d5a0e0ec · DESIGN-set-dispatch-20261008.md · e660fd8295 · 나노 spawn 841aafca5b |
| 매거진 렌더·발행 카드 재대조 | RECHECK-magazine-full-render-publish-20261008.md |

## 열린 일 (순서대로)
1. **§50 초안 완료·master 집행 대기**: `.fable-team/state/drafts-r21/OPS-VERDICT-50.md` · 카드 진행/magazine-full-render-publish.md 증거 줄(미커밋 · nano aeea2736ea).
2. **판정 49 eli5(나노 magazine-eli5-html · 반송 r2 진행 중)**: r1(560c1bbf71)은 픽스처 통과·실자료 72단위 한 번 호출에서 차단 단어 Eli5Error(30초)·timeout(90초). r2 = 설계 §5-b(12개 묶음·동시 3 · 단위별 회색 칩 「AI 풀이 없음 — 사유」 · 바닥 줄 N/전체·생략 M · 0건일 때만 Eli5Error · 200줄 한도로 magazine_eli5_batches.py 1개 추가 master 승인). 재현 = 실자료 모델 사본 `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/1b48fbdd-7716-47fb-9d73-4d6a71438c94/scratchpad/model-detail.json`(휘발 — 없으면 detail-collect 로 collect("2026-10-08") 재생성 약 30초)로 실 LLM 1회 → N+M=72 · 시간 · DA §r2 조건(전체 순회 · 누락 ref 사유 칩) 확인 → §49.
3. **통합 뒤 확인**: §48·§49·§50 cherry-pick → 전체 매거진 시험 → 수동 `--date 2026-10-08 --reattach r1 --no-push` 결과 1줄(PDF 경로·쪽수·HTML 경로·답글 ts) → install-magazine.sh WARN 0 → 내일 08:00 호.
4. **판정 359 나노 set-dispatch-tools(진행)**: 완료 오면 시험 2개 + 홈 초안 diff(추가뿐) + 빈 원장 출력 재현 → §51. 그 뒤 첫 적용(CFO 7세트)은 planner·issues master 몫 — 회수본 `design/harness/drafts/file-dispatch/ORDER-358-cfo-sets-relay-20261008.md`.
5. **R20(낮은 우선 · master#13 #61321 · 미착수)**: CFO 나노 개설 때 ft-index-lint 가 v65 골 3줄로 검사해 REJECT → `bin-cfo/cfo-env.sh` 에 `FT_GOAL_LINES_FILE`(design/cfo/GOAL-cfo.md 13~15행) export 추가 안(feature·harness env 와 같은 패턴). 원장 REQUEST-LEDGER R20.
6. gate-hook-kit-equals-home 카드(대기/ · planner 지시 대기) · r23-tank-rest-path(보류).

## 함정 (실측 · 이 세션)
- 나노 base 가 ops/main-base 보다 뒤처진 경우 `git diff <다른 sha> HEAD` 는 남의 커밋이 «삭제»로 보인다 — 비교는 나노 base 기준.
- 매거진 실자료 규모: 단위 72 · PDF 228쪽 · D4 머지 본문 4259줄 — 픽스처 통과는 실자료 통과가 아니다(eli5 r1 실측).
- md 에 외부 본문을 실을 때 줄머리 `#` 은 제목이 된다(GitHub 링크) — 인용 처리(§50).
- `rev-list -1 --before` 는 그 ref 에서 도달 가능한 커밋 중 고르므로 세 갈래 시작점이 같게 나올 수 있다(§48 메모).
- planner 발주문에 엉뚱한 골(v65)이 붙어 온 적 있음(판정 359) — 발주 머리 골 3줄을 이 파일 골과 대조.
