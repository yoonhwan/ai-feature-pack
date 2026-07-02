# 🧠 fable-team — 일반화된 팀 오케스트레이션 하네스

**오케스트레이터는 전달·조율·모니터링만, 두뇌 작업은 브레인들이.**

Claude Code 네이티브 팀 하네스(Agent/Workflow) 위에서 역할별 서브에이전트 팀을 설치·구동하는 스킬 팩. tmux 불필요. 진행 상태는 디스크 SSOT(`.fable-team/state/`)로 외재화돼 세션이 죽어도 파이프라인이 복원된다.

## 역할 구조

| 층 | 브레인 (설치 시 변경 가능) | 스폰 경로 | 전담 |
|----|--------------------------|-----------|------|
| 오케스트레이터 | ultracode 지원 최상위 모델 (fable5 등) | 현 세션 | 태스크 분해, 전달, 모니터링 루프, 게이트 분기 — **기획·문제해결 금지** |
| planner | fable5 / effort **high** (max는 opt-in — hang 실측) | Workflow | 원인 분석·해결 설계 → 설계 파일 산출 |
| checker × N | sonnet4.6 / low | Agent | 문서·코드·로그 확인 (병렬) |
| implementer | opus4.6 / max | Agent | 설계 파일 기반 구현 + 프로젝트 Skill 호출 |
| tester | sonnet5 / high | Workflow | 테스트 설계·실행·repro |
| DA 게이트 | **codex gpt-5.5 / xhigh** (비대화 `codex exec`) | Workflow/Agent 드라이버 | DA review + approve loop (최대 2라운드) |
| **크루 (opt-in)** | 로컬 하네스별 (아래 표) | Agent 드라이버 | 로컬 하네스 전문 구동 — resume 체인·윈도우 관리 기본 제공 |

핵심 불변식: ① 워커 `tools:`에서 Agent/Task 제외 → **서브의 서브 스폰 차단** ② planner 외 워커에 fable-5/opus-4-8 금지 ③ 단계 간 전달은 파일 경유(설계 파일) → 오케스트레이터 컨텍스트 최소화 ④ 라운드·복원 판정은 카운터 산술이 아니라 **파일 실재 기준**.

## 설치 — 에이전틱 가이드

아래 단계는 Claude Code 에이전트가 그대로 따라 실행할 수 있도록 쓰였다. 사람은 0단계와 인터뷰 답변만 하면 된다.

### 0. 팩 설치 (사람 또는 에이전트)

```bash
./install.sh user                      # 사용자 레벨 (~/.claude/skills/fable-team) — 모든 프로젝트 공용
./install.sh project:/abs/path        # 프로젝트 레벨 — 프로젝트별 커스텀이 목적일 때
```

### 1. 세션 준비

- **새 Claude Code 세션**을 연다 (스킬 등록은 세션 시작 시 1회).
- 오케스트레이터 세션은 **ultracode 지원 최상위 모델**이어야 한다 — 아니면 스킬이 트리거 게이트에서 `/effort ultracode` 설정을 안내한다.

### 2. 설치 인터뷰 (에이전트 주도)

세션에서 **"fable-team 설치 인터뷰"**를 요청하면 에이전트가 [install-interview.md](skill/references/install-interview.md)를 따라 진행한다:

1. **브레인 가용성 체크** ([brain-availability.md](skill/references/brain-availability.md)) — codex 등 외부 브레인을 실측 프로브. 미가용이면 대체 모델을 기본 선택지로 제시 (예: DA → claude 대체 템플릿).
2. **워커별 브레인/effort 질문** — 기본값 그대로 엔터만 쳐도 표준 로스터가 구성된다. planner 외 워커에 fable-5/opus-4-8은 거부된다.
3. **크루 감지·opt-in** — 로컬에 설치된 하네스(omx, gstack, superpowers, insane-search, ouroboros 등)를 실측 감지해 크루 추가 여부를 묻는다 (기본: 추가 안 함).
4. **에이전트 .md 생성** — [agent-templates/](skill/references/agent-templates/)의 `*.md.tpl`을 답변으로 치환해 대상 위치에 Write. 잔여 `{{` 플레이스홀더가 남으면 설치 실패로 간주.

### 3. 검증 (설치 직후 필수)

- **새 세션**에서 (에이전트 정의 등록 경계) 각 워커에 표준 프로브 1회: 도구 화이트리스트·서브 스폰 차단(`NO_SPAWN_TOOL`)·모델 적용 확인 ([orchestration-playbook.md](skill/references/orchestration-playbook.md) §프로브).
- 크루는 하네스 1회 실측 호출까지 (예: omo → `omx exec -s read-only ...`).
- 실패 패턴 `API Error 400 level ... not supported` = effort/모델 조합 오류 → 인터뷰 허용값 표로 교정 후 재설치.

### 4. 사용 시작 — 부팅 시퀀스 (강제)

**"FT 하자"** (또는 "FT 구성", "fable-team") 트리거 시 에이전트는 아래 부팅 시퀀스를 생략 없이 수행한다:

