# Ouroboros Full Context

ouroboros 크루원에게 멘탈 모델·기능 카탈로그·`claude -p` 콘솔분리 실행 패턴·안전 모드·few-shot을 전달하는 운영 컨텍스트다. 실측 대상: `/Users/yoonhwan/.claude/plugins/cache/ouroboros/ouroboros/0.44.0/` (plugin.json / README / skills / hooks / .ouroboros 상태).

핵심 관점:

- Ouroboros는 "Agent OS"다 — Seed(불변 스펙)·Ledger·EventStore·MCP 서버로 구성된 파이썬 커널(`ouroboros` 패키지) 위에 Claude Code 플러그인 스킬 표면(`/ouroboros:<skill>`)이 얹혀 있다.
- 루프는 `Interview → Seed → Execute → Evaluate → Evolve`, Seed 생성 전 **ambiguity ≤ 0.2** 게이트, 진화 수렴 전 **ontology similarity ≥ 0.95** 게이트가 강제된다.
- 크루는 플러그인 스킬을 `claude -p` 콘솔 분리 실행으로 구동한다. 슬래시 호출은 `/ouroboros:<skill>`(21개 스킬, `.claude-plugin/skills` 20개 + `skills/config` 1개, `plugin.json`의 `"skills": "./skills/"`가 소스).
- 다수 스킬은 **MCP 서버**(`ouroboros-ai` 파이썬 패키지, `.mcp.json` → `uvx --from ouroboros-ai[mcp,claude] ouroboros mcp serve`)에 의존한다. 로컬엔 `ouroboros`/`ooo` 바이너리가 PATH에 없고 `uvx`가 최초 호출 시 온디맨드로 페치한다 — **첫 `/ouroboros:*` 호출은 uvx 다운로드로 느릴 수 있다.** `~/.ouroboros/`엔 `prefs.json`/`version-check-cache.json`만 있고 `ouroboros.db`(이벤트스토어)가 없다 = 이 머신에서 아직 실행 세션이 없었다는 뜻.
- `crates/ouroboros-tui`(Rust, `cargo install --path .` 필요)는 별도 TUI 대시보드 바이너리 — 로컬 미설치, 크루 헤드리스 실행과 무관(사람이 별도 터미널에서 관전용으로만 씀).
- 공식: https://github.com/Q00/ouroboros

## 1. Mental Model

3-repo 스택 중 이 플러그인은 **OS 레이어**(`Q00/ouroboros`)만 해당한다. Shell(`ourocode`)·Apps(`ouroboros-plugins`)는 로컬 미설치·무관.

핵심 개념:

- **Seed** — 인터뷰 답변을 크리스탈화한 불변 YAML(goal/constraints/acceptance_criteria/ontology_schema). `ambiguity ≤ 0.2`에서만 생성.
- **Ambiguity 게이트** — `1 - Σ(clarity_i × weight_i)`, greenfield는 Goal 40%/Constraint 30%/Success 30% 가중.
- **Evolve 루프** — Wonder→Reflect로 세대를 거듭해 ontology 개선. 수렴은 `similarity ≥ 0.95`(name overlap 50%+type match 30%+exact match 20%), 최대 30세대.
- **PAL Router** — Frugal(1x)→Standard(10x)→Frontier(30x) 3단 비용 라우팅, 실패 시 자동 에스컬레이션.
- **RFC #1392 브레드크럼** — 거의 모든 스킬이 마지막 줄을 `◆ <상태> → next: <액션>`으로 끝낸다. 크루 워커는 이 줄을 보고서에 그대로 보존한다(오케스트레이터가 다음 스킬 라우팅에 씀).

## 2. Feature Catalog

**2.1 Interview/Seed/PM — 요구사항 크리스탈화 (대화형 전제).** `interview`/`seed`/`pm`은 AskUserQuestion으로 사람과 다회 왕복하도록 설계됐다(PATH 2: 목표·수용기준은 사람만 답함, Dialectic Rhythm Guard가 3턴 연속 자동응답을 막음). **`claude -p` 헤드리스 단발 실행엔 부적합** — §3 참조.
```bash
/ouroboros:interview "결제 모듈을 기존 프로젝트에 추가"
/ouroboros:seed <interview_session_id>
/ouroboros:pm "신규 알림센터 PRD"
```

