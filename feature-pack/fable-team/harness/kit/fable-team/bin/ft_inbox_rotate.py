"""ft_inbox_rotate.py — `show <좌석> --count` · `rotate <좌석> --before …` · show 머리 줄(r1052 단계 2 · B1·B3·B4).

술어는 ft_inbox_core.obligation_closed(x, answered_seqs(좌석)) 하나 — show·--count·--seqs·rotate 가 같은 답을 낸다(B2).
--count 는 본문 파일을 열지도(open) 확인하지도(exists) 않는다. rotate 는 «미닫힘 묶음» 만 보관 파일로 옮기고 닫힌 묶음은 건드리지 않는다(그건 archive 몫).
"""
import json
import os
import re
import time
from collections import Counter
from datetime import datetime, timedelta

from ft_inbox_core import INBOX, answered_seqs, die, lineage, locked, obligation_closed, qpath, read_q, write_q

LOG = f"{INBOX}/rotated.log"  # 한 줄 = 한 회: <ts> <계보> groups=<묶음> rows=<행> file=<보관 파일> | <사유>
LOG_LINE = re.compile(r"^(\S+) (\S+) groups=(\d+) rows=(\d+) file=(.+?) \| ")


def open_groups(rows, ans):
    """묶음 id → 그 묶음 행들, 단 «미닫힘»(한 행이라도 술어 거짓)인 묶음만."""
    mem = {}
    for x in rows:
        mem.setdefault(x["group"], []).append(x)
    return {g: ms for g, ms in mem.items() if not all(obligation_closed(x, ans) for x in ms)}


def cmd_count(seat):
    """OPEN <미닫힘 묶음 수> (+ 있으면 OLDEST seq=<미닫힘 가장 작은 seq> — 상황판 «가장 오래된» 칸용) · 본문 접근 0."""
    ans = answered_seqs(seat)
    og = open_groups(read_q(qpath(seat)), ans)
    un = [x["seq"] for ms in og.values() for x in ms if not obligation_closed(x, ans)]
    print(f"OPEN {len(og)}" + (f"\nOLDEST seq={min(un)}" if un else ""))


def tidy_hits(rows, cut):
    """Locked waive selection: repeated old tool notices, preserving human/HIL/outage rows."""
    cut = min(cut, datetime.now(cut.tzinfo) - timedelta(days=3))
    repeats = Counter((x["from"], x["cls"]) for x in rows)
    human_after = {}
    for x in rows:
        if not x["from"].startswith("ft-"):
            human_after[x["group"]] = max(human_after.get(x["group"], -1), x["seq"])
    hit = []
    for x in sorted(rows, key=lambda row: row["seq"]):
        if (datetime.fromisoformat(x["ts"]) < cut and x["from"].startswith("ft-")
                and repeats[x["from"], x["cls"]] >= 2 and x["cls"] not in ("②", "④")
                and human_after.get(x["group"], -1) <= x["seq"] and not obligation_closed(x)):
            hit.append(x)
            if len(hit) == 200:
                break
    return hit


def cmd_rotate(seat, before, reason):
    """경계(before) 전에 끝난 «미닫힘 묶음»(가장 새 행 ts < before) 전부를 보관 파일에 덧붙이고 큐에서 뺀다. 판정 번호가 든 사유 필수."""
    if not re.search(r"판정 [0-9]+", reason):
        die('usage: rotate <좌석> --before <ISO ts> "<판정 N 이 든 사유>"', 2)
    cut, ans, now = datetime.fromisoformat(before), answered_seqs(seat), time.strftime("%Y-%m-%dT%H:%M:%S")
    arc = f"{INBOX}/archive/{lineage(seat)}-rotated-{time.strftime('%Y%m%d')}.jsonl"
    with locked(q := qpath(seat)):
        rows = read_q(q)
        old = {g for g, ms in open_groups(rows, ans).items() if max(datetime.fromisoformat(x["ts"]) for x in ms) < cut}
        move, stay = [x for x in rows if x["group"] in old], [x for x in rows if x["group"] not in old]
        if move:  # 보관 파일에 먼저 덧붙이고 큐를 바꾼다 — 중간에 죽어도 줄이 사라지지 않는다(중복만 남음)
            os.makedirs(os.path.dirname(arc), exist_ok=True)
            with open(arc, "a", encoding="utf-8") as f:
                f.writelines(json.dumps({**x, "waived": {"by": reason.strip(), "ts": now, "rotated": True}}, ensure_ascii=False) + "\n" for x in move)
            write_q(q, stay)
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(f"{now} {lineage(seat)} groups={len(old)} rows={len(move)} file={arc} | {reason.strip()}\n")
    print(f"ROTATED {len(old)} rows={len(move)} KEPT {len({x['group'] for x in stay})} file={arc if move else '-'}")


def rotated_head(seat):
    """show 첫 줄 — 이 계보가 회전으로 치워 둔 묶음이 있으면 «회전 보관 N묶음 — <파일>(마지막 회전 <ts>)». 없으면 None(출력 바이트 불변)."""
    if not os.path.exists(LOG):
        return None
    with open(LOG, encoding="utf-8") as f:
        ms = [m.groups() for m in map(LOG_LINE.match, f) if m and m.group(2) == lineage(seat)]
    return f"회전 보관 {sum(int(m[2]) for m in ms)}묶음 — {ms[-1][4]}(마지막 회전 {ms[-1][0]})" if ms else None
