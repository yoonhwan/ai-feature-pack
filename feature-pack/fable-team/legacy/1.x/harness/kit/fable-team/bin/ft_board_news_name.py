"""ft_board_news_name — 오빠 thread 답글 본문의 카드 «하는 일 이름» · 근거 줄 카드 번호 (r2058 보정 3 R5·R6).

이름은 본문 만들 때만 계산한다 — 열쇠·snap 에 넣지 않는다(제목만 바뀌면 발행 0). 수집기 손 0: collect dict 의 카드 제목을 읽는다.
"""
import re

MAX_NAME = 24


def card_disp(cid: str) -> str:
    return re.sub(r"^r\d+[a-z]?-", "", cid)


def titles(d: dict) -> dict:
    """{팀 label: {카드 id: 제목}} — axes entries(k=card) 먼저 · 없으면 progress·queue title · 수집 실패 팀 = 없음."""
    out = {}
    for t in d.get("teams", []):
        if "error" in t:
            continue
        got = {q["idx"]: q.get("title") for q in t.get("queue") or [] if q.get("idx")}
        got.update({c: p.get("title") for c, p in (t.get("progress") or {}).items()})
        got.update({e["idx"]: e.get("text") for ax in t.get("axes") or [] for e in ax.get("entries") or [] if e.get("k") == "card" and e.get("idx")})
        out[t["label"]] = {c: v for c, v in got.items() if v}
    return out


def work_name(cid: str, title: str | None) -> str:
    """제목 → 하는 일 이름(id·«끝:» 떼기 → 첫 «(» 뒤 버림 → 번호 꼴 지움 → 24자) · 못 만들면 slug."""
    s = (title or "").strip()
    if not s or s == cid or s.endswith("(제목 없음)"):
        return card_disp(cid)
    if s.startswith(cid):
        s = s[len(cid):].lstrip(" —-:").strip()
        s = s.removeprefix("끝:").strip()
    s = s.split("(", 1)[0]
    s = " ".join(re.sub(r"r\d{3,}|#\d+", "", s).split())
    if not s:
        return card_disp(cid)
    return s if len(s) <= MAX_NAME else s[:MAX_NAME] + "…"


def card_tag(cid: str) -> str | None:
    """근거 줄 카드 번호 = id 맨 앞 «영문 1~3자 + 숫자» 토막(r1483 · L102) · 없으면 None."""
    m = re.match(r"[A-Za-z]{1,3}\d+", cid)
    return m.group(0) if m else None
