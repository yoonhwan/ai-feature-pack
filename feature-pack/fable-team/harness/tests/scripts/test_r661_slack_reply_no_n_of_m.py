"""r661 — 슬랙 답 첫 줄 «요청 N개 중 M개 답함» 강제 제거: 셈은 인자(--asked·--answered) · 덜 답했을 때만 끝줄 «아직 못 한 것: …»(ⓐ~ⓖ).

정본 = design/harness/indices/진행/r661-slack-reply-no-n-of-m-header.md §시험 입력.
가짜 Slack(`_proposal_fakes.slack`) · 임시 원장·답 기록 · 실제 Slack·실제 ~/.hermes/state 쓰기 0.

실행: PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest tests/scripts/test_r661_slack_reply_no_n_of_m.py -q
"""
import json
import re
from pathlib import Path

import pytest
from _proposal_fakes import slack  # noqa: F401 — 가짜 Slack fixture(키트 경로를 sys.path 에)
from _thread_fakes import (  # noqa: F401 — status_head_file 은 autouse fixture 로 등록된다(r1089)
    body_after_status_head,
    status_head_file,
)

import byz_thread_post as tp
import thread_reply_slack as trs

T = "1792492349.071989"  # 오빠 새 최상위 글
DESK = "byz-planner-desk-claude#29"
ROOT = "오빠 글 뿌리: 폰 상단 줄 · 배포 날짜 · 번역 창 — 3개 확인 부탁"
PLAIN = "말씀하신 폰 상단 줄은 안①로 고쳤어요"  # 머리말 없는 보통 답(오빠가 읽던 글)
OLD_HEAD = "요청 3개 중 2개 답함"  # 오빠가 빼라고 한 옛 머리말
LEFT = "배포 날짜는 내일 확인"
LEFT_LINE = f"아직 못 한 것: {LEFT}"
BARE_ONLY = "r558 반영\n#123 확인\nK4b 진행"  # 번호·약어만 3줄


@pytest.fixture
def env(slack, tmp_path, monkeypatch):  # noqa: F811
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n", encoding="utf-8")
    (tmp_path / "hermes.env").write_text("SLACK_BOT_TOKEN=xoxb-secret-2\n", encoding="utf-8")
    (tmp_path / ".fable-team").mkdir()
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_SLACK_STATE_DIR", str(tmp_path / "st"))
    monkeypatch.setenv("FT_SLACK_THREADS", str(tmp_path / "threads.json"))
    monkeypatch.setenv("FT_SLACK_TOPIC_ONLY", "")
    monkeypatch.delenv("FT_SLACK_INBOUND_LEDGER", raising=False)
    monkeypatch.delenv("FT_SLACK_ANSWERED", raising=False)
    p = tmp_path / "st" / "byz_slack_mbox_inbound.C1.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps({"baseline": "0.0", "seen": {}, "ledger": {T: entry()}}), encoding="utf-8")
    slack.msgs.append({"ts": T, "text": ROOT, "bot_id": "B1", "thread_ts": "", "channel": "C1"})
    return tmp_path


def entry() -> dict:
    return {"thread": "", "done": {"@planner": DESK}, "attempt": {"@planner": [DESK]}, "recips": ["@planner"], "finished": True}


def run(env: Path, slack, *extra: str):  # noqa: F811
    return tp.main(["reply", "--ledger", str(env / "threads.json"), "--token-file", str(env / "tok.env"),
                    "--hermes-env", str(env / "hermes.env"), "--slack-base", slack.base, "--channel", "C1", *extra])


def posted(slack) -> dict:  # noqa: F811 — 게시된 답글 1개
    assert len(slack.replies) == 1
    return slack.replies[0]


def test_a_plain_answer_with_counts_is_posted_as_is(env, slack, capsys):  # ⓐ (지금 판 = REJECT → FAIL)  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--asked", "1", "--answered", "1", "--text", PLAIN) == 0
    assert body_after_status_head(posted(slack)["text"]) == PLAIN and "reply ts=" in capsys.readouterr().out


def test_b_input_text_gets_no_added_characters(env, slack):  # ⓑ 앞뒤에 붙는 글자 0  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--asked", "1", "--answered", "1", "--text", PLAIN) == 0
    assert body_after_status_head(posted(slack)["text"]) == PLAIN
    assert not any(ln.startswith(("아직 못 한 것", "요청")) for ln in posted(slack)["text"].splitlines())


def test_c_partial_answer_appends_one_left_line(env, slack):  # ⓒ 덜 답한 것 1줄만 끝에  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--asked", "3", "--answered", "2", "--left", LEFT, "--text", PLAIN) == 0
    lines = body_after_status_head(posted(slack)["text"]).splitlines()
    assert lines == [PLAIN, LEFT_LINE]


def test_d_partial_answer_without_left_is_rejected_before_posting(env, slack, capsys):  # ⓓ  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--asked", "3", "--answered", "2", "--text", PLAIN) == 1
    out = capsys.readouterr()
    assert not slack.replies  # 게시 «전» 거절
    assert "물어본 게 3개인데 2개만 답했어요" in out.err and "--left" in out.err
    assert "남은 것:" not in out.err and not re.search(r"r661|#\d+|\(slack:", out.err)  # 정규식·내부 번호 0


def test_e_counts_missing_is_rejected_with_root_text(env, slack, capsys):  # ⓔ  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--text", PLAIN) == 1
    err = capsys.readouterr().err
    assert not slack.replies and ROOT in err and "--asked" in err  # 뿌리 원문 400자 = 다시 읽게


def test_e2_old_header_in_body_is_rejected(env, slack, capsys):  # ⓔ 변형 — 옛 습관이 남은 좌석  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--asked", "3", "--answered", "2", "--left", LEFT,
               "--text", f"{OLD_HEAD}\n{PLAIN}") == 1
    err = capsys.readouterr().err
    assert not slack.replies and "오빠가 빼라고 했어요" in err and ROOT in err


def test_f_numbered_abbrev_only_lines_still_rejected(env, slack, capsys):  # ⓕ  # noqa: F811
    assert run(env, slack, "--to-slack", T, "--asked", "3", "--answered", "3", "--text", BARE_ONLY) == 1
    err = capsys.readouterr().err
    assert not slack.replies and "쉬운 말로" in err and ROOT in err


def test_f2_topic_thread_only_verdict_is_unchanged(env, slack, capsys, monkeypatch):  # ⓕ2 — r617 판정 불변  # noqa: F811
    monkeypatch.delenv("FT_SLACK_TOPIC_ONLY")  # 기본 = desk(주제 전용 켬)
    room = "승인 묶음 (h12) — 아래를 그대로 실행\n! bash /tmp/h12"
    assert run(env, slack, "--to-slack", T, "--asked", "1", "--answered", "1", "--text", room) == 2
    assert not slack.replies and "post --to desk" in capsys.readouterr().err
    assert trs.room_shaped(room) and not trs.room_shaped(PLAIN)
