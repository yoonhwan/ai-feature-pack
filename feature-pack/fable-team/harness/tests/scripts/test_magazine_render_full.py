"""설계 §9 시험 3 — 풀 디테일 렌더: 2부 절 순서 · 빈 절 「없어요」 · detail 없음 raise · 줄 수 보존 · 각주표 맨 끝 하나.

실행: python3 -m pytest tests/scripts/test_magazine_render_full.py -q
"""
import re

import pytest
from _magazine_detail_fixture import detail_fixture, fake_full_model

import magazine_render_full as mrf
from magazine_render import RenderError

LINES = ["한 줄", "두 줄", "세 줄"]
ANCHORS = ["part1", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "appendix", "footnotes"]


def render(model=None, warn=None):
    return mrf.render_full(model or fake_full_model(), LINES, "t", warn)


def test_sections_in_fixed_order_and_one_footnote_table_at_the_end():
    md, html = render()
    ids = re.findall(r'<h2 id="(\w+)"', html)
    assert ids == ANCHORS and html.count("<h2>각주표") + html.count(">각주표</h2>") == 1
    assert md.rstrip().splitlines()[-1].startswith("| #") and md.count("## 각주표") == 1
    assert html.rindex('id="footnotes"') > html.rindex('id="appendix"')


def test_toc_links_resolve_to_real_anchors():
    _, html = render()
    hrefs = re.findall(r'href="#(\w+)"', html)
    assert hrefs == ANCHORS and all(f'id="{h}"' in html for h in hrefs)


def test_empty_sections_say_none_instead_of_vanishing():
    m = fake_full_model()
    d = m["detail"]
    for k in ("units", "verdict_sections", "decisions", "seats_closed", "appendix"):
        d[k] = []
    d["merge_bodies"], d["issue_evidence"] = {}, {}
    d["open"] = {"cards": [], "requests": [], "holds": [], "breaches": []}
    m["merges"], m["issues_opened"], m["issues_closed"] = [], [], []
    m["seats"] = {"succession": [], "new": []}
    _, html = render(m)
    for anchor in ("d1", "d2", "d3", "d4", "d5", "appendix"):
        section = html.split(f'id="{anchor}"')[1].split("<h2")[0]
        assert "없어요" in section, anchor
    assert "열린 카드·외부 장애 없음" in html


def test_missing_detail_or_key_raises_instead_of_part1_only():
    m = fake_full_model()
    del m["detail"]
    with pytest.raises(RenderError, match="detail 칸 없음 — 수집부터 다시"):
        render(m)
    m2 = fake_full_model()
    del m2["detail"]["open"]["breaches"]
    with pytest.raises(RenderError, match="breaches"):
        render(m2)
    m3 = fake_full_model()
    del m3["detail"]["appendix"]
    with pytest.raises(RenderError, match="appendix"):
        render(m3)


def test_long_body_keeps_every_line_including_blank_ones():
    m = fake_full_model()
    m["detail"]["decisions"][0]["relay_text"] = "\n".join(f"긴전문 {i}" for i in range(120))
    md, html = render(m)
    assert html.count('<p class="ln">긴전문 ') == 120 and all(f"긴전문 {i}" in md for i in range(120))
    body = '<p class="ln">본문 1</p>\n<p class="ln">본문 2</p>\n<p class="ln">&nbsp;</p>\n<p class="ln">본문 4</p>'
    assert body in html  # 판정서 절: 빈 줄도 한 줄로


def test_free_text_hash_numbers_become_n_beon_but_structure_numbers_stay():
    md, html = render()
    assert "885번" in md and "#885 참고" not in md and "claude#13" in md  # 좌석 이름의 # 은 그대로
    assert "#880" in md and "#883" in md  # 구조 칸(이슈·PR) 번호는 남고 각주표에 있다
    assert "| #885 |" in md and "| #883 |" in md


def test_html_is_escaped_and_warning_lands_in_evidence_section():
    m = fake_full_model()
    m["detail"]["appendix"][0]["text"] = "<script>alert(1)</script>"
    md, html = render(m, warn="쉬운 판(HTML) 못 만들었어요 — 형식 오류")
    assert "<script>" not in html and "&lt;script&gt;" in html and "제안서 도구 3개 &lt;b&gt;" in html
    evidence = md.split("## 근거")[1].split("## ")[0]
    assert "쉬운 판(HTML) 못 만들었어요 — 형식 오류" in evidence


def test_decision_blocks_show_rollback_and_missing_relay_wording():
    md, _ = render()
    assert "되돌림: PR revert" in md and "원문에 되돌림 없음" in md and "전문 파일 없음(/tmp 휘발)" in md
    assert "같은 번호 쪽지 1건 더" in md and "DA 판정문: design/harness/DA-x.md#§3" in md


def test_detail_fixture_extra_lines_makes_a_longer_document():
    short = render(fake_full_model())[1]
    long = mrf.render_full({**fake_full_model(), "detail": detail_fixture(300)}, LINES, "t")[1]
    assert long.count('class="ln"') - short.count('class="ln"') == 300


def test_external_body_headings_never_become_md_headings():
    """arch#10 반송 r1-①: 본문 속 「## 결론」·표 줄이 md 에서 진짜 제목이 되면 GitHub 목차가 섞인다."""
    m = fake_full_model()
    nasty = "## 결론\n### 오빠가 할 일\n| a | b |\n  # 들여쓴 제목\n본문"
    m["detail"]["appendix"][0]["text"] = nasty
    m["detail"]["issue_evidence"]["880"] = nasty
    m["detail"]["verdict_sections"][0]["body"] = nasty
    md, html = render(m)
    md_heads = [x for x in md.splitlines() if re.match(r"#{1,3} ", x)]
    html_heads = re.findall(r"<h[123][ >]", html)
    print(f"[md 제목줄] md={len(md_heads)} html={len(html_heads)} · 본문 인용 줄 예: {[x for x in md.splitlines() if 'a | b' in x][0]!r}")
    assert len(md_heads) == len(html_heads)  # md 의 «줄머리 제목» 수 = HTML <h1~3> 수 — 외부 본문은 제목이 되지 않는다
    assert md_heads.count("## 결론") == 1 and "### 오빠가 할 일" not in md_heads  # 결론은 1부 우리 절 하나뿐
    assert "> \\## 결론" in md and "> | a | b |" in md and ">   \\# 들여쓴 제목" in md  # 인용 + 줄머리 # 이스케이프
    assert html.count("<h2") == len(re.findall(r"^## ", md, re.M))
