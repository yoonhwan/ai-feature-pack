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
| `~/.headroom/enabled-projects.json` | 활성 프로젝트 root 절대경로 **배열** (영구 레지스트리) |
| `~/.headroom/claude-hr.sh` | fail-open 래퍼. 레지스트리를 읽어 **현재 프로젝트가 등록 + 프록시 health OK** 일 때만 8790 경유, 아니면 직결 |
| `~/.headroom-venv/bin/python` | 프록시 실행 venv |

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

2. 프록시 health 확인 → **미기동이면 기동 안내**(자동 기동하지 않고 명령만 제시):
```bash
curl -sf -m1 http://localhost:8790/health >/dev/null 2>&1 \
  && echo "✅ 프록시 가동 중 (8790)" \
  || cat <<'EOF'
⚠️ 프록시 미기동 — 아래로 기동(token 모드, 압축+캐시 공존, 텔레메트리 off):
HEADROOM_MODE=token HEADROOM_COMPRESS_USER_MESSAGES=1 HEADROOM_CODE_AWARE_ENABLED=1 HEADROOM_TELEMETRY=off \
  ~/.headroom-venv/bin/python -m headroom.proxy.server \
  --port 8790 --compress-user-messages --exclude-tools Bash --code-aware
EOF
```

3. 사용자에게 안내: 이 프로젝트에서 `claude-hr` 래퍼(`alias claude-hr='~/.headroom/claude-hr.sh'`)로 실행하면 8790을 경유한다. 효과는 **긴 세션·재독 많은 작업**에서만 누적되며 단발 작업엔 무의미하다.

---

## `/headroom off` — 현재 프로젝트 영구 비활성

레지스트리 배열에서 제거:
```bash
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; PROJECT_ROOT="$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || pwd)"
python3 - "$HOME/.headroom/enabled-projects.json" "$PROJECT_ROOT" <<'PY'
import json, sys, os
reg_path, root = sys.argv[1], os.path.realpath(sys.argv[2])
try: reg = json.load(open(reg_path))
except Exception: reg = []
reg = [os.path.realpath(p) for p in reg if os.path.realpath(p) != root]
json.dump(reg, open(reg_path, "w"), indent=2, ensure_ascii=False)
print("✅ 비활성:", root)
PY
```

> 프록시 프로세스는 건드리지 않는다(다른 프로젝트가 쓸 수 있음). 이 프로젝트만 래퍼가 직결로 전환된다.

---

## `/headroom status` — 현재 프로젝트 상태 요약

```bash
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; PROJECT_ROOT="$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || pwd)"
echo "프로젝트: $PROJECT_ROOT"

# 1) 레지스트리 활성 여부
python3 - "$HOME/.headroom/enabled-projects.json" "$PROJECT_ROOT" <<'PY'
import json, sys, os
try: reg = [os.path.realpath(p) for p in json.load(open(sys.argv[1]))]
except Exception: reg = []
print("토글:", "🟢 ON (활성)" if os.path.realpath(sys.argv[2]) in reg else "⚪ OFF (비활성)")
print("활성 프로젝트 수:", len(reg))
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
```

---

## 동작 규칙 요약

- `on`/`off`는 **레지스트리(파일) 영구 변경** — 세션 종료해도 유지.
- 래퍼는 **fail-open**: 프록시가 죽어도 미등록 프로젝트처럼 직결되어 작업 무중단.
- **프로젝트/크루별 수동 컨트롤만.** 어떤 경우에도 사용자 호출 없이 프로젝트를 자동 등록하지 않는다.
- 효과 판단: 긴 세션·재독 많은 코딩/전사/RAG = 강타깃. 단발·소형 입력 = 무의미.
