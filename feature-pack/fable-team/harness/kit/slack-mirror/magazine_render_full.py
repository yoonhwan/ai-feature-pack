"""magazine_render_full — 풀 디테일 PDF 문서 (설계 §1): 1부 요약판(render 그대로) + 2부 풀 디테일 7절 + 부록 + 각주표(맨 끝 하나).

2부 입력은 구조 모델의 새 칸 `detail`(설계 §3). 칸이 없으면 RenderError — 조용히 1부만 내지 않는다.
긴 본문은 줄 단위 그대로(잘림·요약 0). 자유 문장의 `#N` 은 «N번» 으로 푼다(줄 구조는 유지).
빈 절은 생략하지 않고 「없어요」 한 줄 — 수집이 됐다는 표시.
"""
import logging
from collections.abc import Callable
from typing import Any

from magazine_emit import Block, Model, to_html, to_md
from magazine_render import REF, RenderError, check_footnotes, clean_title, footnote_blocks, notes_of, part1, scrub

LOG = logging.getLogger("byz_morning_magazine")
DETAIL_KEYS = ("refs", "units", "verdict_sections", "decisions", "merge_bodies", "issue_evidence", "open", "seats_closed", "appendix")
OPEN_KEYS = ("cards", "requests", "holds", "breaches")
NONE: Block = ("p", "없어요")


def _keep(text: object) -> str:
    return "\n".join(REF.sub(lambda m: f"{m.group(1)}번", line) for line in str(text).splitlines())


def _body(text: object) -> Block:
    return ("lines", _keep(text)) if str(text).strip() else ("p", "(비어 있음)")


def _bullets(items: list[str]) -> Block:
    return ("ul", [(scrub(x), None) for x in items])


def _d1_units(m: Model) -> list[Block]:
    out: list[Block] = []
    for u in m["detail"]["units"]:
        out += [("h3", f"{scrub(u['title'])} · {u['team']}"), _body(u["why"]), ("p", f"골좌표: {scrub(u['coord'])}"), _bullets(u["evidence"] or ["(닫는 증거 줄 없음)"]),
                _bullets([f"DA 판정문: {u['da'] or '(없음)'}", f"옮긴 커밋: {str(u['moved_sha'])[:10]} ({u['ref']})", f"카드: {u['path']}"])]
    return out


def _d2_verdict_sections(m: Model) -> list[Block]:
    out: list[Block] = []
    for v in m["detail"]["verdict_sections"]:
        out += [("h3", scrub(f"{v['section']} {v['title']}")), ("p", str(v["path"])), _body(v["body"])]
    return out


def _decision(d: dict[str, Any]) -> list[Block]:
    out: list[Block] = [("h3", f"판정 {int(d['n'])}"), ("p", f"{d['ts']} → {d['to']}"), _body(d["body"])]
    if d["relay_text"] is None:
        out.append(("p", f"relay 전문: 전문 파일 없음(/tmp 휘발) {d['relay_path'] or ''}".strip()))
    else:
        out += [("p", f"relay 전문 ({d['relay_path']})"), _body(d["relay_text"])]
    out.append(_bullets(d["rollback"]) if d["rollback"] else ("p", "원문에 되돌림 없음"))
    return out + ([("p", f"같은 번호 쪽지 {int(d['more'])}건 더")] if d["more"] else [])


def _d3_decisions(m: Model) -> list[Block]:
    return [b for d in m["detail"]["decisions"] for b in _decision(d)]


def _d4_main(m: Model) -> list[Block]:
    bodies, out = m["detail"]["merge_bodies"], []
    for mg in m["merges"]:
        pr = f" (#{int(mg['pr'])})" if mg.get("pr") else ""
        out += [("h3", f"{clean_title(mg['title'])}{pr} · {str(mg['sha'])[:10]}"), _body(bodies.get(mg["sha"], "(커밋 본문 없음)"))]
    return out


def _d5_issues(m: Model) -> list[Block]:
    ev, out = m["detail"]["issue_evidence"], []
    for i in m["issues_opened"]:
        out += [("h3", f"새로 연 이슈 #{int(i['number'])} {scrub(i['title'])}"), ("p", "열림")]
    for i in m["issues_closed"]:
        out += [("h3", f"닫은 이슈 #{int(i['number'])} {scrub(i['title'])}"), _body(ev[str(i["number"])]) if str(i["number"]) in ev else ("p", "닫는 댓글 없음")]
    return out


