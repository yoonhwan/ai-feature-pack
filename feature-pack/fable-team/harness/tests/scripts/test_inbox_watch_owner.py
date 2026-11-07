"""Frozen inbox owner contracts; fake clock/pipe, temporary canonical comm only."""
import io
import json
import multiprocessing as mp
import os
import subprocess
import sys
from pathlib import Path

import pytest

PACK = Path(__file__).resolve().parents[3]
BIN = PACK / "harness/bin"
SEAT = "byz-planner-master-claude#1"


def child(pipe, root, seat, barrier):
    import time
    os.environ.update(FT_ROOT=str(root), FT_MBOX_DIR=str(root / ".fable-team/comm"), LC_ALL="C")
    os.environ["FT_SEATS_JSON"] = str(root / ".fable-team/seats-planner.json")
    out, err = io.StringIO(), io.StringIO()
    sys.stdout, sys.stderr, sys.argv = out, err, ["-", str(BIN), seat]
    def poll(_):
        pipe.send(("poll", out.getvalue(), err.getvalue()))
        command = pipe.recv()
        if command == "broken":
            sys.stdout = io.TextIOBase()
        if command == "stop":
            raise EOFError
    time.sleep, time.time = poll, lambda: 240.0
    if barrier:
        barrier.wait(timeout=3)
    code = (BIN / "ft-inbox-watch.sh").read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
    rc = 0
    try:
        exec(compile(code, "ft-inbox-watch.sh#python", "exec"), {})
    except EOFError:
        pass
    except SystemExit as error:
        rc = error.code or 0
    except Exception as error:
        rc = 2
        print(type(error).__name__ + ": " + str(error), file=err)
    pipe.send(("exit", rc, out.getvalue(), err.getvalue()))


class Owner:
    def __init__(self, root, seat=SEAT, barrier=None):
        self.pipe, other = mp.Pipe()
        self.process = mp.get_context("fork").Process(target=child, args=(other, root, seat, barrier))
        self.process.start()
        self.event = None

    def read(self):
        assert self.pipe.poll(4), "owner control deadline"
        self.event = self.pipe.recv()
        return self.event

    def tick(self, command="tick"):
        self.pipe.send(command)
        return self.read()

    def close(self):
        if self.event is None:
            self.read()
        if self.event[0] == "poll":
            self.pipe.send("stop")
            self.read()
        self.process.join(3)
        assert not self.process.is_alive(), "normal owner exit required; no kill fallback"
        self.pipe.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")


@pytest.fixture
def world(tmp_path, monkeypatch):
    import shutil
    root = tmp_path / "root"
    ft = root / ".fable-team"
    shutil.copytree(PACK / "harness/comm", ft / "comm")
    write(ft / "comm/mailbox.jsonl", [])
    write(ft / "state/inbox" / (SEAT.split("#")[0] + ".jsonl"), [])
    (ft / "seats-planner.json").write_text(json.dumps({"_master": SEAT, SEAT: {"role": "master"}}))
    guard = tmp_path / "guard"
    guard.mkdir()
    for name in ("tmux", "launchctl", "claude", "codex", "pi", "curl"):
        p = guard / name
        p.write_text('#!/bin/sh\necho INVALID_EXTERNAL >> "'+str(tmp_path / "invalid")+'"\nexit 97\n')
        p.chmod(0o755)
    monkeypatch.setenv("PATH", str(guard) + os.pathsep + os.environ["PATH"])
    yield root
    assert not (tmp_path / "invalid").exists(), "invalid fixture: external runtime contact"


def test_singleton_same_key_competition_and_reacquire(world):
    barrier = mp.get_context("fork").Barrier(2)
    with Owner(world, barrier=barrier) as left, Owner(world, barrier=barrier) as right:
        events = [left.read(), right.read()]
        assert sum(event[0] == "poll" for event in events) == 1
        loser = next(event for event in events if event[0] == "exit")
        assert loser[1:3] == (3, "") and "BUSY owner_lock" in loser[3]
    lock = next((world / ".fable-team/state/inbox-watch").glob("*.lock"))
    inode = lock.stat().st_ino
    with Owner(world) as again:
        assert again.read()[0] == "poll" and lock.stat().st_ino == inode


def test_owner_fences_retired_generation(world):
    with Owner(world) as owner:
        assert owner.read()[0] == "poll"
        p = world / ".fable-team/seats-planner.json"
        successor = "byz-planner-master-pi#2"
        p.write_text(json.dumps({"_master": successor, SEAT: {"role": "stop-ready", "_replaced_by": successor},
                                 successor: {"role": "master", "_replaces": [SEAT]}}))
        assert owner.tick()[:2] == ("exit", 0)


@pytest.mark.parametrize("different_root", [False, True])
def test_other_root_or_role_is_independent(world, tmp_path, different_root):
    import shutil
    other, seat = world, "byz-planner-desk-claude#1"
    if different_root:
        other, seat = tmp_path / "independent", SEAT
        shutil.copytree(world, other)
    else:
        p = world / ".fable-team/seats-planner.json"
        p.write_text(json.dumps({"_master": SEAT, SEAT: {"role": "master"}, "_desk": seat, seat: {"role": "desk"}}))
    with Owner(world) as left, Owner(other, seat) as right:
        assert left.read()[0] == right.read()[0] == "poll"


def queue(root, seqs):
    path = root / ".fable-team/comm/mailbox.jsonl"
    write(path.with_suffix(".tmp"), [{"seq": n, "to": SEAT, "from": "source" + str(n),
          "body": "[HIL] " + "x" * 80 + "\nsecond line"} for n in seqs])
    path.with_suffix(".tmp").replace(path)


def receive(root, sender):
    comm = root / ".fable-team/comm"
    env = dict(os.environ, FT_ROOT=str(root), FT_MBOX_DIR=str(comm), FT_SEATS_JSON=str(comm.parent / "seats-planner.json"))
    return subprocess.run([sys.executable, "-B", str(comm / "mbox.py"), "recv", SEAT, sender, "--all"], env=env,
                          capture_output=True, text=True, timeout=7)


def test_backlog_receipts_rewrite_and_restart(world):
    queue(world, [10, 11, 12])
    assert receive(world, "source11").returncode == 0
    with Owner(world) as owner:
        assert owner.read()[0] == "poll"
        event = owner.tick()
        assert "#10 " in event[1] and "#12 " in event[1] and "#11 " not in event[1]
        assert owner.tick()[1] == event[1]
        state = json.loads(next((world / ".fable-team/state/inbox-watch").glob("*.json")).read_text())
        assert set(state["pending"]) == {"10", "12"} and 11 in state["received"]
        receipt = world / ".fable-team/comm/receipts" / (SEAT + ".jsonl")
        original = receipt.read_bytes()
        receipt.write_text("{")
        assert owner.tick()[1] == event[1]
        receipt.write_bytes(original)
        queue(world, [10, 12, 14])
        assert owner.tick("broken")[1] == event[1]
        state = json.loads(next((world / ".fable-team/state/inbox-watch").glob("*.json")).read_text())
        assert state["pending"]["14"]["notified_generation"] is None
    queue(world, [10, 12, 13])
    with Owner(world) as restarted:
        restarted.read()
        out = restarted.tick()[1]
        assert all("#" + str(n) + " " in out for n in (10, 12, 13)) and "#11 " not in out
