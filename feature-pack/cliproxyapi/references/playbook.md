# headroom · CLIProxyAPI 스택 — 전체 플레이북

2026-06-17 구축 기록. Hermes를 Claude/Codex/Gemini **구독 plan**으로 돌리는 로컬 스택의
설치·연동·트러블슈팅을 처음부터 재현 가능하게 정리한다.

---

## 0. 전체 그림

```
Hermes (anthropic_messages, CC 위장 + tool name cloak)
  → headroom :8790      컨텍스트 압축(code-aware), keepalive, fail-open 래퍼
  → CLIProxyAPI :8317   멀티계정 OAuth 회전 + Claude cloak + OpenAI/Claude/Gemini 변환
  → Anthropic · OpenAI(codex) · Gemini(antigravity)
```

- **headroom**: 토큰 절약(압축). 단일 upstream. 이미 있던 도구.
- **CLIProxyAPI**: 구독 OAuth를 API로 노출 + 멀티계정 라운드로빈 + cloak + 프로토콜 변환.
- **Hermes**: tool 이름 cloak + claude-cli UA 제어(아래 핵심 함정 참조).

역할이 겹치지 않으므로 **체인(headroom→cliproxy)** 으로 둘 다 살린다. 순서는 바꿔도 되고 직결도 가능.

---

## 1. CLIProxyAPI 설치 (macOS arm64)

```bash
# Homebrew core formula (stable, 자동시작은 우리가 LaunchAgent로 별도 관리)
brew install cliproxyapi        # 7.2.10 (core) — 단 우리는 release 7.2.15 binary 고정 사용

# release 7.2.15 binary 고정 (Anthropic 탐지 추격전이라 동작 버전 고정)
curl -fsSL -o /tmp/cpa.tar.gz \
  https://github.com/router-for-me/CLIProxyAPI/releases/download/v7.2.15/CLIProxyAPI_7.2.15_darwin_aarch64.tar.gz
mkdir -p /tmp/cpa && tar -xzf /tmp/cpa.tar.gz -C /tmp/cpa
mkdir -p ~/.cli-proxy-api/bin
cp /tmp/cpa/cli-proxy-api ~/.cli-proxy-api/bin/ && chmod +x ~/.cli-proxy-api/bin/cli-proxy-api
```

### config (`~/.cli-proxy-api/config.yaml`)

```yaml
host: "127.0.0.1"          # localhost only
port: 8317
auth-dir: "~/.cli-proxy-api"
api-keys: []               # 빈 배열 = client 인증 없음 (localhost 신뢰). 필요시 키 등록.
remote-management:
  allow-remote: false
  secret-key: "hermes-mgmt-key"   # 대시보드/management API 인증. plaintext면 기동 시 해시됨.
debug: false               # 트러블슈팅 때만 true (요청/응답 본문 로그)
routing:
  strategy: "round-robin"  # 멀티계정 회전
```

- `api-keys: []` 면 `/v1/*` 호출에 client 키 불필요. 키 넣으면 `x-api-key` 또는 `Authorization: Bearer`로 검증.
- config는 **file watcher hot-reload**. 단 `debug` 등 일부는 재시작 필요.

---

## 2. OAuth 로그인 (구독 계정 연결)

콜백 포트 54545. **대시보드 방식이 가장 안전** (콜백을 메인 포트 8317이 받음 = is_webui).

### 방법 A — 대시보드 (권장)

```bash
# 서버 먼저 기동(아래 LaunchAgent) 후:
open http://127.0.0.1:8317/management.html   # secret-key 입력 → Add account → 브라우저 OAuth
```
계정 추가 시 `~/.cli-proxy-api/{claude,codex,antigravity}-<email>.json` 저장. 다른 계정으로 반복 = 멀티계정 회전 풀.

### 방법 B — CLI

```bash
~/.cli-proxy-api/bin/cli-proxy-api -claude-login -no-browser -config ~/.cli-proxy-api/config.yaml
# 출력된 https://claude.ai/oauth/authorize... URL을 브라우저로 열어 인증
```

### ⚠️ 콜백 실패 함정

