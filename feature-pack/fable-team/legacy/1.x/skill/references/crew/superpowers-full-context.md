# Superpowers Full Context

이 문서는 superpowers 크루원 구동, `claude -p` 콘솔 분리 실행, resume 체인, 스킬 라우팅, few-shot 프롬프트를 한 번에 전달하기 위한 운영 컨텍스트다.

핵심 관점:

- superpowers는 "완전한 소프트웨어 개발 방법론"이다. 단일 프롬프트가 아니라 브레인스토밍 → 워크트리 → 플랜 → 실행 → TDD → 리뷰 → 완료의 **다단계 게이트형 워크플로**를 스킬로 강제한다.
- 각 스킬은 `<HARD-GATE>` / `Iron Law` 형태의 강제 규칙을 갖는다. 크루원은 게이트를 우회하지 않는다.
- 스킬 호출은 `/superpowers:<skill>` 슬래시 형식.
- 다단계 워크플로이므로 **세션 승계(`--resume`)가 핵심 가치**다 — brainstorming의 설계 승인, writing-plans의 실행방식 선택, subagent-driven-development의 태스크별 리뷰 루프가 모두 "같은 대화의 연속"을 전제로 설계됨.
- 실행 모델은 `claude-sonnet-4-6 --effort high` 고정. YOLO(`--dangerously-skip-permissions`)는 격리 worktree 전용.
- 공식: https://github.com/obra/superpowers (Jesse Vincent, MIT)

## 1. Mental Model

superpowers는 OMO처럼 도메인별 스킬 모음이 아니라 **하나의 선형 워크플로를 구성하는 스테이지 스킬 집합**이다.

기본 체인 (README "The Basic Workflow"):

```
brainstorming → using-git-worktrees → writing-plans
  → (subagent-driven-development | executing-plans)
  → test-driven-development (태스크마다)
  → requesting-code-review / receiving-code-review (태스크 사이)
  → verification-before-completion (완료 주장 직전 항상)
  → finishing-a-development-branch (전체 완료 시)
```

교차 적용 스킬:

- **systematic-debugging** — 버그/테스트 실패/예상외 동작 → fix 제안 전 항상 우선.
- **dispatching-parallel-agents** — 독립적인 2개 이상 문제 병렬 조사 시.
- **verification-before-completion** — "완료/통과/고쳐짐" 주장 직전, 스테이지 무관 항상.
- **writing-skills** — 새 스킬 생성/편집 시만 (메타, 드묾).

부트스트랩 규칙(`using-superpowers`): 스킬이 1%라도 적용될 가능성이 있으면 **반드시** 호출한다. "질문일 뿐", "일단 탐색부터"는 회피 사유가 아니다. 프로세스 스킬(브레인스토밍/systematic-debugging)이 먼저, 구현 스킬은 그 다음.

## 2. Skill / Stage Catalog

