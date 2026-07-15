# fable-team 오케스트레이션 플레이북

오케스트레이터(사다리 최상위 가용 모델 — brain-availability §2)가 매 태스크에서 따르는 절차. **오케스트레이터는 전달·조율·커뮤니케이션만 한다** — 기획·문제해결은 architect 브레인에 위임하고, 그 사이에도 파이프라인은 멈추지 않는다.

**빅뱅 금지 — 1이슈·원인 먼저 (문제해결 7원칙 §1, rapid-iteration-loop)**: 오케는 **한 번에 한 이슈만** 이 파이프라인에 태운다(stage 1 checker 병렬은 한 이슈 안의 수집 팬아웃이라 예외). 원인 판별을 먼저 닫고 그 다음에만 fix 설계로. **커밋 랜딩 크기는 오케 책임** — 설계가 단일 계약이어도 Tidy First로 구조 선커밋→행위 후커밋 분할한다(rapid-iteration-loop §1).

**오케는 체인을 굴린다 — 직접 분석·대기 금지 (안티패턴 9·10)**: 로그·계측 데이터 분석은 워커(checker/analyst) 위임 후 결론만 수신(오케 직접 grep·분석 금지). 규명이 확인되면 **즉시** 다음 단계(architect→DA→impl)를 발주 — wakeup 폴링은 워커 완료 감지용이지 오케 행동 지연용이 아니다. **확인과 수정은 병렬**: 라이브 검증이 도는 동안 규명완료분은 즉시 설계·구현 착수.

**다이렉트 확인 루프 (선택지)**: "관찰이 곧 판정"인 건은 이 파이프라인 전에 즉결 확인 루프로 원인 규명을 가속할 수 있다 — 발동조건·권한경계·실증팩 계약은 rapid-iteration-loop §다이렉트 확인 루프. fix는 1줄이라도 설계+DA 경유(변함없음).

**2계층 확장 (대규모/장기 트랙 옵션)**: 워커 전원이 메인오케 직보로 릴레이 허브화되면 — 메인오케(사용자 대리·태스크풀·스톨감시·HIL 전담) / 수행오케(이 플레이북의 오케 역할 그대로, 5워커 직접 지휘)로 분리. **전환 시 워커 전원에 "보고는 수행오케 직접" 명시 재공지 필수**(생략 시 병목 재발 — SKILL.md §2계층 확장).

## 파이프라인

```
0. 킥오프   오케스트레이터: 피처 인터뷰 결과(.fable-team/features/<slug>.md) 확인
            + state/ACTIVE·state/<slug>.state.md 생성 (형상 포함 — context-management §1)
            (+연동 훅: wt-create·cairn spawn — integrations.md §1 순서 준수)
1. 수집     ft-checker × N 병렬 (스폰경로: §스폰 규칙 — [1m] Workflow / 비-[1m] Agent, checker-01…) — 대상 파일 + JSON 보고 형식만 전달
2. 기획     ft-architect (Workflow agent(), model+effort 명시) — 워커 확인 결과를 인라인/파일로 전달
            ★ 체커부터 (7원칙 §4): architect에 넘기는 것은 **실제 실행로그+짧은 재현 데이터**여야 한다(정적 코드리딩만으로 설계 착수 금지).
              계측·재현·수집을 어느 워커로 돌릴지는 오케 자율 — 원인이 계측으로 좁혀지기 전엔 설계로 넘어가지 않는다(7원칙 §2·3).
            → architect가 설계 파일(features/design-<slug>-v<N>.md, 재기획마다 v+1) Write 후 DESIGN_WRITTEN 반환
            ★ 오케스트레이터는 설계 내용을 판단하지 않는다. 전달만.
3. 구현     ft-implementer (스폰경로: §스폰 규칙 — [1m] Workflow / 비-[1m] Agent) — 구현 SSOT 경로 전달 ("SSOT를 Read하고 그대로 구현")
            구현 SSOT: 표준 형상 = 설계 파일, 축약 형상(설계 단계 없음) = 피처 파일(features/<slug>.md)
4. 검증     병렬: ft-tester (Workflow, 설계의 검증 기준 전달) + ft-da review (Agent)
            ★ 완성=라이브 관찰 (7원칙 §7): tester는 유닛/회귀 GREEN이 아니라 **라이브 반응 관찰**을 종결 증거로 남긴다(운영규율 #3). 1회 판정 아님 — 짧은 반복으로 로그 대조(rapid-iteration-loop §7).
5. 게이트   ft-da approve loop.
            ★ 직접 approve loop (7원칙 §5): 설계↔반박 왕복은 architect·DA **둘이 직접 send로 수렴**(스폰 시 상대 세션명 주입), 오케는 중간 릴레이 없이 **최종 APPROVE만 1회** 수거 → 6으로. 설계 pre-gate(구현 전)·post-impl 게이트(이 stage) 어느 접점이든 동일. 라운드 한도·라이브증거·에스컬레이션은 기존 규율 그대로(monitoring-loop §5, 운영규율 #2) — 한도 도달 시 DA가 DA_LOOP_STALLED로 오케에 신호. *(Legacy 비-tmux 경로면 오케 pass-through 릴레이(판단 0)로 폴백.)*
6. 종결     오케스트레이터: tester ALL_PASS + DA APPROVED 증거 수집 → 정리 보고
            + state.md status: done 기록·state/ACTIVE 제거
            (+연동 훅: baton save/finish·cairn complete·PR 권고 — integrations.md §2 순서 준수)
```

