"""ft_board_news_body — 오빠 thread 상태 답글의 본문 = Slack 4칸 (r2058 → r2095 → r2103).

머리 줄(열린·닫힌 골) → «지금»(바뀐 것 · 열린 골마다 1줄) → «다음»(열린 골마다 다음 한 수 · r2096) → «막힌 것, 오빠 할 일» → 끝 줄 «근거:».
열쇠 = standing() 줄 + «다음» 칸 줄(바뀐 것 줄 · 근거 줄 밖) — 팀 카드 수 · 좌석 · 진행 카드는 열쇠에 없다. 줄은 자르지 않는다.
r2103: 골 줄 = 막대 10칸 + n/m · 골 줄 뒤 «진행 중인 일» 묶음(열쇠 밖) · 길면 묶음 → 막대 순으로 빼고 기준판 본문으로 돌아간다.
"""
import os
import re
from datetime import datetime

from ft_board_news_name import card_tag, work_name
from ft_oppa_slack_check import OPPA_SLACK_UID

MAX_CHANGES, MAX_BYTES, MAX_DOING, BAR = 5, 3500, 8, 10
NO_NEXT = "정해진 다음 한 수 없음"
NO_TABLE = "골 진행 표 없음 — planner 원장 «## 골 진행»"
STALE = ("닫는 증거 칸", "main 밖", "좌석", "세션", "나노", "keeper")  # 원장 상태 글의 내부어(S5 · 알리기만)
STALE_DATE = re.compile(r"\(\d{2}-\d{2} 판\)")
MENTION = re.compile(r"<([@!][^<>]*)>")  # r2102 원장·카드 글의 Slack mention 꼴 → 꺾쇠를 뺀다(태그 = 도구가 붙인 1개뿐)


def quiet(s: str) -> str:
    return MENTION.sub(r"\1", s)


def closed(r: list[str]) -> bool:
    return r[2].isdigit() and r[3].isdigit() and int(r[3]) > 0 and int(r[2]) == int(r[3])


def goal_line(row: list[str], bar: bool = True) -> str:
    _, name, n, m, status = row[:5]
    text = status.replace(" · ", ", ")
    if n.isdigit() and m.isdigit() and 0 < int(m) and int(n) <= int(m):
        k = BAR * int(n) // int(m)  # 내림(r2063)
        if bar:
            return f"{name} {'▓' * k}{'░' * (BAR - k)} {n}/{m}." + (f" {text}" if text else "")
        return f"{name}: {m}단계 중 {n}단계 끝남." + (f" {text}" if text else "")
    if n in ("—", "-") or m in ("—", "-"):
        return f"{name}: {text or '상태 글 없음'}"
    return f"{name}: 수 판독 불가." + (f" {text}" if text else "")


def stale_warns(rows: list | None) -> list[str]:
    """열린 골의 원장 상태 글에 내부어 · «(MM-DD 판)» 이 있으면 골마다 WARN 1줄(글은 그대로 · 고치기 = planner)."""
    out = []
    for r in rows or []:
        hits = [] if closed(r) else [w for w in STALE if w in r[4]] + STALE_DATE.findall(r[4])
        out += [f"WARN 원장 상태 글 손볼 곳: {r[1]} — {', '.join(hits)}"] if hits else []
    return out


def standing(cur: dict, bar: bool = True) -> list[str]:
    """열쇠가 되는 본문 줄 = 머리 줄 · 열린 골 줄 · 막힌 것 칸 줄(열쇠 = 막대 꼴 · bar=False = 기준판 꼴)."""
    rows = cur["goals"]
    shut = [r[1] for r in rows or [] if closed(r)]
    top = f"골 진행 알림: 열린 골 {len(rows) - len(shut)}개, 닫힌 골 {len(shut)}개" + (f"({', '.join(shut)})" if shut else "") if rows else f"골 진행 알림: {NO_TABLE}"
    goals = [goal_line(r, bar) for r in rows or [] if not closed(r)] or (["열린 골 없음"] if rows else [])
    todo = [f"<@{os.environ.get('FT_OPPA_SLACK_UID') or OPPA_SLACK_UID}> 오빠 승인 대기 {cur['h']}건" if cur["h"] else "없음"] + [f"{t} 확인 불가(수집 실패, 직전 상태 유지)" for t in cur.get("carried", [])]
    return [top, "지금", *goals, "막힌 것, 오빠 할 일", *todo]


