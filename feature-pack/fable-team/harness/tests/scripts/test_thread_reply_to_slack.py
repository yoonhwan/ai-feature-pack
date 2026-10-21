"""r558 — desk 답이 «오빠 글 밑»으로 간다: reply --to-slack(ⓐⓑⓒ) · --thread 거절(ⓓⓔⓕ) · 쪽지 답 명령 1줄(ⓖ).

r661 — 답 본문의 «요청 N개 중 M개 답함» 머리말 제거: 셈은 --asked·--answered 인자 · 덜 답했으면 --left 1줄(아래 r661/r585 칸).

정본 = design/harness/indices/진행/r558-desk-slack-reply-goes-to-oppa-post-thread.md §시험 입력.
가짜 Slack(`_proposal_fakes.slack`) · 임시 원장·등록부·답 기록 · 실제 Slack·실제 ~/.hermes/state 쓰기 0.

실행: PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest tests/scripts/test_thread_reply_to_slack.py -q
"""
import json
import time
from pathlib import Path

import pytest
from _proposal_fakes import slack  # noqa: F401 — 가짜 Slack fixture(키트 경로를 sys.path 에)

import byz_thread_post as tp
import mirror_inbound as ib
import thread_post_args as pa

DESK = "byz-planner-desk-claude#29"
T = "1792492349.071989"  # 오빠 새 최상위 글(10-20 19:32 실측)
P = "1792422462.316339"  # 오빠 아침 최상위 글 = 스레드 뿌리
OLD = f"{time.time() - 9 * 86400:.6f}"  # 창(7일) 밖
# r585: 오빠 글 뿌리(스레드 첫 글) 원문 — 답 도구가 게시 전에 읽어 보여 준다
ROOT = "오빠 글 뿌리: r558 답 자리 · desk 슬랙 · 번역 창 크기 — 3개 확인 부탁"
ANSWER = "확인했어요. 반영했어요."  # r661: 답 본문에 «요청 N개 중 M개» 머리말을 쓰지 않는다
CNT = ("--asked", "3", "--answered", "3")  # r661: 셈은 글 아니라 인자


@pytest.fixture
def env(slack, tmp_path, monkeypatch):  # noqa: F811
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n", encoding="utf-8")
    (tmp_path / "hermes.env").write_text("SLACK_BOT_TOKEN=xoxb-secret-2\n", encoding="utf-8")
    monkeypatch.setenv("FT_SLACK_STATE_DIR", str(tmp_path / "st"))
    monkeypatch.setenv("FT_SLACK_TOPIC_ONLY", "")  # r561: 이 시험은 r558 규칙(답 안 된 글 거절)만 본다 — 주제 전용 거절은 test_thread_room_post.py
    monkeypatch.setenv("FT_SLACK_THREADS", str(tmp_path / "threads.json"))
    monkeypatch.delenv("FT_SLACK_INBOUND_LEDGER", raising=False)
    monkeypatch.delenv("FT_SLACK_ANSWERED", raising=False)
    return tmp_path


def inbound(env: Path, entries: dict) -> Path:
    p = env / "st" / "byz_slack_mbox_inbound.C1.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps({"baseline": "0.0", "seen": {}, "ledger": entries}), encoding="utf-8")
    return p


def answered(env: Path, data: dict) -> Path:
    p = env / "st" / "byz_slack_answered.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps({"answered": data}), encoding="utf-8")
    return p


def entry(thread: str = "", seat: str = DESK) -> dict:
    return {"thread": thread, "done": {"@planner": seat}, "attempt": {"@planner": [seat]}, "recips": ["@planner"], "finished": True}


def seed(slack, *ts_list: str, text: str = ROOT) -> None:  # noqa: F811 — 가짜 Slack 에 오빠 글 뿌리를 심는다(진짜 슬랙 0)
    for ts in ts_list:
        if not any(m["ts"] == ts for m in slack.msgs):
            slack.msgs.append({"ts": ts, "text": text, "bot_id": "B1", "thread_ts": "", "channel": "C1"})