`-claude-login` 프로세스를 **폴링 중단(Ctrl-C/SIGINT)으로 죽이면** 54545 콜백 리스너가 사라져서,
브라우저에서 권한 승인해도 "리다이렉트 실패"가 난다. 백그라운드로 띄울 땐 셸과 분리하고(SIGINT 전파 차단),
가능하면 대시보드(is_webui, 8317 콜백) 방식을 쓴다. macOS엔 `setsid` 없음 — Shell 도구의 background 잡으로 띄울 것.

### 토큰 권한

```bash
chmod 600 ~/.cli-proxy-api/*.json   # cliproxy가 644로 만들 때가 있음 → 토큰 노출 방지
```

---

## 3. 재부팅 자동시작 — LaunchAgent

`brew services`는 `/opt/homebrew/etc/cliproxyapi.conf`를 봐서 우리 config(`~/.cli-proxy-api/`)와 경로가 다름.
→ **전용 LaunchAgent** 사용.

`~/Library/LaunchAgents/com.cliproxy.api.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.cliproxy.api</string>
  <key>ProgramArguments</key><array>
    <string>/Users/&lt;USER&gt;/.cli-proxy-api/bin/cli-proxy-api</string>
    <string>-config</string><string>/Users/&lt;USER&gt;/.cli-proxy-api/config.yaml</string>
  </array>
  <key>WorkingDirectory</key><string>/Users/&lt;USER&gt;/.cli-proxy-api</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>/Users/&lt;USER&gt;/Library/Logs/cliproxy/proxy.log</string>
  <key>StandardErrorPath</key><string>/Users/&lt;USER&gt;/Library/Logs/cliproxy/proxy-error.log</string>
</dict></plist>
```

```bash
mkdir -p ~/Library/Logs/cliproxy
plutil -lint ~/Library/LaunchAgents/com.cliproxy.api.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.cliproxy.api.plist
launchctl print gui/$(id -u)/com.cliproxy.api | grep state   # running
```

`keepalive`라 죽어도 자가복구. `runatload`라 로그인 시 자동 기동.

---

## 4. headroom → cliproxy 체인

headroom의 upstream을 cliproxy로:

```bash
# plist ProgramArguments 끝에 추가
/usr/libexec/PlistBuddy -c "Add :ProgramArguments: string --anthropic-api-url" ~/Library/LaunchAgents/com.headroom.proxy.plist
/usr/libexec/PlistBuddy -c "Add :ProgramArguments: string http://127.0.0.1:8317" ~/Library/LaunchAgents/com.headroom.proxy.plist
```

### ⚠️ plist 인자 변경은 kickstart로 반영 안 됨

`launchctl kickstart -k` 는 **기존 plist로 프로세스만 재시작** — 새 인자 무시. 반드시:
```bash
launchctl bootout   gui/$(id -u)/com.headroom.proxy
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.headroom.proxy.plist
# headroom은 압축 모델(ModernBERT 등) 로딩에 수십 초 → health ready 대기
curl -sf http://localhost:8790/health | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["ready"],d["config"]["anthropic_api_url"])'
# → True http://127.0.0.1:8317  이어야 체인 연결됨
```

headroom 옵션: `--anthropic-api-url`, `--openai-api-url`, `--backend`. 압축 인자: `--compress-user-messages --code-aware --exclude-tools Bash`.

---

## 5. Hermes 연동

`~/.hermes/config.yaml`:
```yaml
model:
  default: claude-opus-4-8
  provider: anthropic
  base_url: http://local.anthropic.com:8790   # headroom 체인 (/etc/hosts: 127.0.0.1 local.anthropic.com)
  context_length: 1048575
  api_mode: anthropic_messages
```

- `local.anthropic.com` 은 `anthropic.com` 을 포함 → Hermes의 **OAuth 분기**(`is_oauth=True`)를 탐 → CC 위장 로직 적용.
- cliproxy 직결만 쓰려면 `http://local.anthropic.com:8317` 또는 `http://127.0.0.1:8317`.
- 모델 전환: `hermes -m claude-sonnet-4-5-20250929` / `-m gpt-5.5`(codex) / `-m gemini-3.1-pro-low`(antigravity) — 전부 cliproxy 한 엔드포인트.

### Hermes 소스 변경 (3곳, gated)

cliproxy 경유 시 Anthropic third-party 탐지를 우회하려면 Hermes가:

