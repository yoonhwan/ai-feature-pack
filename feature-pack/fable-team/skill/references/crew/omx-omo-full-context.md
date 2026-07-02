# OMO-on-OMX Full Context

이 문서는 OMO 전용 크루원, 비대화형 실행, YOLO 실행, 스킬 라우팅, few-shot 프롬프트를 한 번에 전달하기 위한 운영 컨텍스트다.

핵심 관점:

- OMO가 메인 기능 레이어다. 실제로 "무엇을 잘하게 할 것인가"는 OMO 스킬이 결정한다.
- OMX는 OMO를 Codex 위에서 실행, 주입, 팀화, 상태화하는 런타임/런처다.
- `omx exec '$omo:skill ...'`가 비대화형 자동화의 기본 형태다.
- `omx team`은 장기/병렬 크루 런타임이고, attached tmux OMX CLI 환경에서 가장 잘 맞는다.
- `--dangerously-bypass-approvals-and-sandbox` 또는 OMX alias인 `--madmax`/`--yolo` 계열은 격리된 worktree/컨테이너에서만 쓴다.

## 1. Mental Model

### OMO

OMO는 목적별 고성능 스킬 모음이다. 사용자는 `$omo:<skill>` 형태로 특정 작업 표면을 명시할 수 있다.

예:

```bash
omx exec -C /repo '$omo:frontend 대시보드 UI를 개선하고 visual QA까지 해줘'
omx exec -C /repo '$omo:debugging 실패하는 테스트의 원인을 찾고 수정해줘'
omx exec -C /repo '$omo:programming TypeScript 타입 오류를 고쳐줘'
```

OMO의 장점은 "프롬프트 하나"가 아니라 각 분야별 절차와 품질 게이트가 스킬에 들어 있다는 점이다. 예를 들어 `$omo:frontend`는 디자인 시스템, visual QA, 성능, 접근성까지 강제하고, `$omo:debugging`은 가설 기반 디버깅 루프를 강제한다.

### OMX

OMX는 실행기다.

주요 역할:

- Codex CLI 실행
- `AGENTS.md`/오버레이/스킬 주입
- 비대화형 실행 래핑
- tmux 기반 팀/크루 런타임
- HUD, 상태, trace, notepad, wiki, project-memory
- hooks, setup, doctor, cleanup
- native agent 관리

즉 "기능은 OMO, 운용은 OMX"로 보면 된다.

## 2. Current Local OMX Surface

현재 로컬에서 확인된 버전:

```text
oh-my-codex v0.15.1
Node.js v26.3.0
Platform: darwin arm64
```

현재 로컬 `omx list --json` 기준:

- packaged OMX skills: 42
- native agent prompts: 30
- active skills: 27
- active agents: 18
- core skills: `autopilot`, `ralph`, `ultrawork`, `team`, `ralplan`

주의:

- `omx list`는 OMX 패키지 관점의 목록이다.
- `$omo:*` 스킬은 Codex plugin skill surface에 노출되는 OMO 플러그인 스킬이다.
- OMO와 OMX는 함께 쓰지만, 문서화할 때는 OMO를 작업 기능 레이어로, OMX를 실행 레이어로 분리하면 이해가 쉽다.

## 3. OMO Feature Catalog

아래는 OMO 쪽을 메인으로 본 기능 분류다.

### 3.1 UI / Frontend / Visual Quality

대표 스킬:

- `$omo:frontend`
- `$omo:visual-qa`

할 수 있는 일:

- React/UI/UX/디자인/레이아웃/스타일링 작업
- 디자인 시스템 기반 구현
- `DESIGN.md` 생성 또는 준수
- 브랜드 레퍼런스 기반 UI 변환
- responsive QA: mobile/tablet/desktop
- Playwright 기반 visual QA
- Lighthouse/Core Web Vitals/접근성 점검
- "AI스럽고 밋밋한 UI" 제거

예:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:frontend 현재 랜딩 페이지를 Stripe 수준의 premium SaaS 톤으로 리디자인하고 visual QA까지 해줘'
```

### 3.2 Runtime Debugging

대표 스킬:

- `$omo:debugging`

할 수 있는 일:

- crash, silent failure, wrong response, flaky async, stuck process 원인 분석
- 최소 3개 가설 수립
- 병렬 조사
- 실패 재현
- root cause 확정
- regression test 또는 실행 검증
- 최소 수정

예:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:debugging npm test 실패 원인을 찾고 최소 수정으로 고쳐줘'
```

### 3.3 Programming / Strict Implementation

대표 스킬:

- `$omo:programming`

적용 언어:

- Python
- TypeScript / TSX
- Rust
- Go

할 수 있는 일:

- 타입 안전한 구현
- 기존 패턴 준수
- modern toolchain 기반 검증
- `any`, `unwrap`, `panic`, `@ts-ignore` 같은 회피 금지
- tests/typecheck/lint 기반 확인

예:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:programming src/api의 타입 오류를 고치고 테스트를 실행해줘'
```

### 3.4 Refactor / Cleanup / Anti-Slop

대표 스킬:

- `$omo:refactor`
- `$omo:remove-ai-slops`
- `$ai-slop-cleaner`

할 수 있는 일:

- 과도한 추상화 제거
- 중복/분기/불필요한 래퍼 정리
- 큰 파일 분리
- 행동을 고정한 뒤 cleanup
- "AI가 만든 듯한" 코드 냄새 제거

예:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:remove-ai-slops 최근 변경분에서 AI slop을 제거하고 기존 동작은 유지해줘'
```

### 3.5 Planning / Execution Plan / Work Start

대표 스킬:

- `$omo:ulw-plan`
- `$omo:start-work`
- `$ralplan`
- `$plan`

할 수 있는 일:

- 구현 전 decision-complete plan 작성
- ambiguous scope 정리
- 테스트 전략 포함
- `.omo/plans` 기반 실행
- plan 승인 이후 worker가 바로 실행할 수 있는 형태로 분해

예:

```bash
omx exec -C /repo \
  '$omo:ulw-plan 결제 리팩터링을 위한 구현 계획과 테스트 계획을 작성해줘'

omx exec -C /repo -s workspace-write -a never \
  '$omo:start-work .omo/plans/payment-refactor.md 실행해줘'
```

### 3.6 Review / QA / Verification

대표 스킬:

- `$omo:review-work`
- `$omo:visual-qa`
- `$code-review`
- `$security-review`

할 수 있는 일:

- 구현 후 다각도 검증
- 보안/품질/QA/컨텍스트 마이닝 관점 리뷰
- visual QA
- regression risk 확인
- missing tests 확인

예:

```bash
omx exec -C /repo \
  '$omo:review-work 최근 변경사항을 목표/품질/보안/QA 관점에서 검증해줘'
```

### 3.7 Git / Session / History

대표 스킬:

- `$omo:git-master`
- `$omo:coding-agent-sessions`

할 수 있는 일:

- git history investigation
- blame, log, reflog, bisect 관점 조사
- coding-agent session transcript 검색
- 과거 Codex/Claude/OpenCode/Gemini 등 agent log 재구성

예:

```bash
omx exec -C /repo \
  '$omo:git-master 이 validation 함수가 언제 왜 추가됐는지 찾아줘'

omx exec -C /repo \
  '$omo:coding-agent-sessions 어제 이 프로젝트에서 frontend 관련 Codex 세션을 찾아 요약해줘'
```

### 3.8 LSP / AST / Code Intelligence

대표 스킬:

- `$omo:lsp`
- `$omo:lsp-setup`
- `$omo:ast-grep`

할 수 있는 일:

- language-server diagnostics
- definition/reference lookup
- rename safety
- AST-aware search/rewrite
- codemod

예:

