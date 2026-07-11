---
name: fable-team
description: 일반화된 팀 오케스트레이션 하네스. "FT 구성", "FT 해보자", "FT 하자" 요청 시 사용 (보조 트리거: "fable-team", "팀 구성", "팀 에이전트 설치", "팀으로 진행" / 로컬 패치는 "FT 업데이트"). 오케스트레이터(sonnet-5 또는 fable-5 ultracode — 세션 시작 시 사용자 선택)는 전달·조율만 — 기획·구현 직접 수행은 orchestration-gate 훅이 물리 차단(선언 아닌 강제). 기획·문제해결은 planner 브레인(fable5 1순위 — 미가용 시 sonnet-5 → 병렬 opus-4-6, FT 구성 시 기록)이 전담. 설치 인터뷰 + 피처 설계 인터뷰로 프로젝트별 워커를 커스텀 생성한다. 트리거 시 부팅 시퀀스(피처 입력→추천 설계→프리뷰→컨펌)가 강제된다.
---

# fable-team — 일반화된 팀 오케스트레이션 하네스

## 역할 분리 (핵심 설계)

| 층 | 담당 | 모델 | 하는 일 | 안 하는 일 |
|----|------|------|---------|-----------|
| **오케스트레이터** | 현재 세션 | **sonnet-5 또는 fable-5** (ultracode — 세션 시작 시 사용자 선택) | 태스크 분해, 워커 스폰/전달, 커뮤니케이션, 파이프라인 진행, 게이트 판단 릴레이 | **기획·문제해결·구현 금지** — 두뇌 작업을 직접 하지 않아 멈추지 않는 루프 가능 + **orchestration-gate 훅이 코드 3파일째부터 물리 차단**(§강제 게이트) |
| **planner (기획 브레인)** | 서브에이전트 | **fable5** (1순위) 또는 **codex-5.6-sol**(→ft-planner-x 드라이버) — 세션 시작 인터뷰에서 사용자 선택 + effort **high**(D1, max 금지) | 원인 분석, 해결 설계 — 컨텍스트를 파일/텍스트로 받아 **설계 파일로 반환** | 구현/실행/오케스트레이션 |
| **analyst (진단 전문)** | 서브에이전트 | **opus-4-6** high | 로그↔코드↔스펙 3자대조 진단 → DIAGNOSIS + ESCALATE_TO_PLANNER 보고 | 파일 수정, 구현, 서브 스폰 |
| **워커 5종** | 서브에이전트 | checker/implementer/tester/da/da2 | 확인, 구현, 테스트, DA 판정 | 기획, 서브 스폰 |
| **ft-pm-memory** (신설·상시) | tmux 세션(sonnet-4-6) | 흐름 기억·원장·cairn 대행·BRIEF 브리핑 (증류 면역 외부 기억) | 알림·근거 제시까지 (파이프라인 결정은 오케, 워커 직접 지시·파괴 결정 금지) |

## 트리거 시 체크 게이트 (허들)

스킬 발동 즉시 확인하고, 미충족이면 진행 전 사용자에게 보고한다:

1. **프로파일 체크(D3)**: 현재 세션이 ⓐ Agent/Workflow **양면 지원**(도구 존재 — Workflow는 스킬 지시 호출로 opt-in 충족) ⓑ 로스터 **첫 가용 모델** ⓒ 그 모델의 **최대 유효 effort**(D1 상한 = high)인가? ⓒ만 미달이고 세션 내 조정 가능하면(`/effort high`) 조정 안내 후 진행. ⓑ 미충족(하위 모델 세션)이면 특정 모드 고정 안내(`/effort ultracode` 등) 금지 — **로스터 요건을 충족하는 세션에서 재트리거**하도록 안내 후 중단. ⓐ 중 Workflow만 부재 시 planner/tester 스폰을 미들웨어 드라이버 서브에이전트 경유 `claude -p`(스폰 경로 표 3행)로 전환 선언 후 진행.
2. **세션 effort 상속 함정**: 세션이 xhigh(ultracode)면 claude-5 계열(sonnet-5, fable-5) 워커는 Agent 팀 하네스에서 effort 상속으로 400 에러 즉사 — **스폰 경로 분리 규칙**(아래) 준수. claude-5 유효 effort는 low/medium/high/max(**xhigh 없음**) — 즉사 발생 시 교정: 해당 워커 pane에 `/effort high` 주입 또는 Workflow 경로로 `effort: high` 명시 재스폰. **claude-5 워커 표준 effort = high — planner 포함(기본 high)**. **planner effort = high(D1 표준 — max 퇴출: fable5/max hang 2세션 실측)**. 기존 설계의 보강·조임 회전은 high(수 분 내), 문구 수준 수정은 오케스트레이터 직접(기획 불요 기계적 — 게이트 처방이 명시된 경우). **비차단 규범**: planner/DA 회전은 백그라운드가 원칙 — 회전 대기로 사용자 개발을 정지시키지 않는다(파일이 증거, 릴레이 도착 시 처리·중간엔 다른 요청 계속).
3. 에이전트 정의 존재: 대상 위치에 `<prefix>-planner/checker/implementer/tester/da`가 설치돼 있는가? 없으면 설치 인터뷰(`references/install-interview.md`)부터.
4. **연동 프로브**: install.json `integrations`가 on/required면 가용성 프로브 — required 실패 시 보고 후 대기(headless는 override 정책 — `references/integrations.md` §0), on 실패 시 degrade 기록 후 속행. **프로브 출력(baton status stdout)은 보관해 부팅 시퀀스 1의 discovery가 재사용** — 같은 명령을 다시 실행하지 않는다.

