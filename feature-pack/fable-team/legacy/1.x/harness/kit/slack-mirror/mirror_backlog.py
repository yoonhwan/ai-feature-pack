"""mirror_backlog — 재시작·장애 뒤 «밀린 쪽지»가 상한을 넘으면 원문 대신 요약 1통(r739).

사건: 미러가 멈춰 있던 사이 쪽지가 2000건 쌓이자 다시 켜질 때 그걸 전부 올려 오빠 슬랙을 덮었다(오빠 1792659217).
묶음 판정: 게시 대상(수신 좌석 일치 · 오빠 글 아님) 중 last_seq 뒤에 남은 수가 상한을 «넘으면» 하나씩 올리지 않는다.
건너뛴 사실은 요약 1통으로 보인다 — 조용히 버리는 것이 아니다(원문은 mbox 원장에 그대로 있다).
"""
from __future__ import annotations  # mini python 3.9 — `X | None` 주석 import TypeError 방지

import re

import mirror_lib as lib
import mirror_desk as desk


def is_target(row: dict[str, object], seat: re.Pattern[str], urgent: re.Pattern[str] | None = None,
              urgent_senders: frozenset[str] = frozenset()) -> bool:
    """게시 대상 행인가 — byz_mbox_slack_mirror._row 와 같은 조건(오빠 글 = 메아리 금지). urgent 좌석 앞은 머리 태그 [긴급] 인 행만(r1257)."""
    if str(row.get("from", "")) == "slack-oppa":
        return False
    to = str(row.get("to", ""))
    return bool(seat.search(to)) or bool(urgent and urgent.search(to) and
                (lib.classify(str(row.get("body", "")))[0] == "긴급" or desk.urgent_from(row, urgent_senders)))


def pick(rows: list[dict[str, object]], last_seq: int, seat: re.Pattern[str], max_n: int,
         urgent: re.Pattern[str] | None = None, urgent_senders: frozenset[str] = frozenset(),
         desk_on: bool | None = None) -> list[int]:
    """밀린 게시 대상 seq 목록 — 상한을 넘을 때만 돌려준다(그 외 빈 목록 = 지금처럼 한 줄씩)."""
    if max_n <= 0:  # 0 이면 묶음 끔
        return []
    enabled = bool(urgent_senders) if desk_on is None else desk_on
    seqs = [int(str(r["seq"])) for r in rows if int(str(r["seq"])) > last_seq and
            is_target(r, seat, urgent, urgent_senders) and not desk.wants_desk(r, urgent_senders, enabled)]
    return seqs if len(seqs) > max_n else []


def format_skip(n: int, first: int, last: int) -> str:
    return (f"[상태] 슬랙 미러가 밀린 쪽지 {n}건을 건너뛰었어요(seq {first}~{last}) — 원문은 mbox 원장에 있어요\n"
            f"할 일 없음 — 다음 쪽지부터 다시 올려요\n(mirror · #BACKLOG-{first}-{last})")


def format_gap(first: int, last: int) -> str:
    n = last - first + 1
    return (f"[상태] 슬랙에 못 올라간 보고가 {n}건 있어요 — 보낸 기록이 비어 있어요\n"
            f"할 일 없음 — 하네스 담당이 확인해요\n(mirror · #GAP-{first}-{last})")


def item(seqs: list[int], beyond: int) -> dict[str, object]:
    """요약 1통 — seq = beyond(로그 마지막 행) 로 두어 이번 패스에서 밀린 구간을 «다 지나간» 것으로 저장된다."""
    first, last = seqs[0], seqs[-1]
    return {"id": f"#BACKLOG-{first}-{last}", "seq": beyond, "key": lib.OTHER_KEY,
            "what": "슬랙 미러가 밀린 쪽지를 건너뛴 상태", "text": format_skip(len(seqs), first, last)}


SKIP_ANCHOR = "if bl.skip_backlog(self, st, rows):"  # 변이 시험(test_mirror_backlog.sh)이 이 줄을 지우면 ⓐ(300회 원문) 재현


def skip_backlog(mirror, st: dict[str, object], rows: list[dict[str, object]]) -> bool:
    """밀린 게시 대상이 상한을 넘으면 요약 1통만 올리고 True(이번 패스는 행 루프 생략) — 미러 한 패스의 첫 분기."""
    last_seq = int(str(st["last_seq"]))
    desk_on = bool(mirror.desk)
    hot = [int(str(r["seq"])) for r in rows if int(str(r["seq"])) > last_seq and
           is_target(r, mirror.seat, mirror.urgent, mirror.urgent_senders) and
           desk.wants_desk(r, mirror.urgent_senders, desk_on)]
    prefix = [r for r in rows if not hot or int(str(r["seq"])) < min(hot)]
    seqs = pick(prefix, last_seq, mirror.seat, mirror.a.backlog_max, mirror.urgent, mirror.urgent_senders, desk_on)
    if not seqs:
        return False
    beyond = min(hot) - 1 if hot else int(str(rows[-1]["seq"]))
    mirror.deliver(st, item(seqs, beyond))
    return True
