"""r1289 — 헤드라인 나이 경보와 단계 승격."""
import json
import os
import subprocess
from datetime import datetime
from pathlib import Path

from _stall_world import BIN, NOW, World, counts


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


def headline(w: World, label: str, age: float, clock: str | None = None, folder: bool = False) -> Path:
    tick = label.removeprefix("m.") + "-tick"
    path = w.root / f".fable-team/{tick}/HEADLINE.md"
    if folder:
        path.mkdir(parents=True)
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    stamp = NOW - age * 60
    clock = clock or datetime.fromtimestamp(stamp).strftime("%H:%M")
    path.write_text(f"{clock} · 카드 대기 1\n내용\n", encoding="utf-8")
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
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 15)
    r = scan(w)
    assert counts(r.stdout)["h"] == "1" and len(sent(w, "room-master#1")) == 1
    assert "[헤드라인 멈춤]" in sent(w, "room-master#1")[0]


def test_r3_same_headline_is_not_sent_twice(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 15)
    scan(w)
    w.advance(120)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1


def test_r4_persistent_headline_escalates_to_planner_desk(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 15)
    scan(w)
    scan(w)
    assert not sent(w, "planner-desk#0")
    w.advance(5 * 60)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1
    assert len(sent(w, "planner-desk#0")) == 1


def test_r5_changed_headline_resets_escalation_stage(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    p = headline(w, "m.room", 15)
    scan(w)
    w.advance(5 * 60)
    stamp = NOW + 5 * 60
    p.write_text(f"{datetime.fromtimestamp(stamp).strftime('%H:%M')} · 카드 대기 1\n", encoding="utf-8")
    os.utime(p, (stamp, stamp))
    w.advance(20 * 60)
    scan(w)
    assert not sent(w, "planner-desk#0")


def test_r6_midnight_recent_headline_is_quiet(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    now = datetime(2026, 11, 2, 0, 5).timestamp()
    stamp = datetime(2026, 11, 1, 23, 58).timestamp()
    w.env["FT_NOW"] = str(now)
    p = headline(w, "m.room", 7, "23:58")
    os.utime(p, (stamp, stamp))
    out = scan(w).stdout
    assert counts(out)["h"] == "0" and counts(out)["u"] == "0" and "h? m.room" not in out


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
    headline(w, "m.room", 15)
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
    headline(w, "m.room", 15)
    scan(w)
    assert not sent(w, "room-master#1") and len(sent(w, "planner-desk#0")) == 1


def test_r11_feature_flag_off_does_not_read_headline(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    p = headline(w, "m.room", 60)
    w.env["FT_STALL_HEADLINE"] = "0"
    assert counts(scan(w).stdout)["h"] == "0" and not w.mbox_log()
    assert p.is_file()


def test_r12_summary_appends_h_after_existing_fields(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 15)
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
    p.write_text(f"{datetime.fromtimestamp(NOW - 5 * 60).strftime('%H:%M')} 카드 대기 1\n", encoding="utf-8")
    os.utime(p, (NOW - 5 * 60, NOW - 5 * 60))
    r = scan(w)
    assert "h? m.room" in r.stdout and not w.mbox_log()


def test_r15_policy_stop_skips_headline(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 20)
    (w.root / ".fable-team/state/RESOURCE_FREEZE").write_text("stop\n", encoding="utf-8")
    r = scan(w)
    assert counts(r.stdout)["h"] == "0"
    assert not any("[헤드라인 멈춤]" in line for line in w.mbox_log())


def test_r16_alerts_every_active_team_master(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 15)
    p = w.root / ".fable-team/seats-m.room.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d["room-master#2"] = {"role": "master"}
    p.write_text(json.dumps(d), encoding="utf-8")
    w.live.append("room-master#2")
    w.state("room-master#2", "WORKING", 0.1)
    w._tmux()
    scan(w)
    assert len(sent(w, "room-master#1")) == 1 and len(sent(w, "room-master#2")) == 1


def test_r17_attached_master_still_alerts_without_stall_record(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 15)
    w.attach("room-master#1")
    r = scan(w)
    assert counts(r.stdout)["h"] == "1" and len(sent(w, "room-master#1")) == 1
    saved = json.loads((w.root / ".fable-team/state/stall-scan.json").read_text(encoding="utf-8"))
    assert not any(key.startswith("h:") for key in saved["prev"])
    assert not any("act=h" in line or line.startswith("h m.room") for line in w.scan_log())


def test_r18_non_meta_label_is_out_of_scope(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 15)
    quiet(w)
    r = scan(w)
    assert counts(r.stdout)["stall"] == "0" and counts(r.stdout)["h"] == "1"
    source = (BIN / "ft_stall_scan.py").read_text(encoding="utf-8")
    assert "timeout=7" in source and "timeout=15" not in source


def test_r19_stage_threshold_boundaries(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "m.room", 10)
    assert counts(scan(w).stdout)["h"] == "0"
    assert not sent(w, "room-master#1")
    w.advance(5 * 60)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1
    w.advance(5 * 60)
    scan(w)
    assert len(sent(w, "planner-desk#0")) == 1
