"""r1289 — 헤드라인 나이 경보와 단계 승격."""
import json
import importlib
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

from _stall_world import BIN, NOW, World, counts

sys.path.insert(0, str(BIN))
headline_module = importlib.import_module("ft_stall_headline")
find_headlines = headline_module.find
headline_alerts = headline_module.headline_alerts


def quiet(w: World) -> None:
    for seat in ("planner#1", "t1-master#1", "t1-nano#0", "room-master#1", "room-nano#0"):
        w.state(seat, "WORKING", 0.1)


def room(w: World, live_master: bool = True) -> None:
    w.team("m.room", "room-master#1", ["room-nano#0"])
    if not live_master:
        w.live.remove("room-master#1")
        w._tmux()
    quiet(w)
    p = w.root / ".fable-team/seats-planner.json"
    d = json.loads(p.read_text())
    d["planner-desk#0"] = {"role": "desk"}
    p.write_text(json.dumps(d))
    w.live.append("planner-desk#0")
    w.state("planner-desk#0", "WORKING", 0.1)
    w._tmux()


def headline(w: World, label: str, age: float, clock: str | None = None, folder: bool = False, now: float = NOW) -> Path:
    tick = label.removeprefix("m.") + "-tick"
    path = w.root / f".fable-team/{tick}/HEADLINE.md"
    if folder:
        path.mkdir(parents=True)
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    stamp = now - age * 60
    clock = clock or datetime.fromtimestamp(stamp).strftime("%H:%M")
    path.write_text(f"{clock} · 카드 대기 1 · 팀장=room-master#1=작업 중\n내용\n", encoding="utf-8")
    os.utime(path, (stamp, stamp))
    return path


def scan(w: World) -> subprocess.CompletedProcess[str]:
    return w.scan()


def sent(w: World, seat: str) -> list[str]:
    return [line for line in w.mbox_log() if line.startswith(f"send|{seat}|")]


def test_r1_fresh_headline_is_quiet(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 5)
    r = scan(w)
    assert counts(r.stdout)["h"] == "0" and not w.mbox_log()


def test_r2_fifteen_minutes_alerts_team_master(tmp_path: Path) -> None:
    exact = World(tmp_path / "exact")
    room(exact)
    headline(exact, "m.room", 15)
    assert counts(scan(exact).stdout)["h"] == "0" and not sent(exact, "room-master#1")

    over = World(tmp_path / "over")
    room(over)
    headline(over, "m.room", 15 + 1 / 60)
    r = scan(over)
    assert counts(r.stdout)["h"] == "1" and len(sent(over, "room-master#1")) == 1
    assert "[헤드라인 멈춤]" in sent(over, "room-master#1")[0]

    under = World(tmp_path / "under")
    room(under)
    headline(under, "m.room", 15 - 1 / 60)
    assert counts(scan(under).stdout)["h"] == "0" and not sent(under, "room-master#1")


def test_r3_same_headline_is_not_sent_twice(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 16)
    scan(w)
    w.advance(120)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1


def test_r4_persistent_headline_escalates_to_planner_desk(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 16)
    scan(w)
    scan(w)
    assert not sent(w, "planner-desk#0")
    w.advance(20 * 60 - 1)
    scan(w)
    assert not sent(w, "planner-desk#0")
    w.advance(1)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1
    assert len(sent(w, "planner-desk#0")) == 1


