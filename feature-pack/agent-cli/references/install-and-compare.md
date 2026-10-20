# 설치 · 인증 · 비교 · Trust · 함정

> 2026-04 전수 조사 + 2026-06 실증 보정. 버전·설치법은 빠르게 바뀌니 공식 문서 우선.

## 설치 / 인증

| CLI | 설치(예시) | 인증 | 비대화 진입점 |
|-----|-----------|------|--------------|
| **claude** (Claude Code) | `npm i -g @anthropic-ai/claude-code` | `claude` 로그인(OAuth) 또는 `ANTHROPIC_API_KEY` | `claude -p` |
| **codex** (OpenAI) | `npm i -g @openai/codex` (또는 `npx -y @openai/codex`) | ChatGPT 로그인 / `OPENAI_API_KEY` | `codex exec` |
| **gemini** (Google) | `brew install gemini-cli` 또는 npm | `gemini` Google 로그인 / API 키 | `gemini -p` |
| **opencode** | `brew install opencode` (또는 공식 스크립트) | provider별 키/OAuth | `opencode run` |
| **cursor-agent** | Cursor 공식 CLI 설치(IDE와 별개 바이너리) | Cursor 로그인 | `cursor-agent -p` |
| Aider | `pipx install aider-chat` | provider 키 | `aider --message` |
| Amp | `brew install ampcode/tap/amp` | — | `amp -x` |
| **pi** | `npm i -g --ignore-scripts @earendil-works/pi-coding-agent` | `pi auth check` (OpenGateway Keychain/env) 또는 provider `/login` | `pi -p` / `pi --mode json` |

⚠️ **정정 (이전 가이드 오류)**
- **Gemini 설치는 Google 패키지** — `@anthropic-ai/gemini-cli` 아님.
- **Cursor**: `cursor`(IDE)는 비대화 모드 없음이 맞지만, **별도 `cursor-agent` CLI는 비대화·자율·resume 작동**(부적합 아님). 둘을 혼동하지 말 것.

## 비대화 실행 + JSON

| CLI | 명령 | JSON |
|-----|------|------|
| Claude Code | `claude -p "q"` | `--output-format json` / `stream-json --verbose` |
| Codex | `codex exec "q"` | `--output-schema <file>` |
| Gemini | `gemini -p "q"` | `-o json` / `-o stream-json` |
| OpenCode | `opencode run "q"` | `--format json` |
| Cursor Agent | `cursor-agent -p -f "q"` | `--output-format json` |
| Pi | `pi -p "q"` | `--mode json` (JSONL events) |

## Resume (세션 영속성) — 실증 보정본

| CLI | Resume | Session ID 출처 |
|-----|--------|----------------|
| Claude Code | `--resume <sid>` | JSON `session_id` |
| Codex | **`codex exec resume --last`** | (id는 **stderr** — 추출보다 `--last` 권장) |
| Gemini | **`--resume <session_id>`** | JSON `session_id` (‘latest’는 비대화 hang 사례) |
| OpenCode | `-s <sid>` / `-c` | `opencode session list` |
| Cursor Agent | `--resume <chatId>` + `-f` | JSON `session_id` |

## 도구 제한 / Trust Level

| CLI | 전체 우회(L3) | 제한 |
|-----|--------------|------|
| Claude Code | `--dangerously-skip-permissions` | `--disallowedTools Bash,Write,Edit` / `--tools Read,Grep,Glob` |
| Codex | `--full-auto` ⎮ `--yolo`(=`--dangerously-bypass-approvals-and-sandbox`) | `--sandbox read-only|workspace-write|danger-full-access` |
| Gemini | `--approval-mode yolo` | `--policy ./p.yaml --approval-mode default` |
| OpenCode | (run 기본 무승인) | — |
| Cursor Agent | `-f`/`--force` | — |

**xClaw Trust 매핑**: L3 `--dangerously-skip-permissions` · L2 `--disallowedTools Bash,Write,Edit` · L1 `+Glob` · L0 API 직접.

