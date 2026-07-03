---
name: fable-team
description: 일반화된 팀 오케스트레이션 하네스. "FT 구성", "FT 해보자", "FT 하자" 요청 시 사용 (보조 트리거: "fable-team", "팀 구성", "팀 에이전트 설치", "팀으로 진행" / 로컬 패치는 "FT 업데이트"). 오케스트레이터(opus-4-8 ultracode)는 전달·조율만 — 기획·구현 직접 수행은 orchestration-gate 훅이 물리 차단(선언 아닌 강제). 기획·문제해결은 planner 브레인(opus-4-8 또는 fable5 — FT 구성 시 선택·기록)이 전담. 설치 인터뷰 + 피처 설계 인터뷰로 프로젝트별 워커를 커스텀 생성한다. 트리거 시 부팅 시퀀스(피처 입력→추천 설계→프리뷰→컨펌)가 강제된다.
---

# fable-team — 일반화된 팀 오케스트레이션 하네스

## 역할 분리 (핵심 설계)

| 층 | 담당 | 모델 | 하는 일 | 안 하는 일 |
|----|------|------|---------|-----------|
| **오케스트레이터** | 현재 세션 | **opus-4-8** (ultracode) — fable 아님 | 태스크 분해, 워커 스폰/전달, 커뮤니케이션, 파이프라인 진행, 게이트 판단 릴레이 | **기획·문제해결·구현 금지** — 두뇌 작업을 직접 하지 않아 멈추지 않는 루프 가능 + **orchestration-gate 훅이 코드 3파일째부터 물리 차단**(§강제 게이트) |
| **planner (기획 브레인)** | 서브에이전트 | **opus-4-8 또는 fable5** (FT 구성 시 선택·기록 — §부팅) + effort **high**(D1, max 금지) (미가용 시 사다리: 병렬 opus-4-6 high·sonnet-5 high — D2) | 원인 분석, 해결 설계 — 컨텍스트를 파일/텍스트로 받아 **설계 파일로 반환** | 구현/실행/오케스트레이션 |
| **워커 4종** | 서브에이전트 | checker/implementer/tester/da | 확인, 구현, 테스트, DA 판정 | 기획, 서브 스폰 |

## 트리거 시 체크 게이트 (허들)

스킬 발동 즉시 확인하고, 미충족이면 진행 전 사용자에게 보고한다:

1. **프로파일 체크(D3)**: 현재 세션이 ⓐ Agent/Workflow **양면 지원**(도구 존재 — Workflow는 스킬 지시 호출로 opt-in 충족) ⓑ 사다리 **첫 가용 모델** ⓒ 그 모델의 **최대 유효 effort**(D1 상한 = high)인가? ⓒ만 미달이고 세션 내 조정 가능하면(`/effort high`) 조정 안내 후 진행. ⓑ 미충족(하위 모델 세션)이면 특정 모드 고정 안내(`/effort ultracode` 등) 금지 — **사다리의 다음 프로파일을 충족하는 세션에서 재트리거**하도록 안내 후 중단. ⓐ 중 Workflow만 부재 시 planner/tester 스폰을 미들웨어 드라이버 서브에이전트 경유 `claude -p`(스폰 경로 표 3행)로 전환 선언 후 진행.
2. **세션 effort 상속 함정**: 세션이 xhigh(ultracode)면 claude-5 계열(sonnet-5, fable-5) 워커는 Agent 팀 하네스에서 effort 상속으로 400 에러 즉사 — **스폰 경로 분리 규칙**(아래) 준수. claude-5 유효 effort는 low/medium/high/max(**xhigh 없음**) — 즉사 발생 시 교정: 해당 워커 pane에 `/effort high` 주입 또는 Workflow 경로로 `effort: high` 명시 재스폰. **claude-5 워커 표준 effort = high — planner 포함(기본 high)**. **planner effort = high(D1 표준 — max 퇴출: fable5/max hang 2세션 실측)**. 기존 설계의 보강·조임 회전은 high(수 분 내), 문구 수준 수정은 오케스트레이터 직접(기획 불요 기계적 — 게이트 처방이 명시된 경우). **비차단 규범**: planner/DA 회전은 백그라운드가 원칙 — 회전 대기로 사용자 개발을 정지시키지 않는다(파일이 증거, 릴레이 도착 시 처리·중간엔 다른 요청 계속).
3. 에이전트 정의 존재: 대상 위치에 `<prefix>-planner/checker/implementer/tester/da`가 설치돼 있는가? 없으면 설치 인터뷰(`references/install-interview.md`)부터.
4. **연동 프로브**: install.json `integrations`가 on/required면 가용성 프로브 — required 실패 시 보고 후 대기(headless는 override 정책 — `references/integrations.md` §0), on 실패 시 degrade 기록 후 속행. **프로브 출력(baton status stdout)은 보관해 부팅 시퀀스 1의 discovery가 재사용** — 같은 명령을 다시 실행하지 않는다.

