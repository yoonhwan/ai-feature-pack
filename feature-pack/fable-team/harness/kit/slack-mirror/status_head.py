"""status_head — 사람 채널 슬랙 글 맨 앞에 붙는 «카운팅 머리줄» (r1089 · 오빠 지시 2026-10-28).

planner 틱이 30 분마다 갱신하는 TEAM-STATUS.md 첫 줄(`스크립트 N · 인터뷰 N · 막힌 팀 대기 N`)을 그대로 옮긴다.
그 줄이 낡았으면 끝에 ` (낡음 N분)` 을 붙이고, 파일이 없거나 못 읽거나 형식이 다르면 `카운팅 확인 불가(사유)` 를 낸다
— 조용히 빼지 않는다(#0 RULE). 파일 읽기만 한다(슬랙·명부 쓰기 0).
"""
from __future__ import annotations  # mini python 3.9.6 — `float | None` 주석을 문자열로 미뤄 import TypeError 를 막는다

import logging
import os
import re
import time
from pathlib import Path

from post_guard import DEFAULT_ROOT, ROOT_ENV  # 루트 규칙은 한 곳(post_guard)에만 둔다

FILE_ENV = "FT_TEAM_STATUS_FILE"
STALE_ENV = "FT_TEAM_STATUS_STALE_MIN"
DEFAULT_STALE_MIN = 30.0
REL_PATH = Path(".fable-team") / "state" / "planner-tick" / "TEAM-STATUS.md"
SHAPE = re.compile(r"^스크립트 \d+ · 인터뷰 \d+ · 막힌 팀 대기 \d+")
CANNOT = "카운팅 확인 불가"


def path() -> Path:
    """env FT_TEAM_STATUS_FILE 우선 · 없으면 <루트>/TEAM-STATUS.md (루트 = post_guard 와 같은 규칙)."""
    return Path(os.environ.get(FILE_ENV) or (Path(os.environ.get(ROOT_ENV) or DEFAULT_ROOT) / REL_PATH))


def stale_minutes() -> float:
    try:
        return float(os.environ.get(STALE_ENV) or DEFAULT_STALE_MIN)
    except ValueError:
        logging.getLogger(__name__).warning("status_head: %s 값이 숫자 아님 — 기본 %s분", STALE_ENV, DEFAULT_STALE_MIN)
        return DEFAULT_STALE_MIN


def cannot(reason: str) -> str:
    logging.getLogger(__name__).error("status_head: %s — %s", CANNOT, reason)
    return f"{CANNOT}({reason})"


def head(now: float | None = None) -> str:
    """머리줄 1줄. now = 초 단위 시각(기본 지금) — 시험이 고정값을 넣는다."""
    f = path()
    try:
        first = f.read_text(encoding="utf-8").splitlines()[0].strip()
        age = ((time.time() if now is None else now) - f.stat().st_mtime) / 60
    except FileNotFoundError:
        return cannot("파일 없음")
    except (OSError, UnicodeDecodeError, IndexError):
        return cannot("읽기 실패")
    if not SHAPE.match(first):
        return cannot("형식")
    return f"{first} (낡음 {int(age)}분)" if age > stale_minutes() else first
