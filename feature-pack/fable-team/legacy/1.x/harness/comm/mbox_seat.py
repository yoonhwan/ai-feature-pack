#!/usr/bin/env python3
"""r1657 단계 1 — master 석 쪽지 길(받는 이 결정 1곳 = mbox_guard.sh guard_check 가 부른다).

mbox_seat.py <명부 폴더> <받는 이> <본문> → stdout 1줄 = 실제 받는 이(바꿀 것 없으면 받는 이 그대로) · rc 0.
  · 받는 이가 어느 명부 master 석(`_master`·`_master-<K>`) 우편함이면 본다 · 명부 `_master-<K>` 가 다 빈 값 = 지금과 같다(받는 이 그대로).
  · 머리 [HIL]·오빠 지시 = 석 0(`_master` 값 · 석 1 직접이어도).
  · 머리 [부팅]·[인계]·[레디] = 받는 주소 그대로(석 0 주소 = 석 0 · 석 1 직접 = 석 1 승계 사슬).
  · 본문 머리 400자 첫 카드 참조(r<번호>) → 진행 → 대기 → 완성 → 아카이브(월 폴더 포함) 순서로 찾은 카드의 `- 담당 석: <K>` → `_master-<K>` 값.
  · 참조 없음·카드 못 찾음 = 받는 주소 그대로(석 0 주소 = 석 0 · 석 1 직접 = 보낸 이가 고른 석 1) · 담당 석 빈 값·꼴 밖·`_master-<K>` 빈 값 = 석 0.
  · 카드 폴더 = env FT_CARDS_DIR(시험) → <루트>/.worktrees/<_cards_wt>/<_cards> → <루트>/<_cards>.
판정 불가(명부·카드 못 읽음)는 받는 이 그대로(지금 길 · 조용한 다른 석 0)."""

import glob
import json
import os
import re
import sys

PERSON = re.compile(r"\s*(\[HIL[\]·]|\[오빠|오빠 지시)")  # 사람 창구 머리 = 어느 주소로 와도 석 0
HUMAN = re.compile(r"\s*(\[부팅\]|\[인계\]|\[레디\])")  # 승계·부팅 머리 = 받는 주소 그대로
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


def card_of(
    head, cdir
):  # 첫 카드 참조 → 카드 경로 · 찾기 순서 = 진행 → 대기 → 완성 → 아카이브(월 폴더 포함 · DA#10 R1 · arch cbcc46453a) · 없음 = ""
    m = REF.search(head)
    if not m or not cdir:
        return ""
    for st in ("진행", "대기", "완성", "아카이브"):
        hit = sorted(
            glob.glob(os.path.join(cdir, st, "**", "r%s-*.md" % m.group(1)), recursive=True)
        )
        if hit:
            return hit[0]
    return ""


def route(sdir, to, body):
    for f in sorted(glob.glob(os.path.join(sdir, "seats*.json"))):
        try:
            dd = json.load(open(f, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(dd, dict):
            continue
        s = seats_of(dd)
        if 0 not in s or rk(to) not in {rk(v) for v in s.values()}:
            continue
        if len(s) == 1:
            return to  # 석 1 없음 = 지금과 같다
        head = body[:400]
        if PERSON.match(head):
            return to if rk(to) == rk(s[0]) else s[0]  # [HIL]·오빠 지시 = 사람 창구 석 0 하나(직접 석 1 이어도 · R2 ①)
        if HUMAN.match(head):
            return to  # [부팅]·[인계]·[레디]: 석 0 주소 = 석 0 · 석 1 직접 = 석 1 승계 사슬 그대로(R2 ③)
        card = card_of(head, cards_dir(os.path.dirname(os.path.abspath(sdir)), dd))
        if not card:
            return to  # 카드 없음: 석 0 주소 = 석 0 · 석 1 직접 = 석 1 그대로(R2 ②)
        k = card_seat(card)
        k = k if k in s else 0
        return (
            to if rk(s[k]) == rk(to) else s[k]
        )  # 카드 참조 = 그 카드 담당 석(직접 석 1 도 같은 규칙 · R2 ④)
    return to


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("usage: mbox_seat.py <명부 폴더> <받는 이> <본문>", file=sys.stderr)
        sys.exit(2)
    print(route(*sys.argv[1:4]))
