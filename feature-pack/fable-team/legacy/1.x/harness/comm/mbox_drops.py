# 버린 쪽지의 «유실 표시» — mbox_ops.recv 가 SCANNED 줄 다음에 1줄 · 200줄 규칙 분리(r1651).
"""★ring 포화로 버린 seq 를 «받는 좌석» 에 보인다★ (r1651)

r912/r630 은 버린 «건수» 만 남겼다(dropped=3 oldest_seq=…). 받는 쪽은 무엇이 사라졌는지,
그것이 실보고였는지 영영 몰랐다 — 실측 2026-11-11: h8178·h8172 완료 보고 2통이 그렇게 사라졌다.
⇒ 원장 줄에 버린 seq «전부» 를 적고, 그 좌석의 다음 recv 가 `DROPPED-SEEN n #a,#b` 1줄로 보여준다.
   전문은 mailbox.log.jsonl 에 그대로 있으니 잃은 것은 «알림» 뿐, 되찾는 길은 이 줄이 처음 연다.
   같은 seq 를 두 번 보이지 않는다 — 표식 = mailbox.drops.seen.json 1파일(계보 키 → 마지막 줄 번호).
★DA R2(2026-11-11)★ 표식 읽기·갱신은 «우편함 잠금 안» — 밖에서 읽고-고치면 동시 report 가 서로의 키를
   덮어써 이미 보여준 seq 가 다시 나온다(once 계약 위반). 잠금 재설계 0, claim 의 잠금을 그대로 쓴다.
★DA R1(2026-11-11)★ 은퇴한 옛 좌석은 표시를 «소비하지 않는다» — 소유권은 recv 의 계보 규칙을 그대로 따른다
   (mbox_ops.recv 가 현역일 때만 report 를 부른다).
"""
import json
import os
import sys
import time

from mbox_conf import role_key
from mbox_store import _locked   # ★잠금을 «새로» 만들지 않는다 — claim 이 쓰는 그 우편함 잠금(r1651 DA R2)

DROP_SEEN = "mailbox.drops.seen.json"


def report(canon, me, names):
    """★유실 표시 (r1651)★ — 내 계보 앞으로 버려진 seq 를 «다음 recv» 에 1줄. 같은 seq 는 두 번 안 보인다.
    표식 = mailbox.drops.seen.json 한 파일(계보 키 → 마지막으로 본 원장 «줄 번호»).
    ★원장을 «읽기만» 한다★ — 버린 행은 mailbox.log.jsonl 에 남아 있으니 전문은 거기서 되찾는다.
    """
    try:
        with open(os.path.join(canon, "mailbox.drops.log"), encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return ""
    return _locked(canon, lambda: _mark(canon, me, names, lines))


def _mark(canon, me, names, lines):
    """표식 읽기·갱신 — ★반드시 우편함 잠금 안에서 부른다★(r1651 DA R2). 보여줄 seq 가 없으면 파일을 안 건드린다."""
    state = os.path.join(canon, DROP_SEEN)
    try:
        with open(state, encoding="utf-8") as f:
            seen = json.load(f)
        seen = seen if isinstance(seen, dict) else {}
    except (OSError, ValueError):
        seen = {}
    mine, last = {role_key(n) for n in names}, int(seen.get(role_key(me)) or 0)
    seqs, upto = [], last
    for i, ln in enumerate(lines, 1):
        if i <= last:
            continue
        kv = dict(p.split("=", 1) for p in ln.split() if "=" in p)
        if role_key(kv.get("to", "")) not in mine:
            continue
        upto = i
        seqs.extend(s for s in (kv.get("seqs") or kv.get("oldest_seq") or "").split(",") if s)
    if not seqs:
        return ""
    try:
        seen[role_key(me)] = upto
        tmp = "%s.%d.tmp" % (state, os.getpid())   # 고정 .tmp 이름 = 동시 갱신이 서로의 파일을 덮는다
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(seen, f)
        os.replace(tmp, state)
    except OSError:
        pass
    return "DROPPED-SEEN %d %s — 전문 = mailbox.log.jsonl" % (len(seqs), "#" + ",#".join(seqs))


def log_drop(canon, to, dropped, oldest, seqs=()):
    """★버림 원장 (r630 · seq 전부 r1651)★ — stderr DROPPED 는 보낸 쪽 화면에만 남았다. 본문 0 · 1줄.
    r1651: 버린 seq 를 «전부» 적는다(`seqs=a,b`) — 받는 좌석의 다음 recv 가 DROPPED-SEEN 1줄로 보여준다.
    기록 실패로 send 를 실패시키지 않는다(이미 큐에 들어갔다) — 대신 stderr ERROR 1줄."""
    try:
        with open(os.path.join(canon, "mailbox.drops.log"), "a", encoding="utf-8") as f:
            f.write("%s to=%s dropped=%d oldest_seq=%s seqs=%s\n" % (
                time.strftime("%Y-%m-%dT%H:%M:%S"), to, dropped, oldest, ",".join(str(s) for s in seqs)))
    except OSError as e:
        sys.stderr.write("ERROR mailbox.drops.log 기록 실패: %s\n" % e)
