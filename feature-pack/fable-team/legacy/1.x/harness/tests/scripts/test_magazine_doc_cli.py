"""r117 magazine_doc CLI — dry-run HTML 조립 · 게시 1회(뿌리 글 + HTML 1개) · 같은 sha 재실행 skip · 날짜 없음 거절. 가짜 Slack · 외부 호출 0 (R259 — 쉬운 말 호출 제거).

실행: python3 -m pytest tests/scripts/test_magazine_doc_cli.py -q
"""
import pytest
from _magazine_fakes import FakeMagazineSlack
from _magazine_ledger import GOOD, argv, make_env, page_of

import magazine_doc as md

TITLE = "매거진 2026-10-16 · 오빠 확인판"


@pytest.fixture
def env(tmp_path):
    return make_env(tmp_path)


def test_dry_run_builds_html_without_slack_or_state(env, capsys):
    assert md.main(argv(env, "--dry-run")) == 0
    out = capsys.readouterr().out
    page = page_of(env)
    assert "DRY-RUN warn=0" in out and TITLE in out and "SLACK 링크 없음(드라이런)" in out
    assert "{{" not in page and page.count("<tr><td>") >= 6 and page.count("<li>") == 7  # 할 일 5 + 드러난 문제 2
    assert not (env[0] / "state.json").exists()


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


def test_missing_date_in_title_and_arg_fails(env):
    args = argv(env, "--dry-run")
    i = args.index("--date")
    assert md.main(args[:i] + args[i + 2:]) == 1  # 제목에 날짜가 없는 원장 — --date 가 없으면 DocError
    assert GOOD.splitlines()[0].count("2026") == 0
