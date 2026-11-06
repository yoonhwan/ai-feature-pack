## 부록: Legacy spawn (spawn_backend=agent-v2 — 롤백 경로, 2026-07-02 실측)

> v3 기본은 위 tmuxc 세션 경로다. 아래는 `spawn_backend.default: "agent-v2"` 롤백 시 오케가 따르는 Agent/Workflow 디스패처 **문서 절차**(실행 파일 아님) — `ft-tmux-spawn.sh`가 `exit 6 USE_AGENT_V2`를 반환하면 이 절차로 전환한다. **v2 에이전트 `.md`·템플릿과 함께 삭제 금지**(agent-v2 롤백의 실체).

| 워커 | 경로 | 이유 |
|------|------|------|
| architect (fable5 high), tester (sonnet5 high) 등 **claude-5 계열** | **Workflow `agent()`** + `model`/`effort` 명시 | Agent 팀 하네스는 frontmatter `effort:`를 무시하고 세션 effort(xhigh)를 상속시켜 claude-5 계열이 `400 level "xhigh" not supported`로 죽는다. Workflow의 effort 오버라이드는 실증 통과 (sonnet5+high ALL_PASS). effort 명시는 모든 세션에서 필수 — 세션 상한 초과 지정은 400 즉사, 미명시는 무증상 effort 다운그레이드(Agent 상속 = 세션 effort). |
| checker/implementer/da 등 **4.6 계열** | **Agent 도구** (팀 하네스) | ⚠️ [재교정 2026-07-12] **이 Legacy 경로도 모델 leak 대상** — agent-v2 롤백은 명시 승인 토큰으로만 활성, 스폰 후 `message.model` hard-stop 검증 필수(불일치=kill·재스폰). xhigh effort 상속은 별개. 이름 부여 스폰 → SendMessage approve loop 재라운드. |
| 외부 CLI 하네스 실행 전부 — 장시간 두뇌 작업(claude -p architect), DA(codex exec), 플러그인 크루(claude -p), omo(omx exec) | **미들웨어 드라이버 서브에이전트** (Agent 도구 — **세션 우측 pane 가시**, sonnet4.6 low, 이름 부여. 팀스 별창 아님) — 드라이버가 Bash로 외부 CLI를 `< /dev/null` 실행하고 결과를 SendMessage로 릴레이 | **오케스트레이터가 외부 CLI를 직접 실행하는 것 금지**(직접 `claude -p`/`codex exec`/`omx exec` 발사 금지). 이유: ① 서브에이전트는 세션 우측 pane에 네이티브 가시(별도 tmux 테일러 불요) ② SendMessage는 즉시 전송·유실 위험 낮음(Claude Code 프로토콜 최적화) ③ 자식 CLI는 별도 OS 프로세스라 개입 내성 유지 — 드라이버가 죽어도 계약=프롬프트 파일·결과=출력 파일 낙수로 재회수 가능. 드라이버는 자식을 **detach 발사(nohup/setsid — 드라이버 사망에도 자식 생존)** 후 PID+출력 파일 폴링으로 감시(포그라운드 실행 금지 — 드라이버 동반 사망 시 자식까지 죽는 실사고 2026-07-03). "화면 없는 백그라운드 금지"는 **오케스트레이터의 무가시 직접 발사**에 한한다 — 드라이버 경유 detach는 pane 가시가 이미 확보돼 정당. |

architect는 어차피 **무상태 계약**(컨텍스트 입력 → 설계 파일 출력)이라 Workflow 일회성 호출이 자연스럽다. 대기가 필요한 워커(approve loop 등)만 Agent 경로를 쓴다.

