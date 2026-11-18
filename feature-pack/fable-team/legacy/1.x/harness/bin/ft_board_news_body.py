"""ft_board_news_body — 오빠 thread 상태 답글의 본문 = Slack 4칸 (r2058 → r2095 → r2103).

머리 줄(열린·닫힌 골) → «지금»(바뀐 것 · 열린 골마다 1줄) → «다음»(열린 골마다 다음 한 수 · r2096) → «막힌 것, 오빠 할 일» → 끝 줄 «근거:».
열쇠 = standing() 줄 + «다음» 칸 줄(바뀐 것 줄 · 근거 줄 밖) — 팀 카드 수 · 좌석 · 진행 카드는 열쇠에 없다. 줄은 자르지 않는다.
r2103: 골 줄 = 막대 10칸 + n/m · 골 줄 뒤 «진행 중인 일» 묶음(열쇠 밖) · 길면 묶음 → 막대 순으로 빼고 기준판 본문으로 돌아간다.
"""
import os
import re
import sys
from datetime import datetime

from ft_board_news_name import card_tag, shorten, work_name
from ft_oppa_slack_check import OPPA_SLACK_UID

MAX_CHANGES, MAX_BYTES, MAX_DOING, BAR = 5, 3500, 8, 10
NO_NEXT = "정해진 다음 한 수 없음"
NO_TABLE = "골 진행 표 없음 — planner 원장 «## 골 진행»"
STALE = ("닫는 증거 칸", "main 밖", "좌석", "세션", "나노", "keeper")  # 원장 상태 글의 내부어(S5 · 알리기만)
STALE_DATE = re.compile(r"\(\d{2}-\d{2} 판\)")
MENTION = re.compile(r"<([@!][^<>]*)>")  # r2102 원장·카드 글의 Slack mention 꼴 → 꺾쇠를 뺀다(태그 = 도구가 붙인 1개뿐)
SENT_END = re.compile(r"(\.(?=\s|$)|\s·\s)")  # r2126 V1 문장 끝 = 마침표 · « · » 나눔 · 칸 끝


def quiet(s: str) -> str:
    return MENTION.sub(r"\1", s)


def hapsyo(s: str) -> str | None:
    """«…다» 끝 → 바꿈표 첫 맞음 1개(ⓐ 이다 ⓑ 는다 ⓒ 받침 ㄴ ⓓ 그 밖 받침 ⓔ 받침 없음) · 앞 글자가 한글 아님 = None."""
    c, head = s[-2:-1], s[:-2]
    if c in ("이", "는"):
        return head + ("입니다" if c == "이" else "습니다")
    if not "가" <= c <= "힣":
        return None
    j = (ord(c) - 0xAC00) % 28  # 받침 번호 · 4 = ㄴ → 17 = ㅂ
    return head + (chr(ord(c) + 13) + "니다" if j == 4 else c + ("습니다" if j else "입니다"))


def polite(text: str) -> tuple[str, list[str]]:
    """V1(r2126) 원장 칸 반말 끝 → 존댓말 · 이미 «니다» · 인용 안 · «다» 아닌 끝 = 그대로 → (글, 바꿀 수 없는 문장 앞 20자들)."""
    parts, bad = SENT_END.split(text), []
    for i in range(0, len(parts), 2):
        s, seen = parts[i].rstrip(), "".join(parts[:i + 1])  # 인용 열림 = 칸 처음부터 센다(여러 문장 인용 · DA #320425 R1)
        if not s.endswith("다") or s.endswith("니다") or seen.count("«") > seen.count("»") or seen.count('"') % 2:
            continue
        new = hapsyo(s)
        if new is None:
            bad.append(s.strip()[:20])
        else:
            parts[i] = new + parts[i][len(s):]
    return "".join(parts), bad


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


def goal_counts(cur: dict, name: str, today: str = "") -> list[int]:
    """[완성, 오늘 완성, 진행, 대기] — 모든 팀 카드 중 골좌표 글에 골 짧은 이름이 글자 그대로 든 카드(r2120 E3)."""
    out = [0, 0, 0, 0]
    for team, states in (cur.get("cards") or {}).items():
        goals, done = (cur.get("card_goals") or {}).get(team) or {}, (cur.get("done_on") or {}).get(team) or {}
        for cid in [c for c in states if name and name in goals.get(c, "")]:
            st = states[cid]
            out = [out[0] + (st == "완성"), out[1] + (st == "완성" and done.get(cid) == today), out[2] + (st == "진행"), out[3] + (st == "대기")]
    return out


def card_tail(cur: dict, name: str, today: str) -> str:
    """«카드 완성 N장(오늘 +k), 진행 n장, 대기 m장» — 0 인 칸은 빼고 셋 다 0 이면 빈 글."""
    n, k, p, w = goal_counts(cur, name, today)
    parts = [f"카드 완성 {n}장" + (f"(오늘 +{k})" if k else "")] if n else []
    return ", ".join(parts + ([f"진행 {p}장"] if p else []) + ([f"대기 {w}장"] if w else []))


def with_tail(line: str, tail: str) -> str:
    return f"{line}{'' if line.endswith('.') else '.'} {tail}" if tail else line


