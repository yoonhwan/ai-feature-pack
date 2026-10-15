#!/bin/bash
# desk-self-interview-gate — PreToolUse:AskUserQuestion (R241 · DESIGN-r241-desk-never-stall §1)
# 왜: desk 가 자기 화면에 질문 창을 열면 닫힐 때까지 desk 가 멈추고, 그 사이 슬랙 글은 큐에만 쌓인다(오빠 10-15 «인터뷰 떠 있으면 슬랙도 다 멈춰»).
# 동작: 좌석 이름(tmux 세션) = 명부 seats-planner.json `_desk` 일 때만 본다.
#   desk 세션에 붙은 tmux 클라이언트 중 «attach 뒤 실제 키 사건이 있고»(client_activity > client_created) now − client_activity ≤ FT_DESK_DIRECT_SEC(기본 600)가 있으면 허용 — 오빠가 desk 화면에서 직접 치는 중.
#   client_created 를 못 읽거나 attach 시각과 같으면(키 0) 예외 불성립 = deny — attach 자체를 직접 키로 읽지 않는다(DA⑥ H1). 질문은 슬랙 #byz-desk 스레드 묶음 글로.
#   (기계 입력 send-keys 는 client_activity 값에 반영되지 않는다 — 시험 ③ 이 실측하고, ②b 가 send-keys 만으로는 예외가 성립하지 않음을 확인한다.)
# ★못 읽음★: 명부·tmux 조회 실패 = 허용 + FT_DESK_LOG(기본 ~/.claude/logs/desk-route.log) 1줄 + stderr — 조용히 막지 않는다(인터뷰는 되돌릴 수 있다).
# 외부 호출 0 — tmux 2회 + 파일 1회. 환경: FT_ROOT(루트 고정) · FT_DESK_DIRECT_SEC · FT_DESK_LOG.
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse AskUserQuestion 등록)는 master — 이 파일 범위 밖★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
python3 - <<'PYEOF'
import json, os, subprocess, sys, time

LOG = os.environ.get("FT_DESK_LOG") or os.path.expanduser("~/.claude/logs/desk-route.log")
DIRECT_SEC = int(os.environ.get("FT_DESK_DIRECT_SEC") or 600)
REASON = (
    "desk 화면 인터뷰 금지(R241) — 질문 창이 열려 있으면 desk 가 멈추고 슬랙 글이 쌓입니다. "
    "슬랙 #byz-desk 스레드에 질문 묶음 글 1개로: `byz_thread_post.py reply --ts <오빠 글 ts> --text-file <파일>` "
    "(R235 형식: 질문 전부 한 글 · `<i>-<j>` 번호 선택지 · 추천 `<i>-1` · 끝줄 «답 예: 1-1 2-1 · 모두 추천»). "
    "창을 열지 말고 다음 일을 하세요 — 답은 수신 데몬이 쪽지로 가져옵니다. "
    "(오빠가 desk 화면에서 직접 친 지 %d초 안이면 이 훅은 통과시킵니다)" % DIRECT_SEC
)


def allow(why=None):
    if why:
        line = time.strftime("%Y-%m-%dT%H:%M:%S") + f" desk-self-interview-gate: {why}"
        print(f"WARN {line}", file=sys.stderr)
        try:
            os.makedirs(os.path.dirname(LOG), exist_ok=True)
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass
    sys.exit(0)


def tmux(*args):
    p = subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=5)
    if p.returncode != 0:
        raise RuntimeError(f"tmux {args[0]} rc={p.returncode} {p.stderr.strip()[:80]}")
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
if d.get("tool_name", "AskUserQuestion") != "AskUserQuestion":
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
    me = tmux("display-message", "-p", "-t", pane, "#{session_name}")
    if me != desk:
        allow()
    rows = [ln.split() for ln in tmux("list-clients", "-t", me, "-F", "#{client_activity} #{client_created}").splitlines()]
except (RuntimeError, subprocess.SubprocessError, OSError) as e:
    allow(f"tmux 조회 실패 — 허용: {e}")
def typed(row):  # attach 뒤 키 사건이 있고(activity > created) 창 안. 값을 못 읽으면 불성립
    try:
        act, created = int(row[0]), int(row[1])
    except (IndexError, ValueError):
        return False
    return act > created and time.time() - act <= DIRECT_SEC


if any(typed(r) for r in rows):
    allow()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": REASON}}, ensure_ascii=False))
PYEOF
