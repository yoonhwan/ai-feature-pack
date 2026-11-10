"""공통 머리표·접두 처리 — Slack 미러와 직접 게시 진입점에서 함께 쓴다."""
from __future__ import annotations

import re


_PREFIX = re.compile(r"^\s*\[[^\]]*->[^\]]*\]\s*")
_TAG = re.compile(r"^\s*\[(HIL|BLOCK|긴급)\]\s*", re.IGNORECASE)
DESK_HEADS = ("HIL", "BLOCK", "긴급", "결정 대기", "결정")
_DESK_HEAD = re.compile(r"^\s*\[(" + "|".join(map(re.escape, DESK_HEADS)) + r")\]", re.IGNORECASE)
_GOAL_COORDINATE = re.compile(r"^\s*골좌표:\s*\d+\s*—")


def _is_counter_line(line: str) -> bool:
    import status_head

    return bool(status_head.SHAPE.match(line) or line.startswith(status_head.CANNOT))


def strip_lead(text: str) -> tuple[str, str]:
    """routing 접두 뒤의 연속한 골좌표·카운팅·빈 줄과 나머지를 나눈다."""
    body = _PREFIX.sub("", text, count=1)
    lines = body.splitlines(keepends=True)
    count = 0
    for line in lines:
        plain = line.rstrip("\r\n")
        if not plain.strip() or _GOAL_COORDINATE.match(plain) or _is_counter_line(plain):
            count += 1
        else:
            break
    return "".join(lines[:count]), "".join(lines[count:])


def classify(body: str) -> tuple[str, str]:
    """(라벨, 게시 본문) — 접두 줄은 보존하고 태그만 뗀다."""
    lead, rest = strip_lead(body)
    match = _TAG.match(rest)
    return (match.group(1).upper(), lead + rest[match.end():]) if match else ("보고", lead + rest)


def desk_head(text: str) -> str | None:
    """골좌표·카운팅 줄 뒤 첫 태그를 돌려준다."""
    _, rest = strip_lead(text)
    match = _DESK_HEAD.match(rest)
    return match.group(1).upper() if match else None
