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
| Pi | `npm i -g @mariozechner/pi-coding-agent` | — | `pi --mode rpc` |

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
6. **Amp**(내부 라우팅) / **Aider**(Git 자동화 최강, JSON 약함) / **Pi**(미니멀)

## 컨텍스트 주입

```bash
claude -p "task" --append-system-prompt "ctx"          # 인라인
claude -p "task" --append-system-prompt-file ./ctx.md  # ARG_MAX 우회
claude -p "task" --system-prompt "custom"              # 교체
codex exec "task" -c 'instructions="ctx"'
```

## 함정

| CLI | 함정 |
|-----|------|
| Claude Code | JSON 제어문자 → `json.loads(raw, strict=False)`. 서버 과부하 시 `is_error:true`+`529`(일시적). |
| Codex | 프로젝트 디렉토리서 파일 우선 → 빈 디렉토리 테스트. session id는 stderr. `--full-auto`/`--yolo` 배타. |
| Gemini | personal OAuth rate limit. `--resume latest` 비대화 hang → sid 사용. `-o json` 앞 MCP 경고 접두사. |
| OpenCode | `-m provider/model` 필수. 설정 파일은 하나만(`.json`+`.jsonc` 공존 시 플러그인 중복 로드). |
| Cursor | `-f` 없으면 trust 프롬프트 블로킹. `cursor`(IDE) ≠ `cursor-agent`(CLI). |
| 공통 | node/MCP 자식이 신호 무시 → 타임아웃은 프로세스그룹 SIGKILL로(scripts 참조). Node 버전 불일치 시 네이티브 모듈 rebuild. |
