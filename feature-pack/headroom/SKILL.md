---
name: headroom
description: Per-project headroom 압축 프록시 토글. "/headroom on", "/headroom off", "/headroom status", "헤드룸 켜", "헤드룸 꺼", "헤드룸 상태" 요청 시 실행. 현재 프로젝트를 enabled-projects.json에 등록/해제해 영구 on/off. 사용자가 프로젝트·크루별로 직접 컨트롤하며 자동 활성화하지 않는다.
---

# headroom — per-project 압축 프록시 토글

headroom은 컨텍스트(tool 출력/로그/RAG)를 LLM 도달 전에 압축하는 로컬 프록시(포트 8790). 이 스킬은 **현재 프로젝트 단위로 영구 on/off**를 관리한다.

> ⚠️ **자동 활성화 금지.** 사용자가 명시적으로 `on`을 호출한 프로젝트만 8790을 경유한다. 토글은 세션을 가로질러 영구 유지된다.

## 핵심 파일

| 파일 | 역할 |
|---|---|
| `~/.headroom/enabled-projects.json` | 활성 프로젝트 root 절대경로 **배열** (always-route OFF일 때 opt-in) |
| `~/.headroom/disabled-projects.json` | always-route ON일 때 **opt-out** ( `/headroom off` ) |
| `~/.headroom/always-route` | 존재 시 **모든 프로젝트** 기본 headroom 경유 (Hermes Slack과 동일 정책) |
| `~/.headroom/claude-hr.sh` | fail-open 래퍼. `(always-route OR 등록) AND NOT disabled AND health OK` → 8790 |
| `~/.headroom-venv/bin/python` | 프록시 실행 venv |
| `~/.codex/config.toml` | Codex custom provider. `model_provider = "headroom"` → `http://127.0.0.1:8790/v1` |
| `~/.zshrc` | Codex provider용 `CODEX_DUMMY_API_KEY=dummy` 기본값. 실제 구독 인증은 cliproxy OAuth가 처리 |

현재 프로젝트 root는 **canonical root**로 판정한다 — `git rev-parse --path-format=absolute --git-common-dir`의 dirname(실패 시 `pwd`). 메인 체크아웃과 모든 워크트리가 **동일 root**로 매핑되므로, 한 번 `on`하면 그 프로젝트의 워크트리 전체가 커버된다(`--show-toplevel`은 워크트리별 경로를 반환해 매칭 실패 → 사용 안 함).

---

## `/headroom on` — 현재 프로젝트 영구 활성

1. 프로젝트 root를 레지스트리 배열에 추가(중복 방지):
```bash
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; PROJECT_ROOT="$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || pwd)"
python3 - "$HOME/.headroom/enabled-projects.json" "$PROJECT_ROOT" <<'PY'
import json, sys, os
reg_path, root = sys.argv[1], os.path.realpath(sys.argv[2])
try: reg = json.load(open(reg_path))
except Exception: reg = []
reg = [os.path.realpath(p) for p in reg]
if root not in reg:
    reg.append(root)
json.dump(sorted(set(reg)), open(reg_path, "w"), indent=2, ensure_ascii=False)
print("✅ 활성:", root)
PY
```

2. 프록시 가동 확인 → **이미 떠 있으면 절대 새 프로세스를 spawn하지 않는다**(중복 bind = `Errno48 Address already in use` 크래시루프, 2026-06-09 실제 사건). 단일 인스턴스는 LaunchAgent가 보장한다:
```bash
# (a) 8790 LISTEN 중이면 재사용 — health OK면 그대로 끝 (spawn 금지)
if lsof -nP -iTCP:8790 -sTCP:LISTEN >/dev/null 2>&1; then
  curl -sf -m1 http://localhost:8790/health >/dev/null 2>&1 \
    && { echo "✅ 프록시 이미 가동 — 재사용 (spawn 안 함)"; return 0 2>/dev/null || true; } \
    || echo "⚠️ 8790 LISTEN이나 health 실패(좀비 의심) — 아래 kickstart로 재기동만"
else
  echo "⚠️ 프록시 미기동 — LaunchAgent로 기동 (raw python spawn 금지)"
fi
# (b) LaunchAgent가 단일 관리 인스턴스 보장 — 미기동/불건전일 때만:
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.headroom.proxy.plist 2>/dev/null
launchctl enable    gui/$(id -u)/com.headroom.proxy 2>/dev/null
launchctl kickstart -k gui/$(id -u)/com.headroom.proxy 2>/dev/null   # 좀비면 강제 재기동(중복 spawn 아님)
sleep 1; curl -sf -m1 http://localhost:8790/health >/dev/null 2>&1 && echo "✅ 프록시 가동(8790)" || echo "🔴 기동 실패 — 로그 확인: ~/Library/Logs/headroom/proxy-error.log"
```

