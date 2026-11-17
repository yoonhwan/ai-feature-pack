"""ft_board_news_name — 오빠 thread 답글 본문의 카드 «하는 일 이름» · 근거 줄 카드 번호 (r2058 보정 3 R5·R6).

이름은 본문 만들 때만 계산한다 — 열쇠·snap 에 넣지 않는다(제목만 바뀌면 발행 0). 수집기 손 0: collect dict 의 카드 제목을 읽는다.
r2184: shorten = 다 접어도 넘는 본문의 골 상태 글 줄임(ⓔ · body 가 부른다 · 본문만 · 열쇠 밖).
"""
import re
from itertools import zip_longest

MAX_NAME = 24
FLOOR = 150  # r2184 공통 상한 C 의 바닥(B)
NOTE = "상태 글 {}개는 길어서 줄였습니다, 전문은 골 진행 원장"


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


def keep_len(line: str, status: str, mark: str) -> int:
    """줄이지 않는 앞 글자 수 = 골 이름 · 단계 글 · 원장 표지 — 상태 글이 줄 끝에 없으면 줄 전체."""
    s = status.replace(" · ", ", ")
    if not s or not line.endswith(s):
        return len(line)
    return len(line) - len(s) + (len(mark) + 1 if mark and s.startswith(mark + " ") else 0)


def clip(line: str, keep: int, cap: int) -> str | None:
    """cap 바이트 안 — 뒤를 UTF-8 글자 경계에서 잘라 «…»(3B) · 앞 keep 글자까지 잘리면 None."""
    raw = line.encode()
    if len(raw) <= cap:
        return line
    head = raw[:max(cap - 3, 0)].decode(errors="ignore")  # 끝에 걸린 글자 조각만 버린다
    return head + "…" if len(head) >= keep else None


def shorten(st: list[str], statuses: list[str], mark: str, render, limit: int) -> str | None:
    """ⓔ(r2184) 골 줄(st[2:막힌 것]) 모두에 같은 상한 C · 맞는 C 중 가장 큰 값(바닥 FLOOR) · 알림 줄 포함 · 못 맞추면 None."""
    cut = st.index("막힌 것, 오빠 할 일")
    goals = st[2:cut]
    keeps = [keep_len(g, s, mark) for g, s in zip_longest(goals, statuses[:len(goals)], fillvalue="")]
    for cap in range(max((len(g.encode()) for g in goals), default=0) - 1, FLOOR - 1, -1):
        got = [clip(g, k, cap) for g, k in zip(goals, keeps)]
        if None in got:  # 골 이름 · 표지를 깎아야 맞음 = 더 작은 C 도 못 맞춤
            return None
        out = render([*st[:2], *got, NOTE.format(sum(a != b for a, b in zip(got, goals))), *st[cut:]])
        if len(out.encode()) <= limit:
            return out
    return None
