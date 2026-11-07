"""Real haswork_gate + fire/goal, isolated actionable mailbox and send sink."""
import json
import os
import re
import subprocess

import pytest

from test_ft_seat_pi import BIN, SEAT, message, write
from test_ft_seat_pi import world as world


@pytest.mark.parametrize("fields,expected", [
    ({"stopReason": "stop"}, 1),
    ({"stopReason": "end_turn"}, 1),
    ({"stopReason": "max_tokens"}, 1),
    ({"stopReason": None}, 1),
    ({"stopReason": "toolUse"}, 0),
    ({"stopReason": "stop", "_following": "user"}, 0),
    ({"stopReason": "stop", "_following": "toolResult"}, 0),
    ({"stopReason": "stop", "_queue": True}, 0),
    ({"stopReason": "stop", "_lookup_failure": True}, 0),
    ({"stopReason": "error", "errorMessage": "503 rate_limit_error"}, 0),
    ({"stopReason": "aborted", "errorMessage": "invalid_api_key"}, 0),
    ({"stopReason": "error", "errorMessage": "503"}, 0),
    ({"stopReason": "error", "errorMessage": "timeout"}, 0),
    ({"stopReason": "aborted"}, 0),
    ({}, 0),
])
@pytest.mark.parametrize("entry", ["fire", "goal"])
def test_actual_gate_sends_only_normal_idle(world, tmp_path, fields, expected, entry):
    fields = dict(fields)
    following, queued = fields.pop("_following", None), fields.pop("_queue", False)
    lookup_failure = fields.pop("_lookup_failure", False)
    records = [message(**fields)] + ([message(following)] if following else [])
    if queued:
        records.append({"type": "queue-operation", "operation": "enqueue"})
    write(world, records)
    comm = world[2] / "comm"
    comm.mkdir()
    (comm / "mailbox.jsonl").write_text(json.dumps({"seq": 1, "from": "human", "to": SEAT, "body": "synthetic"}) + "\n", encoding="utf-8")
    source = (BIN / "ft-tick.sh").read_text(encoding="utf-8")
    block = re.search(r"^# r1450 has-work gate\n(.*?)^# end r1450 has-work gate", source, re.M | re.S)[1]
    functions = [re.search(r"^" + name + r"\(\) \{.*?^\}", source, re.M | re.S)[0] for name in ("fire", "goal")]
    setup = r'''
set -uo pipefail
HERE=$BIN; ROOT=$TEST_ROOT; WT=$ROOT; SEATS=$FT_SEATS_JSON
MBOX=$ROOT/.fable-team/comm/mbox.sh; STATE_DIR=$ROOT/state
SEAT_STATUS=$BIN/ft-seat-status.sh; DRY=0; FIRE_V2=0; GOAL_INTERVAL=0
GOAL_TICK=$ROOT/goal.sh
now(){ echo 1794013320; }; log(){ :; }; acct_paused(){ return 0; }
stamp_of(){ echo "$ROOT/stamp"; }; stamp_gap(){ echo 1000000; }
write_stamp(){ :; }; pane_of(){ echo %1; }; agent_gate(){ return 0; }
sleep(){ :; }
tmux(){
  case "$1" in
    capture-pane) printf '❯ \n';;
    send-keys) case " $* " in *' -l '*) echo fire >> "$ROOT/sent";; esac;;
  esac
}
'''
    (tmp_path / "state").mkdir()
    (tmp_path / "goal.sh").write_text('#!/bin/bash\necho goal >> "$TEST_ROOT/sent"\necho "tick sent target=synthetic rc=3 streak=1"\n', encoding="utf-8")
    command = 'fire "$SEAT" master 0 0 synthetic' if entry == "fire" else 'goal "$SEAT"'
    env = dict(os.environ, BIN=str(BIN), TEST_ROOT=str(tmp_path), SEAT=SEAT,
               FT_TICK_HASWORK_GATE="1", PYTHONDONTWRITEBYTECODE="1")
    if lookup_failure:
        env["FT_TMUX"] = "/missing/synthetic/tmux"
    result = subprocess.run(["bash"], input=setup + block + "\n" + "\n".join(functions) + "\n" + command,
                            cwd=tmp_path, env=env, capture_output=True, text=True, timeout=7)
    sent = tmp_path / "sent"
    count = len(sent.read_text().splitlines()) if sent.exists() else 0
    assert result.returncode == 0 and count == expected, (result.returncode, count, result.stdout, result.stderr)
