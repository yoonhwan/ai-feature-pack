"""magazine_brief — 원장(planner 정리 md)을 아침 매거진 한 쪽(지침 §1 칸)으로 옮기는 재료 만들기 (R259 · 판정 1988).

외부 호출 0 · 요약·고침 0 — 원장 줄을 칸에 옮기고, 행 끝 괄호 근거만 «근거 표» 로 뺀다. 원장 형식이 어긋나면 `issues` 에 적어 지침 검사(magazine_guide_check)가 알린다(조용히 건너뛰기 0).
"""
import re
from dataclasses import dataclass, field

from magazine_brief_diff import changes
from magazine_brief_rows import split_evidence, table_rows
from magazine_doc_md import Cell, Doc

RISK = ("진행 중 위험", "위험")  # 이 이름으로 시작하는 §2 묶음만 «지켜보는 위험» 상자 — 나머지 묶음 이름은 planner 자유(거르지 않음)
OPEN_STATES = ("오빠 확인", "막힘")
MAX_OPEN = 8
_CONCLUSION = re.compile(r"(?m)^\*\*결론\*\*\s*[:：]\s*(.+?)\s*$")
_WATCH = re.compile(r"(?m)^\*\*눈여겨볼 줄\*\*\s*[:：]\s*(.+?)\s*$")
_BULLET = re.compile(r"^(\s*)- (.*)$")
_LABEL = (re.compile(r"\*\*(.+?)\*\*\s*[:：]?\s*(.*)"), re.compile(r"([^:：]+?)\s*[:：]\s*(.*)"))


@dataclass
class Brief:
    date: str
    src: str
    conclusion: str = ""
    todo: list[tuple[str, list[str]]] = field(default_factory=list)  # §2 묶음 (제목, 항목들)
    risk: str = ""
    changes: list[tuple[str, str]] = field(default_factory=list)
    changes_note: str = ""
    open_rows: list[tuple[str, str]] = field(default_factory=list)
    teams: list[tuple[str, str, str]] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    evidence: list[tuple[str, str]] = field(default_factory=list)
    issues: list[tuple[str, str, str]] = field(default_factory=list)  # (항목, 칸, 조각) — 원장 형식이 지침과 어긋난 곳

    def take(self, text: str) -> str:
        """행 끝 괄호 근거를 떼어 근거 표에 쌓고 남은 글을 돌려준다."""
        clean, why = split_evidence(text)
        if why:
            self.evidence.append((why, clean[:40] + ("…" if len(clean) > 40 else "")))
        return clean

    def cells(self) -> list[Cell]:
        """칸마다 평문 줄 — 날짜 가드·지침 검사가 읽는 «판에 실릴 글»(근거 표 제외)."""
        parts = [
            ("결론", [self.conclusion]),
            ("오빠 할 일", [ln for title, items in self.todo for ln in (title, *items)] + [self.risk]),
            ("지난 판 뒤로 바뀐 것", [f"{kind} {text}" for kind, text in self.changes] + [self.changes_note]),
            ("눈여겨볼 열린 일", [f"{task} — {state}" for task, state in self.open_rows]),
            ("팀은 지금", [" · ".join(row) for row in self.teams]),
            ("드러난 문제", self.problems),
        ]
        return [Cell(f"b{i}", title, "\n".join(ln for ln in lines if ln)) for i, (title, lines) in enumerate(parts, 1)]

    def as_doc(self) -> Doc:
        return Doc("", "", self.cells(), [])


def _label(text: str) -> tuple[str, str]:
    for rx in _LABEL:
        found = rx.match(text)
        if found:
            return found.group(1).strip().rstrip(":：").strip(), found.group(2).strip()
    return text.strip(), ""


def _fill_todo(cell: Cell, b: Brief) -> None:
    """원장 §2 — 최상위 글머리 = 묶음 제목(굵게 `**` 는 뗌) · 하위 글머리 = 항목 · 제목 뒤 글은 첫 항목. 이름으로 거르지 않고 «위험» 으로 시작하는 묶음만 위험 상자로."""
    groups: list[tuple[str, list[str]]] = []
    for ln in cell.body.splitlines():
        found = _BULLET.match(ln)
        if not found:
            continue
        if not found.group(1):
            title, rest = _label(found.group(2))
            groups.append((b.take(title), [b.take(rest)] if rest else []))
        elif groups:
            groups[-1][1].append(b.take(found.group(2)))
        else:
            b.issues.append(("할 일 형식", cell.title, found.group(2)))
    b.risk = " ".join(x for t, items in groups if t.startswith(RISK) for x in items)
    b.todo = [g for g in groups if not g[0].startswith(RISK)]


def _rows(cell: Cell, need: tuple[str, ...], b: Brief) -> list[dict[str, str]]:
    rows = table_rows(cell.body)
    if not rows or any(k not in r for r in rows for k in need):
        b.issues.append(("표 형식", cell.title, "머리 " + "·".join(need) + " 칸이 없어요"))
    return [r for r in rows if all(k in r for k in need)]


def _fill_open(cells: list[Cell], watch: str, b: Brief) -> None:
    words = [w.strip() for w in re.split(r"[,，]", watch) if w.strip()]
    for cell in cells:
        for row in _rows(cell, ("시키신 일", "지금 상태"), b):
            task, state = row["시키신 일"], row["지금 상태"]
            if state.startswith(OPEN_STATES) or any(task.lstrip("«「\"' ").startswith(w) for w in words):
                b.open_rows.append((b.take(task), b.take(state)))
    b.open_rows = b.open_rows[:MAX_OPEN]


def build_brief(doc: Doc, date: str, src: str, prev: Doc | None, prev_note: str) -> Brief:
    b = Brief(date, src)
    found = _CONCLUSION.search(doc.intro)
    b.conclusion = b.take(found.group(1)) if found else ""
    watch = _WATCH.search(doc.intro)
    for cell in doc.cells:
        if cell.title.startswith("오빠 할 일"):
            _fill_todo(cell, b)
        elif cell.title.startswith("팀 작업"):
            b.teams = [(b.take(r["팀"]), b.take(r["지금 하는 것"]), b.take(r["다음"])) for r in _rows(cell, ("팀", "지금 하는 것", "다음"), b)]
        elif "드러난 문제" in cell.title:
            b.problems = [b.take(m.group(2)) for ln in cell.body.splitlines() if (m := _BULLET.match(ln))]
    _fill_open([c for c in doc.cells if c.title.startswith("오빠가 시킨 일")], watch.group(1) if watch else "", b)
    if prev is None:
        b.changes_note = prev_note
    else:
        b.changes = [(kind, b.take(f"{task} — {state}" if state else task)) for kind, task, state in changes(prev, doc)]
        b.changes_note = "" if b.changes else "지난 판 뒤로 바뀐 것이 없어요"
    return b
