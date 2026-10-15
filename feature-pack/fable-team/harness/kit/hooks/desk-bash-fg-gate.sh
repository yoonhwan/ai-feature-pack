#!/bin/bash
# desk-bash-fg-gate — PreToolUse:Bash (R241 · DESIGN-r241-desk-never-stall §4)
# 왜: desk 가 긴 명령(빌드·시험·sleep)을 전경으로 돌리는 동안 턴이 멈추고 오빠 슬랙 글에 반응하지 못한다.
# 동작: 좌석(tmux 세션)=seats-planner.json `_desk` 일 때만 본다. run_in_background=true 이거나 timeout 이 1..FT_DESK_FG_MS(기본 30000)이면 허용.
#   그 밖(timeout 없음 = 기본 120초 · 30초 초과 · 0 이하)은 deny. 판단 근거 = 도구 입력의 두 값뿐(명령 글자 해석 0).
# ★못 읽음★: 명부·tmux 조회 실패 = 허용 + FT_DESK_LOG(기본 ~/.claude/logs/desk-route.log) 1줄 + stderr. 외부 호출 0.
# 환경: FT_ROOT(루트 고정) · FT_DESK_FG_MS · FT_DESK_LOG. ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse Bash 등록)는 master — 이 파일 범위 밖★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
python3 - <<'PYEOF'
import json, os, subprocess, sys, time

LOG = os.environ.get("FT_DESK_LOG") or os.path.expanduser("~/.claude/logs/desk-route.log")
FG_MS = int(os.environ.get("FT_DESK_FG_MS") or 30000)
REASON = (
    "desk 는 전경 명령 %d초 이하만(R241) — 긴 전경 명령 동안 오빠 슬랙 글을 못 읽습니다. "
    "`timeout: %d` 를 주거나 `run_in_background: true` 로 · 긴 일은 arch/나노에 쪽지로 맡기세요. "
    "(쪽지 mbox.sh·byz_thread_post.py 도 timeout 을 줘야 합니다)" % (FG_MS // 1000, FG_MS)
)


def allow(why=None):
    if why:
        line = time.strftime("%Y-%m-%dT%H:%M:%S") + f" desk-bash-fg-gate: {why}"
        print(f"WARN {line}", file=sys.stderr)
        try:
            os.makedirs(os.path.dirname(LOG), exist_ok=True)
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass
    sys.exit(0)


def tmux_session(pane):
    p = subprocess.run(["tmux", "display-message", "-p", "-t", pane, "#{session_name}"], capture_output=True, text=True, timeout=5)
    if p.returncode != 0:
        raise RuntimeError(f"tmux display-message rc={p.returncode} {p.stderr.strip()[:80]}")
    return p.stdout.strip()


def byz_root(cwd):
    root = os.environ.get("FT_ROOT")
    if not root:
        p = subprocess.run(["git", "-C", cwd or os.getcwd(), "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, timeout=5)
        root = os.path.dirname(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else ""
    return root


try:
    d = json.loads(os.environ["INPUT"])
except ValueError:
    allow("입력 JSON 을 읽지 못함")
if d.get("tool_name", "Bash") != "Bash":
    allow()
ti = d.get("tool_input") or {}
if ti.get("run_in_background") is True:
    allow()
try:
    seats = os.path.join(byz_root(d.get("cwd")), ".fable-team", "seats-planner.json")
    with open(seats, encoding="utf-8") as f:
        desk = json.load(f).get("_desk") or ""
except (OSError, ValueError, subprocess.SubprocessError) as e:
    allow(f"seats-planner.json 명부를 읽지 못함 — 허용: {e}")
pane = os.environ.get("TMUX_PANE")
if not pane:
    allow("tmux 좌석 이름을 못 구함(TMUX_PANE 없음) — 허용")
try:
    me = tmux_session(pane)
except (RuntimeError, subprocess.SubprocessError, OSError) as e:
    allow(f"tmux 조회 실패 — 허용: {e}")
if me != desk:
    allow()
t = ti.get("timeout")
if isinstance(t, (int, float)) and not isinstance(t, bool) and 0 < t <= FG_MS:
    allow()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": REASON}}, ensure_ascii=False))
PYEOF
