# mbox.py 의 show 동사(r2081 A) — 쪽지 번호 하나를 큐·보낸 기록·회전본·전문 파일에서 한 번에 찾는다 · CANON 은 mbox.py 가 묶는다.
#   쓰기 0(잠금·큐 소비·표시·영수·회전 0) · 잠금 없이 읽는다(_save 는 os.replace 라 반쪽 큐를 보지 않는다 · r1333).
#   rc 0 = 전부 찾음 · 1 = 하나라도 없음 · 2 = 인자 틀림 · 3 = 하나라도 판정 불가(못 읽은 곳·예산 초과·깨진 줄이 있는데 못 찾음).
from mbox_conf import *
from mbox_store import _legacy_dirs, _mbox, _bodies_dir
CANON = None   # mbox.py 가 묶는다
MAX_ASK, HEAD_CHARS = 5, 300
USAGE = "usage: mbox.sh show <번호>[,<번호>…] — 번호는 한 번에 1~%d개" % MAX_ASK


def _places():   # [(자리 이름, 경로)] — 큐(정본 + legacy) · 보낸 기록 · 회전본 전부(번호 순)
    out = [("큐(안 읽음)", _mbox(d)) for d in [CANON] + _legacy_dirs()]
    log = os.path.join(CANON, SENT_LOG)
    rot = sorted(int(m.group(1)) for p in glob.glob(glob.escape(log) + ".*")
                 if (m := re.fullmatch(re.escape(log) + r"\.(\d+)", p)))
    return out + [("기록", log)] + [("기록.%d" % n, "%s.%d" % (log, n)) for n in rot]


def _scan(want, budget):
    """(찾은 {번호: [(자리, 행)]}, 읽은 곳 수, 번호 [최소, 최대], 깨진 줄 수, 판정 불가 사유 목록)."""
    found, seqs, broken, why, read, end = {}, [], 0, [], 0, time.time() + budget
    for place, path in _places():
        if not os.path.lexists(path):   # 없는 파일(빈 우편함 · 회전 전) = 읽은 곳에서 뺀다
            continue
        if time.time() > end:
            why.append("예산 %g초 초과" % budget); break
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
        except OSError as e:
            why.append("못 읽음 %s(%s)" % (place, type(e).__name__)); continue
        read += 1
        for ln in filter(str.strip, lines):
            try:
                r = json.loads(ln)
                n = int(r["seq"])
            except (ValueError, TypeError, KeyError):
                broken += 1; continue
            seqs.append(n)
            if n in want:
                found.setdefault(n, []).append((place, r))
    return found, read, (min(seqs), max(seqs)) if seqs else None, broken, why


def _full(n, row):   # 전문 파일 = 행의 body_full 또는 bodies/<번호>.txt · 없음·못 읽음 = (None, None)
    for p in (row.get("body_full"), os.path.join(_bodies_dir(CANON), "%d.txt" % n)):
        if p and os.path.isfile(p):
            try:
                with open(p, encoding="utf-8", errors="replace") as f:
                    return p, f.read()
            except OSError:
                pass
    return None, None


def _found(n, hits, broken):
    places = list(dict.fromkeys(p for p, _ in hits))
    row = hits[0][1]
    print("FOUND #%d %s %s -> %s 자리=%s%s" % (n, row.get("ts", "?"), row.get("from", "?"), row.get("to", "?"),
                                              "+".join(places), " · 깨진 줄 %d" % broken if broken else ""))
    path, text = _full(n, row)
    print((text if text is not None else str(row.get("body", "")))[:HEAD_CHARS])
    if path:
        print("전문: %s (%d자)" % (path, len(text)))


def main(args):
    asked = [x for a in args for x in a.split(",") if x]
    if not asked or len(asked) > MAX_ASK or not all(x.isdigit() for x in asked):
        sys.stderr.write(USAGE + "\n"); return 2
    budget = float(os.environ.get("FT_MBOX_SHOW_BUDGET") or 7)   # 하드 룰 12 — 7초 절대
    want = [int(x) for x in asked]
    found, read, span, broken, why = _scan(set(want), budget)
    rc = 0
    for n in want:
        if n in found:
            _found(n, found[n], broken); continue
        if why or broken:   # 못 읽은 곳·깨진 줄에 있을 수 있다 = «없음» 으로 답하지 않는다
            print("판정 불가 #%d — %s" % (n, " · ".join(why + (["깨진 줄 %d" % broken] if broken else []))))
            rc = 3; continue
        rng = "#%d~#%d" % span if span else "없음"
        old = " · 보관 범위보다 옛 번호" if span and n < span[0] else ""
        print("NONE #%d — 읽은 곳 %d개 · 기록 범위 %s%s" % (n, read, rng, old))
        rc = max(rc, 1)
    return rc
