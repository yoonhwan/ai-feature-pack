# fable-team 강제 오케스트레이션 게이트 (orchestration-gate)

> 출처: joel__w__w 스레드 "토큰 아끼려면 '말'이 아니라 '강제 게이트'로 막아라". 핵심: CLAUDE.md 권고는 우회 가능 — **PreToolUse 훅으로 물리 차단**해야 실제로 막힌다.

## 4-레이어 (한 세트로 유지·배포)

| 레이어 | 팩 템플릿 | 배포처 | 역할 |
|--------|-----------|--------|------|
| 선언 | `templates/CLAUDE.orchestration.snippet.md` | 프로젝트 `CLAUDE.md` | declaration |
| 역할 | `references/agent-templates/` | `~/.claude/agents/` | role assignment |
| 기준 | `templates/rules/orchestration.md` | 프로젝트 `.claude/rules/` | operating criteria |
| 강제 | `templates/hooks/*.sh` + `templates/settings-hooks.snippet.json` | 프로젝트 `.claude/hooks/` + `.claude/settings.json` | enforcement |

**패치마다 4-레이어를 함께 갱신한다**(update.md). 하나만 바꾸면 선언↔강제 불일치가 난다.

## 훅 3종

| 훅 | 이벤트 | 동작 |
|----|--------|------|
| `orchestration-gate.sh` | PreToolUse (Edit\|Write\|NotebookEdit\|Bash) | 오케(TOP 모델)가 한 턴 코드 3파일째 수정·Bash 우회(sed·echo>·tee) → **하드 deny**+위임 메시지. 워커·문서·설정·상태는 면제 |
| `orchestration-turn-reset.sh` | UserPromptSubmit | 턴 코드파일 카운터 리셋 |
| `context-distill-gate.sh` | UserPromptSubmit(warn) + PreToolUse:Agent\|Workflow\|Task(block) | 300k warn 주입 / 450k 신규 스폰 하드 deny |

### 핵심 설계 (실측 통과)
- **모델 판별 = transcript_path의 마지막 assistant `message.model`.** 세션별로 정확 — 오케(fable-5/sonnet-5)만 게이트, 워커는 agent_id 면제(제1 판별)가 우선 — sonnet-5 tester 포함 자유. 워커가 여러 파일 편집 정상.
- **fail-open 절대원칙**: 파싱 오류·환경 이상·모델 불명 → 전부 exit 0(허용). 훅이 세션을 brick하지 않는다(글로벌 프록시 死=전 세션 마비 교훈).
- **코드 파일만 카운트**: `.py/.ts/.go/...` 등 소스만. 문서(.md)·설정(.json/.yaml)·상태(.fable-team/.omc/.claude/.baton/.cairn)·의존물(node_modules/dist)은 비카운트. 같은 파일 재편집은 카운트 비증가.
- **토큰 소스 = 같은 transcript의 마지막 usage**(input+cache_read+cache_creation). 300k/450k 임계.
- env 오버라이드: `OMC_GATE_MAX_CODE_FILES`(기본 2) / `OMC_GATE_TOP_MODELS`(기본 `fable|sonnet-5`) / `OMC_DISTILL_WARN_AT`(300000) / `OMC_DISTILL_BLOCK_AT`(450000).

## 설치 (프로젝트 스코프 — 글로벌 아님)

```bash
templates/install-gate.sh --check  [proj]   # 상태 진단 (기본)
templates/install-gate.sh --install [proj]   # 4-레이어 설치 (멱등·settings 병합·백업 .bak)
```
- proj 생략 = cwd(git root 정규화). 훅 복사+chmod, rules 복사, settings.json hooks 병합(기존 훅 보존·dedup), CLAUDE.md 스니펫(마커 멱등).
- 부팅 시퀀스 4에서 `--check`로 상태 확인 → 미설치면 사용자에 설치 제안.
- **settings 변경 반영 = 새 세션 또는 `/hooks` 열기** (실행 세션엔 소급 안 됨).

## 로스터 (강제 게이트 전제)

- 메인 오케스트레이터(세션) = **sonnet-5 또는 fable-5 (ultracode — 세션 시작 시 사용자 선택)**. 게이트 대상.
- architect = **sonnet-5** (기본) — **fable-5는 에스컬레이션 전용**(신규설계·2연속 DA REJECT·라이브 반증 1회, 증거팩 인라인 필수; 미가용 시 병렬 opus-4-6). 설계 파일만 산출(코드 아님)이라 실무상 게이트 무영향.
- 워커: implementer=opus-4-6/high, tester=sonnet-5/high, checker(대량서치)=sonnet-4-6/medium. 게이트 면제.

## TOP 모델[1m] 서브에이전트 모델 leak 교정 (sonnet-5/fable-5 포함)

[1m] 세션 Agent 스폰 시 워커가 세션 모델 상속(frontmatter 무시) → 전 워커가 세션 TOP 모델. 교정: ① `.claude/settings.json` env에 `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` provider ID 지정(tier alias 해석) ② [1m] 세션은 **일회성 브레인 워커(architect/checker/implementer/tester)만** Workflow 경로(explicit model) 강제 — **장수명 드라이버(DA·crew)는 Agent+wrapper 셔틀로 유지**(외부 CLI가 wrapper 주입 full-id로 실행). 일회성 브레인만 스폰 후 `agent-*.meta.json` model 검증(불일치=hard stop).

## 검증 (README §5 — "실제로 막히는지 증명")
`skill/templates/` 저작 시 합성 stdin으로 전 케이스 실증(2026-07-03): fail-open·워커면제·오케 3째 deny·문서/설정 비카운트·재편집 비증가·Bash우회 deny·300k warn·450k block·설치 멱등·병합보존. 상세 = 피처 `.fable-team/state/orchestration-gate`.