1. **`agent/anthropic_adapter.py`**
   - `_camelize_tool_name` / `_decamelize_tool_name` / `_use_cc_tool_cloak(base_url)` 헬퍼.
   - `build_anthropic_kwargs` 의 `is_oauth` 블록: cc_cloak이면 tool 이름을 `mcp_`+CamelCase로 (`browser_back`→`McpBrowserBack`). tools + 메시지 히스토리 tool_use 모두.
   - `build_anthropic_client` 의 OAuth 분기: cc_cloak이면 `claude-cli` User-Agent / `x-app: cli` **제거** (아래 UA 역설).
2. **`agent/transports/anthropic.py`**
   - `normalize_response(strip_tool_prefix=...)`: 응답 tool_use 이름을 registry 기반으로 복원. `McpBrowserBack`→decamelize→`mcp_browser_back`→(registry)→`browser_back`.

**게이트**: `_use_cc_tool_cloak` = base_url이 `api.anthropic.com` 직결이면 False(기존 `mcp_` 방식 유지, 회귀 없음), 프록시면 True. `HERMES_CC_TOOL_CLOAK=1/0` env로 강제.

---

## 6. 🔴 claude 400 트러블슈팅 (이 스택의 핵심 노하우)

증상: `400 You're out of extra usage` 또는 `Third-party apps now draw from your extra usage, not your plan limits`.
= Anthropic이 요청을 **공식 Claude Code가 아닌 third-party**로 분류 → 구독 plan이 아닌 extra usage(종량)에서 차감 → 잔량 0이면 400.

### 원인은 두 겹 (둘 다 충족해야 200)

**(A) tool 이름 핑거프린팅**
- snake_case API 스타일(`terminal`, `read_file`, `mcp_browser_back`) → third-party로 탐지 → 400.
- CamelCase Claude Code 스타일(`Bash`, `Read`, `McpBrowserBack`) → plan으로 메터링 → 200.
- 실증: 동일 body에서 tool 이름만 snake→Camel 바꾸면 400→200. tools 자체를 빼도 200.
- cliproxy는 tool 이름을 **rename 안 함**(7.2.15 기준) → Hermes가 직접 `mcp_`+CamelCase로 보내야 함.
- `mcp_` 세그먼트가 있어야 통과: `BrowserBack`(400) vs `McpBrowserBack`(200).

**(B) claude-cli User-Agent 역설**
- cliproxy cloak(mode auto)은 "non-Claude-Code 클라이언트만" 변환.
- Hermes가 `User-Agent: claude-cli/...` + `x-app: cli` 를 보내면 cliproxy가 "이미 진짜 CC"로 판단 → **cloak/fingerprint 처리를 스킵** → 불완전한 요청이 그대로 올라가 탐지됨.
- → cliproxy 경유 시엔 claude-cli UA를 **빼야** cliproxy가 cloak을 입혀 통과. (SDK 기본 `Anthropic/Python` UA면 OK.)
- 헤더 격리 실험: baseline 200 / +Authorization 200 / +Anthropic-Beta 200 / **+claude-cli UA & x-app → 400**.

### 진단 절차

```bash
# 진짜 Claude Code가 cliproxy로 200인지 (스택 자체 정상 확인)
ANTHROPIC_BASE_URL=http://127.0.0.1:8317 ANTHROPIC_AUTH_TOKEN=dummy claude -p "reply: OK"

# 실패 요청 본문 열람 (debug:true 필요) — tool 이름/헤더 확인
curl -s -H "Authorization: Bearer hermes-mgmt-key" http://127.0.0.1:8317/v0/management/request-error-logs
curl -s -H "Authorization: Bearer hermes-mgmt-key" -OJ \
  "http://127.0.0.1:8317/v0/management/request-error-logs/<NAME>.log"
# → HEADERS(User-Agent claude-cli?), REQUEST BODY(tools 이름 snake?), API RESPONSE(400 사유)
```

### 기타

- 작은 요청(짧은 메시지, tools 없음)은 그냥 200 — 진짜 워크로드(system+tools+큰 context)에서만 탐지. 진단은 실제 tools 포함 요청으로.
- 멀티계정 라운드로빈이라 계정마다 plan/extra 상태가 달라 200/400이 섞일 수 있음. 일관성 보려면 같은 요청을 연속 전송.
- cloak 강제(OAuth json에 `cloak_mode: always` / `cloak_strict_mode: true`)는 이 케이스에선 효과 없었음 — 진짜 해결은 (A)+(B).

