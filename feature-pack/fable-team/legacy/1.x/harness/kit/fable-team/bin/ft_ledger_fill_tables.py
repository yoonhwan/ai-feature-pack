"""ft_ledger_fill_tables — 원장(PLAN-oppa-ledger.md) 표 세 개를 원천 값으로 다시 쓰고(r851 A1) 닫힌 줄을 5절로 내린다(C1).

손대는 자리 = «## 메인 골 … 지금 상태» 표의 «지금 상태» 칸 · «## 2. 오빠 할 일» 본문 · «## 3. 팀 작업» 절 안 «표 블록» 하나(r3 ④ · 절 머리·표 앞뒤 글줄 그대로)
· 1절의 상태 낱말이 «닫힘/완료» 와 정확히 같은 행(r3 ⑤ · → 5절 표 끝).
그 밖의 바이트(결론 문단 · 머리 · 다른 절 · 사람이 쓴 칸)는 그대로. 원천 하나가 실패면 그 원천을 쓰는 표만 갱신 0 + 오류 1줄.
칸 글자는 매거진 지침 검사(magazine_guide_check.RULES)에 걸리는 조각(번호·sha·경로)을 지운 뒤 싣는다 — 발행 거절 0.
"""
from __future__ import annotations

import hashlib
import re
from datetime import datetime

from ft_ledger_fill_src import FillError

KO = {"cfo": "결제", "feature": "신기능", "knowledge": "지식", "ops": "운영툴", "graphics": "디자인", "room": "방", "v65": "실시간 통역",
      "lecture": "강의", "chatbot": "챗봇", "issues": "이슈", "harness": "하네스", "planner": "planner"}
GUIDE = (r"판정 ?\d+", r"#\d+", r"(?<![0-9A-Za-z])(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}(?![0-9A-Za-z])", r"\b\d{5}\b",
         r"\b[A-Z]{1,3}\d+[a-z]?\b", r"[\w.-]+/[\w./-]+\.(?:md|py|sh|json|html)")  # magazine_guide_check.RULES 앞 6개와 같은 글자(시험이 대조)
_GUIDE = re.compile("|".join(GUIDE))
STAMP = re.compile(r"기계 채움 \d{2}-\d{2} \d{2}:\d{2}")
CLOSED = frozenset(("닫힘", "완료"))  # 상태 낱말(칸의 첫 « — » 앞) «정확 일치» 집합 — 접두사·포함 비교 0(r3 ⑤ «완료 아님 — 승인 대기» 는 열림)
SHOW = 3  # 칸마다 카드 제목 최대 개수(나머지는 «외 N»)


def clean(s: str, n: int = 120) -> str:
    s = re.sub(r"\s+", " ", _GUIDE.sub("", s.replace("|", "/"))).strip(" ·—-")
    return s if len(s) <= n else s[: n - 1] + "…"


def quote(s: str, n: int = 120) -> str:
    """원천 문장(질문·자율 큐) = «» 인용 — 상대 날짜 가드(magazine_date_guard)는 인용 안을 보지 않는다 · 번호·sha 는 clean 이 지운다."""
    return f"«{clean(s.replace('«', '').replace('»', ''), n)}»"


def _span(lines: list[str], pred) -> tuple[int, int] | None:
    """머리 줄(pred 참)부터 다음 «## » 머리 전까지 — (시작, 끝) · 없으면 None."""
    for i, ln in enumerate(lines):
        if ln.startswith("## ") and pred(ln):
            j = next((k for k in range(i + 1, len(lines)) if lines[k].startswith("## ")), len(lines))
            return i, j
    return None


def _cells(ln: str) -> list[str]:
    return [c.strip() for c in ln.strip().strip("|").split("|")]


def _titles(cards: list[tuple[str, str]]) -> str:
    names = [quote(t if clean(t) else n, 40) for n, t in cards[:SHOW]]
    return " · ".join(names) + (f" 외 {len(cards) - SHOW}" if len(cards) > SHOW else "")


