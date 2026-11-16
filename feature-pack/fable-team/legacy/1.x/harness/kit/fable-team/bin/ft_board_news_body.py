"""ft_board_news_body — 오빠 thread 상태 답글의 본문 그리기 (r2058 · ft_board_news.py 에서 뗌 r2095 [structure])."""
import re
from datetime import datetime

from ft_board_news_name import card_disp, card_tag, work_name

MAX_CHANGES, MAX_SEATS, MAX_LINE = 5, 12, 150
NO_TABLE = "골 진행 표 없음 — planner 원장 «## 골 진행»"


def goal_line(row: list[str]) -> str:
    _, name, n, m, status = row
    if n in ("—", "-") or m in ("—", "-"):
        return f"{name} — {status}"
    if not (n.isdigit() and m.isdigit()) or int(m) == 0 or int(n) > int(m):
        return f"{name} 수 판독 불가"
    k = 10 * int(n) // int(m)  # 내림(r2063) — 10칸은 n = m 일 때만
    return f"{name} `{'▓' * k}{'░' * (10 - k)}` {n}/{m}" + (" 완성" if n == m else "")


def seat_short(name: str) -> str:
    s = re.sub(r"^byz-[^-]+-", "", re.sub(r"#\d+$", "", name))
    return re.sub(r"(^|-)r\d+[a-z]?(?=-)", r"\1", s).replace("--", "-")


def changes(prev: dict | None, cur: dict, nm=lambda team, cid: card_disp(cid)) -> list[str]:
    return [t for t, _ in _changes(prev, cur, nm)]


def _changes(prev: dict | None, cur: dict, nm) -> list[tuple[str, list[str]]]:  # [(② 줄, 카드 id들)] · nm(팀, id) = 하는 일 이름(R5)
    if prev is None:
        return [("첫 발행 — 직전 발행 없음", [])]
    out, before = [], {r[0]: r for r in prev.get("goals") or []}
    for r in cur["goals"] or []:
        p = before.get(r[0])
        if p is None or (p[2], p[3]) != (r[2], r[3]):
            out.append((f"{r[1]} {p[2] if p else '—'}→{r[2]} ({r[3]} 중)", []))
    blind = set(cur.get("err", [])) | {t for t in prev.get("err", []) if t not in prev["cards"]}  # 모르는 팀 = 비교 0
    out += [(f"{t} 수집 복구", []) for t in sorted(set(prev.get("err", [])) - set(cur.get("err", [])))]
    for team in sorted((set(prev["cards"]) | set(cur["cards"])) - blind):
        a, b = prev["cards"].get(team, {}), cur["cards"].get(team, {})
        out += [(f"{team} {nm(team, c)} {a.get(c, '없음')}→{b.get(c, '없음')}", [c]) for c in sorted(set(a) | set(b)) if a.get(c) != b.get(c)]
    ps, cs = prev["sessions"], cur["sessions"]
    for n in sorted(set(ps) | set(cs)):
        if (cs.get(n) or ps[n])[0] in blind:
            continue
        if n not in ps or n not in cs:
            out.append((f"{seat_short(n)} {'열림' if n in cs else '닫힘'}", []))
        elif ps[n][1] != cs[n][1]:
            out.append((f"{seat_short(n)} 카드 {nm(cs[n][0], ps[n][1])}→{nm(cs[n][0], cs[n][1])}", [ps[n][1], cs[n][1]]))
    out = out or [("세부 줄 없음 — 카드 수만 바뀜", [])]
    return out[:MAX_CHANGES] + ([(f"외 {len(out) - MAX_CHANGES}건", [])] if len(out) > MAX_CHANGES else [])


def body(cur: dict, prev: dict | None, now: datetime, sha: str, tt: dict | None = None) -> str:
    nm = lambda team, cid: work_name(cid, (tt or {}).get(team, {}).get(cid))  # noqa: E731
    news = _changes(prev, cur, nm)
    tags = list(dict.fromkeys(g for _, ids in news for c in ids if (g := card_tag(c))))  # 근거 줄 번호(R6)
    goals = [goal_line(r) for r in cur["goals"]] if cur["goals"] else [NO_TABLE]
    err = cur.get("err", [])
    live = sorted(((n, v) for n, v in cur["sessions"].items() if v[0] not in err), key=lambda x: (x[1][0], x[0]))  # 카드 없는 좌석 = 접는 줄(r2063)
    seats, bare = [f"{v[0]} · {seat_short(n)} · {nm(v[0], v[1])} · {v[2]}" for n, v in live if v[1] != "—"], sum(v[1] == "—" for _, v in live)
    seats = (seats[:MAX_SEATS] + [f"외 {len(seats) - MAX_SEATS}석"] if len(seats) > MAX_SEATS else seats) + ([f"카드 없이 열린 좌석 {bare}석"] if bare else []) or ["열린 팀 세션 없음"]
    todo = f"오빠 승인 대기 {cur['h']}건" if cur["h"] else "없음"
    lines = ["① 골 진행", *goals, "② 지금", *[t for t, _ in news], "③ 다음", *seats, "④ 막힌 것·오빠 할 일", todo,
             *[f"{t} 확인 불가 — 수집 실패 · 직전 상태 유지" for t in cur.get("carried", [])]]
    lines = [ln if len(ln) <= MAX_LINE else ln[:MAX_LINE - 1] + "…" for ln in lines]
    tail = f"근거: 발행 {now:%Y-%m-%d %H:%M} · 골 진행 원장 {sha}" + (f" · 카드 {' '.join(tags)}" if tags else "")
    return "\n".join(lines + [tail]) + "\n"
