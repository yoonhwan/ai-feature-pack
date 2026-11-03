"""mirror_threads — 수신 데몬(byz_slack_mbox_inbound)이 «루트 목록 밖에서» 읽을 스레드를 고른다."""
from __future__ import annotations  # mini python 3.9.6 — `str | None` 주석을 문자열로 미룬다

from pathlib import Path

import mirror_questions as mq


def add_open(threads: dict[str, str | None], qpath: Path) -> None:
    """열린 질문의 스레드는 루트 순위와 무관하게 항상 읽는다."""
    for e in mq.load(qpath)["open"].values():
        if e.get("thread_ts"):
            threads.setdefault(str(e["thread_ts"]), None)
