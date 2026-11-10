#!/bin/bash
# r1452: actual lifecycle functions, isolated rosters and fake external tools only.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
python3 -B - "$HERE/../bin/ft-tick.sh" <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

source = Path(sys.argv[1]).resolve()
text = source.read_text(encoding="utf-8")
parts = []
for name in ("write_stamp", "read_stamp", "actionable"):
    parts.append(re.search(r"^" + name + r"\(\) \{.*?^\}", text, re.M | re.S)[0])
block = re.search(r"^# r1452 idle-team lifecycle\n(.*?)^# end r1452 idle-team lifecycle", text, re.M | re.S)
if block:
    parts.append(block[1])
setup = r'''
set -uo pipefail
HERE=$BIN; WT=$ROOT; SEATS=$ROOT/.fable-team/seats.json; DRY=0
STATE_DIR=$ROOT/state; MBOX=$ROOT/.fable-team/comm/mbox.sh; SEAT_STATUS=$ROOT/status.sh
ZC_BIN=$ROOT/resume.sh; FT_TICK_IDLE_TEAM_CLOSE_BIN=$ROOT/close.sh
now(){ cat "$ROOT/clock"; }; log(){ printf '%s\n' "$*"; }
team_master_seat(){ cat "$ROOT/harness-master"; }
master_seat(){ python3 -c 'import json,os;print(json.load(open(os.environ["ROOT"]+"/.fable-team/seats.json"))["_master"])'; }
'''
started = time.monotonic()
failures = 0
names = ["byz-fixture-master-claude#1", "byz-fixture-nano-claude#1", "byz-fixture-nano-claude#2"]
protected = ["byz-root-master-claude#1", "byz-harness-master-codex#1"]
for label in ("zero-duration", "root-owner", "harness-owner", "child-work-seen", "child-working", "hil", "human-wait", "prerequisite", "preserve", "old-stop-ready", "reopen", "reopen-dormant", "reopen-card", "reopen-hil", "reopen-hil-only", "reopen-no-ready", "reopen-read-none", "reopen-ready-split", "default-off"):
    if os.environ.get("FT_TEST_IDLE_CASE") and label not in os.environ["FT_TEST_IDLE_CASE"].split(","):
        continue
    begin = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="r1452-") as temp:
        root = Path(temp)
        comm = root / ".fable-team/comm"
        comm.mkdir(parents=True)
        (root / "state").mkdir()
        (root / "clock").write_text("1794000000", encoding="utf-8")
        (root / "harness-master").write_text(protected[1], encoding="utf-8")
        (root / ".fable-team/seats.json").write_text(json.dumps({"_master": protected[0], protected[0]: {"role": "master"}}), encoding="utf-8")
        (root / ".fable-team/seats-harness.json").write_text(json.dumps({"_master": protected[1], protected[1]: {"role": "master"}}), encoding="utf-8")
        members = list(names)
        if label == "root-owner": members[0] = protected[0]
        if label == "harness-owner": members[0] = protected[1]
        roster = {"_master": members[0], "_cards": "cards", **{n: {"role": "master" if i == 0 else "nano", "_replaces": []} for i, n in enumerate(members)}}
        old = "byz-fixture-nano-claude#0"
        roster[old] = {"role": "stop-ready", "_closed": {"reason": "unrelated old seat"}}
        active_roster = json.loads(json.dumps(roster))
        turns = {n: {"state": "IDLE", "turn_end": "2026-11-06T00:00:00+00:00"} for n in members}
        rows = []
        if label == "child-work-seen":
            rows = [{"seq": 42, "from": "human", "to": members[1], "body": "[발주] work"}]
            (root / "state/haswork").mkdir()
            (root / ("state/haswork/" + members[1] + ".seen")).write_text("seq:42\n", encoding="utf-8")
        if label == "child-working": turns[members[1]] = {"state": "WORKING"}
        if label == "hil":
            (root / "hil").mkdir()
            (root / "hil/h1").write_text("# ft-hil-entry plan=/fixture/pending.sh\n", encoding="utf-8")
            (root / "hil/h1.notify").write_text("seat=" + members[1] + "\n", encoding="utf-8")
        if label == "old-stop-ready": rows = [{"seq": 42, "from": "human", "to": old, "body": "[발주] unrelated old seat"}]
        if label in ("human-wait", "prerequisite"):
            cards = root / "cards/대기"
            cards.mkdir(parents=True)
            (cards / "wait.md").write_text("# waiting\n", encoding="utf-8")
            records = root / ".fable-team/state/card-assign"
            records.mkdir(parents=True)
            (records / "wait.json").write_text(json.dumps({"state": "waiting", "reason": "사람" if label == "human-wait" else "선행"}), encoding="utf-8")
        request = "card:request" if label == "reopen-card" else "hil:h1" if label == "reopen-hil-only" else 42
        if label.startswith("reopen"):
            for n in members: roster[n].update(role="stop-ready", _closed={"reason": "fixture"}, _closed_role="master" if n == members[0] else "nano")
            rows = [{"seq": 42, "from": "ft-hil-h1" if label == "reopen-hil" else "human", "to": members[0], "body": "[HIL] reopen" if label == "reopen-hil" else "[발주] reopen"}]
            if label == "reopen-card":
                rows = []
                records = root / ".fable-team/state/card-assign"
                records.mkdir(parents=True)
                (records / "request.json").write_text(json.dumps({"state": "seat", "seat": members[0]}), encoding="utf-8")
            if label == "reopen-hil-only":
                rows = []
                (root / "hil").mkdir()
                (root / "hil/h1").write_text("# ft-hil-entry plan=/fixture/pending.sh\n", encoding="utf-8")
                (root / "hil/h1.notify").write_text("seat=" + members[0] + "\n", encoding="utf-8")
        seats = root / ".fable-team/seats-fixture.json"
        seats.write_text(json.dumps(roster), encoding="utf-8")
        (comm / "mailbox.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
        (root / "active.json").write_text(json.dumps(active_roster), encoding="utf-8")
        (root / "empty").write_text("", encoding="utf-8")
        (root / "turns.json").write_text(json.dumps(turns), encoding="utf-8")
        (root / "status.sh").write_text('#!/bin/bash\npython3 -c \'import json,os,sys;print(json.dumps(json.load(open(os.environ["ROOT"]+"/turns.json"))[sys.argv[1]]))\' "$2"\n', encoding="utf-8")
        (comm / "mbox.sh").write_text('''#!/bin/bash
echo "$1:$2:${3:-}" >> "$ROOT/events"
python3 - "$@" <<'MODEL'
import json,os,sys
from pathlib import Path
r=Path(os.environ['ROOT']);comm=r/'.fable-team/comm';cmd,to,frm=sys.argv[1:4]
sys.path.insert(0,str(Path(os.environ['BIN']).parent/'comm'))
import mbox_handover
mbox_handover.CANON=str(comm)
queue=comm/'mailbox.jsonl';rows=[json.loads(x) for x in queue.read_text().splitlines() if x.strip()]
if cmd=='handover':
    body='[인계] idle-team request='+os.environ['REQUEST']
    rows=[x for x in rows if x.get('to')!=to]+[{'seq':100,'from':to,'to':frm,'body':body}]
    queue.write_text(''.join(json.dumps(x)+'\\n' for x in rows));print('QUEUED seq=100')
elif cmd=='recv':
    if os.environ.get('MODEL_ACTOR')!='1':
        print('background recv forbidden');raise SystemExit(3)
    if os.environ['RECV_NONE']=='1': print('READ none');raise SystemExit
    got=[x for x in rows if x.get('to')==to and x.get('from')==frm]
    if (r/'ready').exists() and not (r/('consumed-'+frm)).exists():
        if os.environ['READY_SPLIT']=='1' and frm==os.environ['DELAY_SEAT'] and not (r/'delayed').exists():
            (r/'delayed').touch();raise SystemExit
        ready=next((x for x in (r/'ready').read_text().splitlines() if x.split()[1]==frm),None)
        if ready:
            count=r/'model-seq';seq=int(count.read_text())+1 if count.exists() else 201;count.write_text(str(seq))
            got.append({'seq':seq,'from':frm,'to':to,'body':ready});(r/('consumed-'+frm)).touch()
    mbox_handover.record(to,got)
    ids={x['seq'] for x in got};queue.write_text(''.join(json.dumps(x)+'\\n' for x in rows if x['seq'] not in ids))
    for x in got:print('READ [%s->%s] #%s'%(frm,to,x['seq']))
MODEL
''', encoding="utf-8")
        (root / "resume.sh").write_text('#!/bin/bash\necho "resume:$2" >> "$ROOT/events"\n', encoding="utf-8")
        (root / "close.sh").write_text('#!/bin/bash\necho "restore:$2" >> "$ROOT/events"\ntmux(){ return 0; }; export -f tmux\nbash "$BIN/ft-seat-close.sh" "$@" || exit $?\n[ "$NO_READY" = 1 ] || printf "[레디] %s request_seq=%s\\n" "$2" "$REQUEST" >> "$ROOT/ready"\n', encoding="utf-8")
        (root / "preserved").mkdir()
        for name in ("conversation.jsonl", "baton", "resume", "uncommitted", "unpushed", "shared", "indices", "ledger", "HIL", "branch"):
            (root / "preserved" / name).write_text(name, encoding="utf-8")
        before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (root / "preserved").iterdir()}
        command = 'idle_team_watch\nprintf 1794003600 > "$ROOT/clock"\nidle_team_watch\n'
        if label == "zero-duration":
            command = 'idle_team_watch\nprintf 1794003599 > "$ROOT/clock"\nidle_team_watch\ncp "$STATE_DIR/idle-teams/fixture.json" "$ROOT/before.json"\nprintf 1794003600 > "$ROOT/clock"\nidle_team_watch\n'
        if label.startswith("reopen"):
            command = 'cp "$ROOT/.fable-team/seats-fixture.json" "$ROOT/closed.json"\ncp "$ROOT/active.json" "$ROOT/.fable-team/seats-fixture.json"\ncp "$ROOT/.fable-team/comm/mailbox.jsonl" "$ROOT/pending"\ncp "$ROOT/empty" "$ROOT/.fable-team/comm/mailbox.jsonl"\n[ ! -d "$ROOT/hil" ] || mv "$ROOT/hil" "$ROOT/hil-held"\n[ ! -d "$ROOT/.fable-team/state/card-assign" ] || mv "$ROOT/.fable-team/state/card-assign" "$ROOT/cards-held"\nidle_team_watch\nprintf 1794003600 > "$ROOT/clock"\nidle_team_watch\ncp "$ROOT/closed.json" "$ROOT/.fable-team/seats-fixture.json"\ncp "$ROOT/pending" "$ROOT/.fable-team/comm/mailbox.jsonl"\n[ ! -d "$ROOT/hil-held" ] || mv "$ROOT/hil-held" "$ROOT/hil"\n[ ! -d "$ROOT/cards-held" ] || mv "$ROOT/cards-held" "$ROOT/.fable-team/state/card-assign"\nidle_team_watch\nMODEL_ACTOR=1 bash "$MBOX" recv "$HARNESS" "$SEAT"\nFT_TICK_IDLE_TEAM_REOPEN=1 idle_team_reopen "$ROOT/.fable-team/seats-fixture.json" "$SEAT" "$REQUEST"\nif [ "$NO_READY" = 0 ]; then for person in $MEMBERS; do MODEL_ACTOR=1 bash "$MBOX" recv "$HARNESS" "$person"; done; fi\nFT_TICK_IDLE_TEAM_REOPEN=1 idle_team_reopen "$ROOT/.fable-team/seats-fixture.json" "$SEAT" "$REQUEST"\n'
            if label == "reopen-ready-split": command += 'for person in $MEMBERS; do MODEL_ACTOR=1 bash "$MBOX" recv "$HARNESS" "$person"; done\nFT_TICK_IDLE_TEAM_REOPEN=1 idle_team_reopen "$ROOT/.fable-team/seats-fixture.json" "$SEAT" "$REQUEST"\n'
            if label == "reopen-dormant":
                command = command.replace('cp "$ROOT/closed.json" "$ROOT/.fable-team/seats-fixture.json"\ncp "$ROOT/pending"', 'cp "$ROOT/closed.json" "$ROOT/.fable-team/seats-fixture.json"\nidle_team_watch\ncp "$STATE_DIR/idle-teams/fixture.json" "$ROOT/dormant.json"\ncp "$ROOT/pending"')
                command = command.replace('idle_team_watch\nMODEL_ACTOR=1', 'idle_team_watch\ncp "$STATE_DIR/idle-teams/fixture.json" "$ROOT/late-plan.json"\nMODEL_ACTOR=1')
        env = dict(os.environ, ROOT=str(root), FT_ROOT=str(root), BIN=str(source.parent), SEAT=members[0], FT_TICK_IDLE_TEAMS="1", PYTHONDONTWRITEBYTECODE="1", HIL_DIR=str(root / "hil"), REQUEST=str(request), NO_READY="1" if label == "reopen-no-ready" else "0", RECV_NONE="1" if label == "reopen-read-none" else "0", READY_SPLIT="1" if label == "reopen-ready-split" else "0", DELAY_SEAT=members[1], MEMBERS=" ".join(members), HARNESS=protected[1])
        if label == "default-off": env.pop("FT_TICK_IDLE_TEAMS")
        result = subprocess.run(["bash"], input=setup + "\n".join(parts) + "\n" + command, env=env, capture_output=True, text=True, timeout=7)
        plan_path = root / "state/idle-teams/fixture.json"
        plan = json.loads(plan_path.read_text()) if plan_path.exists() else {}
        good = result.returncode == 0
        if label in ("zero-duration", "preserve", "old-stop-ready"):
            good &= plan.get("state") == "candidate" and plan.get("members") == members and plan.get("cleanup_verified") is False
            if label == "zero-duration": good &= (root / "before.json").exists() and json.loads((root / "before.json").read_text()).get("state") == "observing"
            good &= len(plan.get("preserve", [])) >= 9
        elif label.startswith("reopen"):
            events = (root / "events").read_text().splitlines() if (root / "events").exists() else []
            expected = "forwarded" if label == "reopen-read-none" else "waiting_ready" if label == "reopen-no-ready" else "ready"
            good &= plan.get("state") == expected and plan.get("request_seq") == request
            good &= bool(events) and len(events) > 1 and events[0].startswith("handover:") and events[1].startswith("recv:")
            calls = 0 if label == "reopen-read-none" else 3
            good &= sum(e.startswith("resume:") for e in events) == calls and sum(e.startswith("restore:") for e in events) == calls
            restored = json.loads(seats.read_text())
            if calls: good &= all(restored[n]["role"] == ("master" if i == 0 else "nano") for i, n in enumerate(members))
            good &= restored[old]["role"] == "stop-ready" and not any(old in e for e in events)
            if label == "reopen-dormant":
                dormant = json.loads((root / "dormant.json").read_text())
                late = json.loads((root / "late-plan.json").read_text())
                good &= dormant.get("cohort") == members and dormant.get("closed_members") == members and late.get("state") == "forwarded"
        elif label == "default-off": good &= not plan and not (root / "events").exists()
        else: good &= plan.get("state") == "protected"
        good &= before == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (root / "preserved").iterdir()}
        failures += not good
        print(f'{"PASS" if good else "FAIL"} {label} rc={result.returncode} state={plan.get("state")} seconds={time.monotonic()-begin:.3f}')
        if not good: print(result.stdout + result.stderr + json.dumps(plan))
print(f"PHASE lifecycle seconds={time.monotonic()-started:.3f} failures={failures}")
sys.exit(bool(failures))
PY
