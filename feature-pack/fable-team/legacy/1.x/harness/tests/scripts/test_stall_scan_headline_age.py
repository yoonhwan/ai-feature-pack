"""r1289 — 헤드라인 나이 경보와 단계 승격.

r1323 — 픽스처를 «지금 꼴» 로 바꾼다: 팀 이름 = TEAMS.md 이름(«m.» 없음) · 경로 = .fable-team/state/<팀>-tick/ · 명부 = seats.json(v65).
H1~H9 = 이름·경로·명부·정지 표식·제0목표 칸·시각 대조·구조 머리·팀장 정지 레디 반례. R1~R20 = r1289 계약 동결(H8).
"""
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

COUNTS = "카드 대기 1·진행 0·완성(오늘) 0"


def quiet(w: World) -> None:
    for seat in ("planner#1", "t1-master#1", "t1-nano#0", "room-master#1", "room-nano#0", "room-master#2", "v65-master#267", "v65-nano#0"):
        w.state(seat, "WORKING", 0.1)


def desk(w: World) -> None:
    p = w.root / ".fable-team/seats-planner.json"
    d = json.loads(p.read_text())
    d["planner-desk#0"] = {"role": "desk"}
    p.write_text(json.dumps(d))
    w.live.append("planner-desk#0")
    w.state("planner-desk#0", "WORKING", 0.1)
    w._tmux()


def roster(w: World, label: str, rows: dict, master: str = "", file: str | None = None) -> None:
    """TEAMS.md 한 줄 + 그 팀 명부(기본 seats-<팀>.json) + 카드 폴더 + 라이브 좌석."""
    rows = {"_master": master, "_label": label, "_cards": f"design/{label}/indices", "_cards_wt": f"wt-{label}", **rows}
    (w.root / f".fable-team/{file or f'seats-{label}.json'}").write_text(json.dumps(rows), encoding="utf-8")
    (w.root / f".worktrees/wt-{label}/design/{label}/indices").mkdir(parents=True, exist_ok=True)
    w._team_row(label)
    w.live.extend(seat for seat in rows if not seat.startswith("_") and seat not in w.live)
    w._tmux()


def room(w: World, live_master: bool = True, label: str = "room") -> None:
    w.team(label, "room-master#1", ["room-nano#0"])
    if not live_master:
        w.live.remove("room-master#1")
        w._tmux()
    quiet(w)
    desk(w)


def live_line(clock: str, master: str = "room-master#1", seat: str = "room-nano#0", counts: str = COUNTS, zero: bool = False) -> str:
    """RULE §1 꼴(400자 상한) 1줄 — 제0목표 칸은 옵션(거버넌스 R13 · K5)."""
    head = "제0목표: 진행 중 카드를 완성하고 닫는다. · " if zero else ""
    return f"{head}{clock} · {counts} · 팀장={master}=✻ {clock} · {seat}=작업 중"


def write_headline(w: World, label: str, first: str, mtime: float, name: str = "HEADLINE.md") -> Path:
    path = w.root / f".fable-team/state/{label.removeprefix('m.')}-tick/{name}"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(first + "\n", encoding="utf-8")
    os.utime(path, (mtime, mtime))
    return path


def headline(w: World, label: str, age: float, clock: str | None = None, now: float = NOW, zero: bool = False) -> Path:
    stamp = now - age * 60
    return write_headline(w, label, live_line(clock or datetime.fromtimestamp(stamp).strftime("%H:%M"), zero=zero), stamp)


def pause(w: World, label: str, text: str = "판정 3108 · 2026-11-02T10:00:00 · 오빠 지시로 팀 정지") -> None:
    path = w.root / f".fable-team/state/{label.removeprefix('m.')}-tick/PAUSED"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text + "\n", encoding="utf-8")


def scan(w: World) -> subprocess.CompletedProcess[str]:
    return w.scan()


def summary(r: subprocess.CompletedProcess[str]) -> dict[str, str]:
    """첫 줄이 WARN(명부 진단)일 수 있으므로 «stall=» 로 시작하는 요약 줄만 읽는다."""
    return counts(next(line for line in r.stdout.splitlines() if line.startswith("stall=")))


def sent(w: World, seat: str) -> list[str]:
    return [line for line in w.mbox_log() if line.startswith(f"send|{seat}|")]


