#!/usr/bin/env python3
"""test_report_hooks.sh 전용 ft-inbox 스텁 — 실제 ft-inbox.py 의 show·report·mark 출력/술어 모양만 흉내 낸다.
큐 = FT_ROOT/.fable-team/state/inbox/<계보>.jsonl · STUB_FAIL 이 있으면 전부 실패(rc≠0)."""
import json
import os
import sys

MUST = {"①", "②", "③", "④", "미상"}
INBOX = f"{os.environ['FT_ROOT']}/.fable-team/state/inbox"


def closed(x):
    return x["mark"] is not None and (x["cls"] not in MUST or x["reported"] is True)


def load(p):
    return [json.loads(ln) for ln in open(p, encoding="utf-8") if ln.strip()]


def show(seat):
    p = f"{INBOX}/{seat.split('#')[0]}.jsonl"
    rows, out = (load(p) if os.path.exists(p) else []), []
    for g in dict.fromkeys(x["group"] for x in sorted(rows, key=lambda x: x["seq"])):
        mem = [x for x in rows if x["group"] == g]
        if not all(closed(x) for x in mem):
            out.append(f"[{mem[0]['cls']}] {g} seq={','.join(str(x['seq']) for x in mem)} "
                       f"미닫힘={','.join(str(x['seq']) for x in mem if not closed(x))} from={mem[0]['from']} 원문=- | 본문")
    print("\n".join(out) or "EMPTY")


def mutate(targets, field, value):
    for fn in (n for n in os.listdir(INBOX) if n.endswith(".jsonl")):
        rows = load(f"{INBOX}/{fn}")
        for x in rows:
            if str(x["seq"]) in targets or x["group"] in targets:
                x[field] = value
        open(f"{INBOX}/{fn}", "w", encoding="utf-8").writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in rows)


if os.environ.get("STUB_FAIL"):
    sys.exit("REJECT stub 강제 실패")
c, a = sys.argv[1], sys.argv[2:]
if c == "show":
    show(a[0])
elif c == "mark":
    mutate({a[0]}, "mark", {"kind": a[1], "note": a[2]})
elif c == "report":
    mutate(set(a), "reported", True)
