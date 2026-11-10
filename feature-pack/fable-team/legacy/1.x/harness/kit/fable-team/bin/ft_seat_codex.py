#!/usr/bin/env python3
"""ft_seat_codex.py — codex 좌석의 «턴 경계» 판정 (R132a · 제안서 §7-1). `ft-seat-status.sh turn` 이 명부 agent=codex 좌석만 여기에 맡긴다.

본체 찾기: 좌석 pane PID 의 자손 중 실행 파일 basename 이 정확히 `codex` 인 PID(코드모드 호스트·node 제외) → `lsof` 로 연
`~/.codex/sessions/**/rollout-*.jsonl` 정확히 1개일 때만 판정한다. 0개·2개 이상·본체 없음 = UNKNOWN + 사유 — pane 스피너·cwd·시각 근접으로
대신 고르지 않는다(#0 RULE). rollout 은 `event_msg` 의 task_started / task_complete / turn_aborted 의 종류·turn_id·시각 키만 읽는다(대화 본문 0).
판정: 마지막 task_started 뒤 종결 사건이 없으면 WORKING · 같은 turn_id 의 종결이면 IDLE(turn_end = 종결 시각 · turn_aborted 면 aborted) ·
종결의 turn_id 가 마지막 시작과 다르면 UNKNOWN(turn_id 불일치).
출력 1행(탭 8열): STATE TURN_END DURATION_MS REPORTED(-) codex READ_BYTES ABORTED(aborted|-) REASON(-|사유)
usage: ft_seat_codex.py [--if-codex <명부 폴더>] <seat>   (--if-codex: 명부 seats*.json 의 agent 가 codex 가 아니면 rc 3 · 출력 0)
env(시험용 주입): FT_SEAT_CODEX_PANE_PID · FT_SEAT_CODEX_PS(기본 `ps -axo pid=,ppid=,comm=`) · FT_SEAT_CODEX_LSOF(기본 `lsof -Fn -p`, 뒤에 pid)
                 · FT_SEAT_CODEX_ROOT(기본 ~/.codex/sessions) · FT_SEAT_CODEX_TAIL_CAP(기본 16MB)
"""
import glob
import json
import os
import re
import shlex
import subprocess
import sys

KINDS = (b"task_started", b"task_complete", b"turn_aborted")
TERMINAL = ("task_complete", "turn_aborted")
START_WIN = 65536


def _run(cmd: list[str]) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError(f"{cmd[0]} 실패 rc={r.returncode}: {r.stderr.strip()[:200]}")
    return r.stdout


def pane_pid(seat: str) -> str | None:
    if os.environ.get("FT_SEAT_CODEX_PANE_PID"):
        return os.environ["FT_SEAT_CODEX_PANE_PID"]
    r = subprocess.run(["tmux", "list-panes", "-a", "-F", "#{session_name}|#{pane_pid}"], capture_output=True, text=True, timeout=30)
    rows = [x.split("|", 1) for x in r.stdout.splitlines() if "|" in x]
    return next((pid for name, pid in rows if name == seat), None)


def descendants(root: str) -> list[tuple[str, str]]:
    """(pid, 실행 파일 경로) — 공백 없는 comm 만(`npm exec …` 같은 프로세스 제목은 실행 파일이 아니다)."""
    table = os.environ.get("FT_SEAT_CODEX_PS", "ps -axo pid=,ppid=,comm=")
    kids: dict[str, list[tuple[str, str]]] = {}
    for line in _run(shlex.split(table)).splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3:
            kids.setdefault(parts[1], []).append((parts[0], parts[2].strip()))
    out, todo = [], [root]
    while todo:
        for pid, comm in kids.get(todo.pop(), []):
            out.append((pid, comm))
            todo.append(pid)
    return out


