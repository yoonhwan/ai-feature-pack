# r1981 — mbox.py 의 peek 명령(읽기만) · CANON 은 mbox.py 가 묶는다 · 200줄 규칙 분리(동작 변경 0).
import os   # r2213 — batched 칸(FT_MBOX_NOW)
import time   # r2213 — batched 칸(시계 · 로컬 시각)
from mbox_conf import *
from mbox_store import _check_name, _legacy_dirs, _load, _locked
from mbox_ops import _lineage   # recv·peek 같은 계보 칸(r1854)
from mbox_lineage import takeable   # recv(claim)와 같은 거르개 함수(r2146 K1)
CANON = None   # mbox.py 가 묶는다


def _int(w):   # r2213 — JS Number.isInteger 와 같은 칸(참거짓·글자·소수·NaN = 아님)
    return isinstance(w, (int, float)) and not isinstance(w, bool) and float(w).is_integer()


def _batched(rows, me):
    """r2213 — 묶음 대기 칸 « batched=<수> wake=<HH:MM>» | "" · 확장 ft-mbox-wake.ts check() 와 같은 칸.

    rows = 정본 우편함 행 · 셈 = to == me ∧ from ≠ me(확장 mine()) · 8통 이상 = 0(ⓔ) ·
    묶음 = wake_at 정수 ∧ 0 이상 ∧ 지금+3600초 이하(wakeOk) ∧ 지금보다 미래 · 지금 = FT_MBOX_NOW | 시스템 시각.
    """
    try:
        now = int(float(os.environ.get("FT_MBOX_NOW") or time.time()) // 1)
    except ValueError:
        return ""
    own = [r for r in rows if r.get("to") == me and r.get("from") != me]
    if len(own) >= 8:
        return ""
    held = [r["wake_at"] for r in own if _int(r.get("wake_at")) and 0 <= r["wake_at"] <= now + 3600 and r["wake_at"] > now]
    return f" batched={len(held)} wake={time.strftime('%H:%M', time.localtime(min(held)))}" if held else ""


def peek(me, rows=False):
    """pending=N …1줄 · rows=True(=`peek --rows`)면 미읽음마다 JSON 1줄(seq·ts·to·from·body)을 더 찍는다.

    줄의 집합 = 아래 pending 을 세는 그 목록 그대로다(계보 옛 이름·옛 우편함 포함 · 옛 이름 선택 규칙을 새로 만들지 않는다).
    읽기만 한다 — mark·recv·큐 쓰기 0. keeper 의 쉼 판정(카드 ft2-done-seat-short-idle A4)이 이 줄을 읽는다.
    """
    _check_name(me)
    dirs = [CANON] + _legacy_dirs()
    names, joined = _lineage(me)
    mine, take, canon = [], takeable(names, me), []
    for d in dirs:
        got = [r for r in _locked(d, lambda d=d: _load(d)) if take(r)]   # recv 와 같은 규칙(r1153 · r2146)
        mine.extend(got)
        if d == CANON:
            canon = got   # r2213 — batched · 8통 셈 = 정본 우편함 행만(옛 우편함 0)
    mine.sort(key=lambda r: r["seq"], reverse=True)
    head = f"pending={len(mine)}"
    if mine:
        head += f" latest_seq={mine[0]['seq']} from={mine[0]['from']}"
    print(f"{head} scanned={len(dirs)} lineage={joined}{_batched(canon, me)}")
    if rows:
        for r in sorted(mine, key=lambda r: r["seq"]):
            print(json.dumps({"seq": r["seq"], "ts": r.get("ts"), "to": r.get("to"), "from": r.get("from"),
                              "body": r.get("body", "")}, ensure_ascii=False))

