"""R320b — ft-penalty.sh(on|status|resume|off|check) + ft-stall-scan 의 자동 발동. 가짜 세계 — 실 spawn·ring 0."""
from pathlib import Path

import pytest

from _stall_world import BIN, World, counts


@pytest.fixture
def w(tmp_path: Path) -> World:
    out = World(tmp_path)
    out.team("t2", "t2-master#1", ["t2-nano#0"])
    return out


def stop_file(w: World) -> Path:
    return w.root / ".fable-team/state/PENALTY_STOP"


def test_two_consecutive_detections_create_penalty(w: World) -> None:
    w.cards("t1", ["c1"])
    w.state("t1-master#1", "IDLE", 5)
    _ = w.scan()
    assert not stop_file(w).exists()
    w.advance(120)
    _ = w.scan()
    assert stop_file(w).exists()
    stops = [r for r in w.mbox_log() if "[페널티]" in r]
    assert {r.split("|")[1] for r in stops} == {"t1-master#1", "t2-master#1"}  # 복구 팀(planner)은 정지 대상 아님


def test_one_shot_resolution_makes_no_penalty(w: World) -> None:
    w.cards("t1", ["c1"])
    w.state("t1-master#1", "IDLE", 5)
    _ = w.scan()
    w.state("t1-master#1", "WORKING", 0.1)
    w.advance(120)
    _ = w.scan()
    assert not stop_file(w).exists()


def test_auto_off_switch(w: World) -> None:
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    w.cards("t1", ["c1"])
    w.state("t1-master#1", "IDLE", 5)
    _ = w.scan()
    w.advance(120)
    _ = w.scan()
    assert not stop_file(w).exists()


def test_check_rejects_unresumed_team_and_passes_resumed(w: World) -> None:
    assert w.penalty("check", "t1").returncode == 0
    assert w.penalty("on", "--reason", "시험").returncode == 0
    r = w.penalty("check", "t1")
    assert r.returncode == 3 and r.stdout.startswith("REJECT penalty")
    assert w.penalty("check").returncode == 3


def test_resume_requires_fresh_scan_without_hang_for_that_team(w: World) -> None:
    _ = w.penalty("on", "--reason", "시험")
    r = w.penalty("resume", "t1")
    assert r.returncode != 0 and "scan" in r.stdout  # 최근 스캔 없음 = 재개 불가
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "착수하겠습니다")
    _ = w.scan("--dry-run")  # dry-run 은 상태 기록 0 → 여전히 불가
    assert w.penalty("resume", "t1").returncode != 0
    w.state("t1-nano#0", "WORKING", 0.1)
    _ = w.scan()
    assert "TURN_END" in w.penalty("resume", "t1").stdout  # master 가 쪽지 뒤 턴을 아직 안 끝냄
    w.state("t1-master#1", "IDLE", -2)
    _ = w.scan()
    assert w.penalty("resume", "t1").returncode == 0
    assert w.penalty("check", "t1").returncode == 0 and w.penalty("check", "t2").returncode == 3


def test_resume_blocked_while_team_has_hang(w: World) -> None:
    _ = w.penalty("on", "--reason", "시험")
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "착수하겠습니다")
    _ = w.scan()
    r = w.penalty("resume", "t1")
    assert r.returncode != 0 and "stall" in r.stdout


def test_all_teams_resumed_removes_file(w: World) -> None:
    _ = w.penalty("on", "--reason", "시험")
    w.state("t1-master#1", "IDLE", -2)
    w.state("t2-master#1", "IDLE", -2)
    _ = w.scan()
    for t in ("t1", "t2"):
        assert w.penalty("resume", t).returncode == 0, t
    assert not stop_file(w).exists() and w.penalty("status").stdout.startswith("penalty=off")


def test_penalty_scan_takes_no_action_on_unresumed_team(w: World) -> None:
    _ = w.penalty("on", "--reason", "시험")
    before = len(w.mbox_log())
    w.cards("t2", ["c1"])
    w.state("t2-master#1", "IDLE", 9)
    r = w.scan()
    assert counts(r.stdout)["a"] == "0" and len(w.mbox_log()) == before


def test_off_removes(w: World) -> None:
    _ = w.penalty("on", "--reason", "시험")
    assert w.penalty("off").returncode == 0 and not stop_file(w).exists()


def test_nano_and_role_spawn_call_check_but_successor_does_not() -> None:
    def calls(name: str) -> bool:
        return "ft-penalty.sh" in (BIN / name).read_text()
    assert calls("ft-nano-spawn.sh") and calls("ft-role-spawn.sh") and not calls("ft-successor-open.sh")


def test_recovery_team_is_exempt_from_penalty(w: World) -> None:
    w.team("harness", "h-master#1", ["h-nano#0"])
    _ = w.penalty("on", "--reason", "시험")
    assert w.penalty("check", "harness").returncode == 0 and w.penalty("check", "planner").returncode == 0
    assert not any(r.startswith("send|h-master#1|") for r in w.mbox_log())
    w.state("h-nano#0", "IDLE", 4)
    w.jsonl("h-nano#0", "착수하겠습니다")
    assert counts(w.scan().stdout)["b"] == "1" and any(r.startswith("ring|h-nano#0") for r in w.mbox_log())


def test_a_not_counted_for_unresumed_team_during_penalty(w: World) -> None:
    w.cards("t1", ["c1"])
    w.state("t1-master#1", "IDLE", 9)
    _ = w.penalty("on", "--reason", "시험")
    assert counts(w.scan().stdout)["a"] == "0"
