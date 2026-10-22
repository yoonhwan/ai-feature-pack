"""mirror_backlog — 재시작·장애 뒤 «밀린 쪽지»가 상한을 넘으면 원문 대신 요약 1통(r739).

사건: 미러가 멈춰 있던 사이 쪽지가 2000건 쌓이자 다시 켜질 때 그걸 전부 올려 오빠 슬랙을 덮었다(오빠 1792659217).
묶음 판정: 게시 대상(수신 좌석 일치 · 오빠 글 아님) 중 last_seq 뒤에 남은 수가 상한을 «넘으면» 하나씩 올리지 않는다.
건너뛴 사실은 요약 1통으로 보인다 — 조용히 버리는 것이 아니다(원문은 mbox 원장에 그대로 있다).
"""
import re

import mirror_lib as lib


def is_target(row: dict[str, object], seat: re.Pattern[str]) -> bool:
    """게시 대상 행인가 — byz_mbox_slack_mirror._row 와 같은 조건(오빠 글 = 메아리 금지)."""
    return bool(seat.search(str(row.get("to", "")))) and str(row.get("from", "")) != "slack-oppa"


def pick(rows: list[dict[str, object]], last_seq: int, seat: re.Pattern[str], max_n: int) -> list[int]:
    """밀린 게시 대상 seq 목록 — 상한을 넘을 때만 돌려준다(그 외 빈 목록 = 지금처럼 한 줄씩)."""
    if max_n <= 0:  # 0 이면 묶음 끔
        return []
    seqs = [int(str(r["seq"])) for r in rows if int(str(r["seq"])) > last_seq and is_target(r, seat)]
    return seqs if len(seqs) > max_n else []


def format_skip(n: int, first: int, last: int) -> str:
    return (f"[상태] 슬랙 미러가 밀린 쪽지 {n}건을 건너뛰었어요(seq {first}~{last}) — 원문은 mbox 원장에 있어요\n"
            f"할 일 없음 — 다음 쪽지부터 다시 올려요\n(mirror · #BACKLOG-{first}-{last})")


def item(seqs: list[int], beyond: int) -> dict[str, object]:
    """요약 1통 — seq = beyond(로그 마지막 행) 로 두어 이번 패스에서 밀린 구간을 «다 지나간» 것으로 저장된다."""
    first, last = seqs[0], seqs[-1]
    return {"id": f"#BACKLOG-{first}-{last}", "seq": beyond, "key": lib.OTHER_KEY,
            "what": "슬랙 미러가 밀린 쪽지를 건너뛴 상태", "text": format_skip(len(seqs), first, last)}


SKIP_ANCHOR = "if bl.skip_backlog(self, st, rows):"  # 변이 시험(test_mirror_backlog.sh)이 이 줄을 지우면 ⓐ(300회 원문) 재현


def skip_backlog(mirror, st: dict[str, object], rows: list[dict[str, object]]) -> bool:
    """밀린 게시 대상이 상한을 넘으면 요약 1통만 올리고 True(이번 패스는 행 루프 생략) — 미러 한 패스의 첫 분기."""
    seqs = pick(rows, int(str(st["last_seq"])), mirror.seat, mirror.a.backlog_max)
    if not seqs:
        return False
    mirror.deliver(st, item(seqs, int(str(rows[-1]["seq"]))))
    return True