```bash
omx exec -C /repo \
  '$omo:lsp src/components/App.tsx의 diagnostics와 reference impact를 확인해줘'

omx exec -C /repo -s workspace-write -a never \
  '$omo:ast-grep console.log 호출을 logger.info로 안전하게 바꿔줘'
```

### 3.9 OMO / LazyCodex / Codex Tooling Maintenance

대표 스킬:

- `$omo:lcx-doctor`
- `$omo:lcx-report-bug`
- `$omo:lcx-contribute-bug-fix`
- `$doctor`

할 수 있는 일:

- LazyCodex / Codex CLI 설치 상태 진단
- 최신 소스와 로컬 설치 비교
- bug issue/PR routing
- Codex/OMO/LazyCodex 관련 결함 fix workflow

예:

```bash
omx exec -C /repo \
  '$omo:lcx-doctor 현재 LazyCodex/Codex 설치 상태를 최신 기준으로 점검해줘'
```

### 3.10 Web / Research / Browsing

대표 스킬:

- `$omo:ultimate-browsing`
- `$autoresearch`
- `perplexity-direct-api`

할 수 있는 일:

- 일반 fetch가 막힌 웹 접근
- WAF/403/Cloudflare/JS-only fallback
- 공식 문서/외부 fact 확인
- Perplexity Direct API 기반 current facts

예:

```bash
omx exec -C /repo \
  '$omo:ultimate-browsing 일반 fetch로 접근 안 되는 문서를 읽고 요약해줘'
```

## 4. OMX Runtime Feature Catalog

OMO가 "기능"이라면 OMX는 "운영 표면"이다.

### 4.1 Interactive Launch

```bash
omx
omx --direct
omx --tmux
omx --yolo
omx --madmax
omx --high
omx --xhigh
```

의미:

- `omx`: 기본 interactive leader 실행
- `--direct`: tmux/HUD 없이 직접 실행
- `--tmux`: detached tmux leader 실행
- `--yolo`: Codex yolo launch shorthand
- `--madmax`: approvals/sandbox bypass alias
- `--high`, `--xhigh`: reasoning effort 상향

### 4.2 Non-Interactive Execution

```bash
omx exec -C /repo '$omo:frontend UI를 개선해줘'
```

권장 기본형:

```bash
omx exec -C /repo \
  -s workspace-write \
  -a never \
  '$omo:programming 타입 오류를 고쳐줘'
```

읽기 전용:

```bash
omx exec -C /repo \
  -s read-only \
  '$analyze 인증 플로우를 분석해줘'
```

순정 Codex:

```bash
codex exec -C /repo 'README를 요약해줘'
```

OMO/AGENTS/overlay 주입이 필요하면 `codex exec`보다 `omx exec`를 선호한다.

### 4.3 Output and Logging

마지막 응답 저장:

```bash
omx exec -C /repo -o result.md \
  '$omo:review-work 최근 변경사항을 검증해줘'
```

JSONL 이벤트 로그:

```bash
omx exec -C /repo --json \
  '$omo:debugging 빌드 실패를 고쳐줘' > run.jsonl
```

stdin 프롬프트:

```bash
cat prompt.md | omx exec -C /repo -
```

또는:

```bash
omx exec -C /repo - < prompt.md
```

### 4.4 Inject Follow-Up Context

실행 중인 non-interactive session에 추가 지시를 넣을 수 있다.

```bash
omx exec inject <session-id> --prompt '추가 조건: public API는 깨지 말고 변경 후 테스트 결과를 보고해.'
```

용도:

- 긴 작업 중 우선순위 조정
- 금지 조건 추가
- 새 로그/스택트레이스 투입
- acceptance criteria 보강

### 4.5 Team / Crew Runtime

```bash
omx team 3:executor "fix failing tests"
omx team status <team-name>
omx team status <team-name> --json
omx team await <team-name> --timeout-ms 600000 --json
omx team resume <team-name>
omx team shutdown <team-name> --force
```

