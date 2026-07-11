#!/bin/bash
# fable-team context-distill-gate — 300k/450k 컨텍스트 하드 증류 게이트
# 소프트 "경계에서 증류" 지침이 실제로 안 먹는 문제 → 물리 장치로 강제.
# 토큰 소스: transcript 마지막 assistant usage(input+cache_read+cache_creation).
# 두 모드 (settings.json에서 인자로 지정):
#   warn   (UserPromptSubmit) : ≥300k면 매 턴 증류 경고 주입(additionalContext).
#   block  (PreToolUse:Task)  : ≥450k면 신규 서브에이전트/워크플로 스폰 차단(즉시 증류 강제).
# 대상: 오케스트레이터(TOP 모델) 세션만 — 워커는 단수명이라 면제. FAIL-OPEN.
set +e
MODE="${1:-warn}"
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

TOP_MODELS="${OMC_GATE_TOP_MODELS:-fable|sonnet-?5}"
WARN_AT="${OMC_DISTILL_WARN_AT:-300000}"
BLOCK_AT="${OMC_DISTILL_BLOCK_AT:-450000}"

RESULT=$(python3 - "$INPUT" "$TOP_MODELS" "$WARN_AT" "$BLOCK_AT" "$MODE" <<'PYEOF' 2>/dev/null
import json, sys, os, re
TAIL_CAP = 16 * 1024 * 1024   # 마지막 레코드가 멀티MB여도 통째로 읽되 폭주 방지 상한
TAIL_CHUNK = 262144

def norm_model(m):
    # dict(id/display_name)·display string 모두 흡수 → 소문자·(공백/점→하이픈)·연속하이픈 축약
    if isinstance(m, dict):
        m = m.get("id") or m.get("display_name") or ""
    if not isinstance(m, str):
        return ""
    return re.sub(r"-+", "-", re.sub(r"[ .]+", "-", m.lower()))

def scan_model_usage(path):
    # 완전 JSONL 레코드 단위 reverse 리더 — 거대 마지막 라인도 통째로 회수(tail cap 우회 방지).
    model, usage = None, None
    try:
        with open(path, "rb") as f:
            f.seek(0, 2); pos = f.tell(); buf = b""
            while pos > 0 and len(buf) < TAIL_CAP:
                step = min(TAIL_CHUNK, pos); pos -= step
                f.seek(pos); buf = f.read(step) + buf
                lines = buf.split(b"\n")
                usable = lines if pos == 0 else lines[1:]  # pos>0이면 앞쪽 부분 라인 제외
                for line in reversed(usable):
                    if not line.strip():
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    msg = obj.get("message") or {}
                    if model is None:
                        model = msg.get("model") or obj.get("model") or None
                    if usage is None and msg.get("usage"):
                        usage = msg["usage"]
                    if model is not None and usage is not None:
                        return model, usage
                if model is not None and usage is not None:
                    return model, usage
    except Exception:
        return model, usage
    return model, usage

try:
    data = json.loads(sys.argv[1]); top_re = sys.argv[2]
    warn_at = int(sys.argv[3]); block_at = int(sys.argv[4])
    mode = sys.argv[5] if len(sys.argv) > 5 else "warn"
except Exception:
    print("ALLOW"); sys.exit(0)

tpath = data.get("transcript_path", "")
if not tpath or not os.path.isfile(tpath):
    print("ALLOW"); sys.exit(0)

model, usage = scan_model_usage(tpath)
model = norm_model(model)     # dict·display·[1m] 모두 정규화 → top_re(하이픈형) 매칭

# 오케스트레이터(TOP)만 대상
if not model or not re.search(top_re, model):
    print("ALLOW"); sys.exit(0)
if not usage:
    print("ALLOW"); sys.exit(0)

ctx = (usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
       + usage.get("cache_creation_input_tokens", 0))
k = ctx // 1000

# 450k block 예외: 증류·마무리·checkpoint 전용 스폰은 데드락 회피 위해 허용(일반 fanout만 차단).
BLOCK_EXEMPT = os.environ.get("OMC_DISTILL_BLOCK_EXEMPT") or \
    r"baton|distill|증류|checkpoint|save|DA[ _-]?final|finalize|종결"
def spawn_text(d):
    ti = d.get("tool_input") or {}
    parts = []
    for key in ("prompt", "description", "command", "subagent_type", "message", "task"):
        v = ti.get(key)
        if isinstance(v, str):
            parts.append(v)
    return " ".join(parts)

# 실제 스폰 시도 판정 — block 모드에서 비스폰 Bash를 오차단해 세션을 brick하지 않기 위함.
# Task = 항상 스폰. Bash = ft-tmux-spawn.sh 호출만 스폰(§1-5 — 450k block Bash 매처 차단 추가).
def is_spawn_attempt(d):
    t = d.get("tool_name", "")
    if t == "Task":
        return True
    if t == "Bash":
        c = ((d.get("tool_input") or {}).get("command") or "")
        return bool(re.search(r"ft-tmux-spawn\.sh", c))
    return False

# 60% 경계 강제 증류: ctx ≥ warn_at(300k) 그리고 ctx% ≥ force_pct(60) → block_at 미만이어도 강제.
#   윈도우: OMC_CTX_WINDOW 우선, 없으면 model에 1m 있으면 1M·아니면 200k. [1m] 세션은 %가 낮게
#   보여 소프트 경계가 안 먹던 문제 → 절대선(block_at)과 % 트리거의 OR로 확실히 발동.
win = int(os.environ.get("OMC_CTX_WINDOW", "0") or 0)
if not win:
    # 게이트는 TOP 모델(fable/sonnet-5 = 대형 윈도우 가정)에서만 발동 → 기본 1M.
    # message.model이 [1m] suffix를 안 실어도 안전(과차단 방지). 소형 윈도우 세션은 OMC_CTX_WINDOW로 명시.
    win = 200_000 if re.search(r"sonnet-4|haiku", model) else 1_000_000
pct = (ctx * 100 // win) if win else 0
force_pct = int(os.environ.get("OMC_DISTILL_FORCE_PCT", "60") or 60)
force_distill = (ctx >= block_at) or (ctx >= warn_at and pct >= force_pct)

# 파이썬은 임계·스폰 판정; 최종 exit 분기는 bash가 한다.
if force_distill:
    txt = spawn_text(data)
    exempt = bool(txt and re.search(BLOCK_EXEMPT, txt, re.I))
    if mode == "block":
        # block 모드(PreToolUse:Task|Bash): 실제 스폰 시도만 차단.
        # 비스폰 Bash(일반 명령)는 450k여도 통과 — 오차단=세션 brick 방지.
        if not is_spawn_attempt(data):
            print("ALLOW|%d" % k)
        elif exempt:
            print("EXEMPT|%d" % k)   # 증류/마무리 전용 스폰 → 데드락 회피 예외
        else:
            print("BLOCK|%d" % k)
    else:
        # warn 모드(UserPromptSubmit): 임계 경고 주입용 STATE (스폰 여부 무관).
        print("EXEMPT|%d" % k if exempt else "BLOCK|%d" % k)
elif ctx >= warn_at:
    print("WARN|%d" % k)
else:
    print("ALLOW|%d" % k)
PYEOF
)

STATE="${RESULT%%|*}"; K="${RESULT##*|}"

if [ "$MODE" = "block" ]; then
  if [ "$STATE" = "BLOCK" ]; then
    # ── 하이진 정리 트리거: 오버플로 유발 파일·로그 압축 (백그라운드·세션당 1회 마커) ──
    TMP="${TMPDIR:-/tmp}"; [ -z "$TMP" ] && TMP=/tmp
    MARK="$TMP/omc-orch-gate/.hygiene-done"
    if [ ! -f "$MARK" ]; then
      mkdir -p "$TMP/omc-orch-gate" 2>/dev/null && : > "$MARK" 2>/dev/null
      HYG="$(dirname "$0")/context-hygiene-clean.sh"
      [ -x "$HYG" ] && nohup bash "$HYG" >/dev/null 2>&1 &
    fi
    printf '🛑 [context-distill-gate] 컨텍스트 %sk 토큰 — 증류 강제선 돌파.\n' "$K" >&2
    printf '신규 서브에이전트/워크플로 스폰을 차단합니다. 지금 즉시:\n' >&2
    printf '  1) ★열린 워커/하위 세션 전원 수거·해산 확인 (dangling 세션 0 — 60%% 경계엔 하위 세션이 하나도 돌면 안 됨)\n' >&2
    printf '  2) state write-through 최신화  3) baton save(워크트리)  4) 세션 재시작(증류) 후 복원.\n' >&2
    printf '진행 중 작업만 마무리하고 새 팬아웃을 시작하지 마세요.\n' >&2
    printf '(하이진 정리 트리거됨 — 대용량 raw/log/transcript 백그라운드 압축. 증류/마무리 전용 스폰 — baton·distill·증류·checkpoint·save·종결 — 은 예외 허용.)\n' >&2
    exit 2
  fi
  exit 0   # EXEMPT/ALLOW/WARN → 스폰 허용 (증류·마무리 데드락 회피 예외 포함)
fi

# warn 모드 (UserPromptSubmit) — additionalContext 주입 (WARN·BLOCK 둘 다 경고)
if [ "$STATE" = "WARN" ] || [ "$STATE" = "BLOCK" ] || [ "$STATE" = "EXEMPT" ]; then
  python3 - "$K" <<'PYEOF2' 2>/dev/null
import json, sys
k = sys.argv[1]
msg = ("⚠️ [context-distill-gate] 컨텍스트 %sk 토큰 — 300k 경계 초과. "
       "지금 .fable-team/bin/ft-ctx-triage.sh <project-root> 실행 → RECOMMEND 결과로 증류 결정: "
       "CONTINUE(수정만) | COMPACT(경계 예약) | DISTILL(write-through 최신화 → baton save → "
       "세션 재시작 후 .fable-team/state/ACTIVE 복원). 450k에서 신규 스폰이 물리 차단됩니다." % k)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": msg}}))
PYEOF2
fi
exit 0
