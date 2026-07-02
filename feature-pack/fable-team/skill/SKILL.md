---
name: fable-team
description: 일반화된 팀 오케스트레이션 하네스. "FT 구성", "FT 해보자", "FT 하자" 요청 시 사용 (보조 트리거: "fable-team", "팀 구성", "팀 에이전트 설치", "팀으로 진행"). 오케스트레이터(ultracode 지원 최상위 모델)는 전달·조율만, 기획·문제해결은 planner 브레인(기본 fable5 max)이 전담. 설치 인터뷰 + 피처 설계 인터뷰로 프로젝트별 워커를 커스텀 생성한다.
---

# fable-team — 일반화된 팀 오케스트레이션 하네스

## 역할 분리 (핵심 설계)

| 층 | 담당 | 모델 | 하는 일 | 안 하는 일 |
|----|------|------|---------|-----------|
| **오케스트레이터** | 현재 세션 | ultracode 지원 최상위 모델 (fable5 등 — 일반화) | 태스크 분해, 워커 스폰/전달, 커뮤니케이션, 파이프라인 진행, 게이트 판단 릴레이 | **기획·문제해결 금지** — 두뇌 작업을 직접 하지 않아 멈추지 않는 문제해결 루프가 가능 |
| **planner (기획 브레인)** | 서브에이전트 | 기본 fable5 + effort max (설치 시 변경 가능) | 원인 분석, 해결 설계 — 컨텍스트를 파일/텍스트로 받아 **설계 파일로 반환** | 구현/실행/오케스트레이션 |
| **워커 4종** | 서브에이전트 | checker/implementer/tester/da | 확인, 구현, 테스트, DA 판정 | 기획, 서브 스폰 |

## 트리거 시 체크 게이트 (허들)

스킬 발동 즉시 확인하고, 미충족이면 진행 전 사용자에게 보고한다:

1. **ultracode/effort 설정**: 현재 세션이 ultracode(또는 그에 준하는 최상위 effort + Workflow 오케스트레이션 지원)로 실행 중인가? 아니면 `/effort ultracode` 설정을 안내하고 확인 후 진행.
2. **세션 effort 상속 함정**: 세션이 xhigh(ultracode)면 claude-5 계열(sonnet-5, fable-5) 워커는 Agent 팀 하네스에서 effort 상속으로 400 에러 즉사 — **스폰 경로 분리 규칙**(아래) 준수.
3. 에이전트 정의 존재: 대상 위치에 `<prefix>-planner/checker/implementer/tester/da`가 설치돼 있는가? 없으면 설치 인터뷰(`references/install-interview.md`)부터.

## 스폰 경로 분리 규칙 (실측 — 2026-07-02)

| 워커 | 경로 | 이유 |
|------|------|------|
| planner (fable5 max), tester (sonnet5 high) 등 **claude-5 계열** | **Workflow `agent()`** + `model`/`effort` 명시 | Agent 팀 하네스는 frontmatter `effort:`를 무시하고 세션 effort(xhigh)를 상속시켜 claude-5 계열이 `400 level "xhigh" not supported`로 죽는다. Workflow의 effort 오버라이드는 실증 통과 (sonnet5+high ALL_PASS). |
| checker/implementer/da 등 **4.6 계열** | **Agent 도구** (팀 하네스) | xhigh 상속에도 정상 동작 실증. 이름 부여 스폰 → 완료 후 열린 상태 대기 → SendMessage 후속 질의/approve loop 재라운드 가능. |

planner는 어차피 **무상태 계약**(컨텍스트 입력 → 설계 파일 출력)이라 Workflow 일회성 호출이 자연스럽다. 대기가 필요한 워커(approve loop 등)만 Agent 경로를 쓴다.

## 표준 로스터 (references/agent-templates/ 와 1:1)