## 부팅 시퀀스 — 3스텝 인터뷰 (트리거 시 강제 — 생략 금지)

허들 통과 후, 파이프라인을 임의로 시작하지 않는다. 아래 순서를 **생략 없이** 수행한다:

**스텝 0 (질문 아님, 유지)**: `.fable-team/state/ACTIVE` 존재 → context-management §4 복원이 인터뷰 전체를 대체(브레인 선택 포함 — state.md의 `brains:` 라인 복원). **없고 integrations가 on/required이며 현 위치가 main 워크트리 내부면 discovery** — `baton status`(1순위) + `<MAIN_ROOT>/.worktrees/*/.fable-team/state/ACTIVE` glob(보조)으로 활성 FT 워크트리 탐색 → 발견 시 해당 워크트리 **절대경로 운용**으로 복원. **신규 세션만 스텝 1~3 진행.**

**스텝 1 — 브레인 선택 (세션 1회, AskUserQuestion 1개)**:
- 질문 대상은 `ask: true` 역할만 = **planner와 DA 레인**. 나머지(analyst/implementer/tester/checker)는 choices[0] 고정 — 언급만 하고 묻지 않는다.
- 선택지 형태 (조합 제시로 질문 1개 압축):
  - ① planner=fable-5, da=codex-5.6-sol, da2=grok-4.6 **[기본]**
  - ② planner=fable-5, da=grok-4.6, da2=codex-5.6-sol
  - ③ planner=codex-5.6-sol(→ft-planner-x), da=grok-4.6 고정, da2=claude-opus-4-6 — **author-review-split이 codex DA를 선택지에서 제거한 조합**
  - ④ 직접 조합 (자유 입력 — constraints 위반 시 재제시)
- 결과를 state.md `brains:` 라인에 write-through. **같은 세션에서 다시 묻지 않는다.**
- **미가용 발생 시 자동 대체 금지**: 브레인 실패(429·auth·CLI 부재)는 `BRAIN_UNAVAILABLE <role> <model> <사유>` 1줄 보고 → AskUserQuestion으로 남은 choices 재제시 → 사용자 선택 후 state.md 갱신.

**스텝 2 — 문제 입력 (AskUserQuestion 1개)**:
- 대화 컨텍스트에서 후보 추출 가능하면 ①② 추천(한 줄 요약), ③ 직접 입력(한 줄/파일 경로), ④ 채팅에서 구체화 후 재확인. **어떤 경로든 사용자 응답 없이 파이프라인 시작 금지.**

**스텝 3 — 배치 추천 → AskUserQuestion 킥오프 (1개)**:
- 오케가 `references/deployment-patterns.md` 카탈로그로 유형 분류 → AskUserQuestion 1개 발사. `question`에 압축 보드 인라인, `options`가 배치 선택지.
- **① = 오케 추천 배치, label에 `(Recommended)` 접미** — 엔터만 치면 ① 선택 = 즉시 킥오프.
- **어떤 옵션을 골라도 재확인 없이 즉시 킥오프** — 조정이 옵션에 내장. `직접 조합` 경로에서만 형상 1줄 재확인 1회 → 킥오프.
- 킥오프 = `state/ACTIVE` + state.md(brains·패턴·선택 형상) write-through → stage 0. 킥오프 확장 훅(워크트리·**PM 확보**·원장 등록)은 `references/integrations.md` §1의 **순서**를 따른다. **PM 확보**: 코드 변경 형상(standard/abbrev)이면 `ft-pm-<proj>#0` 존재 확인 후 부재 시 개설(check-only·P-DOC 미개설), 생존 시 재사용(KICKOFF만 송신) — 스텝3 보드에 `PM: ft-pm-<proj>#0 (상시)` 표기(§3-1). **컨펌 없이 워커를 스폰하지 않는다.**
- **같은 세션의 다음 피처는 스텝 2부터** (스텝 1 생략 — 세션 1회 원칙).

