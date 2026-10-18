# mbox.py 의 recv/peek 계보 합류(P1) — 승계된 옛 이름 큐를 후계가 한 번에 읽는다 · CANON 은 mbox.py 가 묶는다 · 200줄 규칙 분리.
#   send 는 은퇴 수신자를 막고(N3 가드) recv 는 계보를 읽는다 — 비대칭이 설계다(PLAN-planner-no-stall r5 §4-1).
#   계보 규칙은 mbox_guard.sh 의 명부 규칙(tfile 팀 명부 · _replaced_by · 명부 충돌 · closed/stopped)과 같다. 외부 호출 0(json·큐 파일만).
from mbox_conf import *
from mbox_store import _load, _locked, _save
CANON = None   # mbox.py 가 묶는다


def _seats_json():   # mbox.sh 의 _seats_json 과 같은 규칙: env 가 이기고, 없으면 정본 우편함 옆 seats.json
    return os.environ.get("FT_SEATS_JSON") or os.path.join(os.path.dirname(CANON), "seats.json")


def _tfile(d, name):   # 이름의 팀 글자 → authoritative 명부 파일(없으면 "")
    m = re.match(r"^(?:byz|ft)-([a-z0-9]+)-", name)
    return (d + ("/seats.json" if m.group(1) == "v65" else "/seats-" + m.group(1) + ".json")) if m else ""


def _load_docs(d):
    docs, bad = {}, set()
    for f in sorted(glob.glob(d + "/seats*.json")):
        try:
            with open(f, encoding="utf-8") as fh: v = json.load(fh)
        except Exception:
            v = None
        if isinstance(v, dict): docs[f] = v
        else: bad.add(f)
    return docs, bad


def eligible(me):
    """★(이름 목록, 경고 목록)★ — 목록 맨 앞은 me, 뒤는 «가까운 옛 이름부터» 역추적한 계보.

    me 의 팀 명부 한 파일 안에서 `_replaced_by == 현재` 인 행만 따라간다(다른 팀 명부는 계보에 안 쓴다).
    명부 충돌·closed/stopped·명부 파싱 실패는 «그 지점에서 중단» — 그 이름 큐는 읽지 않고 경고 1줄.
    """
    names, warns = [me], []
    sj = _seats_json(); d = os.path.dirname(sj) or "."
    auth = _tfile(d, me)
    docs, bad = _load_docs(d)
    if auth in bad:
        return names, ["명부 읽기 실패 %s — 계보 없이 %s 큐만 읽는다" % (os.path.basename(auth), me)]
    if auth not in docs:
        return names, warns
    def holders(n): return [f for f, v in docs.items() if isinstance(v.get(n), dict)]
    if len(holders(me)) > 1:
        return names, ["명부 충돌 %s — 계보 없이 %s 큐만 읽는다" % (me, me)]
    rows = {k: v for k, v in docs[auth].items() if isinstance(v, dict)}
    todo, seen = [me], {me}
    while todo:
        cur = todo.pop(0)
        for p, row in rows.items():
            if row.get("_replaced_by") != cur or p in seen or _tfile(d, p) != auth:
                continue
            seen.add(p)
            if len(holders(p)) > 1: warns.append("명부 충돌 %s — 이 지점에서 계보 중단(%s 큐 보존)" % (p, p))
            elif row.get("role") in ("closed", "stopped"): warns.append("닫힌 좌석 %s — 이 지점에서 계보 중단(%s 큐 보존)" % (p, p))
            else:
                names.append(p); todo.append(p)
    return names, warns


def claim(dirs, names, frm, limit):
    """★선택과 소비를 «같은 잠금» 안에서 한다★ — 조회 잠금과 소비 잠금이 갈라져 있으면 옛 좌석 recv 와 후계 recv 가
    같은 행을 둘 다 읽는다. 우편함이 여럿(legacy)이면 정해진 순서로 전부 잡고 한 번에 처리한다(send 는 CANON 하나만 잡아 교착 0).
    표시 상한 밖(held)은 소비하지 않는다. 반환 = (읽은 [(디렉터리, 행)] LIFO, 남긴 [(디렉터리, 행)]).
    """
    def run(i):
        if i < len(dirs):
            return _locked(dirs[i], lambda: run(i + 1))
        per = [(d, _load(d)) for d in dirs]
        got = [(d, r) for d, rows in per for r in rows
               if r.get("to") in names and (frm is None or r.get("from") == frm)]
        got.sort(key=lambda x: x[1]["seq"], reverse=True)   # LIFO
        held = []
        if limit is not None and len(got) > limit:
            got, held = got[:limit], got[limit:]
        for d, rows in per:
            gone = {r["seq"] for dd, r in got if dd == d}
            if gone: _save(d, [r for r in rows if r.get("seq") not in gone])
        return got, held
    return run(0)