def run(env: Path, slack, *extra: str, channel: str = "C1"):  # noqa: F811
    seed(slack, T, P)
    argv = ["reply", "--ledger", str(env / "threads.json"), "--token-file", str(env / "tok.env"), "--hermes-env", str(env / "hermes.env"),
            "--slack-base", slack.base, "--channel", channel, *extra]
    return tp.main(argv)


def text_file(env: Path, body: str = "확인했어요. 팀에 전달했어요.") -> str:
    p = env / "reply.txt"
    p.write_text(body, encoding="utf-8")
    return str(p)


def test_to_slack_top_level_replies_under_that_post(env, slack):  # ⓐ  # noqa: F811
    started = time.time()
    inbound(env, {T: entry()})
    assert run(env, slack, "--to-slack", T, *CNT, "--text", ANSWER) == 0
    (r,) = slack.replies
    assert r["thread_ts"] == T and r["text"] == ANSWER
    rec = json.loads((env / "st" / "byz_slack_answered.json").read_text())["answered"]
    assert rec[T] == r["ts"] and started > 0


def test_to_slack_thread_reply_answers_in_same_thread(env, slack):  # ⓑ  # noqa: F811
    inbound(env, {T: entry(thread=P)})
    seed(slack, T, P)
    before = len(slack.roots)
    assert run(env, slack, "--to-slack", T, *CNT, "--text", ANSWER) == 0
    (r,) = slack.replies
    assert r["thread_ts"] == P and len(slack.roots) == before  # 새 스레드 0


def test_to_slack_unknown_ts_is_rejected(env, slack, capsys):  # ⓒ  # noqa: F811
    inbound(env, {T: entry()})
    assert run(env, slack, "--to-slack", "1700000000.000100", *CNT, "--text", ANSWER) == 1
    assert not slack.replies and "수신 원장에 없는 오빠 글 ts" in capsys.readouterr().err


def test_thread_refuses_when_oppa_post_is_unanswered(env, slack, capsys):  # ⓓ  # noqa: F811
    inbound(env, {T: entry(seat=DESK)})
    assert run(env, slack, "--thread", "desk", "--text-file", text_file(env)) == 1
    err = capsys.readouterr().err
    assert not slack.replies and f"reply --to-slack {T}" in err


def test_thread_passes_when_nothing_is_unanswered(env, slack, capsys):  # ⓔ  # noqa: F811
    inbound(env, {T: entry(seat=DESK), OLD: entry(seat=DESK)})
    answered(env, {T: "1792492400.000000", OLD: "1792400000.000000"})  # 창 밖 글도 답 기록이 있으면 조용하다
    assert run(env, slack, "--thread", "desk", "--text-file", text_file(env)) == 0
    assert "reply ts=" in capsys.readouterr().out and slack.replies


def test_thread_force_sends_with_warning(env, slack, capsys):  # ⓕ  # noqa: F811
    inbound(env, {T: entry(seat=DESK)})
    assert run(env, slack, "--thread", "desk", "--force-thread", "--text-file", text_file(env)) == 0
    out = capsys.readouterr()
    assert slack.replies and "WARN" in out.err and f"reply --to-slack {T}" in out.err


def test_thread_window_ignores_posts_older_than_seven_days(env, slack):  # 창 밖 글은 거절 사유가 아니다  # noqa: F811
    inbound(env, {OLD: entry(seat=DESK)})
    assert run(env, slack, "--thread", "desk", "--text-file", text_file(env)) == 0


def test_thread_ignores_other_lineages(env, slack):  # ⓔ 변형 — desk 계보가 아니면 그 이름 스레드 답을 막지 않는다  # noqa: F811
    inbound(env, {T: entry(seat="byz-harness-master-claude#86")})
    assert run(env, slack, "--thread", "desk", "--text-file", text_file(env)) == 0


