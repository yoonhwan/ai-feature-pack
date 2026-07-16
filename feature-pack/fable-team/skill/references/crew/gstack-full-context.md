# gstack Crew Full Context

이 문서는 gstack 크루원을 `claude -p` 콘솔 분리 실행으로 구동하기 위한 운영 컨텍스트다. gstack 스킬 카탈로그, 실행 원형, 안전 모드, few-shot 프롬프트를 한 번에 전달한다.

핵심 관점:

- gstack은 사용자 레벨 스킬 스위트다. 스킬 본체는 `~/.claude/skills/gstack/`, 개별 진입점(`/qa`, `/ship` 등)은 `~/.claude/skills/<name>/`.
- 진입점은 라우터 `_gstack-command`(`name: gstack`) — 특정 스킬을 명시 안 하면 도메인 규칙표로 위임한다.
- 크루는 **현재 세션 Skill 도구를 호출하지 않는다.** `claude -p '/스킬 ...'`로 완전히 분리된 콘솔 프로세스를 띄운다 — 컨텍스트 격리, 독립 session_id, `--resume`으로 이어가기 가능.
- 각 SKILL.md는 preamble(텔레메트리/버전체크/gbrain sync)과 본문 워크플로우로 구성된다. `claude -p`가 스킬을 로드하면 preamble도 자동 실행되므로 크루원이 신경 쓸 필요 없다.
- 공식: https://github.com/garrytan/gstack

## 1. Mental Model

gstack은 "무엇을 검증/생성/출시할 것인가"를 스킬이 결정하는 체크리스트 기반 워크플로우 레이어다. OMO/OMX와 달리 별도 실행 런타임이 없다 — **`claude -p` 자체가 실행기**다.

- gstack 스킬 = 기능 계층 (무엇을 할지 + 게이트)
- `claude -p` = 실행 계층 (분리 프로세스, session_id, resume, 권한 모드)
- 대부분 스킬은 `~/.gstack/projects/{repo_slug}/`에 learnings/timeline/artifacts를 남겨 세션이 끊겨도 다음 실행에서 재사용된다.

## 2. Current Local gstack Surface

```text
gstack VERSION: 1.58.5.0
SKILL.md count (gstack/*): 54
상태 디렉토리: ~/.gstack/ (projects/, gbrain-detection.json, .gbrain-local-status-cache.json)
```

- `~/.claude/skills/gstack/`는 스킬 본체(bin/, lib/) 실제 저장소.
- `~/.claude/skills/<skill-name>/`는 개별 SKILL.md 진입점 dotdir, 대부분 `drwx------`(비공개).
- `~/.gstack/projects/`는 현재 비어 있음 — 스킬 최초 실행 시 프로젝트 슬러그 디렉토리가 생성된다.

## 3. gstack Feature Catalog

### 3.1 QA / 브라우저 테스트
`/qa`(테스트+수정+atomic commit, Quick/Standard/Exhaustive), `/qa-only`(리포트만), `/browse`(~100ms 헤드리스 조작·스크린샷·반응형), `/benchmark`(성능 회귀), `/canary`(배포후 모니터링), `/setup-browser-cookies`(인증 세션), `/connect-chrome`(실브라우저), `/scrape`→`/skillify`(추출→codify), `/pair-agent`(원격 에이전트 브라우저 공유)

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/qa 결제 플로우를 Standard tier로 테스트하고 버그를 고쳐줘' < /dev/null
```

### 3.2 디버깅 / 근본원인 조사
`/investigate` — crash/silent failure/wrong response 근본원인 조사, freeze 훅 연동, gbrain으로 과거 조사 이력 참조.

```bash
claude -p --permission-mode plan --output-format json \
  '/investigate 세션이 5분 뒤 끊기는 원인을 조사만 해줘' < /dev/null
```

### 3.3 리뷰 / 출시 파이프라인
`/review`(diff의 SQL/LLM경계/부작용 구조 이슈), `/ship`(병합→테스트→리뷰→VERSION bump→CHANGELOG→커밋→push→PR), `/land-and-deploy`(`/ship` 이후 머지+CI대기+canary), `/landing-report`(VERSION 슬롯 읽기전용 대시보드), `/codex`(Codex CLI 독립 리뷰/적대적 챌린지)

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/ship 현재 브랜치를 리뷰하고 테스트 통과하면 PR까지 생성해줘' < /dev/null
```

### 3.4 디자인
`/design-review`(라이브 사이트 시각 불일치·AI-slop 수정), `/design-consultation`(디자인 시스템 제안+프리뷰), `/design-shotgun`(변형 다수 생성+비교보드), `/design-html`(프로덕션급 HTML/CSS 최종화), `/ios-design-review`(실기기 HIG 감사)

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/design-review 랜딩 페이지 시각 일관성을 점검하고 고쳐줘' < /dev/null
```

### 3.5 기획 / 계획 리뷰 게이트
`/office-hours`(브레인스토밍, YC 모드), `/spec`(모호한 의도→5단계 실행 spec/이슈), `/plan-ceo-review`(전략/스코프), `/plan-eng-review`(아키텍처 대화형 리뷰), `/plan-design-review`(계획 디자인 0-10), `/plan-devex-review`(계획 DX, EXPANSION/POLISH/TRIAGE), `/devex-review`(라이브 DX 실측), `/autoplan`(4개 리뷰 순차 자동 실행), `/plan-tune`(질문 민감도 튜닝)

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  '/plan-eng-review .omo/plans/payment-refactor.md 아키텍처를 검토해줘' < /dev/null
```

