# HANDOFF — byz-harness-arch-claude#27 (2026-10-10 · 컨텍스트 410k 경고 · 열린 설계 0)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: B(개선요청 접수·협의) + C(업그레이드·배포 발행·반영).

## 상태 = 휴식 (arch 몫 설계·카드는 전부 master 에 넘김 · 집행은 master)

| 요청 | 오빠 판정 | arch 산출 (ops/main-base) | 남은 것 (master 몫) |
|---|---|---|---|
| R81 spawn REJECT 고아 좌석 | 845·846·847(kill = ③④ 실패만) | 카드 `indices/…/r81-spawn-reject-rollback.md` 956514f229 · DA 3회 기록 | main ddcf90affc 랜딩·설치 끝 · v65 고아는 v65 판정 |
| R83 사람 `!` 명령 = 짧은 한 줄 | 850·852(① 번호)·853(/tmp · 홈 0) | 제안서 `PROPOSAL-hil-short-command-20261010.md` r1 f40720a0ba · 카드 진행/ cb1bdcd849 | 나노 결과 판정 · #1184 r1 재승인 |
| R86 쪽지 개선(R34·R57·R85 합침) | 876·877·881(① 세션 안 감시 · 임시 조치 유지) | 제안서 `PROPOSAL-inbox-instant-no-inject-20261010.md` 72df93a6de · 카드 대기/ `r86-inbox-instant-no-inject.md` 1f5964593d | spawn → 랜딩 → 설치 → planner Monitor 무장 → 오빠 참여 라이브 1회 → 원장 R34·R57·R85 닫기 |
| R87 LOOM 터널 세션 종속 | (미결 — 제안 대기) | 제안서 `PROPOSAL-loom-tunnel-outside-session-20261010.md` 0e8b85cc74 · 카드 초안 대기/ `r87-loom-tunnel-launchd.md` a9f0284b1f(제안서 = 없음 · spawn 0) | 슬랙 발행 → 제안 Issue → 오빠 컨펌(①launchd 추천) → 카드 머리 #M · 구현 범위 확정은 후계 arch |

## 함정 (실측 · 이 세션)
- 카드 lint 는 팀 env 필요: `source <루트>/.fable-team/bin-harness/harness-env.sh` 뒤 `ft-index-lint.sh`(안 하면 골 3줄 «불일치» 오탐). 구현 범위에 «실재 경로» 1개 이상 · 새 파일만이면 REJECT.
- 제안서 발행 전 필수 6칸 제목 = 결론·오빠가 결정할 것·배경·제안·되돌림·근거(근거에 sha 1개+) — 확인: origin/main `scripts/harness-install/proposal/` 의 py 들을 한 폴더에 꺼내 `PYTHONPATH=<폴더> python3 proposal_issue_lib.py sections --file <제안서>` rc=0.
- 슬랙 발행기는 카드 `## 상태` 절 필수 · 컨펌 전 카드는 머리 「- 제안서: 없음 — 사유」, 컨펌 뒤 `#M`. 카드 본문에 PROPOSAL 파일명 인용 금지(R82 오탐).
- 쪽지 분류 `rule_class` 는 `re.M` — 새 규칙은 `\A` 로(본문 중간 줄 오탐).
- master 가 같은 워크트리를 쓴다 → `git commit -- <내 경로>` 만 · master 가 staged 로 옮긴 카드는 손대지 말고 내용만 고친 뒤 master 에 커밋 부탁.
- 오빠에게 가는 글 = 쉬운 말 · R번호·판정 번호는 맨 아래 각주 표에만(10-10 오빠 「인댁스쓰면 내가 어떻게 이해해?」).
- 커밋 뒤 auto gc 가 남의 lock(`feat/fix/v5-sse-seam-gap.lock`)으로 실패 메시지 — 커밋은 정상 · lock 손대지 않음.

## 별 후보 (착수 0 — 지시 때만)
1. R86 실측: 쪽지 분류 «판정 N» 머리말은 ①③⑤⑥ 가 섞여 규칙표로 못 가름 — Haiku 경로 절반 감축 뒤 남은 것 재측정.
2. arch#26 인계서 «별 후보» 4건 그대로(매거진 eli5 TIMEOUT 180 · R77 Read 차단 훅 drift · zombie-clean SKILL 74행 · arch#25 5건).

## 추기 (16:4x · 컨텍스트 440k)
- R87: 나노 r2 → main edda18c4a1(PR 1221) 랜딩·실머신 설치 끝(launchd 소유 · 옛 세션 터널 정리). DA 1·2·최종 3회 HOLD — 남은 1건 = install.sh 36~40 watchdog 이 부모 TERM 시 자식 고아 생존(#73362). 닫힘 판정문 0 · 카드 진행/ 유지. gateway 16:30:54 PoolTimeout 1건 = 원인 미규명(보고 «0» 과 다름). 결정 ⓐ나노 r3+master 시험 닫기 ⓑ별 카드 — master#27 쪽지 #73363 로 상신됨.
- 반송 지시 r1: design/harness/ORDER-r87-return-r1-20261010.md.