> ⚠️ **raw `python -m headroom.proxy.server`를 더 이상 안내하지 않는 이유:** 여러 세션이 동시에 `on`하면 각자 8790에 bind를 시도해 `Errno48` 크래시루프가 난다(2026-06-09 사건). `KeepAlive` LaunchAgent는 **단일 인스턴스**를 유지하고 죽어도 자동 부활하므로, `on`은 "떠 있으면 재사용, 없으면 launchctl로만 기동"한다. 동시에 여러 세션이 `on`해도 launchctl이 단일 인스턴스로 수렴시킨다.

3. 사용자에게 안내: 이 프로젝트에서 `claude-hr` 래퍼(`alias claude-hr='~/.headroom/claude-hr.sh'`)로 실행하면 8790을 경유한다. 효과는 **긴 세션·재독 많은 작업**에서만 누적되며 단발 작업엔 무의미하다.

---

## `/headroom off` — 현재 프로젝트 영구 비활성

always-route ON(`~/.headroom/always-route` 존재)이면 **disabled-projects**에 추가. 아니면 enabled-projects에서 제거.

```bash
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; PROJECT_ROOT="$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || pwd)"
if [ -f "$HOME/.headroom/always-route" ]; then
  python3 - "$HOME/.headroom/disabled-projects.json" "$PROJECT_ROOT" <<'PY'
import json, sys, os
reg_path, root = sys.argv[1], os.path.realpath(sys.argv[2])
try: reg = json.load(open(reg_path))
except Exception: reg = []
reg = [os.path.realpath(p) for p in reg]
if root not in reg: reg.append(root)
json.dump(sorted(set(reg)), open(reg_path, "w"), indent=2, ensure_ascii=False)
print("✅ always-route 모드 — 이 프로젝트만 opt-out:", root)
PY
else
  python3 - "$HOME/.headroom/enabled-projects.json" "$PROJECT_ROOT" <<'PY'
import json, sys, os
reg_path, root = sys.argv[1], os.path.realpath(sys.argv[2])
try: reg = json.load(open(reg_path))
except Exception: reg = []
reg = [os.path.realpath(p) for p in reg if os.path.realpath(p) != root]
json.dump(reg, open(reg_path, "w"), indent=2, ensure_ascii=False)
print("✅ 비활성:", root)
PY
fi
```

> 프록시 프로세스는 건드리지 않는다. 이 프로젝트만 래퍼가 직결로 전환된다.

---

## always-route (Slack/Hermes와 동일 정책)

`~/.headroom/always-route` 파일이 있으면 **등록 없이** `cc`/`ccd`가 headroom(:8790)을 경유한다.
- Hermes 게이트웨이(Slack): `config.yaml` `base_url: http://local.anthropic.com:8790` — 항상 headroom
- Claude Code: `claude-hr.sh` + always-route — 동일 체인 (headroom → cliproxy :8317)
- Codex CLI: `~/.codex/config.toml`의 `model_provider = "headroom"` + `[model_providers.headroom] base_url = "http://127.0.0.1:8790/v1"` + `wire_api = "responses"` — OpenAI Responses 경로로 동일 체인 (headroom → cliproxy :8317)

해제: `rm ~/.headroom/always-route` 는 Claude 래퍼만 해제한다. Codex 우회/복구 세션은 `codex --ignore-user-config` 또는 `-c model_provider=...`로 별도 실행한다.

---

## Claude Code 모델 윈도우 정책

