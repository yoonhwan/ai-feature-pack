---
name: agent-cli
description: AI 코딩 에이전트 CLI 설치·설정·비대화형 실행·resume 체인·자동화 래핑 가이드. claude, codex, gemini, opencode, aider, amp, pi, cursor 지원.
triggers:
  - "agent-cli"
  - "codex 설치"
  - "gemini 설치"
  - "claude 설치"
  - "opencode 설치"
  - "aider 설치"
  - "CLI 비교"
  - "resume 체인"
  - "coding agent"
  - "agent install"
  - "래핑 가이드"
---

# agent-cli — AI 코딩 에이전트 CLI 툴킷

AI 코딩 에이전트 CLI 도구의 설치, 설정, 비대화형 실행, resume 체인, 자동화 래핑을 가이드한다.

**지원 CLI** (검증 완료 ✅):
- Claude Code, Codex, Gemini CLI, OpenCode, Cursor Agent
- Aider, Amp, Pi (웹 리서치 기반 — 설치 후 재검증 권장)

**출처**: `docs/cli-tools-reference.md` (2026-04-04 전수 조사, 679줄)

---

## UC1: 설치 (`agent-cli install <name>`)

### Claude Code
```bash
npm install -g @anthropic-ai/claude-code
claude --version
claude auth login
```
- **경로**: `/Applications/cmux.app/Contents/Resources/bin/claude` 또는 npm global
- **인증**: `claude auth login` (브라우저 OAuth)

### Codex (OpenAI)
```bash
npx -y @openai/codex          # 즉시 실행 (설치 불필요)
# 또는 글로벌 설치:
npm install -g @openai/codex
codex --version
```
- **인증**: `OPENAI_API_KEY` 환경변수

### Gemini CLI
```bash
npm install -g @anthropic-ai/gemini-cli
# 또는
npx https://github.com/anthropics/gemini-cli
gemini --version
```
- **경로**: `/opt/homebrew/bin/gemini`
- **인증**: `gemini auth login` (Google OAuth)
- **주의**: personal OAuth → rate limit 빡빡

