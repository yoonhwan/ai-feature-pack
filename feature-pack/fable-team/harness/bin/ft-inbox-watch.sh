#!/usr/bin/env bash
# ft-inbox-watch.sh <좌석> — 오빠 대면 좌석(planner)이 자기 쪽지 큐를 «세션 안»에서 지켜본다(R34·R57·R85 · 판정 881).
# Claude Code Monitor 의 command 로 건다: 새 쪽지 1건 = stdout 1줄 = 세션 안 알림 1건. pane 키 입력(send-keys)·tmux 호출 0 · 읽기 전용.
#   출력 1줄: [쪽지] #<seq> <분류> <from> <본문 첫 줄 40자>  (본문 못 읽으면 `(본문 없음)`)
#   큐 = ft_inbox_core.qpath(<좌석>) (FT_ROOT 규약 그대로) · 시작 시점에 이미 있던 seq 는 «본 것» — 놓친 옛 쪽지는 틱 recv 몫.
#   ★tail -F 금지★: 분류기가 행을 갱신할 때 큐 파일을 통째로 다시 쓴다(write_q) → tail 이 같은 행을 다시 낸다. seq 집합으로 중복을 막는다.
#   환경: FT_INBOX_WATCH_POLL(기본 1초). 큐 없음·깨진 줄은 30초에 1번만 stderr 경고하고 계속 — 종료 0 은 SIGTERM 때만.
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: ft-inbox-watch.sh <좌석>" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec python3 -u - "$HERE" "$1" <<'PY'
import json
import os
import signal
import sys
import time
import fcntl
import hashlib
import uuid
from pathlib import Path

sys.path.insert(0, sys.argv[1])
from ft_inbox_core import qpath

Q = qpath(sys.argv[2])
ROOT = Path(os.environ["FT_ROOT"]).resolve()
COMM = Path(os.environ.get("FT_MBOX_DIR", ROOT / ".fable-team/comm")).resolve()
if COMM != (ROOT / ".fable-team/comm").resolve():
    sys.exit("REJECT canonical comm/root 불일치")
sys.path.insert(0, str(COMM))
import mbox_lineage as lineage
lineage.CANON = str(COMM)
SEAT, TOKEN = sys.argv[2], uuid.uuid4().hex
POLL = float(os.environ.get("FT_INBOX_WATCH_POLL", "1"))
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
last_warn = 0.0


def warn(msg):
    global last_warn
    if time.time() - last_warn >= 30:
        print(f"WARN ft-inbox-watch {msg}", file=sys.stderr, flush=True)
        last_warn = time.time()


def identity():
    directory = Path(os.environ.get("FT_SEATS_JSON", COMM.parent / "seats.json")).resolve().parent
    docs = [(p.resolve(), json.loads(p.read_text(encoding="utf-8"))) for p in directory.glob("seats*.json")]
    matches = [(p, doc) for p, doc in docs if isinstance(doc.get(SEAT), dict)]
    if len(matches) != 1:
        raise ValueError("명부 수신자 유일성")
    path, doc = matches[0]
    if lineage.holder(SEAT) != SEAT:
        return None
    row, role = doc[SEAT], doc[SEAT].get("role")
    fields = [key for key in ("_master", "_arch", "_desk", "_da", "_tester", "_pm") if doc.get(key) == SEAT]
    if fields != ["_" + str(role)] or lineage._team_rows(SEAT)[1] != row:
        raise ValueError("현역 역할 필드 불일치")
    for name in (key for key, value in doc.items() if isinstance(value, dict)):
        seen, current = set(), name
        while isinstance(doc.get(current), dict) and doc[current].get("_replaced_by"):
            if current in seen:
                raise ValueError("승계 순환")
            seen.add(current)
            current = doc[current]["_replaced_by"]
            if current not in doc:
                raise ValueError("승계 후계 없음")
    names, warnings = lineage.eligible(SEAT)
    if warnings:
        raise ValueError("수신 계보 판정 불가")
    return (str(COMM), str(path), fields[0]), names


def save(state):
    temporary = STATE.with_suffix(".tmp-" + TOKEN)
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(state, stream)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, STATE)


try:
    BINDING = identity()
    if BINDING is None:
        sys.exit(0)
    key = hashlib.sha256(json.dumps(BINDING[0]).encode()).hexdigest()
    directory = ROOT / ".fable-team/state/inbox-watch"
    directory.mkdir(parents=True, exist_ok=True)
    LOCK = (directory / (key + ".lock")).open("a+")
    try:
        fcntl.flock(LOCK.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("BUSY owner_lock", file=sys.stderr)
        sys.exit(3)
    STATE = directory / (key + ".json")
    state = json.loads(STATE.read_text()) if STATE.exists() else {"generation": 0}
    state.update(generation=state["generation"] + 1, owner=TOKEN, recipient=SEAT, canonical=BINDING[0])
    save(state)
except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
    print("WARN ft-inbox-watch owner " + type(error).__name__, file=sys.stderr)
    sys.exit(2)


def current_owner():
    current = identity()
    metadata = json.loads(STATE.read_text())
    return current is not None and current[0] == BINDING[0] and metadata.get("owner") == TOKEN and metadata.get("generation") == state["generation"]


def rows():
    try:
        f = open(Q, encoding="utf-8")
    except OSError:
        warn(f"큐 없음 {Q}")
        return []
    out = []
    with f:
        for ln in f:
            try:
                x = json.loads(ln) if ln.strip() else None
            except ValueError:
                warn(f"깨진 줄 {Q}")
                continue
            if isinstance(x, dict) and x.get("seq") is not None:
                out.append(x)
    return out


def first_line(x):
    try:
        with open(x["body_path"], encoding="utf-8") as f:
            return f.readline().strip()[:40] or "(본문 없음)"
    except (KeyError, OSError):
        return "(본문 없음)"


seen = {x["seq"] for x in rows()}
while True:
    time.sleep(POLL)
    try:
        if not current_owner():
            sys.exit(0)
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        warn("owner 관측 " + type(error).__name__)
        continue
    for x in sorted((r for r in rows() if r["seq"] not in seen), key=lambda r: r["seq"]):
        seen.add(x["seq"])
        print(f"[쪽지] #{x['seq']} {x.get('cls', '미상')} {x.get('from', '?')} {first_line(x)}", flush=True)
PY
