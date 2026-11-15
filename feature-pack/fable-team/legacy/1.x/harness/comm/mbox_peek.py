# r1981 — mbox.py 의 peek 명령(읽기만) · CANON 은 mbox.py 가 묶는다 · 200줄 규칙 분리(동작 변경 0).
from mbox_conf import *
from mbox_store import _check_name, _legacy_dirs, _load, _locked
from mbox_ops import _lineage   # recv·peek 같은 계보 칸(r1854)
CANON = None   # mbox.py 가 묶는다


def peek(me, rows=False):
    """pending=N …1줄 · rows=True(=`peek --rows`)면 미읽음마다 JSON 1줄(seq·ts·to·from·body)을 더 찍는다.

    줄의 집합 = 아래 pending 을 세는 그 목록 그대로다(계보 옛 이름·옛 우편함 포함 · 옛 이름 선택 규칙을 새로 만들지 않는다).
    읽기만 한다 — mark·recv·큐 쓰기 0. keeper 의 쉼 판정(카드 ft2-done-seat-short-idle A4)이 이 줄을 읽는다.
    """
    _check_name(me)
    dirs = [CANON] + _legacy_dirs()
    names, joined = _lineage(me)
    mine = []
    for d in dirs:
        mine.extend(r for r in _locked(d, lambda d=d: _load(d))
                    if role_key(r.get("to")) in {role_key(n) for n in names} and r.get("from") != me)   # recv 와 같은 규칙(r1153)
    mine.sort(key=lambda r: r["seq"], reverse=True)
    head = f"pending={len(mine)}"
    if mine:
        head += f" latest_seq={mine[0]['seq']} from={mine[0]['from']}"
    print(f"{head} scanned={len(dirs)} lineage={joined}")
    if rows:
        for r in sorted(mine, key=lambda r: r["seq"]):
            print(json.dumps({"seq": r["seq"], "ts": r.get("ts"), "to": r.get("to"), "from": r.get("from"),
                              "body": r.get("body", "")}, ensure_ascii=False))

