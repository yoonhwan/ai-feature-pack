"""쉬운 판 본문 인덱스 0 (판정 609 r2-3) — 토큰은 본문에서 걷혀 각주로 · 오탐 보존 · 검사 우회는 실패."""
import copy
import logging

import pytest
from _magazine_eli5_kit import UNIT, box, llm, model, render, skill  # noqa: F401

import magazine_eli5 as me
from magazine_indexless import find_tokens, strip_tokens

pytestmark = pytest.mark.usefixtures("skill")
TITLE = "판정 602 R63 (#1060) byz-x-claude#3 M5 ab12cd34ef"


def with_unit(**fields):
    m = model()
    m["detail"]["units"] = [{**copy.deepcopy(UNIT), **fields}]
    return m


def body_of(page: str) -> str:
    return page.split('id="footnotes"')[0]


def test_e4_card_title_loses_its_numbers_in_body_and_keeps_them_in_the_footnote(monkeypatch):
    page = render(monkeypatch, with_unit(title="판정 602 매거진 요약 창 반영 (#1060)"))
    assert "판정 602" not in body_of(page) and "1060" not in body_of(page) and "매거진 요약 창 반영" in body_of(page)
    assert "원제목 판정 602 매거진 요약 창 반영 (#1060)" in page.split('id="footnotes"')[1]


def test_e4b_check_bypass_fixture_raises(monkeypatch):
    with pytest.raises(me.Eli5Error, match="본문 인덱스 검사 실패: R63"):
        render(monkeypatch, with_unit(team="R63"))  # team 칩은 걷어 내는 필드가 아니라 «검사만» 한다


def test_i1_false_positives_are_preserved(monkeypatch):
    page = render(monkeypatch, with_unit(title="CO2 센서 B12 UTF8 점검"))
    assert "CO2 센서 B12 UTF8 점검" in body_of(page) and "원제목" not in page


def test_i2_every_token_moves_to_the_card_footnote(monkeypatch):
    page = render(monkeypatch, with_unit(title=TITLE))
    assert "(제목은 각주)" in body_of(page) and not find_tokens(body_of(page).split('id="units"')[1].split('id="eli5-stats"')[0].replace("<", " <"))
    foot = page.split('id="footnotes"')[1]
    assert all(t in foot for t in ("판정 602", "R63", "(#1060)", "byz-x-claude#3", "M5", "ab12cd34ef"))


def test_i3_sha_chip_moves_to_footnote(monkeypatch):
    page = render(monkeypatch)
    assert "aaaaaaaaaa" not in body_of(page) and "커밋 aaaaaaaaaa" in page.split('id="footnotes"')[1]


def test_i4_failed_decision_line_number_points_at_a_footnote_row(monkeypatch):
    page = render(monkeypatch, model(hil=("셋째를 해 주세요 #77",)), llm(fail_decisions=True))
    assert "원문은 각주 [1]" in box(page, " pending")
    assert "<td>[1]</td><td>오빠 몫</td><td>셋째를 해 주세요 77번</td>" in page


def test_core_line_with_a_token_gets_a_footnote_and_a_clean_line(monkeypatch):
    page = render(monkeypatch, lines=["판정 602 반영이 끝났어요", "깨끗한 줄이에요"])
    core = page.split('id="core"')[1].split('id="units"')[0]
    assert "<li>반영이 끝났어요 <sup" in core and "<li>깨끗한 줄이에요</li>" in core
    assert "<td>핵심 줄</td><td>걷어 낸 표기: 판정 602</td>" in page


@pytest.mark.parametrize("text,gone", [
    ("판정 602 와 §47 확인", ["판정 602", "§47"]), ("R63 이 RR63 은 아님 R1.2", ["R63"]), ("PR #885 (#886) 병합", ["#885", "(#886)"]),
    ("3번 확인 3번째 줄", ["3번"]), ("byz-harness-master-claude#22 에게", ["byz-harness-master-claude#22"]),
    ("M3 K4 M8 K6 MK3", ["M3", "K4"]), ("sha 9f86d081884c 와 20261009 와 deadbeef", ["9f86d081884c"]),
    ("CO2 B12 UTF8 A1 H100", []),
])
def test_token_table(text, gone):
    assert find_tokens(text) == gone and (not gone or not find_tokens(strip_tokens(text)[0]))


def test_ai_explanation_with_a_token_drops_only_that_card(monkeypatch, caplog):
    m = model()
    m["detail"]["units"] = [{**UNIT, "path": "a.md"}, {**UNIT, "path": "b.md", "title": "둘째 카드"}]
    bad = {"icon": "🪟", "analogy": "창 같아요", "lines": ["판정 4 가 반영돼요"]}
    good = {"icon": "🪟", "analogy": "책상 위 작은 창 같아요", "lines": ["한눈에 찾아봐요"]}
    monkeypatch.setattr(me, "explain", lambda units, *a: {"a.md": bad, "b.md": good})
    with caplog.at_level(logging.ERROR, logger="byz_morning_magazine"):
        page = render(monkeypatch, m)
    assert page.count("AI 풀이 없음 — 번호") == 1 and page.count('class="ai-explanation"') == 1 and page.count('class="source"') == 2
    assert page.stats["omitted"] == 1 and page.stats["reasons"] == {"번호": 1} and "판정 4 가" not in page
    assert len([r for r in caplog.records if "사유=번호" in r.message]) == 1


def test_removal_that_glues_neighbours_into_a_new_token_is_stripped_to_a_fixpoint(monkeypatch):
    assert strip_tokens("판정 (#1060) 4 점검") == ("점검", ["(#1060)", "판정 4"])
    page = render(monkeypatch, with_unit(title="판정 (#1060) 4 점검"))
    assert "<h3>점검 " in body_of(page) and "원제목 판정 (#1060) 4 점검" in page