def _work(c: dict, done_notes: int = -1) -> str:
    parts = [f"진행 {len(c['진행'])}장" + (f" — {_titles(c['진행'])}" if c["진행"] else "")]
    if c["착지"]:
        parts.append(f"최근 완성 {len(c['착지'])}장 — {_titles(c['착지'])}")
    if done_notes > 0:
        parts.append(f"완료·착지 쪽지 {done_notes}통")
    return " · ".join(parts)


def goal_state(lines: list[str], goal_teams: list[str], cards: dict[str, dict]) -> list[str]:
    """«메인 골 … 지금 상태» 표 «지금 상태» 칸 = 그 골 담당 팀(정본 팀 칸 · 행 순번 결속)의 카드 실측. 행 수 ≠ 정본 = FillError."""
    span = _span(lines, lambda ln: ln.startswith("## 메인 골") and "지금 상태" in ln)
    if span is None:
        raise FillError("원장에 «## 메인 골 … 지금 상태» 절 없음")
    rows = [i for i in range(*span) if lines[i].startswith("|")]
    if len(rows) < 2 or "지금 상태" not in _cells(lines[rows[0]]):
        raise FillError("«메인 골» 표 머리에 «지금 상태» 칸 없음")
    col, data = _cells(lines[rows[0]]).index("지금 상태"), rows[2:]
    if len(data) != len(goal_teams):
        raise FillError(f"«메인 골» 표 {len(data)}행 ≠ 골 정본 {len(goal_teams)}행")
    out = list(lines)
    for i, team_cell in zip(data, goal_teams):
        names = [t for t in cards if re.search(rf"(?<![a-z0-9]){re.escape(t)}(?![a-z0-9])", team_cell)]
        cells = _cells(lines[i])
        if len(cells) <= col:
            raise FillError(f"«메인 골» 표 행이 칸보다 짧다: {lines[i][:40]}")
        now_n, done_n = sum(len(cards[t]["진행"]) for t in names), sum(len(cards[t]["착지"]) for t in names)
        detail = " / ".join(f"{KO.get(t, t)} {_titles(cards[t]['진행'] + cards[t]['착지'])}" for t in names if cards[t]["진행"] or cards[t]["착지"])
        # 앞머리 = 숫자 요약 — 골 표 블록(ft_goal_table · 1600B)이 이 칸을 24→12자로 자른다
        cells[col] = (f"진행 {now_n}장 · 최근 완성 {done_n}장" + (f" — {detail}" if detail else "") if names else "담당 팀 카드 없음") + " (기계 채움)"
        out[i] = "| " + " | ".join(cells) + " |"
    return out


def oppa_todo(qs: list[dict], hils: list[tuple[str, int]], queue: list[dict], stamp: str) -> list[str]:
    """«## 2. 오빠 할 일» 절 전체(머리 + 번호 줄) — 번호 줄 수 = 질문 + 실행 줄 + 자율 큐(누락 0 · r851 ⓑ)."""
    items = [f"질문 — {quote(str(q.get('what', '')), 140)} (묻는 팀 {KO.get(m[1], m[1]) if (m := re.match(r'byz-([a-z0-9]+)-', str(q.get('seat', '')))) else '모름'})" for q in qs]
    items += [f"실행 줄 — 기다린 지 {mins}분 · ! bash /tmp/{h}" for h, mins in hils]
    items += [f"자율 큐 — {quote(r.get('질문', ''), 140)} · 추천: {quote(r.get('추천안', ''), 80)}" for r in queue]
    head = f"## 2. 오빠 할 일 (기계 채움 {stamp} · {len(items)}건 = 질문 {len(qs)} · 실행 줄 {len(hils)} · 자율 큐 {len(queue)})"
    return [head, *(f"{n}. {t}" for n, t in enumerate(items, 1))]


def team_work(cards: dict[str, dict], notes: dict[str, int]) -> list[str]:
    """«## 3. 팀 작업» 표 블록(머리·구분·행) — 절 머리와 표 밖 글줄은 _replace_table 이 그대로 둔다(r3 ④)."""
    rows = [f"| {KO.get(t, t)} | {_work(c, notes.get(t, 0))} | 대기 카드 {c['대기']}장 |" for t, c in cards.items()]
    return ["| 팀 | 지금 하는 것 | 다음 |", "|---|---|---|", *rows]


