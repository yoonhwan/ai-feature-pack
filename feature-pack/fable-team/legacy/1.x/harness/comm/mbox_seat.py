#!/usr/bin/env python3
"""r1657 단계 1 — master 석 쪽지 길(받는 이 결정 1곳 = mbox_guard.sh guard_check 가 부른다).

mbox_seat.py <명부 폴더> <받는 이> <본문> → stdout 1줄 = 실제 받는 이(바꿀 것 없으면 받는 이 그대로) · rc 0.
  · 받는 이가 어느 명부 `_master`(석 0) 우편함일 때만 본다 · 석 K≥1 이름으로 직접 보낸 쪽지는 그대로.
  · 명부 `_master-<K>` 가 다 빈 값 = 석 1 없음 = 지금과 같다(받는 이 그대로).
  · 본문 머리 400자의 첫 카드 참조(r<번호>) → 대기·진행 카드의 `- 담당 석: <K>` → `_master-<K>` 값.
  · 석 0 으로 가는 것: 머리 [HIL]·[부팅]·[인계]·오빠 지시 · 참조 없음 · 카드 못 찾음 · 담당 석 빈 값·꼴 밖 · `_master-<K>` 빈 값.
  · 카드 폴더 = env FT_CARDS_DIR(시험) → <루트>/.worktrees/<_cards_wt>/<_cards> → <루트>/<_cards>.
판정 불가(명부·카드 못 읽음)는 받는 이 그대로(지금 길 · 조용한 다른 석 0)."""

import glob
import json
import os
import re
import sys

HUMAN = re.compile(r"\s*(\[HIL[\]·]|\[부팅\]|\[인계\]|\[오빠|오빠 지시)")
REF = re.compile(r"(?<![A-Za-z0-9])r(\d+[a-z]?)(?![A-Za-z0-9])")
SEAT = re.compile(r"^- 담당 석:[ \t]*(0|[1-9][0-9]*)[ \t]*$", re.M)


def rk(n):
    return re.sub(r"#\d+$", "", n or "")  # 우편함 키 = 역할 이름(mbox_conf.role_key 와 같은 규칙)


def seats_of(
    dd,
):  # 명부 → {K: 이름} · `_master`(K=0)·`_master-<K>` 중 빈 값 아닌 칸(ft_roster_lib.role_seats 와 같은 규칙)
    ms = ((re.fullmatch(r"_master(?:-([1-9][0-9]*))?", c), v) for c, v in dd.items())
    return {int(m.group(1) or 0): v for m, v in ms if m and isinstance(v, str) and v}


def card_seat(path):  # 카드 머리(첫 «## » 앞)의 `- 담당 석: <K>` → K · 없음·꼴 밖·못 읽음 = 0
    try:
        head = open(path, encoding="utf-8").read().split("\n## ", 1)[0]
    except OSError:
        return 0
    m = SEAT.search(head)
    return int(m.group(1)) if m else 0


def cards_dir(root, dd):
    if os.environ.get("FT_CARDS_DIR"):
        return os.environ["FT_CARDS_DIR"]
    c, wt = dd.get("_cards") or "", dd.get("_cards_wt") or ""
    for p in ([os.path.join(root, ".worktrees", wt, c)] if wt else []) + [os.path.join(root, c)]:
        if c and os.path.isdir(p):
            return p
    return ""


def seat_for(body, cdir):  # 쪽지 → 담당 석 K(석 0 이 기본)
    head = body[:400]
    if HUMAN.match(head):
        return 0
    m = REF.search(head)
    if not m or not cdir:
        return 0
    hit = sorted(
        glob.glob(os.path.join(cdir, "대기", "r%s-*.md" % m.group(1)))
        + glob.glob(os.path.join(cdir, "진행", "r%s-*.md" % m.group(1)))
    )
    return card_seat(hit[0]) if hit else 0


def route(sdir, to, body):
    for f in sorted(glob.glob(os.path.join(sdir, "seats*.json"))):
        try:
            dd = json.load(open(f, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(dd, dict):
            continue
        s = seats_of(dd)
        if 0 not in s or rk(s[0]) != rk(to):
            continue
        if len(s) == 1:
            return to  # 석 1 없음 = 지금과 같다
        k = seat_for(body, cards_dir(os.path.dirname(os.path.abspath(sdir)), dd))
        return s.get(k) if k and s.get(k) else to
    return to


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("usage: mbox_seat.py <명부 폴더> <받는 이> <본문>", file=sys.stderr)
        sys.exit(2)
    print(route(*sys.argv[1:4]))