def headline_state(w: World) -> dict:
    path = w.root / ".fable-team/state/stall-headline.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


# ── H1~H9 — r1323 라이브 이름·경로·명부 ──────────────────────────────────────────


def test_h1_live_team_name_alerts_its_own_master(tmp_path: Path) -> None:
    w = World(tmp_path / "over")
    room(w)
    headline(w, "room", 15 + 1 / 60)
    r = scan(w)
    assert summary(r)["h"] == "1" and len(sent(w, "room-master#1")) == 1
    assert "h? room" not in r.stdout

    under = World(tmp_path / "under")
    room(under)
    headline(under, "room", 15 - 1 / 60)
    r = scan(under)
    assert summary(r)["h"] == "0" and not sent(under, "room-master#1") and "h? room" not in r.stdout


def test_h2_v65_roster_is_seats_json(tmp_path: Path) -> None:
    w = World(tmp_path)
    roster(w, "v65", {"v65-master#267": {"role": "master"}, "v65-nano#0": {"role": "nano"}}, master="v65-master#267", file="seats.json")
    quiet(w)
    desk(w)
    headline(w, "v65", 15 + 1 / 60)
    r = scan(w)
    assert summary(r)["h"] == "1" and len(sent(w, "v65-master#267")) == 1
    assert "명부 읽기 실패" not in r.stdout and not sent(w, "planner-desk#0")


def test_h3_paused_marker_is_out_of_scope(tmp_path: Path) -> None:
    on = World(tmp_path / "on")
    room(on)
    headline(on, "room", 1000)
    pause(on, "room")
    r = scan(on)
    assert summary(r)["h"] == "0" and summary(r)["u"] == "0" and not on.mbox_log()
    assert "h? room 대상 밖(정지 표식)" in r.stdout and "m.room" not in r.stdout
    with patch.object(headline_module, "headline_age", side_effect=AssertionError("HEADLINE opened")):
        found, unknown, notes = find_headlines(on.root, [{"team": "room"}], NOW)
    assert not found and unknown == 0 and notes == ["h? room 대상 밖(정지 표식)"]

    broken = World(tmp_path / "broken")
    room(broken)
    headline(broken, "room", 1000)
    pause(broken, "room", "꼴 아님")
    r = scan(broken)
    assert summary(r)["h"] == "1" and len(sent(broken, "room-master#1")) == 1
    assert sum(1 for line in r.stdout.splitlines() if line.startswith("WARN room 정지 표식 판정 불가 — 경보 보냄(")) == 1

    gone = World(tmp_path / "gone")
    room(gone)
    headline(gone, "room", 1000)
    assert summary(scan(gone))["h"] == "1" and len(sent(gone, "room-master#1")) == 1

    off = World(tmp_path / "off")
    room(off)
    off.env["FT_STALL_PAUSED_SKIP"] = "0"
    headline(off, "room", 1000)
    pause(off, "room")
    r = scan(off)
    assert summary(r)["h"] == "1" and len(sent(off, "room-master#1")) == 1


def test_h4_zero_goal_cell_is_dropped_once(tmp_path: Path) -> None:
    over = World(tmp_path / "over")
    now = datetime(2026, 11, 2, 14, 31, 1).timestamp()
    over.set_now(now)
    room(over)
    write_headline(over, "room", live_line("14:16", zero=True), now - 15 * 60 - 1)
    assert counts(scan(over).stdout)["h"] == "1" and len(sent(over, "room-master#1")) == 1

    under = World(tmp_path / "under")
    under_now = datetime(2026, 11, 2, 14, 30, 59).timestamp()
    under.set_now(under_now)
    room(under)
    write_headline(under, "room", live_line("14:16", zero=True), under_now - 15 * 60 + 1)
    assert summary(scan(under))["h"] == "0" and not sent(under, "room-master#1")

    twice = World(tmp_path / "twice")
    twice.set_now(now)
    room(twice)
    write_headline(twice, "room", "제0목표: 하나 · 제0목표: 둘 · 14:16 · " + COUNTS + " · 팀장=room-master#1=✻ 14:16", now - 86 * 60)
    r = scan(twice)
    assert summary(r)["h"] == "0" and summary(r)["u"] == "1" and not twice.mbox_log()
    assert "h? room 헤드라인 판정 불가 — 첫 줄 시각 없음 또는 꼴 틀림" in r.stdout


