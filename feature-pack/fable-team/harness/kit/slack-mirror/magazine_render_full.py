"""magazine_render_full — 풀 디테일 PDF 문서 (설계 §1): 1부 요약판(render 그대로) + 2부 풀 디테일 7절 + 부록 + 각주표(맨 끝 하나).

2부 입력은 구조 모델의 새 칸 `detail`(설계 §3). 칸이 없으면 RenderError — 조용히 1부만 내지 않는다.
한 건 = 제목 + 본문 3줄 + 원문 위치 1줄 · 한 절은 20건까지(판정 812·821 — magazine_render_cap). 자리마다 «원문 위치» 가 남는다. 자유 문장의 `#N` 은 «N번» 으로 푼다.
빈 절은 생략하지 않고 「없어요」 한 줄 — 수집이 됐다는 표시.
"""
import logging
from collections.abc import Callable, Sequence

import magazine_card_shape as shape
from magazine_emit import Block, Model, to_html, to_md
from magazine_render import REF, RenderError, check_footnotes, clean_title, footnote_blocks, notes_of, part1, scrub
from magazine_render_cap import cap_item, cap_list, cap_section

LOG = logging.getLogger("byz_morning_magazine")
DETAIL_KEYS = ("refs", "units", "malformed", "verdict_sections", "decisions", "merge_bodies", "issue_evidence", "open", "seats_closed", "appendix")
OPEN_KEYS = ("cards", "requests", "malformed_requests", "holds", "breaches")
NONE: Block = ("p", "없어요")
DETAIL_ANCHORS = ("d1", "d2", "d3", "d6", "d7")  # PDF 에서 빠지고 부록 md 로 가는 상세 절(R111 · 오빠 판정 1396)
APPENDIX_POINTER = "상세는 부록 파일 — D1 닫힌 단위 · D2 판정서 절 · D3 판정 · D6 열린 행 · D7 좌석은 같은 스레드의 부록 md 에 있어요"


def _keep(text: object) -> str:
    return "\n".join(REF.sub(lambda m: f"{m.group(1)}번", line) for line in str(text).splitlines())


def _item(title: str, candidates: Sequence[str], where: str) -> tuple[list[Block], str]:
    return cap_item(title, [_keep(c) for c in candidates], where)


def _bullets(items: list[str]) -> Block:
    return ("ul", [(scrub(x), None) for x in items])


def _d1_units(m: Model) -> list[Block]:
    # r1009 — 완성 카드 «끝낸 일» 줄 = 카드 «- 닫힘 판정문:» 1줄(없으면 «## 상태» 의 «진행→완성» 줄). 머리 «- 상태: 대기» 는 싣지 않는다.
    return cap_section([_item(f"{scrub(u['title'])} · {u['team']}", [_closed_line(u), u["why"]], u["path"] + (f" · DA {u['da']}" if u["da"] else "")) for u in m["detail"]["units"]])


def _closed_line(unit: dict) -> str:
    """카드 하나의 닫는 줄 — done(닫힘 판정문→진행→완성) → 첫 증거 줄 → 배경(증거 0장 카드)."""
    return unit.get("done") or next(iter(unit["evidence"]), unit["why"])


def _d2_verdict_sections(m: Model) -> list[Block]:
    return cap_section([_item(scrub(f"{v['section']} {v['title']}"), [v["body"]], f"{v['path']} {v['section']}") for v in m["detail"]["verdict_sections"]])


def _d3_decisions(m: Model) -> list[Block]:
    return cap_section([_item(f"판정 {int(d['n'])}", [f"{d['ts']} → {d['to']}", d["body"]], (d["relay_path"] or "쪽지 원문") + (f" · 같은 번호 {int(d['more'])}건 더" if d["more"] else ""))
                        for d in m["detail"]["decisions"]])


def _d4_main(m: Model) -> list[Block]:
    bodies, items = m["detail"]["merge_bodies"], []
    for mg in m["merges"]:
        pr, sha = f" (#{int(mg['pr'])})" if mg.get("pr") else "", str(mg["sha"])[:10]
        items.append(_item(f"{clean_title(mg['title'])}{pr} · {sha}", [bodies.get(mg["sha"], "(커밋 본문 없음)")], sha))
    return cap_section(items)


def _d5_issues(m: Model) -> list[Block]:
    ev = m["detail"]["issue_evidence"]
    return cap_section([_item(f"새로 연 이슈 #{int(i['number'])} {scrub(i['title'])}", ["열림"], f"이슈 {int(i['number'])}번") for i in m["issues_opened"]]
                       + [_item(f"닫은 이슈 #{int(i['number'])} {scrub(i['title'])}", [ev.get(str(i["number"])) or "닫는 댓글 없음"], f"이슈 {int(i['number'])}번") for i in m["issues_closed"]])


def _d6_open(m: Model) -> list[Block]:
    o = m["detail"]["open"]
    out = cap_section([_item(f"[{c['team']}/{c['state']}] {scrub(c['title'])}", ["\n".join(c["tail"])], str(c["path"])) for c in o["cards"]])
    req, more = cap_list(o["requests"], lambda r: str(r["id"]))
    out += [("h3", "요청 원장 — 닫히지 않은 행")] + ([_bullets([f"{r['id']}: {r['text']}" for r in req]), *more] if req else [NONE])
    hold, more = cap_list(o["holds"], lambda h: str(h["path"]))
    out += [("h3", "HOLD·REJECT 판정문")] + ([_bullets([f"{h['path']}: {h['verdict']}" for h in hold]), *more] if hold else [NONE])
    out += cap_section([_item(f"외부 장애 {b['path']}", [b["text"]], str(b["path"])) for b in o["breaches"]])
    return out if o["cards"] or o["breaches"] else out + [("p", "열린 카드·외부 장애 없음")]


