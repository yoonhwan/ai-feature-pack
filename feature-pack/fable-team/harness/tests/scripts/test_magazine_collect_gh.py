"""아침 매거진 ① gh 수집 시험 — 설계 §9-4 (PATH 가짜 gh · 실 GitHub 0)."""
import json
import os
import stat
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
sys.path.insert(0, str(KIT))
import magazine_collect_gh as mgh  # noqa: E402
from magazine_window import MagazineError  # noqa: E402

KST = ZoneInfo("Asia/Seoul")
START = datetime(2026, 10, 7, 8, tzinfo=KST)
END = datetime(2026, 10, 8, 8, tzinfo=KST)


def fake_gh(tmp_path: Path, monkeypatch, script_body: str) -> Path:
    """PATH 맨 앞에 가짜 gh. 인자는 args.log 에 한 줄씩 남는다."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    gh = bin_dir / "gh"
    gh.write_text(f"#!/bin/sh\necho \"$@\" >> '{tmp_path}/args.log'\n{script_body}\n", encoding="utf-8")
    gh.chmod(gh.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    return tmp_path / "args.log"


def issues(prefix: str, n: int, state: str) -> str:
    return json.dumps([{"number": i, "title": f"{prefix}{i}", "state": state, "url": f"https://x/{i}"} for i in range(1, n + 1)])


def test_opened_and_closed_split_by_search_query(tmp_path, monkeypatch):
    log = fake_gh(tmp_path, monkeypatch, f"""
case "$*" in
  *closed:*) echo '{issues("닫힘", 2, "CLOSED")}' ;;
  *created:*) echo '{issues("열림", 3, "OPEN")}' ;;
  *) exit 9 ;;
esac""")
    out = mgh.collect_gh("Org/repo", START, END)
    assert [i["number"] for i in out["issues_opened"]] == [1, 2, 3]
    assert [i["number"] for i in out["issues_closed"]] == [1, 2]
    assert set(out["issues_opened"][0]) == {"number", "title", "state", "url"}
    calls = log.read_text(encoding="utf-8")
    assert "created:2026-10-06T23:00:00Z..2026-10-07T23:00:00Z" in calls  # KST→UTC
    assert "closed:2026-10-06T23:00:00Z..2026-10-07T23:00:00Z" in calls
    assert "--repo Org/repo" in calls and "--limit 300" in calls
    assert "--state closed" in calls


def test_rc_nonzero_raises(tmp_path, monkeypatch):
    fake_gh(tmp_path, monkeypatch, "echo 'boom' >&2; exit 1")
    with pytest.raises(MagazineError, match="gh"):
        mgh.collect_gh("Org/repo", START, END)


def test_non_json_raises(tmp_path, monkeypatch):
    fake_gh(tmp_path, monkeypatch, "echo '<html>not json</html>'")
    with pytest.raises(MagazineError, match="JSON"):
        mgh.collect_gh("Org/repo", START, END)


def test_json_not_a_list_raises(tmp_path, monkeypatch):
    fake_gh(tmp_path, monkeypatch, "echo '{\"a\": 1}'")
    with pytest.raises(MagazineError, match="JSON"):
        mgh.collect_gh("Org/repo", START, END)


def test_300_results_raises_instead_of_truncating(tmp_path, monkeypatch):
    fake_gh(tmp_path, monkeypatch, f"echo '{issues('열림', 300, 'OPEN')}'")
    with pytest.raises(MagazineError, match="300"):
        mgh.collect_gh("Org/repo", START, END)


def test_gh_not_installed_raises(tmp_path, monkeypatch):
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(MagazineError, match="gh"):
        mgh.collect_gh("Org/repo", START, END)