주의:

- `omx team`은 tmux-runtime surface다.
- Codex App/outside-tmux에서는 shell에서 OMX CLI를 먼저 띄우는 방식이 더 맞다.
- 작은 병렬 fanout은 native subagent가 낫고, 장기/상태/워크트리/worker coordination이 필요하면 `omx team`이 맞다.
- 팀 worker는 자동 전용 worktree를 쓸 수 있다.

### 4.6 Native Agent Management

```bash
omx agents list
omx agents list --scope user
omx agents list --scope project
omx agents add omo-frontend-executor --scope project
omx agents edit omo-frontend-executor --scope project
omx agents remove omo-frontend-executor --scope project --force
```

용도:

- OMO 전용 크루원 역할 프롬프트 저장
- 프로젝트별 specialized agent 정의
- 반복 실행할 role contract 고정

### 4.7 Setup / Doctor / Hooks / State

```bash
omx setup
omx setup --scope project --plugin
omx doctor
omx doctor --team
omx cleanup
omx hooks status
omx tmux-hook status
omx status
omx cancel
omx trace
omx hud --watch
omx reasoning high
```

용도:

- 설치/업데이트/헬스체크
- hooks/HUD/team runtime 확인
- 현재 mode/state 확인
- 취소/정리

## 5. Safety Modes

### Read-only

조사만:

```bash
omx exec -C /repo -s read-only \
  '$analyze 현재 인증 로직을 설명해줘'
```

### Workspace Write

일반 자동 수정:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:programming 타입 오류를 고쳐줘'
```

### Danger Full Access

더 넓은 파일 접근이 필요한 경우:

```bash
omx exec -C /repo -s danger-full-access -a never \
  '$omo:debugging 로컬 통합 테스트 실패를 고쳐줘'
```

### YOLO / Madmax

최대 자동화:

```bash
omx exec -C /repo \
  --dangerously-bypass-approvals-and-sandbox \
  '$omo:frontend UI를 개선하고 검증까지 끝내줘'
```

또는 interactive launch에서:

```bash
omx --yolo
omx --madmax
```

권장 YOLO 패턴:

```bash
git worktree add ../repo-yolo -b omo-yolo
omx exec -C ../repo-yolo \
  --dangerously-bypass-approvals-and-sandbox \
  '$omo:debugging 빌드 실패를 끝까지 고쳐줘'
```

YOLO 사용 조건:

- disposable worktree
- credentials/production env 미노출
- destructive command 금지 조건 명시
- 최종 diff 검토
- tests/build/visual QA evidence 확보

## 6. OMO Crew Member General Contract

OMO 전용 크루원에게 주입할 일반 컨텍스트:

```text
You are an OMO-specialized Codex crew member running under OMX.

Primary model:
- OMO is the main capability layer.
- OMX is the execution and orchestration runtime.
- Use explicit $omo:<skill> routing whenever the task maps to a skill.

Authority:
- Follow AGENTS.md first.
- Load the relevant SKILL.md completely before acting.
- Do not bypass skill gates.
- Do not freestyle when a skill provides a workflow.

Scope:
- Own exactly one bounded slice of work.
- Stay inside assigned files, modules, or investigation scope.
- Do not silently expand scope.
- Report blockers, shared-file conflicts, and missing authority.

Execution:
- Inspect before editing.
- Prefer existing patterns and utilities.
- Keep diffs small, reversible, and reviewable.
- Do not revert unrelated user changes.
- Do not add dependencies unless explicitly requested.
- Verify before claiming completion.

