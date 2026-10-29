# mbox.py 의 recv/peek 계보 합류(P1) — 승계된 옛 이름 큐를 후계가 한 번에 읽는다 · CANON 은 mbox.py 가 묶는다 · 200줄 규칙 분리.
#   send 는 은퇴 수신자를 막고(N3 가드) recv 는 계보를 읽는다 — 비대칭이 설계다(PLAN-planner-no-stall r5 §4-1).
#   계보 규칙은 mbox_guard.sh 의 명부 규칙(tfile 팀 명부 · _replaced_by · 명부 충돌 · closed/stopped)과 같다. 외부 호출 0(json·큐 파일만).
from mbox_conf import *
from mbox_store import _load, _locked, _save
import mbox_teamfile   # 명부 파일 고르기 = mbox_guard.sh 와 «같은 함수»(개명 별칭 · r745)
CANON = None   # mbox.py 가 묶는다


def _seats_json():   # mbox.sh 의 _seats_json 과 같은 규칙: env 가 이기고, 없으면 정본 우편함 옆 seats.json
    return os.environ.get("FT_SEATS_JSON") or os.path.join(os.path.dirname(CANON), "seats.json")


def _tfile(d, name, docs, bad):   # 이름의 팀 글자 → authoritative 명부 파일(없으면 "") · 개명 별칭은 공용 모듈 1개가 정한다(r745)
    return mbox_teamfile.teamfile(d, name, docs, bad)[0]


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
    docs, bad = _load_docs(d)
    auth, awarn = mbox_teamfile.teamfile(d, me, docs, bad)
    if awarn: warns.append(awarn)
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
            if row.get("_replaced_by") != cur or p in seen or _tfile(d, p, docs, bad) != auth:
                continue
            seen.add(p)
            if len(holders(p)) > 1: warns.append("명부 충돌 %s — 이 지점에서 계보 중단(%s 큐 보존)" % (p, p))
            elif row.get("role") in ("closed", "stopped"): warns.append("닫힌 좌석 %s — 이 지점에서 계보 중단(%s 큐 보존)" % (p, p))
            else:
                names.append(p); todo.append(p)
    return names, warns


def _team_rows(name):   # (그 이름 팀 명부의 좌석 행 dict, 그 이름 행) — 명부 없음·깨짐 = ({}, None)
    d = os.path.dirname(_seats_json()) or "."
    docs, bad = _load_docs(d)
    auth = mbox_teamfile.teamfile(d, name, docs, bad)[0]
    rows = {k: v for k, v in docs.get(auth, {}).items() if isinstance(v, dict)}
    return rows, rows.get(name)


def retired_to(me):
    """★현역만 recv(r1116)★ — me 행에 `_replaced_by` 가 있으면 사슬 끝 후계 이름, 현역·미등록이면 "". 옛·새 동시 생존 때 옛 세션이 역할 우편함을 못 가져가게."""
    rows, row = _team_rows(me)
    cur, seen = me, {me}
    while isinstance(row, dict) and row.get("_replaced_by") and row["_replaced_by"] not in seen:
        cur = row["_replaced_by"]; seen.add(cur); row = rows.get(cur)
    return "" if cur == me else cur


def holder(name):
    """doorbell·ring 대상 = 그 역할의 현역 세션(r1116 R7). 명부 이름이면 사슬 끝 · 번호 없는 역할 이름이면 같은 역할 현역 행(번호 큰 것) · 못 찾으면 그대로."""
    cur = retired_to(name)
    if cur:
        return cur
    rows, row = _team_rows(name)
    if isinstance(row, dict):
        return name
    live = [k for k, v in rows.items() if role_key(k) == role_key(name) and not v.get("_replaced_by")
            and v.get("role") not in ("closed", "stopped")]
    num = lambda k: int(k.rsplit("#", 1)[1]) if re.search(r"#\d+$", k) else -1
    return max(live, key=num) if live else name


def claim(dirs, names, frm, limit, me=None, on_take=None, only=None):
    """★선택과 소비를 «같은 잠금» 안에서 한다★ — 조회 잠금과 소비 잠금이 갈라져 있으면 옛 좌석 recv 와 후계 recv 가
    같은 행을 둘 다 읽는다. 우편함이 여럿(legacy)이면 정해진 순서로 전부 잡고 한 번에 처리한다(send 는 CANON 하나만 잡아 교착 0).
    표시 상한 밖(held)은 소비하지 않는다. 반환 = (읽은 [(디렉터리, 행)] LIFO, 남긴 [(디렉터리, 행)]).
    ★비교 키 = 역할 이름(r1116)★ — names 의 역할 키 집합과 `to` 의 역할 키가 같으면 내 것(옛 번호·새 번호·번호 없음 전부).
    me 가 보낸 행은 안 가져간다(같은 역할 옛·새 세션 사이 [인계]·[레디]) · only = 추가 거르개 · on_take(행들) = 소비 «전» 영수 기록(실패 = raise → 큐 무변경).
    """
    keys = {role_key(n) for n in names}
    def run(i):
        if i < len(dirs):
            return _locked(dirs[i], lambda: run(i + 1))
        per = [(d, _load(d)) for d in dirs]
        got = [(d, r) for d, rows in per for r in rows
               if role_key(r.get("to")) in keys and (frm is None or r.get("from") == frm)
               and (me is None or r.get("from") != me) and (only is None or only(r))]
        got.sort(key=lambda x: x[1]["seq"], reverse=True)   # LIFO
        held = []
        if limit is not None and len(got) > limit:
            got, held = got[:limit], got[limit:]
        if on_take and got: on_take([r for _, r in got])
        for d, rows in per:
            gone = {r["seq"] for dd, r in got if dd == d}
            if gone: _save(d, [r for r in rows if r.get("seq") not in gone])
        return got, held
    return run(0)
