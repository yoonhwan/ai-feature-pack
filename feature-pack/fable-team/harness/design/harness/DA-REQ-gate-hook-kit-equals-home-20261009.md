# DA 요청 — gate-hook-kit-equals-home 최종 DA(완성 이동 · 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료) (arch#21 · 2026-10-09)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: 원문 5(키트로 받는 훅 = 이 Mac 에서 도는 훅) + 6-b(오빠 결정 343) + C.

## 고정 대상
- 커밋 `4ed459ddfc7178ecb8a04751f32832f2ddd11202`(브랜치 `nano/gate-hook-kit-equals-home` · base origin/main `d23385ef35`) · 2파일 +1 −38: 키트 `scripts/harness-install/fable-team/templates/hooks/orchestration-gate.sh` ← 홈 `~/.claude/hooks/orchestration-gate.sh` cp · `scripts/harness-install/fable-team/templates/rules/orchestration.md:39` 보류 문구 1개.
- 카드 `design/teams/harness/indices/진행/gate-hook-kit-equals-home.md`(또는 대기/) · 오빠 결정 판정 343(`design/teams/harness/TABLE-gate-hook-copies-20261008.md` 「오빠 결정」 문단).

## arch#21 독립 재현 (4ed459ddfc 아카이브)
- cmp 키트↔홈 rc=0 · 실행 비트 O · 키트에 `LIFECYCLE_RE`·`in_ft_tmux` 0건 · test_orch_gate_top_models pass=10 fail=0 rc=0 · install.sh `hook orchestration-gate.sh home=same settings=registered` · 홈 훅·settings.json 변경 0.

## 질문 (bounded · 새 요구 금지)
- **Q1 빠지는 것 = 보류분뿐**: 키트에서 사라진 37줄이 ⓪ 생명주기 deny(`LIFECYCLE_RE`·`in_ft_tmux` 정의 + deny/면제 블록)와 ⓐ 그 워커 면제뿐이고, 홈에만 있는 줄 0 인가(= 기능 손실이 판정 343 의 보류 결정 범위를 넘지 않는가).
- **Q2 다른 키트 파일 영향**: 키트 bin(`ft-tmux-spawn.sh`·`ft-tmux-distill.sh`)·`ft-worker-guard.sh` 의 `FT_WORKER_ROLE` 사용이 이 변경으로 깨지거나, 키트 문서·시험이 ⓪ 를 «있다»고 단정하는 곳이 남는가(문서 39행 외).
- **Q3 회귀 0**: TOP_MODELS 판정·2파일 한도·워커 agent_id 면제가 홈과 같은 바이트로서 그대로인가 · bash 3.2 셔뱅.
- 범위 밖: ⓪ 켜기(보류) · boot-read-gate 주석 2줄 차이 · 프로젝트 사본 `.claude/hooks/orchestration-gate.sh`.

## 판정문
`design/teams/harness/DA-gate-hook-kit-equals-home-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.