- **Sonnet**: `claude-sonnet-4-6` 기본 200K만 표준으로 쓴다. `claude-sonnet-4-6[1m]` / `[1M]` 별칭은 등록하지 않는다.
- **Haiku**: 200K 표준 윈도우만 쓴다.
- **Opus**: `claude-opus-4-8` 200K와 `claude-opus-4-8[1m]` / `[1M]` 1M을 둘 다 쓸 수 있다.
- 기본 `cc`/`ccd` alias는 `claude-opus-4-8[1M]` Opus 1M으로 둔다. Opus 200K는 `cc2` 명시 alias로만 쓴다. 1M이 일시 unavailable이면 Claude Code의 Bash safety classifier까지 막힐 수 있기 때문이다.
- Sonnet 1M은 Claude Code에서 usage credits가 켜진 경우에만 별도 의도 하에 요청한다. 이 스택은 Sonnet 1M 요청을 200K로 폴백하지 않는다. 권한이 없으면 upstream 429가 나는 것이 맞다.
- `CLAUDE_CODE_DISABLE_1M_CONTEXT`는 진단용 env다. alias나 표준 실행 경로에 넣지 않는다.

---

## `/headroom status` — 현재 프로젝트 상태 요약

```bash
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; PROJECT_ROOT="$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || pwd)"
echo "프로젝트: $PROJECT_ROOT"

# 1) 라우팅 모드
[ -f "$HOME/.headroom/always-route" ] && echo "모드: 🌐 always-route (전 프로젝트 기본 경유)" || echo "모드: 📁 per-project (enabled-projects opt-in)"

# 2) 레지스트리 / opt-out
python3 - "$HOME/.headroom/enabled-projects.json" "$HOME/.headroom/disabled-projects.json" "$PROJECT_ROOT" <<'PY'
import json, sys, os
en_path, dis_path, root = sys.argv[1], sys.argv[2], os.path.realpath(sys.argv[3])
try: en = [os.path.realpath(p) for p in json.load(open(en_path))]
except Exception: en = []
try: dis = [os.path.realpath(p) for p in json.load(open(dis_path))]
except Exception: dis = []
if root in dis:
    print("토글:", "🔴 OFF (disabled-projects opt-out)")
elif root in en:
    print("토글:", "🟢 ON (enabled-projects)")
else:
    print("토글:", "⚪ 미등록 (always-route면 자동 경유)")
print("활성 프로젝트 수:", len(en), "| opt-out 수:", len(dis))
PY

# 2) 프록시 health
curl -sf -m1 http://localhost:8790/health >/dev/null 2>&1 \
  && echo "프록시: 🟢 healthy (8790)" || echo "프록시: 🔴 미기동 → 래퍼는 직결로 fail-open"

# 3) /stats 요약 — cache_bust_count 0 확인 (>0 = 캐시 깨짐 = 손해 신호)
curl -sf -m1 http://localhost:8790/stats 2>/dev/null | python3 -c '
import json,sys
try:
    s=json.load(sys.stdin)
    cb=s.get("compression_vs_cache",{}).get("cache_bust_count", s.get("cache_bust_count","?"))
    print("cache_bust_count:", cb, "(0이어야 정상)")
    print("avg_compression_pct:", s.get("avg_compression_pct","?"))
    print("requests_compressed:", s.get("requests_compressed","?"))
except Exception:
    print("(stats 파싱 불가 — 프록시 미기동이거나 응답 형식 상이)")
' 2>/dev/null || echo "(stats 조회 불가)"

# 4) Codex 라우팅 상태 — Responses API가 headroom :8790/v1로 고정돼야 함
if [ -f "$HOME/.codex/config.toml" ]; then
  grep -q 'model_provider = "headroom"' "$HOME/.codex/config.toml" \
    && echo "Codex: 🟢 model_provider=headroom" || echo "Codex: ⚪ headroom provider 아님"
  grep -q 'base_url = "http://127.0.0.1:8790/v1"' "$HOME/.codex/config.toml" \
    && echo "Codex base_url: 🟢 8790/v1" || echo "Codex base_url: 확인 필요"
  grep -q 'CODEX_DUMMY_API_KEY' "$HOME/.zshrc" 2>/dev/null \
    && echo "Codex auth env: 🟢 dummy local auth configured" || echo "Codex auth env: ⚠️ CODEX_DUMMY_API_KEY 필요"
fi
```

### Codex 적용 확정

Codex는 설정 확인만으로 확정하지 않는다. 실제 호출 후 headroom stats를 보고, 라우팅 이슈 대응 때만 임시 파일 로그를 켠다.

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

