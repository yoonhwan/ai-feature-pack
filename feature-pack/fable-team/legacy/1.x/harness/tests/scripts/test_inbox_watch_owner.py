"""Frozen inbox owner contracts; fake clock/pipe, temporary canonical comm only."""
import json
import multiprocessing as mp

import pytest

from _inbox_watch_fixture import Owner, SEAT, alarm_env, cutover_ready, mail, queue, receive
from _inbox_watch_fixture import world as world


def test_singleton_same_key_competition_and_reacquire(world):
    barrier = mp.get_context("fork").Barrier(2)
    with Owner(world, barrier=barrier) as left, Owner(world, barrier=barrier) as right:
        events = [left.read(), right.read()]
        assert sum(event[0] == "poll" for event in events) == 1
        loser = next(event for event in events if event[0] == "exit")
        assert loser[1:3] == (3, "") and "BUSY owner_lock" in loser[3]
    lock = next((world / ".fable-team/state/inbox-watch").glob("*.lock"))
    inode = lock.stat().st_ino
    with Owner(world) as again:
        assert again.read()[0] == "poll" and lock.stat().st_ino == inode


def test_owner_fences_retired_generation(world):
    with Owner(world) as owner:
        assert owner.read()[0] == "poll"
        p = world / ".fable-team/seats-planner.json"
        successor = "byz-planner-master-pi#2"
        p.write_text(json.dumps({"_master": successor, SEAT: {"role": "stop-ready", "_replaced_by": successor},
                                 successor: {"role": "master", "_replaces": [SEAT]}}))
        assert owner.tick()[:2] == ("exit", 0)


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
    with Owner(world) as left, Owner(other, seat) as right:
        assert left.read()[0] == right.read()[0] == "poll"


def test_backlog_receipts_rewrite_and_restart(world):
    queue(world, [10, 11, 12])
    assert receive(world, "source11").returncode == 0
    with Owner(world) as owner:
        assert owner.read()[0] == "poll"
        event = owner.tick()
        assert "#10 " in event[1] and "#12 " in event[1] and "#11 " not in event[1]
        assert owner.tick()[1] == event[1]
        state = json.loads(next((world / ".fable-team/state/inbox-watch").glob("*.json")).read_text())
        assert set(state["pending"]) == {"10", "12"} and 11 in state["received"]
        receipt = world / ".fable-team/comm/receipts" / (SEAT + ".jsonl")
        original = receipt.read_bytes()
        receipt.write_text("{")
        assert owner.tick()[1] == event[1]
        receipt.write_bytes(original)
        queue(world, [10, 12, 14])
        assert owner.tick("broken")[1] == event[1]
        state = json.loads(next((world / ".fable-team/state/inbox-watch").glob("*.json")).read_text())
        assert state["pending"]["14"]["notified_generation"] is None
    queue(world, [10, 12, 13])
    with Owner(world) as restarted:
        restarted.read()
        out = restarted.tick()[1]
        assert all("#" + str(n) + " " in out for n in (10, 12, 13)) and "#11 " not in out


@pytest.mark.parametrize("entry", ["comm", "kit"])
@pytest.mark.parametrize("command", ["send", "relay"])
@pytest.mark.parametrize("mode", ["alive", "absent", "unknown", "enqueue_failure"])
def test_alarm_contract(world, entry, command, mode):
    script, env = alarm_env(world, entry, mode)
    results = [mail(world, script, env, command, "source" + str(n)) for n in (1, 2)]
    assert all(result.returncode == 0 and "doorbell=quiet" in result.stdout for result in results), results
    rows = [json.loads(line) for line in (world / ".fable-team/comm/mailbox.jsonl").read_text().splitlines()]
    assert len([row for row in rows if row["to"] == SEAT]) == 2
    alarms = [row for row in rows if row["from"] == "ft-watch-alarm"]
    expected = int(mode == "absent" or (mode == "unknown" and entry == "kit"))
    assert len(alarms) == expected
    assert all("Monitor" not in row["body"] and "ft-inbox-watch.sh" not in row["body"] for row in alarms)
    if mode in ("unknown", "enqueue_failure"):
        assert all(result.stderr for result in results)
    if mode == "enqueue_failure":
        assert not (world / ".fable-team/state" / ("planner-watch-missing." + SEAT)).exists()


