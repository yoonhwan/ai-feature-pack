"""판정 603 — REQUEST-LEDGER 형식 미달 행(열 수 ≠ 7): opt-in 없으면 raise · `MAGAZINE_MALFORMED_CARDS=report` 면 드러내고 계속.

임시 git 리포(ref 1개) 픽스처. 실행: python3 -m pytest tests/scripts/test_magazine_collect_open.py -q
"""
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _magazine_fakes import KIT  # noqa: E402,F401
import magazine_card_shape as shape  # noqa: E402
import magazine_collect_detail as mcd  # noqa: E402
import magazine_collect_open as mco  # noqa: E402
from magazine_window import MagazineError  # noqa: E402

KST = ZoneInfo("Asia/Seoul")
START, END = datetime(2026, 10, 8, 8, tzinfo=KST), datetime(2026, 10, 9, 8, tzinfo=KST)
HEAD = "| # | 접수 | 요청자 | 증상 1줄 | Issue | 오빠 값 | 반영 sha |\n|---|---|---|---|---|---|---|\n"
GOOD = "| R1 | 10-04 | a | 닫힌 증상 | #1 | 닫힘 10-05 (PR 1) | abc |\n| R2 | 10-05 | b | 열린 증상 | | 접수 · 대기 | |\n"
BAD4 = "| R38 | 10-08 | c | 네 칸 행 |\n| R39 | 10-08 | d | 또 네 칸 |\n"


def make_repo(tmp_path: Path, ledger: str) -> Path:
    r = tmp_path / "r"
    (r / "design/harness").mkdir(parents=True)
    (r / "design/harness/REQUEST-LEDGER.md").write_text(ledger, encoding="utf-8")
    for a in (["init", "-q", "-b", "main"], ["add", "-A"], ["commit", "-q", "-m", "c"]):
        subprocess.run(["git", "-C", str(r), "-c", "user.name=t", "-c", "user.email=t@t", *a], check=True, capture_output=True)
    return r


def collect(r: Path, tmp_path: Path) -> dict:
    return mco.collect_open(r, mcd.resolve_refs(r, ["main"], START, datetime.now(KST)), tmp_path, START, END)


def test_l1_without_opt_in_malformed_row_still_raises(tmp_path, monkeypatch):
    monkeypatch.delenv(shape.MODE_ENV, raising=False)
    with pytest.raises(MagazineError, match="열 수"):
        collect(make_repo(tmp_path, HEAD + GOOD + BAD4), tmp_path)


def test_l2_report_mode_lists_malformed_rows_and_logs_error(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv(shape.MODE_ENV, "report")
    o = collect(make_repo(tmp_path, HEAD + GOOD + BAD4), tmp_path)
    assert o["requests"] == [{"id": "R2", "text": "열린 증상 → 접수 · 대기"}]  # 닫힘 제외 규칙 그대로
    assert o["malformed_requests"] == [{"id": "R38", "cells": 4}, {"id": "R39", "cells": 4}]
    assert capsys.readouterr().err.splitlines() == ["ERROR magazine: 형식 미달 요청 행 R38 (열 수 4 · 기대 7)", "ERROR magazine: 형식 미달 요청 행 R39 (열 수 4 · 기대 7)"]


def test_l3_report_mode_with_only_good_rows_matches_default(tmp_path, monkeypatch, capsys):
    r = make_repo(tmp_path, HEAD + GOOD)
    monkeypatch.delenv(shape.MODE_ENV, raising=False)
    base = collect(r, tmp_path)
    monkeypatch.setenv(shape.MODE_ENV, "report")
    got = collect(r, tmp_path)
    assert got["malformed_requests"] == [] and got == base and capsys.readouterr().err == ""


def test_l4_unknown_mode_value_raises(tmp_path, monkeypatch):
    monkeypatch.setenv(shape.MODE_ENV, "reprot")
    with pytest.raises(MagazineError, match="알 수 없는 값"):
        collect(make_repo(tmp_path, HEAD + GOOD), tmp_path)


EMPTY_ID = "|  | a | 요지 | 상태 |\n"


def test_l6_report_mode_flags_empty_id_row_with_line_number_default_ignores_it(tmp_path, monkeypatch, capsys):
    r = make_repo(tmp_path, HEAD + GOOD + EMPTY_ID)  # 줄: 머리글 1 · 구분선 2 · R1 3 · R2 4 · 빈 ID 5
    monkeypatch.delenv(shape.MODE_ENV, raising=False)
    base = collect(r, tmp_path)
    assert base["malformed_requests"] == [] and capsys.readouterr().err == ""  # 기본 모드는 지금처럼 무시
    monkeypatch.setenv(shape.MODE_ENV, "report")
    o = collect(r, tmp_path)
    assert o["malformed_requests"] == [{"id": "(빈 ID) 줄 5", "cells": 4}] and o["requests"] == base["requests"]
    assert capsys.readouterr().err.splitlines() == ["ERROR magazine: 형식 미달 요청 행 (빈 ID) 줄 5 (열 수 4 · 기대 7)"]


def test_l7_report_flags_row_without_closing_pipe_default_ignores_blank_and_separator_rows_are_not_flagged(tmp_path, monkeypatch, capsys):
    r = make_repo(tmp_path, HEAD + GOOD + "|  |  | 요청 요지\n|  |  |  |\n|---|:--|\n")  # 줄 5 = 끝 '|' 없는 줄 · 6·7 = 빈 줄/구분선
    monkeypatch.delenv(shape.MODE_ENV, raising=False)
    assert collect(r, tmp_path)["malformed_requests"] == [] and capsys.readouterr().err == ""
    monkeypatch.setenv(shape.MODE_ENV, "report")
    assert collect(r, tmp_path)["malformed_requests"] == [{"id": "(빈 ID) 줄 5", "cells": 2}]
    assert capsys.readouterr().err.splitlines() == ["ERROR magazine: 형식 미달 요청 행 (빈 ID) 줄 5 (열 수 2 · 기대 7)"]


def test_l5_ledger_blob_read_failure_raises_even_in_report_mode(tmp_path, monkeypatch):
    monkeypatch.setenv(shape.MODE_ENV, "report")
    r = make_repo(tmp_path, HEAD + GOOD)
    (r / "design/harness/REQUEST-LEDGER.md").unlink()
    subprocess.run(["git", "-C", str(r), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "rm"], check=True, capture_output=True)
    infos = mcd.resolve_refs(r, ["main"], START, datetime.now(KST))
    with pytest.raises(MagazineError):
        mco.collect_open(r, infos, tmp_path, START, END)
