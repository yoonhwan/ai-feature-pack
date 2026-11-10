#!/bin/bash
# R3: execute the actual goal script; a normal goal-check changes IDLE to WORKING.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
python3 -B - "$HERE/../bin/ft-goal-tick.sh" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

started = time.monotonic()
with tempfile.TemporaryDirectory(prefix="r1450-relay-") as temp:
    root = Path(temp)
    script = root / "ft-goal-tick.sh"
    script.write_text(Path(sys.argv[1]).read_text(encoding="utf-8"), encoding="utf-8")
    (root / "ft-harness-root.sh").write_text('ft_repo_root(){ echo "$FT_GOAL_TICK_ROOT"; }\n', encoding="utf-8")
    (root / "ft-team-lib.sh").write_text('ft_team_doc_ref_only(){ echo "$FT_GOAL_TICK_ROOT/prompt.md"; }\nft_team_doc_tmp(){ return 1; }\n', encoding="utf-8")
    (root / "prompt.md").write_text('```\nfixture prompt\n```\n', encoding="utf-8")
    comm = root / ".fable-team/comm"
    comm.mkdir(parents=True)
    mbox = comm / "mbox.sh"
    mbox.write_text('#!/bin/bash\necho "$1" >> "$FT_GOAL_TICK_ROOT/relay.log"\n', encoding="utf-8")
    mbox.chmod(0o755)
    check = root / "check.sh"
    check.write_text('#!/bin/bash\ntouch "$FT_GOAL_TICK_ROOT/working"\necho REREAD-REQUIRED\nexit 3\n', encoding="utf-8")
    check.chmod(0o755)
    status = root / "status.sh"
    end = datetime.fromtimestamp(time.time() - 61, timezone.utc).isoformat()
    status.write_text('#!/bin/bash\nif [ -f "$FT_GOAL_TICK_ROOT/working" ]; then echo \'{"state":"WORKING"}\'; else echo \'' + json.dumps({"state": "IDLE", "turn_end": end}) + "'; fi\n", encoding="utf-8")
    seats = root / ".fable-team/seats-fixture.json"
    seats.write_text(json.dumps({"_master": "byz-fixture-master-claude#1"}), encoding="utf-8")
    env = dict(os.environ, FT_GOAL_TICK_ROOT=str(root), FT_ROOT=str(root), FT_SEATS_JSON=str(seats),
               FT_GOAL_TICK_TARGET="byz-fixture-master-claude#1", FT_GOAL_TICK_CHECK=str(check),
               FT_GOAL_TICK_STREAK=str(root / "streak"), FT_TICK_SEAT_STATUS=str(status),
               FT_TICK_HASWORK_GATE="1", PYTHONDONTWRITEBYTECODE="1")
    command = 'tmux(){ return 0; }; mktemp(){ command mktemp "$FT_GOAL_TICK_ROOT/goal.XXXXXX"; }; export -f tmux mktemp; exec bash "$1"'
    run = subprocess.run(["bash", "-c", command, "bash", str(script)], cwd=root, env=env,
                         capture_output=True, text=True, timeout=7)
    relays = len((root / "relay.log").read_text().splitlines()) if (root / "relay.log").exists() else 0
    good = run.returncode == 0 and relays == 0 and (root / "working").exists()
    print(f'{"PASS" if good else "FAIL"} R3-actual-goal-recheck rc={run.returncode} relays={relays} expected=0 seconds={time.monotonic()-started:.3f}')
    print(run.stdout + run.stderr, end="")
    sys.exit(not good)
PY
