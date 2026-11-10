"""R111 ② — 상세 부록 md 를 같은 스레드에 붙인다(기존 첨부 경로 재사용). 첨부 실패 = 보이는 실패.

가짜 요약·가짜 PDF·가짜 Slack. 실행: python3 -m pytest tests/scripts/test_magazine_appendix_attach.py -q
"""
import json
import sys
import time
from pathlib import Path

import pytest
from _magazine_detail_fixture import fake_eli5, fake_full_model
from _magazine_fakes import SUMMARY_OK, FakeMagazineSlack
from _thread_fakes import ledger, resume_script, seats

import byz_morning_magazine as cli
import magazine_publish as mp
import magazine_reattach as mr
from magazine_slack import Target, marker
from mirror_lib import MirrorError

DATE = "2026-10-08"
PDF_T, HTML_T, MD_T = (f"아침 매거진 {DATE} {k} r0" for k in ("풀 디테일", "쉬운 판", "상세 부록"))


@pytest.fixture
def slack() -> FakeMagazineSlack:
    return FakeMagazineSlack()


def tgt(slack: FakeMagazineSlack) -> Target:
    return Target(slack.base, "tok", "C1", "U1")


@pytest.fixture
def cli_env(slack, tmp_path, monkeypatch):
    (tmp_path / "model.json").write_text(json.dumps(fake_full_model()), encoding="utf-8")
    (tmp_path / "sum.py").write_text(SUMMARY_OK, encoding="utf-8")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n")
    seen: dict[str, str] = {}

    def convert(html, pdf_path, *_a, **_k):  # noqa: ANN001, ANN202
        seen["html"] = Path(html).read_text(encoding="utf-8")
        pdf_path.write_bytes(b"%PDF-fake")
        return 1

    monkeypatch.setattr(cli, "html_to_pdf", convert)
    monkeypatch.setitem(sys.modules, "magazine_eli5", fake_eli5())
    base = ["--model-file", str(tmp_path / "model.json"), "--summary-cmd", f"python3 {tmp_path / 'sum.py'}", "--out-dir", str(tmp_path / "out"),
            "--state", str(tmp_path / "state.json"), "--token-file", str(tmp_path / "tok"), "--slack-base", slack.base, "--channel", "C1",
            "--ledger", str(ledger(tmp_path)), "--seats-file", str(seats(tmp_path)), "--resume-script", str(resume_script(tmp_path)), "--no-push"]
    return base, tmp_path, seen


def titles(slack: FakeMagazineSlack) -> list[str]:
    return slack.titles(slack.roots[0]["ts"])


def test_p1_cli_pdf_is_summary_only_full_md_stays_and_appendix_is_attached(cli_env, slack):
    base, tmp, seen = cli_env
    assert cli.main(base) == 0
    out = tmp / "out"
    assert "상세는 부록 파일" in seen["html"] and "D1 닫힌 단위</h2>" not in seen["html"]  # PDF 원본 = 요약 절만
    assert "## D1 닫힌 단위" in (out / "MAGAZINE-20261008.md").read_text(encoding="utf-8")  # 전체 md 는 그대로(정보 손실 0)
    assert "## D1 닫힌 단위" in (out / "MAGAZINE-20261008.detail.md").read_text(encoding="utf-8")
    assert titles(slack) == [PDF_T, HTML_T, MD_T]
    assert set(json.loads((tmp / "state.json").read_text())[DATE]["files"]) == {"pdf", "html", "md"}


def test_p2_appendix_attach_failure_is_visible_and_rerun_attaches_only_it(cli_env, slack):
    base, _, _ = cli_env
    slack.fail_complete_at = {3}  # 세 번째 complete(부록) 거절
    assert cli.main(base) == 1 and titles(slack) == [PDF_T, HTML_T]  # 무음 0 — exit 1
    assert cli.main(base) == 0 and titles(slack) == [PDF_T, HTML_T, MD_T]


def make_day(tmp_path: Path) -> mp.Day:
    pdf, easy, app = tmp_path / "m.pdf", tmp_path / "m-eli5.pdf", tmp_path / "m.detail.md"
    pdf.write_bytes(b"%PDF-fake")
    easy.write_bytes(b"%PDF-easy")
    app.write_text("## D1 닫힌 단위\n", encoding="utf-8")
    return mp.Day(DATE, f"*{marker(DATE)}*\n요약", pdf, time.time() - 3600, "sha", easy, app)


def test_p3_publish_day_without_appendix_is_unchanged(slack, tmp_path):
    day = make_day(tmp_path)
    mp.publish_day(tgt(slack), mp.Day(day.date, day.text, day.pdf, day.oldest_epoch, day.md_sha, day.html), tmp_path / "s.json")
    assert titles(slack) == [PDF_T, HTML_T]


def test_p4_reattach_attaches_appendix_with_rev_title(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    mp.publish_day(tgt(slack), day, st)
    mr.reattach(tgt(slack), day, st, "r1", mr.reply_text(DATE, "r1", None))
    assert f"아침 매거진 {DATE} 상세 부록 r1" in titles(slack)


def test_p5_force_file_accepts_md_and_publish_error_type_is_kept(slack, tmp_path):
    day = make_day(tmp_path)
    slack.fail_complete_at = {3}
    with pytest.raises(MirrorError):
        mp.publish_day(tgt(slack), day, tmp_path / "s.json")
    assert cli.parse_args(["--force-file", "md"]).force_file == ["md"]