def news(prev: dict | None, cur: dict, nm) -> list[tuple[str, list[str]]]:
    """[(바뀐 것 줄, 카드 id들)] — 골 n·m · 끝난 일 · 수집 복구만. nm(팀, id) = 하는 일 이름."""
    if prev is None:
        return []
    out, before = [], {r[0]: r for r in prev.get("goals") or []}
    for r in cur["goals"] or []:
        p = before.get(r[0])
        if p is None:
            out.append((f"바뀜: 새 골 {r[1]}(전체 {r[3]})", []))
        elif (p[2], p[3]) != (r[2], r[3]):
            out.append((f"바뀜: {r[1]} {p[2]}단계 → {r[2]}단계(전체 {r[3]})", []))
    blind = set(cur.get("err", [])) | {t for t in prev.get("err", []) if t not in prev["cards"]}  # 모르는 팀 = 비교 0
    for team in sorted(set(cur["cards"]) & set(prev["cards"]) - blind):
        a, b = prev["cards"][team], cur["cards"][team]
        out += [(f"끝난 일: {nm(team, c)}", [c]) for c in sorted(b) if b[c] == "완성" and a.get(c) != "완성"]
    back = set(prev.get("carried", [])) - set(cur.get("err", [])) - set(cur.get("masterless", []))  # 팀장 빈 팀 = 복구 아님(N3)
    out += [(f"수집 복구: {t}", []) for t in sorted(back)]
    return out[:MAX_CHANGES] + ([(f"그 밖에 바뀐 것 {len(out) - MAX_CHANGES}개", [])] if len(out) > MAX_CHANGES else [])


def next_steps(cur: dict) -> list[str]:
    """열린 골마다 «<골 이름>: <다음 한 수>» (표 순서 · 원장 여섯째 column · 빈칸·«—» = 줄 없음)."""
    rows = [r for r in cur["goals"] or [] if not closed(r) and len(r) > 5]
    return [f"{r[1]}: {r[5].replace(' · ', ', ')}" for r in rows if r[5] not in ("", "—", "-")]


def next_key(cur: dict) -> list[str]:
    return next_steps(cur) or [NO_NEXT]


def doing(cur: dict, nm) -> tuple[list[str], int]:
    """(카드 잡은 열린 좌석 줄 «<팀>: <하는 일 이름>, <상태>» 팀 이름 순, 카드 없는 좌석 수) — 수집 실패 팀 = 빠짐(r2063)."""
    live = sorted((v[0], n, v) for n, v in (cur.get("sessions") or {}).items() if v[0] not in cur.get("err", []))
    return [quiet(f"{t}: {nm(t, v[1])}, {v[2]}") for t, _, v in live if v[1] != "—"], sum(v[1] == "—" for _, _, v in live)


def doing_lines(rows: list[str], bare: int, k: int) -> list[str]:
    """«진행 중인 일» 묶음 — 상세 줄 앞 k 개 + «그 밖 N개» + «카드 없이 열린 좌석 N석» · 열린 좌석 0 = «진행 중인 일 없음»."""
    if not rows and not bare:
        return ["진행 중인 일 없음"]
    more = [f"그 밖 {len(rows) - k}개"] if k < len(rows) else []
    return ["진행 중인 일", *rows[:k], *more, *([f"카드 없이 열린 좌석 {bare}석"] if bare else [])]


def body(cur: dict, prev: dict | None, now: datetime, sha: str, tt: dict | None = None) -> str:
    """본문 — 3500B 를 넘으면 ⓐ 진행 줄을 아래부터 → ⓑ 묶음을 통째로 → ⓒ 막대를 모두 빼고(= 기준판 본문)
    → ⓓ «다음» 칸 줄을 아래부터 빼고 «그 밖의 골 N개» 로 맺는다. 상한 안 첫 단계에서 멈춘다(골 줄 · 상태 글은 줄이지 않음 · r2103 A4)."""
    nm = lambda team, cid: work_name(cid, (tt or {}).get(team, {}).get(cid))  # noqa: E731
    fresh = [(quiet(t), ids) for t, ids in news(prev, cur, nm)]
    rows = [[quiet(c) for c in r] for r in cur["goals"]] if cur["goals"] else cur["goals"]
    cur = {**cur, "goals": rows, "carried": [quiet(t) for t in cur.get("carried", [])]}
    tags = list(dict.fromkeys(g for _, ids in fresh for c in ids if (g := card_tag(c))))  # 근거 줄 번호
    tail = f"근거: 발행 {now:%Y-%m-%d %H:%M}, 골 진행 원장 {sha}" + (f", 카드 {' '.join(tags)}" if tags else "")
    steps = next_steps(cur)

    def text(st: list[str], grp: list[str], nxt: list[str]) -> str:
        cut = st.index("막힌 것, 오빠 할 일")
        return "\n".join([*st[:2], *[t for t, _ in fresh], *st[2:cut], *grp, "다음", *nxt, *st[cut:], tail]) + "\n"
    rows, bare = doing(cur, nm)
    st = standing(cur)
    for grp in [doing_lines(rows, bare, k) for k in range(min(MAX_DOING, len(rows)), -1, -1)] + [[]]:  # ⓐ · ⓑ
        if len((out := text(st, grp, steps or [NO_NEXT])).encode()) <= MAX_BYTES:
            return out
    st = standing(cur, bar=False)  # ⓒ · ⓓ = 기준판(r2102) 본문
    for k in range(len(steps), -1, -1):
        nxt = steps[:k] + ([f"그 밖의 골 {len(steps) - k}개"] if k < len(steps) else []) if steps else [NO_NEXT]
        out = text(st, [], nxt)
        if len(out.encode()) <= MAX_BYTES:
            break
    return out
