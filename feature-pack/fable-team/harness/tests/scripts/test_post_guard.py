"""post_guard — 게시 «전» 비밀·내부어 검사 (R205 · 설계 §5). 가짜 슬랙 API — 실제 호출 0 · 걸리면 게시 0 + rc≠0.

실행: python3 -m pytest tests/scripts/test_post_guard.py -q
"""
import pytest
from _proposal_fakes import slack  # noqa: F401 — slack fixture (키트 경로를 sys.path 에)
from _thread_fakes import card, ledger, resume_script

import byz_thread_post as tp
import post_guard as pg

UID = "feature/F-x-proposal"
SECRET = {  # 1묶음 — 패턴 이름 : 샘플
    "slack-token": "토큰은 xoxb-123 입니다", "aws-key": "key AKIAABCDEFGHIJKLMNOP", "private-key": "-----BEGIN RSA PRIVATE KEY-----",
    "sk-key": "sk-abcdefghijklmnop1234", "password": "DB Password=hunter2", "postgres-dsn": "postgresql://u@h/db", "redis-dsn": "redis://localhost:6379",
}
INTERNAL = {  # 2묶음
    "seat-name": "byz-planner-master-claude#4 에게", "abs-path": "/Users/someone/x", "worktree-path": "a/.worktrees/b",
    "cost": "비용 $12 입니다", "verdict-number": "판정 1779 로 확정",
}


@pytest.fixture(autouse=True)
def _no_human_channels(monkeypatch):
    monkeypatch.delenv(pg.HUMAN_CHANNELS_ENV, raising=False)


@pytest.fixture
def env(slack, tmp_path):  # noqa: F811
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n")
    (tmp_path / "hermes.env").write_text("SLACK_BOT_TOKEN=xoxb-secret-2\n")
    return tmp_path


def run(env, slack, cmd, *extra, channel="C1", card_path=None):  # noqa: F811
    argv = [cmd, "--ledger", str(env / "threads.json"), "--token-file", str(env / "tok.env"), "--hermes-env", str(env / "hermes.env"),
            "--slack-base", slack.base, "--channel", channel]
    if cmd in ("start", "progress", "result"):
        argv += ["--card", str(card_path or card(env)), "--issue", "#893", "--seat", "s#1", "--canon", "없음", "--next", "오빠 결정",
                 "--resume-script", str(resume_script(env))]
    return tp.main(argv + list(extra))


@pytest.mark.parametrize("name", sorted(SECRET))
def test_group1_sample_is_rejected_on_any_channel(name):
    with pytest.raises(pg.PostGuardError, match=f"묶음1:{name}"):
        pg.check(SECRET[name], "C-any")


@pytest.mark.parametrize("name", sorted(INTERNAL))
def test_group2_sample_is_rejected_on_human_channel(name):
    with pytest.raises(pg.PostGuardError, match=f"묶음2:{name}"):
        pg.check(INTERNAL[name], "C-any", human=True)


def test_group2_is_not_checked_on_machine_channels_but_group1_is(monkeypatch):
    for sample in INTERNAL.values():
        pg.check(sample, "C-machine")  # #byz-planner 기계 발행은 판정 번호를 쓴다 — 통과
    monkeypatch.setenv(pg.HUMAN_CHANNELS_ENV, "C-talk, C-other")
    with pytest.raises(pg.PostGuardError, match="묶음2"):
        pg.check(INTERNAL["verdict-number"], "C-talk")
    pg.check(INTERNAL["verdict-number"], "C-machine")


def test_clean_text_passes_everywhere():
    pg.check("안녕하세요. 요청을 팀에 전달했어요. https://github.com/org/repo/issues/12", "C-talk", human=True)


def test_mutation_emptying_group2_is_caught_by_the_sample_test(monkeypatch):
    monkeypatch.setattr(pg, "INTERNAL", {})
    with pytest.raises(pytest.fail.Exception):  # 샘플 검사가 «DID NOT RAISE» 로 실패해야 한다 = 변이를 잡는다
        test_group2_sample_is_rejected_on_human_channel("seat-name")


def test_error_names_the_pattern_but_never_echoes_the_text():
    with pytest.raises(pg.PostGuardError) as e:
        pg.check(SECRET["postgres-dsn"], "C1")
    assert "postgres-dsn" in str(e.value) and "u@h" not in str(e.value)


def started(env, slack):  # noqa: F811
    ledger(env)
    assert run(env, slack, "start", "--text", "발행") == 0
    return slack.roots[0]["ts"]


