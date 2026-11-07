#!/usr/bin/env python3
"""Internal Pi adapter. --if-pi <roster-dir> <seat>: non-Pi rc3.

Live binding uses a live pane, its cwd, TMUXC_PI_SESSION_ID and session_info.name.
FT_TMUX / FT_PI_SESSIONS select isolated sources for tests. No model calls.
--if-file classifies an explicitly supplied Pi file without proving live ownership.
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from ft_seat_codex import agent_of
from ft_seat_pi_turn import file_row, is_pi_file


def run(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=7)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} 조회 실패 rc={result.returncode}")
    return result.stdout


def roster_dir():
    if os.environ.get("FT_SEATS_JSON"):
        return str(Path(os.environ["FT_SEATS_JSON"]).parent)
    if os.environ.get("FT_ROOT"):
        return str(Path(os.environ["FT_ROOT"]) / ".fable-team")
    local = Path.cwd() / ".fable-team"
    return str(local if local.is_dir() else Path(__file__).resolve().parent.parent)


def is_pi(seat, directory=None):
    return agent_of(seat, directory or roster_dir()) == "pi"


def live_identity(seat, tmux=None):
    tmux = tmux or os.environ.get("FT_TMUX", "tmux")
    raw = run([tmux, "list-panes", "-a", "-F",
               "#{session_name}\t#{pane_pid}\t#{pane_current_path}\t#{pane_dead}"])
    panes = [ln.split("\t") for ln in raw.splitlines() if ln.split("\t")[0] == seat]
    if len(panes) != 1 or len(panes[0]) != 4:
        raise ValueError("Pi pane 유일성 확인 불가")
    _, pid, cwd, dead = panes[0]
    if not pid.isdigit() or dead != "0" or not Path(cwd).is_dir():
        raise ValueError("Pi pane 생존/cwd 확인 불가")
    if run(["ps", "-p", pid, "-o", "pid="]).strip() != pid:
        raise ValueError("Pi pane 프로세스 확인 불가")
    env = run([tmux, "show-environment", "-t", "=" + seat, "TMUXC_PI_SESSION_ID"])
    ids = [ln.partition("=")[2] for ln in env.splitlines() if ln.startswith("TMUXC_PI_SESSION_ID=")]
    if len(ids) != 1 or not ids[0]:
        raise ValueError("Pi session ID 확인 불가")
    return pid, os.path.realpath(cwd), ids[0]


def locate(seat, tmux=None):
    """Return (path, first session record, pane pid, real cwd); never choose newest."""
    pid, cwd, sid = live_identity(seat, tmux)
    root = Path(os.path.expanduser(os.environ.get("FT_PI_SESSIONS") or os.environ.get("FT_PI_SESSIONS_DIR") or "~/.pi/agent/sessions"))
    found = []
    for path in root.glob("*/*.jsonl"):
        try:
            with path.open(encoding="utf-8") as stream:
                head = json.loads(stream.readline())
                if not isinstance(head, dict) or head.get("type") != "session" or head.get("id") != sid:
                    continue
                if not isinstance(head.get("cwd"), str) or os.path.realpath(head["cwd"]) != cwd:
                    continue
                names = []
                for line in stream:
                    try:
                        record = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(record, dict) and record.get("type") == "session_info":
                        names.append(record.get("name"))
                if seat in names:
                    found.append((str(path), head, pid, cwd))
        except (OSError, ValueError):
            continue
    if len(found) != 1:
        raise ValueError(f"Pi session 후보 {len(found)}개")
    return found[0]


def row(seat, tmux=None):
    return file_row(locate(seat, tmux)[0])


def binding(seat):
    path, head, pid, cwd = locate(seat)
    return dict(rc=0, reason="", engine="pi", pid=int(pid), uuid=head["id"], cwd=cwd,
                jsonl=path, name=seat, name_source="session_info",
                binding=dict(source="pi-session", session=seat, uuid=head["id"], jsonl=path, pid=int(pid)))


def bind_result(seat, expected=None):
    try:
        current = binding(seat)
        if expected is not None and (expected.get("binding") != current["binding"]
                                     or any(expected.get(k) != current[k] for k in ("uuid", "jsonl", "cwd", "pid"))):
            return dict(rc=1, reason="Pi 결속 불일치")
        return current
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
        return dict(rc=2, reason="Pi 결속 판정 불가")


def main(argv):
    try:
        if len(argv) == 3 and argv[0] in ("--if-pi", "--path", "--pane", "--age"):
            if not is_pi(argv[2], argv[1]):
                return 3
            if argv[0] == "--path":
                print(locate(argv[2])[0])
                return 0
            if argv[0] in ("--pane", "--age"):
                path = locate(argv[2])[0]
                state = file_row(path)[0]
                if argv[0] == "--pane":
                    print("BUSY" if state in ("WORKING", "PENDING") else state)
                else:
                    print(int(time.time() - os.path.getmtime(path)) if state == "IDLE" else "-")
                return 0
            argv = argv[2:]
        if len(argv) == 2 and argv[0] == "--if-file":
            if not is_pi_file(argv[1]):
                return 3
            result = file_row(argv[1])
        elif len(argv) == 1:
            result = row(argv[0])
        else:
            return 2
        print("\t".join(result))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("판정 불가 Pi: " + (type(error).__name__ if isinstance(error, subprocess.SubprocessError) else str(error)), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