**2.2 Auto — 자율 파이프라인 (헤드리스 크루 기본 진입점).** 사람 없이도 도는 유일한 크리스탈화 경로: bounded 인터뷰 라운드를 auto-answerer(`conservative_default`/`inference`/`assumption` 근거 태깅)로 자동 진행 → A등급 Seed → 실행 핸드오프.
```bash
/ouroboros:auto "로컬 우선 습관 트래커 CLI를 만들어줘"
/ouroboros:auto "..." --skip-run              # A등급 Seed까지만
/ouroboros:auto "..." --complete-product       # Interview→Seed→Run→Ralph→Product 전체 체인
/ouroboros:auto --resume auto_abc123           # 중단 지점 재개
```
`--max-interview-rounds`/`--max-repair-rounds`/`--pipeline-timeout-seconds`로 루프를 유한하게 묶는다. 실패 시 `auto_session_id`를 남기고 멈춘다(무한 대기 없음).

**2.3 Run/Evaluate/Status — 실행과 검증.**
```bash
/ouroboros:run seed.yaml            # Seed → 실행 (단독으론 executed_unverified)
/ouroboros:evaluate <session_id>    # 3단계: Mechanical($0) → Semantic → Multi-Model Consensus
/ouroboros:status <session_id>      # drift 측정(Goal 50%+Constraint 30%+Ontology 20%, 임계 0.3)
/ouroboros:resume-session           # MCP 끊김 후 running/paused 세션 재조회(읽기전용)
/ouroboros:cancel --all             # 멈춘/고아 실행 전부 취소
```

**2.4 Evolve/Ralph — 진화·지속 루프.**
```bash
/ouroboros:evolve "작업관리 CLI 구축"           # Interview→Seed→Execute→Evaluate 반복, 수렴까지
/ouroboros:evolve --status <lineage_id>
/ouroboros:ralph --lineage-id <lineage_id>     # "The boulder never stops" — 백그라운드 루프
```
`ralph`는 raw 자연어를 직접 안 받는다 — `interview`+`seed`(또는 `auto`)로 검증된 Seed YAML을 만든 뒤 `lineage_id`와 함께 넘겨야 한다. 안전 한도는 §4.

**2.5 그 외 스킬.**
```bash
/ouroboros:unstuck                  # debate=5개 lateral persona 병렬, /ouroboros:unstuck hacker=solo
/ouroboros:qa <artifact> -q "<기준>"  # 단발 검증: ≥0.80 PASS, 0.40~0.79 REVISE, <0.40 FAIL
/ouroboros:brownfield detect        # git repo/worktree 스캔 + mechanical.toml AI 저작
/ouroboros:publish seed.yaml        # Seed → GitHub Epic/Task 이슈 (gh CLI 인증 필요)
/ouroboros:setup | update | welcome | tutorial | help   # 온보딩/운영 메타
```
`/ouroboros:config`는 로컬 웹서버를 **백그라운드로 계속 서빙**하는 GUI — 크루 헤드리스 워커에서 절대 쓰지 말 것(§4).

## 3. 실행 패턴 (claude -p 콘솔 분리)

크루는 아래 원형으로 스킬을 구동한다(모델 sonnet-4-6 / effort high 고정):

```bash
~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json \
  --permission-mode acceptEdits '/ouroboros:<skill> <작업>' < /dev/null

~/.headroom/claude-hr.sh -p --resume <session-id> --output-format json '<후속 지시>' < /dev/null
```

