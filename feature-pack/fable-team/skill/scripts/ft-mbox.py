#!/usr/bin/env python3
"""파일 기반 세션 메시지 큐 (fable-team). LIFO·per-to ring·fcntl.flock·consume-on-read·to==me grep.
v6-realtime-live mbox.py 계승 + 팩 추가분: FT_MBOX_DIR 경로 주입·세션명 allowlist·READ 출력·from 필터."""
import sys, os, re, json, time, fcntl

# 데이터 경로: env FT_MBOX_DIR 우선, 미설정 시 cwd/.fable-team/comm 폴백(워커 계약 cwd=프로젝트 루트).
# bin(update.md §P-2 스왑 대상)과 데이터 동거 금지 → 스크립트 옆이 아니라 <root>/.fable-team/comm.
DIR = os.environ.get("FT_MBOX_DIR") or os.path.join(os.getcwd(), ".fable-team", "comm")
os.makedirs(DIR, exist_ok=True)
MBOX = os.path.join(DIR, "mailbox.jsonl")
LOCK = os.path.join(DIR, "mailbox.lock")
MAX_PER_TO = int(os.environ.get("FT_MBOX_RING") or 10)
# 세션명 allowlist — 세션명이 doorbell 명령 문자열에 삽입되므로 하드 거부(명령 삽입 원천 차단).
NAME_RE = re.compile(r'^[A-Za-z0-9._#-]+$')

def _check_name(n):
    if not n or not NAME_RE.match(n):
        sys.stderr.write("BAD_SESSION_NAME %s\n" % n)
        sys.exit(1)

def _load():
    rows = []
    if os.path.exists(MBOX):
        for ln in open(MBOX, encoding="utf-8"):
            ln = ln.strip()
            if ln:
                try: rows.append(json.loads(ln))
                except Exception: pass
    return rows

def _save(rows):
    rows.sort(key=lambda r: r["seq"])
    with open(MBOX, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

def _locked(fn):
    lf = open(LOCK, "w")
    fcntl.flock(lf, fcntl.LOCK_EX)
    try:
        return fn()
    finally:
        fcntl.flock(lf, fcntl.LOCK_UN); lf.close()

def send(to, frm, body):
    _check_name(to); _check_name(frm)
    def op():
        rows = _load()
        seq = max((r.get("seq", 0) for r in rows), default=0) + 1
        rows.append({"seq": seq, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                     "to": to, "from": frm, "body": body})
        byto = {}
        for r in rows: byto.setdefault(r["to"], []).append(r)
        keep = []
        for _, rs in byto.items():
            rs.sort(key=lambda r: r["seq"]); keep.extend(rs[-MAX_PER_TO:])
        _save(keep)
        return seq, sum(1 for r in keep if r["to"] == to)
    seq, pend = _locked(op)
    print(f"QUEUED seq={seq} to={to} pending={pend}")

def recv(me, frm=None):
    _check_name(me)
    if frm is not None: _check_name(frm)
    def op():
        rows = _load()
        if frm is not None:
            mine = [r for r in rows if r.get("to") == me and r.get("from") == frm]
            rest = [r for r in rows if not (r.get("to") == me and r.get("from") == frm)]
        else:
            mine = [r for r in rows if r.get("to") == me]
            rest = [r for r in rows if r.get("to") != me]
        _save(rest)
        return mine
    mine = _locked(op)
    if not mine:
        print("READ none"); return
    for r in sorted(mine, key=lambda r: r["seq"], reverse=True):  # LIFO
        print(f"READ [{r['from']}->{me}] #{r['seq']} — {r['body']}")

def peek(me):
    _check_name(me)
    rows = _locked(_load)
    mine = sorted([r for r in rows if r.get("to") == me], key=lambda r: r["seq"], reverse=True)
    print(f"pending={len(mine)}" + (f" latest_seq={mine[0]['seq']} from={mine[0]['from']}" if mine else ""))

if __name__ == "__main__":
    a = sys.argv[1:]
    if not a: sys.exit("usage: mbox {send <to> <from> <body>|recv <me> [<from>]|peek <me>}")
    c = a[0]
    if c == "send": send(a[1], a[2], " ".join(a[3:]))
    elif c == "recv": recv(a[1], a[2] if len(a) > 2 else None)
    elif c == "peek": peek(a[1])
    else: sys.exit("unknown cmd")
