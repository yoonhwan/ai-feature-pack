"""r617 — 답글 길(`--ts`·`--to-slack`)도 스레드 = 주제 대화 전용: 방 글 꼴이면 rc2 + «방 글은 post --to desk»(ⓐ~ⓔ).

정본 = design/harness/indices/진행/r617-slack-topic-thread-only-topic-replies.md §시험 입력.
가짜 Slack(`_proposal_fakes.slack`) · 임시 원장·등록부·답 기록 · 실제 Slack·실제 ~/.hermes/state 쓰기 0.

실행: PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest tests/scripts/test_thread_topic_only_replies.py -q
"""
import json
from pathlib import Path

import pytest
from _proposal_fakes import slack  # noqa: F401 — 가짜 Slack fixture(키트 경로를 sys.path 에)

import byz_thread_post as tp
import thread_reply_slack as trs

T = "1792492349.071989"  # 오빠 새 최상위 글
ROOM = "승인 묶음 (h12 · h13) — 아래를 그대로 실행\n! bash /tmp/h12"  # 방 글 꼴(승인 + h<숫자> + ! bash /tmp/h)
TOPIC = "요청 3개 중 3개 답함\n검색 결과는 어제와 같아요."  # 주제 답(방 글 꼴 아님)


@pytest.fixture
def env(slack, tmp_path, monkeypatch):  # noqa: F811
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n", encoding="utf-8")
    (tmp_path / "hermes.env").write_text("SLACK_BOT_TOKEN=xoxb-secret-2\n", encoding="utf-8")
    (tmp_path / ".fable-team").mkdir()
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_SLACK_STATE_DIR", str(tmp_path / "st"))
    monkeypatch.setenv("FT_SLACK_THREADS", str(tmp_path / "threads.json"))
    monkeypatch.delenv("FT_SLACK_TOPIC_ONLY", raising=False)  # 기본 = 켜짐
    monkeypatch.delenv("FT_SLACK_INBOUND_LEDGER", raising=False)
    monkeypatch.delenv("FT_SLACK_ANSWERED", raising=False)
    p = tmp_path / "st" / "byz_slack_mbox_inbound.C1.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps({"baseline": "0.0", "seen": {},
                             "ledger": {T: {"thread": "", "done": {"@planner": "byz-planner-desk-claude#29"},
                                            "attempt": {}, "recips": ["@planner"], "finished": True}}}), encoding="utf-8")
    slack.msgs.append({"ts": T, "text": "오빠 글 뿌리 — 3개 확인 부탁", "bot_id": "B1", "thread_ts": "", "channel": "C1"})
    return tmp_path


def run(env: Path, slack, *extra: str):  # noqa: F811
    return tp.main(["reply", "--ledger", str(env / "threads.json"), "--token-file", str(env / "tok.env"),
                    "--hermes-env", str(env / "hermes.env"), "--slack-base", slack.base, *extra])


def test_ts_room_shape_is_refused(env, slack, capsys):  # ⓐ  # noqa: F811
    assert run(env, slack, "--ts", T, "--text", ROOM) == 2
    out = capsys.readouterr()
    assert not slack.msgs[1:] and "주제 스레드엔 주제 대화만 — 방 글은 post --to desk" in out.err


def test_to_slack_room_shape_is_refused(env, slack, capsys):  # ⓑ  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--text", ROOM) == 2
    assert not slack.msgs[1:] and "방 글은 post --to desk" in capsys.readouterr().err


def test_topic_answer_still_posts(env, slack, capsys):  # ⓒ  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--text", TOPIC) == 0
    assert slack.replies[-1]["thread_ts"] == T and "reply ts=" in capsys.readouterr().out


def test_force_thread_posts_room_shape_with_warning(env, slack, capsys):  # ⓓ  # noqa: F811
    assert run(env, slack, "--ts", T, "--force-thread", "--text", ROOM) == 0
    out = capsys.readouterr()
    assert slack.replies[-1]["thread_ts"] == T and "WARN 방 글 꼴 강제 전송" in out.err


def test_topic_only_empty_env_disables_refusal(env, slack, monkeypatch):  # ⓔ  # noqa: F811
    monkeypatch.setenv("FT_SLACK_TOPIC_ONLY", "")
    assert run(env, slack, "--ts", T, "--text", ROOM) == 0
    assert slack.replies


def test_room_heads_and_room_shaped_edges():
    assert trs.room_shaped("[상태] 승인 대기") and trs.room_shaped("[뉴스] 오늘") and trs.room_shaped("[desk · 승인] x")
    assert trs.room_shaped("h12 승인 요청") and not trs.room_shaped("검색 결과는 그대로예요.")


def test_notice_lines_keep_room_post_pointer():
    import mirror_share as ms

    lines = ms.answer_hint("slack:" + T + ":byz-planner-desk-claude#29").splitlines()
    assert lines[0].startswith("답 = ") and "reply --to-slack" in lines[0]
    assert "post --to desk" in lines[1]  # 방 글(승인·뉴스·알림) 길 안내
