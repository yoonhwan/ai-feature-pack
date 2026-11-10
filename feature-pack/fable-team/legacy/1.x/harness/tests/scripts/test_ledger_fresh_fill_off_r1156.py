"""r1156 원장 신선도 [긴급] — 채움 job(com.byz.ft-news-planner) 꺼짐이면 0 · 담당 = 명부 seats-planner.json _master.
가짜 루트(명부·state) + 가짜 LaunchAgents 폴더(FT_LAUNCH_AGENTS_DIR · 실 ~/Library 0) + FT_MBOX 가짜 송신기 · 자기 재호출 0.
실행: python3 -m pytest tests/scripts/test_ledger_fresh_fill_off_r1156.py -q
"""
import json
import logging
import sys
from datetime import datetime
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
sys.path[:0] = [str(BIN)]

import ft_ledger_fill as lf  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

NOW = datetime(2026, 10, 30, 20, 39)  # «11:1x» = 10-29 11:19 → 2000분
LEDGER = "# 원장\n> 마지막 갱신: 2026-10-29 11:1x · planner#160 (결론 · 갱신 담당 byz-old#1)\n"
MASTER = "byz-planner-master-claude#173"
OFF = "com.byz.ft-news-planner.plist.off-20261029"
STALE = f"원장 2000분 낡음 · 담당 {MASTER}"


@pytest.fixture
def world(tmp_path, monkeypatch):
    root = tmp_path / "root"
    (root / ".fable-team").mkdir(parents=True)
    (root / ".fable-team/seats-planner.json").write_text(json.dumps({"_master": MASTER}), encoding="utf-8")
    mlog = tmp_path / "mbox.log"
    (tmp_path / "mbox.sh").write_text(f'#!/usr/bin/env bash\necho "$@" >> {mlog}\n', encoding="utf-8")
    agents = tmp_path / "LaunchAgents"
    agents.mkdir()
    for k, v in {"FT_MBOX": tmp_path / "mbox.sh", "FT_LEDGER_FILL_STATE": tmp_path / "state", "FT_LAUNCH_AGENTS_DIR": agents}.items():
        monkeypatch.setenv(k, str(v))
    monkeypatch.delenv("FT_LEDGER_FRESH_MIN", raising=False)
    return {"root": root, "agents": agents, "mlog": mlog, "tmp": tmp_path, "mp": monkeypatch}


def sent(w) -> list[str]:
    return w["mlog"].read_text(encoding="utf-8").splitlines() if w["mlog"].is_file() else []


def test_r1_fill_off_no_urgent_and_off_tail(world):
    (world["agents"] / OFF).write_text("x", encoding="utf-8")
    assert lf.fresh_note(world["root"], LEDGER, NOW) == f"{STALE} · 채움 꺼짐({OFF})"
    assert sent(world) == []
    assert not (world["tmp"] / "state" / "fresh-alarm.json").exists()  # 다시 켜지면 같은 사건도 1통


def test_r2_fill_on_one_urgent_owner_roster(world):
    (world["agents"] / "com.byz.ft-news-planner.plist").write_text("x", encoding="utf-8")
    (world["agents"] / OFF).write_text("x", encoding="utf-8")  # 본체가 있으면 옛 .off 는 무시
    assert lf.fresh_note(world["root"], LEDGER, NOW) == STALE
    assert lf.fresh_note(world["root"], LEDGER, NOW) == STALE  # 같은 사건 두 번째 = 0
    s = sent(world)
    assert len(s) == 1 and s[0].startswith(f"send {MASTER} ft-ledger-fill [긴급] {STALE}")


def test_r3_no_plist_no_off_is_not_off(world):
    assert lf.fresh_note(world["root"], LEDGER, NOW) == STALE
    assert len(sent(world)) == 1


def test_r4_owner_from_roster_not_ledger_text(world):
    note = lf.fresh_note(world["root"], LEDGER, NOW)
    assert note.endswith(f"담당 {MASTER}") and "byz-old" not in note
    assert "byz-old" not in sent(world)[0]


def test_r4b_roster_unreadable_owner_unknown_logged(world, caplog):
    (world["root"] / ".fable-team/seats-planner.json").unlink()
    with caplog.at_level(logging.ERROR, logger="ft_ledger_fill"):
        assert lf.fresh_note(world["root"], LEDGER, NOW) == "원장 2000분 낡음 · 담당 모름"
    assert any("seats-planner.json" in r.getMessage() for r in caplog.records if r.levelno == logging.ERROR)


def test_r5_agents_dir_unreadable_alarms_and_logs(world, caplog):
    not_dir = world["tmp"] / "agents-is-a-file"
    not_dir.write_text("x", encoding="utf-8")
    world["mp"].setenv("FT_LAUNCH_AGENTS_DIR", str(not_dir))
    with caplog.at_level(logging.ERROR, logger="ft_ledger_fill"):
        assert lf.fresh_note(world["root"], LEDGER, NOW) == STALE
    assert len(sent(world)) == 1
    assert any("채움 job 폴더 못 읽음" in r.getMessage() for r in caplog.records if r.levelno == logging.ERROR)


def test_fresh_unchanged_by_fill_off(world):
    (world["agents"] / OFF).write_text("x", encoding="utf-8")
    assert lf.fresh_note(world["root"], LEDGER, datetime(2026, 10, 29, 12, 19)) == ""  # 60분 = 신선 · 꼬리 0
