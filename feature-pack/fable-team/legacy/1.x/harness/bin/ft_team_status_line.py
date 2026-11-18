"""ft_team_status_line.py --hil <N|?> [--root R] [--now EPOCH]  (r2255 · desk 틱이 매 틱 1회 부름)

TEAM-STATUS.md 1행 «스크립트 X · 인터뷰 Y · 막힌 팀 대기 Z» 와 2행 설명을 새로 쓴다(3행부터 바이트 그대로).
  스크립트 = --hil 인자 그대로(desk 틱 ① HIL_N · ① 실패면 «?»)
  인터뷰   = desk-reply-wait.jsonl 열쇠 (kind, q_ts) 마다 마지막 줄 중 kind=question ∧ state ∈ {open, notified} 수
             (열쇠 = ft_desk_reply_wake.rowkey 와 같은 식 · 파일 없음 · 깨진 줄 · 읽기 실패 = «?»)
  막힌 팀  = stall-scan.last.json teams 중 f ≥ 1 팀 수(diag 팀 셈 0 · 파일 없음 · 읽기 실패 · ts 10분 넘게 낡음 = «?»)
못 센 칸은 0 대신 «?»(조용한 0 금지). 쓰기 = 같은 폴더 임시 파일 → os.replace · 권한 기존 그대로 · 외부 호출 0.
출력 = 1행 1줄 · rc0. 폴더 없음 · 쓰기 실패 = rc1 «판정 불가 …» 1줄(하드 룰 20) · 인자 오류 = rc2.
"""
from __future__ import annotations  # mini python 3.9.6

import json
import os
import sys
import tempfile
import time
from pathlib import Path

REL = Path(".fable-team") / "state"
STALL_STALE_SEC = 600
OPEN = ("open", "notified")
UNKNOWN = "?"


def rowkey(r: dict) -> tuple:  # ft_desk_reply_wake.rowkey 와 같은 식(r1764) — 같은 q_ts 의 thread 줄이 question 줄을 가리지 않는다
    return (r.get("kind") or "h", r.get("q_ts"))


def interviews(ledger: Path) -> str:
    try:
        lines = ledger.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return UNKNOWN
    last = {}
    for line in lines:
        if not line.strip():
            continue
        try:
            r = json.loads(line)
        except ValueError:
            return UNKNOWN
        if not isinstance(r, dict):
            return UNKNOWN
        last[rowkey(r)] = r
    return str(sum(1 for r in last.values() if r.get("kind") == "question" and r.get("state") in OPEN))


def stalled(last_json: Path, now: float) -> tuple:
    """(칸, stall-scan 시각 epoch 또는 None)."""
    try:
        d = json.loads(last_json.read_text(encoding="utf-8"))
        ts = float(d["ts"])
        teams = d["teams"]
        if not isinstance(teams, dict):
            return UNKNOWN, None
    except (OSError, UnicodeDecodeError, ValueError, KeyError, TypeError):
        return UNKNOWN, None
    if now - ts > STALL_STALE_SEC:
        return UNKNOWN, ts
    n = sum(1 for t in teams.values() if isinstance(t, dict) and "diag" not in t and (t.get("f") or 0) >= 1)
    return str(n), ts


def hhmm(t: float | None) -> str:
    return time.strftime("%H:%M", time.localtime(t)) if t is not None else UNKNOWN


def write(f: Path, first: str, second: str) -> None:
    try:
        rest = f.read_bytes().split(b"\n", 2)
        tail = rest[2] if len(rest) > 2 else b""
        mode = f.stat().st_mode & 0o7777
    except FileNotFoundError:
        tail, mode = b"", 0o644
    data = (first + "\n" + second + "\n").encode("utf-8") + tail
    fd, tmp = tempfile.mkstemp(prefix=".TEAM-STATUS.", dir=str(f.parent))
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, f)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def parse(argv: list) -> tuple:
    opts = {"--hil": None, "--root": os.environ.get("FT_ROOT") or os.getcwd(), "--now": None}
    it = iter(argv)
    for a in it:
        if a not in opts:
            raise ValueError(a)
        opts[a] = next(it)
    hil = opts["--hil"]
    if hil is None or not (hil == UNKNOWN or hil.isdigit()):
        raise ValueError("--hil")
    now = float(opts["--now"]) if opts["--now"] is not None else time.time()
    return hil, Path(opts["--root"]), now


def main(argv: list) -> int:
    try:
        hil, root, now = parse(argv)
    except (ValueError, StopIteration):
        print("usage: ft_team_status_line.py --hil <N|?> [--root R] [--now EPOCH]", file=sys.stderr)
        return 2
    state = root / REL
    folder = state / "planner-tick"
    if not folder.is_dir():
        print(f"판정 불가 — 폴더 없음 {folder}")
        return 1
    stall, sts = stalled(state / "stall-scan.last.json", now)
    first = f"스크립트 {hil} · 인터뷰 {interviews(state / 'desk-reply-wait.jsonl')} · 막힌 팀 대기 {stall}"
    second = (f"설명: desk 틱 {hhmm(now)} · 스크립트 = HIL 대기 · 인터뷰 = 열린 오빠 질문(desk-reply-wait)"
              f" · 막힌 팀 = 팀장 심박 끊김(stall-scan {hhmm(sts)})")
    try:
        write(folder / "TEAM-STATUS.md", first, second)
    except OSError as e:
        print(f"판정 불가 — 쓰기 실패 {e}")
        return 1
    print(first)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
