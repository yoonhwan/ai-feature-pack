## 표준 로스터 (references/agent-templates/ 와 1:1)

> **v3 스폰 경로 주의**: 아래 표의 **브레인·effort·도구**는 v3에서도 유효하나, **"스폰 경로" 열은 Legacy(agent-v2) 매핑**이다 — v3 기본 스폰은 위 **「v3 스폰 — tmuxc 세션」 매트릭스**(전 역할 tmux 세션, `ft-tmux-spawn.sh` 경유)를 따른다. 이 표는 `references/agent-templates/`와의 1:1 대응(롤백 시 디스패처 참조)을 유지한다. v3 상시 세션 **ft-pm-memory**(sonnet-4-6/medium)는 agent-template이 아니라 세션 계약 프롬프트(`prompts/pm.md`)로 정의되므로 이 표에 없다.

| 워커 | 브레인 (선택지) | effort | 스폰 경로 | 도구 | 전담 |
|------|----------------|--------|-----------|------|------|
| ft-architect | **fable-5** 또는 **codex-5.6-sol**(→ft-architect-x 드라이버) | **high** (max 금지) | fable-5=Workflow / codex=드라이버 | Read, Grep, Glob, Write | 원인 분석·해결 설계 → 설계 파일 |
| ft-analyst | **opus-4-6** | **high** | Agent | Read, Grep, Glob, Bash(읽기전용) | 로그↔코드↔스펙 3자대조 진단 |
| ft-checker | sonnet 4.6 | **medium** | Agent | Read, Grep, Glob | 대량 서치·로그·문서·아키텍처 확인 (병렬 다수, 단말성) |
| ft-implementer | **opus-4-8** | **high** | Agent | +Bash, Edit, Write, Skill, Monitor | 설계 파일 기반 구현. 프로젝트 스킬 호출 가능 |
| ft-tester / ft-tester2 | sonnet 5 | high | Workflow(effort 명시) | +Bash, Monitor | 테스트 설계·실행·repro |
| ft-da | **codex-5.6-sol** 또는 **grok-4.6** (드라이버: sonnet 4.6 low) | **high** | 드라이버 | +Bash, Monitor | DA review + DA approve loop |
| ft-da2 | **grok-4.6** 또는 **codex-5.6-sol** (da의 반대편) | **high** | 드라이버 | +Bash, Monitor | DA 이종 교차 검증 |
| ft-architect-x | codex-5.6-sol (architect=codex 선택 시에만 활성) | high (드라이버 low) | 드라이버 | +Bash, Write, Monitor | architect 계약 대행 (codex 출력 → 설계 파일) |
| ft-da-cursor | grok-4.6 (드라이버: sonnet 4.6 low) | high (드라이버 low) | 드라이버 | +Bash, Monitor | grok DA 판정 릴레이 |

> **메인 오케스트레이터(세션) = sonnet-5 또는 fable-5 (ultracode — 세션 시작 시 사용자 선택)** — 워커 아님(로스터에 없음). 기획·구현을 직접 하지 않고 위임하며, **orchestration-gate 훅**(§강제 게이트)이 코드 3파일째부터 물리 차단한다.

공통 불변: `tools:`에 Agent/Task 없음(서브의 서브 차단), 워커 모델에 fable-5 금지(최상위 브레인 좌석 architect만 예외), 보고는 최소 토큰 형식 강제.

**크루 (opt-in 확장 로스터)**: 로컬 하네스 전문 드라이버 워커 — ft-da(codex)가 원형이며, 같은 패턴으로 **하네스 이름 그대로** 추가한다. A형(외부 CLI): `omo`(OMX/OMO)·`perplexity`(무상태 API 스크립트 `perplexity_direct.py` — 웹 서치·팩트체크, 산출물 파일 저장 책임 때문에 `tools:`에 Write 포함). B형(claude 플러그인): `gstack`·`superpowers`·`insane-search`·`ouroboros` — **드라이버 서브에이전트(sonnet4.6 low, 우측 pane 가시)가 Bash로 `claude -p`(자식 실행 모델 sonnet4.6 high)를 실행·릴레이**(스폰 경로 표 3행 — 오케스트레이터 직접 실행 금지). 템플릿은 `ft-<crew>.md.tpl` 1:1. **세션 승계(resume/inject 체인)와 컨텍스트 윈도우 관리(요약-후-fork + WINDOW_PRESSURE)는 크루의 기본 제공 계약**(brain_sessions 4번째 버킷 규칙 동일 적용). 감지·설치는 install-interview §4, 공통 계약·카탈로그는 `references/crew/crew-support.md`, 하네스별 상세는 `references/crew/<하네스>-full-context.md`.
