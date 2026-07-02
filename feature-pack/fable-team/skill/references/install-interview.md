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
| `{{PLANNER_MODEL}}` / `{{PLANNER_EFFORT}}` | 기획·문제해결 브레인? (팀의 두뇌 — 최상위 모델 권장) | [claude-fable-5 / max] | Workflow 경로로만 스폰 (SKILL.md 스폰 경로 분리 규칙) |
| `{{CHECKER_MODEL}}` / `{{CHECKER_EFFORT}}` | 확인 워커 브레인? | [claude-sonnet-4-6 / low] | sonnet4.6은 low·medium·high만 |
| `{{IMPLEMENTER_MODEL}}` / `{{IMPLEMENTER_EFFORT}}` | 구현 워커 브레인? | [claude-opus-4-6 / max] | |
| `{{TESTER_MODEL}}` / `{{TESTER_EFFORT}}` | 테스터 브레인? | [claude-sonnet-5 / high] | claude-5 유효 effort: low/medium/high/max — **xhigh 불가, 표준 high** |
| `{{DA_BRAIN_MODEL}}` / `{{DA_EFFORT}}` | DA 브레인? | [gpt-5.5 (codex default) / xhigh] | codex는 xhigh 지원 |
| `{{DA_DRIVER_MODEL}}` | DA 드라이버(codex 호출 셔틀)? | [claude-sonnet-4-6] | 드라이버 effort는 low 고정 |
| `{{DA_MAX_ROUNDS}}` | approve loop 최대 라운드? | [2] | 초과 시 사용자 에스컬레이션 |

**금지 검증 (인터뷰 후 필수)**: planner를 제외한 워커 모델에 `fable-5` 또는 `opus-4-8`이 들어가면 거부하고 재질문. planner만 최상위 모델(fable5) 허용 — 두뇌 역할이기 때문이다.

**오케스트레이터 게이트**: 설치 완료 후 "오케스트레이터는 ultracode 지원 최상위 모델 세션에서 이 스킬을 트리거해야 하며, 기획·문제해결은 planner에 위임된다"를 사용자에게 고지한다.

## 3. 프로젝트 커스텀

| 키 | 질문 | 기본값 |
|----|------|--------|
| `{{EXTRA_INSTRUCTIONS}}` | 이 프로젝트에서 워커가 따라야 할 추가 지침? (프로젝트 스킬 호출 규칙, 금지사항 등) | [빈 줄] |
| `{{TEST_RUNNER_NOTE}}` | 테스트 러너 지정? (예: "테스트는 반드시 `make test`로") | [빈 줄] |

프로젝트에 스킬이 있으면(`<project>/.claude/skills/*`) 목록을 보여주고 "구현/테스터 워커가 사용할 스킬"을 고르게 한 뒤, 해당 지침을 `{{EXTRA_INSTRUCTIONS}}`에 넣는다.
예: `- 이 프로젝트에서 UI 작업 시 frontend-ui-ux-design 스킬을 Skill 도구로 호출하라.`

## 4. 크루(로컬 하네스 전문 워커) 감지·설치 — opt-in

표준 로스터 외에, 로컬에 설치된 외부 하네스를 전문 구동하는 크루를 추가할 수 있다 (`references/crew/crew-support.md`).

1. **감지** (Bash 실측 — crew-support.md 카탈로그 기준): `omx --version`(omo), `ls ~/.claude/skills/gstack`(gstack), `~/.claude/plugins/cache/claude-plugins-official/superpowers/`(superpowers), `~/.claude/plugins/cache/gptaku-plugins/insane-search/`(insane-search), `~/.claude/plugins/cache/ouroboros/ouroboros/`(ouroboros). da는 §0 브레인 체크가 이미 커버.
2. 감지된 하네스마다 "크루 추가?" **opt-in** 질문 — 기본값 [추가 안 함].
3. 추가 선택 시: `agent-templates/ft-<crew>.md.tpl` 치환(드라이버 모델 `{{OMO_DRIVER_MODEL}}`/`{{CREW_DRIVER_MODEL}}` 기본 [claude-sonnet-4-6]) 또는 crew-support.md의 일반 계약 골격으로 `<PREFIX>-<crew>.md` Write. B형 크루의 실행 모델은 템플릿에 sonnet4.6 high로 고정돼 있다(질문 불요).
4. 검증: §5 프로브와 동일 + 하네스 1회 실측 호출 (예: omo 크루 → `omx exec -s read-only '$analyze <간단 질의>' < /dev/null`).

## 5. 설치 절차 (인터뷰 완료 후)

1. `references/agent-templates/*.md.tpl` **5개 전부**(planner/checker/implementer/tester/da)를 Read. 크루 opt-in(§4)이 있으면 해당 크루 템플릿도.
2. 모든 `{{PLACEHOLDER}}`를 답변으로 치환 (빈 값은 빈 문자열, 잔여 `{{`가 남으면 설치 실패로 간주).
3. 대상 위치에 **`<PREFIX>-planner.md`**, `<PREFIX>-checker.md`, `<PREFIX>-implementer.md`, `<PREFIX>-tester.md`, `<PREFIX>-da.md`(+ 선택 크루 `<PREFIX>-<crew>.md`)로 Write — **planner 누락 금지**. planner .md가 설치돼 있어야 다음 세션부터 Workflow `agentType`으로도 인식된다(세션 시작 등록 타입만 유효).
3-1. **답변 스냅샷 기록**: 인터뷰 답변 전체(placeholder 키-값 + substitutions + 설치 시각 + 팩 커밋 해시)를 설치 스킬 위치의 `install.json`에 Write — 이후 "FT 업데이트"(`references/update.md`)가 이 파일로 재치환한다(재인터뷰 불요).
4. 검증 — 프로브는 **두 경로로 전 워커**를 커버한다 (`orchestration-playbook.md` §프로브):
   - Agent 경로(checker/implementer/da + 크루 드라이버): 팀 하네스 프로브.
   - **Workflow 경로(planner/tester): Workflow `agent()`에 model/effort 명시로 동일 프로브** — Agent 프로브만 돌리면 planner가 목록에 안 떠 설치가 완료된 것처럼 보이는 함정(실사례: `probe-checker/impl/da`만 표시되고 기획 브레인 미검증).
   - **통과 기준: 신규 세션은 planner(최고성능 max effort 기획 브레인) 프로브 통과가 필수** — planner 프로브가 없으면 설치 미완으로 간주하고 3번부터 재수행.
5. 실패 패턴: 워커가 `API Error 400 level ... not supported`로 죽으면 effort/모델 조합 오류 — 위 허용값 표로 교정 후 재설치.