def _d6_open(m: Model) -> list[Block]:
    o, out = m["detail"]["open"], []
    for c in o["cards"]:
        out += [("h3", f"[{c['team']}/{c['state']}] {scrub(c['title'])}"), ("p", str(c["path"])), ("lines", _keep("\n".join(c["tail"])))]
    out += [("h3", "요청 원장 — 닫히지 않은 행")] + ([_bullets([f"{r['id']}: {r['text']}" for r in o["requests"]])] if o["requests"] else [NONE])
    out += [("h3", "HOLD·REJECT 판정문")] + ([_bullets([f"{h['path']}: {h['verdict']}" for h in o["holds"]])] if o["holds"] else [NONE])
    for b in o["breaches"]:
        out += [("h3", f"외부 장애 {b['path']}"), _body(b["text"])]
    return out if o["cards"] or o["breaches"] else out + [("p", "열린 카드·외부 장애 없음")]


def _d7_seats(m: Model) -> list[Block]:
    succ, new = m["seats"].get("succession", []), m["seats"].get("new", [])
    out: list[Block] = [("h3", f"승계 {len(succ)}건 · 신규 {len(new)}석")]
    out.append(("table", ["이전", "이후"], [[scrub(o), scrub(n)] for o, n in succ]) if succ else NONE)
    out += [("h3", "신규 좌석")] + ([_bullets(list(new))] if new else [NONE]) + [("h3", "닫힘 (NANO-LEDGER)")]
    closed = m["detail"]["seats_closed"]
    return out + ([_bullets([f"{c['path']}: {c['line']}" for c in closed])] if closed else [NONE])


def _appendix(m: Model) -> list[Block]:
    return [b for a in m["detail"]["appendix"] for b in (("h3", str(a["path"])), _body(a["text"]))]


SECTIONS: tuple[tuple[str, str, Callable[[Model], list[Block]]], ...] = (
    ("d1", "D1 닫힌 단위", _d1_units), ("d2", "D2 판정서 절", _d2_verdict_sections), ("d3", "D3 판정(결정 원문)", _d3_decisions),
    ("d4", "D4 main 에 들어간 것", _d4_main), ("d5", "D5 이슈", _d5_issues), ("d6", "D6 열린 행", _d6_open), ("d7", "D7 좌석", _d7_seats),
    ("appendix", "부록 — 브리핑·마감 문서", _appendix),
)


def check_detail(model: Model) -> None:
    detail = model.get("detail")
    if not isinstance(detail, dict):
        raise RenderError("detail 칸 없음 — 수집부터 다시")
    for key in DETAIL_KEYS:
        if key not in detail:
            raise RenderError(f"detail 에 '{key}' 칸 없음")
    for key in OPEN_KEYS:
        if key not in detail["open"]:
            raise RenderError(f"detail.open 에 '{key}' 칸 없음")


def render_full(model: Model, lines: list[str], generated_at: str, warn: str | None = None) -> tuple[str, str]:
    """(md, html). warn = 쉬운 판(eli5) 실패 1줄 — 있으면 «근거» 절 끝에 같은 줄로 남긴다(설계 §5)."""
    check_detail(model)
    body, notes = part1(model, lines, generated_at)
    title = str(body[0][1])
    first = next(i for i, b in enumerate(body) if b[0] == "h2")  # 1부 첫 절(결론) 에 목차 앵커
    body[first] = (*body[first], "part1")
    toc = [("1부 요약판", "part1")] + [(name, anchor) for anchor, name, _ in SECTIONS] + [("각주표", "footnotes")]
    blocks: list[Block] = body[:1] + [("h2", "목차"), ("toc", toc)] + body[1:] + ([("p", warn)] if warn else [])
    blocks.append(("h1", "2부 풀 디테일"))
    for anchor, name, build in SECTIONS:
        blocks += [("h2", name, anchor)] + (build(model) or [NONE])
    check_footnotes(to_md(blocks), notes)
    blocks += [("h2", "각주표", "footnotes")] + footnote_blocks(notes)[1:]
    return to_md(blocks), to_html(blocks, title)


def build_eli5(model: Model, cmd: str) -> tuple[str | None, str | None]:
    """(HTML, None) 성공 · (None, 원인 첫 줄) 실패 — 실패는 ERROR 로그 + 호출 쪽이 뿌리 글·PDF 근거 절에 같은 줄을 남긴다(설계 §5).

    모듈 없음(ImportError)·Eli5Error(RuntimeError)만 «보이는 실패»로 다룬다. 그 밖의 예외는 발행 전체 실패로 올라간다.
    """
    try:
        import magazine_eli5
        return magazine_eli5.build(model, notes_of(model), cmd), None
    except (ImportError, RuntimeError) as e:
        LOG.error("쉬운 판(eli5) 생성 실패: %s: %s", type(e).__name__, e)
        return None, (str(e).splitlines() or [""])[0] or type(e).__name__