## 래핑 적합도 (요약)

1. **Claude Code** — stream-json + disallowedTools + append-system-prompt = 완전 제어 (최적)
2. **Codex** — sandbox 격리 강력, exec + output-schema
3. **Gemini** — stream-json + Policy Engine
4. **OpenCode** — json + 서버모드(attach). 도구 제한 부재가 약점
5. **Cursor Agent** — 비대화·resume 작동(`-f` 필수). IDE(`cursor`)와 구분
6. **Pi** — 미니멀·provider 자유도·RPC/SDK·skills. `--tools`로 권한 최소화, `--session-id`로 resume. 단 기본 sandbox/plan mode 없음
7. **Amp**(내부 라우팅) / **Aider**(Git 자동화 최강, JSON 약함)

## 컨텍스트 주입

```bash
claude -p "task" --append-system-prompt "ctx"          # 인라인
claude -p "task" --append-system-prompt-file ./ctx.md  # ARG_MAX 우회
claude -p "task" --system-prompt "custom"              # 교체
codex exec "task" -c 'instructions="ctx"'
pi -p --append-system-prompt "ctx" --tools read,bash "task" </dev/null
```

## Pi (pi-coding-agent)

```bash
# 1) 인증/모델 확인
pi auth check --provider opengateway --json
pi --list-models deepseek

# 2) 비대화 1회
SID="$(python3 -c 'import uuid;print(uuid.uuid4())')"
pi -p --session-id "$SID" \
  --model opengateway/deepseek/deepseek-v4.1-flash-ultrafast \
  --tools read,grep,find,bash \
  "task" < /dev/null

# 3) resume
pi -p --session "$SID" \
  --model opengateway/deepseek/deepseek-v4.1-flash-ultrafast \
  --tools read,grep,find,bash \
  "follow-up" < /dev/null
```

- Pi에는 Claude의 `--dangerously-skip-permissions` 같은 **승인 프롬프트 자체가 없다**. 대신 `--tools` allowlist로 권한을 줄인다.
- `--approve`/`--no-approve`는 **project trust** 결정용. headless에서는 prompt가 없으므로 명시한다.
- `--skill <path>`로 스킬을 주입하고, `--append-system-prompt`로 페르소나를 넣는다.
- `--mode json`은 JSONL 이벤트를 낸다(첫 `session`, 마지막 `agent_settled`). 모델 오류도 exit 0일 수 있으니 `stopReason`을 확인한다.
- `--session-id`는 없으면 새로 만들고, `--session`은 exact/partial ID로 기존 세션을 찾는다. `--continue`는 현재 project 최신 세션에 의존하므로 자동화에 쓰지 않는다.
- `--fork` + `--session-id <new>`는 허용. `--fork` + `--session`/`--continue`/`--resume`/`--no-session`은 금지. `--session-id` + `--session`/`--continue`/`--resume`도 금지.

## 함정

| CLI | 함정 |
|-----|------|
| Claude Code | JSON 제어문자 → `json.loads(raw, strict=False)`. 서버 과부하 시 `is_error:true`+`529`(일시적). |
| Codex | 프로젝트 디렉토리서 파일 우선 → 빈 디렉토리 테스트. session id는 stderr. `--full-auto`/`--yolo` 배타. |
| Gemini | personal OAuth rate limit. `--resume latest` 비대화 hang → sid 사용. `-o json` 앞 MCP 경고 접두사. |
| OpenCode | `-m provider/model` 필수. 설정 파일은 하나만(`.json`+`.jsonc` 공존 시 플러그인 중복 로드). |
| Cursor | `-f` 없으면 trust 프롬프트 블로킹. `cursor`(IDE) ≠ `cursor-agent`(CLI). |
| 공통 | node/MCP 자식이 신호 무시 → 타임아웃은 프로세스그룹 SIGKILL로(scripts 참조). Node 버전 불일치 시 네이티브 모듈 rebuild. |