총 질문 수: 신규 세션 첫 피처 = 3개, 이후 피처 = 2개, 복원 세션 = 0개.

## v3 스폰 — tmuxc 세션 (기본 경로, spawn_backend=tmux)

v3 기본값은 **전 역할 tmuxc 세션**이다(비-tmuxc 경로 0 — 승인된 예외 3종 `grok_driver`/`checker_workflow`/`raw_launch_fallback` 제외). 워커는 오케 세션과 생명주기가 분리돼 **오케 증류·재시작에도 생존한다**(v3 핵심 이득). 스폰·통신·증류·정리는 `.fable-team/bin/ft-tmux-*.sh` 검증 래퍼가 tmuxc 명령을 감싸 수행한다 — 오케는 `tmuxc open|kill|clean|distill`을 Bash로 직접 발행하지 않는다(orchestration-gate가 deny, §강제 게이트·설계 §0-2 L3).

| 역할 | 브레인 | v3 스폰 (`ft-tmux-spawn.sh`) | 계약 프롬프트 |
|------|--------|------------------------------|--------------|
| ft-planner | fable-5/high | `--agent claude --role planner` | `.fable-team/prompts/planner.md` |
| ft-planner=codex | codex-5.6-sol | `--agent codex` (세션 직접 — **ft-planner-x 드라이버 폐지**) | `prompts/da-codex.md` 계열 |
| ft-analyst | opus-4-6/high | `--agent claude --role analyst` | `prompts/analyst.md` |
| ft-implementer | opus-4-8/high | `--agent claude --role implementer` | `prompts/implementer.md` |
| ft-tester/tester2 | sonnet-5/high | `--agent claude --role tester` | `prompts/tester.md` |
| ft-da (codex) | codex-5.6-sol | `--agent codex` (세션 직접, **라운드 2+ resume 불요**) | `prompts/da-codex.md` |
| ft-da2 (grok) | grok-4.6 | 드라이버 세션(예외 `grok_driver` — cursor-agent 비세션형) | `prompts/da-cursor.md` |
| ft-checker | sonnet-4-6/medium | `--agent claude --role checker` (단명 — done 후 kill) | `prompts/checker.md` |
| **ft-pm-memory** (신설) | sonnet-4-6/medium | `--name ft-pm-<proj>#0 --role pm` (상시 세션) | `prompts/pm.md` |

- **세션명 규약**: `ft-<slug>-<role>#0` (증류 시 `#N+1` — tmuxc UC10). PM은 `ft-pm-<proj basename>#0`(프로젝트당 1개, 피처 공유).
- **모델 라우팅**: `tmuxc open --name <sess> --agent claude|codex --role <role> --prompt <계약경로>`가 정본. 모델 full-ID·effort·`FT_WORKER_ROLE` env 주입 가능 여부는 install.json `tmuxc_caps`가 판정 — 갭 시 승인된 `raw_launch_fallback`(headroom 기동 합성) 또는 스폰 스크립트 `exit 4 CAPABILITY_GAP` HIL 상신.
- **역할 계약 전달**: `~/.claude/agents/ft-*.md`는 tmux 세션에 미적용 → 본문을 세션 계약 프롬프트 `.fable-team/prompts/<role>.md`로 이관(Phase 3 산출). 스폰 후 `[orch→<sess>] 계약: <path> Read 후 시작. 입력: <경로들>` 1줄 send.
- **설치 배선**: 세션 계약 프롬프트 원본은 `skill/templates/session-prompts/*.md`(8종) — 설치·업데이트 시 `agent-templates`와 **동일 `{{...}}` 키로 치환**해 `.fable-team/prompts/<role>.md`로 복사한다(신규 인터뷰 질문 불요). 절차는 `references/install-interview.md` §5-3-2, 재치환은 `references/update.md`. 잔여 `{{`는 설치 실패로 간주.
- **보고·통신**: 산출물은 워커가 직접 Write, 완료는 파일 센티널(`<sess>.done` 원자 tmp+mv), 오케 수신은 `ft-tmux-poll.sh` 1줄 호출(`DONE <path>`/`MSG`/`NEEDS_INPUT`/`RUNNING`/`HANG`). 역send는 비보장 가속. 상세 = 설계 §1-4·§1-6.
- **가시성**: 워커는 독립 tmux 세션이다 — 우측 pane 상주가 아니라 **필요 시 사용자가 `tmux attach`로 관찰**한다(사용자 승인 2026-07-11). 오케의 HIL 집중 게이트(§1-6 hil 센티널)가 사용자 접점을 단일화하므로 상시 attach는 불요.
- **롤백 진입점**: `install.json spawn_backend.default: "agent-v2"`면 `ft-tmux-spawn.sh`가 `exit 6 USE_AGENT_V2`를 반환 → 오케가 아래 **Legacy spawn 부록** 절차(Agent 도구 스폰 + checker=Workflow)로 전환한다.

