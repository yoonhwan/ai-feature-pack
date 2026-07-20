# fable-team 설치 인터뷰

## 0. 브레인 가용성 체크 (인터뷰 전 필수)

`brain-availability.md`의 프로브를 실행해 codex/cursor-agent/gemini 가용성을 실측한다. 미가용 브레인이 기본값에 있으면 대체 추천표의 대안을 해당 질문의 기본 선택지로 바꿔 제시하고, 결과를 `install.json`의 `substitutions`에 기록한다.

설치 요청 시 AskUserQuestion(또는 대화)으로 아래를 순서대로 받는다. 기본값은 [대괄호].

## 1. 공통

| 키 | 질문 | 기본값 |
|----|------|--------|
| `{{TEAM_NAME}}` | 팀 이름? | [fable-team] |
| `{{PREFIX}}` | 에이전트 이름 접두사? (충돌 방지) | [ft] |
| 설치 위치 | 사용자 레벨(`~/.claude/agents/` + `~/.claude/skills/fable-team/`) vs 프로젝트(`<project>/.claude/agents/` + `.claude/skills/`)? | [사용자 레벨] — 모든 프로젝트 공용. 프로젝트별 스킬/하네스 커스텀이 목적이면 프로젝트 |

## 2. 워커별 브레인/effort

| 키 | 질문 | 기본값 | 허용값 주의 |
|----|------|--------|-------------|
| `{{ARCHITECT_MODEL}}` / `{{ARCHITECT_EFFORT}}` | 기획·문제해결 브레인? (**기본 claude-sonnet-5** — fable-5는 에스컬레이션 전용(신규설계·2연속 DA REJECT·라이브 반증 1회, 증거팩 인라인 필수). 미가용 시 `BRAIN_UNAVAILABLE` 보고 후 남은 choices 재제시) | [claude-sonnet-5 / **high**] | Workflow 경로로만 스폰. **선택을 install.json ARCHITECT_MODEL에 기록**. max 금지(hang). codex-5.6-sol 선택 시 ft-architect-x 드라이버 활성 |
| `{{ANALYST_MODEL}}` / `{{ANALYST_EFFORT}}` | 진단(analyst) 브레인? | [claude-opus-4-6 / **high**] | Agent 경로. Bash 읽기전용. DIAGNOSIS + ESCALATE_TO_ARCHITECT 보고 |
| `{{CHECKER_MODEL}}` / `{{CHECKER_EFFORT}}` | 대량 서치·로그·문서 워커 브레인? | [claude-sonnet-4-6 / **medium**] | sonnet4.6은 low·medium·high만. 빠른 확인 BTS 3종 표준 = medium |
| `{{IMPLEMENTER_MODEL}}` / `{{IMPLEMENTER_EFFORT}}` | 구현 워커 브레인? | [claude-opus-4-8 / **high**] | opus-4-8 high 기본. 미가용 시 opus-4-6 유지 보고 후 사용자 결정. max 금지 |
| `{{TESTER_MODEL}}` / `{{TESTER_EFFORT}}` | 테스터 브레인? | [claude-sonnet-5 / high] | claude-5 유효 effort: low/medium/high/max — **xhigh 불가, 표준 high** |
| `{{DA_BRAIN_MODEL}}` / `{{DA_EFFORT}}` | DA 브레인? | [gpt-5.5 (codex default) / **high**] | codex 또는 grok-4.6(cursor-agent) — 세션 인터뷰 스텝1에서 사용자 선택 |
| `{{DA_DRIVER_MODEL}}` | DA 드라이버(codex/cursor-agent 호출 셔틀)? | [claude-sonnet-4-6] | 드라이버 effort는 low 고정. ft-da-cursor(grok) 드라이버도 동일 모델 |
| `{{DA_MAX_ROUNDS}}` | approve loop 최대 라운드? | [2] | 초과 시 사용자 에스컬레이션 |

**금지 검증 (인터뷰 후 필수)**: architect를 제외한 워커 모델에 `fable-5`가 들어가면 거부하고 재질문. **architect(최상위 브레인 좌석)만 fable-5 허용** — 두뇌 역할이기 때문이다.

**오케스트레이터 게이트**: 설치 완료 후 "메인 오케스트레이터 = **sonnet-5 또는 fable-5 (ultracode — 세션 시작 시 사용자 선택)** 세션에서 이 스킬을 트리거하며, 기획·문제해결은 architect(fable5 또는 codex-5.6-sol — 세션 인터뷰에서 선택)에, 구현은 워커에 위임된다"를 사용자에게 고지한다.

