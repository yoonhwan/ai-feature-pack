"""ft_news_watch — 뉴스 실행 잠금 + 신선도 경보 (R209 · 판정 1795). 쓰는 쪽은 ft_news_ledger.py.

잠금: v65 틱과 planner 전용 launchd 가 같은 분에 돌아도 한 쪽만 일한다(다른 쪽 = 0 으로 나간다).
경보: 마지막 발행(`news-publish/<날짜>/published.txt` mtime · 오늘 → 어제 순) 이 FT_NEWS_STALE_MIN(기본 180)분을 넘으면
`seats-planner.json` `_master` 에 mbox 1통 — 정지 1건당 1통(state/news-ledger/stale.notified) · 발행되면 그 표시를 지워 다시 장전하고, 표식은 «경보 당시 마지막 발행 식별자» 를 담아 관측 공백 사이에 새 발행이 있었으면 새 정지로 다시 울린다.
쪽지 실패 = ERROR 만 · 표시 0(다음 실행이 다시 시도).
"""
import fcntl
import json
import logging
import os
import subprocess
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path

LOG = logging.getLogger("ft_news_ledger")
STALE_MIN = 180


@contextmanager
def locked(state: Path):
    """yield True = 잠금 얻음 · False = 다른 실행이 일하는 중."""
    state.mkdir(parents=True, exist_ok=True)
    with open(state / ".lock", "w", encoding="utf-8") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def last_published(root: Path, now: datetime) -> tuple[datetime | None, str]:
    """(마지막 발행 시각, 식별자 «날짜:mtime_ns») — 오늘 → 어제 순 · 없으면 (None, "none")."""
    pub = root / ".fable-team" / "state" / "news-publish"
    for day in (now, now - timedelta(days=1)):
        if (f := pub / f"{day:%Y-%m-%d}" / "published.txt").exists():
            st = f.stat()
            return datetime.fromtimestamp(st.st_mtime), f"{day:%Y-%m-%d}:{st.st_mtime_ns}"
    return None, "none"


def check_stale(root: Path, state: Path, now: datetime, why: str) -> None:
    try:
        _check(root, state, now, why)
    except (OSError, ValueError, KeyError) as e:
        LOG.error("뉴스 정지 경보 건너뜀: %s", e)


def _check(root: Path, state: Path, now: datetime, why: str) -> None:
    limit = int(os.environ.get("FT_NEWS_STALE_MIN", STALE_MIN))
    (last, ident), mark = last_published(root, now), state / "stale.notified"
    age = int((now - last).total_seconds() // 60) if last else None
    if age is not None and age <= limit:
        mark.unlink(missing_ok=True)
        return
    if mark.exists() and mark.read_text(encoding="utf-8").splitlines()[-1] == f"ident={ident}":
        return  # 같은 정지 사건 — 표식에 묶인 «마지막 발행» 이 그대로다(다른 발행이 있었으면 새 사건 = 다시 울림)
    master = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))["_master"]
    msg = f"[뉴스 정지 {age if age is not None else '?'}분 · 마지막 {last:%H:%M}" if last else "[뉴스 정지 ?분 · 마지막 기록 없음"
    msg += f" · 원인 칸: {why}]"
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    if subprocess.run(["bash", mbox, "send", master, "ft-news-ledger", msg], capture_output=True, check=False).returncode != 0:
        LOG.error("뉴스 정지 경보 쪽지 실패 — 다음 실행에 다시")
        return
    mark.write_text(f"{msg}\nident={ident}\n", encoding="utf-8")
