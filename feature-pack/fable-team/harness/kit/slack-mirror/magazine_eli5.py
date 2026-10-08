"""eli5 JSON → 오프라인 HTML. 사실 영역과 AI 풀이 영역은 템플릿에서 분리한다."""
import html
import re
from collections import Counter
from pathlib import Path
from string import Template
from typing import TypedDict

from magazine_emit import Model
from magazine_eli5_batches import BLOCKED_WORDS as BLOCKED_WORDS, ICONS as ICONS, Eli5Error, explain
from magazine_render import Notes, scrub
from magazine_summary import run_cmd

SKILL_ROOT = Path.home() / ".claude/plugins/cache/claude-community/eli5"
TEMPLATE = Path(__file__).with_name("magazine_eli5_template.html")


class Eli5Stats(TypedDict):
    success: int
    total: int
    omitted: int
    reasons: dict[str, int]


class Eli5HTML(str):
    stats: Eli5Stats

    def __new__(cls, value: str, stats: Eli5Stats):
        result = super().__new__(cls, value)
        result.stats = stats
        return result


def _h(value: object) -> str:
    return html.escape(str(value), quote=True)


def _skill() -> str:
    paths = list(SKILL_ROOT.glob("*/skills/eli5/SKILL.md"))
    if not paths:
        raise Eli5Error("eli5 SKILL.md 없음")
    newest = max(paths, key=lambda p: tuple(int(n) for n in re.findall(r"\d+", p.parents[2].name)))
    body = newest.read_text(encoding="utf-8")
    body = re.sub(r"\A---[ \t]*\r?\n.*?\r?\n---[ \t]*(?:\r?\n|\Z)", "", body, count=1, flags=re.DOTALL)
    return body.replace("$ARGUMENTS", "아래 <자료>")


def _units(model: Model) -> list[dict]:
    detail = model.get("detail")
    if not isinstance(detail, dict) or not isinstance(detail.get("units"), list):
        raise ValueError("detail.units 칸 없음 — 수집부터 다시")
    units = detail["units"]
    paths = [u.get("path") if isinstance(u, dict) else None for u in units]
    if any(not isinstance(p, str) or not p for p in paths) or len(set(paths)) != len(paths):
        raise ValueError("detail.units 경로가 없거나 중복됨")
    return units


def _list(lines: list[str]) -> str:
    return "<ul>" + "".join(f"<li>{_h(scrub(line))}</li>" for line in lines) + "</ul>" if lines else "<p>없어요</p>"


def _decisions(model: Model) -> str:
    lines = []
    for verdict in model["verdicts"]:
        line = scrub(verdict["line"])
        if len(line) > 80:
            line = line[:80] + "…원문은 PDF D3"
        lines.append(f"판정 {verdict['n']} · {line}")
    return _list(lines)


def _facts(unit: dict) -> str:
    sentence = re.split(r"(?<=[.!?。])\s+|\n", str(unit["why"]), maxsplit=1)[0]
    return (
        f'<div class="chips"><span>{_h(scrub(unit["team"]))}</span><span>닫힘</span>'
        f'<span class="evidence">{_h(unit["moved_sha"][:10])}</span></div>'
        f'<h3>{_h(scrub(unit["title"]))}</h3>'
        f'<div class="source"><span>원문</span><p>{_h(scrub(sentence))}</p></div>'
    )


def _card(unit: dict, ai: dict | str) -> str:
    fact = '<article class="unit-card">' + _facts(unit)
    if isinstance(ai, str):
        return fact + f'<p class="omitted">AI 풀이 없음 — {_h(ai)}</p></article>'
    explanation = (
        '<aside class="ai-explanation"><div class="ai-heading">'
        f'<span class="icon" aria-hidden="true">{_h(ai["icon"])}</span>'
        '<span>AI 풀이 — 정본은 옆 원문 줄</span></div>'
        f'<p class="analogy">{_h(ai["analogy"])}</p>'
        + "".join(f'<p class="explanation-line">{_h(line)}</p>' for line in ai["lines"]) + "</aside>"
    )
    return fact + explanation + "</article>"


def _footnotes(notes: Notes) -> str:
    if not notes:
        return "<p>없어요</p>"
    rows = "".join(
        "<tr>" + "".join(f"<td>{_h(x)}</td>" for x in (f"#{n}", *(scrub(v) for v in values))) + "</tr>"
        for n, values in sorted(notes.items())
    )
    return '<table><thead><tr><th>번호</th><th>종류</th><th>제목</th><th>상태</th></tr></thead><tbody>' + rows + "</tbody></table>"


def build(model: Model, notes: Notes, cmd: str) -> Eli5HTML:
    units = _units(model)
    ai = explain(units, cmd, _skill(), run_cmd)
    reasons = dict(sorted(Counter(v for v in ai.values() if isinstance(v, str)).items()))
    omitted = sum(reasons.values())
    stats: Eli5Stats = {"success": len(units) - omitted, "total": len(units), "omitted": omitted, "reasons": reasons}
    counts = " · ".join(f"{reason} {count}건" for reason, count in reasons.items()) or "없음"
    footer = f"AI 풀이 {stats['success']}/{stats['total']} · 생략 {omitted}({counts})"
    hil = model["mbox"]["hil"]
    headline = f"닫힌 일 {len(units)}건 · 결정 {len(model['verdicts'])}건 · 오빠 몫 {len(hil)}건"
    page = Template(TEMPLATE.read_text(encoding="utf-8")).substitute(
        date=_h(model["date"]), headline=_h(headline), hil=_list(hil), decided=_decisions(model),
        cards="".join(_card(u, ai[u["path"]]) for u in units), footnotes=_footnotes(notes), stats=_h(footer),
    )
    return Eli5HTML(page, stats)