| 워커 | 브레인 기본값 | effort | 도구 | 전담 |
|------|--------------|--------|------|------|
| ft-planner | **fable5** (설치 시 변경 가능) | max | Read, Grep, Glob, Write | 원인 분석·해결 설계 → 설계 파일 |
| ft-checker | sonnet 4.6 | low | Read, Grep, Glob | 문서/코드/로그 확인 (병렬 다수) |
| ft-implementer | opus 4.6 | max | +Bash, Edit, Write, Skill | 설계 파일 기반 구현. 프로젝트 스킬 호출 가능 |
| ft-tester | sonnet 5 | high | +Bash | 테스트 설계·실행·repro |
| ft-da | codex gpt-5.5 xhigh (드라이버: sonnet 4.6 low) | xhigh | +Bash | DA review + DA approve loop |

공통 불변: `tools:`에 Agent/Task 없음(서브의 서브 차단), 워커 모델에 fable-5/opus-4-8 금지(planner의 fable5만 예외), 보고는 최소 토큰 형식 강제.

**크루 (opt-in 확장 로스터)**: 로컬 하네스 전문 드라이버 워커 — ft-da(codex)가 원형이며, 같은 패턴으로 `omo`(OMX/OMO — `ft-omo.md.tpl`)·`superpowers`·`gstack` 등 **하네스 이름으로** 추가한다. **세션 승계(resume/inject 체인)와 컨텍스트 윈도우 관리(요약-후-fork + WINDOW_PRESSURE)는 크루의 기본 제공 계약**(brain_sessions 4번째 버킷 규칙 동일 적용). 감지·설치는 install-interview §4, 공통 계약·카탈로그는 `references/crew/crew-support.md`, omo 하네스 상세는 `references/crew/omx-omo-full-context.md`.

## 사용 절차

0. **브레인 가용성 체크** (설치 시작 전 필수): `references/brain-availability.md` — codex/cursor 등 미가용 시 대응 모델 추천으로 대체
1. **설치 인터뷰** (최초/변경 시): `references/install-interview.md`
2. **피처 인터뷰** (매 피처 시작 시): `references/feature-interview.md` — 무엇을 할지 한 줄/파일로 받고, 프로젝트의 스킬·플러그인·하네스·도구를 서치해 추천 기반 설계 인터뷰 진행
3. **오케스트레이션** (파이프라인 실행): `references/orchestration-playbook.md`
4. **모니터링·지원 체크 루프** (파이프라인 상시): `references/monitoring-loop.md` — 멈춤 감지 + 진로이탈 교정 + 상태 원장
5. **컨텍스트 관리** (상태 외재화·compact/clear/재시작·복원): `references/context-management.md` — 디스크 SSOT(`.fable-team/state/`) write-through, ctx 임계 정책, 세션 재시작 복원 절차. **새 세션 트리거 시 피처 인터뷰 이전에 §4(ACTIVE 감지·복원)를 먼저 수행.**

## 함정 (실측)

- **Agent 팀 하네스는 frontmatter `effort:` 무시** → 세션 effort 상속. ultracode(xhigh) 세션에서 claude-5 계열 워커 즉사. Workflow 경로로 우회.
- **에이전트 .md 수정은 이미 등록된 타입에 소급 반영 안 됨** — 같은 이름 재사용 시 구정의(모델·도구)가 캐시로 살아있을 수 있다. 정의 변경 시 새 파일명으로 만들거나 새 세션에서 사용.
- codex 호출: `npx -y @openai/codex exec ... < /dev/null` (alias 미해석 + stdin hang 방지), `-c model_reasoning_effort="xhigh"` 지원 확인됨, 적용 여부는 세션 헤더 `reasoning effort:` 라인으로 검증.
- 워커 실제 모델 검증: `~/.claude/projects/<proj>/<session>/subagents/agent-*.meta.json`의 `model` + `agent-*.jsonl`의 `message.model`.
- 워커 감시: Monitor로 `agent-*.jsonl`에 `API Error` 문자열 포함 폴링 (조용한 실패 방지).
- **원장이 컨텍스트에만 있으면 자동 컴팩션/재시작/증류로 증발** → 라운드 한도 붕괴·완료 단계 재실행·미승인 종결 위험. 진행 상태는 반드시 디스크 SSOT(`.fable-team/state/`)에 write-through (`references/context-management.md`).