def rollouts_of(pid: str) -> set[str]:
    sessions = os.path.realpath(os.environ.get("FT_SEAT_CODEX_ROOT", os.path.expanduser("~/.codex/sessions")))
    found = set()
    for line in _run(shlex.split(os.environ.get("FT_SEAT_CODEX_LSOF", "lsof -Fn -p")) + [pid]).splitlines():
        for path in re.findall(r"/\S*rollout-\S*\.jsonl", line):
            real = os.path.realpath(path)
            if real.startswith(sessions + os.sep):
                found.add(real)
    return found


def read_events(path: str) -> tuple[list[tuple[str, str, str, object]], int]:
    """끝에서부터 창을 2배씩 넓혀 마지막 task_started 가 보일 때까지 읽는다 → ([(kind, turn_id, ts, duration_ms)], 읽은 바이트)"""
    size, cap = os.path.getsize(path), int(os.environ.get("FT_SEAT_CODEX_TAIL_CAP", str(16 << 20)))
    win = START_WIN
    while True:
        want = min(win, size)
        with open(path, "rb") as fh:
            fh.seek(size - want)
            raw = fh.read(want)
        lines = raw.split(b"\n")
        if want < size:
            lines = lines[1:]  # 잘린 첫 줄 버림
        events = []
        for line in lines:
            if not any(k in line for k in KINDS):
                continue
            try:
                rec = json.loads(line)
                pl = rec["payload"]
                if rec.get("type") == "event_msg" and pl.get("type") in ("task_started", *TERMINAL):
                    events.append((pl["type"], str(pl.get("turn_id")), str(rec.get("timestamp", "-")), pl.get("duration_ms")))
            except (ValueError, KeyError, TypeError, AttributeError):
                continue  # 손상·미완 행은 건너뛴다
        if any(e[0] == "task_started" for e in events) or want >= size or want >= cap:
            return events, want
        win *= 2


def judge(events: list[tuple[str, str, str, object]]) -> tuple[str, str, str, bool, str]:
    """(STATE, turn_end, duration_ms, aborted, 사유)"""
    starts = [i for i, e in enumerate(events) if e[0] == "task_started"]
    if not starts:
        return "UNKNOWN", "-", "-", False, "task_started 기록 없음"
    last = starts[-1]
    ends = events[last + 1:]
    if not ends:
        return "WORKING", "-", "-", False, "-"
    kind, turn_id, ts, dur = ends[-1]
    if turn_id != events[last][1]:
        return "UNKNOWN", "-", "-", False, "turn_id 불일치"
    return "IDLE", ts, ("-" if dur is None else str(dur)), kind == "turn_aborted", "-"


def row(seat: str) -> list[str]:
    def unknown(why: str, nbytes: int = 0) -> list[str]:
        return ["UNKNOWN", "-", "-", "-", "codex", str(nbytes), "-", why]

    pid = pane_pid(seat)
    if not pid:
        return unknown("좌석 pane 없음")
    bodies = [p for p, comm in descendants(pid) if " " not in comm and os.path.basename(comm) == "codex"]
    if not bodies:
        return unknown("codex 본체 없음")
    files = sorted(set().union(*(rollouts_of(p) for p in bodies)))
    if len(files) != 1:
        return unknown(f"rollout {len(files)}")
    try:
        events, nbytes = read_events(files[0])
    except OSError as e:
        return unknown(f"rollout 읽기 실패: {e.strerror}")
    state, end, dur, aborted, why = judge(events)
    return [state, end, dur, "-", "codex", str(nbytes), "aborted" if aborted else "-", why]


def agent_of(seat: str, roster_dir: str) -> str | None:
    for f in sorted(glob.glob(os.path.join(roster_dir, "seats*.json"))):
        v = json.load(open(f, encoding="utf-8")).get(seat)
        if isinstance(v, dict):
            return v.get("agent")
    return None


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[0] == "--if-codex":
        if agent_of(argv[2], argv[1]) != "codex":
            return 3
        argv = argv[2:]
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    print("\t".join(row(argv[0])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
