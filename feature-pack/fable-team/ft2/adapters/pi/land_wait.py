"""r2297 착지 대기 거짓 경보 판독 — transition_watch 가 부른다(카드 본문만 · git 0 · 쓰기 0 · 사전 DA#33 조건부 APPROVE-DESIGN).
A1 «- 착지 대상: 없음» 표지 · A2 «## 상태» 끝 줄 중단·대체·거절(keeper_endings._head 그대로 부름) · A3 «- 착지: » 꼴 틀림 이름표 · A4 두 ref 사본 = 상태 마지막 날짜 줄이 늦은 쪽.
"""
import re

MARK, LOOSE, DATE = re.compile(r"^- 착지 대상: 없음", re.M), re.compile(r"^- 착지: ", re.M), re.compile(r"\d{4}-\d{2}-\d{2}")


def skip(endings, body):   # A1·A2 — 착지 줄이 생길 수 없는 카드 = True
    return bool(MARK.search(body)) or endings._head(body) is not None


def text(stem, body, mins):   # A3 — 40hex 착지 줄 0 · «- 착지: » 줄 있음 = 꼴 틀림 · 없음 = r2293 그대로
    return "%s 착지 줄 꼴 틀림(40hex 0) · 세트 뒤 %d분" % (stem, mins) if LOOSE.search(body) else "%s 세트 뒤 %d분 · 착지 줄 0" % (stem, mins)


def stamp(body):   # «## 상태» 절 마지막 날짜 줄의 날짜(YYYY-MM-DD) · 없음 = ""
    part = re.split(r"^## 상태[ \t]*$", body, maxsplit=1, flags=re.M)
    rows = re.split(r"^## ", part[1], maxsplit=1, flags=re.M)[0].splitlines() if len(part) == 2 else []
    return next((m.group(0) for row in reversed(rows) if (m := DATE.search(row))), "")


def pick(copies):   # A4 같은 (팀 · stem) 사본(REFS 차례 · ref 마다 1장) → 1장 · 날짜가 더 늦은 사본만 앞 ref 를 이김 · 같음·판독 불가 = 앞 ref
    best = copies[0]
    for c in copies[1:]:
        a, b = stamp(best["body"]), stamp(c["body"])
        best = c if a and b and b > a else best
    return best