### 3.6 보안
`/cso` — secrets/의존성 공급망/CI-CD/LLM보안/OWASP Top 10+STRIDE, daily(8/10 게이트)/comprehensive(2/10) 2모드.

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  '/cso 이번 배포 전 daily 보안 감사를 실행해줘' < /dev/null
```

### 3.7 문서화
`/document-generate`(Diataxis 프레임워크 신규 문서), `/document-release`(배포 후 diff 대조 문서 동기화), `/make-pdf`(마크다운→출판급 PDF), `/diagram`(설명/mermaid→다이어그램 3종)

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/document-release 최근 배포 내용을 문서에 반영해줘' < /dev/null
```

### 3.8 컨텍스트 / 세션 기억
`/context-save`(구 `/checkpoint`, git상태+결정+잔여작업 캡처), `/context-restore`(최근 저장 상태 복원), `/learn`(학습 리뷰/검색/정리), `/retro`(주간 회고)

```bash
~/.headroom/claude-hr.sh -p --resume <session-id> --output-format json '/context-save 진행상황을 저장해줘' < /dev/null
```

### 3.9 안전 모드
`/careful`(파괴적 명령 사전 경고, Bash 훅), `/freeze`(디렉토리 밖 Edit/Write 차단), `/unfreeze`(해제), `/guard`(careful+freeze 동시)

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/guard src/payments만 건드리며 결제 로직을 고쳐줘' < /dev/null
```

### 3.10 셋업 / 운영
`/setup-deploy`(배포 플랫폼 감지+CLAUDE.md 기록), `/setup-gbrain`/`/sync-gbrain`(gbrain 설치·재인덱싱), `/gstack-upgrade`(버전 업그레이드), `/health`(타입체크/린트/테스트/데드코드 종합 0-10 점수)

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  '/health 현재 코드베이스 건강도 점수를 확인해줘' < /dev/null
```

### 3.11 iOS
`/ios-qa`(실기기 USB, 비전 기반 스크린샷→분석→행동 루프), `/ios-fix`(`/ios-qa` 버그→수정→재빌드→검증 자동), `/ios-design-review`(실기기 HIG 감사), `/ios-clean`(DebugBridge 제거), `/ios-sync`(계측 최신화)

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/ios-qa 로그인부터 결제까지 실기기에서 QA 해줘' < /dev/null
```

## 4. Execution Runtime & Safety Modes

gstack엔 OMX 같은 런타임이 없다. 크루는 **`claude -p` 콘솔 분리 실행**으로 스킬을 구동한다 — 컨텍스트가 분리되어 크루원 간 간섭이 없고, `--resume`으로 동일 세션을 이어갈 수 있다.

**최초 실행 (session_id 회수):**
```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/qa <작업>' < /dev/null
```
`--output-format json`이 최종 응답 + `session_id`를 반환한다. 오케스트레이터는 이를 파싱해 크루 상태에 기록.

**후속 실행 (세션 승계):**
```bash
~/.headroom/claude-hr.sh -p --resume <session-id> --output-format json '<후속 지시>' < /dev/null
```
동일 세션 컨텍스트(대화 이력, 로드된 SKILL.md, 진행 상태)를 이어받는다. 추가 지시·새 로그 투입에 사용.

**조사만 (읽기 전용):**
```bash
claude -p --permission-mode plan --output-format json \
  '/investigate <원인>을 조사만 해줘 (수정 금지)' < /dev/null
```

**YOLO (격리 worktree 전용):**
```bash
git worktree add ../repo-gstack-yolo -b gstack-yolo
claude -p --dangerously-skip-permissions --output-format json \
  -C ../repo-gstack-yolo '/ship 빌드 실패를 끝까지 고치고 배포해줘' < /dev/null
```
조건: disposable worktree, credentials/production env 미노출, destructive command 금지를 프롬프트에 명시, 최종 diff 검토, tests/build/QA 증거 확보.

**항상 붙는 원형 값:** 모델 `claude-sonnet-4-6` 고정 · effort `high` 고정 · `--output-format json`(session_id 회수) · `< /dev/null`(stdin 미닫음 hang 방지 — codex exec 트러블슈팅과 동일 원인).

## 5. gstack Crew Member General Contract

```text
You are a gstack-specialized Claude Code crew member running detached via `claude -p`.

Primary model:
- gstack is a suite of slash-command skills (/qa, /ship, /investigate, /review, ...).
- Each skill's SKILL.md defines its own workflow, quality gates, and STOP points,
  loaded automatically when you invoke its slash command in the prompt.
- Invoke the skill explicitly by name; do not freestyle when a skill covers the task.

