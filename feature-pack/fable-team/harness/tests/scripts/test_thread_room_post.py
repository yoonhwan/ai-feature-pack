"""r561 — 스레드는 주제 대화 전용: 방 글 `post`(ⓐⓑ) · `--thread desk` 거절(ⓒⓓⓔ) · 쪽지 끝 방 글 안내(ⓕ) · 기존 길 불변(ⓖ).

정본 = design/harness/indices/진행/r561-desk-room-post-vs-topic-thread.md §시험 입력.
가짜 Slack(`_proposal_fakes.slack`) · 임시 원장·등록부·답 기록 · 실제 Slack·실제 ~/.hermes/state 쓰기 0.

실행: PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest tests/scripts/test_thread_room_post.py -q
"""
import json
from datetime import datetime
from pathlib import Path

import pytest
from _proposal_fakes import slack  # noqa: F401 — 가짜 Slack fixture(키트 경로를 sys.path 에)

import byz_thread_post as tp
import mirror_inbound as ib
import thread_post_args as pa
import thread_post_update as tpu

DESK_CH = "C9DESK"
T = "1792492349.071989"  # 오빠 새 최상위 글
SEAT = "byz-planner-desk-claude#29"


@pytest.fixture
def env(slack, tmp_path, monkeypatch):  # noqa: F811
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n", encoding="utf-8")
    (tmp_path / ".fable-team").mkdir()  # post_guard 사람 채널 판정 루트(명부 0장 = env 만)
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_SLACK_STATE_DIR", str(tmp_path / "st"))
    monkeypatch.setenv("FT_SLACK_THREADS", str(tmp_path / "threads.json"))
    monkeypatch.delenv("FT_SLACK_TOPIC_ONLY", raising=False)
    today = datetime.now(tpu.KST).date().isoformat()  # 도구와 같은 «오늘» 식(thread_post_update.named_root)
    (tmp_path / "threads.json").write_text(json.dumps({"desk": {"channel": DESK_CH, "root_ts": "1792422462.316339", "date": today}}), encoding="utf-8")
    return tmp_path


def run(env: Path, slack, *argv: str):  # noqa: F811
    return tp.main([argv[0], "--ledger", str(env / "ledger.json"), "--token-file", str(env / "tok.env"), "--slack-base", slack.base, *argv[1:]])


def body(env: Path, text: str = "승인 알림: r561 설치 승인 요청") -> str:
    p = env / "body.txt"
    p.write_text(text, encoding="utf-8")
    return str(p)


def entry(thread: str = "") -> dict:
    return {"thread": thread, "done": {"@planner": SEAT}, "attempt": {"@planner": [SEAT]}, "recips": ["@planner"], "finished": True}


def inbound(env: Path, entries: dict) -> None:
    p = env / "st" / f"byz_slack_mbox_inbound.{DESK_CH}.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps({"baseline": "0.0", "seen": {}, "ledger": entries}), encoding="utf-8")


def test_post_to_name_writes_room_post_without_thread_ts(env, slack, capsys):  # ⓐ  # noqa: F811
    assert run(env, slack, "post", "--to", "desk", "--text", "승인 알림 1건") == 0
    (m,) = slack.msgs
    assert m["channel"] == DESK_CH and m["thread_ts"] == "" and m["text"] == "승인 알림 1건"
    assert capsys.readouterr().out.strip() == f"POSTED {m['ts']}"
    assert not (env / "st" / "byz_slack_answered.json").exists()  # 답 기록 쓰기 0
    assert json.loads((env / "threads.json").read_text())["desk"]["root_ts"] == "1792422462.316339"  # 등록부 불변


def test_post_channel_direct_and_unknown_name_rejected(env, slack, capsys):  # ⓑ  # noqa: F811
    assert run(env, slack, "post", "--channel", "COTHER", "--text-file", body(env)) == 0
    assert slack.msgs[-1]["channel"] == "COTHER" and slack.msgs[-1]["thread_ts"] == ""
    n = len(slack.msgs)
    assert run(env, slack, "post", "--to", "ops", "--text", "x") == 1
    assert "등록부에 없는 이름" in capsys.readouterr().err and len(slack.msgs) == n
    assert pa.parse(["post", "--to", "desk", "--text", "x"]).to == "desk"
    with pytest.raises(SystemExit):
        pa.parse(["post", "--to", "desk", "--channel", "C1", "--text", "x"])
    with pytest.raises(SystemExit):
        pa.parse(["post", "--to", "desk"])
    with pytest.raises(SystemExit):
        pa.parse(["post", "--to", "desk", "--text", "x", "--text-file", "f"])


