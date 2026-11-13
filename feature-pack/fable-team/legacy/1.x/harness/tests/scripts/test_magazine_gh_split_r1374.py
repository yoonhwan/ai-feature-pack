"""r1374 — gh 목록이 300건 상한에 닿으면 창을 반으로 나눠 다시 읽는다 (PATH 가짜 gh · 실 GitHub 0).

가짜 gh = 고정 Issue 목록(number·시각)에서 --search 창(양끝 포함)에 든 것만 --limit 까지 잘라 낸다.
"""
import json
import os
import stat
import subprocess
import sys
import types
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
sys.path.insert(0, str(KIT))
import magazine_collect_gh as mgh  # noqa: E402
from magazine_window import MagazineError  # noqa: E402

START = datetime(2026, 11, 2, 23, tzinfo=timezone.utc)
END = START + timedelta(days=1)
MID = START + timedelta(hours=12)

FAKE_GH = r'''#!/usr/bin/env python3
import json, sys
from datetime import datetime
args = sys.argv[1:]
open(LOG, "a", encoding="utf-8").write(" ".join(args) + "\n")
query = args[args.index("--search") + 1]
limit = int(args[args.index("--limit") + 1])
lo, hi = query.split(":", 1)[1].split("..")
p = lambda s: datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
rows = [r for r in json.load(open(DATA, encoding="utf-8")) if p(lo) <= p(r["at"]) <= p(hi)]
print(json.dumps([{"number": r["number"], "title": "t%d" % r["number"], "state": "CLOSED", "url": "u"} for r in rows[:limit]]))
'''


def _z(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def fake_gh(tmp_path: Path, monkeypatch, stamps: list[datetime]) -> Path:
    data = tmp_path / "issues.json"
    data.write_text(json.dumps([{"number": i + 1, "at": _z(t)} for i, t in enumerate(stamps)]), encoding="utf-8")
    log = tmp_path / "args.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    gh = bin_dir / "gh"
    gh.write_text(FAKE_GH.replace("LOG", repr(str(log)), 1).replace("DATA", repr(str(data)), 1), encoding="utf-8")
    gh.chmod(gh.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    return log


def spread(n: int) -> list[datetime]:
    """창 안에 고르게 n건(경계 정확히 위는 피함)."""
    step = timedelta(days=1) / (n + 1)
    return [START + step * (i + 1) + timedelta(seconds=7) for i in range(n)]


def calls(log: Path) -> list[str]:
    return log.read_text(encoding="utf-8").splitlines()


def numbers(rows: list[dict]) -> list[int]:
    return [int(r["number"]) for r in rows]


def test_g1_day_with_344_closed_collects_all(tmp_path, monkeypatch):
    log = fake_gh(tmp_path, monkeypatch, spread(344))
    out = mgh.collect_gh("Org/repo", START, END)
    for key in ("issues_opened", "issues_closed"):
        got = numbers(out[key])
        assert sorted(got) == list(range(1, 345)), key
        assert len(got) == len(set(got)), key
    assert len(calls(log)) <= 2 * 8  # 조각 2~3개 · 폭주 0


def test_g2_issue_on_slice_border_appears_once(tmp_path, monkeypatch):
    stamps = spread(299) + [MID]  # 300건 → 반으로 나뉨 · MID 는 두 조각 모두에 든다
    fake_gh(tmp_path, monkeypatch, stamps)
    out = mgh.collect_gh("Org/repo", START, END)
    got = numbers(out["issues_closed"])
    assert got.count(300) == 1
    assert sorted(got) == list(range(1, 301))


def test_g3_one_hour_slice_still_at_limit_raises(tmp_path, monkeypatch):
    burst = [START + timedelta(hours=5, seconds=i) for i in range(300)]  # 5분 안에 300건
    log = fake_gh(tmp_path, monkeypatch, burst)
    with pytest.raises(MagazineError, match="잘린 목록"):
        mgh.collect_gh("Org/repo", START, END)
    assert len(calls(log)) <= 8  # 1시간 조각에서 멈춤 · 무한 재귀 0


def test_g4_small_day_one_call_per_list(tmp_path, monkeypatch):
    log = fake_gh(tmp_path, monkeypatch, spread(10))
    out = mgh.collect_gh("Org/repo", START, END)
    assert numbers(out["issues_closed"]) == list(range(1, 11))
    assert numbers(out["issues_opened"]) == list(range(1, 11))
    lines = calls(log)
    assert len(lines) == 2
    span = f"{_z(START)}..{_z(END)}"
    assert any(f"closed:{span}" in c and "--limit 300" in c for c in lines)
    assert any(f"created:{span}" in c for c in lines)


def test_g5_gh_timeout_retries_once_then_raises(monkeypatch):
    seen: list[float] = []

    def slow(cmd, **kw):
        seen.append(kw.get("timeout"))
        raise subprocess.TimeoutExpired(cmd, kw.get("timeout"))

    stub = types.SimpleNamespace(run=slow, TimeoutExpired=subprocess.TimeoutExpired)
    monkeypatch.setattr(mgh, "subprocess", stub)  # 이 모듈만 · 전역 subprocess 그대로
    with pytest.raises(MagazineError, match="gh"):
        mgh.collect_gh("Org/repo", START, END)
    assert len(seen) == 2  # 1회 + 재시도 1
    assert all(t is not None and t <= 7 for t in seen)  # 하드 룰 12
