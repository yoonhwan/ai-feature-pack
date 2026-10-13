"""r117 magazine_doc CLI — dry-run HTML 조립 · 쉬운 요약 실패 표시 · 게시 1회(뿌리 글 + HTML 1개) · 같은 sha 재실행 skip. 가짜 hermes·가짜 Slack.

실행: python3 -m pytest tests/scripts/test_magazine_doc_cli.py -q
"""
import json
import logging

import pytest
from _magazine_fakes import FakeMagazineSlack, git  # 같은 import 로 slack-mirror 경로도 올라온다
from test_magazine_doc import SRC

import magazine_doc as md
import magazine_hermes as mh

TITLE = "매거진 2026-10-13 · 오빠 확인판"


def fake_fetch(mode: str = "ok"):
    def fetch(url: str, body: bytes, timeout: float) -> bytes:
        text = "이슈 #1 입니다" if mode == "numbered" else "지금은 쉬는 중이고 곧 이어서 해요."
        return json.dumps({"content": [{"type": "text", "text": text}], "stop_reason": "end_turn", "usage": {"input_tokens": 700}}).encode()
    return fetch


@pytest.fixture(autouse=True)
def proxy(monkeypatch):
    monkeypatch.setattr(mh, "_fetch", fake_fetch())


@pytest.fixture
def env(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    for k, v in (("user.email", "t@t"), ("user.name", "t")):
        git(repo, "config", k, v)
    (repo / "doc.md").write_text(SRC, encoding="utf-8")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "doc")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-test\n", encoding="utf-8")
    return tmp_path, repo


def argv(env, mode: str, slack: FakeMagazineSlack | None = None) -> list[str]:
    tmp, repo = env
    base = ["--src-repo", str(repo), "--src-sha", "HEAD", "--src-path", "doc.md", "--out-dir", str(tmp / "out"), "--proxy-url", "http://proxy.test", mode]
    if slack:
        base += ["--state", str(tmp / "state.json"), "--token-file", str(tmp / "tok"), "--slack-base", slack.base, "--channel", "C1"]
    return base


def test_dry_run_builds_html_without_slack_or_state(env, capsys):
    assert md.main(argv(env, "--dry-run")) == 0
    out = capsys.readouterr().out
    page = next((env[0] / "out").glob("MAGAZINE-DOC-2026-10-13-*.html")).read_text(encoding="utf-8")
    assert "DRY-RUN calls=9" in out and "failed=0" in out and TITLE in out
    assert page.count('<section id="c') == 5 and page.count('<details class="row"') == 4
    assert page.count("지금은 쉬는 중이고 곧 이어서 해요.") == 9
    assert page.count("<tr><td>") == 2 and page.count("<li>") == 14
    assert "&lt;b&gt;x&lt;/b&gt;" in page and "{{" not in page
    assert not (env[0] / "state.json").exists()


def test_failed_summary_marked_but_body_kept(env, monkeypatch, caplog):
    monkeypatch.setattr(mh, "_fetch", fake_fetch("numbered"))
    with caplog.at_level(logging.ERROR, logger="magazine_hermes"):
        assert md.main(argv(env, "--dry-run")) == 0
    page = next((env[0] / "out").glob("*.html")).read_text(encoding="utf-8")
    assert page.count("쉬운 요약 실패(번호·해시·경로가 섞인 답)") == 9
    assert "교정 해결" in page and "크레딧 만료 코드 - 진행" in page  # 본문은 그대로
    assert sum(r.levelno == logging.ERROR for r in caplog.records) == 9


def test_publish_posts_one_root_and_one_html_then_skips(env, capsys):
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 0
    assert [m["text"].splitlines()[0] for m in slack.roots] == [TITLE]
    ts = slack.roots[0]["ts"]
    html_file = next((env[0] / "out").glob("*.html"))
    assert slack.titles(ts) == [TITLE] and slack.content_types == ["text/html"] and slack.uploads == [html_file.read_bytes()]
    capsys.readouterr()
    assert md.main(argv(env, "--publish", slack)) == 0
    assert "skip" in capsys.readouterr().out
    assert len(slack.roots) == 1 and slack.upload_url_calls == 1


def test_upload_failure_keeps_root_and_rerun_does_not_repost(env):
    slack = FakeMagazineSlack()
    slack.fail_complete = True
    assert md.main(argv(env, "--publish", slack)) == 1
    slack.fail_complete = False
    assert md.main(argv(env, "--publish", slack)) == 0
    assert len(slack.roots) == 1 and slack.titles(slack.roots[0]["ts"]) == [TITLE]


def test_missing_date_in_title_fails(env, tmp_path):
    repo = env[1]
    (repo / "doc.md").write_text(SRC.replace("(2026-10-13 11:4x · planner 정리)", "(날짜 없음)"), encoding="utf-8")
    git(repo, "commit", "-qam", "no date")
    assert md.main(argv(env, "--dry-run")) == 1
