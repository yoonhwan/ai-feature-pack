#!/usr/bin/env python3
"""파일 기반 세션 메시지 큐 (fable-team). LIFO·per-to ring·fcntl.flock·consume-on-read·to==me grep.
v6-realtime-live mbox.py 계승 + 팩 추가분: FT_MBOX_DIR 경로 주입·세션명 allowlist·READ 출력·from 필터.

★2026-08-25 — 우편함이 «셋으로 갈라져» 메시지가 유실되던 것을 고친다★
이전: 데이터 경로가 «cwd 기준»이라, 같은 스크립트를 불러도 부른 사람의 cwd 에 따라 다른
우편함을 썼다 — 보낸 쪽과 받는 쪽이 서로 다른 파일을 보는 사고가 실제로 났다.
지금: ★send 는 «정본» 하나에만 쓰고, recv/peek 는 «정본+레거시»를 전부 읽는다(union)★.
union 을 두는 이유 — 경로를 «순간에» 바꾸면 바꾸기 직전 큐잉된 메시지가 옛 파일에 남아
★아무도 안 읽는다★. 레거시가 전부 0행이 되면 그때 걷어낸다(그 판단은 별도).
"""
import sys, os, re, json, time, fcntl

MAX_PER_TO = int(os.environ.get("FT_MBOX_RING") or 10)
# 세션명 allowlist — 세션명이 doorbell 명령 문자열에 삽입되므로 하드 거부(명령 삽입 원천 차단).
NAME_RE = re.compile(r'^[A-Za-z0-9._#-]+$')


def _repo_root(start):
    """★정본 자리를 «유도»한다 — 하드코딩 금지★.

    이 파일 위쪽의 `.fable-team` 을 찾고, 그 부모가 `.worktrees/<x>` 면 리포 루트는 두 단계
    위다. ★워크트리 «안»이 아니라 «밖»을 정본으로 잡는 이유★: 워크트리는 정리되면 사라지고,
    그날 그 안의 우편함을 쓰던 세션이 전부 끊긴다.
    """
    d = os.path.abspath(start)
    while d != os.path.dirname(d):
        if os.path.basename(d) == ".fable-team":
            parent = os.path.dirname(d)
            gp = os.path.dirname(parent)
            return os.path.dirname(gp) if os.path.basename(gp) == ".worktrees" else parent
        d = os.path.dirname(d)
    return os.path.abspath(start)


_ROOT = _repo_root(os.path.dirname(os.path.abspath(__file__)))
# ★명시가 추론을 이긴다★ — env 로 준 FT_MBOX_DIR 은 그대로 존중한다(이전엔 래퍼가 덮어썼다).
CANON = os.environ.get("FT_MBOX_DIR") or os.path.join(_ROOT, ".fable-team", "comm")
os.makedirs(CANON, exist_ok=True)


def _legacy_dirs():
    """레거시 우편함 — ★손으로 나열하지 않고 워크트리 목록에서 «유도»한다★.

    손으로 쓴 목록은 다음에 생기는 워크트리를 못 잡는다.
    """
    out, wt = [], os.path.join(_ROOT, ".worktrees")
    if os.path.isdir(wt):
        for name in sorted(os.listdir(wt)):
            d = os.path.join(wt, name, ".fable-team", "comm")
            if os.path.isdir(d) and os.path.abspath(d) != os.path.abspath(CANON):
                out.append(d)
    return out


def _mbox(d): return os.path.join(d, "mailbox.jsonl")


def _check_name(n):
    if not n or not NAME_RE.match(n):
        sys.stderr.write("BAD_SESSION_NAME %s\n" % n)
        sys.exit(1)


def _load(d):
    rows, p = [], _mbox(d)
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            ln = ln.strip()
            if ln:
                try: rows.append(json.loads(ln))
                except Exception: pass
    return rows


def _save(d, rows):
    rows.sort(key=lambda r: r["seq"])
    with open(_mbox(d), "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def _locked(d, fn):
    lf = open(os.path.join(d, "mailbox.lock"), "w")
    fcntl.flock(lf, fcntl.LOCK_EX)
    try:
        return fn()
    finally:
        fcntl.flock(lf, fcntl.LOCK_UN); lf.close()


def send(to, frm, body):
    _check_name(to); _check_name(frm)
    def op():
        rows = _load(CANON)
        seq = max((r.get("seq", 0) for r in rows), default=0) + 1
        rows.append({"seq": seq, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                     "to": to, "from": frm, "body": body})
        byto = {}
        for r in rows: byto.setdefault(r["to"], []).append(r)
        keep = []
        for _, rs in byto.items():
            rs.sort(key=lambda r: r["seq"]); keep.extend(rs[-MAX_PER_TO:])
        _save(CANON, keep)
        return seq, sum(1 for r in keep if r["to"] == to)
    seq, pend = _locked(CANON, op)
    # ★«어느 파일에 몇 바이트» 를 찍는다★ — QUEUED 를 «도착»으로도 «온전»으로도 읽지 않게.
    print(f"QUEUED seq={seq} to={to} pending={pend} "
          f"file={_mbox(CANON)} bytes={len(body.encode('utf-8'))}")


def _take(d, me, frm):
    def op():
        rows = _load(d)
        def is_mine(r):
            return r.get("to") == me and (frm is None or r.get("from") == frm)
        mine = [r for r in rows if is_mine(r)]
        if mine:
            _save(d, [r for r in rows if not is_mine(r)])
        return mine
    return _locked(d, op)


def recv(me, frm=None):
    _check_name(me)
    if frm is not None: _check_name(frm)
    dirs = [CANON] + _legacy_dirs()
    got = [(d, r) for d in dirs for r in _take(d, me, frm)]
    # ★어느 파일들을 봤는지 찍는다★ — 안 찍으면 union 이 실제로 도는지 아무도 모른다.
    print(f"SCANNED {len(dirs)} mailbox(es): " + " ".join(_mbox(d) for d in dirs))
    if not got:
        print("READ none"); return
    for d, r in sorted(got, key=lambda x: x[1]["seq"], reverse=True):  # LIFO
        tag = "" if os.path.abspath(d) == os.path.abspath(CANON) else " (legacy)"
        print(f"READ [{r['from']}->{me}] #{r['seq']}{tag} — {r['body']}")


def peek(me):
    _check_name(me)
    dirs = [CANON] + _legacy_dirs()
    mine = []
    for d in dirs:
        mine.extend(r for r in _locked(d, lambda d=d: _load(d)) if r.get("to") == me)
    mine.sort(key=lambda r: r["seq"], reverse=True)
    head = f"pending={len(mine)}"
    if mine:
        head += f" latest_seq={mine[0]['seq']} from={mine[0]['from']}"
    print(f"{head} scanned={len(dirs)}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a: sys.exit("usage: mbox {send <to> <from> <body>|recv <me> [<from>]|peek <me>}")
    c = a[0]
    if c == "send": send(a[1], a[2], " ".join(a[3:]))
    elif c == "recv": recv(a[1], a[2] if len(a) > 2 else None)
    elif c == "peek": peek(a[1])
    else: sys.exit("unknown cmd")
