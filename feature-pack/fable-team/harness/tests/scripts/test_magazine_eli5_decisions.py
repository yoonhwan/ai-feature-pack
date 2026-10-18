"""쉬운 판 첫 장 결정 두 박스 (판정 609 r2-2) — 출처·분류·다시 쓰기 실패·순서."""
import logging

import pytest
from _magazine_eli5_kit import EASY, box, llm, model, render, skill  # noqa: F401

import magazine_eli5 as me
from magazine_eli5_decisions import split_verdicts

pytestmark = pytest.mark.usefixtures("skill")
MARKED = [(1, "[a->b] [판정 345 · 오빠 10-08] 발행 시간은 여덟 시로 한다"), (2, "[a->b] [c->d] [판정 346 · 오빠 10-08] 쉬운 판은 PDF 로 붙인다")]
OTHER = [(3, "[a->b] 승계 접수 — 새 좌석이 이어받음"), (4, "판정 9 오빠가 승인했다고 전함"), (5, "[판정 347] 오빠 확인 필요")]


def test_e1_pending_box_has_one_line_per_hil_and_an_explicit_empty_sentence(monkeypatch):
    two = render(monkeypatch, model(hil=("첫째 결정을 해 주세요", "둘째 결정을 해 주세요")))
    assert box(two, " pending").count("<li>") == 2 and "오빠가 내려야 할 결정" in box(two, " pending")
    none = render(monkeypatch, model(hil=()))
    assert "지금 기다리는 결정은 없어요" in box(none, " pending") and "<li>" not in box(none, " pending")


def test_e2_decided_box_takes_only_marked_heads_and_lists_the_rest_in_the_end_table(monkeypatch):
    prompts = []
    page = render(monkeypatch, model(hil=(), verdicts=MARKED + OTHER), llm(prompts))
    decided = box(page, " decided")
    assert decided.count("<li>") == 2 and "판정 머리에 ‘오빠’ 표식이 있는 기록 2건" in decided
    assert "오빠 표식이 없는 판정 기록 3건 — 끝 각주 목록" in decided
    assert all(t in page.split('id="unmarked"')[1] for t in ("승계 접수", "오빠가 승인했다고 전함", "오빠 확인 필요"))
    assert len(prompts) == 1 and "발행 시간은 여덟 시로" in prompts[0] and "승계 접수" not in prompts[0]


def test_e3_rewrite_failure_shows_failure_sentence_with_footnote_and_error(monkeypatch, caplog):
    m = model(hil=("첫째를 해 주세요", "둘째를 해 주세요"))
    bad = lambda ref, text: "가" * 71 if ref == "0" else EASY  # noqa: E731
    with caplog.at_level(logging.ERROR, logger="byz_morning_magazine"):
        page = render(monkeypatch, m, llm(decide=bad))
    pending = box(page, " pending")
    assert "쉬운 말 풀이 실패 — 원문은 각주 [1]" in pending and EASY in pending and pending.count("<li>") == 2
    assert "<td>[1]</td><td>오빠 몫</td><td>첫째를 해 주세요</td>" in page
    assert len([r for r in caplog.records if "결정 줄 풀이 생략" in r.message]) == 1
    with caplog.at_level(logging.ERROR, logger="byz_morning_magazine"):
        down = render(monkeypatch, m, llm(fail_decisions=True))
    assert box(down, " pending").count("쉬운 말 풀이 실패") == 2  # 호출 전체가 실패해도 박스는 그대로 나간다


def test_e3b_rewrite_with_index_token_is_a_failure_line(monkeypatch):
    page = render(monkeypatch, model(), llm(decide=lambda ref, text: "판정 602 를 해 주세요"))
    assert "쉬운 말 풀이 실패" in box(page, " pending") and "판정 602 를" not in box(page, " pending")


def test_e5_first_page_order_pending_decided_core_cards(monkeypatch):
    page = render(monkeypatch, model(verdicts=MARKED))
    order = [page.index(x) for x in ('id="decisions"', "오빠가 내려야 할 결정</h3>", 'id="core"', 'id="decided"', "오빠가 내린 결정</h3>", 'id="units"', 'id="footnotes"')]
    assert order == sorted(order) and "main 에 두 건이 들어갔어요" in page.split('id="core"')[1].split('id="decided"')[0]
    assert 'class="decision decided"' in page and 'class="decision pending"' in page
    assert "닫힌 일 1건 · 오빠가 내린 결정 2건 · 기다리는 결정 1건" in page


def test_print_css_lets_the_decided_box_flow_across_pages_but_keeps_its_lines_whole():
    css = open(me.TEMPLATE, encoding="utf-8").read().split("@media print{")[1].split("</style>")[0]
    assert ".unit-card,.decision:not(.decided){break-inside:avoid}" in css and ".decided li{break-inside:avoid}" in css
    assert ".decided{break-inside:avoid}" not in css and ".decision{break-inside:avoid}" not in css


@pytest.mark.parametrize("line,marked", [
    ("[a->b] [판정 345 · 오빠 10-08] x", True), ("[a->b] [c->d] [판정 345 · 오빠] x", True),
    ("[a->b] 승계 접수 …", False), ("판정 9 오빠가 승인", False), ("[판정 345] 오빠 승인", False), ("[HIL 오빠] 확인", True), ("[HIL] 오빠 확인", False),
])
def test_d1_d2_marker_is_read_from_first_bracket_head_after_send_prefix(line, marked):
    got, other = split_verdicts([{"n": 1, "line": line}])
    assert bool(got) is marked and bool(other) is not marked
