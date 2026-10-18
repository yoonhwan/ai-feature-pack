"""byz_thread_post `attach` — 보드 뿌리 글 스레드에 시트 PDF(+md) 첨부, 첫 파일 링크 출력 (S2 r-sheet-publish). 가짜 Slack 만 · 실 호출 0."""
import pytest
from _magazine_fakes import FakeMagazineSlack
from _thread_fakes import card, ledger, resume_script

import byz_thread_post as tp

KEY = "board:2026-10-12"


@pytest.fixture
def env(tmp_path):
    slack = FakeMagazineSlack()
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n")
    (tmp_path / "root.txt").write_text("시트 뿌리\n", encoding="utf-8")
    common = ["--channel", "C1", "--ledger", str(ledger(tmp_path)), "--token-file", str(tmp_path / "tok"), "--slack-base", slack.base]
    return slack, common, tmp_path


def test_attach_uploads_files_into_root_thread_and_prints_first_link(env, capsys):
    slack, common, tmp = env
    assert tp.main(["update", "--key", KEY, "--text-file", str(tmp / "root.txt"), *common]) == 0
    (tmp / "a.pdf").write_bytes(b"%PDF-x")
    (tmp / "a.md").write_text("# 시트\n", encoding="utf-8")
    capsys.readouterr()
    assert tp.main(["attach", "--key", KEY, "--file", str(tmp / "a.pdf"), "--file", str(tmp / "a.md"), "--title", "시트 rev R", *common]) == 0
    assert capsys.readouterr().out.strip() == "link=https://slack.test/files/F1 ts=F1"
    root_ts = slack.roots[0]["ts"]
    assert slack.titles(root_ts) == ["시트 rev R", "시트 rev R (a.md)"] and slack.content_types == ["application/pdf", "text/markdown"]


def test_attach_without_root_raises_and_uploads_nothing(env, capsys):
    slack, common, tmp = env
    (tmp / "a.pdf").write_bytes(b"%PDF-x")
    assert tp.main(["attach", "--key", KEY, "--file", str(tmp / "a.pdf"), "--title", "t", *common]) == 1
    assert "장부 불명" in capsys.readouterr().err and slack.upload_url_calls == 0


# ── R231a — 첨부 파일 게시 «전» 검사(file_guard): 걸리면 글·업로드·카드 «시도» 줄 모두 0 ──


def _unit(cmd, tmp, common, *extra):
    c = card(tmp)
    argv = [cmd, "--card", str(c), "--issue", "#893", "--seat", "s#1", "--canon", "없음", "--next", "오빠 결정",
            "--resume-script", str(resume_script(tmp)), "--text", "작업", *extra, *common]
    return c, tp.main(argv)


def test_start_with_secret_md_posts_nothing_and_leaves_card_untouched(env, capsys):
    slack, common, tmp = env
    (tmp / "s.md").write_text("token xoxb-123\n", encoding="utf-8")
    c, rc = _unit("start", tmp, common, "--file", str(tmp / "s.md"))
    assert rc == 1 and "묶음1" in capsys.readouterr().err
    assert not slack.roots and slack.upload_url_calls == 0 and "시도" not in c.read_text(encoding="utf-8")


def test_start_with_clean_md_posts_one_root_and_one_upload(env):
    slack, common, tmp = env
    (tmp / "ok.md").write_text("정상 글\n", encoding="utf-8")
    _, rc = _unit("start", tmp, common, "--file", str(tmp / "ok.md"))
    assert rc == 0 and len(slack.roots) == 1 and slack.upload_url_calls == 1


def test_start_with_pdf_on_human_channel_posts_nothing(env, monkeypatch):
    slack, common, tmp = env
    monkeypatch.setenv("BYZ_HUMAN_CHANNELS", "C1")
    (tmp / "a.pdf").write_bytes(b"%PDF-x")
    _, rc = _unit("start", tmp, common, "--file", str(tmp / "a.pdf"))
    assert rc == 1 and not slack.roots and slack.upload_url_calls == 0


def test_progress_with_rejected_file_posts_no_text(env):
    slack, common, tmp = env
    _, rc = _unit("start", tmp, common)
    assert rc == 0 and len(slack.roots) == 1
    (tmp / "s.md").write_text("AKIAABCDEFGHIJKLMNOP\n", encoding="utf-8")
    _, rc = _unit("progress", tmp, common, "--file", str(tmp / "s.md"))
    assert rc == 1 and not slack.replies_of(slack.roots[0]["ts"]) and slack.upload_url_calls == 0


def test_board_attach_rejects_secret_md_before_upload(env, capsys):
    slack, common, tmp = env
    assert tp.main(["update", "--key", KEY, "--text-file", str(tmp / "root.txt"), *common]) == 0
    (tmp / "s.md").write_text("-----BEGIN RSA PRIVATE KEY-----\n", encoding="utf-8")
    assert tp.main(["attach", "--key", KEY, "--file", str(tmp / "s.md"), "--title", "t", *common]) == 1
    assert "묶음1" in capsys.readouterr().err and slack.upload_url_calls == 0


def test_uploaded_bytes_are_the_checked_bytes_even_if_file_changes_after_check(env, monkeypatch):
    """H3 — 검사 뒤(글 게시 시점)에 원본이 바뀌어도 올라가는 바이트 = 검사 때 바이트."""
    slack, common, tmp = env
    f = tmp / "r.md"
    f.write_text("정상 본문\n", encoding="utf-8")
    real_post = tp.post

    def swapping_post(*a, **kw):
        f.write_text("token xoxb-123\n", encoding="utf-8")
        return real_post(*a, **kw)

    monkeypatch.setattr(tp, "post", swapping_post)
    _, rc = _unit("start", tmp, common, "--file", str(f))
    assert rc == 0 and slack.uploads == ["정상 본문\n".encode()]