---

## 동작 규칙 요약

- `on`/`off`는 **레지스트리(파일) 영구 변경** — 세션 종료해도 유지.
- 래퍼는 **fail-open**: 프록시가 죽어도 미등록 프로젝트처럼 직결되어 작업 무중단.
- **프로젝트/크루별 수동 컨트롤만.** 어떤 경우에도 사용자 호출 없이 프로젝트를 자동 등록하지 않는다.
- 효과 판단: 긴 세션·재독 많은 코딩/전사/RAG = 강타깃. 단발·소형 입력 = 무의미.

---

## 🔒 운영 정책 — 프로젝트 레벨 전용 (SPOF 방지)

- **글로벌 `ANTHROPIC_BASE_URL` 정적 설정 금지.** 셸 rc/환경에 프록시 URL을 export하면 **모든 세션이 프록시에 묶이고**, 프록시가 죽는 순간 전 세션이 동시에 `ConnectionRefused`로 마비된다(정적 env = fail-open 아님). 2026-06-09 실제 사건.
- **`always-route`는 래퍼 전용** (`~/.headroom/always-route` + `claude-hr.sh`). 매 호출 health 체크 후 set/unset이라 fail-open 유지. Slack/Hermes는 `config.yaml` `base_url`로 동일 headroom 체인.
- **Codex는 예외적으로 custom provider에 hard-bound** 한다. `~/.codex/config.toml`의 `model_provider=headroom`은 fail-open 래퍼가 아니므로 headroom/cliproxy 진단·복구용 Codex 세션은 `--ignore-user-config` 또는 직접 provider override로 띄운다.
- Codex provider `env_key`는 실제 OpenAI 키가 아니라 `CODEX_DUMMY_API_KEY=dummy`를 쓴다. 로컬 headroom 요청 헤더를 만족시키기 위한 값이고, 구독 plan 인증은 cliproxy OAuth 토큰이 upstream에서 처리한다.
- headroom/cliproxy 파일 로그는 기본 OFF다. 이슈 대응 때만 `~/.claude/skills/headroom-cliproxyapi/scripts/file-logs.sh on`으로 켜고, 재현/tail 후 반드시 `off`로 되돌린다.
- `file-logs.sh on/off`는 LaunchAgent 재시작을 동반하므로 라이브 Claude Code 세션 중에는 기본 거부한다. 강제 캡처가 필요할 때만 `HEADROOM_FILE_LOGS_FORCE=1`을 붙인다.
- 활성화는 **오직 `enabled-projects.json` 레지스트리 + fail-open 래퍼**로만. 프로젝트별 opt-in이고, 미등록/프록시다운이면 자동 직결되어 무중단.
- 헤드룸은 **프로젝트·크루 단위 도구**다. 전역 기본값으로 만들지 않는다.

## 🚑 §5 SPOF 복구 — 프록시가 죽어 세션이 마비될 때

**증상**: 경유 중이던 Claude/Codex 대화창이 전부 `API Error: Connection refused`. 프록시(8790)가 다운됐고, 그 세션들이 정적 env로 묶여 fail-open이 안 된 상태(래퍼 미경유).

**복구**:
1. **헤드룸 미경유 세션에서 재기동한다** — 마비된 세션 안에서는 못 한다(자기 연결이 죽어 있음). **다른 프로젝트/루트**(레지스트리 미등록)에서 새 셸/세션을 연다.
2. ```bash
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.headroom.proxy.plist 2>/dev/null
   launchctl enable    gui/$(id -u)/com.headroom.proxy
   launchctl kickstart -k gui/$(id -u)/com.headroom.proxy
   sleep 1; curl -sf -m1 http://localhost:8790/health && echo " ✅ 8790 복구"
   ```
3. 8790이 살아나면 마비됐던 대화창은 **재시도(같은 입력 재전송)** 로 복귀한다.
4. **근본 예방**: 프록시 작업/모니터 세션은 **처음부터 직결로** 띄우고, 일반 세션은 정적 env가 아니라 **fail-open 래퍼**(`claude-hr.sh`)로 띄운다 — 매 호출 조건부 set/unset이라 프록시가 죽어도 그 세션만 직결로 빠지고 작업은 안 끊긴다.
