#!/bin/bash
# r1450: real fire/goal functions, isolated mailbox/state, no live pane or mail.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
python3 -B - "$HERE/../bin/ft-tick.sh" "${1:-}" <<'PY'
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

source = Path(sys.argv[1]).resolve()
text = Path(os.environ.get("FT_TEST_R1450_BODY", source)).read_text(encoding="utf-8")
functions = []
block = re.search(r"^# r1450 has-work gate\n(.*?)^# end r1450 has-work gate", text, re.M | re.S)
if block:
    functions.append(block[1])
for name in ("fire", "goal"):
    functions.append(re.search(r"^" + name + r"\(\) \{.*?^\}", text, re.M | re.S)[0])
setup = r'''
set -uo pipefail
HERE=$BIN; ROOT=$TEST_ROOT; WT=$ROOT; SEATS=$ROOT/.fable-team/seats-fixture.json
MBOX=$ROOT/.fable-team/comm/mbox.sh; STATE_DIR=$ROOT/state; DRY=0
SEAT_STATUS=$ROOT/status.sh; FIRE_V2=0; GOAL_INTERVAL=0; GOAL_TICK=$ROOT/goal.sh
now(){ echo 1794000000; }; log(){ :; }; acct_paused(){ return 0; }
stamp_of(){ echo "$ROOT/$1.$2.stamp"; }; stamp_gap(){ echo 1000000; }
write_stamp(){ :; }; pane_of(){ echo %1; }; agent_gate(){ return 0; }
sleep(){ :; }
tmux(){
  case "$1" in
    capture-pane) printf '❯ \n';;
    send-keys) case " $* " in *' -l '*) echo fire >> "$ROOT/sent";; esac;;
  esac
}
'''
started = time.monotonic()
failed = 0
cases = [("a-no-work", None, 60, 0), ("b-recent", "human", 59, 0),
         ("c-ready", "human", 60, 1), ("d-tool-only", "ft-tick", 60, 0),
         ("default-off", None, 60, 1), ("dedup", "human", 60, 1),
         ("working", "human", 60, 0), ("unknown", "human", 60, 0),
         ("missing-end", "human", 60, 0), ("recheck-working", "human", 60, 0),
         ("inbox-open", None, 60, 0), ("card-assigned", None, 60, 1),
         ("master-unassigned", None, 60, 0), ("card-waiting", None, 60, 0),
         ("card-ledger-only", None, 60, 1), ("card-old-seat", None, 60, 0),
         ("mailbox-reference", "human", 60, 1), ("goal-quiet-then-fire", "human", 60, 1)]
if sys.argv[2] == "--team":
    cases = []
if sys.argv[2] == "--amendments":
    cases = [c for c in cases if c[0] in ("inbox-open", "master-unassigned", "card-ledger-only")]
for label, sender, age, expected in cases:
    for entry in ("fire", "goal"):
        begin = time.monotonic()
        with tempfile.TemporaryDirectory(prefix="r1450-") as temp:
            root = Path(temp)
            comm = root / ".fable-team/comm"
            comm.mkdir(parents=True)
            (root / "cards/대기").mkdir(parents=True)
            (root / "state").mkdir()
            seat = "byz-fixture-master-claude#1"
            roster = {"_master": seat, "_cards": str(root / "cards"),
                      seat: {"role": "master", "_replaces": []}}
            (root / ".fable-team/seats-fixture.json").write_text(json.dumps(roster), encoding="utf-8")
            rows = [] if sender is None else [{"seq": 1, "from": sender, "to": seat, "body": "[작업] 구현 확인"}]
            if label == "mailbox-reference":
                rows[0]["body"] = "참고: 검토 결과 공유. 실행 요청 없음"
            (comm / "mailbox.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
            status = {"state": "IDLE", "turn_end": time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(1794000000 - age))}
            if label in ("working", "unknown"):
                status["state"] = label.upper()
            if label == "missing-end":
                status["turn_end"] = None
            status_script = "#!/bin/bash\nprintf '%s\\n' '" + json.dumps(status) + "'\n"
            if label == "recheck-working":
                status_script = '#!/bin/bash\nif [ -f "$TEST_ROOT/status-read" ]; then echo \'{"state":"WORKING"}\'; else touch "$TEST_ROOT/status-read"; echo \'' + json.dumps(status) + "'; fi\n"
            (root / "status.sh").write_text(status_script, encoding="utf-8")
            goal_script = '#!/bin/bash\necho goal >> "$TEST_ROOT/sent"\necho "tick sent target=$FT_GOAL_TICK_TARGET rc=3 streak=1"\n'
            if label == "goal-quiet-then-fire":
                goal_script = '#!/bin/bash\necho "tick quiet target=$FT_GOAL_TICK_TARGET rc=0 streak=0"\n'
            (root / "goal.sh").write_text(goal_script, encoding="utf-8")
            if label == "inbox-open":
                inbox = root / ".fable-team/state/inbox"
                inbox.mkdir(parents=True)
                row = {"seq": 2, "from": "human", "cls": "미상", "mark": None,
                       "reported": False, "body_path": str(root / "body.txt")}
                (root / "body.txt").write_text("[작업] 아직 미완료", encoding="utf-8")
                (inbox / "byz-fixture-master-claude.jsonl").write_text(json.dumps(row) + "\n", encoding="utf-8")
            if label.startswith("card-") or label == "master-unassigned":
                if label != "card-ledger-only":
                    (root / "cards/대기/work.md").write_text("# 실행할 카드\n- 선행: A 카드 완성\n- 시기: A 카드 완성 후\n", encoding="utf-8")
                ledger = root / ".fable-team/state/card-assign"
                ledger.mkdir(parents=True)
                row = {"state": "waiting", "reason": "사람"} if label == "card-waiting" else {"state": "seat", "seat": seat, "updated": 1}
                if label == "card-old-seat":
                    row["seat"] = "byz-fixture-master-claude#0"
                if label != "master-unassigned":
                    (ledger / "work.json").write_text(json.dumps(row), encoding="utf-8")
            command = 'fire "$SEAT" master 0 0 fixture' if entry == "fire" else 'goal "$SEAT"'
            if label == "dedup":
                command += "\n" + command
            if label == "goal-quiet-then-fire":
                command = 'goal "$SEAT"\nfire "$SEAT" master 0 0 fixture'
            env = dict(os.environ, TEST_ROOT=str(root), BIN=str(source.parent), SEAT=seat,
                       FT_ROOT=str(root), FT_TICK_HASWORK_GATE="1", PYTHONDONTWRITEBYTECODE="1")
            if label == "default-off":
                env.pop("FT_TICK_HASWORK_GATE")
            run = subprocess.run(["bash"], input=setup + "\n".join(functions) + "\n" + command + "\n",
                                 env=env, capture_output=True, text=True, timeout=7)
            sent = len((root / "sent").read_text().splitlines()) if (root / "sent").exists() else 0
            good = run.returncode == 0 and sent == expected
            failed += not good
            print(f'{"PASS" if good else "FAIL"} {label}/{entry} rc={run.returncode} sends={sent} expected={expected} seconds={time.monotonic()-begin:.3f}')
            if not good:
                print(run.stdout + run.stderr)