def test_notice_ends_with_the_answer_command(env, slack, tmp_path, monkeypatch):  # ⓖ  # noqa: F811
    comm = tmp_path / "comm"
    comm.mkdir()
    mbox = comm / "mbox.sh"
    mbox.write_text((Path(__file__).parent / "_fake_mbox.sh").read_text(encoding="utf-8"), encoding="utf-8")
    monkeypatch.setenv("FAKE_MBOX", str(mbox))
    saved: list[int] = []
    e = {"text": "오빠 새 글 (Slack) — 원문:\n안녕", "done": {}, "attempt": {}}
    ib.attempt_send(e, "byz-planner-desk-claude#29", "byz-planner-desk-claude#29", 0, f"slack:{T}:byz-planner-desk-claude#29",
                    type("A", (), {"mbox": str(mbox), "to_key": ""})(), comm / "spool", str(tmp_path / "seats.json"), lambda: saved.append(1))
    body = json.loads((comm / "mailbox.jsonl").read_text(encoding="utf-8").splitlines()[0])["body"]
    lines = body.splitlines()
    assert lines[-2] == f'답 = python3 ~/.hermes/scripts/byz_thread_post.py reply --to-slack {T} --text "…"'
    assert lines[-3] == f"(slack:{T}:byz-planner-desk-claude#29)"  # 기존 출처 토큰 줄 불변 · 중복 판정 근거


def test_r661_old_header_in_body_is_rejected_with_root_text(env, slack, capsys):  # ⓐ (r585 자리 — 이제 옛 머리말은 금지)  # noqa: F811
    inbound(env, {T: entry()})
    assert run(env, slack, "--to-slack", T, *CNT, "--text", "요청 3개 중 3개 답함\n확인했어요.") == 1
    err = capsys.readouterr().err
    assert not slack.replies  # 게시 0
    assert ROOT in err and "오빠가 빼라고 했어요" in err  # 뿌리 원문 + 사람 말


def test_r585_numbered_abbrev_lines_are_rejected(env, slack, capsys):  # ⓑ  # noqa: F811
    inbound(env, {T: entry()})
    body = "r558 반영\n#123 확인\nK4b 진행"
    assert run(env, slack, "--to-slack", T, *CNT, "--text", body) == 1
    err = capsys.readouterr().err
    assert not slack.replies and "쉬운 말로" in err and ROOT in err


def test_r661_partial_answer_needs_left_line(env, slack, capsys):  # ⓒ (r585 자리 — --left 필수)  # noqa: F811
    inbound(env, {T: entry()})
    assert run(env, slack, "--to-slack", T, "--asked", "3", "--answered", "1", "--text", "번역 창만 확인했어요.") == 1
    err = capsys.readouterr().err
    assert not slack.replies and "물어본 게 3개인데 1개만 답했어요" in err and "--left" in err


def test_r661_good_answer_posts_under_root_with_one_left_line(env, slack, capsys):  # ⓓ (r585 자리)  # noqa: F811
    inbound(env, {T: entry()})
    text = "번역 창은 확인했어요."
    assert run(env, slack, "--to-slack", T, "--asked", "3", "--answered", "2", "--left", "r558 답 자리 — 오늘 안에 볼게요.",
               "--text", text) == 0
    (r,) = slack.replies
    assert r["thread_ts"] == T and r["text"] == text + "\n아직 못 한 것: r558 답 자리 — 오늘 안에 볼게요."
    assert "reply ts=" in capsys.readouterr().out


def test_r585_root_read_failure_is_rejected(env, slack, capsys):  # ⓔ  # noqa: F811
    inbound(env, {T: entry()})
    slack.fail_replies = True
    assert run(env, slack, "--to-slack", T, *CNT, "--text", ANSWER) == 1
    assert not slack.replies and "뿌리 글 읽기 실패" in capsys.readouterr().err
    slack.fail_replies = False


def test_reply_parses_counts_as_arguments():
    a = pa.parse(["reply", "--to-slack", T, "--asked", "3", "--answered", "2", "--left", "x", "--text", "y"])
    assert (a.asked, a.answered, a.left) == (3, 2, "x")


def test_reply_requires_exactly_one_root_and_one_body():
    with pytest.raises(SystemExit):
        pa.parse(["reply", "--thread", "desk"])
    with pytest.raises(SystemExit):
        pa.parse(["reply", "--thread", "desk", "--ts", "1.2", "--text", "x"])
    with pytest.raises(SystemExit):
        pa.parse(["reply", "--thread", "desk", "--text", "x", "--text-file", "f"])
    assert pa.parse(["reply", "--to-slack", T, "--text", "x"]).to_slack == T
