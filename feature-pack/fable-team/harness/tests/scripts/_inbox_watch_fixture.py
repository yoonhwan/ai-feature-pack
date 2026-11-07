"""Temporary inbox-watch fixture/child control; never a product import path."""
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