def _d7_seats(m: Model) -> list[Block]:
    succ, new = m["seats"].get("succession", []), m["seats"].get("new", [])
    out: list[Block] = [("h3", f"승계 {len(succ)}건 · 신규 {len(new)}석")]
    shown, more = cap_list(succ, lambda r: str(r[0]))
    out.append(("table", ["이전", "이후"], [[scrub(o), scrub(n)] for o, n in shown]) if succ else NONE)
    shown_new, more_new = cap_list(list(new), str)
    out += [*more, ("h3", "신규 좌석")] + ([_bullets(shown_new), *more_new] if new else [NONE]) + [("h3", "닫힘 (NANO-LEDGER)")]
    closed, more = cap_list(m["detail"]["seats_closed"], lambda c: str(c["path"]))
    return out + ([_bullets([f"{c['path']}: {c['line']}" for c in closed]), *more] if closed else [NONE])


def _malformed(m: Model) -> list[Block]:
    bad = m["detail"]["malformed"]
    if not bad:
        return []
    shown, more = cap_list(bad, lambda c: str(c["path"]))
    return [("h3", f"형식 미달 카드 {len(bad)}장"), _bullets([f"{c['team']} · {c['path']} · 빠진 절: {', '.join(c['missing'])}" for c in shown]), *more]


def _malformed_requests(m: Model) -> list[Block]:
    bad = m["detail"]["open"]["malformed_requests"]
    if not bad:
        return []
    shown, more = cap_list(bad, lambda r: str(r["id"]))
    return [("h3", f"형식 미달 요청 행 {len(bad)}개"), _bullets([f"{r['id']} · 열 수 {r['cells']}(기대 7)" for r in shown]), *more]


def _appendix(m: Model) -> list[Block]:
    return _malformed(m) + _malformed_requests(m) + cap_section([_item(str(a["path"]), [a["text"]], str(a["path"])) for a in m["detail"]["appendix"]])


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


def _blocks(model: Model, lines: list[str], generated_at: str, warn: str | None, skip: frozenset[str]) -> list[Block]:
    """skip 에 든 앵커의 절은 빼고 목차에 «상세는 부록 파일» 1줄을 둔다."""
    check_detail(model)
    body, notes = part1(model, lines, generated_at)
    first = next(i for i, b in enumerate(body) if b[0] == "h2")  # 1부 첫 절(결론) 에 목차 앵커
    body[first] = (*body[first], "part1")
    toc = [("1부 요약판", "part1")] + [(name, anchor) for anchor, name, _ in SECTIONS if anchor not in skip] + [("각주표", "footnotes")]
    bad = [shape.warning_line(model["detail"]["malformed"]), shape.requests_warning_line(model["detail"]["open"]["malformed_requests"])]
    pointer: list[Block] = [("p", APPENDIX_POINTER)] if skip else []
    blocks: list[Block] = body[:1] + [("h2", "목차"), ("toc", toc)] + pointer + [("p", w) for w in bad if w] + body[1:] + ([("p", warn)] if warn else [])
    blocks.append(("h1", "2부 풀 디테일"))
    for anchor, name, build in SECTIONS:
        if anchor not in skip:
            blocks += [("h2", name, anchor)] + (build(model) or [NONE])
    check_footnotes(to_md(blocks), notes)
    return blocks + [("h2", "각주표", "footnotes")] + footnote_blocks(notes)[1:]


def render_full(model: Model, lines: list[str], generated_at: str, warn: str | None = None) -> tuple[str, str]:
    """(md, html). warn = 쉬운 판(eli5) 실패 1줄 — 있으면 «근거» 절 끝에 같은 줄로 남긴다(설계 §5)."""
    blocks = _blocks(model, lines, generated_at, warn, frozenset())
    return to_md(blocks), to_html(blocks, str(blocks[0][1]))


def render_summary(model: Model, lines: list[str], generated_at: str, warn: str | None = None) -> tuple[str, str, str]:
    """(PDF 원본 md, PDF 원본 html, 부록 md) — PDF 는 요약 절만, 상세 절(DETAIL_ANCHORS)은 부록 md 로 절 순서 그대로(R111)."""
    blocks = _blocks(model, lines, generated_at, warn, frozenset(DETAIL_ANCHORS))
    appendix: list[Block] = [("h1", f"{blocks[0][1]} — 상세 부록")]
    for anchor, name, build in SECTIONS:
        if anchor in DETAIL_ANCHORS:
            appendix += [("h2", name, anchor)] + (build(model) or [NONE])
    return to_md(blocks), to_html(blocks, str(blocks[0][1])), to_md(appendix)


def build_eli5(model: Model, cmd: str, lines: Sequence[str] = ()) -> tuple[str | None, str | None]:
    """(HTML, None) 성공 · (None, 원인 첫 줄) 실패 — 실패는 ERROR 로그 + 호출 쪽이 뿌리 글·PDF 근거 절에 같은 줄을 남긴다(설계 §5).

    모듈 없음(ImportError)·Eli5Error(RuntimeError)만 «보이는 실패»로 다룬다. 그 밖의 예외는 발행 전체 실패로 올라간다.
    """
    try:
        import magazine_eli5
        return magazine_eli5.build(model, notes_of(model), cmd, lines), None
    except (ImportError, RuntimeError) as e:
        LOG.error("쉬운 판(eli5) 생성 실패: %s: %s", type(e).__name__, e)
        return None, (str(e).splitlines() or [""])[0] or type(e).__name__
