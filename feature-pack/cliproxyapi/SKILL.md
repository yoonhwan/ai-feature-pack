---
name: headroom-cliproxyapi
description: 헤드룸·CLIProxyAPI 구독 프록시 스택 + Hermes 게이트웨이(Slack/Discord) 운영·진단. cliproxy/headroom/8790/8317, claude 400 extra usage, cc_tool_cloak, 게이트웨이 재시작, tool round-trip, Discord config·hermes-discord toolset, doctor.
---

# proxy-stack — 구독 프록시 스택 관리·진단

Claude/Codex/Gemini **구독(Pro/Max/Plus)** 을 API처럼 쓰는 로컬 스택을 한 세트로 관리한다.
핵심 가치: 구독 OAuth를 **plan limit**으로 메터링시키고(third-party "extra usage" 회피), 멀티계정 회전 + 컨텍스트 압축을 동시에.

```
Hermes (CC 위장 + tool name cloak)
  → headroom :8790    컨텍스트 압축 (code-aware), keepalive, fail-open
  → CLIProxyAPI :8317 멀티계정 OAuth 회전 + cloak + 프로토콜 변환, keepalive
  → Anthropic · OpenAI(codex) · Gemini(antigravity)   전부 구독 plan
```

> 순서는 바꿔도 됨(직결도 가능). 목표는 **스택을 유지해 압축(headroom) + 멀티계정/cloak(cliproxy) 두 피처를 동시에** 살리는 것.

## When to Use

- "스택/프록시 점검", "cliproxy 상태", "헤드룸 체인 확인", "doctor"
- `claude` 가 `400 You're out of extra usage` / `Third-party apps now draw from your extra usage` 로 막힐 때
- 재부팅 후 스택이 떠 있는지 확인
- 멀티계정 추가/회전, OAuth 재로그인
- Hermes가 갑자기 구독이 아닌 API 과금으로 새는 의심

## 핵심 파일 / 포트

| 항목 | 경로 / 값 |
|---|---|
| CLIProxyAPI binary | `~/.cli-proxy-api/bin/cli-proxy-api` (7.2.15 고정) |
| CLIProxyAPI config | `~/.cli-proxy-api/config.yaml` (port 8317, api-keys:[], secret-key: hermes-mgmt-key, **`routing.strategy: fill-first`**) |
| OAuth 토큰 (계정) | `~/.cli-proxy-api/{claude,codex,antigravity}-*.json` (권한 600) |
| CLIProxyAPI 자동시작 | `~/Library/LaunchAgents/com.cliproxy.api.plist` (keepalive+runatload) |
| 대시보드 | `http://127.0.0.1:8317/management.html` (key: secret-key) |
| headroom 자동시작 | `~/Library/LaunchAgents/com.headroom.proxy.plist` (`--anthropic-api-url http://127.0.0.1:8317`) |
| Hermes 연동 | `~/.hermes/config.yaml` → `model.base_url: http://local.anthropic.com:8790` |
| Claude Code (`cc`/`ccf`/`ccs`) | `~/.headroom/claude-hr.sh` + `~/.headroom/always-route` → `http://localhost:8790` (Slack과 동일 체인) |
| Codex CLI | `~/.codex/config.toml` → `model_provider = "headroom"`, `base_url = "http://127.0.0.1:8790/v1"`, `wire_api = "responses"` |
| 로그 | cliproxy: `~/Library/Logs/cliproxy/proxy.log`, headroom 요청 로그: `~/.headroom/logs/proxy.log`, headroom launchd stderr: `~/Library/Logs/headroom/proxy-error.log` |

## doctor — 한 방 진단

```bash
bash ~/.claude/skills/headroom-cliproxyapi/scripts/doctor.sh        # 진단만 (read-only)
bash ~/.claude/skills/headroom-cliproxyapi/scripts/doctor.sh --fix  # 안전한 복구(kickstart)까지
```

점검 항목: ① cliproxy ② OAuth ③ headroom 체인 ④ Hermes config ⑤ **게이트웨이(Slack/Discord)** ⑥ claude tool 스모크 ⑦ Codex route/log 검증 절차.

## Codex 적용 — Responses API도 headroom 경유

Codex는 `ANTHROPIC_BASE_URL` 래퍼가 아니라 Codex custom provider로 고정한다. 기존 alias가 단순 `npx -y @openai/codex`면 headroom이 죽어도 Codex는 직접 OpenAI로 살아 있을 수 있다.

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
# ~/.zshrc — 로컬 프록시용 더미 auth. 실제 구독 인증은 cliproxy OAuth upstream.
export CODEX_DUMMY_API_KEY="${CODEX_DUMMY_API_KEY:-dummy}"
```

적용 확정은 **동작 테스트 + 양쪽 로그**로만 한다:

```bash
CODEX_DUMMY_API_KEY="${CODEX_DUMMY_API_KEY:-dummy}" \
  codex exec --skip-git-repo-check --ephemeral -C "$HOME" \
  'Return exactly CODEX_HEADROOM_OK.'

