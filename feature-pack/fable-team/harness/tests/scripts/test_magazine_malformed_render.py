"""판정 602 — 형식 미달 카드 경고: 첫 화면(목차 뒤) · 슬랙 뿌리 글 · 부록 h3. malformed 0 이면 세 곳 모두 기존 출력과 같다.

실행: python3 -m pytest tests/scripts/test_magazine_malformed_render.py -q
"""
import json
import sys

import pytest
from _magazine_detail_fixture import fake_eli5, fake_full_model, fake_pdf
from _magazine_fakes import SUMMARY_OK, FakeMagazineSlack
from _thread_fakes import ledger, resume_script, seats

import byz_morning_magazine as cli
import magazine_render_full as mrf
from magazine_slack import root_text

LINES = ["한 줄", "두 줄", "세 줄"]
BAD = [{"path": "design/cfo/indices/완성/old-a.md", "team": "cfo", "missing": ["상태", "골좌표"], "moved_sha": "a" * 40, "ref": "main"},
       {"path": "design/cfo/indices/완성/old-b.md", "team": "cfo", "missing": ["배경"], "moved_sha": "b" * 40, "ref": "main"}]
LINE = "⚠ 형식 미달 카드 2장: design/cfo/indices/완성/old-a.md · design/cfo/indices/완성/old-b.md"


@pytest.fixture
def slack_env(tmp_path, monkeypatch):
    slack = FakeMagazineSlack()
    (tmp_path / "model.json").write_text(json.dumps(fake_full_model()), encoding="utf-8")
    (tmp_path / "sum.py").write_text(SUMMARY_OK, encoding="utf-8")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n")
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf())
    monkeypatch.setitem(sys.modules, "magazine_eli5", fake_eli5())
    return ["--model-file", str(tmp_path / "model.json"), "--summary-cmd", f"python3 {tmp_path / 'sum.py'}", "--out-dir", str(tmp_path / "out"),
            "--state", str(tmp_path / "state.json"), "--token-file", str(tmp_path / "tok"), "--slack-base", slack.base, "--channel", "C1",
            "--ledger", str(ledger(tmp_path)), "--seats-file", str(seats(tmp_path)), "--resume-script", str(resume_script(tmp_path))], tmp_path


def model_with(malformed):
    m = fake_full_model()
    m["detail"]["malformed"] = malformed
    return m


def test_first_screen_line_sits_between_toc_and_part1_first_section():
    md, html = mrf.render_full(model_with(BAD), LINES, "t")
    after_toc = md.split("## 목차", 1)[1]
    assert after_toc.index(LINE) < after_toc.index("\n## ") and md.count(LINE) == 1 and LINE in html


def test_appendix_starts_with_h3_and_one_line_per_card_with_all_paths():
    md, _ = mrf.render_full(model_with(BAD), LINES, "t")
    appendix = md.split("## 부록", 1)[1]
    assert appendix.index("### 형식 미달 카드 2장") < appendix.index("### design/harness/BRIEFING")
    assert "cfo · design/cfo/indices/완성/old-a.md · 빠진 절: 상태, 골좌표" in appendix and "cfo · design/cfo/indices/완성/old-b.md · 빠진 절: 배경" in appendix


def test_root_text_has_the_line_apart_from_the_easy_edition_warning():
    text = root_text("2026-10-09", LINES, None, 0, "U1", "쉬운 판(HTML) 못 만들었어요 — x", None, None, LINE)
    rows = text.split("\n")
    assert LINE in rows and rows.index(LINE) == rows.index("쉬운 판(HTML) 못 만들었어요 — x") + 1


def test_zero_malformed_leaves_all_three_places_unchanged():
    md, html = mrf.render_full(model_with([]), LINES, "t")
    assert "형식 미달" not in md and "형식 미달" not in html
    assert root_text("2026-10-09", LINES, None, 0, "U1") == root_text("2026-10-09", LINES, None, 0, "U1", None, None, None, None)
    assert "형식 미달" not in root_text("2026-10-09", LINES, None, 0, "U1")


def test_cli_dry_run_root_post_carries_the_line(slack_env, capsys):
    base, tmp = slack_env
    (tmp / "model.json").write_text(json.dumps(model_with(BAD)), encoding="utf-8")
    assert cli.main([*base, "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert LINE in out.split("--- 슬랙 뿌리 글 ---")[1] and LINE in (tmp / "out" / "MAGAZINE-20261008.md").read_text(encoding="utf-8")