**★ [재교정 2026-07-12] Agent-tool 워커 스폰 모델 leak — 재현 확정, 07-06 "미재현" 결론 반증됨**: 07-06 재검증(`claude-sonnet-5[1m]`→ft-checker→sonnet-4-6)은 "leak 미재현, Agent 경로 안전"이라 결론냈으나 **2026-07-12 라이브 실측에서 반증됨** — `claude-fable-5` 오케(master#66, auto mode)가 Agent-tool로 워커 스폰 시 워커 `message.model`이 frontmatter full-ID(`claude-opus-4-8` 등)를 무시하고 **세션 모델 `claude-fable-5`로 leak**(implementer가 fable-5로 뜸). 반면 **tmuxc로 스폰한 워커는 전부 정상**(ft-cfo-implementer#2/#3=opus-4-8, analyst=opus-4-6, pm=sonnet-4-6 — status line 실측).

**확정 사실 vs 가설 (인과 미분리 — 정직하게 구분)**: **확정된 것은 관측뿐** — Agent-tool 워커 스폰이 **환경·모델 조합에 따라 비결정적으로 세션 모델을 상속(leak)한다**(07-12 fable-5 오케 → 워커 fable-5 실측). **원인은 가설 단계**다: 같은 resolver-env 부재 조건에서 07-06 sonnet-4-6은 정상, 07-12 opus-4-8은 leak했으므로 "bare full-ID 프로바이더 해석 실패 → 세션모델 폴백" 단일 가설로는 **모델별 차이를 설명 못한다**(세션모델·모드·요청모델 3변수 동시변경으로 인과 미분리). **유력 가설**: 비표준 프록시/Agent 레지스트리의 **모델별 해석·허용 차이**(특정 세대 ID만 해석됨). 확정 인과는 통제 실험(단일변수) 전까지 보류.

**왜 tier alias로도 못 고치나 (이건 확정)**: 로스터는 `opus-4-8` vs `opus-4-6`, `sonnet-5` vs `sonnet-4-6` 등 **세대 구분이 필수**인데 tier alias(opus/sonnet/haiku/fable)는 세대를 구분하지 못한다. Agent-tool 경로로는 로스터의 세대별 모델을 정확히 지정할 수 없다.

**tmuxc는 왜 나은가 (구조적 보장은 아직 아님 — 주의)**: tmuxc는 실제 `claude` 프로세스를 띄우고 **관측상 워커가 전부 정상 세대**로 떴다(실측). 단 **현재 `ft-tmux-spawn.sh`는 install.json `brains.<role>` 조회 없이 호출자 `--model`을 그대로 전달**하므로(코드 실측), "install.json 기반 자동 세대 라우팅"은 아직 **구조적 보장이 아니다** — 실측은 "그 세션이 정상"의 확인일 뿐. **진짜 보장은 스폰 후 `message.model` 검증(사후 대조, 아래 준수 게이트)** 이다. 단 이 사후검증은 **tmuxc(ft-tmux-spawn.sh가 자동 수행, 불일치=exit 7 kill)** 와 **Workflow(수동)** 에만 적용된다 — **Agent/Task 경로엔 사후검증층이 없어**(스폰이 팀 하네스 내부라 스크립트가 개입 못함) `spawn-route-gate.sh` PreToolUse **예방(deny)** 으로만 막는다. 게이트가 fail-open으로 놓치면 그 Agent 스폰은 미검증 통과 — 그래서 Agent 워커 경로 자체를 금지한다.

**결론·규칙 (하드)**:
- **전 워커 스폰은 tmuxc(v3 기본 경로)로만.** `ft-tmux-spawn.sh` 경유 — 세대별 모델 정확 라우팅 검증됨.
- **Agent-tool 일회성 브레인 스폰 금지**(이 환경 = 비표준 프록시 + resolver env 부재에서 세션 모델 leak). Legacy agent-v2 롤백 경로를 부득이 쓸 경우 스폰 직후 `message.model` 검증을 **hard-stop 게이트로 필수** — 지정 세대와 불일치 시 즉시 중단하고 tmuxc로 재스폰.
- **장수명 드라이버(codex/cursor DA·플러그인 크루)는 예외**: 드라이버=셔틀이라 자체 모델 무관(외부 CLI가 실제 브레인). Agent-tool teammate로 스폰 유지.
- resolver env를 갖추고 frontmatter를 tier alias로 전환하면 Agent 경로도 이론상 가능하나, **세대 구분 불가로 로스터엔 부적합** — 채택하지 않는다.

### ★ 스폰 경로 결정표 (재교정 2026-07-12 — Agent-tool 모델 leak 재현 반영)

**2026-07-12 실측으로 Agent-tool 워커 스폰의 세션 모델 leak이 재현됨**(§상단 재교정 — fable-5 오케 + Agent-tool → 워커 fable-5). 07-06의 "leak 미재현·Agent 경로 허용" 결론은 반증됐다. 따라서 **일회성 브레인 워커 스폰은 tmuxc(v3 기본, `ft-tmux-spawn.sh`)로만** — 세대별 모델 정확 라우팅 검증됨. Agent-tool 경로는 비표준 프록시 + resolver env 부재 환경에서 bare full-ID가 세션 모델로 폴백해 leak하므로 **일회성 브레인엔 금지**(부득이한 Legacy agent-v2 롤백 시 `message.model` hard-stop 검증 필수). Workflow 경로는 `effort` 명시·구조화 출력이 필요한 특수 케이스에 한해 `agentType`+full-ID로 쓰되 스폰 후 `message.model` 검증. 장수명 드라이버는 셔틀이라 예외(아래).

| 워커 유형 | 스폰 경로 | 모델/effort 제어 |
|-----------|-----------|------------------|
| **일회성 브레인** (architect·checker·analyst·implementer·tester) | **tmuxc `ft-tmux-spawn.sh`(정본)**. 특수 케이스만 Workflow `agent()`+`agentType`+full-ID | **Agent-tool 금지**(2026-07-12 leak 재현 — bare full-ID가 세션 모델로 폴백). tmuxc는 실제 claude 프로세스라 세대별 정확 라우팅(실측). Workflow 사용 시 스폰 후 `message.model` hard-stop 검증 |
| **analyst (진단 전문)** | **tmuxc `ft-tmux-spawn.sh`** (opus-4-6 high) | [재교정 2026-07-12] Agent-tool 금지(모델 leak) — 전 워커 규칙 적용. Bash 읽기 전용(파일 수정 금지). DIAGNOSIS + ESCALATE_TO_ARCHITECT 보고 계약. 스폰 후 `message.model` 검증 |
| **장수명 드라이버** (codex DA·cursor DA·architect-x·omx/omo·claude 플러그인 크루) | **Agent-tool teammate** (sonnet-4-6 low, 우측 pane 가시) — Bash로 외부 CLI를 `< /dev/null` detach 실행 + SendMessage 릴레이 | 드라이버는 **셔틀**(외부 CLI가 실제 브레인). approve loop·SendMessage 대기 때문에 Workflow(일회성) 불가 → Agent 필수. [1m]에서 드라이버 모델 leak은 **무관**(드라이버=셔틀, 외부 CLI가 wrapper의 주입된 full-id/effort로 실행 → 실제 브레인 모델에 영향 없음). mismatch hard-stop은 **일회성 브레인(Workflow 강제)에 적용**, 드라이버에는 해당 없음. 스트림: codex `--json`+`--output-last-message`로 이벤트 파싱·중간보고(ft-update-backlog #1) |
| **DA 브레인** | codex gpt-5.5 **high** 또는 grok-4.6 (cursor-agent) — 세션 시작 인터뷰에서 사용자 선택 | 세션 무관(외부 CLI). 드라이버=sonnet-4-6 low |
| **architect 대체** (fable 부재 시) | **codex-5.6-sol high** (→ft-architect-x 드라이버) — 세션 시작 인터뷰에서 선택. 미가용 시 `BRAIN_UNAVAILABLE` 보고 후 남은 choices 재제시 | fable 미가용·rate limit 시 대안. 자동 폴백 금지 |

**★ full model ID 강제 (bare tier 금지 — 실측 leak 원인)**: 스폰 호출·state 원장·보고에 모델을 적을 땐 **항상 정확한 full ID**로 — `claude-fable-5`·`claude-sonnet-5`·`claude-opus-4-6`·`claude-sonnet-4-6`. **bare tier `"opus"`/`"sonnet"` 절대 금지** — bare tier는 세션 TOP 모델로 해석돼 leak(실측: `model:"opus"` 스폰 → 세션 모델/xhigh). 원장에 "opus/high"처럼 쓰면 세대가 모호 → 반드시 "opus-4-6"으로. **단 [재교정 2026-07-12] 이 full-ID 규칙은 "원장·보고 표기 명확성"에 한한 것 — 실제 스폰의 모델 라우팅은 full-ID로도 Agent/Workflow 경로에선 leak한다**(비표준 프록시 + resolver env 부재 시 세션 모델 폴백). **스폰은 tmuxc 정본**이 세대별 정확 라우팅을 보장한다(§상단 재교정). Workflow를 부득이 쓸 땐 `agentType`+스폰 후 `message.model` hard-stop 검증 병행.

**준수 게이트(필수)**: **일회성 브레인(Workflow 경로)** 스폰 후 실제 모델을 검증한다 — workflow 디렉토리 `agent-*.jsonl`의 `message.model`. **지정 스펙과 불일치 = hard stop**(해당 워커 중단 → 올바른 경로로 재스폰, leak 미교정 진행 금지). **장수명 드라이버는 제외**(셔틀 — 외부 CLI가 wrapper 주입 full-id로 실행, 드라이버 자체 모델 leak은 무관). "더 강력하니 괜찮다"는 금지 — 로스터의 존재 이유(비용·동작 제어)를 부정. fable-5는 서버 rate limit이 타이트(실측 2회 실패) → 실패 시 `BRAIN_UNAVAILABLE` 보고 후 남은 choices(codex-5.6-sol/high 등) 재제시.
