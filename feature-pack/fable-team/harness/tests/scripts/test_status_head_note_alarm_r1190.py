"""status_head r1190 — 1행 숫자 뒤 «(메모)» 허용 + 형식이 깨진 판(mtime)마다 planner 에게 [경보] 1통 (반례 R1~R6).

가짜 루트(FT_ROOT) 아래 가짜 .fable-team/comm/mbox.sh(호출 인자 수집기) · 실 루트·실 mbox·실 슬랙 0 · 자기 재호출 0 · 고정 sleep 0.
실행: python3 -m pytest tests/scripts/test_status_head_note_alarm_r1190.py -q
"""
import json
import logging
import os

import pytest
from _proposal_fakes import slack  # noqa: F401 — 키트 경로를 sys.path 에

import status_head as sh

PLANNER = "byz-planner-master-claude#181"
NOTE = "스크립트 1(h360) · 인터뷰 2 · 막힌 팀 대기 3"
PLAIN = "스크립트 1 · 인터뷰 2 · 막힌 팀 대기 3"
BROKEN = "스크립트 ? · 인터뷰 2 · 막힌 팀 대기 3"
FAKE_MBOX = '#!/bin/bash\nprintf "%s\\037" "$@" >> "$(dirname "$0")/calls.log"; echo >> "$(dirname "$0")/calls.log"\nexit "${FAKE_MBOX_RC:-0}"\n'


@pytest.fixture
def root(tmp_path, monkeypatch):
    """가짜 루트 — 명부(_master) · 가짜 mbox · 상태 폴더."""
    r = tmp_path / "root"
    (r / ".fable-team" / "comm").mkdir(parents=True)
    (r / ".fable-team" / "state").mkdir()
    (r / ".fable-team" / "seats-planner.json").write_text(json.dumps({"_master": PLANNER}), encoding="utf-8")
    (r / ".fable-team" / "comm" / "mbox.sh").write_text(FAKE_MBOX, encoding="utf-8")
    monkeypatch.setenv("FT_ROOT", str(r))
    monkeypatch.delenv("FAKE_MBOX_RC", raising=False)
    return r


def status(tmp_path, monkeypatch, first, mtime=1_793_000_000):
    f = tmp_path / "TEAM-STATUS.md"
    f.write_text(f"{first}\n설명: 시험\n", encoding="utf-8")
    os.utime(f, (mtime, mtime))
    monkeypatch.setenv(sh.FILE_ENV, str(f))
    return mtime


def calls(root):
    log = root / ".fable-team" / "comm" / "calls.log"
    return [line.split("\x1f")[:-1] for line in log.read_text(encoding="utf-8").splitlines()] if log.exists() else []


def mark(root):
    return root / ".fable-team" / "state" / "status-head-alarm.txt"


@pytest.mark.parametrize("first", [NOTE, PLAIN])
def test_r1_r2_note_or_plain_first_line_is_the_head_and_no_alarm(root, tmp_path, monkeypatch, first):  # ⓐ · R1 · R2
    now = status(tmp_path, monkeypatch, first)
    assert sh.head(now=now) == first
    assert calls(root) == []


def test_r3_broken_shape_sends_one_alarm_to_planner(root, tmp_path, monkeypatch):  # ⓑ · R3
    now = status(tmp_path, monkeypatch, BROKEN)
    assert sh.head(now=now) == "카운팅 확인 불가(형식)"
    (c,) = calls(root)
    assert c[:3] == ["send", PLANNER, "status-head"] and c[3].startswith("[경보]") and BROKEN in c[3]
    assert mark(root).read_text(encoding="utf-8").strip() == str(os.stat(os.environ[sh.FILE_ENV]).st_mtime_ns)


def test_r4_same_edition_three_heads_one_alarm(root, tmp_path, monkeypatch):  # ⓑ · R4
    now = status(tmp_path, monkeypatch, BROKEN)
    heads = [sh.head(now=now) for _ in range(3)]
    assert heads == ["카운팅 확인 불가(형식)"] * 3
    assert len(calls(root)) == 1


def test_r5_new_broken_edition_sends_one_more(root, tmp_path, monkeypatch):  # ⓑ · R5
    sh.head(now=status(tmp_path, monkeypatch, BROKEN))
    sh.head(now=status(tmp_path, monkeypatch, "스크립트 ? · 인터뷰 ? · 막힌 팀 대기 3", mtime=1_793_000_600))
    assert len(calls(root)) == 2


@pytest.mark.parametrize("break_mbox", ["missing", "rc2"])
def test_r6_alarm_failure_keeps_head_logs_one_error_and_writes_no_mark(root, tmp_path, monkeypatch, caplog, break_mbox):  # ⓒ · R6
    if break_mbox == "missing":
        (root / ".fable-team" / "comm" / "mbox.sh").unlink()
    else:
        monkeypatch.setenv("FAKE_MBOX_RC", "2")
    now = status(tmp_path, monkeypatch, BROKEN)
    with caplog.at_level(logging.ERROR):
        assert sh.head(now=now) == "카운팅 확인 불가(형식)"
    errors = [r.getMessage() for r in caplog.records if r.levelno == logging.ERROR]
    assert len(errors) == 1 and "경보 실패" in errors[0]
    assert not mark(root).exists()
