#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_wake.py — r2015 «[정리 차례]» 깨움 확인(ft_nano_record_notify.notify_row 가 차례 쪽지 발신 뒤 부른다).
차례 쪽지 발신 출력의 doorbell=<값> 이 sent 가 아니면(quiet·held·budget·skipped·absent·noagent·error·none·칸 없음) 같은 좌석에 `mbox.sh ring` 1회(7초) ·
  결과 1줄 «WAKE <좌석> doorbell=<값> → ring rc=<n> doorbell=<값>».
ring 도 실패(rc≠0 · ring 의 doorbell 이 sent·ext·none 아님 = 주입 0)면 팀장 «[정리 차례 · 깨움 실패] <좌석> <카드> seq=<n>» 1통 ·
  같은 열쇠(팀장·카드·Q) 1회 — 열쇠 = 보낸 기록 sent 칸의 «<팀장>|<카드>|<Q>|깨움실패»."""
from __future__ import annotations

import os
import re

from ft_nano_record import run

RING_OK = ("sent", "ext", "none")   # none = 받는 쪽 미읽음 0(이미 읽음)


def doorbell(out):   # mbox 출력의 doorbell=<값> · 못 읽음 = «못읽음»
    m = re.search(r"\bdoorbell=(\S+)", out or "")
    return m.group(1) if m else "못읽음"


def wake(ctx, r, seq, send, update, frm):   # r = 차례 줄 · seq = 차례 쪽지 seq · send·update = notify 의 발신·기록 함수
    if r["k"] != "차례":   # 주인 없음·카드 없음(팀장 수신) = 깨움 확인 0
        return
    db = doorbell(getattr(ctx, "send_out", ""))
    if db == "sent":
        return
    rc, out, _e = run(["bash", os.environ.get("FT_MBOX") or str(ctx.comm / "mbox.sh"), "ring", r["seat"]], env=dict(os.environ))
    rdb, rcs = doorbell(out), "-" if rc is None else rc
    print(f"WAKE {r['seat']} doorbell={db} → ring rc={rcs} doorbell={rdb}")
    key = f"{r['master']}|{r['stem']}|{r['q']}|깨움실패"
    if (rc == 0 and rdb in RING_OK) or not r["master"] or ctx.store()["sent"].get(key):
        return
    body = f"[정리 차례 · 깨움 실패] {r['seat']} {r['stem']} seq={seq} — 차례 doorbell={db} · ring rc={rcs} doorbell={rdb} · 착지 {r['q'][:10]}(PR #{r['pr']})"
    fseq = send(ctx, r["master"], frm, body)
    if fseq is not None:
        update(ctx, lambda st: st["sent"].__setitem__(key, {"n": 1, "seq": fseq}))