**강제 게이트 설치 지원 (필수 제안)**: 설치 완료 후 `templates/install-gate.sh --check <프로젝트>`로 orchestration-gate 설치 상태를 진단하고, 미설치면 **설치를 제안**한다(`--install`). 이는 오케의 코드 직접수정 폭주·컨텍스트 증류를 **훅으로 물리 차단**하는 4-레이어(선언·역할·기준·강제)를 프로젝트 `.claude/`에 배포한다 — 상세 `references/orchestration-gate.md`. **[1m]/opus 오케 세션은 서브에이전트 모델 leak 교정**(resolver env or Workflow 강제 — 스폰 경로 §)도 함께 안내한다.

## 3. 프로젝트 커스텀

| 키 | 질문 | 기본값 |
|----|------|--------|
| `{{EXTRA_INSTRUCTIONS}}` | 이 프로젝트에서 워커가 따라야 할 추가 지침? (프로젝트 스킬 호출 규칙, 금지사항 등) | [빈 줄] |
| `{{TEST_RUNNER_NOTE}}` | 테스트 러너 지정? (예: "테스트는 반드시 `make test`로") | [빈 줄] |

프로젝트에 스킬이 있으면(`<project>/.claude/skills/*`) 목록을 보여주고 "구현/테스터 워커가 사용할 스킬"을 고르게 한 뒤, 해당 지침을 `{{EXTRA_INSTRUCTIONS}}`에 넣는다.
예: `- 이 프로젝트에서 UI 작업 시 frontend-ui-ux-design 스킬을 Skill 도구로 호출하라.`

## 4. 크루(로컬 하네스 전문 워커) 감지·설치 — opt-in

표준 로스터 외에, 로컬에 설치된 외부 하네스를 전문 구동하는 크루를 추가할 수 있다 (`references/crew/crew-support.md`).

1. **감지** (Bash 실측 — crew-support.md 카탈로그 기준): `omx --version`(omo), `ls ~/.claude/skills/perplexity-direct-api`(perplexity), `ls ~/.claude/skills/gstack`(gstack), `~/.claude/plugins/cache/claude-plugins-official/superpowers/`(superpowers), `~/.claude/plugins/cache/gptaku-plugins/insane-search/`(insane-search), `~/.claude/plugins/cache/ouroboros/ouroboros/`(ouroboros). da는 §0 브레인 체크가 이미 커버.
2. 감지된 하네스마다 "크루 추가?" **opt-in** 질문 — 기본값 [추가 안 함]. §0에서 architect substitution 기록 시(=fable-less) omo·insane-search 질문에 **`★ fable-less 추천` 배지 + 근거 1줄 표시** — 기본값은 [추가 안 함] 그대로(§3 원칙: 기본값 변경 구현 금지).
3. 추가 선택 시: `agent-templates/ft-<crew>.md.tpl` 치환(드라이버 모델 `{{OMO_DRIVER_MODEL}}`/`{{CREW_DRIVER_MODEL}}` 기본 [claude-sonnet-4-6]) 또는 crew-support.md의 일반 계약 골격으로 `<PREFIX>-<crew>.md` Write. B형 크루의 실행 모델은 템플릿에 sonnet4.6 high로 고정돼 있다(질문 불요).
4. 검증: §5 프로브와 동일 + 하네스 1회 실측 호출 (예: omo 크루 → `omx exec -s read-only '$analyze <간단 질의>' < /dev/null`).

## 4.5 연동(integrations) 감지·선언 — baton·cairn

로컬 하네스 연동 레벨을 선언한다 (`references/integrations.md`가 상세 SSOT):

1. 프로브 2종 Bash 실측: `bash ~/.baton/current/bin/baton status < /dev/null`, `(cd <프로젝트 루트> && bash ~/.cairn/current/bin/cairn status < /dev/null)`.
2. 감지된 것마다 AskUserQuestion: "연동 레벨? **[off]** / on / required" (미감지면 질문 생략 = off 고정). **required 선택 시 추가 질문 1개**: "무인(headless) 실행에서 required 실패 시? **[deny — fail-fast+롤백]** / allow-degrade — 요란한 기록 후 속행".
3. 답변을 `install.json.integrations`에 기록 (§5-3-1 스냅샷 포함 — "FT 업데이트"가 보존).

## 5. 설치 절차 (인터뷰 완료 후)

