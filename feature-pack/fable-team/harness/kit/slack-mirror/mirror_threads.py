"""mirror_threads — 수신 데몬(byz_slack_mbox_inbound)이 «루트 목록 밖에서» 읽을 스레드를 고른다.

R242 단계 2: 루트가 읽는 창(7일)보다 오래된 스레드도 «마지막 답 시각»(원장 seen 값)이 THREAD_KEEP 안이면
그 뒤 답글만 읽는다. 조회 실패·예산 초과 스레드는 seen 을 그대로 두고 다음 패스에 다시 읽는다(놓침 0).
"""
from __future__ import annotations  # mini python 3.9.6 — `str | None` 주석을 문자열로 미룬다

import sys
import time
from pathlib import Path
from typing import Any

import mirror_humans as mh
import mirror_lib as lib
import mirror_questions as mq

THREAD_KEEP = 14 * 86400  # 마지막 답이 이보다 오래된 스레드는 더 읽지 않는다(알려진 한계 · .out 1줄)
THREAD_CAP = 20  # 패스당 조회 스레드 상한 — 최근 답 순
THREAD_BUDGET_S = 56.0  # 하드 룰 12 배치 상한 70초 − 마지막 호출 최악 14초(7초 + 재시도 1)


def add_open(threads: dict[str, str | None], qpath: Path) -> None:
    """열린 질문의 스레드는 루트 순위와 무관하게 항상 읽는다."""
    for e in mq.load(qpath)["open"].values():
        if e.get("thread_ts"):
            threads.setdefault(str(e["thread_ts"]), None)


def _pick(seen: dict[str, str], skip: set[str], now: float) -> tuple[list[str], int]:
    """오래된 seen 은 원장에서 내리고(닫는 사건) 남은 것 중 루트 목록에 없는 스레드를 최근 답 순으로."""
    stale = [t for t, v in seen.items() if float(v) < now - THREAD_KEEP]
    for t in stale:
        del seen[t]
    if stale:
        print(f"오래된 스레드 건너뜀 {len(stale)} — 마지막 답 {THREAD_KEEP // 86400}일 넘음(알려진 한계)", flush=True)
    return sorted((t for t in seen if t not in skip), key=lambda t: float(seen[t]), reverse=True), len(stale)


def read_old(inb: Any, seen: dict[str, str], skip: set[str], floor: str, found: dict[str, dict[str, object]]) -> None:
    """S1 ③ · S2 그 뒤 답글만 · S3 seen 갱신은 inb.seen_updates(후보를 원장에 올린 뒤 반영) · S4 예산."""
    a = inb.a
    order, _ = _pick(seen, skip, time.time())
    unchecked, t0 = max(0, len(order) - THREAD_CAP), time.monotonic()
    for i, t in enumerate(order[:THREAD_CAP]):
        if time.monotonic() - t0 >= THREAD_BUDGET_S:
            unchecked += min(len(order), THREAD_CAP) - i
            break
        try:
            msgs = lib.paged(a.api_base, inb.token, "conversations.replies", {"channel": a.channel, "ts": t, "oldest": max(floor, seen[t]), "limit": 200})
        except lib.MirrorError as e:
            print(f"ERROR: 스레드 {t} 답글 조회 실패 — 다음 패스에 다시 읽어요({e})", file=sys.stderr)
            unchecked += 1
            continue
        replies = [m for m in msgs if str(m["ts"]) != t and str(m["ts"]) > seen[t]]
        for m in replies:
            if str(m["ts"]) > floor and mh.allowed(m, inb.humans, a.channel, log=not a.human):
                found[str(m["ts"])] = {**m, "thread_ts": t}
        if replies:
            inb.seen_updates[t] = max(str(m["ts"]) for m in replies)
    if unchecked:
        print(f"스레드 미확인 {unchecked} — 다음 패스에 다시(상한 {THREAD_CAP} · 예산 {THREAD_BUDGET_S:.0f}초)", flush=True)
