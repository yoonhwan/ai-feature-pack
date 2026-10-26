#!/usr/bin/env bash
# ft-inbox-watch.sh <좌석> — 오빠 대면 좌석(planner)이 자기 쪽지 큐를 «세션 안»에서 지켜본다(R34·R57·R85 · 판정 881).
# Claude Code Monitor 의 command 로 건다: 새 쪽지 1건 = stdout 1줄 = 세션 안 알림 1건. pane 키 입력(send-keys)·tmux 호출 0 · 읽기 전용.
#   출력 1줄: [쪽지] #<seq> <분류> <from> <본문 첫 줄 40자>  (본문 못 읽으면 `(본문 없음)`)
#   큐 = ft_inbox_core.qpath(<좌석>) (FT_ROOT 규약 그대로) · 시작 시점에 이미 있던 seq 는 «본 것» — 놓친 옛 쪽지는 틱 recv 몫.
#   ★tail -F 금지★: 분류기가 행을 갱신할 때 큐 파일을 통째로 다시 쓴다(write_q) → tail 이 같은 행을 다시 낸다. seq 집합으로 중복을 막는다.
#   환경: FT_INBOX_WATCH_POLL(기본 1초). 큐 없음·깨진 줄은 30초에 1번만 stderr 경고하고 계속 — 종료 0 은 SIGTERM 때만.
#   ★끝 표식(r928)★: 끝날 때(EXIT·TERM·INT) state/planner-watch-last.<좌석> 에 «YYYY-MM-DD HH:MM:SS watch-end <좌석>» 1줄 — ft-mbox.sh watch_alarm 이
#     이 mtime 으로 «다시 거는 틈»(기본 5분)을 유예한다(Monitor 30분 한도 뒤 재기동 틈을 «감시 없음» 긴급으로 오인하지 않게). 쓰기 실패 = WARN 1줄(fail-open).
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: ft-inbox-watch.sh <좌석>" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec python3 -u - "$HERE" "$1" <<'PY'
import json
import os
import signal
import sys
import time

sys.path.insert(0, sys.argv[1])
from ft_inbox_core import qpath

SEAT = sys.argv[2]
Q = qpath(SEAT)
POLL = float(os.environ.get("FT_INBOX_WATCH_POLL", "1"))
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
last_warn = 0.0
# ★r928 끝 표식★ — <루트>/.fable-team/state (= 큐 경로의 state/inbox 두 단계 위) · 좌석 이름 규칙은 ft-mbox.sh 와 같다(tr -c 'A-Za-z0-9._#-' '_').
STATE = os.path.dirname(os.path.dirname(Q))
MARK = os.path.join(STATE, "planner-watch-last." + "".join(
    c if c in "._#-" or (c.isascii() and c.isalnum()) else "_" for c in SEAT))


def mark_end():
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(MARK, "w", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S") + " watch-end " + SEAT + "\n")
    except OSError as e:  # 표식을 못 남기면 유예가 없다 = 기존처럼 긴급. 감시는 이미 끝나므로 여기서 죽지 않는다.
        print(f"WARN ft-inbox-watch 끝 표식 실패 {MARK}: {e}", file=sys.stderr, flush=True)


def warn(msg):
    global last_warn
    if time.time() - last_warn >= 30:
        print(f"WARN ft-inbox-watch {msg}", file=sys.stderr, flush=True)
        last_warn = time.time()


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
try:
    while True:
        time.sleep(POLL)
        for x in sorted((r for r in rows() if r["seq"] not in seen), key=lambda r: r["seq"]):
            seen.add(x["seq"])
            print(f"[쪽지] #{x['seq']} {x.get('cls', '미상')} {x.get('from', '?')} {first_line(x)}", flush=True)
finally:
    mark_end()
PY
