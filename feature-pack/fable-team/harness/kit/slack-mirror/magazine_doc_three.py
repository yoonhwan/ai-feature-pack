"""magazine_doc_three — 원장 맨 위를 «요청한 일 / 완료한 일 / 해야 할 일» 3칸으로 묶는 변환 층 (R190 · 판정 1723).

원장 파일은 그대로 두고, 표 행·글머리를 원문 줄 그대로 옮긴다(요약·고침 0). 3칸 대상 절(오빠가 시킨 일 + 오빠 할 일)이 없는 옛 문서는 지금 동작 그대로.
"""
import logging
import re
from dataclasses import dataclass, field
from datetime import date as Date
from datetime import timedelta

from magazine_doc_md import Cell, Doc

LOG = logging.getLogger("magazine_doc")
_SEP = re.compile(r"^\|[\s:|-]+\|$")
_DONE = ("완료", "✅")
_KNOWN = ("미착수", "진행", "오빠 확인") + _DONE
_DAY = re.compile(r"(?<!\d)(?:(\d{4})-)?(\d{1,2})-(\d{1,2})(?!\d)")


@dataclass
class _Table:
    lead: list[str]
    head: str
    sep: str
    rows: list[str]


@dataclass
class _Out:
    req: list[str] = field(default_factory=list)
    done: list[str] = field(default_factory=list)
    todo: list[str] = field(default_factory=list)
    unknown: list[str] = field(default_factory=list)
    nohead: list[str] = field(default_factory=list)
    undated: int = 0


def _role(title: str) -> str:
    t = title.strip()
    if t.startswith("오빠 할 일"):
        return "todo"
    if t.startswith("2-1.") or "발주한 것" in t:
        return "order"
    if "시킨 일" in t:
        return "ask"
    return "archive" if "완료 보관" in t else ""