def standing(cur: dict, bar: bool = True, tails: dict | None = None) -> list[str]:
    """열쇠가 되는 본문 줄 = 머리 줄 · 열린 골 줄 · 막힌 것 칸 줄(열쇠 = 막대 꼴 · bar=False = 기준판 꼴).
    tails = {골 번호: 카드 진행 글} — 본문에만 붙는다(열쇠 밖 · r2120)."""
    rows = cur["goals"]
    shut = [r[1] for r in rows or [] if closed(r)]
    top = f"골 진행 알림: 열린 골 {len(rows) - len(shut)}개, 닫힌 골 {len(shut)}개" + (f"({', '.join(shut)})" if shut else "") if rows else f"골 진행 알림: {NO_TABLE}"
    goals = [with_tail(goal_line(r, bar), (tails or {}).get(r[0], "")) for r in rows or [] if not closed(r)] or (["열린 골 없음"] if rows else [])
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


def voiced(r: list[str], mark: str) -> list[str]:
    """열린 골 행의 상태 · 다음 칸 = V1 바꿈 + 상태 칸 앞 F1 원장 시각 표지(r2126 · 본문만 · 열쇠 밖)."""
    r = [quiet(c) for c in r]
    if closed(r):
        return r
    for i in (4, 5)[:len(r) - 4]:
        r[i], bad = polite(r[i])
        for s in bad:
            print(f"WARN 말투 바꿈 불가: {r[1]} — {s}", file=sys.stderr)
    for i in (4, 5)[:len(r) - 4]:  # F1 표지 = 지금 · 다음 칸 둘 다(DA #320425 R2) · 빈칸 · «—» = 줄 없음
        r[i] = f"{mark} {r[i]}" if mark and r[i] not in ("", "—", "-") else r[i]
    return r


def body(cur: dict, prev: dict | None, now: datetime, sha: str, tt: dict | None = None, meas: str = "", mark: str = "", beat: str = "") -> str:
    """본문 — 3500B 를 넘으면 ⓐ 진행 줄을 아래부터 → ⓑ 묶음을 통째로 → ⓒ 막대를 모두 빼고(= 기준판 본문)
    → ⓓ «다음» 칸 줄을 아래부터 빼고 «그 밖의 골 N개» 로 맺는다. 상한 안 첫 단계에서 멈춘다 · 그래도 넘으면 ⓔ 긴 골 상태 글부터 줄임(r2184 · 그 앞은 r2103 A4).
    r2126: meas = «지금» 칸 첫 줄(실측) · mark = 원장 칸 앞 표지 · beat = 무변화 상태 글 첫 줄(진행 묶음 0 = 짧은 글)."""
    nm = lambda team, cid: work_name(cid, (tt or {}).get(team, {}).get(cid))  # noqa: E731
    fresh = [(quiet(t), ids) for t, ids in news(prev, cur, nm)]
    tails = {r[0]: quiet(card_tail(cur, r[1], f"{now:%F}")) for r in cur["goals"] or [] if not closed(r)}  # r2120 E3
    rows = [voiced(r, mark) for r in cur["goals"]] if cur["goals"] else cur["goals"]
    cur = {**cur, "goals": rows, "carried": [quiet(t) for t in cur.get("carried", [])]}
    tags = list(dict.fromkeys(g for _, ids in fresh for c in ids if (g := card_tag(c))))  # 근거 줄 번호
    tail = f"근거: 발행 {now:%Y-%m-%d %H:%M}, 골 진행 원장 {sha}" + (f", 카드 {' '.join(tags)}" if tags else "")
    steps = next_steps(cur)

    def text(st: list[str], grp: list[str], nxt: list[str]) -> str:
        cut = st.index("막힌 것, 오빠 할 일")
        return "\n".join([*([beat] if beat else []), *st[:2], *([meas] if meas else []), *[t for t, _ in fresh], *st[2:cut], *grp, "다음", *nxt, *st[cut:], tail]) + "\n"
    rows, bare = doing(cur, nm)
    st = standing(cur, tails=tails)
    for grp in ([] if beat else [doing_lines(rows, bare, k) for k in range(min(MAX_DOING, len(rows)), -1, -1)]) + [[]]:  # ⓐ · ⓑ
        if len((out := text(st, grp, steps or [NO_NEXT])).encode()) <= MAX_BYTES:
            return out
    st = standing(cur, bar=False)  # ⓒ · ⓓ = 기준판(r2102) 본문 — 카드 진행 덧붙임도 빠짐(r2120 E4)
    for k in range(len(steps), -1, -1):
        nxt = steps[:k] + ([f"그 밖의 골 {len(steps) - k}개"] if k < len(steps) else []) if steps else [NO_NEXT]
        out = text(st, [], nxt)
        if len(out.encode()) <= MAX_BYTES:
            break
    if len(out.encode()) > MAX_BYTES:  # ⓔ r2184 · 못 맞추면 넘는 글 그대로(= N 의 발행 0 · 실측 줄 지움 0)
        out = shorten(st, [r[4] for r in cur["goals"] or [] if not closed(r)], mark, lambda s: text(s, [], nxt), MAX_BYTES) or out
    return out