## 부팅 시퀀스 (트리거 시 강제 — 생략 금지)

허들 통과 후, 파이프라인을 임의로 시작하지 않는다. 아래 순서를 **생략 없이** 수행한다:

1. **복원 체크 (integration-aware)**: 현 위치 기준 `.fable-team/state/ACTIVE` 존재 → context-management §4 복원이 부팅을 대체. **없고 integrations가 on/required이며 현 위치가 main 워크트리 내부(판정: integrations.md §공통)면 discovery** — `baton status`(1순위) + `<MAIN_ROOT>/.worktrees/*/.fable-team/state/ACTIVE` glob(보조)으로 활성 FT 워크트리 탐색 → 발견 시 해당 워크트리 **절대경로 운용**으로 §4 복원(cd 금지, 다수면 사용자 선택). 둘 다 없으면 2로.
2. **피처 입력 인터뷰 (무조건 AskUserQuestion)**: 선택지 구성 — 기존 대화 컨텍스트에서 태스크 후보를 추출할 수 있으면 **①②로 추천 제시**(각 한 줄 요약, 추천이 1개면 ①만), **③ 내용 추가**(직접 입력 — 한 줄 메시지 또는 파일 경로), **④ 채팅에서 이어하기**(인터뷰를 닫고 대화로 피처를 구체화한 뒤 한 줄 재확인). 후보가 없으면 ③④만 제시. **어떤 경로든 사용자 응답 없이 파이프라인 시작 금지.**
3. **추천 설계**: 입력 기반으로 feature-interview §2~3 수행 — 프로젝트 자산 서치 → 추천안 제시.
4. **실행 준비 프리뷰 (부팅 보드)**: 확정 전 한 화면으로 보여준다 — ① 피처 한 줄 ② 파이프라인 형상(표준/축약 + DA 강도) ③ 투입 로스터(워커 + 크루, 각 브레인) — **planner 브레인 선택 필수(opus-4-8 vs fable5 — AskUserQuestion, 선택은 install.json `PLANNER_MODEL` + state.md 기록. 메인 오케는 항상 opus-4-8)** ④ 산출물 경로(`.fable-team/features/<slug>.md`, `state/`) ⑤ 예상 라운드 한도 + **orchestration-gate 설치 상태(`templates/install-gate.sh --check` — 미설치면 설치 제안)** ⑥ (integrations on/required 시) 작업 공간: 워크트리 경로·브랜치(wt-create 예정) + cairn 노드(spawn parent 후보 — `cairn status` 요약에서 제시 — 또는 add-task 폴백).
5. **컨펌 게이트**: 사용자가 승인해야 킥오프(`state/ACTIVE` + state.md 생성 → stage 0). 조정 요청 시 해당 항목만 수정 후 재확인 1회. **컨펌 없이 워커를 스폰하지 않는다.** 킥오프 확장 훅(워크트리·원장 등록)은 `references/integrations.md` §1의 **순서**를 따른다.

## 스폰 경로 분리 규칙 (실측 — 2026-07-02)