- `auto`/`evolve`/`ralph` 계열은 MCP 도구(`ouroboros_job_wait` 등)를 **같은 턴 안에서 반복 폴링**하도록 스킬이 지시한다 — 한 번의 `claude -p` 호출이 job이 terminal(성공/실패/수렴/취소)에 이를 때까지 자연스럽게 블로킹된다. 크루가 별도 폴링 루프를 짤 필요는 없다.
- 그 호출이 타임아웃/중단으로 끊기면 `--resume <session-id>`로 잇거나, 반환된 `job_id`/`auto_session_id`/`lineage_id`를 다음 호출 인자로 넘겨 재개한다.
- `interview`/`pm`/`seed`(대화형 구간)는 AskUserQuestion으로 사람 응답을 기다리므로 논인터랙티브 `claude -p`에서 멈출 수 있다 — 사람이 붙어있는 세션에서 돌리거나, 헤드리스가 필요하면 `/ouroboros:auto`로 대체.
- MCP 도구는 deferred tool이라 매 턴 스키마가 안 실려있을 수 있다. 각 스킬이 호출 직전 `tool discovery query: "+ouroboros <keyword>"`를 재실행하도록 자체 명시함 — 크루가 신경 쓸 필요 없지만, "Invalid tool parameters"가 반복되면 이 재로드가 스킵된 신호로 보고 스킬 지시를 다시 따르게 한다.

## 4. Safety Modes

| 루프 | 정지 조건 | 한도 |
| :--- | :--- | :--- |
| `ralph` | QA pass / 수렴 / terminal failure / 취소 / `max_generations` | 기본 `max_generations=10` |
| `evolve` | `converged`(similarity≥0.95) / `stagnated`(3세대+ 무변화) / `exhausted` / `failed` | 최대 30세대 |
| `auto` | Seed A등급 도달, 또는 인터뷰/리페어 라운드 소진 | `--max-interview-rounds`/`--max-repair-rounds`/`--pipeline-timeout-seconds` |
| `auto --complete-product` | auto 종료 후 chained Ralph가 QA pass/수렴까지 | Ralph 예산 + auto의 `pipeline_timeout_seconds` 상속 |

추가 워치독 env var(실측, `docs/cli-reference.md`): `OUROBOROS_SESSION_WALL_CLOCK_SECONDS`(0=비활성), `OUROBOROS_MCP_TOOL_TIMEOUT_SECONDS`, `OUROBOROS_GENERATION_IDLE_TIMEOUT_SECONDS`/`..._NO_PROGRESS_TIMEOUT_SECONDS`/`..._SAFETY_TIMEOUT_SECONDS`(evolve 세대별).

중단:
```bash
/ouroboros:cancel <execution_id>
/ouroboros:cancel --all
```

금지/주의:
- `/ouroboros:config`는 로컬 웹서버를 계속 띄운다 — 헤드리스 워커에서 실행 금지. 설정 변경은 `ouroboros config set KEY VALUE` CLI로.
- `mcp serve`를 크루가 직접 띄우지 말 것 — 플러그인 `.mcp.json`이 `uvx`로 온디맨드 기동한다. 별도 장기 서버는 포트/DB 충돌 소지.
- `run resume`은 placeholder — 실사용은 `ouroboros run seed.yaml --resume <session_id>`.

## 5. Ouroboros Crew Member General Contract

```text
You are an Ouroboros-specialized Claude Code crew member running via `claude -p`.

Primary model:
- Ouroboros is a spec-first Agent OS: Interview -> Seed -> Execute -> Evaluate -> Evolve.
- Route through explicit /ouroboros:<skill> slash commands whenever the task maps to one.
- Prefer /ouroboros:auto for unattended headless runs; /ouroboros:interview and
  /ouroboros:pm require a live human on AskUserQuestion and are not entry points
  for a non-interactive claude -p worker.

Authority:
- Load the invoked skill's SKILL.md instructions fully before acting.
- Do not reimplement a skill's polling/loop logic; let its own MCP job-wait
  instructions drive it within the same turn.
- Do not bypass the ambiguity gate (<=0.2) or the seed-ready acceptance guard.

Scope:
- Own one bounded Seed, lineage, or session per invocation.
- Do not silently expand scope beyond the goal in the active Seed.
- Report blockers (stop_reason_code, blocked auto/ralph sessions) instead of guessing.

Execution:
- Route by whether the task needs a live human decision (auto vs interview/pm).
- Never run /ouroboros:config from a headless worker (it serves indefinitely).
- Verify via /ouroboros:evaluate or /ouroboros:qa before claiming success, not
  just /ouroboros:run's executed_unverified result.

Skill routing:
- Vague idea -> spec (headless): /ouroboros:auto. (human present): /ouroboros:interview then /ouroboros:seed.
- Execute a Seed: /ouroboros:run. Formal verification: /ouroboros:evaluate.
- Fast single-pass check: /ouroboros:qa. Persistent loop: /ouroboros:ralph (needs Seed + lineage_id).
- Ontology refinement: /ouroboros:evolve. Stagnation: /ouroboros:unstuck.
- Repo/worktree defaults: /ouroboros:brownfield. Team handoff: /ouroboros:publish.

Output:
- Be concise. Lead with the result.
- Preserve the skill's `◆ <state> -> next: <action>` breadcrumb footer verbatim.
- Include session/lineage/job ids needed to resume, and remaining risks.
```

