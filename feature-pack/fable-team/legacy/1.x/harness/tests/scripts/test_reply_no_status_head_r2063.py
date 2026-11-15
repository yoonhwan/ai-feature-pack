"""r2063 ⑧ — `reply --ts <ts> --no-status-head` = 사람 채널이어도 카운팅 머리줄 0 · 그 밖 길은 지금 그대로.

정본 = design/harness/indices/대기/r2063-board-news-bar-floor-cardless-fold.md 계약 A6 · 반례 ⑧ · 변이 M3.
가짜 Slack(`_proposal_fakes.slack`) · 임시 루트 · 실제 Slack·실제 ~/.hermes 쓰기 0.

실행: PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest tests/scripts/test_reply_no_status_head_r2063.py -q
"""
from pathlib import Path

import pytest
from _proposal_fakes import slack  # noqa: F401 — 가짜 Slack fixture(키트 경로를 sys.path 에)
from _thread_fakes import (  # noqa: F401 — status_head_file 은 autouse fixture 로 등록된다(r1089)
    STATUS_HEAD,
    status_head_file,
)

import byz_thread_post as tp
import post_guard as pg

TS = "1794729663.977629"
BODY = "① 골 진행 확인했어요.\n둘째 줄"


@pytest.fixture
def env(slack, tmp_path, monkeypatch):  # noqa: F811
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n", encoding="utf-8")
    (tmp_path / ".fable-team").mkdir()  # 사람 채널 판정 루트(명부 0장 = env 만)
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_SLACK_STATE_DIR", str(tmp_path / "st"))
    monkeypatch.setenv("FT_SLACK_THREADS", str(tmp_path / "threads.json"))
    monkeypatch.delenv(pg.HUMAN_CHANNELS_ENV, raising=False)
    (tmp_path / "body.txt").write_text(BODY, encoding="utf-8")
    return tmp_path


def run(env: Path, slack, *argv: str) -> int:  # noqa: F811
    return tp.main([argv[0], "--ledger", str(env / "ledger.json"), "--token-file", str(env / "tok.env"), "--slack-base", slack.base, *argv[1:]])


def _posted(monkeypatch) -> list[dict]:
    calls: list[dict] = []
    monkeypatch.setattr(pg, "post", lambda base, token, channel, text, thread_ts=None: calls.append({"text": text}) or "1793.000100")
    return calls


def test_guarded_post_head_off_posts_body_as_is(monkeypatch):  # ⑧ ⓐ
    calls = _posted(monkeypatch)
    pg.guarded_post("http://x", "t", "C1", BODY, human=True, status_head=False)
    assert calls[0]["text"] == BODY and not calls[0]["text"].startswith(STATUS_HEAD)


def test_guarded_post_default_keeps_head(monkeypatch):  # ⑧ ⓑ
    calls = _posted(monkeypatch)
    pg.guarded_post("http://x", "t", "C1", BODY, human=True)
    assert calls[0]["text"] == f"{STATUS_HEAD}\n{BODY}"


def test_guarded_post_head_off_still_checks_internal_words(monkeypatch):  # ⑧ ⓒ
    calls = _posted(monkeypatch)
    with pytest.raises(pg.PostGuardError):
        pg.guarded_post("http://x", "t", "C1", "판정 1779 로 확정", human=True, status_head=False)
    assert calls == []


def test_reply_ts_no_status_head(env, slack, capsys):  # ⑧ ⓓ (기준판 = 모르는 인자 rc 2)  # noqa: F811
    assert run(env, slack, "reply", "--ts", TS, "--no-status-head", "--text-file", str(env / "body.txt")) == 0
    (m,) = slack.replies
    assert m["thread_ts"] == TS and m["text"] == BODY and STATUS_HEAD not in m["text"]
    assert capsys.readouterr().out.strip().startswith("reply ts=")


def test_reply_ts_without_flag_keeps_head(env, slack):  # ⑧ ⓔ  # noqa: F811
    assert run(env, slack, "reply", "--ts", TS, "--text-file", str(env / "body.txt")) == 0
    assert slack.replies[-1]["text"] == f"{STATUS_HEAD}\n{BODY}"


@pytest.mark.parametrize("argv", [
    ("reply", "--thread", "desk", "--no-status-head", "--text", "x"),
    ("reply", "--to-slack", TS, "--no-status-head", "--text", "x"),
    ("post", "--to", "desk", "--no-status-head", "--text", "x"),
])
def test_flag_outside_reply_ts_is_rc2(env, slack, argv):  # ⑧ ⓕ  # noqa: F811
    with pytest.raises(SystemExit) as e:
        run(env, slack, *argv)
    assert e.value.code == 2 and not slack.msgs