def _cols(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _tables(body: str) -> tuple[list[_Table], list[str]]:
    """(표들, 꼬리 줄) — 표 앞에 붙은 줄(소제목·머리글)은 그 표의 lead."""
    lines, i = body.splitlines(), 0
    out: list[_Table] = []
    lead: list[str] = []
    while i < len(lines):
        if lines[i].startswith("|") and i + 1 < len(lines) and _SEP.match(lines[i + 1].strip()):
            j = i + 2
            while j < len(lines) and lines[j].startswith("|"):
                j += 1
            out.append(_Table(lead, lines[i], lines[i + 1], lines[i + 2:j]))
            lead, i = [], j
        else:
            lead.append(lines[i])
            i += 1
    return out, lead


def _is_done(state: str) -> bool:
    return state.startswith(_DONE)


def _in_window(text: str, date: str) -> bool | None:
    """«내린 날» 이 발행일 또는 그 전날이면 True · 날짜가 읽히는데 그 밖이면 False · 날짜가 안 읽히면 None."""
    base = Date.fromisoformat(date)
    days: list[Date] = []
    for y, m, d in _DAY.findall(text):
        try:
            day = Date(int(y) if y else base.year, int(m), int(d))
            if not y and day > base:  # 연도 없는 날짜가 기준일보다 미래면 전년(연말 경계: 발행 01-01 의 «12-31»)
                day = Date(base.year - 1, int(m), int(d))
            days.append(day)
        except ValueError:
            continue
    return any(base - timedelta(days=1) <= x <= base for x in days) if days else None


def _cell_at(row: str, idx: int) -> str:
    cols = _cols(row)
    return cols[idx] if idx < len(cols) else ""


def _put(dest: list[str], heads: list[str], t: _Table, rows: list[str]) -> None:
    if dest and dest[-1].strip():
        dest.append("")
    dest += heads + [t.head, t.sep] + rows


def _heads(cell: Cell, t: _Table, role: str) -> list[str]:
    marks = [ln for ln in t.lead if ln.startswith("###")]
    return marks or ([] if role == "ask" else [f"### {cell.title}"])


def _notes(tables: list[_Table], tail: list[str]) -> list[str]:
    lead = [ln for t in tables for ln in t.lead if ln.strip() and not ln.startswith("###")]
    return lead + [ln for ln in tail if ln.strip()]


def _by_status(cell: Cell, role: str, out: _Out) -> None:
    tables, tail = _tables(cell.body)
    out.req += _notes(tables, tail)
    for t in tables:
        idx = _cols(t.head).index("지금 상태") if "지금 상태" in _cols(t.head) else None
        if idx is None:
            out.nohead.append(cell.title)
            _put(out.req, _heads(cell, t, role), t, t.rows)
            continue
        states = [(r, _cell_at(r, idx)) for r in t.rows]
        done = [r for r, s in states if _is_done(s)]
        opened = [(r, s) for r, s in states if not _is_done(s)]
        out.unknown += [s for _, s in opened if not s.startswith(_KNOWN)]
        for dest, rows in ((out.req, [r for r, _ in opened]), (out.done, done)):
            if rows:
                _put(dest, _heads(cell, t, role), t, rows)


def _by_date(cell: Cell, date: str, out: _Out) -> None:
    tables, tail = _tables(cell.body)
    out.done += _notes(tables, tail)
    for t in tables:
        idx = _cols(t.head).index("내린 날") if "내린 날" in _cols(t.head) else None
        if idx is None:
            out.nohead.append(cell.title)
        keep = []
        for r in t.rows:
            hit = _in_window(_cell_at(r, idx), date) if idx is not None else True
            out.undated += hit is None
            if hit is not False:
                keep.append(r)
        if keep:
            _put(out.done, _heads(cell, t, "archive"), t, keep)


def _warn(out: _Out) -> None:
    if out.unknown:
        kinds = ", ".join(sorted({s[:12] or "(빈 상태)" for s in out.unknown})[:5])
        LOG.warning("3칸 묶음: 상태 낱말을 몰라 «요청한 일» 로 보낸 행 %d건 — %s", len(out.unknown), kinds)
    if out.nohead:
        LOG.warning("3칸 묶음: 상태 열(지금 상태·내린 날)을 못 찾은 표 %d개 — 통째로 옮겼어요: %s", len(out.nohead), ", ".join(out.nohead))
    if out.undated:
        LOG.warning("3칸 묶음: «내린 날» 에서 날짜를 못 읽은 완료 보관 행 %d건 — 지우지 않고 «완료한 일» 에 실었어요", out.undated)


def _body(lines: list[str]) -> str:
    return "\n".join(lines).strip("\n")


def group_three(doc: Doc, date: str) -> tuple[list[Cell], list[Cell]]:
    """(맨 위 3칸, 그 아래 칸들). 대상 절이 없으면 ([], 지금 칸 그대로). 본문이 빈 칸은 만들지 않는다."""
    roles = [(c, _role(c.title)) for c in doc.cells]
    if not {"ask", "todo"} <= {r for _, r in roles}:
        return [], doc.cells
    out = _Out()
    for c, role in roles:
        if role in ("ask", "order"):
            _by_status(c, role, out)
        elif role == "archive":
            _by_date(c, date, out)
        elif role == "todo":
            out.todo.append(c.body)
    _warn(out)
    cells = [Cell("c1", "요청한 일", _body(out.req)), Cell("c2", "완료한 일", _body(out.done)), Cell("c3", "해야 할 일", _body(out.todo))]
    return [c for c in cells if c.body.strip()], [c for c, role in roles if not role]


def with_three(doc: Doc, date: str) -> Doc:
    """3칸을 맨 위에 둔 새 Doc(칸 키 c1.. 다시 매김). 3칸이 없으면 doc 그대로."""
    got, rest = group_three(doc, date)
    if not got:
        return doc
    return Doc(doc.title, doc.intro, [Cell(f"c{i}", c.title, c.body) for i, c in enumerate(got + rest, 1)], doc.teams)