Skill routing:
- UI/frontend/design/performance/accessibility: $omo:frontend.
- Visual/browser verification: $omo:visual-qa.
- Runtime bug/crash/wrong behavior: $omo:debugging.
- Python/Rust/TypeScript/Go implementation: $omo:programming.
- Refactor/cleanup: $omo:refactor.
- AI slop cleanup: $omo:remove-ai-slops.
- Post-implementation validation: $omo:review-work.
- Git history or commit work: $omo:git-master.
- LSP diagnostics/references/rename: $omo:lsp.
- AST search/rewrite/codemod: $omo:ast-grep.
- Local agent session reconstruction: $omo:coding-agent-sessions.

Verification:
- Run the narrowest meaningful checks first.
- For frontend, drive real browser visual QA.
- For code, run lint/typecheck/tests where applicable.
- Report exact commands and outcomes.

Output:
- Be concise.
- Lead with the result.
- Include changed files, verification, and remaining risks.
- If blocked, name the blocker and the next recoverable step.
```

## 7. Ready-to-Run Context Message

아래는 `omx exec`에 그대로 넣을 수 있는 컨텍스트 메시지다.

```bash
omx exec -C /repo -s workspace-write -a never "$(cat <<'EOF'
You are an OMO-specialized Codex crew member running under OMX.

OMO is the main capability layer. OMX is only the launcher/orchestrator.
Use explicit OMO skill routing for this task.
Load the relevant SKILL.md before acting.

Rules:
- Follow AGENTS.md first.
- Inspect the repo before editing.
- Keep diffs small and reversible.
- Do not revert unrelated user changes.
- Do not add dependencies unless explicitly requested.
- Verify before claiming completion.
- Report changed files, verification commands, and remaining risks.

Skill map:
- UI/frontend/design/performance/accessibility -> $omo:frontend
- Browser/visual verification -> $omo:visual-qa
- Runtime failures -> $omo:debugging
- TS/Python/Rust/Go implementation -> $omo:programming
- Cleanup/refactor -> $omo:refactor
- AI slop cleanup -> $omo:remove-ai-slops
- Post-implementation validation -> $omo:review-work
- Git history -> $omo:git-master
- LSP/code intelligence -> $omo:lsp
- AST codemods -> $omo:ast-grep

Task:
<PUT TASK HERE>
EOF
)"
```

YOLO version:

```bash
git worktree add ../repo-omo-yolo -b omo-yolo

omx exec -C ../repo-omo-yolo \
  --dangerously-bypass-approvals-and-sandbox \
  "$(cat <<'EOF'
You are an OMO-specialized Codex crew member running under OMX in an isolated worktree.

OMO is the main capability layer. OMX is the launcher/orchestrator.
Use the relevant $omo:<skill> explicitly and load its SKILL.md before acting.

Hard constraints:
- Do not touch production services.
- Do not delete user data.
- Do not rewrite git history.
- Do not revert unrelated user changes.
- Keep changes reviewable.
- Verify with tests/build/visual QA as applicable.

Task:
<PUT TASK HERE>
EOF
)"
```

## 8. Few-Shot Examples

### Few-shot 1: Frontend Polish

User intent:

```text
Make this dashboard feel less generic and more like a polished operational SaaS product.
```

Command:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:frontend Improve the dashboard into a polished operational SaaS UI. Use or create DESIGN.md as required. Verify responsive states and visual QA.'
```

Expected behavior:

- Loads frontend skill.
- Checks whether `DESIGN.md` exists.
- Reads existing UI/component system.
- Creates/updates design tokens if needed.
- Implements UI changes.
- Runs build and visual QA where possible.
- Reports changed files and verification.

### Few-shot 2: Debugging

User intent:

```text
Tests are failing after the auth change. Find the root cause and fix it.
```

Command:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:debugging Tests are failing after the auth change. Reproduce, identify root cause, fix minimally, and verify.'
```

Expected behavior:

- Forms multiple hypotheses.
- Runs failing tests.
- Reads relevant code paths.
- Fixes root cause, not symptom.
- Verifies with targeted tests.

### Few-shot 3: Strict TypeScript Fix

Command:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:programming Fix TypeScript errors without using any, ts-ignore, or weakening types. Run typecheck afterward.'
```

