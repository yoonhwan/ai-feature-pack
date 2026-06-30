<!-- 🤖 AGENT: 이 문서를 끝까지 읽어라. 그다음 ① 아래 "🤖 에이전트 설치·안내 절차"대로 headroom + 토글 스킬을 설치하고 ② 사용자에게 활성화 범위/방식을 물어본 뒤 ③ /headroom on|off|status 사용법을 사용자에게 안내하라. 자동 활성화 금지 — 사용자가 명시한 프로젝트만 켠다. -->

# 🗜️ headroom

> **AI 코딩 에이전트의 컨텍스트 비용을 LLM 도달 전에 깎는 로컬 프록시.** `ANTHROPIC_BASE_URL` 한 줄, 코드 변경 0.
>
> 언어 최적화는 착시(«1%). 캐시는 provider가 이미 10x 깎아 max. **남은 유일 레버는 carry/re-prefill되는 토큰 수를 줄이는 압축** — headroom이 그걸 한다.

---

## 🤖 에이전트 설치·안내 절차

> **이 문서를 읽은 에이전트가 따를 절차.** 사람이 읽을 땐 건너뛰고 [📦 설치](#-설치)부터 봐도 된다.

**STEP 1 — headroom 설치** ([📦 설치](#-설치) 참조)
```bash
python3.12 -m venv ~/.headroom-venv
~/.headroom-venv/bin/pip install "headroom-ai[all]"
```

**STEP 1.5 — 0.23.0 핫픽스 적용** (⚠️ 현 PyPI 최신 0.23.0 필수 — [🚑 에러 케이스 대응](#-에러-케이스-대응-트러블슈팅) 참조)
```bash
bash "$(dirname "$0")/patches/apply.sh"   # tree-sitter panic + 빈값 400 차단, 멱등
```
> PyPI `headroom-ai==0.23.0`은 tree-sitter thread-local fix가 빠진 갈래에서 태깅돼 **두 결함이 살아 있다**(500/400). 0.24.0이 릴리스되면 `pip install -U headroom-ai` 후 이 단계 불필요. 자세한 내용은 [`patches/README.md`](./patches/README.md).

**STEP 2 — 토글 스킬 + fail-open 래퍼 설치**
```bash
HR_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/.claude/skills/headroom ~/.headroom
cp "$HR_DIR/SKILL.md" ~/.claude/skills/headroom/SKILL.md
cp "$HR_DIR/templates/claude-hr.sh" ~/.headroom/claude-hr.sh
mkdir -p ~/.claude/skills/headroom-cliproxyapi/scripts
cp "$HR_DIR/scripts/file-logs.sh" ~/.claude/skills/headroom-cliproxyapi/scripts/file-logs.sh
cp "$HR_DIR/scripts/clean-proxy-logs.sh" ~/.claude/skills/headroom-cliproxyapi/scripts/clean-proxy-logs.sh
cp "$HR_DIR/scripts/file-logs.sh" ~/.headroom/headroom-cliproxy-file-logs.sh
cp "$HR_DIR/scripts/clean-proxy-logs.sh" ~/.headroom/clean-proxy-logs.sh
[ -f ~/.headroom/enabled-projects.json ] || echo '[]' > ~/.headroom/enabled-projects.json
[ -f ~/.headroom/disabled-projects.json ] || cp "$HR_DIR/templates/disabled-projects.json" ~/.headroom/disabled-projects.json
# Slack/Hermes와 동일 체인: Claude Code도 기본 headroom 경유 (해제: rm ~/.headroom/always-route)
cp "$HR_DIR/templates/always-route" ~/.headroom/always-route
chmod +x ~/.headroom/claude-hr.sh ~/.headroom/headroom-cliproxy-file-logs.sh ~/.headroom/clean-proxy-logs.sh ~/.claude/skills/headroom-cliproxyapi/scripts/*.sh
```

**STEP 3 — 사용자에게 질문** (자동 결정 금지, 반드시 물어본다)
1. 어떤 프로젝트/에이전트에 켤까요? (프로젝트별 수동 토글 — `/headroom on`)
2. 프록시를 상시 서비스로 둘까요, 세션마다 래퍼로 띄울까요? (상시화는 fail-open 래퍼 필수)
3. 멀티 프로바이더(Codex/Cursor/Aider/Copilot)도 쓰시나요? → [🔌 멀티 프로바이더](#-멀티-프로바이더-설치-가이드)

**STEP 4 — 사용법 안내** (사용자에게 전달)
- `/headroom on` = 현재 프로젝트 영구 활성 · `/headroom off` = 영구 비활성 · `/headroom status` = 상태+`cache_bust_count`(0 확인)
- 실행은 `claude-hr` 래퍼로 (`alias claude-hr='~/.headroom/claude-hr.sh'`). 프록시 죽어도 직결되어 무중단.
- **효과는 긴 세션·재독 많은 작업에서만 누적** — 단발/소형 입력엔 무의미하다고 솔직히 안내.

---

## 🤔 왜 headroom?

**Claude Code / Codex / Cursor를 오래 쓰면 컨텍스트가 차고 토큰·한도가 녹습니다.** 직접 PoC로 검증한 "왜 비싼가 + 무엇이 진짜 레버인가"가 근거입니다.

스테이트리스 LLM은 턴 간 기억이 없어 **매 턴 누적 컨텍스트 전체를 다시 먹입니다**(풀 forward). 비용은 둘로 갈립니다:

- **carry** — 매 턴 쌓인 컨텍스트 재전송. 캐시 히트면 0.1배 요율이지만 **윈도우 전체 × 매 턴**.
- **re-prefill** — 캐시 만료 후 다음 턴이 풀 윈도우를 처음부터 재계산(cache_create). cache_read의 **12.5배** 중량.

한 17세션 샘플: 입력:출력 ≈ **327:1**, **비용의 절반이 cache_create(재워밍)**.

> 구독형 사용자에겐 돈보다 **rate-limit이 통화**. 캐시 만료 후 재prefill이 한도를 풀 중량으로 때립니다. **압축 = 재prefill 토큰↓ → 만료당 한도 소모↓ → 벽 치기 전 더 오래.**

---

## 🧠 핵심 멘탈모델

### ① 3-Zone — 압축은 중간띠에서만

```
[ ❄️ 동결 prefix ]   [ 🗜️ 압축 가능 중간띠 ]   [ 📤 recent N (풀) ]
 system+초기, 캐시키     오래된 tool 출력            최신 메시지(보호)
 ≥1024tok byte-동일      ← headroom 압축 대상 →       protect_recent(기본 4)
 = KV캐시 히트(0.1x)                                  크던작던 풀로 LLM행
```

- 앞쪽은 캐시 위해 **동결**(건드리면 캐시 전부 무효), recent는 fidelity 위해 **풀**.
- **신규 대화는 전부 prefix/recent → 압축 0.** 길어질수록 내용이 중간띠로 밀려 압축이 누적됩니다.

### ② 캐시 vs 압축 — 둘은 긴장 관계

압축하려면 내용을 고쳐써야 → prefix 캐시가 깨집니다. 그래서 모드가 갈립니다:

| 모드 | 동작 | 라이브 압축률 |
|---|---|---|
| `cache` | prefix 동결, 관찰만 | ~0% |
| `token` | 공격 압축 + 캐시 공존 | 재독 25~30% |

**손익분기 = 세션 길이 × 압축 후 재독 횟수.** 긴 세션만 net 이득.

> ✅ **증명됨**: `token` 모드에서 압축이 켜진 채로도 캐시가 생존합니다 — `cache_bust_count: 0`, `tokens_lost_to_cache_bust: 0`. CacheAligner가 압축 출력을 **결정론적**으로 안정화해 캐시 키를 유지하기 때문입니다. (이 결정론이 깨지면 매 요청 cache miss → 재앙. load-bearing 전제)

### ③ 프리필 타이밍 — keep-alive 루프 금지

TTL은 히트마다 갱신되니 핑으로 캐시 유지가 기술적으로 가능합니다. 그러나 **핑 1회 = 풀 윈도우 cache_read**. 12.5핑 ≈ 1시간 ≈ 재prefill 1회. 5분 내 자연 연타면 무료, 길게 비울 거면 만료 후 복귀 시 재prefill 1번이 쌉니다.

> **구독형은 idle 핑이 한도 자해.** 정답: 온디맨드 재prefill(보증금) > 루프(임대료). → 거의 항상 손해.

---

## ⚙️ 동작 — 요청 여정

API 경계 프록시(`ANTHROPIC_BASE_URL=localhost:PORT`):

1. **분류** — ContentRouter가 타입 판별 → JSON / 코드(AST) / 산문 차등 압축.
2. **가역 압축(CCR)** — 원본은 로컬 보관, 모델엔 압축본 + `headroom_retrieve` 통로. 컨텍스트 내 lossy, 필요 시 복원.
3. **캐시 정합(CacheAligner)** — 압축 출력을 결정론적으로 안정화해 prefix 캐시 키 유지.
4. **재prefill** — `[동결 prefix] + [압축 중간띠] + [recent 풀]` → **가장 비싼 cache_create를 작은 토큰 위에서** = 최대 페이오프.

---

## 📦 설치

```bash
python3.12 -m venv ~/.headroom-venv
~/.headroom-venv/bin/pip install "headroom-ai[all]"
~/.headroom-venv/bin/headroom --version       # 0.23.0
bash patches/apply.sh                          # ⚠️ 0.23.0 핫픽스(필수) — 아래 🚑 참조
```

> ⚠️ **0.23.0은 그대로 쓰면 안 된다.** tree-sitter `unsendable` panic(500)과 빈값 400 두 결함이 살아 있다 — `patches/apply.sh`(멱등)로 적용. 0.24.0 릴리스 후엔 불필요. → [🚑 에러 케이스 대응](#-에러-케이스-대응-트러블슈팅) · [`patches/`](./patches/README.md)

프록시 기동 (압축 + 캐시 공존, **텔레메트리 off** — 아래 🔒 참조):

```bash
HEADROOM_MODE=token HEADROOM_COMPRESS_USER_MESSAGES=1 HEADROOM_CODE_AWARE_ENABLED=1 HEADROOM_TELEMETRY=off \
  ~/.headroom-venv/bin/python -m headroom.proxy.server \
  --port 8790 --compress-user-messages --exclude-tools Bash --code-aware
```

> click `headroom proxy`는 옵션이 제한적 → **`python -m headroom.proxy.server` 직접 실행**이 full 제어. (`--no-telemetry` 플래그는 click 전용 → server.py 직접 실행 시 `HEADROOM_TELEMETRY=off` env 사용)

---

## 🔌 멀티 프로바이더 설치 가이드

headroom은 Claude Code 외 Codex·Cursor·Aider·Copilot·임의 OpenAI 호환 클라이언트에도 붙는다.

### 설치 채널

```bash
pip install "headroom-ai[all]"                  # Python (전체)
npm install headroom-ai                          # Node / TypeScript
docker pull ghcr.io/chopratejas/headroom:latest  # 컨테이너
```

### 에이전트별 한 줄 wrap

`headroom wrap <agent>` — 프록시 기동 + 에이전트 실행을 한 번에 처리한다.

```bash
headroom wrap claude        # Claude Code
headroom wrap codex         # Codex
headroom wrap cursor        # Cursor
headroom wrap aider         # Aider
headroom wrap copilot       # GitHub Copilot CLI
```

| 에이전트 | wrap | 비고 |
|---|---|---|
| Claude Code | ● | `ANTHROPIC_BASE_URL` 경유 |
| Codex | ● | 운영 표준은 `~/.codex/config.toml` custom provider |
| Cursor | ● | config 출력 → 1회 붙여넣기 |
| Aider | ● | 프록시 기동 + 런치 |
| Copilot CLI | ● | 프록시 기동 + 런치 |

### Codex CLI 운영 표준 (headroom → cliproxy)

구독 프록시 스택을 쓸 때 Codex는 `headroom wrap codex`보다 Codex custom provider로 고정한다. 그래야 일반 `codex`/`codex exec`/tmux가 모두 같은 체인을 탄다.

```toml
# ~/.codex/config.toml
model_provider = "headroom"

[model_providers.headroom]
name = "Headroom"
base_url = "http://127.0.0.1:8790/v1"
env_key = "CODEX_DUMMY_API_KEY"
wire_api = "responses"
```

```bash
# ~/.zshrc — 실제 인증은 cliproxy OAuth가 처리하므로 더미 값만 필요
export CODEX_DUMMY_API_KEY="${CODEX_DUMMY_API_KEY:-dummy}"
alias codex='npx -y @openai/codex'
```

검증은 응답만 보지 말고 headroom stats까지 본다. 파일 로그는 평상시 OFF이므로 라우팅 이슈 대응 때만 잠깐 켠다:

```bash
bash ~/.claude/skills/headroom-cliproxyapi/scripts/file-logs.sh on

CODEX_DUMMY_API_KEY="${CODEX_DUMMY_API_KEY:-dummy}" \
  codex exec --skip-git-repo-check --ephemeral -C "$HOME" \
  'Return exactly CODEX_HEADROOM_OK.'

curl -sf http://127.0.0.1:8790/stats \
  | python3 -c 'import json,sys; stats=json.load(sys.stdin); [print(req.get("provider"), req.get("model"), req.get("status_code"), req.get("path")) for req in stats.get("recent_requests", [])[-5:]]'

grep -E '/v1/responses|codex|openai|status=200' \
  ~/Library/Logs/cliproxy/proxy.log 2>/dev/null | tail -30

bash ~/.claude/skills/headroom-cliproxyapi/scripts/file-logs.sh off
```

이 경로는 의도적으로 fail-open이 아니다. headroom/cliproxy 복구용 Codex는 `codex --ignore-user-config` 또는 provider override로 직접 띄운다.

### Claude Code 모델 윈도우 정책

구독 프록시 표준 경로에서는 Sonnet/Haiku를 200K로 고정하고, Opus만 200K와 1M을 둘 다 허용한다.

| 모델군 | 표준 모델명 | 1M 모델명 | 정책 |
|---|---|---|---|
| Sonnet | `claude-sonnet-4-6` | 없음 | 200K만 사용. 1M 별칭은 대소문자 변형 모두 등록하지 않는다. |
| Haiku | `claude-haiku-4-5-20251001` | 없음 | 200K만 사용. |
| Opus | `claude-opus-4-8` | `claude-opus-4-8[1m]` | 200K와 1M 둘 다 사용 가능. 1M suffix는 cliproxy 카탈로그와 동일하게 소문자 `[1m]`로 고정한다. |

기본 `cc`/`ccd` alias는 `claude-opus-4-8[1m]` Opus 1M으로 둔다. Opus 200K는 `cc2` 명시 alias로만 쓴다. 1M이 일시 unavailable이면 Claude Code의 Bash safety classifier까지 막힐 수 있다.

Sonnet 1M은 Claude Code에서 usage credits가 켜진 경우에만 별도 의도 하에 요청한다. 이 스택은 Sonnet 1M 요청을 200K로 폴백하지 않는다. 권한이 없으면 upstream 429가 나는 것이 맞다. `CLAUDE_CODE_DISABLE_1M_CONTEXT`는 진단용으로만 쓰고 alias에는 넣지 않는다.

### 로그 운영 정책

headroom/cliproxy 파일 로그는 기본 OFF다. LaunchAgent에는 `StandardOutPath`/`StandardErrorPath`를 두지 않고, headroom 내부 rotating 파일 로그는 `HEADROOM_FILE_LOGGING=off`로 끈다. 평상시 확인은 `/health`, `/stats`, cliproxy `/v1/models`, 실제 smoke 응답으로 한다.

`file-logs.sh on/off`는 LaunchAgent stdout/stderr 경로를 바꾸므로 프록시 재시작을 동반한다. 라이브 Claude Code 세션 중 실행하면 headroom 또는 cliproxy 포트가 순간적으로 닫혀 `ConnectionRefused`로 작업 세션이 멈출 수 있다. 스크립트는 활성 TCP 연결이 있으면 기본 거부하며, 정말 사고 캡처가 필요할 때만 `HEADROOM_FILE_LOGS_FORCE=1`을 붙인다.

이슈 대응 루프:

```bash
bash ~/.claude/skills/headroom-cliproxyapi/scripts/file-logs.sh on
# 문제 재현 또는 모니터링
bash ~/.claude/skills/headroom-cliproxyapi/scripts/file-logs.sh tail
bash ~/.claude/skills/headroom-cliproxyapi/scripts/file-logs.sh off

# 라이브 연결이 있는데도 강제 캡처해야 하는 경우만:
HEADROOM_FILE_LOGS_FORCE=1 bash ~/.claude/skills/headroom-cliproxyapi/scripts/file-logs.sh on
```

큰 로그 정리는 `~/.headroom/clean-proxy-logs.sh`가 담당한다. 운영 환경에서는 `com.headroom.proxy-log-cleanup` LaunchAgent로 매일 한 번 실행한다.

### Copilot 구독 모드

```bash
headroom wrap copilot --subscription -- --model gpt-4o
```

OpenAI 호환 Copilot 요청을 가로채 동일 압축 파이프라인 적용 후 Copilot 호스티드 API로 포워드. 런치 시 `COPILOT_PROVIDER_API_URL=...` 출력.

> ⚠️ macOS Keychain auth 재사용은 스모크 검증됨. Windows Credential Manager / Linux Secret Service / Docker·CI 경로는 미검증 — Docker·CI는 host keychain 의존 대신 `GITHUB_COPILOT_TOKEN`(또는 `GITHUB_COPILOT_GITHUB_TOKEN`) 명시 전달 권장.

### OpenAI 호환 클라이언트 (코드 변경 0)

```bash
headroom proxy --port 8790
# 클라이언트:
OPENAI_BASE_URL=http://localhost:8790/v1 your-app
```

어떤 OpenAI 호환 클라이언트든 프록시 경유 가능. MCP-native 설치: `headroom mcp install`.

### 영구 설치 (상주 서비스)

```bash
headroom init claude|codex|copilot|openclaw                          # 에이전트별 durable hooks + 라우팅
headroom install apply --preset persistent-service --providers auto  # 자동 감지 상주 서비스
headroom install status
```

### 백엔드 라우팅 (게이트웨이 / 대체 upstream)

upstream을 LiteLLM·Bedrock·Vertex 등으로 바꿀 때:

```bash
ANTHROPIC_TARGET_API_URL=https://litellm.internal  headroom proxy   # Anthropic 트래픽 라우팅
OPENAI_TARGET_API_URL=https://custom.endpoint      headroom proxy   # OpenAI 트래픽 라우팅
# --backend anthropic|openai · Bedrock=[bedrock] extra · any-llm=[anyllm] extra (py3.11+)
```

> 참고: `HEADROOM_CONTEXT_TOOL=lean-ctx`로 CLI 컨텍스트 도구 교체 가능(기본은 RTK — shell 출력 재작성).

---

## 🚀 사용

### fail-open + 레지스트리 인식 래퍼 (SPOF 제거 — 핵심 안전장치)

`~/.headroom/claude-hr.sh`. **always-route ON**(`~/.headroom/always-route`)이면 등록 없이 8790 경유. 아니면 **현재 프로젝트가 `enabled-projects.json`에 등록 + 프록시 health OK** 일 때만 경유. `disabled-projects` opt-out·프록시 다운·파싱 실패는 직결(fail-open). 프로젝트 root는 **canonical(git-common-dir) 기준**이라 워크트리도 메인과 동일 root로 매칭됩니다.

```bash
#!/bin/zsh
# headroom fail-open + registry-aware 래퍼
REGISTRY="$HOME/.headroom/enabled-projects.json"
PROXY_URL="http://localhost:8790"

# canonical 프로젝트 root (워크트리 → 메인 root로 정규화)
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
PROJECT_ROOT="$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || pwd)"

is_enabled() {
  [ -f "$REGISTRY" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$REGISTRY" "$PROJECT_ROOT" <<'PY' 2>/dev/null
import json, sys, os
try:
    reg = [os.path.realpath(p) for p in json.load(open(sys.argv[1]))]
    sys.exit(0 if os.path.realpath(sys.argv[2]) in reg else 1)
except Exception:
    sys.exit(1)
PY
}

if is_enabled && curl -sf -m1 "$PROXY_URL/health" >/dev/null 2>&1; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
else
  unset ANTHROPIC_BASE_URL    # 미등록 또는 프록시 다운 → 직결, 작업 무중단
fi
exec claude "$@"
```

`~/.zshrc`에 `alias claude-hr='~/.headroom/claude-hr.sh'` 추가 후 `claude-hr`로 실행. 토글은 `/headroom on|off`(스킬)로 — 래퍼는 레지스트리만 읽는다.

### 🤖 에이전트 실행 경로 — 어떻게 띄워야 경유하나 (중요)

`ANTHROPIC_BASE_URL`은 **프로세스 시작 시점 env**다. 즉 **claude를 어떤 명령으로 띄웠느냐**가 경유 여부를 결정한다. 두 가지 배치:

| 배치 | 방법 | 커버 범위 |
|---|---|---|
| **A. 별도 alias** | `alias claude-hr='~/.headroom/claude-hr.sh'` → 의식적으로 `claude-hr`로 실행 | 사용자가 직접 띄울 때만 |
| **B. 베이스 alias 재지정 (권장·전체 커버)** | 평소 쓰는 claude alias 자체를 래퍼로: `alias cc='~/.headroom/claude-hr.sh --dangerously-skip-permissions --model "..."'` | **모든 launch + tmux/오케스트레이터가 spawn·증류하는 세션까지** 자동 경유 |

**B를 권장**하는 이유: tmux 멀티세션·오케스트레이터(예: 세션 증류)는 보통 사용자의 베이스 claude alias로 세션을 재기동한다. 베이스 alias를 래퍼로 바꾸면 **그 모든 세션이 fail-open + registry 조건부로 자동 경유**한다(등록 프로젝트+프록시 살아있을 때만, 아니면 직결). 래퍼는 `"$@"`로 flags를 투명 전달하므로 `--model` 등 옵션은 그대로 유지된다.

> ⚠️ **기존에 떠 있던 세션은 소급 적용 안 됨.** env는 시작 시점에 굳으므로, **alias를 바꾼 뒤 새로 띄우거나 세션을 재증류(재기동)해야** 경유가 시작된다. `/stats`의 `api_req`가 0→증가하면 실제 경유 시작 신호다.

### 관찰 (`/stats`)

```bash
curl -s localhost:8790/health        # status healthy
curl -s localhost:8790/stats         # 압축률 + cache_bust_count(0이어야 정상)
```

| 지표 | 의미 |
|---|---|
| `avg_compression_pct` | 압축 발동 정도 |
| **`cache_bust_count`** | **0 유지 필수** (>0 = 캐시 깨짐 = 손해 신호) |
| `cache_write_1h_tokens` | 1h extended 캐시 사용 확인 |
| `/api/oauth/usage` | 구독 rate-limit 소모 (압축 효과 실측) |

---

## 🎯 어디에 쓰면 효과가 큰가

압축은 **입력이 크고 + 여러 턴 재실리고 + 압축 여지가 있을 때** 발동합니다.

| | ✅ 강타깃 | ❌ 약타깃 |
|---|---|---|
| 입력 덩치 | 코딩 tool 출력 / 긴 전사(수천~수만 tok) | 짧은 요약 (~수백 tok) |
| 재실림 | 긴 미션 / 세션 누적 | 단발 독립 호출 |
| 압축 여지 | tool 출력 캐시 밖 벌키 | 시스템 프롬프트(이미 캐싱) |
| resume | 재개마다 cold prefill | — |

→ **multi-agent swarm · 긴 코딩 세션 · 긴 문서/전사 후처리 · 다중 청크 RAG** 에 강함. **단발 채팅 · 작은 입력 · 시스템 프롬프트**엔 무의미.

---

## ⚠️ 정직한 한계

PoC 실측을 그대로 공개합니다 (신뢰의 핵심):

| 경로 | 압축률 |
|---|---|
| 라이브러리 직접(`compress_user_messages=True`) | **83.7%** |
| 라이브 프록시 — 단발 read | **0%** (표준 도구 기본 제외 + recent 보호) |
| 라이브 프록시 — 재독/supersede | **25~30%** (best 30.7%) |

- **단발 0%는 버그가 아니라 설계.** `DEFAULT_EXCLUDE_TOOLS = {Read,Bash,Grep,Glob,Edit,Write}` + `protect_recent`(기본 4)가 표준 도구 결과와 최근 메시지를 보호합니다. 같은 파일을 **재독(supersede)** 할 때 옛 복사본이 보호 밖으로 밀려 압축이 발동합니다.
- **만능 아님**: 기본설정은 코딩 에이전트 도구 출력을 안 건드림. tool_result 압축은 베타(rtk).
- **디버깅 주의**: CCR은 컨텍스트 내 lossy. 모델이 복원 필요를 모르면 오판할 수 있으니, 디버깅 워크플로우에서는 `headroom_retrieve` 복원 정확도를 별도 점검하세요.
- 수치는 환경/버전(v0.23)에 따라 다를 수 있음.

---

## 🚑 에러 케이스 대응 (트러블슈팅)

> 다른 피처팩/에이전트 사용자가 헤드룸 경유 중 만나는 3대 증상과 대응. 근본원인은 모두 **PyPI 0.23.0의 미수정 결함** 또는 **프록시 SPOF**다.

### 증상 A — `400 messages.N: user messages must have non-empty content`

- **원인**: 압축이 non-empty 입력을 **빈 문자열로** 압축해 반환 → 프록시가 빈 user-message content를 Anthropic에 전송 → 요청 전체 400 거부. (tree-sitter panic이 빈 content를 유발하는 경로가 대표적)
- **fix**: `patches/apply.sh` (빈값 가드 — non-empty 입력인데 결과가 비면 원본 fallback). 업스트림 [PR #771](https://github.com/chopratejas/headroom/pull/771).
- **임시**: 압축 user-message 끄기 — plist/기동 명령에서 `--compress-user-messages` 제거.

### 증상 B — 대용량 요청 500 / `compression_first_stage` RuntimeError / `No response returned`

- **원인**: `code_compressor.py`가 tree-sitter Parser(pyo3 `#[pyclass(unsendable)]`)를 **모듈 전역 dict로 스레드 공유**. 압축은 `ThreadPoolExecutor`에서 도므로 한 스레드의 파서를 다른 워커가 재사용하면 `pyo3_runtime.PanicException` → panic이 `BaseException`이라 `except Exception` 통과 → 500. 526KB+ 대용량에서 빈발.
- **fix**: `patches/apply.sh` (파서 캐시를 `threading.local()`로 스레드별 격리 + 잔여 panic passthrough). upstream main(0.24.0-dev)엔 이미 반영, **0.23.0 미릴리스 누락**.

### 증상 C — 전 세션 `API Error: Connection refused` (SPOF 마비)

- **원인**: 프록시(8790) 다운. 정적 `ANTHROPIC_BASE_URL` env로 묶인 세션은 **fail-open이 아니라서** 프록시가 죽으면 동시에 전부 마비된다.
- **복구**:
  1. **헤드룸 미경유 세션에서** 재기동 — 마비된 세션 안에선 못 한다(자기 연결이 죽음). **다른 프로젝트/루트**(레지스트리 미등록)에서 새 셸/세션을 연다.
  2. ```bash
     launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.headroom.proxy.plist 2>/dev/null
     launchctl enable    gui/$(id -u)/com.headroom.proxy
     launchctl kickstart -k gui/$(id -u)/com.headroom.proxy
     sleep 1; curl -sf -m1 http://localhost:8790/health && echo " ✅ 8790 복구"
     ```
  3. 8790이 살아나면 마비됐던 대화창은 **재시도(같은 입력 재전송)** 로 복귀.
  4. **예방**: 프록시 작업/모니터 세션은 처음부터 직결로 띄우고, 일반 세션은 정적 env가 아니라 [fail-open 래퍼](#-fail-open--레지스트리-인식-래퍼-spof-제거--핵심-안전장치)로 띄운다. **글로벌 `ANTHROPIC_BASE_URL` 정적 export 금지**(전 세션 SPOF).

### pyo3 panic 로그 식별법

프록시 로그(`~/Library/Logs/headroom/proxy-error.log`)에서 아래가 보이면 증상 A/B의 tree-sitter panic이다:

```
pyo3_runtime.PanicException: _native::Parser is unsendable, but sent to another thread
```

`patches/apply.sh` 적용 후엔 0건이어야 한다.

### ⚠️ stomping 주의 (Errno48 크래시루프)

여러 세션이 동시에 `/headroom on` 하며 각자 `python -m headroom.proxy.server`를 띄우면 8790 중복 bind = `Errno48 Address already in use` 크래시루프(2026-06-09 사건). **새 프로세스 spawn 금지** — 8790이 이미 LISTEN이면 재사용, 미가동일 때만 LaunchAgent(`launchctl bootstrap`)로 단일 인스턴스 기동. 스킬 `on` 로직이 이를 강제한다.

---

## 🔒 보안 / 프라이버시 (코드 실측 감사)

"스타 많아도 인젝션·외부유출 우려" — v0.23 코드 직접 감사 결과:

| 항목 | 판정 | 근거 |
|---|---|---|
| 프롬프트/코드 외부 전송 | ❌ 없음 | 텔레메트리 payload에 prompt/content/messages/text 필드 0건(`telemetry/beacon.py`) |
| 크레덴셜(OAuth/API키) | ✅ 로컬 | 의도된 upstream(anthropic 등)으로만. 타처 전송 없음. 내용 로깅(`--log-messages`)은 opt-in |
| **익명 텔레메트리** | ⚠️ **기본 ON** | 5분마다 vendor Supabase로 **집계 stats만**(tokens_saved/압축률/캐시율/models_used/os/익명uuid). **opt-out: `HEADROOM_TELEMETRY=off`** |
| 인젝션(`headroom learn`→CLAUDE.md) | ❌ 기본 off | `learn:false` 기본 |
| 메모리/벡터 외부저장 | ❌ 기본 off | `memory:false` 기본 (Qdrant cloud URL 존재하나 미사용) |
| 공급망 | ⚠️ 주의 | 번들 RTK 바이너리 + 기동 시 HF 모델 다운로드(huggingface.co) |

**결론: 프롬프트·코드·크레덴셜은 로컬 전용으로 유출 없음. 단 익명 사용량 텔레메트리가 기본 켜짐** → 독점/민감 환경은 **반드시 `HEADROOM_TELEMETRY=off`**(위 기동 명령에 포함). `learn`·`memory`는 끈 채로 둘 것.

### fail-open 주의 (정적 env 상속 함정)
프록시 URL을 **셸 env에 정적으로 export**하면(또는 그런 셸이 spawn한 세션) 그 세션은 라우팅되지만 **fail-open이 아님** — 프록시가 죽으면 세션도 죽는다. **반드시 [fail-open 래퍼](#-fail-open--레지스트리-인식-래퍼-spof-제거--핵심-안전장치)로 기동**해 매 호출 조건부로 base URL을 set/unset 해야 안전하다. tmux/오케스트레이터가 세션을 spawn할 때 정적 `ANTHROPIC_BASE_URL`을 상속시키지 말 것.

---

## 📜 라이선스

MIT
