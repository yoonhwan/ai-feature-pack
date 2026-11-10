"""mirror_threads — 수신 데몬(byz_slack_mbox_inbound)이 «루트 목록 밖에서» 읽을 스레드를 고른다.

R242 단계 2: 루트가 읽는 창(7일)보다 오래된 스레드도 «마지막 답 시각»(원장 seen 값)이 THREAD_KEEP 안이면
그 뒤 답글만 읽는다(③). 조회 실패 스레드는 seen 을 그대로 두고 다음 회에 다시 읽는다(놓침 0).
보탬(호출 예산): ③ 는 데몬마다 THREAD_EVERY_S 에 1회 · 1회 THREAD_CAP 개 · «마지막 확인(checked) 오래된 순» 순환.
"""
from __future__ import annotations  # mini python 3.9.6 — `str | None` 주석을 문자열로 미룬다

import math
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import mirror_humans as mh
import mirror_lib as lib
import mirror_questions as mq

THREAD_KEEP = 14 * 86400  # 마지막 답이 이보다 오래된 스레드는 더 읽지 않는다(알려진 한계 · .out 1줄)
THREAD_EVERY_S = 60.0  # ③ 주기 — 그 사이 패스는 ③ 호출 0(분당 replies 약 240 → 데몬당 5)
THREAD_CAP = 5  # ③ 1회 조회 스레드 수
THREAD_BUDGET_S = 56.0  # 하드 룰 12 배치 상한 70초 − 마지막 호출 최악 14초(7초 + 재시도 1)
LATE_S = 600  # ③ 로 찾은 답이 이보다 늦게 가면 본문 첫 줄에 «[옛 글 …]»(R242 단계 3)
KST = timezone(timedelta(hours=9))


def mark_late(p: dict[str, object], m: dict[str, object]) -> dict[str, object]:
    """③ 로 찾은 답이 LATE_S 넘게 늦었으면 계획에 머리 1줄(late)을 고정한다 — 재시도 때도 같은 본문 · ①② 경로는 그대로."""
    age = time.time() - float(str(m["ts"]))
    if m.get("via") != "old" or age <= LATE_S:
        return p
    late = f"{int(age // 3600)}시간" if age >= 3600 else f"{int(age // 60)}분"
    return {**p, "late": f"[옛 글 {datetime.fromtimestamp(float(str(m['ts'])), KST).strftime('%m-%d %H:%M')} · {late} 늦게]"}


def add_open(threads: dict[str, str | None], qpath: Path) -> None:
    """열린 질문의 스레드는 루트 순위와 무관하게 항상 읽는다."""
    for e in mq.load(qpath)["open"].values():
        if e.get("thread_ts"):
            threads.setdefault(str(e["thread_ts"]), None)


def _pick(seen: dict[str, str], checked: dict[str, str], skip: set[str], now: float) -> list[str]:
    """오래된 seen 은 원장에서 내리고(닫는 사건 · checked 도 같이) 남은 대상을 «마지막 확인 오래된 순»(동률 = 최근 답 순)."""
    stale = [t for t, v in seen.items() if float(v) < now - THREAD_KEEP]
    for t in stale:
        del seen[t]
        checked.pop(t, None)
    if stale:
        print(f"오래된 스레드 건너뜀 {len(stale)} — 마지막 답 {THREAD_KEEP // 86400}일 넘음(알려진 한계)", flush=True)
    return sorted((t for t in seen if t not in skip), key=lambda t: (float(checked.get(t, 0)), -float(seen[t])))


def _read_one(inb: Any, t: str, oldest: str) -> list[dict[str, object]] | None:
    a = inb.a
    try:
        return lib.paged(a.api_base, inb.token, "conversations.replies", {"channel": a.channel, "ts": t, "oldest": oldest, "limit": 200})
    except lib.MirrorError as e:
        print(f"ERROR: 스레드 {t} 답글 조회 실패 — 다음 회 첫 자리로 다시 읽어요({e})", file=sys.stderr)
        return None


def read_old(inb: Any, st: dict[str, Any], skip: set[str], floor: str, found: dict[str, dict[str, object]]) -> None:
    """S1 ③ · S2 그 뒤 답글만 · S3 seen 갱신은 inb.seen_updates(후보를 원장에 올린 뒤 반영) · B5~B8 호출 예산."""
    now = time.time()
    if now - float(st.get("thread_at", 0)) < THREAD_EVERY_S:
        return
    st["thread_at"] = f"{now:.6f}"
    seen, checked = st["seen"], st.setdefault("checked", {})
    order = _pick(seen, checked, skip, now)
    ok, failed, t0 = 0, 0, time.monotonic()
    for t in order[:THREAD_CAP]:
        if time.monotonic() - t0 >= THREAD_BUDGET_S:
            break
        msgs = _read_one(inb, t, max(floor, seen[t]))
        if msgs is None:
            failed += 1
            continue
        ok, checked[t] = ok + 1, f"{time.time():.6f}"
        replies = [m for m in msgs if str(m["ts"]) != t and str(m["ts"]) > seen[t]]
        for m in replies:
            if str(m["ts"]) > floor and mh.allowed(m, inb.humans, inb.a.channel, log=not inb.a.human):
                found[str(m["ts"])] = {**m, "thread_ts": t, "via": "old"}
        if replies:
            inb.seen_updates[t] = max(str(m["ts"]) for m in replies)
    tail = f" · 스레드 미확인 {failed}(다음 회 첫 자리)" if failed else ""
    print(f"③ 스레드 순환 확인 {ok}/대상 {len(order)} · 한 바퀴 약 {math.ceil(len(order) / THREAD_CAP)}분{tail}", flush=True)