피처 인터뷰에서 축약 형상(확인→구현→테스트, DA 생략 등)을 확정했으면 **해당 단계만 수행** — 형상은 `features/<slug>.md`와 state frontmatter(`pipeline`/`da`)에 기록되고, 세션 복원도 이 형상을 따른다(context-management §4). **check-only 형상 = 0(킥오프)→1(수집) 후 보고·종결** — 기획/구현/검증/게이트 단계 없음, 워크트리·연동 훅 전체 skip(integrations.md §1-0).

**`da: review`의 실행 의미**: stage 4 검증에서 DA review **1회 판정만** 수행하고 stage 5 게이트는 없다 — 판정은 `da-round1.md`로 기록해 종결 보고에 첨부하며, CHANGES_REQUESTED여도 **자동 재기획 재순환 없이** 사용자 판단으로 넘긴다(게이트·재순환은 `da: loop2` 전용).

멈추지 않는 루프의 원리: 오케스트레이터가 두뇌 작업을 안 하므로 각 단계는 "산출물 파일/JSON을 다음 워커에 릴레이"만이다. 판단이 필요한 지점은 전부 architect(설계)와 da(게이트)에 있고, 오케스트레이터는 게이트 결과에 따라 분기만 한다.

## 스폰 규칙

- **경로 선택 (SKILL.md 스폰경로 결정표가 단일 SSOT — 교정 2026-07-06)**: model leak은 [1m]·비-[1m] 모두 반증됨(`subagent_type`만 지정+model 생략 시 frontmatter full ID 적용) — **일회성 브레인도 Agent 도구 허용**. Workflow는 effort 명시 제어·schema·대량 fan-out이 필요할 때 선택. 단 **xhigh(ultracode) 세션에서 claude-5 계열 워커**(architect fable5, tester sonnet5)는 effort 상속 400 리스크 미재검증 — Workflow `effort` 명시 권장. 장수명 드라이버(DA·크루)는 세션 무관 Agent-tool(셔틀 — 외부 CLI가 주입된 full-id로 실행). bare tier `model:"opus"` 지정은 여전히 금지(model 생략이 정답).
- **DA 드라이버**: 스킬 설치 후 **새 세션**이면 Agent 도구(`<prefix>-da`, Bash 포함 정의가 시작 시 등록됨). 세션 중 정의를 만들었/고쳤다면 등록 캐시가 구정의라 Bash가 빠질 수 있음 → 새 세션에서 재시작하거나, Agent 도구를 새 이름으로 재등록해 우회 (DA=드라이버 Agent+codex wrapper — Workflow 아님, E2E 실증: gpt-5.5/xhigh APPROVED).
- **DA 브레인 resume 체인**: approve loop 라운드 2+는 새 one-shot 재인라인 대신 `codex exec resume <session-id>`로 재개(라운드 1 지적 기억 + 토큰 절약). 최초 실행에서 session-id를 판정과 함께 회수해 state.md `brain_sessions`에 기록 — 세션을 넘는 복원 자산(context-management §3).
- Agent 경로 워커는 `name: <role>-NN` 부여, 프롬프트에 "완료 후 대기하라" — 열린 상태로 두고 SendMessage로 후속 질의(approve loop 재라운드, 추가 확인).
- 독립 스폰은 한 메시지에 병렬로.
- 감시: Monitor로 `subagents/agent-a<name>-*.jsonl`에 완료 마커와 **`API Error` 문자열을 함께** 폴링 (조용한 실패 방지). Workflow는 task-notification으로 자동 통지.