## 부록: Legacy spawn (spawn_backend=agent-v2 — 롤백 경로, 2026-07-02 실측)

> v3 기본은 위 tmuxc 세션 경로다. 아래는 `spawn_backend.default: "agent-v2"` 롤백 시 오케가 따르는 Agent/Workflow 디스패처 **문서 절차**(실행 파일 아님) — `ft-tmux-spawn.sh`가 `exit 6 USE_AGENT_V2`를 반환하면 이 절차로 전환한다. **v2 에이전트 `.md`·템플릿과 함께 삭제 금지**(agent-v2 롤백의 실체).

| 워커 | 경로 | 이유 |
|------|------|------|
| planner (fable5 high), tester (sonnet5 high) 등 **claude-5 계열** | **Workflow `agent()`** + `model`/`effort` 명시 | Agent 팀 하네스는 frontmatter `effort:`를 무시하고 세션 effort(xhigh)를 상속시켜 claude-5 계열이 `400 level "xhigh" not supported`로 죽는다. Workflow의 effort 오버라이드는 실증 통과 (sonnet5+high ALL_PASS). effort 명시는 모든 세션에서 필수 — 세션 상한 초과 지정은 400 즉사, 미명시는 무증상 effort 다운그레이드(Agent 상속 = 세션 effort). |
| checker/implementer/da 등 **4.6 계열** | **Agent 도구** (팀 하네스) | xhigh 상속에도 정상 동작 실증. 이름 부여 스폰 → 완료 후 열린 상태 대기 → SendMessage 후속 질의/approve loop 재라운드 가능. |
| 외부 CLI 하네스 실행 전부 — 장시간 두뇌 작업(claude -p planner), DA(codex exec), 플러그인 크루(claude -p), omo(omx exec) | **미들웨어 드라이버 서브에이전트** (Agent 도구 — **세션 우측 pane 가시**, sonnet4.6 low, 이름 부여. 팀스 별창 아님) — 드라이버가 Bash로 외부 CLI를 `< /dev/null` 실행하고 결과를 SendMessage로 릴레이 | **오케스트레이터가 외부 CLI를 직접 실행하는 것 금지**(직접 `claude -p`/`codex exec`/`omx exec` 발사 금지). 이유: ① 서브에이전트는 세션 우측 pane에 네이티브 가시(별도 tmux 테일러 불요) ② SendMessage는 즉시 전송·유실 위험 낮음(Claude Code 프로토콜 최적화) ③ 자식 CLI는 별도 OS 프로세스라 개입 내성 유지 — 드라이버가 죽어도 계약=프롬프트 파일·결과=출력 파일 낙수로 재회수 가능. 드라이버는 자식을 **detach 발사(nohup/setsid — 드라이버 사망에도 자식 생존)** 후 PID+출력 파일 폴링으로 감시(포그라운드 실행 금지 — 드라이버 동반 사망 시 자식까지 죽는 실사고 2026-07-03). "화면 없는 백그라운드 금지"는 **오케스트레이터의 무가시 직접 발사**에 한한다 — 드라이버 경유 detach는 pane 가시가 이미 확보돼 정당. |

planner는 어차피 **무상태 계약**(컨텍스트 입력 → 설계 파일 출력)이라 Workflow 일회성 호출이 자연스럽다. 대기가 필요한 워커(approve loop 등)만 Agent 경로를 쓴다.

**★ [교정 2026-07-06] TOP 모델[1m] 세션의 서브에이전트 모델 leak — 재검증 결과 미재현 (오진 또는 플랫폼 수정)**: 07-03 실측(당시 opus-4-8[1m])은 "[1m] 세션에서 Agent 스폰 시 워커가 frontmatter 모델을 무시하고 세션 모델을 상속한다"고 주장했으나, **07-06 재검증에서 반증됨** — `claude-sonnet-5[1m]` 세션에서 Agent 도구로 ft-checker(`subagent_type`만 지정, model 생략) 스폰 → transcript `message.model` = `claude-sonnet-4-6` (frontmatter 정확 적용). **resolver env(`ANTHROPIC_DEFAULT_*_MODEL`) 전무한 환경에서도 leak 없음.** 비-[1m] 세션도 동일 날짜에 leak 없음 확인(ft-checker→sonnet-4-6, ft-implementer→opus-4-6). 판정: 07-03 주장은 오진이었거나 플랫폼이 이후 수정된 것.

