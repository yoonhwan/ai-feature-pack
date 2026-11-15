"""r1752 — stall-scan 은 팀장이 지금 WORKING 이어도 «마지막으로 끝낸 턴» 시각(master_end)을 남긴다.

R1752_BIN = 시험할 bin 폴더(기본 kit · 셸 짝 tests/test_stall_scan_master_end_working_r1752.sh 가 변이 사본·기준판을 넣는다).
가짜 세계(_stall_world) — 실 좌석·실 페널티 0 · FT_NOW 고정 · since = NOW(ft-penalty.sh on).
"""
import json
import os
from pathlib import Path

import pytest

import _stall_world
from _stall_world import NOW, World
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

_stall_world.BIN = Path(os.environ.get("R1752_BIN") or _stall_world.BIN)


@pytest.fixture
def w(tmp_path: Path) -> World:
    out = World(tmp_path)
    assert out.penalty("on", "--reason", "시험").returncode == 0
    return out


def master_end(w: World) -> float | None:
    snap = json.loads((w.root / ".fable-team/state/stall-scan.last.json").read_text(encoding="utf-8"))
    return snap["teams"]["t1"]["master_end"]


def test_1_working_end_after_since_resumes(w: World) -> None:
    w.state("t1-master#1", "WORKING", -1)  # TURN_END = since + 60초
    _ = w.scan()
    assert master_end(w) == NOW + 60
    r = w.penalty("resume", "t1")
    assert r.returncode == 0 and "resumed=t1" in r.stdout, r.stdout


def test_2_working_end_before_since_stays_blocked(w: World) -> None:
    w.state("t1-master#1", "WORKING", 1)  # TURN_END = since − 60초(쪽지 전 턴)
    _ = w.scan()
    assert master_end(w) == NOW - 60
    r = w.penalty("resume", "t1")
    assert r.returncode == 1 and "재개 불가" in r.stdout and "TURN_END ≤ since" in r.stdout, r.stdout


def test_3_idle_end_after_since_resumes(w: World) -> None:
    w.state("t1-master#1", "IDLE", -1)
    _ = w.scan()
    assert master_end(w) == NOW + 60
    r = w.penalty("resume", "t1")
    assert r.returncode == 0 and "resumed=t1" in r.stdout, r.stdout


def test_4_unknown_keeps_none(w: World) -> None:
    _ = (w.stub / "turn" / "t1-master#1").write_text("UNKNOWN - - - pane\n")
    _ = w.scan()
    assert master_end(w) is None
    r = w.penalty("resume", "t1")
    assert r.returncode == 1 and "재개 불가" in r.stdout, r.stdout


@pytest.mark.parametrize("state", ["UNKNOWN", "PENDING"])
def test_4b_non_idle_working_with_end_keeps_none(w: World, state: str) -> None:
    w.state("t1-master#1", state, -1)  # TURN_END 값이 있어도 IDLE·WORKING 밖이면 None(A2 · 추측 0)
    _ = w.scan()
    assert master_end(w) is None
    assert w.penalty("resume", "t1").returncode == 1
