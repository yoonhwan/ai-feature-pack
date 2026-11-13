"""r1855 ft2 launch Pi seat (outside the roster, no TMUXC_PI_SESSION_ID) -- first session of the launch intent only.

identity: tmux env FT2_HOLDER == seat and intent FT2_HOLDER == seat and pane command basename == pi.
first_session: pane cwd == intent worktree, head.cwd == worktree, head.timestamp in [intent.at, +120s] exactly 1.
A same-cwd session newer than the window means the pane moved on (세션 바뀜). Never choose the newest file.
"""
import datetime
import json
import os
from pathlib import Path

WINDOW = 120


def identity(seat, tmux, env, run, pane):
    """(intent, pane pid, real cwd) | None (= not an ft2 launch Pi seat)."""
    try:
        if env.get("FT2_HOLDER") != seat:
            return None
        launch = Path(env["FT2_ROOT"]) / ".fable-team" / "teams" / env["FT2_TEAM"] / "runtime" / "launch"
        intent = json.loads((launch / f"{env['FT2_WORK']}@{env['FT2_ATTEMPT']}.intent").read_text(encoding="utf-8"))
        if not isinstance(intent, dict) or intent.get("FT2_HOLDER") != seat:
            return None
        pid, cwd = pane(seat, tmux)
        return (intent, pid, os.path.realpath(cwd)) if Path(run(["ps", "-p", pid, "-o", "comm="]).strip()).name == "pi" else None
    except (OSError, ValueError, KeyError):
        return None


def epoch(text):   # tz 없는 값(intent.at) = 로컬 시각
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()


def first_session(got, root):
    """(path, head, pane pid, worktree) — intent 때 첫 세션 «정확히 1개» · 0·2+·세션 바뀜 = ValueError."""
    intent, pid, cwd = got
    if not all(isinstance(intent.get(k), str) for k in ("worktree", "at")):
        raise ValueError("Pi intent worktree·at 없음")
    wt, at, hits, late = os.path.realpath(intent["worktree"]), epoch(intent["at"]), [], 0
    if cwd != wt:
        raise ValueError("Pi pane cwd ≠ intent worktree")
    for path in root.glob("*/*.jsonl"):
        try:
            with path.open(encoding="utf-8") as stream:
                head = json.loads(stream.readline())
            if head.get("type") != "session" or not isinstance(head.get("id"), str) or os.path.realpath(head["cwd"]) != wt:
                continue
            ts = epoch(head["timestamp"])
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            continue
        hits += [(str(path), head, pid, wt)] if at <= ts <= at + WINDOW else []
        late += ts > at + WINDOW
    if late:
        raise ValueError("세션 바뀜")
    if len(hits) != 1:
        raise ValueError(f"Pi session 후보 {len(hits)}개")
    return hits[0]
