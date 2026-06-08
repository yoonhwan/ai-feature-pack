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

**STEP 2 — 토글 스킬 설치** (이 폴더의 `SKILL.md`를 사용자 스킬로 배치 + 레지스트리/래퍼 생성)
```bash
mkdir -p ~/.claude/skills/headroom ~/.headroom
cp "$(dirname "$0")/SKILL.md" ~/.claude/skills/headroom/SKILL.md   # 이 폴더의 SKILL.md
[ -f ~/.headroom/enabled-projects.json ] || echo '[]' > ~/.headroom/enabled-projects.json
# fail-open + 레지스트리 인식 래퍼 생성 (아래 🚀 사용 섹션의 claude-hr.sh 그대로)
chmod +x ~/.headroom/claude-hr.sh
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
```

프록시 기동 (압축 + 캐시 공존 — 증명된 조합):

```bash
HEADROOM_MODE=token HEADROOM_COMPRESS_USER_MESSAGES=1 HEADROOM_CODE_AWARE_ENABLED=1 \
  ~/.headroom-venv/bin/python -m headroom.proxy.server \
  --port 8790 --compress-user-messages --exclude-tools Bash --code-aware
```

> click `headroom proxy`는 옵션이 제한적 → **`python -m headroom.proxy.server` 직접 실행**이 full 제어.

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
| Codex | ● | Claude와 메모리 공유 |
| Cursor | ● | config 출력 → 1회 붙여넣기 |
| Aider | ● | 프록시 기동 + 런치 |
| Copilot CLI | ● | 프록시 기동 + 런치 |

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

`~/.headroom/claude-hr.sh`. **현재 프로젝트가 `enabled-projects.json`에 등록 + 프록시 health OK** 일 때만 8790 경유, 그 외(미등록 / 프록시 다운 / 파싱 실패)는 모두 직결되어 작업이 무중단됩니다. 프로젝트 root는 **canonical(git-common-dir) 기준**이라 워크트리도 메인과 동일 root로 매칭됩니다(한 번 `on` → 워크트리 전체 커버).

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

## 📜 라이선스

MIT
