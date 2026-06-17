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
| CLIProxyAPI config | `~/.cli-proxy-api/config.yaml` (port 8317, api-keys:[], secret-key: hermes-mgmt-key) |
| OAuth 토큰 (계정) | `~/.cli-proxy-api/{claude,codex,antigravity}-*.json` (권한 600) |
| CLIProxyAPI 자동시작 | `~/Library/LaunchAgents/com.cliproxy.api.plist` (keepalive+runatload) |
| 대시보드 | `http://127.0.0.1:8317/management.html` (key: secret-key) |
| headroom 자동시작 | `~/Library/LaunchAgents/com.headroom.proxy.plist` (`--anthropic-api-url http://127.0.0.1:8317`) |
| Hermes 연동 | `~/.hermes/config.yaml` → `model.base_url: http://local.anthropic.com:8790` |
| 로그 | `~/Library/Logs/cliproxy/`, `~/Library/Logs/headroom/` |

## doctor — 한 방 진단

```bash
bash ~/.claude/skills/headroom-cliproxyapi/scripts/doctor.sh        # 진단만 (read-only)
bash ~/.claude/skills/headroom-cliproxyapi/scripts/doctor.sh --fix  # 안전한 복구(kickstart)까지
```

점검 항목: ① cliproxy ② OAuth ③ headroom 체인 ④ Hermes config ⑤ **게이트웨이(Slack/Discord)** ⑥ claude tool 스모크.

## 자주 쓰는 명령

```bash
# 상태
launchctl print gui/$(id -u)/com.cliproxy.api | grep state
curl -sf http://127.0.0.1:8317/v1/models | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]),"models")'
curl -sf http://localhost:8790/health | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["ready"],d["config"]["anthropic_api_url"])'

# 계정 추가(멀티계정 회전) — 브라우저 OAuth
~/.cli-proxy-api/bin/cli-proxy-api -claude-login -config ~/.cli-proxy-api/config.yaml
#  또는 대시보드 http://127.0.0.1:8317/management.html 에서 Add account

# cliproxy 재기동(프로세스만)
launchctl kickstart -k gui/$(id -u)/com.cliproxy.api

# headroom 인자 변경 후엔 반드시 bootout→bootstrap (kickstart는 인자 반영 안 함)
launchctl bootout gui/$(id -u)/com.headroom.proxy
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.headroom.proxy.plist
```

## ⚠️ 핵심 함정 (오늘 다 깨진 것들)

1. **claude 400 "extra usage"** = Anthropic이 요청을 third-party로 분류. 원인 두 겹:
   - **tool 이름 핑거프린팅**: snake_case(`terminal`)면 third-party, CamelCase(`McpTerminal`)면 plan. → Hermes가 `mcp_`+CamelCase로 보냄.
   - **claude-cli UA 역설**: Hermes가 `claude-cli` UA를 보내면 cliproxy가 "이미 진짜 CC"로 보고 cloak을 **스킵** → 탐지됨. cliproxy 경유 시엔 UA를 **빼야** cliproxy가 cloak.
2. **headroom plist 인자 변경**: `kickstart -k`는 반영 안 함. `bootout`→`bootstrap` 필수.
3. **OAuth 콜백 실패**: `-claude-login` 프로세스를 폴링 중단(SIGINT)으로 죽이면 54545 콜백 리스너가 사라져 리다이렉트 실패. 대시보드(`is_webui`) 방식은 콜백을 메인 포트(8317)가 받아 안전.
4. **글로벌 `ANTHROPIC_BASE_URL` 정적 export 금지** (SPOF). 프록시 죽으면 전 세션 마비. fail-open 래퍼/프로젝트 레벨로만.
5. **Hermes 게이트웨이 재시작** — `config.yaml`·소스 패치 후 **반드시** 재기동. CLI(`hermes -z`)는 매번 새 프로세스라 최신 코드, **상주 게이트웨이는 옛 코드**를 들고 있을 수 있음 → Slack/Discord만 400, CLI는 정상인 역설.
6. **cc_cloak encode/decode 게이트 불일치** — 요청은 `_use_cc_tool_cloak(base_url)`, 응답 복원은 `_is_anthropic_oauth`. 환경에 따라 한쪽만 동작할 수 있음. 이상 시 `HERMES_CC_TOOL_CLOAK=1` 강제 + 게이트웨이 재시작.

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
