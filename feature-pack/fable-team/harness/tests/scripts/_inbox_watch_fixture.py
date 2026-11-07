"""Temporary inbox-watch fixture/child control; never a product import path."""
import io
import json
import multiprocessing as mp
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

PACK = Path(__file__).resolve().parents[3]
BIN = PACK / "harness/bin"
SEAT = "byz-planner-master-claude#1"


def child(pipe, root, seat, barrier, comm, epoch):
    import time
    os.environ.update(FT_ROOT=str(root), FT_MBOX_DIR=str(comm or root / ".fable-team/comm"), LC_ALL="C")
    os.environ["FT_SEATS_JSON"] = str(root / ".fable-team/seats-planner.json")
    out, err = io.StringIO(), io.StringIO()
    sys.stdout, sys.stderr, sys.argv = out, err, ["-", str(BIN), seat]
    sys.dont_write_bytecode = True
    def poll(_):
        pipe.send(("poll", out.getvalue(), err.getvalue(), time.time()))
        command = pipe.recv()
        if command == "broken":
            sys.stdout = io.TextIOBase()
        if command == "advance240":
            time.time = lambda: 480.0
        if command == "stop":
            raise EOFError
    time.sleep, time.time = poll, lambda: float(epoch)
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
        if not isinstance(rc, int):
            print(str(rc), file=err)
            rc = 1
    except Exception as error:
        rc = 2
        print(type(error).__name__ + ": " + str(error), file=err)
    pipe.send(("exit", rc, out.getvalue(), err.getvalue()))


class Owner:
    def __init__(self, root, seat=SEAT, barrier=None, comm=None, epoch=240):
        self.pipe, other = mp.Pipe()
        self.process = mp.get_context("fork").Process(target=child, args=(other, root, seat, barrier, comm, epoch))
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


def queue(root, seqs, seat=SEAT):
    """Write synthetic seqs, or atomically rewrite current records for seqs=None."""
    path = root / ".fable-team/comm/mailbox.jsonl"
    rows = [{"seq": n, "to": seat, "from": "source" + str(n),
             "body": "[HIL] " + "x" * 80 + "\nsecond line"} for n in (seqs or [])]
    if seqs is None:
        rows = [json.loads(line) for line in path.read_text().splitlines()]
    write(path.with_suffix(".tmp"), rows)
    path.with_suffix(".tmp").replace(path)


def receive(root, sender, seat=SEAT):
    comm = root / ".fable-team/comm"
    env = dict(os.environ, FT_ROOT=str(root), FT_MBOX_DIR=str(comm), FT_SEATS_JSON=str(comm.parent / "seats-planner.json"))
    return subprocess.run([sys.executable, "-B", str(comm / "mbox.py"), "recv", seat, sender, "--all"], env=env,
                          capture_output=True, text=True, timeout=7)


def alarm_env(root, entry, mode="absent", baseline=False, fake_doorbell=False):
    ft = root / ".fable-team"
    bindir = ft / "bin"
    shutil.copytree(PACK / "harness/kit/fable-team/bin", bindir)
    script = ft / "comm/mbox.sh" if entry == "comm" else bindir / "ft-mbox.sh"
    if baseline:
        rel = "feature-pack/fable-team/harness/" + ("comm/mbox.sh" if entry == "comm" else "kit/fable-team/bin/ft-mbox.sh")
        result = subprocess.run(["git", "-C", str(PACK), "show", "beff70e8:" + rel], capture_output=True, timeout=7)
        assert result.returncode == 0
        script.write_bytes(result.stdout)
    (ft / "seats-harness.json").write_text(json.dumps({"_master": "byz-harness-master-claude#1"}))
    fake = bindir / "fake-pgrep"
    fake.write_text('#!/bin/sh\n[ "$FT_FIX_WATCH" = unknown ] && exit 2\n[ "$FT_FIX_WATCH" = alive ] && echo "999 /opt/Python -u - $FT_BIN '+SEAT+'"\nexit 0\n')
    fake.chmod(0o755)
    env = dict(os.environ, FT_ROOT=str(root), FT_MBOX_DIR=str(ft / "comm"), FT_BIN=str(bindir),
               FT_SEATS_JSON=str(ft / "seats-planner.json"), FT_PGREP=str(fake), FT_FIX_WATCH=mode,
               FT_MBOX_RATE_N="999", FT_MBOX_FANOUT_WINDOW="0", FT_MBOX_RELAY_DIR=str(root / "relay"),
               FT_NAME_LINT=str(bindir / "ft-name-lint.sh"), LC_ALL="C", TMPDIR=str(root), PYTHONDONTWRITEBYTECODE="1")
    env.update(FT_ROOTS_TSV=str(root / "roots.tsv"), FT_MBOX_LEGACY="0")
    if fake_doorbell:
        fake_tmux = root.parent / "guard/tmux"
        fake_tmux.write_text('#!/bin/sh\necho FAKE_TMUX >> "'+str(root / "fake-tmux.log")+'"\nexit 0\n')
    for key in ("TMUX", "TMUX_PANE", "FT_PLANNER_HEAD_MODE", "FT_SEAT"):
        env.pop(key, None)
    if mode == "unknown" and entry == "comm":
        env["FT_BIN"] = str(root / "missing-bin")
    if mode == "enqueue_failure":
        target = ft / "comm/mbox.py" if entry == "comm" else bindir / "ft-mbox.py"
        actual = target.with_name("actual-" + target.name)
        target.rename(actual)
        target.write_text('import runpy,sys\nif len(sys.argv)>3 and sys.argv[3]=="ft-watch-alarm": sys.exit(7)\nrunpy.run_path('+repr(str(actual))+',run_name="__main__")\n')
    return script, env


def mail(root, script, env, command="send", sender="source1", seat=SEAT):
    args = ["bash", str(script), command, seat, sender]
    if command == "relay":
        body = root / "body.txt"
        body.write_text("[HIL] synthetic original body\n")
        args.append(str(body))
    return subprocess.run([*args, "[HIL] synthetic " + sender + "x" * 80], env=env, cwd=root,
                          capture_output=True, text=True, timeout=7)


def cutover_ready(evidence):
    return all(evidence.get(key) is True for key in ("owner", "recovery", "driver", "receipt"))