### OpenCode
```bash
go install github.com/opencode-ai/opencode@latest
# 또는
brew install opencode
opencode --version
```
- **경로**: `/opt/homebrew/bin/opencode`
- **인증**: 프로바이더별 API key (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY` 등)

### Cursor Agent
```bash
# Cursor IDE 설치 후 CLI 자동 포함
brew install --cask cursor
cursor --version
```
- **경로**: `/opt/homebrew/bin/cursor`
- **주의**: IDE 전용. 비대화형 에이전트 모드 없음. `--chat`으로 독립 채팅만 가능.

### Aider
```bash
pip install aider-chat
# 또는
pipx install aider-chat
aider --version
```
- **인증**: 프로바이더별 API key
- **특징**: Git 자동화 최강 (`--auto-commits`, `--attribute-author`)

### Amp
```bash
# ampcode.com/install 에서 설치
# macOS:
brew install ampcode/tap/amp
amp --version
```
- **특징**: 내부 자동 모델 라우팅 (모델 선택 불가)

### Pi
```bash
npm install -g @mariozechner/pi-coding-agent
pi --version
```
- **특징**: 미니멀. 내장 4개 도구만 (read/write/edit/bash). MCP 미지원 (의도적).

---

## UC2: 비대화형 실행

| CLI | 명령 | JSON 출력 | 검증 |
|-----|------|----------|------|
| Claude Code | `claude -p "질문"` | `--output-format json` / `stream-json --verbose` | ✅ |
| Codex | `codex exec "질문"` | `--output-schema <file>` | ✅ |
| Gemini | `gemini -p "질문"` | `-o json` / `-o stream-json` | ✅ |
| OpenCode | `opencode run "질문"` | `--format json` | ✅ |
| Cursor | ❌ 비대화형 없음 | — | ✅ |
| Aider | `aider --message "질문"` | `--stream` (text만) | 🔍 |
| Amp | `amp -x "질문"` | `--stream-json` | 🔍 |
| Pi | `pi --mode rpc` | stdin/stdout JSON RPC | 🔍 |

### 공통 실행 패턴

```bash
# Claude Code
claude -p "task" --output-format stream-json --verbose --model sonnet

# Codex
codex exec "task" -m o3 --sandbox workspace-write --full-auto

# Gemini
gemini -p "task" -o stream-json -m gemini-2.5-pro --yolo

# OpenCode
opencode run "task" --format json -m anthropic/claude-sonnet

# Aider
aider --message "task" --model claude-3-opus --yes-always --no-stream

# Amp
amp -x "task" --stream-json --dangerously-allow-all
```

---

## UC3: Resume 체인 (세션 영속성)

**핵심**: 프로세스는 매번 종료되지만 `--resume`으로 대화 이력이 완전히 복원된다.
4라운드 테스트에서 5개 CLI 모두 검증 완료 (2026-04-05).

| CLI | Resume 플래그 | Session ID 획득 | 4라운드 검증 |
|-----|-------------|----------------|-------------|
| Claude Code | `--resume <session-id>` | JSON `session_id` 필드 | ✅ 완벽 |
| Codex | `codex exec resume <id> "prompt"` | stdout `session id:` 라인 | ✅ 성공 |
| Gemini | `--resume latest` / `--resume <idx>` | `--list-sessions` | ✅ 완벽 |
| OpenCode | `-s <session-id>` / `-c` | `opencode session list` | ✅ 완벽 |
| Cursor Agent | `--resume <chatId>` + `-f` | JSON `session_id` 필드 | ✅ 완벽 |

### 재현 명령

**Claude Code:**
```bash
# Round 1: 세션 생성
claude -p "프롬프트" --output-format json > r1.json
SID=$(python3 -c "import json; print(json.loads(open('r1.json').read(),strict=False)['session_id'])")

# Round N: resume
claude -p "후속 프롬프트" --resume "$SID" --output-format json
```

**Gemini CLI:**
```bash
# Round 1
gemini -p "프롬프트" --approval-mode yolo > r1.txt

# Round N (latest = 가장 최근 세션)
gemini -p "후속 프롬프트" --resume latest --approval-mode yolo
```

**Codex:**
```bash
# Round 1 (빈 디렉토리에서 실행 권장)
codex exec --skip-git-repo-check "프롬프트"
# session id는 stdout에서 추출

# Round N
codex exec resume "$SID" "후속 프롬프트" --skip-git-repo-check
```

**OpenCode:**
```bash
# Round 1
opencode run -m google/gemini-pro-latest "프롬프트"

# Round N
opencode run -s "$SID" -m google/gemini-pro-latest "후속 프롬프트"
# 또는: opencode run -c "후속 프롬프트"
```

**Cursor Agent:**
```bash
# Round 1
cursor agent -p -f --output-format json "프롬프트" > r1.json
SID=$(python3 -c "import json; print(json.loads(open('r1.json').read(),strict=False)['session_id'])")

# Round N
cursor agent -p -f --output-format json --resume "$SID" "후속 프롬프트"
```

### JSON 파싱 주의

```python
import json
# strict=False 필수 (제어 문자 포함 가능)
data = json.loads(raw_output, strict=False)
session_id = data.get("session_id")
```

### Resume 체인 활용 패턴 (멀티에이전트)

```
Brain 루프:
  1. claude -p "태스크" --resume {session-id} --output-format json
     → 응답 파싱
  2. 응답에 질문/HIL 필요?
     → YES: Slack/채팅으로 질문 전달 → 응답 수집
     → NO: 결과 처리
  3. claude -p "답변/후속 지시" --resume {session-id}
     → 이전 대화 전체 유지, 이어서 작업
  4. 완료될 때까지 반복
```

---

## UC4: 도구 제한 (권한 제어)

| CLI | 방식 | 명령 |
|-----|------|------|
| Claude Code | 블랙리스트 | `--disallowedTools "Bash,Write,Edit"` |
| Claude Code | 빌트인 제한 | `--tools "Read,Grep,Glob"` |
| Claude Code | 전체 우회 | `--dangerously-skip-permissions` |
| Codex | 샌드박스 | `--sandbox read-only` / `workspace-write` / `danger-full-access` |
| Codex | 전체 우회 | `--dangerously-bypass-approvals-and-sandbox` |
| Gemini | 정책 파일 | `--policy ./restrict.yaml --approval-mode default` |
| Gemini | 전체 우회 | `--approval-mode yolo` |
| Aider | 부분 비활성 | `--disable-playwright` 등 |

### Trust Level 매핑 (xClaw 기준)

| Level | 설명 | Claude Code 플래그 |
|-------|------|-------------------|
| L3 | Full Trust | `--dangerously-skip-permissions` |
| L2 | Write 제한 | `--disallowedTools Bash,Write,Edit` |
| L1 | Read Only | `--disallowedTools Bash,Write,Edit,Glob` |
| L0 | CLI 미사용 | API 직접 호출 |

---

## UC5: 래핑 적합도 비교 (`agent-cli compare`)

| CLI | 비대화형 | JSON 스트리밍 | 도구 제한 | Resume | 래핑 적합도 |
|-----|---------|-------------|----------|--------|-----------|
| **Claude Code** | ✅ `-p` | ✅ stream-json | ✅ disallowedTools | ✅ | **최적** (1순위) |
| **Codex** | ✅ `exec` | ⚠️ schema만 | ✅ sandbox | ✅ | **양호** (2순위) |
| **Gemini** | ✅ `-p` | ✅ stream-json | ⚠️ Policy | ✅ | **양호** (3순위) |
| **OpenCode** | ✅ `run` | ✅ json | ❌ | ✅ | **보통** |
| **Amp** | ✅ `-x` | ✅ stream-json | ⚠️ settings | ❌ | **양호** |
| **Aider** | ✅ `--message` | ⚠️ stream | ⚠️ | ❌ | **보통** (Git 최강) |
| **Pi** | ✅ `rpc` | ✅ JSON RPC | ❌ | ❌ | **보통** (미니멀) |
| **Cursor** | ❌ | ❌ | ❌ | ❌ | **부적합** (IDE 전용) |

### 래핑 우선순위

1. **Claude Code** — stream-json + disallowedTools + append-system-prompt 조합으로 완전 제어
2. **Codex** — sandbox 기반 격리가 강력. exec + output-schema
3. **Gemini** — stream-json + Policy Engine
4. **OpenCode** — json 출력 + 서버 모드(attach). 도구 제한 부재가 약점
5. **Amp** — stream-json + MCP. 모델 선택 불가(내부 라우팅)
6. **Aider** — Git 자동화 최강. JSON 스트리밍 미약

---

## UC6: 컨텍스트 주입

```bash
# Claude Code (인라인)
claude -p "task" --append-system-prompt "context here"

# Claude Code (파일 — ARG_MAX 우회)
claude -p "task" --append-system-prompt-file ./context.md

# Claude Code (시스템 프롬프트 교체)
claude -p "task" --system-prompt "custom system prompt"

# Codex (config 기반)
codex exec "task" -c 'instructions="context here"'
```

---

## 제약/함정

| CLI | 함정 |
|-----|------|
| Claude Code | JSON에 제어 문자 → `json.loads(raw, strict=False)` 필수 |
| Codex | 프로젝트 디렉토리에서 파일 시스템 우선 → 대화 컨텍스트 무시 가능. 빈 디렉토리에서 테스트 |
| Codex | 비대화형: `--dangerously-bypass-approvals-and-sandbox` 필요 (`-a never`와 동시 사용 불가) |
| Gemini | personal OAuth → rate limit 빡빡 |
| Gemini | `--allowed-tools` deprecated → Policy Engine 전환 필요 |
| Cursor | `-f` trust 플래그 없으면 실행 거부 |
| Cursor | 비대화형 에이전트 모드 없음 (IDE 전용) |
| OpenCode | 프로바이더/모델 `-m provider/model` 형식 필수 |
| Node | 버전 불일치 → 네이티브 모듈(better-sqlite3 등) rebuild 필요 |

---

## 성공 기준

- [ ] `which <cli>` 또는 `<cli> --version`으로 설치 확인
- [ ] 비대화형 실행에서 응답 수신 (`-p` 또는 `exec`)
- [ ] JSON 출력 파싱 성공 (`session_id` 추출)
- [ ] resume 체인으로 이전 컨텍스트 복원 (2라운드 이상)
- [ ] (래핑 시) session_id 추출 + 재사용 가능

---

## 참조

- 원본 문서: `docs/cli-tools-reference.md` (679줄, 2026-04-04)
- resume 실험: 같은 문서 §비대화형 영속성 (2026-04-05 검증)
- xClaw 래핑: 같은 문서 §xClaw Step 5 래핑 시 권장
