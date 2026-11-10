"""설계 §9 시험 5 — 본문 틀 순서 · 각주표 완전성 · html 중화. 네트워크 0.

실행: python3 -m pytest tests/scripts/test_magazine_render.py -q
"""
import re

import pytest
from _magazine_fakes import fake_model

import magazine_render as mr

LINES = ["main 에 두 건이 들어갔어요", "이슈는 하나 열렸어요", "오빠가 할 일은 하나예요"]


def render() -> tuple[str, str]:
    return mr.render(fake_model(), LINES, "2026-10-08 08:00 KST")


def test_section_order_md_and_html_identical():
    md, html = render()
    heads = ["# 아침 매거진", "## 결론", "## 오빠 할 일", "## 바뀐 것", "## 근거", "## 각주표"]
    pos = [md.index(h) for h in heads]
    assert pos == sorted(pos)
    tags = [html.index(t) for t in ["<h1>", ">결론<", ">오빠 할 일<", ">바뀐 것<", ">근거<", ">각주표<"]]
    assert tags == sorted(tags)
    # 같은 블록 목록에서 나와 소제목 순서가 같다
    md_h = [m for m in re.findall(r"^#{1,3} (.+)$", md, re.M)]
    html_h = re.findall(r"<h[123]>(.+?)</h[123]>", html)
    assert md_h == html_h


def test_every_body_number_is_in_footnote_table():
    md, _ = render()
    body, table = md.split("## 각주표")
    in_body = set(mr.REF.findall(body))
    in_table = set(re.findall(r"\| #(\d+) \|", table))
    assert in_body and in_body <= in_table
    assert {"883", "884", "885", "880"} <= in_table
    assert "| 883 |" not in table and "| #883 | PR |" in table and "| #885 | Issue |" in table


def test_free_text_numbers_become_plain_words_not_refs():
    md, _ = render()
    assert "12번" in md and "77번" in md  # 제목·HIL 줄 속 #N → N번
    assert not mr.REF.search(md.replace("(#883)", "").replace("(#884)", "").split("## 각주표")[0].replace("#885 ", "").replace("#880 ", ""))
    assert "byz-harness-master-claude#12" in md  # 좌석명 #N 은 번호 표기가 아니다


def test_number_missing_from_footnotes_raises():
    with pytest.raises(mr.RenderError, match="#99"):
        mr.check_footnotes("본문에 #99 가 있어요", {1: ("PR", "t", "병합됨")})
    mr.check_footnotes("seat#12 와 12번", {})  # 좌석명·N번은 통과


def test_html_neutralizes_markup_and_mentions():
    md, html = render()
    assert "<script>" not in html and "&lt;script&gt;" in html
    assert "<@U1>" not in html and "&lt;@U1&gt;" in html
    assert "<script>" in md  # md 는 데이터를 그대로 싣는다(설계 §1)


def test_missing_model_key_and_empty_state():
    m = fake_model()
    del m["seats"]
    with pytest.raises(mr.RenderError, match="seats"):
        mr.render(m, LINES, "t")
    empty = fake_model()
    for k in ("merges", "issues_opened", "issues_closed", "verdicts", "docs"):
        empty[k] = []
    empty["mbox"] = {"total": 0, "bad_lines": 3, "by_team": {}, "hil": []}
    md, _ = mr.render(empty, LINES, "t")
    assert "유효 줄에서 판정 0건 · 깨진 줄 3건" in md and "## 오빠 할 일\n\n없어요" in md


def test_hil_cap_and_skipped_days():
    m = fake_model()
    m["mbox"]["hil"] = [f"질문 {i}" for i in range(11)]
    m["skipped_days"] = ["2026-10-07"]
    md, _ = mr.render(m, LINES, "t")
    assert "질문 7" in md and "질문 8" not in md and "외 3건" in md
    assert "건너뛴 날: 2026-10-07" in md


def test_seats_grouped_by_team_with_cap():
    m = fake_model()
    m["seats"] = {
        "succession": [[f"byz-v65-nano-x{i}#0", f"byz-v65-nano-x{i}#1"] for i in range(47)],
        "new": [f"byz-harness-nano-y{i}#0" for i in range(77)],
    }
    md, _ = mr.render(m, LINES, "t")
    assert "승계 47건 · 신규 77석" in md and "| v65 | 47 | 0 |" in md and "| harness | 0 | 77 |" in md
    assert md.count("(승계)") == mr.SEAT_MAX and "나머지 42건 생략" in md


def test_hil_header_line_and_more_note():
    m = fake_model()
    md = mr.render(m, LINES, "t")[0]
    assert "요청 3건 중 답이 안 간 1건 — planner 가 그 좌석에 회신한 것은 뺐어요" in md and "외 " not in md.split("## 바뀐 것")[0]
    m["mbox"]["hil_asked"], m["mbox"]["hil"] = 45, [f"질문 {i}" for i in range(9)]
    top = mr.render(m, LINES, "t")[0].split("## 바뀐 것")[0]
    assert "요청 45건 중 답이 안 간 9건" in top and top.count("- 질문 ") == 8 and "외 1건" in top
