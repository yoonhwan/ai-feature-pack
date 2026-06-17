# cliproxyapi — 올인원 설치 (에이전트용)

에이전트에게: **"feature-pack/cliproxyapi/INSTALL.md 읽고 설치해줘"**

## 목표

```
Hermes (패치 적용 시) → headroom :8790 → CLIProxyAPI :8317 → 구독 OAuth
```

**사용자가 직접 하는 것은 대시보드 OAuth 로그인뿐.** 나머지는 에이전트가 설치·기동·검증한다.

## Prerequisites

- macOS **Apple Silicon** (arm64). Intel/Linux는 `references/playbook.md` §1 경로 조정.
- `python3.12+`, `curl`, `git`
- 레포 클론:

```bash
git clone https://github.com/yoonhwan/ai-feature-pack.git ~/ai-feature-pack
cd ~/ai-feature-pack
```

- **headroom** 미설치 시 `feature-pack/headroom/README.md` STEP 1~1.5 + LaunchAgent 먼저 (또는 본 INSTALL STEP 2).

## SSOT

| 문서 | 경로 |
|------|------|
| 설치·트러블슈팅 정본 | `feature-pack/cliproxyapi/references/playbook.md` |
| headroom | `feature-pack/headroom/README.md` |
| Hermes 패치 | `feature-pack/cliproxyapi/patches/hermes-cc-cloak.patch` |
| 진단 | `feature-pack/cliproxyapi/scripts/doctor.sh` |

---

## STEP 1 — CLIProxyAPI 7.2.15

```bash
CPA_ROOT=~/ai-feature-pack/feature-pack/cliproxyapi
curl -fsSL -o /tmp/cpa.tar.gz \
  https://github.com/router-for-me/CLIProxyAPI/releases/download/v7.2.15/CLIProxyAPI_7.2.15_darwin_aarch64.tar.gz
mkdir -p /tmp/cpa ~/.cli-proxy-api/bin ~/Library/Logs/cliproxy
tar -xzf /tmp/cpa.tar.gz -C /tmp/cpa
cp /tmp/cpa/cli-proxy-api ~/.cli-proxy-api/bin/
chmod +x ~/.cli-proxy-api/bin/cli-proxy-api
~/.cli-proxy-api/bin/cli-proxy-api --version
```

`~/.cli-proxy-api/config.yaml`:

```yaml
host: "127.0.0.1"
port: 8317
auth-dir: "~/.cli-proxy-api"
api-keys: []
remote-management:
  allow-remote: false
  secret-key: "hermes-mgmt-key"
debug: false
routing:
  strategy: "round-robin"
```

LaunchAgent `~/Library/LaunchAgents/com.cliproxy.api.plist` — `references/playbook.md` §3 XML (`$HOME` 치환, KeepAlive+RunAtLoad).

```bash
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.cliproxy.api.plist
curl -sf http://127.0.0.1:8317/v1/models | head -c 200
```

---

## STEP 2 — headroom → cliproxy 체인

```bash
python3.12 -m venv ~/.headroom-venv
~/.headroom-venv/bin/pip install "headroom-ai[all]"
bash ~/ai-feature-pack/feature-pack/headroom/patches/apply.sh
mkdir -p ~/Library/Logs/headroom
```

LaunchAgent `~/Library/LaunchAgents/com.headroom.proxy.plist` — ProgramArguments에 포함:

- `--port 8790`
- `--compress-user-messages`
- `--exclude-tools Bash`
- `--code-aware`
- `--anthropic-api-url http://127.0.0.1:8317`

```bash
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.headroom.proxy.plist
# 30~60초 대기 후:
curl -sf http://localhost:8790/health
```

`/etc/hosts` (없으면 추가): `127.0.0.1  local.anthropic.com`

⚠️ plist 인자 변경은 `bootout` → `bootstrap` 필수 (`kickstart -k`만으로는 인자 미반영).

---

## STEP 3 — 스킬 배치

```bash
PACK=~/ai-feature-pack/feature-pack/cliproxyapi
mkdir -p ~/.claude/skills/headroom-cliproxyapi/{scripts,references}
cp "$PACK/SKILL.md" ~/.claude/skills/headroom-cliproxyapi/
cp "$PACK/scripts/doctor.sh" ~/.claude/skills/headroom-cliproxyapi/scripts/
cp "$PACK/references/playbook.md" ~/.claude/skills/headroom-cliproxyapi/references/
chmod +x ~/.claude/skills/headroom-cliproxyapi/scripts/doctor.sh
```

---

## STEP 4 — Hermes 연동 (선택, hermes-agent 있을 때)

```bash
cd /path/to/hermes-agent
git apply ~/ai-feature-pack/feature-pack/cliproxyapi/patches/hermes-cc-cloak.patch
```

`~/.hermes/config.yaml`:

```yaml
model:
  default: claude-opus-4-8
  provider: anthropic
  base_url: http://local.anthropic.com:8790
  api_mode: anthropic_messages
```

게이트웨이 사용 시 **반드시 재시작**:

```bash
launchctl kickstart -k "gui/$(id -u)/ai.hermes.gateway"
# 또는: hermes gateway restart
```

---

## STEP 5 — ⛔ 사용자 OAuth (에이전트 멈춤)

사용자에게만 안내:

1. `http://127.0.0.1:8317/management.html`
2. Management key: **`hermes-mgmt-key`**
3. **Add account** → Claude / Codex / Antigravity(Gemini)
4. CLI `-claude-login` 폴링 중단(Ctrl-C) **금지** — 대시보드만

"로그인 완료" 후:

```bash
chmod 600 ~/.cli-proxy-api/*.json
ls ~/.cli-proxy-api/*.json
```

---

## STEP 6 — 검증

```bash
bash ~/.claude/skills/headroom-cliproxyapi/scripts/doctor.sh
# 기대: ✅ 스택 정상

# Hermes 있으면:
hermes -z -q "Run terminal: echo STACK_OK"
```

실패 시 `references/playbook.md` §6, §10, §11.

---

## 완료 보고

1. cliproxy / headroom LaunchAgent state
2. OAuth 계정 파일명 (토큰 내용 X)
3. doctor.sh 요약
4. Hermes 패치·gateway 재시작 여부
5. 대시보드 로그인 안내 완료
