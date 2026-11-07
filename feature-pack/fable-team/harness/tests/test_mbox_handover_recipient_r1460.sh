#!/usr/bin/env bash
# r1460: isolate recipient selection through real ready-body/close-check CLI.
# Synthetic comm/log/roster/receipts only; no ready/send/recv/retire or tmux.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
python3 -B - "$HERE/../comm" <<'PY'
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SOURCE = Path(sys.argv[1]).resolve()
OLD = "byz-feature-master-claude#78"
NEW = "byz-feature-master-claude#79"
THIRD = "byz-knowledge-master-claude#92"


def handover(seq, recipient):
    body = f"[인계] {OLD} -> {recipient} · 항목 1 · 합성 fixture\n- #1 합성 작업"
    return {"seq": seq, "from": OLD, "to": recipient, "body": body, "ts": "2026-11-07T00:00:00"}


def ready(seq, handover_seq):
    return {"seq": seq, "from": NEW, "to": OLD,
            "body": f"[레디] {NEW} <- {OLD} · [인계] #{handover_seq} 받음 · 항목 1\n#1 받음"}


def write_rows(path, rows):
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def fixture(root, case):
    comm = root / ".fable-team/comm"
    shutil.copytree(SOURCE, comm)
    (comm / "receipts").mkdir()
    roster = {"_master": NEW, OLD: {"role": "stop-ready", "_replaced_by": NEW},
              NEW: {"role": "master", "_replaces": [OLD]}, THIRD: {"role": "master"}}
    seats = root / ".fable-team/seats-feature.json"
    seats.write_text(json.dumps(roster), encoding="utf-8")
    rotated, rows, received = [], [], []
    if case == 1:
        rows, received = [handover(10, NEW), ready(11, 10)], [handover(10, NEW)]
    elif case == 2:
        rows = [handover(20, THIRD)]
    else:
        rotated = [handover(10, NEW)]
        rows, received = [handover(30, NEW), handover(40, THIRD), ready(50, 30)], [handover(30, NEW)]
    write_rows(comm / "mailbox.log.jsonl.1", rotated)
    write_rows(comm / "mailbox.log.jsonl", rows)
    write_rows(comm / "mailbox.jsonl", [])
    write_rows(comm / "receipts" / (NEW + ".jsonl"), received)
    env = dict(os.environ, FT_ROOT=str(root), FT_MBOX_DIR=str(comm), FT_SEATS_JSON=str(seats),
               PYTHONDONTWRITEBYTECODE="1", LC_ALL="C")
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
        env.pop(key, None)
    return comm, env


def check(comm, env, case, command):
    args = ["ready-body", NEW, OLD] if command == "ready-body" else ["close-check", OLD]
    started = time.monotonic()
    result = subprocess.run([sys.executable, "-B", str(comm / "mbox.py"), *args], cwd=comm.parent.parent,
                            env=env, capture_output=True, text=True, timeout=7)
    print(f"CASE {case} {command} rc={result.returncode} seconds={time.monotonic()-started:.3f}")
    print("stdout: " + result.stdout.rstrip())
    print("stderr: " + result.stderr.rstrip())
    if case == 2:
        missing = (f"REJECT {OLD} 의 [인계] 없음 — 구세션이 bash mbox.sh handover {OLD} {NEW} 먼저\n"
                   if command == "ready-body" else f"REJECT {OLD} [인계] 없음 — bash mbox.sh handover {OLD} {NEW}\n")
        actual = result.stderr if command == "ready-body" else result.stdout
        return result.returncode == 3 and actual == missing
    selected, response = (10, 11) if case == 1 else (30, 50)
    expected = (f"[레디] {NEW} <- {OLD} · [인계] #{selected} 받음 · 항목 1\n#1 받음\n"
                if command == "ready-body" else f"CLOSE-OK {OLD} [인계] #{selected} → [레디] #{response} 항목 1 전부 받음\n")
    return result.returncode == 0 and result.stdout == expected


started, failures = time.monotonic(), 0
for case in (1, 2, 3):
    with tempfile.TemporaryDirectory(prefix=f"mbox-r1460-case{case}-") as temporary:
        comm, env = fixture(Path(temporary), case)
        for command in ("ready-body", "close-check"):
            passed = check(comm, env, case, command)
            failures += not passed
            print(f'{"PASS" if passed else "FAIL"} case={case} command={command}')
print(f"PHASE recipient seconds={time.monotonic()-started:.3f} failures={failures}")
raise SystemExit(bool(failures))
PY