print(f"PHASE fixtures seconds={time.monotonic()-started:.3f} failures={failed}")
if sys.argv[2] == "--amendments":
    sys.exit(bool(failed))
with tempfile.TemporaryDirectory(prefix="r1450-team-") as temp:
    begin = time.monotonic()
    root = Path(temp)
    comm = root / ".fable-team/comm"
    comm.mkdir(parents=True)
    (root / "cards").mkdir()
    (root / "state").mkdir()
    fake = root / "fakebin"
    fake.mkdir()
    for name in ("tmux", "pgrep", "tmm"):
        p = fake / name
        p.write_text('#!/bin/bash\nexit 0\n', encoding="utf-8")
        p.chmod(0o755)
    seat = "byz-fixture-master-claude#1"
    roster = {"_master": seat, "_cards": str(root / "cards"), seat: {"role": "master", "tick": "ft-master-tick", "_replaces": []}}
    seats = root / ".fable-team/seats-fixture.json"
    seats.write_text(json.dumps(roster), encoding="utf-8")
    mail = {"seq": 1, "from": "human", "to": seat, "body": "[작업] fixture"}
    (comm / "mailbox.jsonl").write_text(json.dumps(mail) + "\n", encoding="utf-8")
    (comm / "mbox.sh").write_text('#!/bin/bash\nexit 0\n', encoding="utf-8")
    status = {"state": "IDLE", "turn_end": time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(1794000000 - 60))}
    (root / "status.sh").write_text("#!/bin/bash\necho '" + json.dumps(status) + "'\n", encoding="utf-8")
    env = dict(os.environ, FT_ROOT=str(root), FT_TICK_SEATS=str(seats),
               FT_TICK_MBOX=str(comm / "mbox.sh"), FT_TICK_STATE_DIR=str(root / "state"),
               FT_TICK_STAMP_PREFIX=str(root / "stamp-"), FT_TICK_PIDFILE=str(root / "pid"),
               FT_TICK_PATH_FIRST=str(fake), FT_TICK_SEAT_STATUS=str(root / "status.sh"),
               FT_TICK_NOW_BASE="1794000000", FT_TICK_TEAM="fixture", FT_MODEL_SWAP="0",
               FT_TICK_TEAMMAIN_SEC="0", PYTHONDONTWRITEBYTECODE="1")
    env.update({name: "0" for name in re.findall(r'\$\{(FT_TICK_[A-Z_]+):-1\}', text)})
    env["FT_TICK_HASWORK_GATE"] = "1"
    run = subprocess.run(["bash", str(source), "--once", "--dry-run"], cwd=root, env=env,
                         capture_output=True, text=True, timeout=7)
    good = run.returncode == 0 and f"DRY seat={seat} kind=master " in run.stdout
    failed += not good
    print(f'{"PASS" if good else "FAIL"} team-dry-run rc={run.returncode} seconds={time.monotonic()-begin:.3f}')
    print(run.stdout + run.stderr)
sys.exit(bool(failed))
PY