잔존 주의사항 (leak과 별개로 유효):
- **bare tier `model:"opus"`/`"sonnet"` 지정은 여전히 금지** — tier alias는 세션 TOP 모델로 해석될 수 있음(07-03 실측, 미재검증). `subagent_type`만 지정하고 model 파라미터를 생략하면 frontmatter full ID가 적용되므로 안전.
- resolver env 설정(`install-gate.sh --install --with-resolver-env`)은 tier alias를 쓸 때만 필요한 **선택 사항**으로 강등.
- 스폰 후 `message.model` 검증(mismatch=hard stop)은 저비용 안전판으로 **유지 권장** — 단 "[1m]=Workflow 강제"의 근거는 소멸.

### ★ 스폰 경로 결정표 (교정 2026-07-06 — model leak 반증 반영)

07-03 실측은 "Agent-tool teammate=세션 TOP 모델/xhigh leak"을 주장했으나 **07-06 재검증에서 model leak은 [1m]·비-[1m] 모두 미재현**(§45 교정 참조 — `subagent_type`만 지정+model 생략 시 frontmatter full ID 정확 적용). 따라서 **Agent 경로는 모든 세션에서 일회성 브레인에도 허용**된다. Workflow가 여전히 우위인 지점은 leak이 아니라 ① `effort` 파라미터 명시 제어(Agent 도구엔 effort 파라미터가 없어 frontmatter `effort:`에 의존) ② 구조화 출력(schema) ③ 대량 fan-out 오케스트레이션이다. **미재검증 잔존 리스크**: ultracode(xhigh) 세션에서 claude-5 계열 워커의 effort 상속 400 즉사(§21)는 07-06에 재검증 안 됨 — xhigh 세션에서 claude-5 워커(planner·tester)를 Agent로 스폰할 땐 스폰 후 배너/`message.model` 확인 또는 Workflow `effort` 명시 경로를 유지하라.

