#!/bin/bash
# No cleanup simulation: dispatch barriers and cursor scheduling with a fake tool.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
python3 -B - "$HERE/../bin" <<'PY'
import ast
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

bin_dir = Path(sys.argv[1]).resolve()
started = time.monotonic()
source = (bin_dir / "ft-tick.sh").read_text(encoding="utf-8")
function = re.search(r"^inbox_tidy\(\) \{.*?^\}", source, re.M | re.S)[0]
stamp = re.search(r"^write_stamp\(\) \{.*?^\}", source, re.M | re.S)[0]
save = re.search(r"^inbox_tidy_save\(\) \{.*?^\}", source, re.M | re.S)
function = (save[0] + "\n" if save else "") + function
for name in ("ft-inbox.py", "ft_inbox_rotate.py"):
    ast.parse((bin_dir / name).read_text(encoding="utf-8"))
with tempfile.TemporaryDirectory(prefix="r1450-tidy-off-") as temp:
    root = Path(temp)
    setup = 'now(){ echo unexpected >> "$ROOT/calls"; }; timeout(){ echo unexpected >> "$ROOT/calls"; }; python3(){ echo unexpected >> "$ROOT/calls"; };\n'
    for label, flag, dry in [("default-off", None, "0"), ("dry-run", "1", "1")]:
        env = dict(os.environ, ROOT=str(root), STATE_DIR=str(root / "state"), DRY=dry)
        env.pop("FT_TICK_INBOX_TIDY", None)
        if flag is not None:
            env["FT_TICK_INBOX_TIDY"] = flag
        run = subprocess.run(["bash"], input=setup + function + "\ninbox_tidy\n", env=env,
                             capture_output=True, text=True, timeout=7)
        good = run.returncode == 0 and not (root / "calls").exists() and not (root / ".fable-team/state/inbox-tidy-cursor.json").exists()
        print(f'{"PASS" if good else "FAIL"} inbox-tidy/{label} rc={run.returncode} tool_calls={int((root / "calls").exists())}')
        print(run.stdout + run.stderr, end="")
        if not good:
            sys.exit(1)
with tempfile.TemporaryDirectory(prefix="r1450-tidy-cursor-") as temp:
    root = Path(temp)
    seats = [f"byz-fixture-nano-claude#{i}" for i in range(1, 4)]
    roster = root / "seats-fixture.json"
    roster.write_text(json.dumps({s: {"role": "nano"} for s in seats}), encoding="utf-8")
    (root / "clock").write_text("1794000000", encoding="utf-8")
    setup = r'''
set -uo pipefail
now(){ cat "$ROOT/clock"; }
log(){ printf '%s\n' "$*"; }
python3(){
  command python3 "$@" || return $?
  if [ "$1" = - ] && [ "${2:-}" = "$SEATS" ]; then
    value=$(cat "$ROOT/clock"); printf '%s\n' "$((value + 20))" > "$ROOT/clock"
  fi
}
timeout(){
  shift
  printf '%s\n' "$4" >> "$ROOT/attempts"
  value=$(cat "$ROOT/clock"); printf '%s\n' "$((value + 5))" > "$ROOT/clock"
  echo 'WAIVED 2 seq=101,102'
}
'''
    env = dict(os.environ, ROOT=str(root), SEATS=str(roster), STATE_DIR=str(root / "state"),
               HERE=str(bin_dir), DRY="0", FT_TICK_INBOX_TIDY="1", FT_TICK_INBOX_TIDY_REASON="판정 1 scheduling fixture")
    audited_stamp = stamp.replace("write_stamp()", "real_write_stamp()", 1) + '\nwrite_stamp(){ real_write_stamp "$@" || return $?; printf \'%s\\n\' "$2" >> "$ROOT/cursor-writes.jsonl"; }\n'
    command = setup + audited_stamp + "\n" + function + "\ninbox_tidy\n"
    first = subprocess.run(["bash"], input=command, env=env, capture_output=True, text=True, timeout=7)
    cursor = root / ".fable-team/state/inbox-tidy-cursor.json"
    saved = json.loads(cursor.read_text(encoding="utf-8")) if cursor.exists() else {}
    run = subprocess.run(["bash"], input=command, env=env, capture_output=True, text=True, timeout=7)
    attempts = (root / "attempts").read_text(encoding="utf-8").splitlines()
    writes = [json.loads(line) for line in (root / "cursor-writes.jsonl").read_text(encoding="utf-8").splitlines() if line.startswith("{")]
    good = (first.returncode == run.returncode == 0 and attempts == seats[:2]
            and saved == {"seat": seats[1], "last_seq": 0, "ts": 1794000025}
            and any(x.get("seat") == seats[0] and x.get("last_seq") == 102 for x in writes))
    print(f'{"PASS" if good else "FAIL"} R4-json-next-round rc={run.returncode} attempts={attempts} expected={seats[:2]} saved={saved}')
    print(first.stdout + first.stderr + run.stdout + run.stderr, end="")
    if not good:
        sys.exit(1)
    cursor.write_text(json.dumps({"seat": "removed-seat#99", "last_seq": 0, "ts": 1794000050}) + "\n", encoding="utf-8")
    (root / "attempts").write_text("", encoding="utf-8")
    run = subprocess.run(["bash"], input=command, env=env, capture_output=True, text=True, timeout=7)
    attempts = (root / "attempts").read_text(encoding="utf-8").splitlines()
    good = run.returncode == 0 and attempts[:1] == seats[:1]
    print(f'{"PASS" if good else "FAIL"} R4-removed-cursor rc={run.returncode} first={attempts[:1]} expected={seats[:1]}')
    if not good:
        print(run.stdout + run.stderr, end="")
        sys.exit(1)
print(f"PHASE tidy-default seconds={time.monotonic()-started:.3f}; cleanup execution=0; candidate simulation=0")
PY
