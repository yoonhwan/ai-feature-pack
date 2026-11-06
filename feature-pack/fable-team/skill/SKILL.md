---
name: fable-team
description: 일반화된 팀 오케스트레이션 하네스. 트리거: "FT 구성", "FT 해보자", "FT 하자", "fable-team", "팀 구성", "팀 에이전트 설치", "팀으로 진행", "FT 업데이트". 오케스트레이터는 전달·조율만 · 기획·문제해결은 architect · 구현은 worker. 트리거 시 부팅 시퀀스(피처→설계→컨펌) 강제.
---

# fable-team — 팀 오케스트레이션 하네스

전문 = `references/skill-sections/`. 필요한 절만 읽는다.

## 절 인덱스
- **역할 분리** — 오케=전달 · arch=설계 · worker=구현 → `references/skill-sections/01-role-separation.md`
- **트리거 게이트** — 발동 전 확인 4항 → `references/skill-sections/02-trigger-gate.md`
- **부팅 시퀀스** — 3스텝 인터뷰 강제 → `references/skill-sections/03-boot-sequence.md`
- **v3 스폰** — 기본 경로 · tmuxc 스폰 → `references/skill-sections/04-spawn-v3.md`
- **Legacy spawn** — 롤백(agent-v2) → `references/skill-sections/05-spawn-legacy.md`
- **표준 로스터** — 역할·모델 = agent-templates → `references/skill-sections/06-roster.md`
- **사용 절차** — 설치·업데이트 순서 → `references/skill-sections/07-usage.md`
- **강제 게이트** — 훅 물리 차단 → `references/skill-sections/08-orchestration-gate.md`
- **함정** — 실측 함정 → `references/skill-sections/09-pitfalls.md`
- **운영 규율** — v6 retro §4.1 → `references/skill-sections/10-operating-rules.md`
- **문제해결 7원칙** — 기본 방법론 → `references/skill-sections/11-problem-solving-7.md`
- **문제해결 체인** — 표준 체인 → `references/skill-sections/12-problem-chain.md`

## 상시 규칙 (3줄)
1. 오케는 전달·조율만 — 기획·구현 직접 수행은 게이트 훅이 차단.
2. 기획·문제해결 = architect · 라이브 디버깅은 FT 반려·솔로.
3. 트리거 시 부팅 시퀀스(피처→설계→프리뷰→컨펌) 생략 0.