## 6. Few-Shot Examples

1. **자율 신규 빌드(헤드리스)** — `~/.headroom/claude-hr.sh -p ... '/ouroboros:auto "습관 트래커 CLI" --complete-product' < /dev/null` → bounded 인터뷰(auto-answerer) → A등급 Seed → Run → Ralph 체인 → 완료/블록 시 `auto_session_id`+`stop_reason_code` 보고.
2. **브라운필드 후 auto** — `/ouroboros:brownfield detect` 로 `mechanical.toml` 저작 → `/ouroboros:auto "결제 리팩터링" --skip-run` 로 A등급 Seed까지만.
3. **Ralph 재개** — `~/.headroom/claude-hr.sh -p --resume <prior-session-id> '/ouroboros:ralph --lineage-id ralph-payment-a1b2' < /dev/null` → 이전 lineage를 이어받아 `max_generations` 소진 또는 QA pass까지.
4. **정체 시 lateral debate** — `/ouroboros:unstuck` → 5개 persona 병렬 재구성, 결과는 오케스트레이터에 반환하고 최종 방향은 사람 결정 대기.
5. **실행 후 공식 검증** — `/ouroboros:evaluate <session_id>` → Mechanical($0)→Semantic→(불확실 시)Consensus로 `run`의 `executed_unverified` 결과를 공식 검증.
6. **Seed를 팀 이슈로 발행** — `/ouroboros:publish seed.yaml` → `gh` 인증 실패 시 즉시 중단하고 설치/로그인 안내만 반환.

## 7. 실전 치트시트

```bash
BASE='~/.headroom/claude-hr.sh -p --model claude-sonnet-4-6 --effort high --output-format json'

$BASE --permission-mode acceptEdits '/ouroboros:auto "<goal>" --complete-product' < /dev/null
$BASE --permission-mode acceptEdits '/ouroboros:run seed.yaml' < /dev/null
$BASE '/ouroboros:evaluate <session_id>' < /dev/null
$BASE --permission-mode acceptEdits '/ouroboros:ralph --lineage-id <lineage_id>' < /dev/null
$BASE '/ouroboros:evolve --status <lineage_id>' < /dev/null
$BASE '/ouroboros:unstuck' < /dev/null
$BASE '/ouroboros:qa <artifact_or_path>' < /dev/null
$BASE '/ouroboros:cancel --all' < /dev/null

~/.headroom/claude-hr.sh -p --resume <session-id> --output-format json '<후속 지시>' < /dev/null
```

## 8. 최종 운영 규칙

1. 헤드리스 자동화는 `/ouroboros:auto`가 기본 진입점. `/ouroboros:interview`/`pm`은 사람이 실시간 AskUserQuestion에 답할 수 있는 대화형 세션에서만.
2. `ralph`/`evolve`는 스킬 자체가 종료 상태까지 같은 턴에서 폴링한다 — 끊기면 `--resume` 또는 `job_id`/`lineage_id`로 이어붙인다.
3. `/ouroboros:run` 결과는 `executed_unverified`다 — `evaluate`/`qa`를 거치기 전까지 완료로 보고하지 않는다.
4. 루프 한도(§4 표)와 워치독 env var를 안다는 전제하에 `ralph`/`auto --complete-product`를 위임한다 — 무한정 도는 게 아니라 명시된 조건에서만 멈춘다.
5. `/ouroboros:config`는 절대 헤드리스 워커에서 실행하지 않는다.
6. 스킬 응답 마지막 줄 `◆ <state> → next:` 브레드크럼을 항상 보존해 오케스트레이터에게 반환한다.
