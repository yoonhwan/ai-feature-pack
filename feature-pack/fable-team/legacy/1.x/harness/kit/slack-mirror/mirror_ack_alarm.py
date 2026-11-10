"""mirror_ack_alarm — desk 미읽음 경보의 단계 (R241 · DA⑥ H2). 호출 = mirror_ack.watch → step(항목마다 한 걸음).

순서: ① planner 쪽지 먼저 — 성공 alarm_planner_seq · 결과 불명(MboxError.rc 가 None=시간 초과·실행 실패 또는 0=QUEUED 없음) alarm_planner_unsure(재전송 0 · 슬랙 줄 0) · 명시 실패는 기록 없이 다음 패스에 재시도
      ② planner 성공 «뒤에만» 슬랙 «planner 에 알렸어요» 줄 — 성공 alarm_slack_ts · 실패는 다음 패스에 재시도(쪽지는 다시 보내지 않는다)
"""
import os
import sys
import time
from pathlib import Path

import mirror_inbound as ib
import mirror_lib as lib
import mirror_share as ms

ACK_SEC = 180  # FT_DESK_ACK_SEC · 시계 대역 FT_ACK_NOW(시험)


def _now() -> float:
    return float(os.environ.get("FT_ACK_NOW") or time.time())


def _unread(inb, ts: str, e: dict) -> bool | None:
    """desk 대기 큐에 그 쪽지 토큰이 남았나. 큐를 못 읽으면 None(모름)."""
    role = e["recips"][0]
    to = e["done"].get(role)
    if not (Path(inb.comm) / "mailbox.jsonl").exists() or not to:
        return None
    return ib.queue_has(inb.comm, f"slack:{ts}:{role}", to) or ib.queue_has(inb.comm, f"slack:{ts}:{to}", to)


def step(inb, st: dict, ts: str, e: dict) -> None:
    if not e.get("ack_ts") or e.get("alarm_slack_ts"):
        return
    sec = int(os.environ.get("FT_DESK_ACK_SEC") or ACK_SEC)
    if not (e.get("alarm_planner_seq") or e.get("alarm_planner_unsure")):  # 경보 시작 전 — 읽음/시간 판단
        if e.get("read_seen"):
            return
        unread = _unread(inb, ts, e)
        if unread is None:
            print(f"ERROR: 오빠 글 {ts} desk 대기 큐를 조회하지 못해 경보 판단을 미뤘어요", file=sys.stderr)
            return
        if not unread:
            e["read_seen"] = True
            inb._save(st)
            return
        waited = _now() - float(e["ack_at"])
        if waited < sec:
            return
        _planner(inb, st, ts, e, int(waited // 60))
    if e.get("alarm_planner_seq"):
        try:
            e["alarm_slack_ts"] = lib.post(inb.a.api_base, inb.token, inb.a.channel, f"desk 가 다른 일 중이라 {sec // 60}분째 못 읽었어요 — planner 에 알렸어요", e.get("thread") or ts)
        except lib.MirrorError as err:
            print(f"ERROR: 오빠 글 {ts} 미읽음 경보 슬랙 게시 실패(다음 패스에 재시도): {err}", file=sys.stderr)
        inb._save(st)


def _planner(inb, st: dict, ts: str, e: dict, mins: int) -> None:
    name, why = ms.live_planner(inb.planner_seats)
    if name is None:
        print(f"ERROR: 오빠 글 {ts} 경보 — planner 현역 세션 확인 불가({why}) · 다음 패스에 재시도", file=sys.stderr)
        return
    try:
        e["alarm_planner_seq"] = ib.send(inb.a.mbox, name, f"[{ib.FROM}->{name}] [desk 대기 경보] 오빠 글 {ts} · 쪽지 {e.get('mbox_seq', '?')} · {mins}분 미읽음", inb.spool)
    except ib.MboxError as err:
        if err.rc in (None, 0):  # 시간 초과·실행 실패·rc 0 인데 QUEUED 없음 = 보냈는지 모른다 — 다시 보내지 않는다
            e["alarm_planner_unsure"] = True
            print(f"ERROR: 오빠 글 {ts} 경보 planner 쪽지 결과 불명(재전송 0): {err}", file=sys.stderr)
        else:
            print(f"ERROR: 오빠 글 {ts} 경보 planner 쪽지 실패(다음 패스에 재시도): {err}", file=sys.stderr)
    inb._save(st)