def test_h4b_lead_cell_alone_counts_as_screen_cell(tmp_path: Path) -> None:
    """동결 13-r3 «나노 0 팀은 팀장 칸에 적음» — 좌석 칸이 없어도 팀장 칸이 STATUS 면 구조 정상."""
    now = datetime(2026, 11, 2, 14, 21, 0).timestamp()
    lead_only = World(tmp_path / "lead_only")
    lead_only.set_now(now)
    room(lead_only)
    write_headline(lead_only, "room", "14:16 · 카드 대기 5·진행 0·완성(오늘) 0 · 팀장=틱(✻ 14:15)", datetime(2026, 11, 2, 14, 16, 0).timestamp())
    r = scan(lead_only)
    assert summary(r)["h"] == "0" and summary(r)["u"] == "0" and not lead_only.mbox_log()
    assert "h? room" not in r.stdout

    no_status = World(tmp_path / "no_status")
    no_status.set_now(now)
    room(no_status)
    write_headline(no_status, "room", "14:16 · 카드 대기 5·진행 0·완성(오늘) 0 · 팀장=대기", datetime(2026, 11, 2, 14, 16, 0).timestamp())
    r = scan(no_status)
    assert summary(r)["h"] == "0" and summary(r)["u"] == "1" and not no_status.mbox_log()
    assert "h? room 헤드라인 판정 불가 — 구조 없음" in r.stdout


def test_h5_clock_and_mtime_slack(tmp_path: Path) -> None:
    def world(name: str, mtime_clock: tuple[int, int]) -> World:
        w = World(tmp_path / name)
        w.set_now(datetime(2026, 11, 2, 14, 34, 1).timestamp())
        room(w)
        stamp = datetime(2026, 11, 2, *mtime_clock, 0).timestamp()
        write_headline(w, "room", live_line("14:19"), stamp)
        return w

    ahead = world("ahead", (14, 20))
    r = scan(ahead)
    assert summary(r)["h"] == "1" and "시각 불일치" not in r.stdout

    behind = world("behind", (14, 35))
    r = scan(behind)
    assert summary(r)["h"] == "0" and summary(r)["u"] == "1" and not behind.mbox_log()
    assert "h? room 헤드라인 판정 불가 — 시각 불일치" in r.stdout

    edge = world("edge", (14, 34))
    r = scan(edge)
    assert "시각 불일치" not in r.stdout


def test_h6_stale_broken_shape_still_alerts(tmp_path: Path) -> None:
    harness_line = "12:55 · 카드 대기 75·진행 1·완성(오늘 착지) 7장 · 팀장=master#151·arch#208"
    stale = World(tmp_path / "stale")
    stale.set_now(datetime(2026, 11, 2, 14, 21, 0).timestamp())
    room(stale)
    write_headline(stale, "room", harness_line, datetime(2026, 11, 2, 12, 55, 0).timestamp())
    r = scan(stale)
    assert summary(r)["h"] == "1" and len(sent(stale, "room-master#1")) == 1
    assert "꼴 틀림" in sent(stale, "room-master#1")[0]

    fresh = World(tmp_path / "fresh")
    fresh.set_now(datetime(2026, 11, 2, 13, 0, 0).timestamp())
    room(fresh)
    write_headline(fresh, "room", harness_line, datetime(2026, 11, 2, 12, 55, 0).timestamp())
    r = scan(fresh)
    assert summary(r)["h"] == "0" and summary(r)["u"] == "1" and not fresh.mbox_log()
    assert "h? room 헤드라인 판정 불가 — 구조 없음" in r.stdout


def test_h6b_missing_card_head_is_not_enough(tmp_path: Path) -> None:
    line = "14:16 · 팀장=작업 중"

    fresh = World(tmp_path / "fresh")
    fresh.set_now(datetime(2026, 11, 2, 14, 21, 0).timestamp())
    room(fresh)
    write_headline(fresh, "room", line, datetime(2026, 11, 2, 14, 16, 0).timestamp())
    r = scan(fresh)
    assert summary(r)["h"] == "0" and summary(r)["u"] == "1" and not fresh.mbox_log()
    assert "h? room 헤드라인 판정 불가 — 구조 없음" in r.stdout

    stale = World(tmp_path / "stale")
    stale.set_now(datetime(2026, 11, 2, 14, 40, 0).timestamp())
    room(stale)
    write_headline(stale, "room", line, datetime(2026, 11, 2, 14, 16, 0).timestamp())
    r = scan(stale)
    assert summary(r)["h"] == "1" and len(sent(stale, "room-master#1")) == 1
    assert "꼴 틀림" in sent(stale, "room-master#1")[0]