Authority:
- Follow the skill's checklist and gates. Do not skip STOP points or approval gates.
- If headless/spawned and the skill asks via AskUserQuestion, auto-choose the
  recommended option and report the choice.

Scope:
- Own exactly one bounded slice of work per `claude -p` invocation.
- Do not silently expand scope across skills (e.g., don't run /ship mid-/qa).
- Report blockers, shared-file conflicts, and missing authority.

Execution:
- Inspect before editing. Prefer existing patterns. Keep diffs small and reversible.
- Do not revert unrelated user changes. Do not add dependencies unless requested.
- Verify before claiming completion using the skill's own verification step.

Skill routing:
- Testing/bugs on a live app -> /qa (fix) or /qa-only (report only).
- Browser interaction/screenshot -> /browse.
- Runtime bug/crash/root cause -> /investigate.
- Diff review -> /review. Ship/PR/deploy -> /ship, then /land-and-deploy.
- Visual/design polish -> /design-review. Plan-stage architecture -> /plan-eng-review.
- Security audit -> /cso.
- Docs after shipping -> /document-release; docs from scratch -> /document-generate.
- Save/restore session -> /context-save, /context-restore.

Output:
- Be concise. Lead with the result.
- Include changed files, verification commands/output, remaining risks.
- Report session_id (from --output-format json) so the orchestrator can --resume.
```

## 6. Few-Shot Examples

**1) QA + Fix**
```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/qa Test the signup flow (Standard tier). Fix bugs found, commit each fix atomically, re-verify.' < /dev/null
```
Expected: `/qa` 워크플로우 로드 → 헤드리스 테스트 → 소스 수정 atomic commit → 재검증 → before/after 헬스스코어 + session_id 보고.

**2) Root Cause Investigation (read-only)**
```bash
claude -p --permission-mode plan --output-format json \
  '/investigate Sessions expire after 5 minutes instead of 24 hours. Investigate root cause only, do not fix.' < /dev/null
```
Expected: 복수 가설 수립 → 관련 코드 조사 → file:line 근거로 원인 보고 → 파일 미수정(plan mode).

**3) Ship**
```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/ship Merge base branch, run tests, review diff, bump VERSION, create PR.' < /dev/null
```
Expected: 베이스 병합 → 테스트 → diff 리뷰 → VERSION/CHANGELOG → 커밋/push/PR → PR URL + session_id 보고.

**4) Follow-up via Resume**
최초 호출이 `session_id: "abc123"` 반환 후:
```bash
~/.headroom/claude-hr.sh -p --resume abc123 --output-format json \
  'New constraint: do not touch the payments module. Re-verify and report.' < /dev/null
```
Expected: 동일 컨텍스트(이미 로드된 스킬, 이전 발견사항) 이어받아 새 제약 적용 후 재검증.

**5) Security Audit**
```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  '/cso Run a daily security audit before this deploy.' < /dev/null
```
Expected: daily 모드(8/10 게이트) → secrets/의존성/CI-CD/OWASP 체크 → 게이트 통과 항목만 보고.

## 7. Practical Command Cheatsheet

```bash
# QA + fix / report-only
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json --permission-mode acceptEdits '/qa Test and fix the checkout flow.' < /dev/null
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json '/qa-only Report bugs on the pricing page.' < /dev/null

# Investigate (read-only)
claude -p --permission-mode plan --output-format json '/investigate Why does CI fail but not local?' < /dev/null

# Review / Ship / Land
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json '/review Check my current diff.' < /dev/null
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json --permission-mode acceptEdits '/ship Ship the current branch.' < /dev/null
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json --permission-mode acceptEdits '/land-and-deploy Merge and verify prod.' < /dev/null

# Design / Security
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json --permission-mode acceptEdits '/design-review Audit and fix the dashboard.' < /dev/null
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json '/cso Run a daily security audit.' < /dev/null

# Context save/restore + follow-up injection
~/.headroom/claude-hr.sh -p --resume <session-id> --output-format json '/context-save Save current progress.' < /dev/null
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json '/context-restore Resume where I left off.' < /dev/null
~/.headroom/claude-hr.sh -p --resume <session-id> --output-format json 'New constraint: do not change the public API.' < /dev/null

# YOLO (isolated worktree only)
git worktree add ../repo-yolo -b gstack-yolo
claude -p --dangerously-skip-permissions --output-format json -C ../repo-yolo '/ship Fix and ship end to end.' < /dev/null
```

## 8. Final Operating Rule

1. gstack 도메인 카탈로그(§3)에서 스킬을 고른다 — 애매하면 `/gstack` 라우터에 맡긴다.
2. `claude -p '/skill-name ...' --output-format json < /dev/null`로 호출한다.
3. 모델/effort는 `claude-sonnet-4-6` / `high` 고정.
4. 조사 전용은 `--permission-mode plan`, 일반 수정은 `acceptEdits`.
5. `--dangerously-skip-permissions`는 격리 worktree에서만.
6. JSON 출력에서 `session_id`를 회수하고, 후속 지시는 전부 `--resume`으로.
7. 완료 주장 전 스킬 자체 검증 단계를 반드시 거친다 — 건너뛰지 않는다.