def test_thread_desk_rejected_even_when_nothing_unanswered(env, slack, capsys):  # ⓒ  # noqa: F811
    inbound(env, {})  # 답 안 된 오빠 글 0 — r558 규칙으로는 통과하던 자리
    assert run(env, slack, "reply", "--thread", "desk", "--channel", DESK_CH, "--text-file", body(env)) == 1
    err = capsys.readouterr().err
    assert not slack.msgs and "REJECT --thread desk" in err
    assert "주제 대화 전용" in err and "post --to desk" in err and "reply --to-slack" in err


def test_thread_desk_force_sends_with_warning(env, slack, capsys):  # ⓓ  # noqa: F811
    inbound(env, {})
    assert run(env, slack, "reply", "--thread", "desk", "--channel", DESK_CH, "--force-thread", "--text-file", body(env)) == 0
    out = capsys.readouterr()
    assert slack.replies and slack.replies[-1]["thread_ts"] == "1792422462.316339"
    assert "WARN --thread desk 강제 전송" in out.err


def test_topic_only_empty_env_keeps_old_behavior(env, slack, monkeypatch):  # ⓔ  # noqa: F811
    monkeypatch.setenv("FT_SLACK_TOPIC_ONLY", "")  # 끄기 = r558 거절만
    inbound(env, {})
    assert run(env, slack, "reply", "--thread", "desk", "--channel", DESK_CH, "--text-file", body(env)) == 0
    assert slack.replies
    monkeypatch.setenv("FT_SLACK_TOPIC_ONLY", "desk,ops")
    assert run(env, slack, "reply", "--thread", "ops", "--channel", DESK_CH, "--text-file", body(env)) == 1


def test_notice_ends_with_answer_then_room_post_line(env, slack, tmp_path, monkeypatch):  # ⓕ  # noqa: F811
    comm = tmp_path / "comm"
    comm.mkdir()
    mbox = comm / "mbox.sh"
    mbox.write_text((Path(__file__).parent / "_fake_mbox.sh").read_text(encoding="utf-8"), encoding="utf-8")
    monkeypatch.setenv("FAKE_MBOX", str(mbox))
    e = {"text": "오빠 새 글 (Slack) — 원문:\n안녕", "done": {}, "attempt": {}}
    ib.attempt_send(e, SEAT, SEAT, 0, f"slack:{T}:{SEAT}", type("A", (), {"mbox": str(mbox), "to_key": ""})(),
                    comm / "spool", str(tmp_path / "seats.json"), lambda: None)
    lines = json.loads((comm / "mailbox.jsonl").read_text(encoding="utf-8").splitlines()[0])["body"].splitlines()
    assert lines[-2] == f'답 = python3 ~/.hermes/scripts/byz_thread_post.py reply --to-slack {T} --text "…"'
    assert lines[-1] == '방 글(승인·뉴스·알림) = python3 ~/.hermes/scripts/byz_thread_post.py post --to desk --text "…"'
    assert lines[-3] == f"(slack:{T}:{SEAT})"  # 출처 토큰 줄 불변


def test_existing_paths_unchanged(env, slack, capsys):  # ⓖ  # noqa: F811
    inbound(env, {T: entry()})
    # r585: 답 도구가 게시 전에 오빠 글 뿌리를 읽는다 — r661: 셈은 인자(본문에 머리말 없음)
    slack.msgs.append({"ts": T, "text": "오빠 글 뿌리 — 3개 확인 부탁", "bot_id": "B1", "thread_ts": "", "channel": DESK_CH})
    assert run(env, slack, "reply", "--to-slack", T, "--asked", "3", "--answered", "3", "--text", "확인했어요.") == 0
    assert slack.replies[-1]["thread_ts"] == T
    assert run(env, slack, "reply", "--ts", "1700000000.000100", "--text", "옛 길") == 0
    assert slack.replies[-1]["thread_ts"] == "1700000000.000100"
    assert "reply ts=" in capsys.readouterr().out
    ledger = env / "ledger.json"
    before = ledger.read_text(encoding="utf-8") if ledger.exists() else ""
    assert run(env, slack, "post", "--to", "desk", "--text", "방 글") == 0
    assert (ledger.read_text(encoding="utf-8") if ledger.exists() else "") == before  # post 는 장부를 안 쓴다


def test_topic_only_defaults_to_desk():
    import thread_reply_slack as trs

    assert trs.topic_only() == {"desk"}
