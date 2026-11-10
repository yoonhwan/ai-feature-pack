#!/bin/bash
# fable-team bang-command-gate — PreToolUse:AskUserQuestion (R106 · 오빠 「명령 실행 요청 멍청하게 길게 하냐」)
# 왜: 오빠가 `!` 로 칠 명령은 `! bash /tmp/h<N>` 한 줄이 표준(R83). 질문 글(question·header·options[].label·description·preview)에 60자 초과·
#   /tmp/h<N> 밖 절대경로·따옴표 밖 &&·;·| 가 든 `!` 줄이 있으면 deny + 안내. `!` 로 시작하지 않는 줄(①막힌 명령 원문)은 검사 밖.
# 판정기 = bang_command_check.py(쪽지 가드와 같은 것) — 경로 env FT_BANG_COMMAND_CHECK > 이 파일과 같은 폴더 사본.
# ★FAIL-OPEN(sibling 훅 관례)★: stdin 파싱 불가·판정기 없음/깨짐 = 허용 + 로그 1줄(~/.claude/logs/bang-command-gate.log · 시험은 FT_BANG_COMMAND_LOG).
# ★설치(~/.claude/hooks/ 에 훅+판정기 함께 cp · settings.json PreToolUse AskUserQuestion 등록)는 이 파일 범위 밖 — master 몫★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
python3 - <<'PYEOF'
import importlib.util, json, os, sys, time

LOG = os.environ.get("FT_BANG_COMMAND_LOG") or os.path.expanduser("~/.claude/logs/bang-command-gate.log")


def note(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" bang-command-gate: {msg}\n")
    except OSError:
        pass


def warn_open(what, e):  # 허용은 유지하되 호출자에게도 보이게 stderr 1줄 + 파일 로그
    note(f"{what}({e}) — 허용(fail-open)")
    print(f"WARN bang-command-gate: {what} — 검사 없이 허용(R106)", file=sys.stderr)
    sys.exit(0)


chk = os.environ.get("FT_BANG_COMMAND_CHECK") or os.path.join(os.environ["HOOK_DIR"], "bang_command_check.py")
try:
    data = json.loads(os.environ["INPUT"])
    if not isinstance(data, dict):
        raise ValueError("객체 아님")
except ValueError as e:
    warn_open("stdin JSON 파싱 불가", e)
try:
    spec = importlib.util.spec_from_file_location("bang_command_check", chk)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
except Exception as e:  # 판정기 없음/깨짐 — 막지 않는다
    warn_open(f"판정기 없음/로드 실패 {chk}", e)
if data.get("tool_name") not in (None, "AskUserQuestion"):
    sys.exit(0)
parts = []
for q in (data.get("tool_input") or {}).get("questions") or []:
    if not isinstance(q, dict):
        continue
    parts += [str(q.get(k) or "") for k in ("question", "header")]
    for o in q.get("options") or []:
        if isinstance(o, dict):
            parts += [str(o.get(k) or "") for k in ("label", "description", "preview")]
found = mod.violations("\n".join(parts))
if found:
    reason = mod.GUIDE + " · 위반 줄: " + " | ".join(c[:40] for c in found)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
          "permissionDecisionReason": reason}}, ensure_ascii=False))
PYEOF
exit 0
