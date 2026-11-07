"""Frozen inbox owner contracts; fake clock/pipe, temporary canonical comm only."""
import json
import multiprocessing as mp

import pytest

from _inbox_watch_fixture import Owner, SEAT, queue, receive
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