---

## 7. cliproxy cloak / 헤더 옵션 (config)

- `disable-claude-cloak-mode: false`(기본) — non-CC 클라이언트를 CC로 위장.
- claude OAuth json 항목: `cloak_mode`(auto/always/never), `cloak_strict_mode`, `cloak_sensitive_words`, `experimental-cch-signing`.
- `claude-header-defaults`: user-agent/package-version 등 fingerprint. stale하면 탐지(PR #2795 = Claude Code 버전 정렬).
- 관련 이슈/PR: router-for-me/CLIProxyAPI #2599(OAuth extra-usage), #2621(tool name fingerprint + cloak + CCH), #2795/#2839(버전·tool rename).

---

## 8. 에러 대응 / fail-open

- 두 프록시 모두 **keepalive LaunchAgent** = 죽어도 자가복구 + 재부팅 자동시작.
- headroom: `claude-hr.sh` + `always-route` — health 실패 시 직결(fail-open). **글로벌 `ANTHROPIC_BASE_URL` 정적 export 금지**(SPOF).
- **Claude Code = Slack 동일 체인**: `~/.headroom/always-route` + `cc` alias가 `claude-hr.sh` 경유 → `:8790` → cliproxy `:8317`.
- cliproxy 다운 시 headroom 체인은 502 → keepalive 복구가 1차. 추가로 Hermes `fallback_providers` 고려.
- `quota-exceeded.switch-project` / `switch-preview-model` / round-robin이 계정 소진 시 자동 회전.

---

## 9. 빠른 복구 치트시트

```bash
# 전체 진단
bash ~/.claude/skills/headroom-cliproxyapi/scripts/doctor.sh [--fix]

# cliproxy 안 뜸
launchctl kickstart -k gui/$(id -u)/com.cliproxy.api
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.cliproxy.api.plist   # 미등록 시

# headroom 안 뜸 / 체인 끊김
launchctl bootout   gui/$(id -u)/com.headroom.proxy
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.headroom.proxy.plist

# claude 400 extra usage → §6 (tool 이름 CamelCase? claude-cli UA 제거? 계정 잔량?)
# Hermes Slack/Discord만 400·CLI는 OK → §10 게이트웨이 재시작 + 최신 소스 확인
# 계정 추가/재로그인 → 대시보드 http://127.0.0.1:8317/management.html
# 토큰 권한 → chmod 600 ~/.cli-proxy-api/*.json
```

---

## 10. Hermes 게이트웨이 운영 케이스 (2026-06-17)

채널 지침이 아니라 **스택·툴·게이트웨이 프로세스** 실전에서 깨진 것들.

### 케이스 A — 코드 고쳤는데 Slack만 400

| 관찰 | 의미 |
|------|------|
| `hermes -z` CLI | 200, tool 정상 |
| Slack `@Hermes` | 400 extra usage |
| 게이트웨이 PID 기동 시각 | 소스 패치 **이전** |

**원인:** 게이트웨이는 상주 프로세스 → 메모리에 옛 `anthropic_adapter` (cc_cloak 없음, snake_case tool).

**복구:**
```bash
launchctl kickstart -k "gui/$(id -u)/ai.hermes.gateway"
# 로그: gateway.log에 새 기동 시각, 이후 cliproxy POST /v1/messages 200
```

### 케이스 B — config 바꿨는데 채널 동작 안 바뀜

`slack.channel_prompts`, `channel_skill_bindings`, `free_response_channels` 는 어댑터 **기동 시**만 로드. 파일 저장만으로는 반영 안 됨 → **게이트웨이 재시작** (§10 케이스 A와 동일 명령).

반면 `channel_roles/slack/*.md`, `events.json`, 크론 `jobs.json` 은 에이전트가 런타임 `read_file` — 재시작 불필요.

### 케이스 C — 툴콜은 되는데 “작업 없음”만 응답

스택/cc_cloak 문제가 **아님**. `api_calls=1`, tool 미호출 = 모델 판단. 채널에 `channel_prompts`/role 없으면 일반 모드.

→ 채널 지침은 별도 작업. **운영 관점:** `api_calls`·`gateway.log`·`errors.log`로 스택 vs 프롬프트 분리 진단.

### 케이스 D — cc_cloak encode/decode 게이트 (2026-06-19 근본 수정)

| 방향 | 게이트 (수정 후) |
|------|--------|
| 요청 (tool 이름 CamelCase) | `_use_cc_tool_cloak(base_url)` — 프록시면 ON |
| 응답 (decamelize 복원) | `strip_tool_prefix = _is_anthropic_oauth OR _use_cc_tool_cloak(base_url)` |

**과거 버그**: 응답 게이트가 `_is_anthropic_oauth`만 봐서, 직결이 아닌데(=프록시) OAuth가 꺼지면 **응답의 `McpTerminal`이 안 풀려 tool 실행이 깨짐**(요청은 cloak하는데 응답은 복원 안 하는 비대칭).
**수정** (`conversation_loop.py` 메인 3601 / truncation 1708 두 지점):
```python
strip_tool_prefix = (
    agent._is_anthropic_oauth
    or _use_cc_tool_cloak(
        getattr(agent, "_anthropic_base_url", None) or getattr(agent, "base_url", None)
    )
)
```
\+ `chat_completion_helpers.py`: `base_url=(_anthropic_base_url or agent.base_url)` fallback (None이면 cloak 판정 실패하던 것 보강).
검증: `hermes -z "Run terminal: echo TOOLCALL_WORKS"` → `TOOLCALL_WORKS` + cliproxy 신규 400 없음.
임시 회피(코드 못 고칠 때): `HERMES_CC_TOOL_CLOAK=1`.

> ⚠️ **최종 가드 (변형 미들웨어 버전용)**: byz처럼 `apply_llm_request_middleware`로 **api_kwargs 빌드 후 페이로드를 변형**하는 버전은 위 게이트만으로 부족 — API 호출 직전 `_ensure_local_anthropic_cc_cloak(agent, api_kwargs)`로 system prefix 재주입 + tool 이름 재-CamelCase + beta 헤더(`claude-code-20250219`,`oauth-2025-04-20`) 병합을 한 번 더. 변형 경로가 없는 버전(`pre_api_request` hook이 read-only)에선 `build_anthropic_kwargs`가 이미 cloak하므로 **불필요**(중복 방어 생략).

### 케이스 E — 멀티 프로필 게이트웨이

```bash
pgrep -fl 'hermes_cli.main.*gateway'
# 예: pid 4447 → 기본 ~/.hermes (Slack hermes-hajun 등)
#     pid 665  → --profile zion (별도 HERMES_HOME)
```

재시작·진단 시 **어느 프로필이 해당 채널을 처리하는지** 먼저 확인.

### 케이스 F — 게이트웨이 재시작 무한루프 (알림 폭탄) [2026-06-19, #30719 계열]

**증상:** 게이트웨이가 ~10초 주기로 죽고 살아남(`launchctl print … gateway` 의 `runs`가 수백으로 폭증), Slack home 채널에 shutdown/startup 알림 폭탄. `hermes -z` CLI는 정상인데 상주 게이트웨이만 미친 듯 재시작.

**진범 = 삼중 자가복구가 서로 물림:**
1. 누군가 `hermes gateway restart`를 실행 → ① launchd `kickstart -k` + ② **detached respawn watcher**(`launch_detached_profile_gateway_restart`, old_pid 죽으면 `gateway run` 재spawn) **동시 발동** → 기본 프로필 게이트웨이가 두 갈래로 살아나 충돌(SIGTERM flap, "same bot token").
2. **keepalive**(plist `SuccessfulExit=0`)가 exit 1을 재시작으로 받음.
3. **auto-resume**(`_schedule_resume_pending_sessions`)이 "재시작으로 중단된 세션"을 부활 → 그 세션이 바로 "게이트웨이 재시작" 작업이라 **또 restart 실행** → ∞.

**최초 트리거:** Slack 채널에 **"게이트웨이 재시작"류 메시지**를 보내면 게이트웨이 에이전트가 "내가 재시작 명령을 실행하라"로 해석하고 자기 자신을 죽이는 경로로 감. (Defense 1 `_HERMES_GATEWAY=1`은 `hermes gateway restart` CLI만 막고, 에이전트가 `launchctl kickstart -k`를 Bash로 직접 때리면 우회됨.)

**진단 (read-only):**
```bash
launchctl print "gui/$(id -u)/ai.hermes.gateway" | grep -E 'state|runs'   # runs 폭증?
grep "Shutdown context" ~/.hermes/logs/gateway.log | tail   # signal=SIGTERM parent_pid=1 under_systemd=yes 10초 주기
grep -c "Scheduled auto-resume" ~/.hermes/logs/gateway.log  # 증폭기 동작 흔적
```

**복구 (정지 → 좀비 차단 → 재기동):**
```bash
UID=$(id -u)
launchctl bootout "gui/$UID/ai.hermes.gateway-watchdog"   # 워치독 먼저(5분 부활 차단)
launchctl bootout "gui/$UID/ai.hermes.gateway"
for p in $(pgrep -f 'hermes_cli.main gateway run'); do ps -o command= -p $p | grep -q 'profile zion' || kill -TERM $p; done
# 좀비 세션 차단 (근본): sessions.json에서 resume_pending=true 세션을 false로 (백업 필수).
#   reason {restart_timeout, shutdown_timeout, restart_interrupted} 이 auto-resume 대상.
#   임시 대안: config.yaml agent.gateway_auto_continue_freshness 를 1로 낮춰 재기동 후 원복.
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/ai.hermes.gateway.plist
sleep 60; launchctl print "gui/$UID/ai.hermes.gateway" | grep -E 'state|runs'   # runs=1 유지?
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/ai.hermes.gateway-watchdog.plist
```

**예방:** 게이트웨이 재시작은 **Slack/Discord 채널 메시지로 시키지 말 것**. 터미널에서 직접 `launchctl kickstart -k "gui/$(id -u)/ai.hermes.gateway"`. 워치독(`hermes_gateway_watchdog.sh`)은 `--replace`를 안 부르고 단순 kickstart만 하므로 이 루프의 범인이 아님(무죄).

### 검증 체크리스트 (패치/재시작 후)

1. `doctor.sh` — cliproxy + headroom + 스모크 200
2. `hermes -z` — tool round-trip (`TOOLCALL_WORKS`)
3. 게이트웨이 재시작
4. 메시징 1회 — `gateway.log`에서 `api_calls≥1`, cliproxy 200, `errors.log` 신규 400 없음

---

## 11. Discord 플랫폼

Hermes 게이트웨이의 Discord 어댑터도 **동일 model.base_url 스택**을 탄다. cc_cloak·extra usage 트러블슈팅은 §6과 동일.

### config (`~/.hermes/config.yaml`)

```yaml
discord:
  require_mention: true
  free_response_channels: ''      # 채널 ID CSV — 멘션 없이 응답 허용
  allowed_channels: ''            # 비우면 전체 허용(토큰 권한 내)
  auto_thread: true
  thread_require_mention: false
  channel_prompts: {}             # Slack과 동일 패턴 — 채널/스레드 ID → 지침 문자열
  channel_skill_bindings: []      # Slack과 동일 — 자동 skill 로드 (신중히)
```

- **Slack과 독립** — `slack.channel_prompts`가 Discord에 주입되지 않음.
- Discord 지침·skill 바인딩 변경 → **게이트웨이 재시작** (§10 케이스 B).

### toolset `hermes-discord`

게이트웨이 Discord 세션 기본 번들 (`tools.discord` in config):

- `discord` — 메시지/임베드/DM (`tools/discord_tool.py`)
- `discord_admin` — 모더레이션 (권한 필요)

에이전트가 Discord API를 직접 쓸 때만 로드. LLM API 경로(cliproxy)와 무관.

### 시크릿

`~/.hermes/.env`:
- `DISCORD_BOT_TOKEN` — 봇 토큰
- (선택) `DISCORD_ALLOWED_USERS`, `DISCORD_ALLOWED_CHANNELS` — allowlist

설정 후 `hermes gateway setup` 또는 config 편집 + 재시작.

### Discord 트러블슈팅 빠른 표

| 증상 | 먼저 볼 것 |
|------|------------|
| 봇 온라인인데 무응답 | `require_mention`, 채널 invite, `allowed_channels` |
| 400 extra usage | §6 + **게이트웨이 재시작**(§10 A) |
| config 바꿨는데 동일 | 게이트웨이 재시작 (§10 B) |
| tool 이름 깨짐 | cc_cloak §6 + §10 D |

Slack 전용 진단: `hermes-slack-troubleshooting` skill. Discord는 위 + `gateway.log`의 `platform=discord` 라인.