# headroom 로그: path=/v1/responses, user-agent=codex_exec, forwarder=openai_responses,
# url=http://127.0.0.1:8317/v1/responses 가 보여야 함
grep -E 'codex_exec|/v1/responses|openai_responses|127\.0\.0\.1:8317' \
  ~/.headroom/logs/proxy.log 2>/dev/null | tail -30

# cliproxy 로그: /v1/responses 200 또는 OpenAI/codex provider 처리가 보여야 함
grep -E '/v1/responses|codex|openai|status=200' \
  ~/Library/Logs/cliproxy/proxy.log 2>/dev/null | tail -30
```

주의: 이 경로는 의도적으로 fail-open이 아니다. headroom/cliproxy 수리용 Codex 세션은 `codex --ignore-user-config` 또는 provider override로 직접 띄운다.

## 자주 쓰는 명령

```bash
# 상태
launchctl print gui/$(id -u)/com.cliproxy.api | grep state
curl -sf http://127.0.0.1:8317/v1/models | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]),"models")'
curl -sf http://localhost:8790/health | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["ready"],d["config"]["anthropic_api_url"])'

# 계정 추가(멀티계정 회전) — 브라우저 OAuth
~/.cli-proxy-api/bin/cli-proxy-api -claude-login -config ~/.cli-proxy-api/config.yaml
#  또는 대시보드 http://127.0.0.1:8317/management.html 에서 Add account

# 라우팅 전략 — 기본은 fill-first (강력 권장)
#  config.yaml: routing.strategy: "fill-first"   ← 변경 후 반드시 kickstart 재기동
#  fill-first  = 한 계정을 quota/rate-limit 소진까지 고정 → 소진 시 다음 계정 (DEFAULT)
#  round-robin = 요청마다 계정 균등 분산 → prompt cache가 매 요청 miss (캐시는 계정 단위) = 비권장
#  why: BYZ 비용 ~93%가 캐시. round-robin은 캐시를 매번 깨서 quota·비용 둘 다 손해.

# cliproxy 재기동(프로세스만)
launchctl kickstart -k gui/$(id -u)/com.cliproxy.api

# headroom plist 변경 후 안전 재로드 (kickstart는 plist 인자/env 변경을 반영 안 함)
# 절대 `; echo "bootstrap 완료"`처럼 반환코드를 숨기지 말 것.
UID_NUM="$(id -u)"
PL="$HOME/Library/LaunchAgents/com.headroom.proxy.plist"
plutil -lint "$PL" || exit 1
launchctl bootout "gui/$UID_NUM/com.headroom.proxy" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  launchctl print "gui/$UID_NUM/com.headroom.proxy" >/dev/null 2>&1 || break
  sleep 0.5
done
launchctl bootstrap "gui/$UID_NUM" "$PL" || exit 1
launchctl enable "gui/$UID_NUM/com.headroom.proxy" || true
for try in 1 2 3 4 5 6 7 8 9 10; do
  curl -sf http://localhost:8790/health >/dev/null && { echo "headroom ready"; break; }
  sleep 1
  [ "$try" = 10 ] && { echo "headroom health failed"; exit 1; }