## 컨텍스트 최소화 수칙

- 워커에 넘기는 것: 원문/요약 노트 인라인 또는 파일 경로 + 보고 형식. 그 외 금지.
- 단계 간 전달은 **파일 경유** (설계 파일, 피처 파일) — 오케스트레이터 컨텍스트에 본문을 싣지 않는다.
- 워커 보고: JSON 한 줄 / 판정 첫 줄 / `DESIGN_WRITTEN <경로>` 형식 강제.
- checker는 파일당 1워커 병렬 — 워커당 컨텍스트 최소화.

## 프로브 (설치 검증용 표준 질의)

각 워커에 1회:
```
JSON 한 줄로 반환 (키: tools, spawn_test):
1. tools: 호출 가능 도구 전체 배열
2. spawn_test: Agent/Task로 서브 스폰 시도 → "SPAWNED" | "NO_SPAWN_TOOL"
```
기대값: tools에 Agent/Task(스폰) 없음 + **SendMessage/TaskCreate/TaskGet/TaskUpdate/TaskList 5종 존재**, spawn_test=NO_SPAWN_TOOL, `agent-*.meta.json`의 model이 지정 모델과 일치. (실측 교정 2026-07-06: frontmatter `tools:` 명시 시 팀 도구는 **자동 부여되지 않는다** — 템플릿 tools 라인에 5종 명시 필수. 프로브에서 SendMessage 부재 = fan-in 사망 = 설치 불량.)

**프로브 경로 이원화 (필수)**: Agent 경로 워커(checker/implementer/da/크루)는 팀 하네스 프로브, **architect/tester는 Workflow `agent()`(model/effort 명시)로 프로브**. Agent 프로브만 돌리면 architect(기획 브레인)가 안 떠 설치 검증이 비어 보인다 — architect 프로브 부재 = 설치 미완.

## 워커 도구 능력 ↔ 작업 성격 매칭 (위임 함정)

- **ft-checker는 읽기 전용(`Read, Grep, Glob`) — Bash도 Write도 없다.** 대량 서치·로그·문서·아키텍처 "확인"만 담당한다.
- **실행성 일회성 작업(외부 스크립트/CLI 호출 + 결과 파일 저장)은 ft-checker에 위임하지 마라 — 도구 부재로 거부당한다(실측).** 예: Perplexity 서치(`perplexity_direct.py` 호출), 임시 스크립트 실행 후 산출물 저장, `git`/빌드/테스트 커맨드 등. 이런 작업은 **Bash+Write를 가진 ft-implementer**에 위임한다(로스터 표: ft-implementer = `+Bash, Edit, Write, Skill`). 검색·조사라도 "실행+저장"이 끼면 checker가 아니라 implementer(또는 해당 크루 드라이버)다.

## 실측 함정 (2026-07-02 검증분)

- Agent 팀 하네스: frontmatter `effort:` 미반영 → 세션 effort 상속. ultracode 세션 + claude-5 워커 = 400 즉사. → Workflow 경로.
- 에이전트 타입 정의는 스폰 시점 캐시 — .md 수정 후 같은 타입 재스폰해도 구정의일 수 있음. 새 이름 or 새 세션.
- Workflow `agent()`의 `agentType`은 세션 시작 시 등록된 타입만 인식 (세션 중 추가된 커스텀 타입 불가) → `model`/`effort` 직접 지정으로 대체.
- codex: `npx -y @openai/codex exec --skip-git-repo-check -c model_reasoning_effort="xhigh" "<프롬프트>" < /dev/null`. 헤더 `reasoning effort: xhigh`로 적용 확인. `--full-auto`는 구현 위임시에만. (이 줄은 effort 적용 실측 기록 — **드라이버 정본 레시피는 `agent-templates/ft-da.md.tpl`**: `CODEX_DUMMY_API_KEY` + `-C <대상디렉토리>` 포함, 복붙은 그쪽에서.)
- 워커 모델 실측: `agent-*.meta.json` `model` 필드 + transcript `message.model`.
