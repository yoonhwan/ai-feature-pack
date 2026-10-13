"""ft_api_outage_util.py — ft_api_outage.py 의 형제 모듈: 오류 문구 분류·해제 근거 파싱 + 수신자 공용 notify 잠금 (R146).

잠금 = 수신자별 공용 notify 상태의 «읽기 → 발신 → 성공 기록» 을 한 프로세스만 하게 하는 fcntl.flock 1개(macOS 에 flock 명령 없음).
대기 상한은 7초 룰 — 넘으면 yield False(건너뛰기 아님: 호출 쪽이 ERROR 1줄 + 발신 0 + 다음 틱 재시도).
"""
import fcntl
import re
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

CAUSES = (("rate_limit", "rate_limit|limit reached"), ("oauth_not_allowed", "OAuth authentication is currently not allowed"),
          ("subscription_disabled", "disabled Claude subscription access"))
Rec = dict[str, object]


def hhmm(epoch: int) -> str:
    return time.strftime("%H:%M", time.localtime(epoch))


def text_of(rec: Rec) -> str:
    msg = rec.get("message")
    parts = msg.get("content") if isinstance(msg, dict) else None  # pyright: ignore[reportUnknownMemberType]
    body = " ".join(str(p.get("text", "")) for p in parts if isinstance(p, dict)) if isinstance(parts, list) else ""  # pyright: ignore[reportUnknownVariableType,reportUnknownMemberType,reportUnknownArgumentType]
    return f"{body} {rec.get('error', '')}"


def cause_of(rec: Rec) -> str:
    return next((n for n, pat in CAUSES if re.search(pat, text_of(rec))), "기타")


def reset_of(rec: Rec, ts: int) -> str:
    """문구의 해제 근거 → «HH:MM (문구: resets 3am, retry after 120s)» · 근거 없으면 빈 문자열."""
    text, basis, eta = text_of(rec), [], ""
    if m := re.search(r"resets?\s*(?:at\s*)?(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)", text, re.I):
        eta = m.group(1).strip()
        basis.append(f"resets {eta}")
    if m := re.search(r"retry[\s_-]*after\s*(\d+)\s*(min\w*|m\b|s\w*)?", text, re.I):
        mins = (m.group(2) or "s").lower().startswith("m")
        basis.append(f"retry after {m.group(1)}{'min' if mins else 's'}")
        eta = eta or hhmm(ts + int(m.group(1)) * (60 if mins else 1))
    return f"{eta} (문구: {', '.join(basis)})" if basis else ""


@contextmanager
def locked(path: Path, timeout: float = 7.0) -> Iterator[bool]:
    """path 에 배타 잠금 — 얻으면 True · timeout 초 안에 못 얻으면 False(잠금 없음)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as fh:
        end, got = time.monotonic() + timeout, False
        while not got:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)  # GUARD:flock
                got = True
            except BlockingIOError:
                if time.monotonic() >= end:
                    break
                time.sleep(0.05)
        try:
            yield got
        finally:
            if got:
                fcntl.flock(fh, fcntl.LOCK_UN)