| 워커 | 경로 | 이유 |
|------|------|------|
| planner (fable5 high), tester (sonnet5 high) 등 **claude-5 계열** | **Workflow `agent()`** + `model`/`effort` 명시 | Agent 팀 하네스는 frontmatter `effort:`를 무시하고 세션 effort(xhigh)를 상속시켜 claude-5 계열이 `400 level "xhigh" not supported`로 죽는다. Workflow의 effort 오버라이드는 실증 통과 (sonnet5+high ALL_PASS). effort 명시는 모든 세션에서 필수 — 세션 상한 초과 지정은 400 즉사, 미명시는 무증상 effort 다운그레이드(Agent 상속 = 세션 effort). |
| checker/implementer/da 등 **4.6 계열** | **Agent 도구** (팀 하네스) | xhigh 상속에도 정상 동작 실증. 이름 부여 스폰 → 완료 후 열린 상태 대기 → SendMessage 후속 질의/approve loop 재라운드 가능. |
| 외부 CLI 하네스 실행 전부 — 장시간 두뇌 작업(claude -p planner), DA(codex exec), 플러그인 크루(claude -p), omo(omx exec) | **미들웨어 드라이버 서브에이전트** (Agent 도구 — **세션 우측 pane 가시**, sonnet4.6 low, 이름 부여. 팀스 별창 아님) — 드라이버가 Bash로 외부 CLI를 `< /dev/null` 실행하고 결과를 SendMessage로 릴레이 | **오케스트레이터가 외부 CLI를 직접 실행하는 것 금지**(직접 `claude -p`/`codex exec`/`omx exec` 발사 금지). 이유: ① 서브에이전트는 세션 우측 pane에 네이티브 가시(별도 tmux 테일러 불요) ② SendMessage는 즉시 전송·유실 위험 낮음(Claude Code 프로토콜 최적화) ③ 자식 CLI는 별도 OS 프로세스라 개입 내성 유지 — 드라이버가 죽어도 계약=프롬프트 파일·결과=출력 파일 낙수로 재회수 가능. 드라이버는 자식을 **detach 발사(nohup/setsid — 드라이버 사망에도 자식 생존)** 후 PID+출력 파일 폴링으로 감시(포그라운드 실행 금지 — 드라이버 동반 사망 시 자식까지 죽는 실사고 2026-07-03). "화면 없는 백그라운드 금지"는 **오케스트레이터의 무가시 직접 발사**에 한한다 — 드라이버 경유 detach는 pane 가시가 이미 확보돼 정당. |

planner는 어차피 **무상태 계약**(컨텍스트 입력 → 설계 파일 출력)이라 Workflow 일회성 호출이 자연스럽다. 대기가 필요한 워커(approve loop 등)만 Agent 경로를 쓴다.

**★ opus-4-8[1m] / 최상위 오케스트레이터 세션의 서브에이전트 모델 leak (실측 2026-07-03 — 필독)**: 세션 모델이 `[1m]` suffix(예: `claude-opus-4-8[1m]`)면 **Agent 도구 스폰 시 워커가 frontmatter 모델을 무시하고 세션 모델(opus-4-8)을 상속**해 전 워커가 opus4.8로 뜨는 사고가 난다(서브에이전트는 `[1m]`을 상속 못 하고, tier alias는 resolver env 부재 시 denied). 교정 2가지 — **택1 이상 필수**:
1. **resolver env 설정** (권장): 프로젝트 `.claude/settings.json`의 `env`에 `ANTHROPIC_DEFAULT_OPUS_MODEL`/`ANTHROPIC_DEFAULT_SONNET_MODEL`/`ANTHROPIC_DEFAULT_HAIKU_MODEL`를 실제 provider ID로 지정 → tier alias(`opus`/`sonnet`/`haiku`)가 해석돼 Agent 경로 정상.
2. **[1m]/top 세션은 전 일회성 브레인 워커 Workflow 경로 강제** — Agent 대신 `agent()` + `model`/`effort` 명시. Workflow는 세션 모델을 상속하지 않고 명시 모델을 고정하므로 leak 없음(fableless 검증서 probe-planner/tester Workflow=정상, Agent 경로 leak 실측). 4.6 일회성 브레인도 [1m] 세션에선 Agent 대신 Workflow 우선. **장수명 드라이버는 Agent 유지**(셔틀 — 외부 CLI가 wrapper 주입 full-id로 실행, leak 무관).

즉 위 표의 "4.6 계열 = Agent 도구"는 **비-[1m] 세션 한정**. [1m]/opus 오케 세션에선 스폰 전 워커 실제 모델을 `agent-*.meta.json`으로 검증(함정 절). **스폰 후 `agent-*.meta.json`의 `model`이 지정 브레인과 불일치하면 = hard stop** — 즉시 해당 워커 중단·재스폰(leak 미교정 진행 금지). resolver env는 `install-gate.sh --install --with-resolver-env`로 settings.json `env`에 주입한다.

