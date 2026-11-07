"""Frozen inbox owner contracts; fake clock/pipe, temporary canonical comm only."""
import io
import json
import multiprocessing as mp
import os
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
        if pipe.recv() == "stop":
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

    def tick(self):
        self.pipe.send("tick")
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
    owners = [Owner(world, barrier=barrier) for _ in range(2)]
    try:
        events = [owner.read() for owner in owners]
        assert sum(event[0] == "poll" for event in events) == 1
        loser = next(event for event in events if event[0] == "exit")
        assert loser[1:3] == (3, "") and "BUSY owner_lock" in loser[3]
    finally:
        for owner in owners:
            owner.close()
    lock = next((world / ".fable-team/state/inbox-watch").glob("*.lock"))
    inode = lock.stat().st_ino
    again = Owner(world)
    try:
        assert again.read()[0] == "poll" and lock.stat().st_ino == inode
    finally:
        again.close()


def test_owner_fences_retired_generation(world):
    owner = Owner(world)
    try:
        assert owner.read()[0] == "poll"
        p = world / ".fable-team/seats-planner.json"
        successor = "byz-planner-master-pi#2"
        p.write_text(json.dumps({"_master": successor, SEAT: {"role": "stop-ready", "_replaced_by": successor},
                                 successor: {"role": "master", "_replaces": [SEAT]}}))
        assert owner.tick()[:2] == ("exit", 0)
    finally:
        owner.close()


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
    owners = [Owner(world), Owner(other, seat)]
    try:
        assert all(owner.read()[0] == "poll" for owner in owners)
    finally:
        for owner in owners:
            owner.close()
