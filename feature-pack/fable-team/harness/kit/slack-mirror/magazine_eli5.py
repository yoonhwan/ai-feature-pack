"""eli5 JSON → 오프라인 HTML. 사실 영역과 AI 풀이 영역은 템플릿에서 분리한다."""
import html
import logging
import re
from collections import Counter
from collections.abc import Sequence
from pathlib import Path
from string import Template
from typing import TypedDict

from magazine_eli5_batches import BLOCKED_WORDS as BLOCKED_WORDS, ICONS as ICONS, Eli5Error, explain
from magazine_eli5_decisions import decision_boxes
from magazine_emit import Model
from magazine_indexless import Foot, check_body, find_tokens, strip_tokens
from magazine_render import Notes, scrub
from magazine_summary import run_cmd

SKILL_ROOT = Path.home() / ".claude/plugins/cache/claude-community/eli5"
TEMPLATE = Path(__file__).with_name("magazine_eli5_template.html")
LOG = logging.getLogger("byz_morning_magazine")


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


def _core(lines: Sequence[str], foot: Foot, texts: list[str]) -> str:
    """24시간 핵심 — 요약 줄(summary.lines)을 그대로. 인덱스 표기가 있으면 걷어 그 줄 끝 각주로."""
    if not lines:
        return "<p>없어요</p>"
    items = []
    for line in lines:
        clean, found = strip_tokens(line)
        mark = f' <sup class="fn">[{foot.add("핵심 줄", "걷어 낸 표기: " + " · ".join(found))}]</sup>' if found else ""
        texts.append(clean)
        items.append(f"<li>{_h(clean)}{mark}</li>")
    return "<ul>" + "".join(items) + "</ul>"


def _drop_indexed(ai: dict[str, dict | str]) -> None:
    """AI 풀이가 인덱스 표기를 품으면 «그 카드만» 풀이 없음(번호) — 쉬운 판 전체를 죽이지 않는다."""
    for path, value in ai.items():
        if isinstance(value, dict) and find_tokens(" ".join([value["analogy"], *value["lines"]])):
            LOG.error("AI 풀이 생략 path=%s 사유=번호", path)
            ai[path] = "번호"


def _facts(unit: dict, foot: Foot, texts: list[str]) -> str:
    raw_title = " ".join(str(unit["title"]).split())
    raw_line = " ".join(re.split(r"(?<=[.!?。])\s+|\n", str(unit["why"]), maxsplit=1)[0].split())
    title, gone_t = strip_tokens(raw_title)
    source, gone_s = strip_tokens(raw_line)
    team = scrub(unit["team"])
    parts = ([f"원제목 {raw_title}"] if gone_t else []) + ([f"원문 줄 {raw_line}"] if gone_s else []) + [f"커밋 {str(unit['moved_sha'])[:10]}"]
    n = foot.add("닫힌 단위", " · ".join(parts))
    texts += [team, title or "(제목은 각주)", source or "(원문 줄은 각주)"]
    return (
        f'<div class="chips"><span>{_h(team)}</span><span>닫힘</span></div>'
        f'<h3>{_h(title or "(제목은 각주)")} <sup class="fn">[{n}]</sup></h3>'
        f'<div class="source"><span>원문</span><p>{_h(source or "(원문 줄은 각주)")}</p></div>'
    )


def _card(unit: dict, ai: dict | str, foot: Foot, texts: list[str]) -> str:
    fact = '<article class="unit-card">' + _facts(unit, foot, texts)
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


def build(model: Model, notes: Notes, cmd: str, lines: Sequence[str] = ()) -> Eli5HTML:
    units = _units(model)
    ai = explain(units, cmd, _skill(), run_cmd)
    _drop_indexed(ai)
    reasons = dict(sorted(Counter(v for v in ai.values() if isinstance(v, str)).items()))
    omitted = sum(reasons.values())
    stats: Eli5Stats = {"success": len(units) - omitted, "total": len(units), "omitted": omitted, "reasons": reasons}
    counts = " · ".join(f"{reason} {count}건" for reason, count in reasons.items()) or "없음"
    footer = f"AI 풀이 {stats['success']}/{stats['total']} · 생략 {omitted}({counts})"
    foot, texts = Foot(), []
    boxes = decision_boxes(model, cmd, run_cmd, foot)
    core = _core(lines, foot, texts)
    cards = "".join(_card(u, ai[u["path"]], foot, texts) for u in units)
    headline = f"닫힌 일 {len(units)}건 · 오빠가 내린 결정 {boxes.marked}건 · 기다리는 결정 {boxes.waiting}건"
    check_body([headline, *boxes.texts, *texts])  # «사실 문자열»(걷어 낸 제목·원문 줄·핵심 줄·박스 문구) — 남으면 진짜 버그라 쉬운 판 실패 경로 · AI 풀이는 위에서 카드별로 처리
    page = Template(TEMPLATE.read_text(encoding="utf-8")).substitute(
        date=_h(model["date"]), headline=_h(headline), pending=boxes.pending, decided=boxes.decided, core=core, cards=cards,
        footnotes=foot.html() + "<h3>PR·이슈</h3>" + _footnotes(notes), unmarked=boxes.unmarked, stats=_h(footer),
    )
    return Eli5HTML(page, stats)