### 2.1 Design — brainstorming
트리거: 기능/컴포넌트/동작 변경 등 창의적 작업 착수 전. "너무 단순해서 설계 필요 없다"는 안티패턴 — 모든 프로젝트가 이 프로세스를 거친다.
게이트: `<HARD-GATE>` — 설계 제시·사용자 승인 전 구현 스킬 호출·코드 작성 금지.
흐름: 컨텍스트 탐색 → 한 번에 한 질문 clarify → 2-3개 접근법 제시 → 섹션별 설계 승인 → 문서화·커밋 → self-review(placeholder/모순/scope) → 사용자 스펙 리뷰 → writing-plans 전환.
산출물: `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. 터미널 상태: writing-plans **만** 호출.

### 2.2 Isolation — using-git-worktrees
트리거: 격리 필요한 feature 착수 전, 또는 플랜 실행 직전.
Step 0(기존 격리 감지, submodule 가드) → 1a(네이티브 툴 우선) → 1b(git fallback, `.worktrees/`) → 2(프로젝트 셋업) → 3(clean baseline 테스트).
**crew 팁**: 오케스트레이터가 `git worktree add .worktrees/<branch>`로 먼저 만들고 `claude -p -C .worktrees/<branch>`로 그 안에서 세션을 띄우면 Step 0이 재생성을 건너뛴다 — 비대화 실행에서 동의 프롬프트 미수신 문제를 피한다.

### 2.3 Planning — writing-plans
트리거: 스펙/요구사항 있는 다단계 작업, 코드 건드리기 전.
산출물: `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`. 태스크는 2-5분 단위, 정확한 파일 경로·완성 코드·검증 커맨드 포함. placeholder("TBD" 등) 금지.
헤더에 `REQUIRED SUB-SKILL: subagent-driven-development(권장) or executing-plans` 명시. self-review 후 실행 방식을 양자택일로 묻는다.

### 2.4 Execution — subagent-driven-development (동일 세션, 권장)
트리거: 계획 있고 태스크가 대체로 독립적, 같은 세션 실행.
패턴: 태스크마다 fresh implementer subagent → task reviewer(spec compliance + code quality 두 verdict 필수) → Critical/Important는 fix subagent 재작업 → 원장(`.superpowers/sdd/progress.md`) 기록 → 전 태스크 종료 후 whole-branch 리뷰 → finishing-a-development-branch.
레드 플래그: 병렬 구현 subagent 금지, reviewer 사전 판단 지시 금지, 리뷰 미통과 상태로 다음 태스크 금지, 완료 기록된 태스크 재디스패치 금지.

### 2.5 Execution — executing-plans (별도 세션)
트리거: 별도 세션에서 human checkpoint 두고 실행. subagent 미지원 환경 폴백.
플로우: 계획 로드·비판적 검토 → 태스크별 진행·단계 검증 → 전체 완료 후 finishing-a-development-branch. 블로커/불명확 지시/반복 검증 실패 시 즉시 정지·확인 요청.

### 2.6 Implementation Discipline — test-driven-development
트리거: 모든 기능/버그수정 구현 전.
Iron Law: `NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST`. Red(실패 테스트·확인) → Green(최소 구현) → Refactor(그린 유지). 테스트 전에 쓴 코드는 "참고용 보관" 없이 삭제.

### 2.7 Bug Investigation — systematic-debugging
트리거: 버그/테스트 실패/예상외 동작, fix 제안 전.
Iron Law: `NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST`. 4단계: Root Cause(에러 완독·재현·최근변경·경계별 계측) → Pattern Analysis(작동 예시 대조) → Hypothesis&Testing(단일 가설·최소 변경) → Implementation(실패 테스트→단일 fix→검증). **3회 이상 fix 실패 시 아키텍처 문제로 규정, 4번째 시도 없이 인간과 논의**.

### 2.8 Parallel Investigation — dispatching-parallel-agents
트리거: 독립적인 2개 이상 실패/서브시스템을 공유 상태 없이 병렬 조사·수정.
패턴: 독립 도메인 식별 → focused/self-contained 프롬프트 → 한 응답에 모두 디스패치 → 결과 리뷰·충돌 확인·전체 테스트.

### 2.9 Review — requesting-code-review / receiving-code-review
requesting: 태스크 완료마다(subagent-driven 필수)·주요 기능 완료 후·merge 전 필수. BASE/HEAD SHA로 `code-reviewer.md` 템플릿을 채워 `general-purpose` subagent 디스패치.
receiving: 피드백 받으면 즉시 구현 금지 — READ→UNDERSTAND→VERIFY(코드베이스 대조)→EVALUATE→RESPOND→IMPLEMENT. 퍼포먼스성 동의("You're absolutely right!") 금지. YAGNI 위반 제안은 실사용 grep 후 판단.

### 2.10 Completion Gate — verification-before-completion
트리거: 어떤 성공 주장이든 하기 직전, commit/PR/다음 태스크 이동 전, 에이전트 결과 신뢰 전 — 항상.
Iron Law: `NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE`. "should pass", "probably" 자체가 레드 플래그. 이 메시지 안에서 검증 커맨드를 직접 실행하지 않았다면 통과 주장 불가.

### 2.11 Wrap-up — finishing-a-development-branch
트리거: 구현 완료 + 전체 테스트 통과, 통합 방식 결정 시.
Step 1(테스트 검증) → 2(환경 감지) → 3(base branch 결정) → 4(정확히 4개 옵션: 로컬 merge/PR/유지/discard — detached HEAD는 3개) → 5(실행) → 6(옵션 1·4만 워크트리 정리).

### 2.12 Meta — writing-skills
트리거: 새 스킬 생성/편집/배포 전 검증. TDD를 문서화에 적용(베이스라인→GREEN→REFACTOR). crew 운용에서는 드묾.

## 3. Execution Pattern — `claude -p` 분리 실행 + resume 체인

**최초 실행 (session_id 회수):**
```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/superpowers:brainstorming <주제>' < /dev/null
```
JSON 응답에서 `session_id`를 파싱해 보관. `< /dev/null`로 stdin을 명시적으로 닫아 추가 입력 대기 hang을 막는다.

**후속 실행 (세션 승계):**
```bash
~/.headroom/claude-hr.sh -p --resume <session-id> --output-format json '<후속 지시>' < /dev/null
```
superpowers는 단계마다 "다음엔 이 스킬만 호출하라"는 명시적 terminal state를 갖는다(예: brainstorming → writing-plans만). **세션을 끊고 새로 시작하면 이 컨텍스트 연속성이 깨진다** — 새 세션은 이전 설계/승인 이력을 모른다. 워크플로 단계 전환마다 `--resume`이 기본형이다.

세션 유실 시 복구 앵커: `docs/superpowers/specs/*-design.md`, `docs/superpowers/plans/*.md`, `.superpowers/sdd/progress.md`. 새 세션이라도 이 파일들을 먼저 Read시켜 상태를 복원한다.

## 4. Safety Modes

**Workspace Write (기본):**
```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/superpowers:test-driven-development 실패 테스트부터 작성해줘' < /dev/null
```

**YOLO (격리 worktree 전용):**
```bash
git worktree add .worktrees/superpowers-yolo -b superpowers-yolo
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  -C .worktrees/superpowers-yolo --dangerously-skip-permissions \
  '/superpowers:subagent-driven-development docs/superpowers/plans/foo.md 실행해줘' < /dev/null
```
조건: disposable worktree, credentials/production env 미노출, destructive command 금지 명시, 최종 diff 검토, verification-before-completion 증거 확보 후에만 완료 보고.

## 5. Superpowers Crew Member General Contract

```text
You are a superpowers-specialized Codex/Claude crew member running non-interactively via `claude -p`.

Primary model:
- Superpowers is a staged, gated software development methodology, not a single-shot prompt.
- Default chain: brainstorming -> using-git-worktrees -> writing-plans ->
  (subagent-driven-development | executing-plans) -> test-driven-development (per task) ->
  requesting-code-review/receiving-code-review (between tasks) ->
  verification-before-completion (always, before any completion claim) ->
  finishing-a-development-branch.
- systematic-debugging is mandatory before proposing any fix for a bug/test failure.
- Invoke skills via the exact slash form: /superpowers:<skill-name>.

Authority:
- If a skill's HARD-GATE or Iron Law applies, you do not have a choice — follow it.
- Do not skip brainstorming's design-approval gate, TDD's failing-test-first law,
  systematic-debugging's root-cause-first law, or verification-before-completion's
  fresh-evidence law, even under time pressure.
- Do not invoke an implementation skill before a design is approved.
- Do not claim "done/fixed/passing" without running the verification command in the same message.

Scope:
- Own exactly one bounded slice of work per session/task.
- Follow each skill's terminal-state rule (e.g. brainstorming's only next skill is
  writing-plans) — do not freelance a different next step.
- Report blockers, ambiguity, and 3+ failed fix attempts (architecture question) instead of guessing.

Execution:
- Prefer --resume over a new session when continuing a staged workflow — design approval,
  plan choice, and per-task review loops depend on session continuity.
- If a worktree is required, prefer detecting existing isolation (using-git-worktrees Step 0)
  over creating a new one when already inside one.
- Keep diffs small, reversible, reviewable. Do not revert unrelated user changes. Do not add
  dependencies unless explicitly requested.

Skill routing:
- Creative/feature/behavior work before any code: brainstorming.
- Isolation before execution: using-git-worktrees.
- Spec/requirements to multi-step plan: writing-plans.
- Same-session task execution with review loops: subagent-driven-development.
- Separate-session/no-subagent execution: executing-plans.
- Any implementation: test-driven-development.
- Any bug/test failure/unexpected behavior: systematic-debugging (before proposing fixes).
- 2+ independent, non-overlapping failures: dispatching-parallel-agents.
- Task/feature/pre-merge review: requesting-code-review.
- Incoming feedback: receiving-code-review (verify before implementing, no performative agreement).
- Any completion/success claim: verification-before-completion (gate, not optional).
- Implementation complete + tests green: finishing-a-development-branch.

Verification:
- Run the narrowest meaningful checks first, then the full suite before declaring done.
- Report exact commands and outcomes, not impressions.

Output:
- Be concise. Lead with the result.
- Include changed files, verification commands+output, and remaining risks.
- If blocked, name the blocker and the next recoverable step.
```

## 6. Few-Shot Examples

**1. 신규 기능 — 전체 체인 시작**
```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/superpowers:brainstorming 결제 실패 시 재시도 로직 설계를 시작해줘' < /dev/null
```
Expected: 컨텍스트 탐색 → 한 번에 한 질문 → 접근법 제시 → 섹션별 승인 → 스펙 작성·커밋 → self-review → 사용자 리뷰 요청. session_id 보관.

**2. 설계 승인 → 플랜 (resume)**
```bash
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '스펙 승인. writing-plans로 구현 계획 작성해줘' < /dev/null
```
Expected: bite-sized 태스크 계획 작성, 실행 방식(subagent-driven-development vs executing-plans) 질문으로 종료.

**3. 플랜 실행 (subagent-driven, resume)**
```bash
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json 'subagent-driven-development로 실행해줘' < /dev/null
```
Expected: 태스크별 implementer→TDD→task reviewer(spec+quality)→fix loop→원장 갱신→whole-branch 리뷰.

**4. 버그 발견 — systematic-debugging 우선**
```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/superpowers:systematic-debugging 인증 변경 후 실패하는 테스트의 근본 원인을 찾아줘' < /dev/null
```
Expected: fix 제안 전 4단계 완주. 3회 이상 실패 시 아키텍처 문제로 정지·질의.

**5. 완료 게이트 → 마무리 (resume)**
```bash
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json 'verification-before-completion 기준으로 증거 확인 후, finishing-a-development-branch로 마무리해줘' < /dev/null
```
Expected: 검증 커맨드 실행 증거 없이는 완료 주장 금지 → 테스트 재검증 → 정확히 4개 옵션(merge/PR/유지/discard) 제시 → 선택 실행 → 옵션 1·4만 워크트리 정리.

## 7. Practical Command Cheatsheet

```bash
# 최초 — 브레인스토밍
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/superpowers:brainstorming <주제>' < /dev/null

# resume — 플랜 작성 / 실행 / 별도세션 실행
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '/superpowers:writing-plans 계획 작성' < /dev/null
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '/superpowers:subagent-driven-development 실행' < /dev/null
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '/superpowers:executing-plans 실행' < /dev/null

# 버그 — 근본원인 우선
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/superpowers:systematic-debugging <증상>' < /dev/null

# 독립 실패 병렬 조사 / 리뷰 요청 / 완료 게이트 / 마무리
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '/superpowers:dispatching-parallel-agents <실패목록>' < /dev/null
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '/superpowers:requesting-code-review <BASE>..<HEAD>' < /dev/null
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '/superpowers:verification-before-completion 증거확인' < /dev/null
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '/superpowers:finishing-a-development-branch' < /dev/null

# 결과를 파일로 / stdin 프롬프트
~/.headroom/claude-hr.sh -p --resume <sid> --output-format json '...' < /dev/null > result.json
cat prompt.md | ~/.headroom/claude-hr.sh -p --resume <sid> --output-format json - < /dev/null

# YOLO (격리 worktree 전용)
git worktree add .worktrees/sp-yolo -b sp-yolo
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  -C .worktrees/sp-yolo --dangerously-skip-permissions \
  '/superpowers:subagent-driven-development <plan-path> 실행' < /dev/null
```

## 8. Final Operating Rule

When in doubt:

1. brainstorming 없이 구현 스킬로 바로 가지 않는다 — 설계 승인이 게이트다.
2. 버그/테스트실패는 systematic-debugging의 근본원인 조사 없이 fix하지 않는다.
3. 구현은 항상 test-driven-development(RED 먼저)로 한다.
4. 워크플로 전환마다 `--resume`으로 같은 세션을 잇는다 — 새 세션 시작은 컨텍스트 연속성을 깬다.
5. "완료/통과/고쳐짐"을 말하기 전에는 이 메시지 안에서 직접 검증 커맨드를 실행한 증거가 있어야 한다.
6. YOLO는 격리 worktree 안에서만, 최종 diff와 검증 증거를 확보한 뒤에만 완료로 보고한다.
7. 각 스킬의 terminal state(다음에 호출해야 할 유일한 스킬)를 임의로 바꾸지 않는다.
