"""magazine_brief_html — Brief → 아침 매거진 HTML 한 쪽 (R259 · 판정 1988 · 승인 견본 틀 · 지침 §1 칸 순서).

칸 순서 = 날짜+결론 · 오빠 할 일 · 지난 판 뒤로 바뀐 것 · 눈여겨볼 열린 일 · 팀은 지금 · 드러난 문제 · 근거 표. 빈 칸은 칸째 생략한다. 외부 호출 0.
"""
import html
import re
from pathlib import Path

from magazine_brief import Brief

TEMPLATE = Path(__file__).with_name("magazine_swiss_template.html")
NO_CONCLUSION = "원장에 결론 줄이 없어요 — 위 지침 줄을 보고 원장을 고쳐 주세요"
_KIND = {"끝": "ok", "새": "wait", "바뀜": "wait"}


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    return re.sub(r"`([^`]+)`", r'<span class="cmd">\1</span>', out)


def _list(tag: str, items: list[str], cls: str = "") -> str:
    attr = f' class="{cls}"' if cls else ""
    return f"<{tag}{attr}>\n" + "\n".join(f"  <li>{x}</li>" for x in items) + f"\n</{tag}>"


def _table(head: list[str], rows: list[list[str]], mute: set[int] | None = None) -> str:
    out = ["<table>", "  <tr>" + "".join(f"<th>{h}</th>" for h in head) + "</tr>"]
    for i, row in enumerate(rows):
        cls = ' class="mute"' if mute and i in mute else ""
        out.append("  <tr>" + "".join(f"<td{cls}>{c}</td>" for c in row) + "</tr>")
    return "\n".join(out + ["</table>"])


def _todo(b: Brief) -> str:
    out = []
    for title, items in b.todo:
        out.append(f'<p class="grp">{inline(title)}</p>')
        out += [_list("ol", [inline(x) for x in items], "todo")] if items else []
    if b.risk:
        out.append(f'<div class="risk"><b>지켜보는 위험</b> — {inline(b.risk)}</div>')
    return "\n".join(out)


def _changes(b: Brief) -> str:
    items = [f'<span class="{_KIND[k]}">{k}</span> {inline(t)}' for k, t in b.changes]
    return "\n".join(([_list("ul", items)] if items else []) + ([f'<p class="more">{inline(b.changes_note)}</p>'] if b.changes_note else []))


def _done(b: Brief) -> str:
    """① 끝낸 일 축하 — 머리 1줄 + 일마다 카드(무엇 · 쉬운 풀이). 풀이 실패는 카드 안에 그대로 보인다."""
    out = [f'<p class="cheer">{inline(b.done_head())}</p>']
    for d in b.done:
        easy = d.easy()
        if isinstance(d.eli5, dict):
            pic = f'<p class="analogy">{html.escape(d.eli5["icon"])} {inline(easy[0])}</p>' + "".join(f"<p>{inline(x)}</p>" for x in easy[1:])
        else:
            pic = f'<p class="eli5-fail">{inline(easy[0])}</p>'
        what = f'<p class="fact">{inline(d.fact())}</p>' if d.fact() else ""
        out.append(f'<div class="done"><p class="chip">{inline(d.chip)}</p><h3>{inline(d.head())}</h3>{what}<div class="eli5">{pic}</div></div>')
    return "\n".join(out)


REMAINING = "<!--remaining-->"
PART2 = '<p class="part">아래는 남은 일이에요 — 오빠 차례 · 골마다 남은 것 · 왜 아직 열려 있나 · 어느 팀이 다음에 무엇을 하나</p>\n' + REMAINING


def _footer(b: Brief) -> str:
    rows, seen = [[f"원장 {b.src}", "이 판을 만든 원장 커밋"]], set()
    for why, what in b.evidence:
        if (why, what) not in seen:
            seen.add((why, what))
            rows.append([html.escape(why), html.escape(what)])
    return "<footer>\n" + _table(["근거", "무엇"], rows) + "\n</footer>"


def render(b: Brief) -> str:
    sections = [
        ("오빠 할 일", _todo(b)),
        ("지난 판 뒤로 바뀐 것", _changes(b)),
        ("눈여겨볼 열린 일", _table(["일", "지금"], [[inline(t), f'<span class="wait">{inline(s)}</span>'] for t, s in b.open_rows]) + '\n<p class="more">나머지 열린 일은 원장에 있어요(이 판에는 planner 가 고른 줄과 «오빠 확인 대기·막힘» 줄만 올라와요).</p>' if b.open_rows else ""),
        ("팀은 지금", _table(["팀", "지금", "다음"], [[inline(c) for c in r] for r in b.teams], {i for i, r in enumerate(b.teams) if r[1].startswith("쉼")}) if b.teams else ""),
        ("드러난 문제", _list("ul", [inline(x) for x in b.problems]) if b.problems else ""),
    ]
    month, day = int(b.date[5:7]), int(b.date[8:10])
    body = [f'<p class="date">{month}월 {day}일 아침 매거진</p>', f"<h1>{inline(b.conclusion) if b.conclusion else NO_CONCLUSION}</h1>"]
    body += [f"<h2>끝낸 일</h2>\n{_done(b)}"] if b.span else []
    body.append(PART2)  # ② 남은 일 — 골 표(magazine_doc)는 REMAINING 자리에 들어간다
    body += [f"<h2>{title}</h2>\n{text}" for title, text in sections if text]
    body.append(_footer(b))
    values = {"TITLE": html.escape(f"매거진 {b.date} · 오빠 확인판"), "BODY": "\n\n".join(body)}
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], TEMPLATE.read_text(encoding="utf-8"))
