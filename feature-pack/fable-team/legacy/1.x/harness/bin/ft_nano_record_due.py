#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_due.py — r1717 A2 판정(읽기만): `due [--pr N] [--no-fetch]` · `settle --seat <좌석> --pr <N> (--card <stem>… | --no-card "<사유>")`.
due 줄: «차례 <좌석> 종류=<닫기|기록만> 빠짐=<ⓢⓛⓒ>» · «닫기 요청 밀림 <좌석>» · «끝 … (닫기 요청 #seq|기록만|남은 일 — 닫기 요청 0|주인 기록|카드 없음 확정)» ·
  «주인 없음 <카드> 담당=<팀장>» · «카드 없음 PR #N 담당=<팀장>» · «판정 불가 카드 ref <사유> pr=N»(r1743 A3 · cards_err 줄) · «판정 불가 <카드> <명령> rc=<n>» — 뜻 = 카드 r1717 A2. rc 0 = 전부 판정 · 3 = 판정 불가 1건 이상.
settle = «카드 없음» 장부 줄을 팀장·arch 가 닫는다(장부에 덧줄 1개 append · role=nano 좌석 = REJECT)."""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

from ft_nano_record import CARD_RX, DONE_RX, Ctx, Reject, Unjudged, left_free, left_of, marks, rec_of, section


def card_key(path):   # 카드 경로 → (팀, indices 뿌리, stem) | None
    m = CARD_RX.search(path or "")
    return (m.group(2) or m.group(3), m.group(1), m.group(4)) if m else None


def idx_stem(row):
    return Path(str((row or {}).get("index") or "")).stem


def owners(ctx, doc, stem, sec):   # 차례 좌석 → [(좌석, 종류, 그 좌석의 지금 카드)] · 종류 닫기 = 지금 index · 기록만 = 재사용 좌석
    nanos = {k: v for k, v in doc.items() if not k.startswith("_") and isinstance(v, dict) and v.get("role") == "nano" and not v.get("_replaced_by")}
    if not nanos:
        return []
    now = [(k, "닫기", stem) for k, v in sorted(nanos.items()) if idx_stem(v) == stem and k in ctx.live()]
    if now:
        return now
    cand = [m.group(1) for ln in sec for m in [re.search(r"대기→진행\s*·\s*좌석\s+(\S+)", ln)] if m][-1:]
    try:
        a = json.loads((ctx.state / "card-assign" / f"{stem}.json").read_text(encoding="utf-8"))
        cand += [a["seat"]] if a.get("state") == "seat" and a.get("seat") else []
    except (OSError, ValueError, KeyError, AttributeError):
        pass
    return [(k, "기록만", idx_stem(nanos[k])) for k in dict.fromkeys(cand) if k in nanos and idx_stem(nanos[k]) != stem and k in ctx.live()]   # r1717-mut:reuse


def judge(ctx, base, seat, sort, sec, alive=True):   # 좌석 1개의 줄(단계 ㉯→㉰→㉱ · 기록이 먼저다)
    q, m = base["q"], marks(sec, seat, base["q"])
    row = {**base, "seat": seat, "sort": sort or "닫기", "m": m}
    miss = "".join(s for s, k in (("ⓢ", "s"), ("ⓛ", "l"), ("ⓒ", "c")) if not m[k])   # r1717-mut:three
    if miss:
        return {**row, "k": "차례" if alive else "주인없음", "miss": miss}
    if sort == "기록만" or "좌석 계속" in m["c"]:
        return {**row, "k": "끝", "why": "기록만"}
    if not left_free(left_of(m["c"]), base["master"]):
        return {**row, "k": "끝", "why": "남은 일 — 닫기 요청 0", "left": left_of(m["c"])}
    st, key, rec = ctx.store(), f"{seat}|{base['stem']}|{q}", rec_of(m)
    sent = st["close"].get(key) or {}
    if sent.get("rec") == rec:
        return {**row, "k": "끝", "why": f"닫기 요청 #{sent.get('seq')}", "rec": rec, "seq": sent.get("seq")}
    if st["rejrec"].get(key) == rec or not alive:
        return {**row, "k": "끝", "why": "닫기 거절 — 기록을 고친 뒤 다시" if alive else "좌석 없음 · 기록 있음", "rec": rec}
    return {**row, "k": "밀림", "rec": rec}


def card_rows(ctx, e, path):
    key = card_key(path)
    if not key:
        return [{"k": "판정불가", "stem": Path(path).stem, "why": "카드 경로 꼴 rc=1"}]
    team, iroot, stem = key
    base = {"pr": e.get("pr"), "q": e["landed"], "stem": stem, "team": team, "iroot": iroot, "e": e, "master": ""}
    try:
        doc = ctx.seats(team)
        base["master"] = str(doc.get("_master") or "")
        base["path"], raw = ctx.card(team, iroot, stem)
        lines, st, en = section(raw.decode("utf-8", "replace"))
        sec = lines[st + 1:en] if st is not None else []   # r1717-mut:section
        own = owners(ctx, doc, stem, sec)
        gone = sorted({m.group(1) for ln in sec for m in [DONE_RX.match(ln)] if m and f"착지 {e['landed'][:10]}" in ln} - {s for s, _k, _c in own})
        out = [{**judge(ctx, base, s, k, sec), "cur": c} for s, k, c in own] + [judge(ctx, base, s, None, sec, alive=False) for s in gone]
    except Unjudged as u:
        return [{**base, "k": "판정불가", "why": str(u)}]
    if not out:
        m = marks(sec, "", e["landed"])
        miss = "".join(s for s, k in (("ⓢ", "s"), ("ⓛ", "l")) if not m[k])
        out = [{**base, "k": "주인없음", "miss": miss}] if miss else [{**base, "k": "끝", "why": "주인 기록"}]
    return out


def rows(ctx, pr=None):   # 장부 줄마다 카드별 줄
    out = []
    for e in ctx.ledger():
        if pr is not None and e.get("pr") != pr:
            continue
        if e["cards"]:
            for c in e["cards"]:
                out += card_rows(ctx, e, c)
            continue
        base = {"pr": e.get("pr"), "q": e["landed"], "stem": f"PR#{e.get('pr')}", "e": e, "master": ""}
        team = (str(e.get("by") or "").split("-") + ["", ""])[1]
        try:
            base["master"] = str(ctx.seats(team).get("_master") or "") if team else ""
        except Unjudged:
            pass
        if e.get("cards_err"):   # r1743 A3: ref 못 읽음 = «카드 없음» 아님 · 판정 불가(하드 룰 20)
            out.append({**base, "k": "카드ref불가", "why": str(e["cards_err"])})
            continue
        out.append({**base, "k": "끝", "why": f"카드 없음 확정 · {e['nocard']}"} if e["nocard"] else {**base, "k": "카드없음"})
    return out


def due_rows(ctx, pr=None, fetch=True):   # A2 — fetch 는 «열린 줄» 이 있을 때만 실행당 1회(remote-tracking 판으로 먼저 본다)
    ctx.fetch = False
    out = rows(ctx, pr)
    if fetch and any(r["k"] not in ("끝", "카드없음") for r in out):
        ctx.fetch, ctx._tips = True, {}
        out = rows(ctx, pr)
    return out


def fmt(r):
    tail = f"pr={r.get('pr')} 착지={str(r.get('q') or '')[:10]}"
    k = r["k"]
    if k == "차례":
        return f"차례 {r['seat']} 종류={r['sort']} 빠짐={r['miss']} 카드={r['stem']} {tail}"
    if k == "밀림":
        return f"닫기 요청 밀림 {r['seat']} 카드={r['stem']} {tail} rec={r['rec']}"
    if k == "끝":
        return f"끝 {r['stem']} {tail} 좌석={r.get('seat') or '-'} ({r['why']})"
    if k == "주인없음":
        return f"주인 없음 {r['stem']} 담당={r['master'] or '-'} 빠짐={r['miss']} {tail}"
    if k == "카드없음":
        return f"카드 없음 PR #{r.get('pr')} 담당={r['master'] or '-'} 착지={str(r.get('q') or '')[:10]}"
    if k == "카드ref불가":
        return f"판정 불가 카드 ref {r['why']} pr={r.get('pr')} 착지={str(r.get('q') or '')[:10]}"
    return f"판정 불가 {r['stem']} {r['why']}"


def cmd_settle(ctx, a):
    doc = ctx.seats((a.seat.split("-") + ["", ""])[1])
    row = doc.get(a.seat)
    if isinstance(row, dict) and row.get("role") == "nano" or not isinstance(row, dict) and a.seat not in (doc.get("_master"), doc.get("_arch")):
        raise Reject(f"settle 은 팀장·arch 만 — {a.seat} (role=nano 또는 명부 밖)")
    if not [e for e in ctx.ledger() if e.get("pr") == a.pr]:
        raise Reject(f"장부에 PR #{a.pr} 줄 없음")
    if bool(a.card) == bool((a.no_card or "").strip()):
        raise Reject("--card <stem>… 또는 --no-card \"<사유>\" 중 하나")
    cards = []
    for stem in a.card or []:
        key = card_key(f"{doc.get('_cards') or ''}/진행/{stem}.md")
        if not key:
            raise Reject(f"명부 _cards 칸으로 카드 자리를 못 정함({stem})")
        ctx.card(key[0], key[1], stem)   # 카드 ref 에 실재해야 한다(없음 = 판정 불가)
        cards.append(str(ctx.root / key[1] / "진행" / f"{stem}.md"))
    line = {"pr": a.pr, "settle": "card" if cards else "no-card", "cards": cards, "why": (a.no_card or "").strip(), "by": a.seat, "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}
    with open(ctx.state / "land-record-turn.jsonl", "a", encoding="utf-8") as fh:
        fh.write(json.dumps(line, ensure_ascii=False) + "\n")
    print(f"SETTLED PR #{a.pr} " + (f"카드 {' '.join(a.card)}" if cards else f"카드 없음 확정 — {line['why']}"))
    return 0


def main(argv):
    p = argparse.ArgumentParser(prog="ft-nano-record.sh")
    sub = p.add_subparsers(dest="verb", required=True)
    d = sub.add_parser("due")
    d.add_argument("--pr", type=int)
    d.add_argument("--no-fetch", action="store_true")
    s = sub.add_parser("settle")
    s.add_argument("--seat", required=True)
    s.add_argument("--pr", type=int, required=True)
    s.add_argument("--card", action="append")
    s.add_argument("--no-card")
    a = p.parse_args(argv)
    try:
        ctx = Ctx()
        if a.verb == "settle":
            return cmd_settle(ctx, a)
        out = due_rows(ctx, a.pr, not a.no_fetch)
    except Reject as e:
        print(f"REJECT {e}")
        return 1
    except Unjudged as e:
        print(f"판정 불가 {e}")
        return 3
    for r in out:
        print(fmt(r))
    return 3 if any(r["k"] in ("판정불가", "카드ref불가") for r in out) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
