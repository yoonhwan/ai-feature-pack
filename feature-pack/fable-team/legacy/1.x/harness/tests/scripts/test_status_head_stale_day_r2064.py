"""status_head r2064 — 하루(1440분) 넘게 낡은 머리줄은 옛 수 대신 «카운팅 확인 불가(낡음)» (반례 ①~⑤).

가짜 루트(FT_ROOT) · 가짜 mbox(calls.log) · 임시 TEAM-STATUS(FT_TEAM_STATUS_FILE) · 나이 = head(now=…) 고정값 / os.utime.
실 슬랙·실 mbox·실 TEAM-STATUS 0 · sleep 0.
실행: python3 -m pytest tests/scripts/test_status_head_stale_day_r2064.py -q
"""
import json
import logging
import os
import time

import pytest
from _proposal_fakes import slack  # noqa: F401 — 키트 경로를 sys.path 에

import mirror_head
import post_guard as pg
import status_head as sh

PLANNER = "byz-planner-master-claude#181"
PLAIN = "스크립트 0 · 인터뷰 0 · 막힌 팀 대기 0"
BROKEN = "스크립트 ? · 인터뷰 0 · 막힌 팀 대기 0"
STALE = "카운팅 확인 불가(낡음)"
MTIME = 1_793_000_000
FAKE_MBOX = '#!/bin/bash\nprintf "%s\\037" "$@" >> "$(dirname "$0")/calls.log"; echo >> "$(dirname "$0")/calls.log"\nexit 0\n'


@pytest.fixture
def root(tmp_path, monkeypatch):
    r = tmp_path / "root"
    (r / ".fable-team" / "comm").mkdir(parents=True)
    (r / ".fable-team" / "state").mkdir()
    (r / ".fable-team" / "seats-planner.json").write_text(json.dumps({"_master": PLANNER}), encoding="utf-8")
    (r / ".fable-team" / "comm" / "mbox.sh").write_text(FAKE_MBOX, encoding="utf-8")
    monkeypatch.setenv("FT_ROOT", str(r))
    monkeypatch.delenv(sh.STALE_ENV, raising=False)
    monkeypatch.delenv(pg.HUMAN_CHANNELS_ENV, raising=False)
    return r


def status(tmp_path, monkeypatch, first=PLAIN, mtime=MTIME):
    f = tmp_path / "TEAM-STATUS.md"
    f.write_text(f"{first}\n설명: 시험\n", encoding="utf-8")
    os.utime(f, (mtime, mtime))
    monkeypatch.setenv(sh.FILE_ENV, str(f))


def head_at(age_min):
    return sh.head(now=MTIME + age_min * 60)


def calls(root):
    log = root / ".fable-team" / "comm" / "calls.log"
    return log.read_text(encoding="utf-8").splitlines() if log.exists() else []


@pytest.mark.parametrize("age", [1441, 17576])
def test_1_older_than_a_day_says_cannot_stale_without_old_numbers(root, tmp_path, monkeypatch, caplog, age):  # ① · A1
    status(tmp_path, monkeypatch)
    with caplog.at_level(logging.ERROR):
        out = head_at(age)
    assert out == STALE and "스크립트" not in out
    assert sum(1 for r in caplog.records if r.levelno == logging.ERROR) == 1
    assert calls(root) == []


@pytest.mark.parametrize("age, want", [(1440, f"{PLAIN} (낡음 1440분)"), (31, f"{PLAIN} (낡음 31분)"), (29, PLAIN)])
def test_2_up_to_a_day_keeps_the_old_behaviour(root, tmp_path, monkeypatch, age, want):  # ② · A2
    status(tmp_path, monkeypatch)
    assert head_at(age) == want


@pytest.mark.parametrize("age, want", [(1500, STALE), (1000, PLAIN)])
def test_3_day_cap_ignores_a_larger_env_threshold(root, tmp_path, monkeypatch, age, want):  # ③ · A2
    monkeypatch.setenv(sh.STALE_ENV, "2000")
    status(tmp_path, monkeypatch)
    assert head_at(age) == want


def test_4a_broken_shape_stays_shape_even_when_old(root, tmp_path, monkeypatch):  # ④ · A3
    status(tmp_path, monkeypatch, first=BROKEN)
    assert head_at(3000) == "카운팅 확인 불가(형식)"
    assert len(calls(root)) == 1


def test_4b_missing_file_stays_missing(root, tmp_path, monkeypatch):  # ④ · A3
    monkeypatch.setenv(sh.FILE_ENV, str(tmp_path / "없는파일.md"))
    assert head_at(3000) == "카운팅 확인 불가(파일 없음)"


def test_5_guarded_post_starts_with_cannot_stale_once(root, tmp_path, monkeypatch):  # ⑤ · A4
    status(tmp_path, monkeypatch, mtime=time.time() - 3000 * 60)
    posted = []
    monkeypatch.setattr(pg, "post", lambda base, token, channel, text, thread_ts=None: posted.append(text) or "1793.000100")
    pg.guarded_post("http://x", "t", "C1", "본문 첫 줄\n둘째 줄", human=True)
    assert posted[0] == f"{STALE}\n본문 첫 줄\n둘째 줄"
    pg.guarded_post("http://x", "t", "C1", posted[0], human=True)
    assert posted[1] == posted[0]
    assert mirror_head._is_counter_line(STALE)