def _replace(lines: list[str], prefix: str, new: list[str]) -> list[str]:
    span = _span(lines, lambda ln: ln.startswith(prefix))
    if span is None:
        raise FillError(f"원장에 «{prefix}» 절 없음")
    tail = [ln for ln in lines[span[0] + 1:span[1]] if not ln.strip()][-1:]  # 절 끝 빈 줄 1개는 지킨다
    return lines[:span[0]] + new + tail + lines[span[1]:]


def _replace_table(lines: list[str], prefix: str, table: list[str]) -> list[str]:
    """r851 r3 ④ — 그 절 안 «표 블록»(연속한 `|` 줄) 하나만 바꾼다 · 절 머리·표 앞뒤 글줄(planner 메모)은 바이트 그대로.
    표 0개·2개 이상 = FillError(그 표 갱신 0 · 어느 표인지 추측 0)."""
    span = _span(lines, lambda ln: ln.startswith(prefix))
    if span is None:
        raise FillError(f"원장에 «{prefix}» 절 없음")
    blocks, i = [], span[0] + 1
    while i < span[1]:
        if lines[i].startswith("|"):
            j = next((k for k in range(i, span[1]) if not lines[k].startswith("|")), span[1])
            blocks.append((i, j))
            i = j
        else:
            i += 1
    if len(blocks) != 1:
        raise FillError(f"«{prefix}» 절의 표 {len(blocks)}개 — 하나여야 함(갱신 0)")
    a, b = blocks[0]
    return lines[:a] + table + lines[b:]


def key(row: str) -> str:
    return hashlib.sha1(row.encode("utf-8")).hexdigest()[:16]


def lower_closed(lines: list[str], seen: dict[str, str], published_at: str, now: datetime) -> tuple[list[str], dict[str, str], int]:
    """1절 «닫힘/완료» 행 — 처음 본 시각 < 마지막 «발행 성공» 시각이면 5절 표 끝으로(같은 글자 그대로 · 내린 날 = 지금).
    발행 성공 기록이 없거나(빈 값) 그 뒤에 처음 본 행은 남긴다. 돌려주는 seen = 아직 1절에 있는 닫힌 행만."""
    one = _span(lines, lambda ln: ln.startswith("## 1. 오빠가 시킨 일"))
    five = _span(lines, lambda ln: ln.startswith("## 5. 완료 보관"))
    if one is None or five is None:
        raise FillError("원장에 1절(오빠가 시킨 일) 또는 5절(완료 보관) 없음")
    stamp, day, head, move, keep = f"{now:%Y-%m-%d %H:%M}", "", None, [], {}
    for i in range(*one):
        ln = lines[i]
        if ln.startswith("### "):
            day, head = (m[0] if (m := re.search(r"\d{2}-\d{2}", ln)) else ""), None
        elif ln.startswith("|") and "지금 상태" in ln:
            head = _cells(ln)
        elif ln.startswith("|") and head and not set(ln) <= set("|-: "):
            c = dict(zip(head, _cells(ln)))
            if c.get("지금 상태", "").split("—", 1)[0].strip() not in CLOSED:
                continue
            k = key(ln)
            if seen.get(k) and published_at and seen[k] < published_at:
                move.append((i, f"| {day}-{c.get('순번') or '_'} | {c.get('시키신 일', '')} | {c.get('종류', '')} | {c['지금 상태']} | {now:%m-%d} |"))
            else:
                keep[k] = seen.get(k) or stamp
    if not move:
        return lines, keep, 0
    last = max((i for i in range(*five) if lines[i].startswith("|")), default=None)
    if last is None:
        raise FillError("5절(완료 보관)에 표 없음 — 내림 0")
    gone = {i for i, _ in move}
    out = [ln for i, ln in enumerate(lines[:last + 1]) if i not in gone] + [r for _, r in move] + lines[last + 1:]
    return out, keep, len(move)


def same(a: str, b: str) -> bool:
    """기계 채움 시각만 다른 판 = 같은 판(변화 0 = 커밋 0 · r851 ⓑ)."""
    return STAMP.sub("기계 채움 _", a) == STAMP.sub("기계 채움 _", b)