done
```

## ⚠️ 핵심 함정 (오늘 다 깨진 것들)

1. **claude 400 "extra usage"** = Anthropic이 요청을 third-party로 분류. 원인 두 겹:
   - **tool 이름 핑거프린팅**: snake_case(`terminal`)면 third-party, CamelCase(`McpTerminal`)면 plan. → Hermes가 `mcp_`+CamelCase로 보냄.
   - **claude-cli UA 역설**: Hermes가 `claude-cli` UA를 보내면 cliproxy가 "이미 진짜 CC"로 보고 cloak을 **스킵** → 탐지됨. cliproxy 경유 시엔 UA를 **빼야** cliproxy가 cloak.
2. **headroom plist 인자 변경**: `kickstart -k`는 반영 안 함. `bootout`→`bootstrap` 필수.
3. **OAuth 콜백 실패**: `-claude-login` 프로세스를 폴링 중단(SIGINT)으로 죽이면 54545 콜백 리스너가 사라져 리다이렉트 실패. 대시보드(`is_webui`) 방식은 콜백을 메인 포트(8317)가 받아 안전.
4. **글로벌 `ANTHROPIC_BASE_URL` 정적 export 금지** (SPOF). 프록시 죽으면 전 세션 마비. fail-open 래퍼/프로젝트 레벨로만.
5. **Hermes 게이트웨이 재시작** — `config.yaml`·소스 패치 후 **반드시** 재기동. CLI(`hermes -z`)는 매번 새 프로세스라 최신 코드, **상주 게이트웨이는 옛 코드**를 들고 있을 수 있음 → Slack/Discord만 400, CLI는 정상인 역설.
6. **cc_cloak encode/decode 게이트 불일치** — 요청은 `_use_cc_tool_cloak(base_url)`로 tool 이름을 CamelCase cloak하는데 응답 복원(strip)이 `_is_anthropic_oauth`만 보면, **로컬 프록시(OAuth 아님)에서 응답의 `Mcp*` 이름이 안 풀려 tool 실행이 깨진다**(비대칭). **근본 수정(2026-06-19)**: `conversation_loop.py`의 두 `normalize_response` 지점(메인 3601 / truncation 1708) `strip_tool_prefix`를 `_is_anthropic_oauth OR _use_cc_tool_cloak(base_url)`로 게이트 일치 + `chat_completion_helpers.py` base_url에 `or agent.base_url` fallback. 검증: `hermes -z "Run terminal: echo TOOLCALL_WORKS"` → `TOOLCALL_WORKS`. (임시 회피는 여전히 `HERMES_CC_TOOL_CLOAK=1`.)
7. **게이트웨이 재시작 무한루프 (알림 폭탄)** — Slack/Discord 채널에 "게이트웨이 재시작"류 메시지를 보내면 에이전트가 자기 자신을 `launchctl kickstart -k`로 죽임 → **keepalive + detached respawn watcher + auto-resume** 삼중 자가복구가 물려 ~10초 주기 무한 재시작(`runs` 폭증). 증상: `Shutdown context: signal=SIGTERM parent_pid=1 under_systemd=yes` 10초 간격. **게이트웨이 재시작은 채널 말고 터미널에서 직접** `launchctl kickstart -k`. 복구: 게이트웨이+워치독 bootout → 좀비 세션 `resume_pending=false`(sessions.json) → 재기동. 상세 `references/playbook.md` §10 케이스 F.
8. **Codex가 장애 중에도 살아 있으면** 대개 `~/.codex/config.toml`에 headroom provider가 없고 alias가 직접 OpenAI로 나간 상태다. 적용 후엔 `/v1/responses`가 headroom `:8790` → cliproxy `:8317`로 찍혀야 하며, headroom이 죽으면 Codex도 의도적으로 실패한다.

상세 노하우·재현 절차·트러블슈팅 전체는 `references/playbook.md`.

## Hermes 게이트웨이 (Slack · Discord 공통)

스택·cc_cloak은 **플랫폼 무관** — 게이트웨이가 띄운 에이전트의 모든 LLM 호출에 적용.

```bash
# 재시작 (macOS LaunchAgent — 기본 ~/.hermes 프로필)
launchctl kickstart -k "gui/$(id -u)/ai.hermes.gateway"

# 또는 CLI
hermes gateway restart

# 확인
tail -5 ~/.hermes/logs/gateway.log    # slack/discord connected
pgrep -fl 'hermes_cli.main.*gateway'  # zion 등 다른 프로필 PID 별도 확인
```

**재시작이 필요한 변경:** `model.base_url`, `slack.*` / `discord.*` (`channel_prompts`, `channel_skill_bindings`, `free_response_channels`), Hermes 소스(`anthropic_adapter.py` 등).

**재시작 불필요:** `events.json`, 크론 `jobs.json`, `channel_roles/*.md` (에이전트가 `read_file`로 읽음).

## 툴 round-trip 스모크 (게이트웨이 재시작 후)

```bash
# CLI — 한 턴 tool 호출
hermes -z -q "Run terminal: echo TOOLCALL_WORKS"

# 게이트웨이 로그 — api_calls>1, cliproxy 200
tail -20 ~/.hermes/logs/gateway.log ~/.hermes/logs/agent.log
```

Discord도 동일 스택. Discord 전용 설정·도구는 `references/playbook.md` §11.

## 정책

- 두 프록시 모두 **keepalive LaunchAgent** = 죽어도 자가복구 + 재부팅 자동시작.
- headroom은 `claude-hr.sh` **fail-open**(health 실패 시 직결). cliproxy는 keepalive가 1차 방어.
- OAuth 토큰 파일은 항상 **600**. 대시보드 secret-key는 localhost 전용.
- 버전 업그레이드는 신중히 — Anthropic의 third-party 탐지 vs cliproxy cloak는 버전 추격전이라, 동작하는 버전(현재 7.2.15)을 고정.