def test_r5_changed_headline_resets_escalation_stage(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    p = headline(w, "m.room", 16)
    scan(w)
    w.advance(5 * 60)
    stamp = NOW + 5 * 60
    p.write_text(f"{datetime.fromtimestamp(stamp).strftime('%H:%M')} · 카드 대기 1 · 팀장=room-master#1=작업 중\n", encoding="utf-8")
    os.utime(p, (stamp, stamp))
    w.advance(20 * 60)
    scan(w)
    assert not sent(w, "planner-desk#0")


def test_r6_midnight_boundary_has_three_points(tmp_path: Path) -> None:
    now = datetime(2026, 11, 2, 0, 5).timestamp()
    cases = ((15, 0, 0), (15 + 1 / 60, 1, 1), (15 - 1 / 60, 0, 0), (7, 0, 0))
    for index, (age, expected_h, expected_send) in enumerate(cases):
        w = World(tmp_path / str(index))
        room(w)
        w.env["FT_NOW"] = str(now)
        headline(w, "m.room", age, now=now)
        r = scan(w)
        assert counts(r.stdout)["h"] == str(expected_h)
        assert len(sent(w, "room-master#1")) == expected_send


def test_r7_future_headline_is_unknown(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", -1)
    r = scan(w)
    assert "h? m.room" in r.stdout and not w.mbox_log()


def test_r8_missing_headline_is_unknown(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    r = scan(w)
    assert "h? m.room" in r.stdout and counts(r.stdout)["u"] != "0"


def test_r9_label_maps_to_tick_directory(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 16)
    wrong = w.root / ".fable-team/m.room/HEADLINE.md"
    wrong.parent.mkdir(parents=True)
    wrong.write_text("bad")
    assert counts(scan(w).stdout)["h"] == "1"

    outside = World(tmp_path / "outside")
    (outside.root / ".fable-team/seats-m.room.json").write_text(
        json.dumps({"_master": "", "_label": "m.room", "_cards": "design/room/indices"}),
        encoding="utf-8",
    )
    quiet(outside)
    r = scan(outside)
    assert "h? m.room 대상 밖" in r.stdout and counts(r.stdout)["u"] == "0"


def test_r10_missing_team_master_routes_directly_to_planner(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w, live_master=False)
    headline(w, "m.room", 16)
    scan(w)
    assert not sent(w, "room-master#1") and len(sent(w, "planner-desk#0")) == 1


def test_r11_feature_flag_off_does_not_read_headline(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 60)
    with patch.dict(os.environ, {"FT_STALL_HEADLINE": "0"}), patch.object(Path, "open", side_effect=AssertionError("HEADLINE opened")):
        found, unknown, notes = find_headlines(w.root, [{"team": "m.room"}], NOW)
    assert not found and unknown == 0 and not notes


def test_r12_summary_appends_h_after_existing_fields(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 16)
    first = scan(w).stdout.splitlines()[0]
    assert first.endswith("h=1") and " f=" in first and counts(first)["stall"] == "0"


def test_r13_old_mtime_and_matching_clock_uses_full_age(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 24 * 60 + 5)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1


def test_r14_mtime_clock_mismatch_is_unknown(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    p = headline(w, "m.room", 5, datetime.fromtimestamp(NOW - 5 * 60).strftime("%H:%M"))
    p.write_text(f"{datetime.fromtimestamp(NOW - 5 * 60).strftime('%H:%M')} · 진행 중\n", encoding="utf-8")
    os.utime(p, (NOW - 5 * 60, NOW - 5 * 60))
    r = scan(w)
    assert "h? m.room 헤드라인 판정 불가 — 구조 없음" in r.stdout and not w.mbox_log()


def test_r15_policy_stop_skips_headline(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 20)
    (w.root / ".fable-team/state/RESOURCE_FREEZE").write_text("stop\n", encoding="utf-8")
    r = scan(w)
    assert counts(r.stdout)["h"] == "0"
    assert "h? m.room 대상 밖(정책 정지)" in r.stdout and counts(r.stdout)["u"] == "0"
    assert not any("[헤드라인 멈춤]" in line for line in w.mbox_log())

    broken = World(tmp_path / "broken")
    room(broken)
    headline(broken, "m.room", 20)
    (broken.root / ".fable-team/state/SPAWN_HOLD").write_text("{bad", encoding="utf-8")
    r = scan(broken)
    assert "h? m.room 정책 정지 판정 불가" in r.stdout and counts(r.stdout)["u"] == "1"


def test_r16_alerts_live_successor_master_only(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 16)
    p = w.root / ".fable-team/seats-m.room.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d["room-master#2"] = {"role": "master"}
    p.write_text(json.dumps(d), encoding="utf-8")
    w.live.remove("room-master#1")
    w.live.append("room-master#2")
    w.state("room-master#2", "WORKING", 0.1)
    w._tmux()
    scan(w)
    assert not sent(w, "room-master#1") and len(sent(w, "room-master#2")) == 1
    assert not sent(w, "planner-desk#0")


def test_r17_attached_master_still_alerts_without_stall_record(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 16)
    _ = (w.stub / "tmux").write_text("".join(f"{seat} {1 if seat in {'room-master#1', 'planner-desk#0'} else 0}\n" for seat in w.live))
    r = scan(w)
    assert counts(r.stdout)["h"] == "1" and len(sent(w, "room-master#1")) == 1
    w.advance(20 * 60)
    scan(w)
    assert len(sent(w, "planner-desk#0")) == 1
    saved = json.loads((w.root / ".fable-team/state/stall-scan.json").read_text(encoding="utf-8"))
    assert not any(key.startswith("h") for key in saved["prev"])
    assert not any("act=h" in line or line.startswith("h m.room") for line in w.scan_log())
    headline_state = json.loads((w.root / ".fable-team/state/stall-headline.json").read_text(encoding="utf-8"))
    assert len(headline_state) == 2 and all(key.startswith(("h1:", "h2:")) for key in headline_state)


def test_r18_non_meta_label_is_out_of_scope(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 16)
    quiet(w)
    r = scan(w)
    assert counts(r.stdout)["stall"] == "0" and counts(r.stdout)["h"] == "1"
    source = (BIN / "ft_stall_scan.py").read_text(encoding="utf-8")
    assert "timeout=7" in source and "timeout=15" not in source


def test_r19_stage_threshold_boundaries(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 16)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1
    w.advance(20 * 60 - 1)
    scan(w)
    assert not sent(w, "planner-desk#0")
    w.advance(1)
    scan(w)
    assert len(sent(w, "planner-desk#0")) == 1


def test_r18b_rotated_log_receipt_skips_retry_and_records_state(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    comm = w.root / ".fable-team/comm"
    key = "h1:m.room:20261101:20:05"
    (comm / "mailbox.log.jsonl").write_text("", encoding="utf-8")
    row = {"seq": 7, "from": "ft-stall-scan", "to": "room-master#1", "body": f"[헤드라인 멈춤] key={key}"}
    (comm / "mailbox.log.jsonl.1").write_text(json.dumps(row) + "\n", encoding="utf-8")
    calls: list[tuple[str, str]] = []
    item = {"kind": "h", "team": "m.room", "seat": "room-master#1", "masters": ["room-master#1"],
            "date": "20261101", "clock": "20:05", "age": 16.0, "why": "헤드라인 멈춤"}

    def timed_out(to: str, body: str) -> tuple[int, bool]:
        calls.append((to, body))
        return 99, True

    notes = headline_alerts(w.root, comm, [item], {"room-master#1": 0}, NOW, timed_out)
    state = json.loads((w.root / ".fable-team/state/stall-headline.json").read_text(encoding="utf-8"))
    assert not notes and len(calls) == 1 and key in calls[0][1]
    assert state[key]["sent_at"] == NOW


def test_r20_headline_keys_ignore_old_and_a_suppression_and_pick_latest_master(tmp_path: Path) -> None:
    now = datetime(2026, 11, 2, 20, 20, 1).timestamp()
    previous = World(tmp_path / "previous")
    room(previous)
    previous.env["FT_NOW"] = str(now)
    headline(previous, "m.room", 15 + 1 / 60, "20:05", now=now)
    state_dir = previous.root / ".fable-team/state"
    old_key = "h1:m.room:20261101:20:05"
    (state_dir / "stall-headline.json").write_text(json.dumps({old_key: {"sent_at": now - 1200}}), encoding="utf-8")
    scan(previous)
    assert len(sent(previous, "room-master#1")) == 1

    suppressed = World(tmp_path / "suppressed")
    room(suppressed)
    headline(suppressed, "m.room", 16)
    suppressed.cards("m.room", ["card"])
    suppressed.state("room-master#1", "IDLE", 5)
    stall_state = {"handled": {"room-master#1": NOW - 30}, "prev": [], "seats": {}}
    (suppressed.root / ".fable-team/state/stall-scan.json").write_text(json.dumps(stall_state), encoding="utf-8")
    stamp = datetime.fromtimestamp(NOW - 30).strftime("%Y-%m-%dT%H:%M:%S")
    (suppressed.root / ".fable-team/state/stall-scan.log").write_text(f"{stamp} act=a to=room-master#1 old\n", encoding="utf-8")
    scan(suppressed)
    assert len(sent(suppressed, "room-master#1")) == 1

    latest = World(tmp_path / "latest")
    room(latest)
    p = latest.root / ".fable-team/seats-m.room.json"
    rows = json.loads(p.read_text(encoding="utf-8"))
    rows["room-master#3"] = {"role": "master"}
    rows["room-master#12"] = {"role": "master"}
    p.write_text(json.dumps(rows), encoding="utf-8")
    latest.live.remove("room-master#1")
    latest.live.extend(("room-master#3", "room-master#12"))
    latest.state("room-master#3", "WORKING", 0.1)
    latest.state("room-master#12", "WORKING", 0.1)
    latest._tmux()
    headline(latest, "m.room", 16)
    scan(latest)
    assert not sent(latest, "room-master#3") and len(sent(latest, "room-master#12")) == 1