@pytest.mark.parametrize("entry", ["comm", "kit"])
@pytest.mark.parametrize("quiet", [False, True])
def test_stdout_consumer_uses_normal_recv_receipt(world, entry, quiet):
    script, env = alarm_env(world, entry, "alive", fake_doorbell=True)
    seat = SEAT if quiet else "byz-planner-desk-claude#1"
    roster = world / ".fable-team/seats-planner.json"
    roster.write_text(json.dumps({"_master": SEAT, SEAT: {"role": "master", "tick": None},
                                 "_desk": "byz-planner-desk-claude#1", "byz-planner-desk-claude#1": {"role": "desk", "tick": None}}))
    result = mail(world, script, env, seat=seat)
    assert result.returncode == 0 and ("doorbell=quiet" in result.stdout) == quiet, result
    with Owner(world, seat) as owner:
        owner.read()
        event = owner.tick()
        assert len(event[1].splitlines()) == 1
        queue(world, None)
        assert owner.tick()[1] == event[1]
        assert receive(world, "source1", seat).returncode == 0
        assert owner.tick()[1] == event[1]
    receipts = [json.loads(line) for line in (world / ".fable-team/comm/receipts" / (seat + ".jsonl")).read_text().splitlines()]
    assert len(receipts) == 1 and (world / "fake-tmux.log").exists() != quiet
    assert receipts[0]["seq"] == int(event[1].split()[1][1:]) and len(event[1].rstrip().split(" ", 4)[4]) == 40


@pytest.mark.parametrize("entry", ["comm", "kit"])
def test_same_absence_recovery_fixture_before_after(world, entry):
    import shutil
    comparison = []
    for baseline in (True, False):
        root = world.parent / ("baseline" if baseline else "final")
        shutil.copytree(world, root)
        script, env = alarm_env(root, entry, baseline=baseline)
        assert mail(root, script, env).returncode == 0
        with Owner(root) as owner:
            assert owner.read()[-1] == 240.0
            assert len(owner.tick()[1].splitlines()) == 1
            assert receive(root, "source1").returncode == 0
            owner.tick()
        with Owner(root, epoch=480) as owner:
            assert owner.read()[-1] == 480.0
            env["FT_FIX_WATCH"] = "alive"
            assert mail(root, script, env, sender="source2").returncode == 0
            assert len(owner.tick()[1].splitlines()) == 1
            assert receive(root, "source2").returncode == 0
        rows = [json.loads(line) for line in (root / ".fable-team/comm/mailbox.jsonl").read_text().splitlines()]
        alarms = [row for row in rows if row["from"] == "ft-watch-alarm"]
        received = (root / ".fable-team/comm/receipts" / (SEAT + ".jsonl")).read_text().splitlines()
        comparison.append((sum("Monitor" in row["body"] for row in alarms), len(alarms), len(received)))
    print("COMPARISON", entry, json.dumps(comparison), "normal_exit_then_fake_elapsed=240")
    assert comparison == [(1, 1, 2), (0, 1, 2)]
    assert not cutover_ready(dict(owner=True, recovery=True, driver=False, receipt=True))


def test_receipt_write_failure_preserves_original_and_pending(world):
    queue(world, [10])
    module = world / ".fable-team/comm/mbox_handover.py"
    original = module.read_text()
    module.write_text(original + '\ndef _append(*args):\n    raise OSError("fixture receipt write failure")\n')
    assert receive(world, "source10").returncode != 0
    assert json.loads((world / ".fable-team/comm/mailbox.jsonl").read_text())["seq"] == 10
    with Owner(world) as owner:
        owner.read()
        assert "#10 " in owner.tick()[1]
        state = json.loads(next((world / ".fable-team/state/inbox-watch").glob("*.json")).read_text())
        assert "10" in state["pending"] and 10 not in state["received"]


@pytest.mark.parametrize("defect", ["missing", "ambiguous", "cycle", "generation", "canonical"])
def test_invalid_binding_and_stale_generation_fail_closed(world, defect):
    roster = world / ".fable-team/seats-planner.json"
    doc = json.loads(roster.read_text())
    if defect == "missing":
        del doc["_master"]
    if defect == "ambiguous":
        doc["_desk"] = SEAT
    if defect == "cycle":
        doc[SEAT]["_replaced_by"] = SEAT
    roster.write_text(json.dumps(doc))
    with Owner(world, comm=world / "wrong" if defect == "canonical" else None) as owner:
        event = owner.read()
        if defect == "generation":
            path = next((world / ".fable-team/state/inbox-watch").glob("*.json"))
            state = json.loads(path.read_text())
            state["generation"] += 1
            path.write_text(json.dumps(state))
            assert owner.tick()[:2] == ("exit", 0)
        else:
            assert event[0] == "exit" and event[1] != 0 and event[2] == ""