1. `references/agent-templates/*.md.tpl`에서 필요한 템플릿을 Read. 기본 5종(architect/checker/implementer/tester/da) + 신설 3종(analyst/architect-x/da-cursor)에서 세션 선택에 따라 활성화할 것만. **§0에서 DA를 claude로 대체 확정(substitutions 기록)한 경우 da 템플릿은 `ft-da.md.tpl` 대신 `ft-da-claude.md.tpl`**(brain-availability §3). architect=codex 선택 시 `ft-architect-x.md.tpl` 추가. DA에 grok 선택 시 `ft-da-cursor.md.tpl` 추가. 크루 opt-in(§4)이 있으면 해당 크루 템플릿도.
2. 모든 `{{PLACEHOLDER}}`를 답변으로 치환 (빈 값은 빈 문자열, 잔여 `{{`가 남으면 설치 실패로 간주).
3. 대상 위치에 **`<PREFIX>-architect.md`**, `<PREFIX>-checker.md`, `<PREFIX>-implementer.md`, `<PREFIX>-tester.md`, `<PREFIX>-da.md`(+ 선택 크루 `<PREFIX>-<crew>.md`)로 Write — **architect 누락 금지**. architect .md가 설치돼 있어야 다음 세션부터 Workflow `agentType`으로도 인식된다(세션 시작 등록 타입만 유효).
3-1. **답변 스냅샷 기록 (SSOT)**: 인터뷰 답변 전체(placeholder 키-값 + substitutions + 설치 시각 + 팩 커밋 해시)를 **프로젝트 `<root>/.fable-team/install.json`**(단일 원천 SSOT)에 Write — 이후 "FT 업데이트"(`references/update.md`)가 이 파일로 재치환한다(재인터뷰 불요). 설치 스킬 위치와 프로젝트 `.fable-team/` 후보 2위치가 상이하면 **상이한 것이 복수일 때만 중단**하고 사용자 확인(update.md SSOT 규약과 동일).
3-2. **v3 세션 계약 프롬프트 설치 (필수 — tmuxc 세션 경로)**: `skill/templates/session-prompts/*.md`(architect/analyst/implementer/tester/da-codex/da-cursor/checker/pm 8종)를 Read → **동일 `{{PLACEHOLDER}}` 키**(`{{TEAM_NAME}}`/`{{DA_BRAIN_MODEL}}`/`{{DA_EFFORT}}`/`{{DA_MAX_ROUNDS}}`/`{{EXTRA_INSTRUCTIONS}}`/`{{TEST_RUNNER_NOTE}}` — 3번과 같은 답변 사용, **신규 인터뷰 질문 불요**)로 치환 → `.fable-team/prompts/<role>.md`로 Write. **잔여 `{{`가 남으면 설치 실패로 간주**(2번과 동일 규칙). da는 세션 선택에 따라 `da-codex`(codex 직접) 또는 `da-cursor`(grok 드라이버) 중 활성만 설치. 이 프롬프트는 v3 tmuxc 세션(`ft-tmux-spawn.sh --prompt-file`)이 스폰 직후 Read하는 역할 계약이다(3번의 `<PREFIX>-*.md` agent 정의는 Legacy/agent-v2 롤백 디스패처용 — 둘 다 설치·유지).
3-3. **bin 11종 설치 (v3 tmuxc 세션 스크립트)**: `skill/scripts/`의 11종(`ft-lib.sh` + `ft-tmux-spawn.sh`/`ft-tmux-send.sh`/`ft-tmux-poll.sh`/`ft-tmux-kill.sh`/`ft-tmux-distill.sh` + `ft-pm-watchd.sh` + `ft-ctx-triage.sh` + `ft-gzip.sh` + `ft-mbox.py`/`ft-mbox.sh`)을 프로젝트 `<root>/.fable-team/bin/`에 복사 + `chmod +x`. 이 bin 세트가 tmuxc 세션(spawn/send/poll/kill/distill·PM watchd·ctx triage·gzip·mbox 파일 큐)의 런타임이며, `ft-lib.sh`는 나머지가 source하는 공용 헬퍼다. **이 bin 세트는 개별 파일 교체가 아니라 원자 디렉토리 스왑으로만 갱신**한다(리네임·가드 배포 시 update.md §P-2 — 유일 예외 = Phase 0 가드 append). 설치·재설치는 멱등(내용 동일 시 무변화).
4. 검증 — 프로브는 **두 경로로 전 워커**를 커버한다 (`orchestration-playbook.md` §프로브):
   - Agent 경로(checker/implementer/da + 크루 드라이버): 팀 하네스 프로브.
   - **Workflow 경로(architect/tester): Workflow `agent()`에 model/effort 명시로 동일 프로브** — Agent 프로브만 돌리면 architect가 목록에 안 떠 설치가 완료된 것처럼 보이는 함정(실사례: `probe-checker/impl/da`만 표시되고 기획 브레인 미검증).
   - **통과 기준: 신규 세션은 architect(최상위 기획 브레인 — 기본 high) 프로브 통과가 필수** — architect 프로브가 없으면 설치 미완으로 간주하고 3번부터 재수행.
5. 실패 패턴: 워커가 `API Error 400 level ... not supported`로 죽으면 effort/모델 조합 오류 — 위 허용값 표로 교정 후 재설치.