### ★ 스폰 경로 결정표 (ultracode/[1m] 세션 — 하드 실측 확정 2026-07-03)

opus-4-8[1m] ultracode 세션에서 jsonl `message.model` 하드 검증: **Workflow=스펙 정확 준수**(implementer=opus-4-6/medium·tester=sonnet-5·checker=sonnet-4-6 전부 일치), **Agent-tool teammate=opus-4-8/xhigh leak**(model·effort 둘 다). 따라서:

| 워커 유형 | 스폰 경로 | 모델/effort 제어 |
|-----------|-----------|------------------|
| **일회성 브레인** (planner·checker·implementer·tester) | **Workflow `agent()`** + `agentType` + `effort` 명시 | ✅ 스펙 정확 준수(실증). ultracode/[1m]에서 **Agent-tool 금지**(leak) |
| **장수명 드라이버** (codex DA·omx/omo·cursor·claude 플러그인 크루) | **Agent-tool teammate** (sonnet-4-6 low, 우측 pane 가시) — Bash로 외부 CLI를 `< /dev/null` detach 실행 + SendMessage 릴레이 | 드라이버는 **셔틀**(외부 CLI가 실제 브레인). approve loop·SendMessage 대기 때문에 Workflow(일회성) 불가 → Agent 필수. [1m]에서 드라이버 모델 leak은 **무관**(드라이버=셔틀, 외부 CLI가 wrapper의 주입된 full-id/effort로 실행 → 실제 브레인 모델에 영향 없음). mismatch hard-stop은 **일회성 브레인(Workflow 강제)에 적용**, 드라이버에는 해당 없음. 스트림: codex `--json`+`--output-last-message`로 이벤트 파싱·중간보고(ft-update-backlog #1) |
| **DA 브레인** | codex gpt-5.5 **high/xhigh** (드라이버의 Bash `-c model_reasoning_effort`) | 세션 무관(외부 CLI). 드라이버=sonnet-4-6 low |
| **planner 대체** (fable 부재 시) | **codex gpt-5.5 xhigh** (드라이버 경유) 또는 opus-4-8 (Workflow) | fable 미가용·rate limit 시 대안 |

**★ full model ID 강제 (bare tier 금지 — 실측 leak 원인)**: 스폰 호출·state 원장·보고에 모델을 적을 땐 **항상 정확한 full ID**로 — `claude-opus-4-6`·`claude-opus-4-8`·`claude-sonnet-5`·`claude-sonnet-4-6`. **bare tier `"opus"`/`"sonnet"` 절대 금지** — `opus`는 세션 기본(opus-4-8)으로 해석돼 leak(실측: `model:"opus"` 스폰 → 4.8/xhigh). 원장에 "opus/high"처럼 쓰면 4.6인지 4.8인지 모호 → 반드시 "opus-4-6"으로. Workflow는 `agentType`(frontmatter 정확 ID) 사용이 안전(model 파라미터로 tier 넘기지 말 것).

**준수 게이트(필수)**: **일회성 브레인(Workflow 경로)** 스폰 후 실제 모델을 검증한다 — workflow 디렉토리 `agent-*.jsonl`의 `message.model`. **지정 스펙과 불일치 = hard stop**(해당 워커 중단 → 올바른 경로로 재스폰, leak 미교정 진행 금지). **장수명 드라이버는 제외**(셔틀 — 외부 CLI가 wrapper 주입 full-id로 실행, 드라이버 자체 모델 leak은 무관). "더 강력하니 괜찮다"는 금지 — 로스터의 존재 이유(비용·동작 제어)를 부정. fable-5는 서버 rate limit이 타이트(실측 2회 실패) → 실패 시 opus-4-8 planner 또는 codex 5.5 xhigh 대체.

## 표준 로스터 (references/agent-templates/ 와 1:1)

| 워커 | 브레인 기본값 | effort | 도구 | 전담 |
|------|--------------|--------|------|------|
| ft-planner | **opus-4-8 또는 fable5** (FT 구성 시 선택·기록 — §부팅) | **high** (max 금지) | Read, Grep, Glob, Write | 원인 분석·해결 설계 → 설계 파일 |
| ft-checker | sonnet 4.6 | **high** | Read, Grep, Glob | 대량 서치·로그·문서·아키텍처 확인 (병렬 다수, 단말성) |
| ft-implementer | opus 4.6 | **medium** (heavy=high) | +Bash, Edit, Write, Skill | 설계 파일 기반 구현. 프로젝트 스킬 호출 가능 |
| ft-tester | sonnet 5 | high | +Bash | 테스트 설계·실행·repro |
| ft-da | codex gpt-5.5 xhigh (드라이버: sonnet 4.6 low) | xhigh | +Bash | DA review + DA approve loop |

> **메인 오케스트레이터(세션) = opus-4-8 ultracode** — 워커 아님(로스터에 없음). 기획·구현을 직접 하지 않고 위임하며, **orchestration-gate 훅**(§강제 게이트)이 코드 3파일째부터 물리 차단한다.

공통 불변: `tools:`에 Agent/Task 없음(서브의 서브 차단), 워커 모델에 fable-5/opus-4-8 금지(최상위 브레인 좌석 planner만 예외 — 사다리 모델 fable-5/opus-4-8), 보고는 최소 토큰 형식 강제.

**크루 (opt-in 확장 로스터)**: 로컬 하네스 전문 드라이버 워커 — ft-da(codex)가 원형이며, 같은 패턴으로 **하네스 이름 그대로** 추가한다. A형(외부 CLI): `omo`(OMX/OMO). B형(claude 플러그인): `gstack`·`superpowers`·`insane-search`·`ouroboros` — **드라이버 서브에이전트(sonnet4.6 low, 우측 pane 가시)가 Bash로 `claude -p`(자식 실행 모델 sonnet4.6 high)를 실행·릴레이**(스폰 경로 표 3행 — 오케스트레이터 직접 실행 금지). 템플릿은 `ft-<crew>.md.tpl` 1:1. **세션 승계(resume/inject 체인)와 컨텍스트 윈도우 관리(요약-후-fork + WINDOW_PRESSURE)는 크루의 기본 제공 계약**(brain_sessions 4번째 버킷 규칙 동일 적용). 감지·설치는 install-interview §4, 공통 계약·카탈로그는 `references/crew/crew-support.md`, 하네스별 상세는 `references/crew/<하네스>-full-context.md`.

## 사용 절차

0. **브레인 가용성 체크** (설치 시작 전 필수): `references/brain-availability.md` — codex/cursor 등 미가용 시 대응 모델 추천으로 대체
1. **설치 인터뷰** (최초/변경 시): `references/install-interview.md`
2. **피처 인터뷰** (매 피처 시작 시): `references/feature-interview.md` — 무엇을 할지 한 줄/파일로 받고, 프로젝트의 스킬·플러그인·하네스·도구를 서치해 추천 기반 설계 인터뷰 진행
3. **오케스트레이션** (파이프라인 실행): `references/orchestration-playbook.md`
4. **모니터링·지원 체크 루프** (파이프라인 상시): `references/monitoring-loop.md` — 멈춤 감지 + 진로이탈 교정 + 상태 원장
5. **컨텍스트 관리** (상태 외재화·compact/clear/재시작·복원): `references/context-management.md` — 디스크 SSOT(`.fable-team/state/`) write-through, ctx 임계 정책, 세션 재시작 복원 절차. **새 세션 트리거 시 피처 인터뷰 이전에 §4(ACTIVE 감지·복원)를 먼저 수행.**
6. **업데이트** ("FT 업데이트" 시): `references/update.md` — 팩 소스 → 로컬 설치본 패치(스킬 파일 + 에이전트 .md 재치환, 인터뷰 답변 보존) + 새 세션 프로브 재검증.
7. **강제 게이트** (오케 폭주·컨텍스트 방어): `references/orchestration-gate.md` — 4-레이어(선언·역할·기준·강제) + 프로젝트 설치 지원(`templates/install-gate.sh`). 부팅 시퀀스에서 설치 상태 확인·제안.

## 강제 게이트 (orchestration-gate) — 선언 아닌 물리 차단

CLAUDE.md·SKILL.md에 "오케는 위임한다"고 적는 건 **권고**라 모델이 우회 가능. **PreToolUse 훅으로 물리 차단**해야 실제로 막힌다(출처: joel__w__w 스레드). fable-team은 4-레이어를 **한 세트로** 유지·배포한다:

| 레이어 | 파일 | 역할 |
|--------|------|------|
| 선언 | `templates/CLAUDE.orchestration.snippet.md` → 프로젝트 CLAUDE.md | declaration |
| 역할 | `references/agent-templates/` (로스터) | role assignment |
| 기준 | `templates/rules/orchestration.md` → `.claude/rules/` | operating criteria |
| 강제 | `templates/hooks/orchestration-gate.sh`·`orchestration-turn-reset.sh`·`context-distill-gate.sh` → `.claude/hooks/` + settings.json | enforcement |

- **오케 편집 게이트**: 최상위 모델 오케(fable/opus-4-8)가 한 턴에 **코드 파일 2개까지**, 3개째 Edit/Write/Bash(sed·echo>·tee) **하드 deny**+위임 메시지. 워커(opus-4-6/sonnet)는 무제한(모델 판별=transcript 마지막 assistant model). **fail-open**(오류 시 허용 — 세션 brick 금지).
- **컨텍스트 증류 게이트**: 300k warn 주입 / 450k 신규 스폰 하드 deny.
- **설치**: `templates/install-gate.sh --check|--install [proj]` — 상태 진단 + 멱등 설치(settings 병합·백업). **패치마다 4-레이어 세트로 함께 갱신**(update.md).

## 함정 (실측)

- **Agent 팀 하네스는 frontmatter `effort:` 무시** → 세션 effort 상속. ultracode(xhigh) 세션에서 claude-5 계열 워커 즉사. Workflow 경로로 우회 — claude-5엔 effort **high** 명시(xhigh 전달 금지, 전 좌석 high — D1).
- **opus-4-8[1m]/top 세션 서브에이전트 모델 leak** — Agent 도구 스폰 시 워커가 세션 모델(opus4.8)을 상속(frontmatter 무시). 교정: resolver env(`ANTHROPIC_DEFAULT_*_MODEL`) 설정 or [1m] 세션은 **일회성 브레인 워커**(planner/checker/implementer/tester)만 Workflow 경로 강제(**장수명 드라이버는 Agent+wrapper 유지** — 결정표 §57-58). 일회성 브레인은 스폰 후 `agent-*.meta.json` model 검증(불일치=hard stop), 드라이버는 셔틀이라 제외.
- **에이전트 .md 수정은 이미 등록된 타입에 소급 반영 안 됨** — 같은 이름 재사용 시 구정의(모델·도구)가 캐시로 살아있을 수 있다. 정의 변경 시 새 파일명으로 만들거나 새 세션에서 사용.
- codex 호출: `npx -y @openai/codex exec ... < /dev/null` (alias 미해석 + stdin hang 방지), `-c model_reasoning_effort="xhigh"` 지원 확인됨, 적용 여부는 세션 헤더 `reasoning effort:` 라인으로 검증.
- 워커 실제 모델 검증: `~/.claude/projects/<proj>/<session>/subagents/agent-*.meta.json`의 `model` + `agent-*.jsonl`의 `message.model`.
- 워커 감시: Monitor로 `agent-*.jsonl`에 `API Error` 문자열 포함 폴링 (조용한 실패 방지).
- **원장이 컨텍스트에만 있으면 자동 컴팩션/재시작/증류로 증발** → 라운드 한도 붕괴·완료 단계 재실행·미승인 종결 위험. 진행 상태는 반드시 디스크 SSOT(`.fable-team/state/`)에 write-through (`references/context-management.md`).
- **세션 내 백그라운드 워커는 사용자 개입에 동반 사망** — ESC/메시지마다 `[Request interrupted by user]`, 자동 재시도도 재개입 시 재사망(실측). **가시성 규범**: 모든 워커는 **세션 우측 pane에 보여야 한다**(서브에이전트 — Agent 도구. 팀스 별창 방식 아님) — 외부 CLI 실행도 미들웨어 드라이버 서브에이전트 경유(스폰 경로 표 3행)라 우측 pane 가시가 보편 경로다. 보이지 않는 백그라운드는 돌지 않는 것으로 간주하고 금지. PID·파일 실측은 드라이버의 자식 감시 수단이지 **사람 가시성의 대체가 아니다**(tmux 테일러는 선택 보조일 뿐 의무 아님).
