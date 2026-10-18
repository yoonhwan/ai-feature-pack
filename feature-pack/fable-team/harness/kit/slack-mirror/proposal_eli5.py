"""proposal_eli5 — 제안서 md → 쉬운 판 HTML (판정 357 설계 §r2-2). 매거진 eli5 묶음 모듈을 «부르기만» 한다.

사실 영역(결정 박스·되돌림·절 원문·각주표) = md 원문 그대로 · AI 풀이 영역 = 절 카드 옆 보조. 절 파싱 실패는 raise(발행 0),
AI 풀이 0건은 Eli5Error(호출 쪽이 HTML 없이 md 만 발행 + 경고 줄 + ERROR). 호출 쪽이 읽은 «한 번의 바이트»만 받는다(파일을 다시 읽지 않는다).
"""
from collections import Counter
from pathlib import Path
from string import Template

from magazine_eli5 import Eli5HTML, Eli5Stats, _h, _skill
from magazine_eli5_batches import explain
from magazine_render import scrub
from magazine_summary import run_cmd

TEMPLATE = Path(__file__).with_name("proposal_eli5_template.html")
CARD_SECTIONS = ("결론", "제안", "영향 범위", "검증", "실험·예측 시뮬")


def sections(text: str) -> tuple[str, dict[str, list[str]]]:
    """(제목, {절 이름: 줄들}) — 같은 이름의 절이 둘이면 raise(어느 쪽이 원문인지 알 수 없다)."""
    title, out, cur = "", {}, None
    for ln in text.splitlines():
        if ln.startswith("# ") and not title:
            title = ln[2:].strip()
        elif ln.startswith("## "):
            cur = ln[3:].strip()
            if cur in out:
                raise ValueError(f"제안서에 「## {cur}」 칸이 둘 이상")
            out[cur] = []
        elif cur is not None:
            out[cur].append(ln)
    return title, out


def _raw(lines: list[str]) -> str:
    body = [ln for ln in lines if ln.strip()]
    return "".join(f"<p>{_h(ln)}</p>" for ln in body) if body else "<p>없어요</p>"


def _card(name: str, lines: list[str], ai: dict | str) -> str:
    src = "".join(f"<p>{_h(scrub(ln))}</p>" for ln in lines if ln.strip())
    card = f'<article class="unit-card"><div class="chips"><span>{_h(name)}</span></div><h3>{_h(name)}</h3><div class="source"><span>원문</span>{src}</div>'
    if isinstance(ai, str):
        return card + f'<p class="omitted">AI 풀이 없음 — {_h(ai)}</p></article>'
    return card + (
        f'<aside class="ai-explanation"><div class="ai-heading"><span class="icon" aria-hidden="true">{_h(ai["icon"])}</span>'
        f'<span>AI 풀이 — 정본은 옆 원문 줄</span></div><p class="analogy">{_h(ai["analogy"])}</p>'
        + "".join(f'<p class="explanation-line">{_h(x)}</p>' for x in ai["lines"]) + "</aside></article>"
    )


def build(text: str, key: str, cmd: str) -> Eli5HTML:
    title, secs = sections(text)
    for need in ("오빠가 결정할 것", "되돌림"):
        if not any(ln.strip() for ln in secs.get(need, [])):
            raise ValueError(f"제안서 「## {need}」 칸이 없거나 비어 있다")
    names = [n for n in CARD_SECTIONS if n in secs]
    units = [{"path": f"{key}#{n}", "title": n, "text": "\n".join(secs[n])} for n in names]
    ai = explain(units, cmd, _skill(), run_cmd)
    reasons = dict(sorted(Counter(v for v in ai.values() if isinstance(v, str)).items()))
    omitted = sum(reasons.values())
    stats: Eli5Stats = {"success": len(units) - omitted, "total": len(units), "omitted": omitted, "reasons": reasons}
    counts = " · ".join(f"{r} {c}건" for r, c in reasons.items()) or "없음"
    page = Template(TEMPLATE.read_text(encoding="utf-8")).substitute(
        key=_h(key), title=_h(title or key), decision=_raw(secs["오빠가 결정할 것"]), revert=_raw(secs["되돌림"]),
        cards="".join(_card(n, secs[n], ai[f"{key}#{n}"]) for n in names),
        footnotes='<pre class="raw">' + _h("\n".join(ln for ln in secs.get("각주표", []) if ln.strip()) or "없음") + "</pre>",
        stats=_h(f"AI 풀이 {stats['success']}/{stats['total']} · 생략 {omitted}({counts})"),
    )
    return Eli5HTML(page, stats)

