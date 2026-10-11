# HANDOFF — byz-harness-arch-claude#26 (2026-10-10 · 컨텍스트 412k 경고 · 열린 설계 0)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: B(개선요청 접수·협의) + C(업그레이드·배포 발행·반영).

## 상태 = 휴식 (arch 몫 설계·카드는 전부 master#25 에 넘김 · 집행은 master)

| 요청 | 오빠 판정 | arch 산출 (ops/main-base 커밋) | 남은 것 (master 몫) |
|---|---|---|---|
| R74 매거진 크기 | 806 → 812 A안 → 821 ①(건당 5줄·절당 20건·경보선 1,500) | 제안서 `PROPOSAL-magazine-size-cap-20261010.md` r1 · 카드 `indices/진행/r74-magazine-size-cap.md` · 반송 지시 `ORDER-r74-return-r1-20261010.md`(8cfae0cd40) | 나노 r1 끝(9b2e0cd845 · 10-10 규모 md 1,316줄) → 시험 재실행·라이브 설치 |
| R75 zombie-clean keep-last-2 | 807 · 전역 CLAUDE.md 820 반영됨 | 설계 `DESIGN-r75-zombie-clean-keep2-order-20261010.md` r1(사전 DA APPROVE #71393) · 카드 `indices/대기/r75-zombie-clean-keep2-order.md`(2ee9a108fb) | 나노 spawn → 시험 11건 → 설치(.bak) |
| R76 승인 제안서 기록 발행 | 809 | 카드 `indices/진행/r76-…`(eb54882c22) | main 랜딩됨(61384daf80 기준 코드에 반영) · 라이브 두 파일 ≠ main(설치 전 diff) |
| R77 «오빠가 본 승인» 게이트 | 811·814 → 816 A안 → 826 ①Issue 흡수 | 제안서 `PROPOSAL-proposal-approval-gate-20261010.md` r1 · 카드 `indices/진행/r77-proposal-approval-gate.md` 구현 범위 r1(848a750452 · DA 2차 B1·B3 필수 교정 포함) · loom 7건 사후 Issue 계획 planner#21 relay(seq 71508) | 나노 r1 결과 보고됨(09:39) → 새 범위 DA 재발주 → 설치 · loom 7건 = loom arch 초안 + issues master 등록 |
| R79 GCE 의도된 정지 VM | 830 | 카드 `indices/대기/r79-gce-intended-stopped-vms.md`(43d7b69262) | 나노 spawn → 적용(ⓑ ops-guard 로컬 우선 추천 / ⓐ main 묶음 push = 오빠 승인값) |
| R80 기록 rN 답글 | (R76 후속 · 도구 결함) | 카드 `indices/대기/r80-proposal-publish-record-revision.md`(bc48f39695) | 나노 spawn → 랜딩 → 설치 → v65 arch#197 에 1줄 |

## 별 후보 (착수 0 — 지시 때만)
1. 매거진 쉬운 판 `magazine_eli5_batches.py:13` `TIMEOUT = 180.0` — 전역 7초 룰과 다름(배치 12건 한 호출이라 별 판단).
2. R77 제안서 §4 좌석 매거진 Read 차단 훅 — live `boot-read-gate.sh` ≠ 추적본(diff 먼저).
3. `SKILL.md`(zombie-clean) 74행 «기본 1» 이 옛 값 — 전역 CLAUDE.md 는 820 으로 고쳐짐.
4. 이전 arch#25 별 후보 5건(R72 recheck_sha · cherry 게이트 design/ 충돌 · spawn 233줄 · mbox-v2 계보 · codex Serena 판) 그대로.

## 함정 (실측 · 이 세션)
- 이 워크트리의 `scripts/fable-team-bin/mbox-v2.sh` 는 `mbox.py` 가 없어 죽는다 → 정본 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh` 만.
- `byz_proposal_publish.py` 발행 조건: 제안서 머리 `- 상태:` 1줄(초안·컨펌 대기·수정 요청 rN·승인 — 판정 N) · 커밋된 원문(미커밋 BlockError) · 카드에 `## 상태` 절 · `--resume-script` 는 루트 `.fable-team/bin/ft-resume-cmd.sh`(v6-realtime-live 쪽이면 planner 명부를 못 찾음). 수정판은 `--revision rN`(같은 스레드 답글).
- 슬랙 링크 형식 `https://openclaw-bott.slack.com/archives/C0C6MJGRR89/p<ts 점 뺌>` · 답글은 `?thread_ts=<뿌리>&cid=C0C6MJGRR89`.
- 카드 lint: 골좌표 「…」 는 GOAL-harness.md 표 원문 복붙(20자+) · `## 상태`·`## 구현 범위`·`## 완료 조건` 필수 · 구현 범위 경로 중 1개 이상 실재(새 파일만 있으면 REJECT — 기존 파일 경로 하나를 같이 인용).
- 커밋 뒤 auto gc 가 남의 lock(`feat/fix/v5-sse-seam-gap.lock`)으로 실패 메시지를 낸다 — 커밋은 정상 · lock 손대지 않음.
- 매거진 원문(`~/.hermes/magazine/*.md`) Read 금지 — wc·헤더 개수·가짜 모델 측정만.
- master 가 같은 워크트리를 쓴다 → `git commit -- <내 경로>` 만 · 남의 staged 이동(r74·r76 진행 이동)은 손대지 않음.
- 스크래치(#26) = `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/cceab6a7-941b-4789-ae20-771526a56b2c/scratchpad/`(zc-r1.sh · measure_r74*.py).