def test_h7_meta_label_normalized_to_live_name(tmp_path: Path) -> None:
    """옛 «m.<팀>» 이름이 와도 경로·명부·정지 표식·경보 team·억제 키가 전부 정규화 이름 하나(K1)."""
    paused = World(tmp_path / "paused")
    room(paused)
    headline(paused, "m.room", 100)  # 폴더는 정규화 이름(room-tick)
    pause(paused, "room")
    found, unknown, notes = find_headlines(paused.root, [{"team": "m.room", "master": "room-master#1"}], NOW)
    assert not found and unknown == 0 and not paused.mbox_log()
    assert notes == ["h? room 대상 밖(정지 표식)"]

    live = World(tmp_path / "live")
    room(live)
    headline(live, "m.room", 15 + 1 / 60)
    found, unknown, notes = find_headlines(live.root, [{"team": "m.room", "master": "room-master#1"}], NOW)
    assert unknown == 0 and not notes and len(found) == 1 and found[0]["team"] == "room"
    calls: list[tuple[str, str]] = []

    def send(to: str, body: str) -> tuple[int, bool]:
        calls.append((to, body))
        return 0, False

    headline_alerts(live.root, live.root / ".fable-team/comm", found, {"room-master#1": 0}, NOW, send)
    assert len(calls) == 1 and calls[0][0] == "room-master#1" and " room 1단계" in calls[0][1]
    keys = list(headline_state(live))
    assert keys and all(key.startswith("h1:room:") for key in keys) and "m.room" not in json.dumps(keys)


def test_h9_stop_ready_master_is_out_of_scope(tmp_path: Path) -> None:
    w = World(tmp_path)
    roster(w, "room", {"room-master#1": {"role": "stop-ready"}, "room-master#2": {"role": "master"}}, master="room-master#1")
    w.live.remove("room-master#1")
    w._tmux()
    w.set_now(datetime(2026, 11, 2, 14, 21, 0).timestamp())
    quiet(w)
    desk(w)
    write_headline(w, "room", "12:55 · 카드 대기 75·진행 1·완성(오늘 착지) 7장 · 팀장=master#151·arch#208", datetime(2026, 11, 2, 12, 55, 0).timestamp())
    r = scan(w)
    assert summary(r)["h"] == "0" and summary(r)["u"] == "0" and not w.mbox_log()
    assert "h? room 대상 밖 — 팀장 정지 레디" in r.stdout


# ── R1~R20 — r1289 계약 동결(픽스처만 지금 꼴 · H8) ────────────────────────────────


def test_r1_fresh_headline_is_quiet(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 5)
    r = scan(w)
    assert summary(r)["h"] == "0" and not w.mbox_log()


def test_r2_fifteen_minutes_alerts_team_master(tmp_path: Path) -> None:
    exact = World(tmp_path / "exact")
    room(exact)
    headline(exact, "room", 15)
    assert summary(scan(exact))["h"] == "0" and not sent(exact, "room-master#1")

    over = World(tmp_path / "over")
    room(over)
    headline(over, "room", 15 + 1 / 60)
    r = scan(over)
    assert summary(r)["h"] == "1" and len(sent(over, "room-master#1")) == 1
    assert "[헤드라인 멈춤]" in sent(over, "room-master#1")[0]

    under = World(tmp_path / "under")
    room(under)
    headline(under, "room", 15 - 1 / 60)
    assert summary(scan(under))["h"] == "0" and not sent(under, "room-master#1")


def test_r3_same_headline_is_not_sent_twice(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 16)
    scan(w)
    w.advance(120)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1


def test_r4_persistent_headline_escalates_to_planner_desk(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 16)
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
    p = headline(w, "room", 16)
    scan(w)
    w.advance(5 * 60)
    stamp = NOW + 5 * 60
    p.write_text(live_line(datetime.fromtimestamp(stamp).strftime("%H:%M")) + "\n", encoding="utf-8")
    os.utime(p, (stamp, stamp))
    w.advance(20 * 60)
    scan(w)
    assert not sent(w, "planner-desk#0")


