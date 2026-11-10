"""magazine_doc_md — 오빠 확인 문서(planner 정리 md) 읽기: 칸·팀 나누기 + md → HTML(원문 그대로, 표·목록 행 수 보존).

칸 = `## ` 제목(팀 구역 앞) · 팀 = 팀 구역(`## 5. 팀별…`) 뒤의 `### ` 제목. 팀 안의 `## ` 소제목(「## 1. 지금 붙잡고 있는 것」)은 칸이 아니라 팀 본문이다.
"""
import html
import re
from dataclasses import dataclass


class DocError(RuntimeError):
    pass


@dataclass(frozen=True)
class Cell:
    key: str
    title: str
    body: str


@dataclass(frozen=True)
class Doc:
    title: str
    intro: str
    cells: list[Cell]
    teams: list[Cell]


def _clean(lines: list[str]) -> str:
    return "\n".join(ln for ln in lines if ln.strip() != "---").strip("\n")


def _intro(lines: list[str]) -> tuple[str, str, int]:
    """(제목, 머리말, 첫 `## ` 줄 번호) — 머리말은 `> ` 인용 표식을 뗀 글."""
    title = next((ln[2:].strip() for ln in lines if ln.startswith("# ")), "")
    first = next((i for i, ln in enumerate(lines) if ln.startswith("## ")), -1)
    if not title or first < 0:
        raise DocError("제목(`# `) 또는 첫 칸(`## `) 이 없어요")
    head = [ln.lstrip("> ").rstrip() for ln in lines[:first] if not ln.startswith("# ")]
    return title, _clean(head), first


def parse_doc(md: str) -> Doc:
    lines = md.splitlines()
    title, intro, first = _intro(lines)
    cells: list[tuple[str, list[str]]] = []
    teams: list[tuple[str, list[str]]] = []
    zone, cur = False, None
    for ln in lines[first:]:
        if not zone and ln.startswith("## "):
            name = re.sub(r"^\d+\.\s*", "", ln[3:]).strip()
            zone, cur = "팀별" in name, None if "팀별" in name else (name, [])
            if cur:
                cells.append(cur)
        elif zone and ln.startswith("### "):
            cur = (ln[4:].strip(), [])
            teams.append(cur)
        elif cur is not None:
            cur[1].append(ln)
    if zone and not teams:  # 팀 구역이 아예 없는 문서(오빠 원장 — 팀 작업이 칸 하나)는 teams = [] · 구역만 있고 팀이 없으면 깨진 문서
        raise DocError("팀 구역(`## 5. 팀별…`)에 팀(`### `) 이 없어요")
    return Doc(title, intro, _cells("c", cells), _cells("t", teams))


def _cells(prefix: str, rows: list[tuple[str, list[str]]]) -> list[Cell]:
    return [Cell(f"{prefix}{i}", name, _clean(body)) for i, (name, body) in enumerate(rows, 1)]


_SEP = re.compile(r"^\|[\s:|-]+\|$")
_NUM = re.compile(r"^\d+\. ")
_OPEN = {"ul": "<ul>", "ol": "<ol>", "table": "<table>"}
_CLOSE = {"ul": "</ul>", "ol": "</ol>", "table": "</table>"}


def _inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", out)


def _kind(ln: str) -> str:
    if not ln.strip() or ln.strip() == "---":
        return "blank"
    if ln.startswith("|"):
        return "sep" if _SEP.match(ln.strip()) else "row"
    if ln.startswith("- "):
        return "ul"
    return "ol" if _NUM.match(ln) else "text"


def _row(ln: str, head: bool) -> str:
    tag = "th" if head else "td"
    cols = ln.strip().strip("|").split("|")
    return "<tr>" + "".join(f"<{tag}>{_inline(c.strip())}</{tag}>" for c in cols) + "</tr>"


def _block(ln: str, kind: str, head: bool) -> str:
    if kind == "row":
        return _row(ln, head)
    if kind == "ul":
        return f"<li>{_inline(ln[2:].strip())}</li>"
    if kind == "ol":
        return f"<li>{_inline(_NUM.sub('', ln).strip())}</li>"
    if ln.startswith("###") or ln.startswith("##"):
        return f"<h4>{_inline(ln.lstrip('#').strip())}</h4>"
    return f"<p>{_inline(ln.lstrip('> ').strip())}</p>"


def to_html(body: str) -> str:
    """원문 줄 그대로 HTML 로 — 표 데이터 줄 = `<tr>`, 목록 줄 = `<li>`, 나머지 줄 = `<p>`/`<h4>`. 문자는 전부 이스케이프."""
    out: list[str] = []
    mode = ""
    lines = body.splitlines()
    for i, ln in enumerate(lines):
        kind = _kind(ln)
        want = {"ul": "ul", "ol": "ol", "row": "table", "sep": "table"}.get(kind, "")
        if want != mode:
            out += ([_CLOSE[mode]] if mode else []) + ([_OPEN[want]] if want else [])
            mode = want
        if kind in ("blank", "sep"):
            continue
        out.append(_block(ln, kind, kind == "row" and i + 1 < len(lines) and _kind(lines[i + 1]) == "sep"))
    return "\n".join(out + ([_CLOSE[mode]] if mode else []))
