#!/bin/zsh
# claude-hr.sh — Claude Code 프록시 라우팅 스위처
#
# 두 레이어를 독립 토글한다.
#   headroom (:8790)  컨텍스트 압축. upstream 은 plist 인자로 cliproxy(:8317) 에 고정.
#   cliproxy (:8317)  멀티계정 OAuth 회전 + cloak + 프로토콜 변환.
#
# 라우팅 매트릭스
#   headroom  cliproxy   ANTHROPIC_BASE_URL
#   on        on         http://localhost:8790      (압축 → 회전 → 구독)
#   off       on         http://127.0.0.1:8317      (회전 → 구독, 압축 생략)
#   off       off        unset                      (Anthropic 직결)
#   on        off        거부 — headroom upstream 이 8317 고정이라 성립 불가
#
# 상태: ~/.headroom/routing.json  {"default":{...},"projects":{"<root>":{...}}}
# env 오버라이드: HEADROOM_ROUTE=0|1  CLIPROXY_ROUTE=0|1
#
# 스위처 CLI:  claude-hr.sh route status
#              claude-hr.sh route headroom on|off [--global]
#              claude-hr.sh route cliproxy on|off [--global]
#              claude-hr.sh route reset [--global]

set -u

HR_DIR="$HOME/.headroom"
ROUTING="$HR_DIR/routing.json"
HEADROOM_URL="http://localhost:8790"
CLIPROXY_URL="http://127.0.0.1:8317"

# ── 프로젝트 root (워크트리는 공용 git dir 기준으로 하나의 root 로 접힌다)
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
PROJECT_ROOT="$([ -n "$GIT_COMMON" ] && dirname "$GIT_COMMON" || pwd)"

_need_python() {
  command -v python3 >/dev/null 2>&1 || {
    print -u2 "claude-hr: python3 가 없어 라우팅 상태를 읽을 수 없다 — 직결로 진행"
    return 1
  }
}

# ── 유효 설정 조회: "headroom cliproxy source" 한 줄 출력
_resolve() {
  python3 - "$ROUTING" "$PROJECT_ROOT" <<'PY' 2>/dev/null
import json, os, sys

routing_file, root = sys.argv[1], os.path.realpath(sys.argv[2])
cfg = {}
try:
    with open(routing_file) as fh:
        cfg = json.load(fh)
except Exception:
    cfg = {}

default = cfg.get("default") or {"headroom": False, "cliproxy": False}
source = "default"
resolved = dict(default)

for key, val in (cfg.get("projects") or {}).items():
    if os.path.realpath(os.path.expanduser(key)) == root:
        resolved.update(val or {})
        source = "project"
        break

print(int(bool(resolved.get("headroom"))), int(bool(resolved.get("cliproxy"))), source)
PY
}

# ── 상태 파일 쓰기: _write <layer> <0|1> <global|project>
_write() {
  python3 - "$ROUTING" "$PROJECT_ROOT" "$1" "$2" "$3" <<'PY'
import json, os, sys

routing_file, root, layer, value, scope = sys.argv[1:6]
root = os.path.realpath(root)
value = bool(int(value))

try:
    with open(routing_file) as fh:
        cfg = json.load(fh)
except Exception:
    cfg = {}

cfg.setdefault("default", {"headroom": False, "cliproxy": False})
cfg.setdefault("projects", {})

if scope == "global":
    cfg["default"][layer] = value
else:
    entry = None
    for key in list(cfg["projects"]):
        if os.path.realpath(os.path.expanduser(key)) == root:
            entry = key
            break
    if entry is None:
        entry = root
        cfg["projects"][entry] = dict(cfg["default"])
    cfg["projects"][entry][layer] = value

os.makedirs(os.path.dirname(routing_file), exist_ok=True)
with open(routing_file, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
print(f"{layer}={'on' if value else 'off'} ({scope})")
PY
}

_reset() {
  python3 - "$ROUTING" "$PROJECT_ROOT" "$1" <<'PY'
import json, os, sys

routing_file, root, scope = sys.argv[1:4]
root = os.path.realpath(root)

try:
    with open(routing_file) as fh:
        cfg = json.load(fh)
except Exception:
    cfg = {}

if scope == "global":
    cfg["default"] = {"headroom": False, "cliproxy": False}
    print("default 를 headroom=off cliproxy=off 로 초기화")
else:
    removed = [k for k in (cfg.get("projects") or {})
               if os.path.realpath(os.path.expanduser(k)) == root]
    for key in removed:
        del cfg["projects"][key]
    print("프로젝트 오버라이드 제거 — default 상속" if removed else "프로젝트 오버라이드 없음")

with open(routing_file, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
PY
}

# ── env 오버라이드 반영
_apply_env_override() {
  local want_hr="$1" want_cp="$2"
  case "${HEADROOM_ROUTE:-}" in 0) want_hr=0 ;; 1) want_hr=1 ;; esac
  case "${CLIPROXY_ROUTE:-}" in 0) want_cp=0 ;; 1) want_cp=1 ;; esac
  print "$want_hr $want_cp"
}

_headroom_up() { curl -sf -m1 "$HEADROOM_URL/health" >/dev/null 2>&1; }
_cliproxy_up() { curl -sf -m2 "$CLIPROXY_URL/v1/models" >/dev/null 2>&1; }

