"""ft_board_news_body — 오빠 thread 상태 답글의 본문 = Slack 4칸 (r2058 → r2095).

머리 줄(열린·닫힌 골) → «지금»(바뀐 것 · 열린 골마다 1줄) → «다음»(열린 골마다 다음 한 수 · r2096) → «막힌 것, 오빠 할 일» → 끝 줄 «근거:».
열쇠 = standing() 줄 + «다음» 칸 줄(바뀐 것 줄 · 근거 줄 밖) — 팀 카드 수 · 좌석 · 진행 카드는 열쇠에 없다. 줄은 자르지 않는다.
"""
import os
import re
from datetime import datetime

from ft_board_news_name import card_tag, work_name
from ft_oppa_slack_check import OPPA_SLACK_UID

MAX_CHANGES, MAX_BYTES = 5, 3500
NO_NEXT = "정해진 다음 한 수 없음"
NO_TABLE = "골 진행 표 없음 — planner 원장 «## 골 진행»"
STALE = ("닫는 증거 칸", "main 밖", "좌석", "세션", "나노", "keeper")  # 원장 상태 글의 내부어(S5 · 알리기만)
STALE_DATE = re.compile(r"\(\d{2}-\d{2} 판\)")


def closed(r: list[str]) -> bool:
    return r[2].isdigit() and r[3].isdigit() and int(r[3]) > 0 and int(r[2]) == int(r[3])


def goal_line(row: list[str]) -> str:
    _, name, n, m, status = row[:5]
    text = status.replace(" · ", ", ")
    if n.isdigit() and m.isdigit() and 0 < int(m) and int(n) <= int(m):
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


def standing(cur: dict) -> list[str]:
    """열쇠가 되는 본문 줄 = 머리 줄 · 열린 골 줄 · 막힌 것 칸 줄."""
    rows = cur["goals"]
    shut = [r[1] for r in rows or [] if closed(r)]
    top = f"골 진행 알림: 열린 골 {len(rows) - len(shut)}개, 닫힌 골 {len(shut)}개" + (f"({', '.join(shut)})" if shut else "") if rows else f"골 진행 알림: {NO_TABLE}"
    goals = [goal_line(r) for r in rows or [] if not closed(r)] or (["열린 골 없음"] if rows else [])
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


def body(cur: dict, prev: dict | None, now: datetime, sha: str, tt: dict | None = None) -> str:
    """본문 — 3500B 를 넘으면 «다음» 칸 줄을 아래부터 빼고 «그 밖의 골 N개» 로 맺는다(골 줄 · 상태 글은 줄이지 않음)."""
    nm = lambda team, cid: work_name(cid, (tt or {}).get(team, {}).get(cid))  # noqa: E731
    fresh = news(prev, cur, nm)
    tags = list(dict.fromkeys(g for _, ids in fresh for c in ids if (g := card_tag(c))))  # 근거 줄 번호
    st = standing(cur)
    cut = st.index("막힌 것, 오빠 할 일")
    tail = f"근거: 발행 {now:%Y-%m-%d %H:%M}, 골 진행 원장 {sha}" + (f", 카드 {' '.join(tags)}" if tags else "")
    steps = next_steps(cur)
    for k in range(len(steps), -1, -1):
        nxt = steps[:k] + ([f"그 밖의 골 {len(steps) - k}개"] if k < len(steps) else []) if steps else [NO_NEXT]
        lines = [*st[:2], *[t for t, _ in fresh], *st[2:cut], "다음", *nxt, *st[cut:], tail]
        out = "\n".join(lines) + "\n"
        if len(out.encode()) <= MAX_BYTES:
            break
    return out
