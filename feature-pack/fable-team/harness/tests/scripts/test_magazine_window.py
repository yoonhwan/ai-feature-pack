"""아침 매거진 ① 창 계산 시험 — 설계 §9-1 (네트워크·실 파일 0)."""
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
sys.path.insert(0, str(KIT))
import magazine_window as mw  # noqa: E402

KST = ZoneInfo("Asia/Seoul")


def at(y, mo, d, h, mi=0):
    return datetime(y, mo, d, h, mi, tzinfo=KST)


def test_manual_date_gives_previous_0800_to_0800():
    d, start, end = mw.window("2026-10-08", at(2026, 10, 8, 9, 30))
    assert d == "2026-10-08"
    assert start == at(2026, 10, 7, 8)
    assert end == at(2026, 10, 8, 8)
    assert start.utcoffset().total_seconds() == 9 * 3600


def test_scheduled_after_0800_same_day_picks_today():
    d, start, end = mw.window(None, at(2026, 10, 8, 9, 30))
    assert (d, start, end) == ("2026-10-08", at(2026, 10, 7, 8), at(2026, 10, 8, 8))


def test_scheduled_exactly_0800_picks_today():
    d, _, _ = mw.window(None, at(2026, 10, 8, 8, 0))
    assert d == "2026-10-08"


def test_scheduled_wake_next_day_before_0800_picks_last_closed_window():
    """10-08 07:00 잠듦 → 10-09 07:30 깸: 예정일은 10-08 (DA HOLD-M2)."""
    d, start, end = mw.window(None, at(2026, 10, 9, 7, 30))
    assert (d, start, end) == ("2026-10-08", at(2026, 10, 7, 8), at(2026, 10, 8, 8))


def test_now_in_utc_is_converted_to_kst():
    utc_now = datetime(2026, 10, 8, 0, 30, tzinfo=ZoneInfo("UTC"))  # = 09:30 KST
    d, _, _ = mw.window(None, utc_now)
    assert d == "2026-10-08"


def test_manual_future_window_raises():
    with pytest.raises(mw.MagazineError, match="닫히지"):
        mw.window("2026-10-09", at(2026, 10, 9, 7, 59))


def test_manual_date_exactly_at_close_is_allowed():
    d, _, end = mw.window("2026-10-09", at(2026, 10, 9, 8, 0))
    assert (d, end) == ("2026-10-09", at(2026, 10, 9, 8))


def test_bad_date_string_raises():
    with pytest.raises(mw.MagazineError):
        mw.window("2026/10/08", at(2026, 10, 9, 9))


def test_naive_now_raises():
    with pytest.raises(mw.MagazineError, match="tz"):
        mw.window(None, datetime(2026, 10, 9, 9))


def test_skipped_days_between_last_published_and_d():
    assert mw.skipped_days("2026-10-06", "2026-10-08") == ["2026-10-07"]
    assert mw.skipped_days("2026-10-04", "2026-10-08") == ["2026-10-05", "2026-10-06", "2026-10-07"]


def test_skipped_days_none_when_adjacent_none_or_not_published():
    assert mw.skipped_days("2026-10-07", "2026-10-08") == []
    assert mw.skipped_days(None, "2026-10-08") == []
    assert mw.skipped_days("2026-10-08", "2026-10-08") == []