# ── 요청 모델이 cliproxy 카탈로그에 있는지 (없으면 경고만, 차단 안 함)
_warn_unknown_model() {
  local wanted=""
  local -a args
  args=("$@")
  local idx=1
  while (( idx <= ${#args} )); do
    if [[ "${args[$idx]}" == "--model" ]]; then
      wanted="${args[$((idx+1))]:-}"
      break
    fi
    (( idx++ ))
  done
  [ -n "$wanted" ] || return 0
  local catalog
  catalog="$(curl -sf -m2 "$CLIPROXY_URL/v1/models" 2>/dev/null)" || return 0
  print -r -- "$catalog" | python3 -c '
import json, sys
wanted = sys.argv[1]
try:
    ids = {m["id"] for m in json.load(sys.stdin)["data"]}
except Exception:
    sys.exit(0)
if wanted not in ids:
    near = sorted(i for i in ids if wanted.split("[")[0] in i)
    sys.stderr.write(f"claude-hr: 경고 — cliproxy 카탈로그에 {wanted!r} 없음. "
                     f"세션이 모델 미지원으로 실패할 수 있다.\n")
    if near:
        sys.stderr.write("  사용 가능: " + ", ".join(near) + "\n")
' "$wanted" 2>&1 >/dev/null
}

# ── 스위처 CLI
if [[ "${1:-}" == "route" ]]; then
  _need_python || exit 1
  shift
  sub="${1:-status}"
  scope="project"
  for arg in "$@"; do [[ "$arg" == "--global" ]] && scope="global"; done

  case "$sub" in
    status)
      read -r hr cp src <<< "$(_resolve)"
      read -r hr cp <<< "$(_apply_env_override "$hr" "$cp")"
      print "프로젝트: $PROJECT_ROOT"
      print "설정 소스: $src${HEADROOM_ROUTE+ (+env HEADROOM_ROUTE)}${CLIPROXY_ROUTE+ (+env CLIPROXY_ROUTE)}"
      print "  headroom : $([ "$hr" = 1 ] && print on || print off)   프로세스 $(_headroom_up && print '● up' || print '○ down')"
      print "  cliproxy : $([ "$cp" = 1 ] && print on || print off)   프로세스 $(_cliproxy_up && print '● up' || print '○ down')"
      if [ "$hr" = 1 ] && [ "$cp" = 0 ]; then
        print "  → ⛔ 불가 조합 (headroom upstream 이 8317 고정)"
      elif [ "$hr" = 1 ]; then
        print "  → ANTHROPIC_BASE_URL=$HEADROOM_URL  (압축 → 회전 → 구독)"
      elif [ "$cp" = 1 ]; then
        print "  → ANTHROPIC_BASE_URL=$CLIPROXY_URL  (회전 → 구독, 압축 생략)"
      else
        print "  → unset  (Anthropic 직결)"
      fi
      exit 0
      ;;
    headroom|cliproxy)
      val="${2:-}"
      case "$val" in
        on)  _write "$sub" 1 "$scope" ;;
        off) _write "$sub" 0 "$scope" ;;
        *)   print -u2 "usage: claude-hr.sh route $sub on|off [--global]"; exit 2 ;;
      esac
      exit $?
      ;;
    reset)
      _reset "$scope"; exit $?
      ;;
    *)
      print -u2 "usage: claude-hr.sh route status|headroom on|off|cliproxy on|off|reset [--global]"
      exit 2
      ;;
  esac
fi

# ── 실행 경로
if _need_python; then
  read -r WANT_HR WANT_CP _SRC <<< "$(_resolve)"
else
  WANT_HR=0; WANT_CP=0
fi
read -r WANT_HR WANT_CP <<< "$(_apply_env_override "$WANT_HR" "$WANT_CP")"

if [ "$WANT_HR" = 1 ] && [ "$WANT_CP" = 0 ]; then
  print -u2 "claude-hr: 불가 조합 — headroom=on + cliproxy=off."
  print -u2 "  headroom LaunchAgent 의 --anthropic-api-url 이 $CLIPROXY_URL 에 고정돼 있어"
  print -u2 "  headroom 을 켜면 cliproxy 를 우회할 수 없다."
  print -u2 "  cliproxy 를 켜거나(route cliproxy on) headroom 을 끄라(route headroom off)."
  exit 78
fi

if [ "$WANT_HR" = 1 ]; then
  if ! _headroom_up; then
    print -u2 "claude-hr: headroom 경유가 요청됐지만 :8790 health 실패 — 직결 폴백을 거부한다"
    exit 69
  fi
  export ANTHROPIC_BASE_URL="$HEADROOM_URL"
  # headroom 은 x-headroom-cwd 로 프로젝트별 압축 캐시/메모리를 분리한다.
  # 없으면 "workspace unresolved; skipping track_compression" 으로 fail-closed.
  export ANTHROPIC_CUSTOM_HEADERS="x-headroom-cwd: $PROJECT_ROOT"
  _warn_unknown_model "$@"
elif [ "$WANT_CP" = 1 ]; then
  if ! _cliproxy_up; then
    print -u2 "claude-hr: cliproxy 경유가 요청됐지만 :8317 /v1/models 실패 — 직결 폴백을 거부한다"
    exit 69
  fi
  export ANTHROPIC_BASE_URL="$CLIPROXY_URL"
  unset ANTHROPIC_CUSTOM_HEADERS
  _warn_unknown_model "$@"
else
  unset ANTHROPIC_BASE_URL
  unset ANTHROPIC_CUSTOM_HEADERS
fi

exec ~/.local/bin/claude "$@"
