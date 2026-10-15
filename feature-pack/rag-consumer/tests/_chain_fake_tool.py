"""A fake measurement tool for the chain wrapper tests: it only does what its spec file says.

usage: _chain_fake_tool.py NAME [args...]   (spec: $CH_SPEC_DIR/NAME.json)

spec keys: rc, sleep, write [{"name", "text" | "dir"}], stdout, stderr, ignore (swallow signals), cleanup_s.
Every call appends "NAME pid args" to $CH_SPEC_DIR/calls.txt; every signal received appends its number to
$CH_SPEC_DIR/NAME.signals. Result files are written below $PROBE_BASE. No real op / launchctl / taskpolicy.
"""

import json
import os
from pathlib import Path
import signal
import sys
import time

name = sys.argv[1]
spec_dir = Path(os.environ["CH_SPEC_DIR"])
spec = json.loads((spec_dir / f"{name}.json").read_text(encoding="utf-8"))
with (spec_dir / "calls.txt").open("a") as handle:
    handle.write(f"{name} {os.getpid()} {' '.join(sys.argv[2:])}\n")


def on_signal(signum, _frame):
    with (spec_dir / f"{name}.signals").open("a") as handle:
        handle.write(f"{signum}\n")
    if spec.get("ignore"):
        return
    time.sleep(spec.get("cleanup_s", 0))
    sys.exit(128 + signum)


for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, on_signal)

if spec.get("stdout"):
    sys.stdout.write(spec["stdout"] + "\n")
if spec.get("stderr"):
    sys.stderr.write(spec["stderr"] + "\n")
sys.stdout.flush()
end = time.time() + spec.get("sleep", 0)
while time.time() < end:
    time.sleep(0.03)
base = Path(os.environ["PROBE_BASE"])
for item in spec.get("write", []):
    target = base / item["name"]
    target.parent.mkdir(parents=True, exist_ok=True)
    if item.get("dir"):
        target.mkdir(parents=True, exist_ok=True)
    else:
        target.write_text(item["text"], encoding="utf-8")
if spec.get("self_kill"):
    os.kill(os.getpid(), spec["self_kill"])
    time.sleep(5)
sys.exit(spec.get("rc", 0))