1. `.fable-team/state/ACTIVE` 복원 체크 — 진행 중 파이프라인이 있으면 복원이 부팅을 대체 ([context-management.md](skill/references/context-management.md) §4)
2. **피처 입력 인터뷰(무조건 AskUserQuestion)** — 대화 컨텍스트에서 추출한 태스크 후보 ①②를 추천으로, ③ 내용 추가(한 줄/파일), ④ 채팅에서 이어하기 중 선택받는다
3. 프로젝트 자산 서치 → **추천 설계** 제시 ([feature-interview.md](skill/references/feature-interview.md))
4. **실행 준비 프리뷰(부팅 보드)** — 피처·파이프라인 형상·로스터(+크루)·산출물 경로·라운드 한도를 한 화면으로
5. **사용자 컨펌 후에만 킥오프** — 이후 6단계 파이프라인(수집→기획→구현→검증→게이트→종결)이 파일 릴레이로 돈다

### 5. 업데이트 (로컬 패치)

팩 소스가 갱신되면 **"FT 업데이트"** 트리거 → `install.sh` 재실행(스킬 파일) + 설치된 에이전트 .md 재치환(**인터뷰 답변 보존** — `install.json` 스냅샷 기반, 재인터뷰 불요) + 새 세션 프로브 재검증. 상세: [update.md](skill/references/update.md)

## 크루 — 로컬 하네스 전문 워커 (opt-in)

da(codex)가 원형. 같은 드라이버 패턴으로 하네스 이름 그대로 크루를 추가한다. **세션 승계(resume/inject 체인)와 컨텍스트 윈도우 관리(요약-후-fork + WINDOW_PRESSURE)는 모든 크루의 기본 계약.** 공통 계약·카탈로그: [crew-support.md](skill/references/crew/crew-support.md)

| 크루 | 하네스 | 구동 | 상세 레퍼런스 | 공식 |
|------|--------|------|---------------|------|
| da | Codex CLI (gpt-5.5 xhigh) | `codex exec` 비대화 | [brain-availability.md](skill/references/brain-availability.md) | [openai/codex](https://github.com/openai/codex) |
| omo | OMX/OMO — 목적별 고성능 스킬 레이어 | `omx exec` 비대화 | [omx-omo-full-context.md](skill/references/crew/omx-omo-full-context.md) | [Yeachan-Heo/oh-my-codex](https://github.com/Yeachan-Heo/oh-my-codex) |
| gstack | QA·ship·design·browse 등 50+ 스킬 스위트 | `claude -p` 콘솔 분리 (sonnet4.6 high) | [gstack-full-context.md](skill/references/crew/gstack-full-context.md) | [garrytan/gstack](https://github.com/garrytan/gstack) |
| superpowers | TDD·디버깅·플랜 워크플로 스킬 라이브러리 | `claude -p` 콘솔 분리 (sonnet4.6 high) | [superpowers-full-context.md](skill/references/crew/superpowers-full-context.md) | [obra/superpowers](https://github.com/obra/superpowers) |
| insane-search | 차단 사이트 적응 접근·검색 (X/Reddit/Naver 등) | `claude -p` 콘솔 분리 (sonnet4.6 high) | [insane-search-full-context.md](skill/references/crew/insane-search-full-context.md) | [fivetaku/insane-search](https://github.com/fivetaku/insane-search) |
| ouroboros | 요구사항 결정화 — 소크라틱 인터뷰·모호성 스코어링 | `claude -p` 콘솔 분리 (sonnet4.6 high) | [ouroboros-full-context.md](skill/references/crew/ouroboros-full-context.md) | [Q00/ouroboros](https://github.com/Q00/ouroboros) |

하네스별 디테일(기능 카탈로그·안전 모드·few-shot)은 전부 상세 레퍼런스로 분리돼 있다 — README에는 싣지 않는다.

## 문서 인덱스

| 문서 | 역할 |
|------|------|
| [skill/SKILL.md](skill/SKILL.md) | 트리거 게이트(ultracode 체크) + 스폰 경로 분리 규칙 + 실측 함정 |
| [install-interview.md](skill/references/install-interview.md) | 설치 인터뷰 (placeholder 치환 + 크루 opt-in) |
| [brain-availability.md](skill/references/brain-availability.md) | 브레인 가용성 프로브 + 대체 추천표 |
| [feature-interview.md](skill/references/feature-interview.md) | 피처 접수 + 프로젝트 자산 서치 → 추천 설계 |
| [orchestration-playbook.md](skill/references/orchestration-playbook.md) | 6단계 파이프라인 + 스폰 규칙 + 프로브 |
| [monitoring-loop.md](skill/references/monitoring-loop.md) | 멈춤 감지 + 진로이탈 교정 + 상태 원장 |
| [context-management.md](skill/references/context-management.md) | 상태 외재화(디스크 SSOT) + 라운드 무결성 + 세션 복원 |
| [crew-support.md](skill/references/crew/crew-support.md) | 크루 공통 계약 + 카탈로그 + 신규 크루 추가 절차 |
| [update.md](skill/references/update.md) | 로컬 패치 업데이트 — 답변 보존 재치환 + 재검증 |
| [integrations.md](skill/references/integrations.md) | baton·cairn 연동 — 프로파일 게이팅(off/on/required) + 생명주기 훅 + tmuxc 경계 |
| [docs/](docs/) | 설계 이력 (design-ctx-management, design-round-integrity) |

## 실측 검증 (2026-07-02, E2E)

mul 음수 버그 수정 사이클: planner(fable5 max) 설계 파일 → implementer(opus4.6) 2줄 패치 → tester ALL_PASS(8케이스) → DA(codex gpt-5.5/xhigh) APPROVED — 오케스트레이터 개입 없이 파일 릴레이만으로 완주. 컨텍스트 관리 설계는 DA(codex) 3라운드 + critic(opus) 5라운드 + planner(fable) 교차 게이트 전건 APPROVED.