Expected behavior:

- Loads programming skill.
- Fixes types structurally.
- Avoids suppression.
- Runs typecheck.

### Few-shot 4: Anti-Slop Cleanup

Command:

```bash
omx exec -C /repo -s workspace-write -a never \
  '$omo:remove-ai-slops Clean AI-generated code smells from the current branch while preserving behavior. Add regression coverage only where needed.'
```

Expected behavior:

- Identifies slop categories.
- Locks behavior if needed.
- Removes unnecessary abstraction/duplication.
- Keeps diff narrow.
- Verifies behavior.

### Few-shot 5: Post-Implementation Review

Command:

```bash
omx exec -C /repo \
  '$omo:review-work Review the current branch after implementation. Check goal fit, quality, security, QA, and missing tests.'
```

Expected behavior:

- Runs review orchestration.
- Produces findings first.
- Identifies residual risks.
- Does not modify unless asked.

### Few-shot 6: Long-Running Crew

Command:

```bash
omx team 3:executor "Split the frontend redesign into design-system extraction, component implementation, and visual QA. Coordinate through OMX team state."
```

Expected behavior:

- Creates tmux-backed team workers.
- Uses worktrees where needed.
- Tracks worker status.
- Leader integrates and verifies.

## 9. What Works Best

Use OMO + OMX for:

- high-quality frontend implementation
- bug diagnosis and repair
- strict typed programming
- cleanup/refactor/deslop
- post-implementation review
- visual QA
- codebase research
- git history investigation
- local agent session reconstruction
- multi-agent/team execution

Use plain `codex exec` for:

- simple one-off text/code questions
- tasks where OMO skill injection is not needed
- scripts that must avoid OMX overlays/hooks

Use `omx exec` for:

- all OMO skill tasks
- AGENTS.md-aware automation
- non-interactive project work
- output/log capture
- context injection

Use `omx team` for:

- durable multi-worker tasks
- worktree-isolated parallel work
- long-running coordinated delivery
- tasks where workers need shared state and handoff

## 10. Practical Command Cheatsheet

```bash
# OMO frontend
omx exec -C /repo -s workspace-write -a never '$omo:frontend Improve the UI and verify visually.'

# OMO debugging
omx exec -C /repo -s workspace-write -a never '$omo:debugging Reproduce and fix the failing test.'

# OMO programming
omx exec -C /repo -s workspace-write -a never '$omo:programming Fix TypeScript errors and run typecheck.'

# OMO refactor
omx exec -C /repo -s workspace-write -a never '$omo:refactor Simplify src/auth while preserving behavior.'

# OMO review
omx exec -C /repo '$omo:review-work Review current branch and report findings first.'

# OMO visual QA
omx exec -C /repo '$omo:visual-qa Verify localhost:3000 at 375, 768, and 1280px.'

# Read-only analysis
omx exec -C /repo -s read-only '$analyze Explain the auth flow with file references.'

# JSONL logs
omx exec -C /repo --json '$omo:debugging Fix build failure.' > run.jsonl

# Last message output
omx exec -C /repo -o result.md '$omo:review-work Review changes.'

# Inject follow-up
omx exec inject <session-id> --prompt 'New constraint: do not change public API.'

# Interactive direct
omx --direct

# Interactive tmux
omx --tmux

# Team
omx team 3:executor "Fix failing tests in parallel."

# Doctor
omx doctor
omx doctor --team

# Native agents
omx agents list
omx agents add omo-frontend-executor --scope project
omx agents edit omo-frontend-executor --scope project
```

## 11. Final Operating Rule

When in doubt:

1. Pick the OMO skill that owns the domain.
2. Run it through `omx exec` for automation.
3. Use `-s workspace-write -a never` for normal local edits.
4. Use YOLO only inside an isolated worktree.
5. Use `omx team` only when durable parallel coordination is worth the overhead.
6. Verify before claiming completion.

