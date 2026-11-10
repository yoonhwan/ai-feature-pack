"""mirror_marker — Slack 스레드에서 재개 표식을 찾는다."""
from __future__ import annotations

import re

import mirror_lib as lib


def thread_texts(base: str, token: str, channel: str, thread_ts: str, limit: int = 100) -> list[str]:
    params = {"channel": channel, "ts": thread_ts, "limit": limit}
    messages = lib.paged(base, token, "conversations.replies", params)
    return [str(message.get("text", "")) for message in messages]


def has_marker(texts: list[str], marker: str) -> bool:
    pat = re.compile(re.escape(marker) + r"(?!\d)")
    return any(pat.search(text) for text in texts)