def test_r6_midnight_boundary_has_three_points(tmp_path: Path) -> None:
    now = datetime(2026, 11, 2, 0, 5).timestamp()
    cases = ((15, 0, 0), (15 + 1 / 60, 1, 1), (15 - 1 / 60, 0, 0), (7, 0, 0))
    for index, (age, expected_h, expected_send) in enumerate(cases):
        w = World(tmp_path / str(index))
        w.set_now(now)
        room(w)
        headline(w, "room", age, now=now)
        r = scan(w)
        assert summary(r)["h"] == str(expected_h)
        assert len(sent(w, "room-master#1")) == expected_send


def test_r7_future_headline_is_unknown(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", -1)
    r = scan(w)
    assert "h? room" in r.stdout and not w.mbox_log()


def test_r8_missing_headline_is_unknown(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    (w.root / ".fable-team/state/room-tick/HEADLINE.md").unlink()  # 세계는 헤드라인을 쓰지만 이 팀만 지운다
    r = scan(w)
    assert "h? room" in r.stdout and summary(r)["u"] != "0"


def test_r9_label_maps_to_tick_directory(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 16)
    wrong = w.root / ".fable-team/room/HEADLINE.md"
    wrong.parent.mkdir(parents=True, exist_ok=True)
    wrong.write_text("bad")
    assert summary(scan(w))["h"] == "1"

    outside = World(tmp_path / "outside")
    roster(outside, "room", {"room-nano#0": {"role": "nano"}}, master="room-nano#0")
    quiet(outside)
    r = scan(outside)
    assert "h? room 대상 밖 — 현역 팀장 없음" in r.stdout and summary(r)["u"] == "0"


def test_r10_missing_team_master_routes_directly_to_planner(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w, live_master=False)
    headline(w, "room", 16)
    scan(w)
    assert not sent(w, "room-master#1") and len(sent(w, "planner-desk#0")) == 1


def test_r11_feature_flag_off_does_not_read_headline(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 60)
    with patch.dict(os.environ, {"FT_STALL_HEADLINE": "0"}), patch.object(Path, "open", side_effect=AssertionError("HEADLINE opened")):
        found, unknown, notes = find_headlines(w.root, [{"team": "room"}], NOW)
    assert not found and unknown == 0 and not notes


def test_r12_summary_appends_h_after_existing_fields(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 16)
    first = scan(w).stdout.splitlines()[0]
    keys = [kv.split("=", 1)[0] for kv in first.split()]  # r1882·r1883 — 기존 칸(a~f·h) 순서 그대로 + 끝에 g·m 1칸씩
    assert " h=1" in first and keys == ["stall", "a", "b", "c", "d", "e", "seats", "u", "ts", "l", "f", "h", "g", "m"] and counts(first)["stall"] == "0"


def test_r13_old_mtime_and_matching_clock_uses_full_age(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 24 * 60 + 5)
    scan(w)
    assert len(sent(w, "room-master#1")) == 1


def test_r14_mtime_clock_mismatch_is_unknown(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    p = headline(w, "room", 5, datetime.fromtimestamp(NOW - 5 * 60).strftime("%H:%M"))
    p.write_text(f"{datetime.fromtimestamp(NOW - 5 * 60).strftime('%H:%M')} · 진행 중\n", encoding="utf-8")
    os.utime(p, (NOW - 5 * 60, NOW - 5 * 60))
    r = scan(w)
    assert "h? room 헤드라인 판정 불가 — 구조 없음" in r.stdout and not w.mbox_log()


def test_r15_policy_stop_skips_headline(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 20)
    (w.root / ".fable-team/state/RESOURCE_FREEZE").write_text("stop\n", encoding="utf-8")
    r = scan(w)
    assert summary(r)["h"] == "0"
    assert "h? room 대상 밖(정책 정지)" in r.stdout and summary(r)["u"] == "0"
    assert not any("[헤드라인 멈춤]" in line for line in w.mbox_log())

    broken = World(tmp_path / "broken")
    room(broken)
    headline(broken, "room", 20)
    (broken.root / ".fable-team/state/SPAWN_HOLD").write_text("{bad", encoding="utf-8")
    r = scan(broken)
    assert "h? room 정책 정지 판정 불가" in r.stdout
    assert summary(r)["u"] == "3"  # K1 — «m.» 거르기를 지워 판정 불가 갈래가 현역 3팀(t1·planner·room) 전부를 센다


def test_r16_alerts_live_successor_master_only(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 16)
    p = w.root / ".fable-team/seats-room.json"
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
    headline(w, "room", 16)
    _ = (w.stub / "tmux").write_text("".join(f"{seat} {1 if seat in {'room-master#1', 'planner-desk#0'} else 0}\n" for seat in w.live))
    r = scan(w)
    assert summary(r)["h"] == "1" and len(sent(w, "room-master#1")) == 1
    w.advance(20 * 60)
    scan(w)
    assert len(sent(w, "planner-desk#0")) == 1
    saved = json.loads((w.root / ".fable-team/state/stall-scan.json").read_text(encoding="utf-8"))
    assert not any(key.startswith("h") for key in saved["prev"])
    assert not any("act=h" in line or line.startswith("h room") for line in w.scan_log())
    room_keys = [key for key in headline_state(w) if ":room:" in key]  # K1 — t1·planner 도 판정 대상이 됐다
    assert len(room_keys) == 2 and all(key.startswith(("h1:", "h2:")) for key in room_keys)


def test_r18_non_meta_label_is_out_of_scope(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 16)
    quiet(w)
    r = scan(w)
    assert summary(r)["stall"] == "0" and summary(r)["h"] == "1"
    source = (BIN / "ft_stall_scan.py").read_text(encoding="utf-8")
    assert "timeout=7" in source and "timeout=15" not in source


def test_r19_stage_threshold_boundaries(tmp_path: Path) -> None:
    w = World(tmp_path)
    room(w)
    headline(w, "room", 16)
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
    key = "h1:room:20261101:20:05"
    (comm / "mailbox.log.jsonl").write_text("", encoding="utf-8")
    row = {"seq": 7, "from": "ft-stall-scan", "to": "room-master#1", "body": f"[헤드라인 멈춤] key={key}"}
    (comm / "mailbox.log.jsonl.1").write_text(json.dumps(row) + "\n", encoding="utf-8")
    calls: list[tuple[str, str]] = []
    item = {"kind": "h", "team": "room", "seat": "room-master#1", "masters": ["room-master#1"],
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
    previous.set_now(now)
    room(previous)
    headline(previous, "room", 15 + 1 / 60, "20:05", now=now)
    state_dir = previous.root / ".fable-team/state"
    old_key = "h1:room:20261101:20:05"
    (state_dir / "stall-headline.json").write_text(json.dumps({old_key: {"sent_at": now - 1200}}), encoding="utf-8")
    scan(previous)
    assert len(sent(previous, "room-master#1")) == 1

    suppressed = World(tmp_path / "suppressed")
    room(suppressed)
    headline(suppressed, "room", 16)
    suppressed.cards("room", ["card"])
    suppressed.state("room-master#1", "IDLE", 5)
    stall_state = {"handled": {"room-master#1": NOW - 30}, "prev": [], "seats": {}}
    (suppressed.root / ".fable-team/state/stall-scan.json").write_text(json.dumps(stall_state), encoding="utf-8")
    stamp = datetime.fromtimestamp(NOW - 30).strftime("%Y-%m-%dT%H:%M:%S")
    (suppressed.root / ".fable-team/state/stall-scan.log").write_text(f"{stamp} act=a to=room-master#1 old\n", encoding="utf-8")
    scan(suppressed)
    assert len(sent(suppressed, "room-master#1")) == 1

    latest = World(tmp_path / "latest")
    room(latest)
    p = latest.root / ".fable-team/seats-room.json"
    rows = json.loads(p.read_text(encoding="utf-8"))
    rows["room-master#3"] = {"role": "master"}
    rows["room-master#12"] = {"role": "master"}
    p.write_text(json.dumps(rows), encoding="utf-8")
    latest.live.remove("room-master#1")
    latest.live.extend(("room-master#3", "room-master#12"))
    latest.state("room-master#3", "WORKING", 0.1)
    latest.state("room-master#12", "WORKING", 0.1)
    latest._tmux()
    headline(latest, "room", 16)
    scan(latest)
    assert not sent(latest, "room-master#3") and len(sent(latest, "room-master#12")) == 1