def reply(env, slack, text, ts, channel="C1"):  # noqa: F811
    f = env / "reply.txt"
    f.write_text(text, encoding="utf-8")
    return run(env, slack, "reply", "--ts", ts, "--text-file", str(f), channel=channel)


def test_reply_posts_one_thread_answer_without_card_or_ledger_or_files(env, slack, capsys):  # noqa: F811
    root = started(env, slack)
    before = (env / "threads.json").read_text()
    assert reply(env, slack, "확인했어요. 팀에 전달했어요.", root) == 0
    (r,) = slack.replies
    assert r["thread_ts"] == root and r["text"] == "확인했어요. 팀에 전달했어요." and not getattr(slack, "files", [])
    assert (env / "threads.json").read_text() == before and "reply ts=" in capsys.readouterr().out


@pytest.mark.parametrize("sample", [SECRET["slack-token"], INTERNAL["seat-name"], INTERNAL["cost"]])
def test_reply_rejects_secret_and_internal_words_with_zero_posts(env, slack, capsys, sample):  # noqa: F811
    root = started(env, slack)
    assert reply(env, slack, sample, root) == 1
    assert not slack.replies and len(slack.msgs) == 1  # 환경변수 없이도 reply 는 항상 사람 채널로 본다
    assert sample not in capsys.readouterr().err


def test_reply_rejects_bad_ts_and_empty_text(env, slack):  # noqa: F811
    started(env, slack)
    assert reply(env, slack, "x", "not-a-ts") == 1
    assert reply(env, slack, "   \n", "1700000000.000100") == 1 and not slack.replies


def test_start_with_a_secret_posts_nothing_and_leaves_the_card_untouched(env, slack):  # noqa: F811
    ledger(env)
    before = card(env).read_text(encoding="utf-8")
    assert run(env, slack, "start", "--text", SECRET["redis-dsn"]) == 1
    assert slack.msgs == [] and card(env).read_text(encoding="utf-8") == before  # 「시도」 줄도 안 남는다


def test_progress_and_update_are_guarded_too(env, slack, tmp_path):  # noqa: F811
    started(env, slack)
    assert run(env, slack, "progress", "--text", SECRET["aws-key"]) == 1 and not slack.replies
    f = tmp_path / "board.md"
    f.write_text(SECRET["private-key"], encoding="utf-8")
    assert run(env, slack, "update", "--key", "board:2026-10-15", "--text-file", str(f)) == 1 and len(slack.msgs) == 1


def test_start_on_a_configured_human_channel_rejects_verdict_numbers(env, slack, monkeypatch):  # noqa: F811
    ledger(env)
    monkeypatch.setenv(pg.HUMAN_CHANNELS_ENV, "C1")
    assert run(env, slack, "start", "--text", INTERNAL["verdict-number"]) == 1 and slack.msgs == []
    monkeypatch.delenv(pg.HUMAN_CHANNELS_ENV)
    assert run(env, slack, "start", "--text", INTERNAL["verdict-number"]) == 0  # 기계 채널은 통과


# ── R231a 교정 3 H2 — 명부 `_slack_channel` 타입 검증(손상 = 게시 0 · 키 없음 = 정상) ──


def _roster(tmp_path, monkeypatch, body):
    d = tmp_path / ".fable-team"
    d.mkdir()
    (d / "seats-x.json").write_text(body, encoding="utf-8")
    monkeypatch.setenv(pg.ROOT_ENV, str(tmp_path))


@pytest.mark.parametrize("body, want", [
    ('{"_slack_channel": "C1"}', {"C1"}), ('{"_slack_channel": ["C1", "C2"]}', {"C1", "C2"}), ('{"_master": "m#1"}', set()),
])
def test_roster_channel_field_valid_shapes(tmp_path, monkeypatch, body, want):
    _roster(tmp_path, monkeypatch, body)
    assert pg.human_channels() == want


@pytest.mark.parametrize("body", [
    '{"_slack_channel": {"channel": "C1"}}', '{"_slack_channel": 7}', '{"_slack_channel": null}', '{"_slack_channel": ""}',
    '{"_slack_channel": []}', '{"_slack_channel": ["C1", 3]}', '{"_slack_channel": ["C1", ""]}', '["C1"]', '"C1"',
])
def test_roster_channel_field_malformed_raises(tmp_path, monkeypatch, body):
    _roster(tmp_path, monkeypatch, body)
    with pytest.raises(pg.PostGuardError, match="사람 채널 판정 불가"):
        pg.human_channels()