| 워커 유형 | 스폰 경로 | 모델/effort 제어 |
|-----------|-----------|------------------|
| **일회성 브레인** (planner·checker·analyst·implementer·tester) | **Agent 도구**(`subagent_type`만, model 생략) 또는 **Workflow `agent()`** + `agentType` + `effort` 명시 | 둘 다 frontmatter/스펙 준수(07-06 실측). claude-5 워커를 xhigh 세션에서 쓸 땐 Workflow `effort` 명시 권장(잔존 리스크 절) |
| **analyst (진단 전문)** | **Agent 도구** (opus-4-6 high) | 4.6 계열이라 effort 함정 없음. Bash 읽기 전용(파일 수정 금지). DIAGNOSIS + ESCALATE_TO_PLANNER 보고 계약 |
| **장수명 드라이버** (codex DA·cursor DA·planner-x·omx/omo·claude 플러그인 크루) | **Agent-tool teammate** (sonnet-4-6 low, 우측 pane 가시) — Bash로 외부 CLI를 `< /dev/null` detach 실행 + SendMessage 릴레이 | 드라이버는 **셔틀**(외부 CLI가 실제 브레인). approve loop·SendMessage 대기 때문에 Workflow(일회성) 불가 → Agent 필수. [1m]에서 드라이버 모델 leak은 **무관**(드라이버=셔틀, 외부 CLI가 wrapper의 주입된 full-id/effort로 실행 → 실제 브레인 모델에 영향 없음). mismatch hard-stop은 **일회성 브레인(Workflow 강제)에 적용**, 드라이버에는 해당 없음. 스트림: codex `--json`+`--output-last-message`로 이벤트 파싱·중간보고(ft-update-backlog #1) |
| **DA 브레인** | codex gpt-5.5 **high** 또는 grok-4.6 (cursor-agent) — 세션 시작 인터뷰에서 사용자 선택 | 세션 무관(외부 CLI). 드라이버=sonnet-4-6 low |
| **planner 대체** (fable 부재 시) | **codex-5.6-sol high** (→ft-planner-x 드라이버) — 세션 시작 인터뷰에서 선택. 미가용 시 `BRAIN_UNAVAILABLE` 보고 후 남은 choices 재제시 | fable 미가용·rate limit 시 대안. 자동 폴백 금지 |

**★ full model ID 강제 (bare tier 금지 — 실측 leak 원인)**: 스폰 호출·state 원장·보고에 모델을 적을 땐 **항상 정확한 full ID**로 — `claude-fable-5`·`claude-sonnet-5`·`claude-opus-4-6`·`claude-sonnet-4-6`. **bare tier `"opus"`/`"sonnet"` 절대 금지** — bare tier는 세션 TOP 모델로 해석돼 leak(실측: `model:"opus"` 스폰 → 세션 모델/xhigh). 원장에 "opus/high"처럼 쓰면 세대가 모호 → 반드시 "opus-4-6"으로. Workflow는 `agentType`(frontmatter 정확 ID) 사용이 안전(model 파라미터로 tier 넘기지 말 것).

**준수 게이트(필수)**: **일회성 브레인(Workflow 경로)** 스폰 후 실제 모델을 검증한다 — workflow 디렉토리 `agent-*.jsonl`의 `message.model`. **지정 스펙과 불일치 = hard stop**(해당 워커 중단 → 올바른 경로로 재스폰, leak 미교정 진행 금지). **장수명 드라이버는 제외**(셔틀 — 외부 CLI가 wrapper 주입 full-id로 실행, 드라이버 자체 모델 leak은 무관). "더 강력하니 괜찮다"는 금지 — 로스터의 존재 이유(비용·동작 제어)를 부정. fable-5는 서버 rate limit이 타이트(실측 2회 실패) → 실패 시 `BRAIN_UNAVAILABLE` 보고 후 남은 choices(codex-5.6-sol/high 등) 재제시.

## 표준 로스터 (references/agent-templates/ 와 1:1)

> **v3 스폰 경로 주의**: 아래 표의 **브레인·effort·도구**는 v3에서도 유효하나, **"스폰 경로" 열은 Legacy(agent-v2) 매핑**이다 — v3 기본 스폰은 위 **「v3 스폰 — tmuxc 세션」 매트릭스**(전 역할 tmux 세션, `ft-tmux-spawn.sh` 경유)를 따른다. 이 표는 `references/agent-templates/`와의 1:1 대응(롤백 시 디스패처 참조)을 유지한다. v3 상시 세션 **ft-pm-memory**(sonnet-4-6/medium)는 agent-template이 아니라 세션 계약 프롬프트(`prompts/pm.md`)로 정의되므로 이 표에 없다.

| 워커 | 브레인 (선택지) | effort | 스폰 경로 | 도구 | 전담 |
|------|----------------|--------|-----------|------|------|
| ft-planner | **fable-5** 또는 **codex-5.6-sol**(→ft-planner-x 드라이버) | **high** (max 금지) | fable-5=Workflow / codex=드라이버 | Read, Grep, Glob, Write | 원인 분석·해결 설계 → 설계 파일 |
| ft-analyst | **opus-4-6** | **high** | Agent | Read, Grep, Glob, Bash(읽기전용) | 로그↔코드↔스펙 3자대조 진단 |
| ft-checker | sonnet 4.6 | **medium** | Agent | Read, Grep, Glob | 대량 서치·로그·문서·아키텍처 확인 (병렬 다수, 단말성) |
| ft-implementer | **opus-4-8** | **high** | Agent | +Bash, Edit, Write, Skill, Monitor | 설계 파일 기반 구현. 프로젝트 스킬 호출 가능 |
| ft-tester / ft-tester2 | sonnet 5 | high | Workflow(effort 명시) | +Bash, Monitor | 테스트 설계·실행·repro |
| ft-da | **codex-5.6-sol** 또는 **grok-4.6** (드라이버: sonnet 4.6 low) | **high** | 드라이버 | +Bash, Monitor | DA review + DA approve loop |
| ft-da2 | **grok-4.6** 또는 **codex-5.6-sol** (da의 반대편) | **high** | 드라이버 | +Bash, Monitor | DA 이종 교차 검증 |
| ft-planner-x | codex-5.6-sol (planner=codex 선택 시에만 활성) | high (드라이버 low) | 드라이버 | +Bash, Write, Monitor | planner 계약 대행 (codex 출력 → 설계 파일) |
| ft-da-cursor | grok-4.6 (드라이버: sonnet 4.6 low) | high (드라이버 low) | 드라이버 | +Bash, Monitor | grok DA 판정 릴레이 |

> **메인 오케스트레이터(세션) = sonnet-5 또는 fable-5 (ultracode — 세션 시작 시 사용자 선택)** — 워커 아님(로스터에 없음). 기획·구현을 직접 하지 않고 위임하며, **orchestration-gate 훅**(§강제 게이트)이 코드 3파일째부터 물리 차단한다.

공통 불변: `tools:`에 Agent/Task 없음(서브의 서브 차단), 워커 모델에 fable-5 금지(최상위 브레인 좌석 planner만 예외), 보고는 최소 토큰 형식 강제.

**크루 (opt-in 확장 로스터)**: 로컬 하네스 전문 드라이버 워커 — ft-da(codex)가 원형이며, 같은 패턴으로 **하네스 이름 그대로** 추가한다. A형(외부 CLI): `omo`(OMX/OMO)·`perplexity`(무상태 API 스크립트 `perplexity_direct.py` — 웹 서치·팩트체크, 산출물 파일 저장 책임 때문에 `tools:`에 Write 포함). B형(claude 플러그인): `gstack`·`superpowers`·`insane-search`·`ouroboros` — **드라이버 서브에이전트(sonnet4.6 low, 우측 pane 가시)가 Bash로 `claude -p`(자식 실행 모델 sonnet4.6 high)를 실행·릴레이**(스폰 경로 표 3행 — 오케스트레이터 직접 실행 금지). 템플릿은 `ft-<crew>.md.tpl` 1:1. **세션 승계(resume/inject 체인)와 컨텍스트 윈도우 관리(요약-후-fork + WINDOW_PRESSURE)는 크루의 기본 제공 계약**(brain_sessions 4번째 버킷 규칙 동일 적용). 감지·설치는 install-interview §4, 공통 계약·카탈로그는 `references/crew/crew-support.md`, 하네스별 상세는 `references/crew/<하네스>-full-context.md`.

## 사용 절차

0. **브레인 가용성 체크** (설치 시작 전 필수): `references/brain-availability.md` — codex/cursor 등 미가용 시 남은 choices 재제시
1. **설치 인터뷰** (최초/변경 시): `references/install-interview.md`
2. **동적 배치 카탈로그**: `references/deployment-patterns.md` — 7패턴(P-BUG/P-FEAT/P-REFAC/P-ANLZ/P-HOT/P-VRFY/P-DOC) + 운영 규칙 4개 + 킥오프 AskUserQuestion 템플릿 7종. 스텝3에서 유형 분류 → 투입 워커 부분집합 추천에 사용
3. **피처 인터뷰** (매 피처 시작 시): `references/feature-interview.md` — 무엇을 할지 한 줄/파일로 받고, 프로젝트의 스킬·플러그인·하네스·도구를 서치해 추천 기반 설계 인터뷰 진행
4. **오케스트레이션** (파이프라인 실행): `references/orchestration-playbook.md`
4. **모니터링·지원 체크 루프** (파이프라인 상시): `references/monitoring-loop.md` — 멈춤 감지 + 진로이탈 교정 + 상태 원장
5. **컨텍스트 관리** (상태 외재화·compact/clear/재시작·복원): `references/context-management.md` — 디스크 SSOT(`.fable-team/state/`) write-through, ctx 임계 정책, 세션 재시작 복원 절차. **새 세션 트리거 시 피처 인터뷰 이전에 §4(ACTIVE 감지·복원)를 먼저 수행.**
6. **업데이트** ("FT 업데이트" 시): `references/update.md` — 팩 소스 → 로컬 설치본 패치(스킬 파일 + 에이전트 .md 재치환, 인터뷰 답변 보존) + 새 세션 프로브 재검증.
7. **강제 게이트** (오케 폭주·컨텍스트 방어): `references/orchestration-gate.md` — 4-레이어(선언·역할·기준·강제) + 프로젝트 설치 지원(`templates/install-gate.sh`). 부팅 시퀀스에서 설치 상태 확인·제안.
8. **반복 문제해결 루프** (로그드리븐 BTS): `references/rapid-iteration-loop.md` — 큰 수정(재설계) 금지, **빠른 테스트→문제발견→수술적 대응→재테스트 반복**으로 작업리스트 완성. 로그는 얼마든 심고 증명 후 정리. 3자대조(로그↔코드↔스펙). 테스트=byz-e2e/omo qa/ft-tester, 로그·BTS 파악=ft-checker(sonnet), 문제확인=ft-planner+ft-da(approve loop), 수정=ft-implementer(surgical).

## 강제 게이트 (orchestration-gate) — 선언 아닌 물리 차단

CLAUDE.md·SKILL.md에 "오케는 위임한다"고 적는 건 **권고**라 모델이 우회 가능. **PreToolUse 훅으로 물리 차단**해야 실제로 막힌다(출처: joel__w__w 스레드). fable-team은 4-레이어를 **한 세트로** 유지·배포한다:

| 레이어 | 파일 | 역할 |
|--------|------|------|
| 선언 | `templates/CLAUDE.orchestration.snippet.md` → 프로젝트 CLAUDE.md | declaration |
| 역할 | `references/agent-templates/` (로스터) | role assignment |
| 기준 | `templates/rules/orchestration.md` → `.claude/rules/` | operating criteria |
| 강제 | `templates/hooks/orchestration-gate.sh`·`orchestration-turn-reset.sh`·`context-distill-gate.sh` → `.claude/hooks/` + settings.json | enforcement |

- **오케 편집 게이트**: 최상위 모델 오케(fable-5/sonnet-5)가 한 턴에 **코드 파일 2개까지**, 3개째 Edit/Write/Bash(sed·echo>·tee) **하드 deny**+위임 메시지. 워커(opus-4-6/sonnet)는 무제한(모델 판별=transcript 마지막 assistant model). **fail-open**(오류 시 허용 — 세션 brick 금지).
- **컨텍스트 증류 게이트**: 300k warn 주입 / 450k 신규 스폰 하드 deny.
- **설치**: `templates/install-gate.sh --check|--install [proj]` — 상태 진단 + 멱등 설치(settings 병합·백업). **패치마다 4-레이어 세트로 함께 갱신**(update.md).

## 함정 (실측)

- **Agent 팀 하네스는 frontmatter `effort:` 무시** → 세션 effort 상속. ultracode(xhigh) 세션에서 claude-5 계열 워커 즉사. Workflow 경로로 우회 — claude-5엔 effort **high** 명시(xhigh 전달 금지, 전 좌석 high — D1).
- **[반증 2026-07-06] TOP 모델[1m] 세션 서브에이전트 모델 leak — 미재현**: `subagent_type`만 지정+model 생략 시 [1m]·비-[1m] 모두 frontmatter full ID 정확 적용(§45 교정). 잔존 함정은 **bare tier `model:"opus"` 지정**(세션 모델로 해석될 수 있음 — 금지 유지)과 **xhigh 세션의 claude-5 워커 effort 상속 400**(미재검증 — §21). 스폰 후 `message.model` 스팟체크는 저비용 안전판으로 유지.
- **에이전트 .md 수정은 이미 등록된 타입에 소급 반영 안 됨** — 같은 이름 재사용 시 구정의(모델·도구)가 캐시로 살아있을 수 있다. 정의 변경 시 새 파일명으로 만들거나 새 세션에서 사용.
- codex 호출: `npx -y @openai/codex exec ... < /dev/null` (alias 미해석 + stdin hang 방지), `-c model_reasoning_effort="xhigh"` 지원 확인됨, 적용 여부는 세션 헤더 `reasoning effort:` 라인으로 검증.
- 워커 실제 모델 검증: `~/.claude/projects/<proj>/<session>/subagents/agent-*.meta.json`의 `model` + `agent-*.jsonl`의 `message.model`.
- 워커 감시: Monitor로 `agent-*.jsonl`에 `API Error` 문자열 포함 폴링 (조용한 실패 방지).
- **원장이 컨텍스트에만 있으면 자동 컴팩션/재시작/증류로 증발** → 라운드 한도 붕괴·완료 단계 재실행·미승인 종결 위험. 진행 상태는 반드시 디스크 SSOT(`.fable-team/state/`)에 write-through (`references/context-management.md`).
- **세션 내 백그라운드 워커는 사용자 개입에 동반 사망** — ESC/메시지마다 `[Request interrupted by user]`, 자동 재시도도 재개입 시 재사망(실측). **v3 가시성 규범**: v3 워커는 **독립 tmux 세션**이라 오케 세션 개입에 동반 사망하지 않는다(생명주기 분리 = v3 핵심 이득) — 사용자는 필요 시 `tmux attach`로 임의 워커를 직접 관찰한다. 오케의 HIL 집중 게이트(§1-6)가 사용자 접점을 단일화하므로 상시 attach는 불요하다. "보이지 않는 백그라운드는 돌지 않는 것으로 간주" 원칙은 유지되되, v3에선 이를 **우측 pane**이 아니라 **명명된 tmux 세션 + `ft-tmux-poll.sh` 센티널 판독**으로 실현한다(무가시 직접 발사는 여전히 금지). *(Legacy agent-v2 경로에선 우측 pane 서브에이전트 가시가 규범 — 위 「부록: Legacy spawn」 참조.)*
