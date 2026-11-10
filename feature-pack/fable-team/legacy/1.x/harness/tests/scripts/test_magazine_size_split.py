"""R111 ② — PDF 는 요약 절만, 상세 절(D1·D2·D3·D6·D7)은 부록 md 로 쪼갠다. 정보 손실 0 · 상한 숫자 불변.

가짜 모델·가짜 PDF 변환기만 쓴다(실 슬랙·실 LLM 0).
실행: python3 -m pytest tests/scripts/test_magazine_size_split.py -q
"""
import re

import pytest
from _magazine_detail_fixture import fake_full_model, fake_pdf

import magazine_render_cap as mrc
import magazine_render_full as mrf

LINES = ["한 줄", "두 줄", "세 줄"]
DETAIL = ["D1 닫힌 단위", "D2 판정서 절", "D3 판정(결정 원문)", "D6 열린 행", "D7 좌석"]
SUMMARY_ONLY = ["D4 main 에 들어간 것", "D5 이슈", "부록 — 브리핑·마감 문서", "각주표"]


def h2s(md: str) -> list[str]:
    return re.findall(r"^## (.+)$", md, flags=re.M)


def big_model() -> dict:
    m = fake_full_model()
    m["detail"]["units"] = [{**m["detail"]["units"][0], "path": f"design/harness/indices/완성/u{i}.md", "title": f"단위 {i}", "why": "\n".join(f"왜 {j}" for j in range(12))} for i in range(40)]
    return m


def parts(m: dict) -> tuple[str, str, str, str]:
    full, _ = mrf.render_full(m, LINES, "2026-10-13 09:00 KST")
    summary_md, summary_html, appendix_md = mrf.render_summary(m, LINES, "2026-10-13 09:00 KST")
    return full, summary_md, summary_html, appendix_md


def test_s1_summary_has_only_summary_sections_and_appendix_has_detail_in_order():
    _, summary, _, appendix = parts(big_model())
    assert all(d not in h2s(summary) for d in DETAIL) and all(s in h2s(summary) for s in SUMMARY_ONLY)
    assert [h for h in h2s(appendix) if h in DETAIL] == DETAIL  # 절 순서 그대로 · 상세 절 전부


def test_s2_summary_plus_appendix_covers_every_section_of_full_md():
    full, summary, _, appendix = parts(big_model())
    assert set(h2s(summary)) | set(h2s(appendix)) == set(h2s(full))


def test_s3_pdf_toc_points_to_appendix_file_and_has_no_dangling_detail_entries():
    _, summary, html, _ = parts(big_model())
    assert "상세는 부록 파일" in summary and "상세는 부록 파일" in html
    assert all(f"\n- {d}\n" not in summary and f'href="#{a}"' not in html for d, a in zip(DETAIL, ("d1", "d2", "d3", "d6", "d7")))


def test_s4_appendix_text_equals_full_detail_sections():
    full, _, _, appendix = parts(big_model())
    for name in DETAIL:
        body = full.split(f"## {name}")[1].split("\n## ")[0].strip()
        assert body in appendix


def test_s5_limits_unchanged_and_summary_fits_where_full_would_not(monkeypatch, tmp_path):
    assert (mrc.MD_MAX_LINES, mrc.MD_MAX_BYTES) == (1500, 120 * 1024)
    full, summary, html, _ = parts(big_model())
    assert len(summary.encode()) < len(full.encode())
    monkeypatch.setattr(mrc, "MD_MAX_BYTES", len(summary.encode()) + 1)
    html_path, pdf_path = tmp_path / "s.html", tmp_path / "s.pdf"
    html_path.write_text(html, encoding="utf-8")
    assert mrc.checked_pdf(summary, html_path, pdf_path, "t", fake_pdf(2)) == 2  # 요약은 통과
    with pytest.raises(mrc.MagazineSizeError):
        mrc.checked_pdf(full, html_path, pdf_path, "t", fake_pdf(2))  # 전체 md 였다면 지금처럼 실패


def test_s6_summary_over_cap_still_raises_visible_error(monkeypatch, tmp_path):
    _, summary, html, _ = parts(big_model())
    monkeypatch.setattr(mrc, "MD_MAX_BYTES", len(summary.encode()) - 1)
    html_path = tmp_path / "s.html"
    html_path.write_text(html, encoding="utf-8")
    with pytest.raises(mrc.MagazineSizeError, match="md 크기 초과"):
        mrc.checked_pdf(summary, html_path, tmp_path / "s.pdf", "t", fake_pdf(1))
