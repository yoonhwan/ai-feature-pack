"""magazine_window — 아침 매거진 창 계산 (설계 DESIGN-morning-magazine-20261008 §1).

창 = (D-1) 08:00 ~ D 08:00 KST. D 고르기:
- date=None(예약·launchd) → «마지막으로 닫힌 08:00 경계»의 날짜 (now<08:00 이면 어제).
- date 명시(수동)       → 그 날짜 그대로. end 가 now 보다 뒤면 raise (창이 안 닫힘).
"""
from datetime import date as _date
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

KST = ZoneInfo("Asia/Seoul")
CLOSE_HOUR = 8


class MagazineError(RuntimeError):
    pass


def _close_of(d: _date) -> datetime:
    return datetime(d.year, d.month, d.day, CLOSE_HOUR, tzinfo=KST)


def bounds(day: str) -> tuple[datetime, datetime]:
    """D 의 (start, end) — 닫힘 여부는 보지 않는다(window 가 본다)."""
    try:
        d = _date.fromisoformat(day)
    except ValueError as e:
        raise MagazineError(f"날짜 형식이 YYYY-MM-DD 가 아니에요: {day!r}") from e
    return _close_of(d - timedelta(days=1)), _close_of(d)


def window(date: str | None, now: datetime) -> tuple[str, datetime, datetime]:
    if now.tzinfo is None:
        raise MagazineError("now 에 tz 가 없어요 — tz-aware datetime 만 받아요")
    kst_now = now.astimezone(KST)
    if date is None:
        last_close = _close_of(kst_now.date())
        day = kst_now.date() if kst_now >= last_close else kst_now.date() - timedelta(days=1)
        date = day.isoformat()
    start, end = bounds(date)
    if end > kst_now:
        raise MagazineError(f"창이 아직 닫히지 않았어요: {date} 창 끝 {end.isoformat()} > 지금 {kst_now.isoformat()}")
    return date, start, end


def skipped_days(last_published: str | None, day: str) -> list[str]:
    """마지막 발행일과 D 사이에 빈 날(양끝 제외). 발행 이력이 없으면 빈 목록."""
    if last_published is None:
        return []
    last, target = _date.fromisoformat(last_published), _date.fromisoformat(day)
    return [(last + timedelta(days=i)).isoformat() for i in range(1, (target - last).days)]
