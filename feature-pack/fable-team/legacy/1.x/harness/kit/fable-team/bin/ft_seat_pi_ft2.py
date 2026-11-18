"""r1855 ft2 launch Pi seat (outside the roster, no TMUXC_PI_SESSION_ID) -- first session of the launch intent only.

identity: tmux env FT2_HOLDER == seat and intent FT2_HOLDER == seat and pane command basename == pi.
first_session: pane cwd == intent worktree, head.cwd == worktree, head.timestamp in [intent.at, +120s] exactly 1.
A same-cwd session newer than the window means the pane moved on (세션 바뀜). Never choose the newest file.
r2100: a late session whose id is another live tmux session's TMUXC_PI_SESSION_ID is that seat's, not a move.
r2121: a late session is another seat's when one of its session_info names (never the seat) keys a seat-resume record with that name and uuid == its id.
"""
import datetime
import json
import os
import subprocess
import time
from pathlib import Path

WINDOW = 120
CAP = 7   # r2100 owners() tmux 추가 조회 전체 상한(초)


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


def candidates(root, cwd, none_yet):   # r1993 cwd 폴더 1개 먼저 · 거기서 후보 0 일 때만 전수 glob(뒤 호환)
    yield from sorted((root / ("--" + cwd.strip("/").replace("/", "-") + "--")).glob("*.jsonl"))
    if none_yet():
        yield from root.glob("*/*.jsonl")


def owners(seat, tmux):
    """r2100 산 tmux 세션(좌석 자신 제외)의 env TMUXC_PI_SESSION_ID 값 집합 — 남의 세션 증명.

    list-sessions 실패·시간 초과·상한(7초) 넘음 = 예외(판정 불가) · env 조회 «can't find session» = 그 세션만 건너뜀.
    """
    end = time.monotonic() + CAP

    def call(*args):
        left = end - time.monotonic()
        if left <= 0:
            raise RuntimeError("tmux 조회 상한 넘음")
        return subprocess.run([tmux, "-u", *args], capture_output=True, text=True, timeout=left)

    listed = call("list-sessions", "-F", "#{session_name}")
    if listed.returncode:
        raise RuntimeError(f"tmux list-sessions 실패 rc={listed.returncode}")
    ids = set()
    for name in listed.stdout.splitlines():
        env = call("show-environment", "-t", "=" + name) if name and name != seat else None
        if env is None or (env.returncode and "can't find session" in env.stderr):
            continue
        if env.returncode:
            raise RuntimeError(f"tmux show-environment 실패 rc={env.returncode}")
        ids.update(ln.partition("=")[2] for ln in env.stdout.splitlines() if ln.startswith("TMUXC_PI_SESSION_ID="))
    return ids - {""}


def due(end):
    """r2121 한 판정의 읽기 합계 상한 — 읽기 전·읽기 뒤·결속 성공 전 공용 · 넘음 = ValueError(판정 불가)."""
    if time.monotonic() > end:
        raise ValueError(f"Pi 이름 판독 {CAP}초 넘음")


def names(path, end):
    """r2121 D3 — 파일 전체를 줄 단위로 끝까지 · «"session_info"» 글자 든 줄만 JSON · 이름 목록(없음·빈 = "") · end(monotonic) 넘음 = ValueError."""
    got = []
    with open(path, encoding="utf-8", errors="replace") as stream:
        for line in stream:
            due(end)
            try:
                rec = json.loads(line) if '"session_info"' in line else None
            except ValueError:
                continue
            if isinstance(rec, dict) and rec.get("type") == "session_info":
                got.append(rec["name"].strip() if isinstance(rec.get("name"), str) else "")
    due(end)   # DA R1 — 마지막 줄 읽기 뒤
    return got


def record(name, sid, end):
    """r2121 보정2 — 은퇴 기록 폴더 직접 자식 <name>.json 의 name·uuid 가 같음 = 증명 · 폴더 밖 이름(/·절대·.·..)·못 읽음·깨짐 = 0."""
    if Path(name).name != name or name in (".", ".."):
        return False
    due(end)
    folder = Path(os.path.expanduser(os.environ.get("ZC_RESUME_DIR") or "~/.claude/state/seat-resume"))
    try:
        rec = json.loads((folder / (name + ".json")).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        rec = None
    due(end)   # DA R1 — 기록 읽기·해석 뒤
    return isinstance(rec, dict) and rec.get("name") == name and rec.get("uuid") == sid


def proven(path, sid, seat, end):
    """r2121 D3 보정2 다른 좌석 기록 증명 = 좌석 이름 아닌 session_info 이름(중복 제거)의 은퇴 기록 uuid = 세션 id ∧ 파일 안 좌석 이름 0 · 이름만 = 증거 아님."""
    try:
        got = names(path, end)
    except OSError:
        return False
    if not seat or seat in got:
        return False
    for name in dict.fromkeys(got):
        if name and record(name, sid, end):
            return True
    return False


def first_session(got, root, owner=None):
    """(path, head, pane pid, worktree) — intent 때 첫 세션 «정확히 1개» · 0·2+·세션 바뀜 = ValueError.

    owner = (좌석, tmux) — 창 뒤(late) 후보가 있을 때만 owners() 로 증명된 남의 세션을 뺀다(r2100).
    """
    intent, pid, cwd = got
    if not all(isinstance(intent.get(k), str) for k in ("worktree", "at")):
        raise ValueError("Pi intent worktree·at 없음")
    wt, at, hits, late = os.path.realpath(intent["worktree"]), epoch(intent["at"]), [], []
    if cwd != wt:
        raise ValueError("Pi pane cwd ≠ intent worktree")
    for path in candidates(root, wt, lambda: not hits and not late):
        try:
            with path.open(encoding="utf-8") as stream:
                head = json.loads(stream.readline())
            if head.get("type") != "session" or not isinstance(head.get("id"), str) or os.path.realpath(head["cwd"]) != wt:
                continue
            ts = epoch(head["timestamp"])
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            continue
        hits += [(str(path), head, pid, wt)] if at <= ts <= at + WINDOW else []
        late += [(head["id"], path)] if ts > at + WINDOW else []
    seat, end = intent.get("FT2_HOLDER") or (owner or (None,))[0], time.monotonic() + CAP
    late = [sid for sid, path in late if not proven(path, sid, seat, end)]   # r2121 D3 보정2 — owners 전에 뺌
    due(end)   # DA R1 — 증명·결속 성공 전
    if late and owner:
        late = set(late) - owners(*owner)
    if late:
        raise ValueError("세션 바뀜")
    if len(hits) != 1:
        raise ValueError(f"Pi session 후보 {len(hits)}개")
    return hits[0]
