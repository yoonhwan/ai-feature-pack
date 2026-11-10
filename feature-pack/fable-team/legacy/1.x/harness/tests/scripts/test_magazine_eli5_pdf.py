"""쉬운 판 PDF 변환·업로드 배선 (판정 609 설계 1) — 쉬운 판은 PDF 로 붙고 HTML 은 out 폴더에만 남는다 · 변환 실패는 쉬운 판 실패 경로. 가짜 Slack 만."""
import json
import logging
import sys

import pytest
from _magazine_detail_fixture import fake_eli5, fake_full_model, fake_pdf
from _magazine_fakes import SUMMARY_OK, FakeMagazineSlack
from _thread_fakes import ledger, resume_script, seats

import byz_morning_magazine as cli
from magazine_attach import file_title
from magazine_pdf import PdfError

DATE = "2026-10-08"
PDF_NEW, HTML_NEW, APPENDIX_NEW = (file_title(DATE, k, "r0") for k in ("pdf", "html", "md"))


@pytest.fixture
def slack() -> FakeMagazineSlack:
    return FakeMagazineSlack()


@pytest.fixture
def env(slack, tmp_path, monkeypatch):
    (tmp_path / "model.json").write_text(json.dumps(fake_full_model()), encoding="utf-8")
    (tmp_path / "sum.py").write_text(SUMMARY_OK, encoding="utf-8")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n")
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf())
    monkeypatch.setitem(sys.modules, "magazine_eli5", fake_eli5())
    return ["--model-file", str(tmp_path / "model.json"), "--summary-cmd", f"python3 {tmp_path / 'sum.py'}", "--out-dir", str(tmp_path / "out"),
            "--state", str(tmp_path / "state.json"), "--token-file", str(tmp_path / "tok"), "--slack-base", slack.base, "--channel", "C1",
            "--ledger", str(ledger(tmp_path)), "--seats-file", str(seats(tmp_path)), "--resume-script", str(resume_script(tmp_path)),
            "--date", DATE, "--no-push"], tmp_path


def test_cli_writes_easy_pdf_next_to_html_and_uploads_only_pdfs(env, slack):
    base, tmp = env
    assert cli.main(base) == 0
    out = tmp / "out"
    assert (out / "MAGAZINE-20261008-eli5.html").exists() and (out / "MAGAZINE-20261008-eli5.pdf").read_bytes() == b"%PDF-fake"
    root = slack.roots[0]
    assert slack.titles(root["ts"]) == [PDF_NEW, HTML_NEW, APPENDIX_NEW] and slack.content_types == ["application/pdf"] * 2 + ["text/markdown"]
    assert "쉬운 판 PDF(먼저 보세요)·풀 디테일 PDF" in root["text"] and "오빠가 내린 결정 0건 · 기다리는 결정 1건 — 쉬운 판 첫 장" in root["text"]


def test_cli_passes_the_summary_lines_to_the_easy_edition(env, monkeypatch):
    base, _ = env
    seen = []
    mod = fake_eli5()
    mod.build = lambda model, notes, cmd, lines=(): seen.append(list(lines)) or "<html>쉬운 판</html>"
    monkeypatch.setitem(sys.modules, "magazine_eli5", mod)
    assert cli.main(base) == 0
    assert seen == [["main 에 두 건이 들어갔어요", "이슈는 하나 열렸어요", "오빠가 할 일은 하나예요"]]


def test_easy_pdf_failure_is_a_visible_easy_edition_failure_and_full_pdf_still_goes(env, slack, monkeypatch, caplog):
    base, tmp = env
    ok = fake_pdf()

    def convert(html, pdf, *a, **k):
        if "eli5" in html.name:
            raise PdfError("PDF 생성 실패: 변환기 죽음")
        return ok(html, pdf, *a, **k)
    monkeypatch.setattr(cli, "html_to_pdf", convert)
    with caplog.at_level(logging.ERROR, logger="byz_morning_magazine"):
        assert cli.main(base) == 0
    root = slack.roots[0]
    assert slack.titles(root["ts"]) == [PDF_NEW, APPENDIX_NEW] and "쉬운 판(HTML) 못 만들었어요 — PDF 생성 실패: 변환기 죽음" in root["text"]
    assert "오빠가 내린 결정" not in root["text"] and any("쉬운 판 PDF 변환 실패" in r.message for r in caplog.records)
    assert (tmp / "out" / "MAGAZINE-20261008-eli5.html").exists()
