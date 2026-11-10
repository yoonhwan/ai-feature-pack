"""쉬운 판 PDF 첨부 (판정 609 r2-1) — 새 제목·옛 제목 호환 · 확장자별 content-type · 뿌리 글 안내 · 쉬운 판 PDF 변환 실패 경로. 가짜 Slack 만."""
import json
import time

import pytest
from _magazine_fakes import FakeMagazineSlack

import magazine_publish as mp
import magazine_reattach as mr
from magazine_attach import AttachError, file_title, legacy_title
from magazine_slack import Target, marker, root_text

DATE = "2026-10-08"
PDF_NEW, HTML_NEW = file_title(DATE, "pdf", "r0"), file_title(DATE, "html", "r0")
PDF_OLD = legacy_title(DATE, "pdf", "r0")


@pytest.fixture
def slack() -> FakeMagazineSlack:
    return FakeMagazineSlack()


def day_of(tmp_path, easy_name="m-eli5.pdf"):
    pdf, easy = tmp_path / "m.pdf", tmp_path / easy_name
    pdf.write_bytes(b"%PDF-fake")
    easy.write_bytes(b"%PDF-easy")
    return mp.Day(DATE, f"*{marker(DATE)}*\n요약", pdf, time.time() - 3600, "sha", easy)


def tgt(slack):
    return Target(slack.base, "tok", "C1", "U1")


def stage(slack, st, title, *, sharing=True):
    """뿌리 글 + 그 스레드의 첨부 1개(제목 title) + (옛 판이 남긴) sharing 기록."""
    root = f"{time.time():.6f}"
    slack.msgs += [{"ts": root, "text": f"*{marker(DATE)}*\n요약", "bot_id": "B1", "thread_ts": ""},
                   {"ts": f"{time.time() + 1:.6f}", "text": "", "bot_id": "B1", "thread_ts": root, "files": [{"id": "F0", "title": title}]}] if title else \
                  [{"ts": root, "text": f"*{marker(DATE)}*\n요약", "bot_id": "B1", "thread_ts": ""}]
    files = {"pdf": {"file_id": "F0", "phase": "sharing", "ts": root}} if sharing else {}
    st.write_text(json.dumps({DATE: {"phase": "posted", "ts": root, "files": files}}), encoding="utf-8")
    return root


def test_a1_old_title_in_thread_is_adopted_with_zero_upload_and_html_gets_new_title(slack, tmp_path):
    st = tmp_path / "s.json"
    root = stage(slack, st, PDF_OLD)
    mp.publish_day(tgt(slack), day_of(tmp_path), st)
    assert slack.titles(root) == [PDF_OLD, HTML_NEW] and slack.upload_url_calls == 1


def test_a2_new_title_in_thread_is_adopted(slack, tmp_path):
    st = tmp_path / "s.json"
    root = stage(slack, st, PDF_NEW)
    mp.publish_day(tgt(slack), day_of(tmp_path), st)
    assert slack.titles(root) == [PDF_NEW, HTML_NEW] and slack.upload_url_calls == 1


def test_a3_no_title_with_sharing_record_is_still_unknown(slack, tmp_path):
    st = tmp_path / "s.json"
    stage(slack, st, None)
    with pytest.raises(AttachError, match="불명"):
        mp.publish_day(tgt(slack), day_of(tmp_path), st)
    assert slack.upload_url_calls == 0


def test_a4_reattach_uses_new_titles_and_pdf_bytes_for_the_easy_edition(slack, tmp_path):
    st, day = tmp_path / "s.json", day_of(tmp_path)
    mp.publish_day(tgt(slack), day, st)
    root = slack.roots[0]["ts"]
    mr.reattach(tgt(slack), day, st, "r1", mr.reply_text(DATE, "r1", None))
    assert slack.titles(root)[-2:] == [file_title(DATE, "pdf", "r1"), file_title(DATE, "html", "r1")]
    assert slack.content_types == ["application/pdf"] * 4 and slack.uploads[-1] == b"%PDF-easy"


def test_content_type_follows_the_extension_and_unknown_extension_raises(slack, tmp_path):
    day = day_of(tmp_path, "easy.html")
    mp.publish_day(tgt(slack), day, tmp_path / "s.json")
    assert slack.content_types == ["application/pdf", "text/html"]
    odd = day_of(tmp_path, "easy.zip")
    with pytest.raises(AttachError, match="확장자"):
        mp.publish_day(tgt(slack), odd, tmp_path / "s2.json", force=True)


LINES = ["main 에 두 건이 들어갔어요"]


def test_root_text_points_at_the_easy_pdf_and_states_the_decision_counts():
    text = root_text(DATE, LINES, None, 3, "U1", decided=7)
    assert "본문은 스레드의 쉬운 판 PDF(먼저 보세요)·풀 디테일 PDF" in text
    assert "오빠가 내린 결정 7건 · 기다리는 결정 3건 — 쉬운 판 첫 장" in text
    assert "오빠가 내린 결정" not in root_text(DATE, LINES, None, 3, "U1")
    assert "오빠가 내린 결정" not in root_text(DATE, LINES, None, 3, "U1", "쉬운 판(HTML) 못 만들었어요 — x", decided=7)
