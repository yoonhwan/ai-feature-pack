"""팀 뿌리 글과 질문 라우팅 — T5b HIL 답 뒤 같은 이슈 일반 보고(팀 스레드)가 원래 key 로 질문을 닫는다 · T5c 팀 스레드의 오빠 답글은 planner 에게만 (판정 623 r2-A · 실 mbox 미러·inbound 스크립트 사용)."""
import json
from pathlib import Path

import pytest
from _slack_fakes import FAKE_SUMMARIZER, FakeSlack
from _team_fakes import FakeLabels
from _thread_fakes import resume_script
from test_byz_mbox_slack_mirror import TO, questions, rows_file
from test_byz_mbox_slack_mirror import run as mbox_run
from test_byz_mbox_slack_mirror import start as mbox_start
from test_byz_slack_mbox_inbound import PLANNER, env, queue, root, to_of  # noqa: F401  (env = 픽스처 재사용)
from test_byz_slack_mbox_inbound import run as inbound_run
from test_byz_slack_mbox_inbound import start as inbound_start

import mirror_questions as mq  # noqa: E402  (_team_fakes 가 KIT 를 sys.path 에 올린 뒤)


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


def test_t5b_report_in_team_thread_still_closes_the_question_by_the_original_key(tmp_path: Path, slack: FakeSlack, monkeypatch):
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-test\n", encoding="utf-8")
    (tmp_path / "fake_sum.py").write_text(FAKE_SUMMARIZER, encoding="utf-8")
    resume_script(tmp_path)
    labels = FakeLabels()
    monkeypatch.setenv("GITHUB_MIRROR_TOKEN", "t")
    flags = ("--team-roots", "--github-api", labels.base)
    mbox_start(tmp_path, slack)
    rows_file(tmp_path, (2, TO, "[HIL] #820 어느 쪽?\n1) a\n2) b"))
    assert mbox_run(tmp_path, slack, *flags).returncode == 0
    qp = tmp_path / "st" / "byz_slack_questions.C1.json"
    assert "2" in questions(tmp_path)["open"]
    mq.set_delivered(qp, 2, "1.0", 50)
    with open(tmp_path / "mailbox.log.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps({"seq": 51, "ts": "t", "to": TO, "from": "src#1", "body": "#820 답대로 진행했어요"}, ensure_ascii=False) + "\n")
    assert mbox_run(tmp_path, slack, *flags).returncode == 0
    assert "2" not in questions(tmp_path)["open"] and "2" in questions(tmp_path)["resolved"]
    team = next(m for m in slack.roots if "(mirror · team:harness:" in m["text"])
    assert any("답대로" in m["text"] or "820" in m["text"] for m in slack.replies(team))  # 일반 보고는 팀 스레드에
    labels.srv.shutdown()


def test_t5c_oppa_reply_in_a_team_thread_goes_to_planner_only(env: Path, slack: FakeSlack):  # noqa: F811
    inbound_start(env, slack)
    ts = root(slack, "[작업상황] harness · 2026-10-09 — 지금 하는 일\n(mirror · team:harness:2026-10-09 시작)")
    (env / "st").mkdir(exist_ok=True)
    (env / "st" / "byz_slack_threads.C1.json").write_text(json.dumps({"threads": {"team:harness:2026-10-09": ts}}), encoding="utf-8")
    slack.msgs.append({"ts": f"{float(ts) + 0.01:.6f}", "text": "[작업상황] 담당 src#1 의 보고", "thread_ts": ts, "bot_id": "B1"})
    slack.human("이거 어떻게 돼가?", ts)
    (env / "seats-planner.json").write_text(json.dumps({"_master": PLANNER}), encoding="utf-8")
    r = inbound_run(env, slack, MIRROR_PLANNER_SEATS=str(env / "seats-planner.json"), MIRROR_TMUX="true")  # 현역 planner = 명부 + 살아 있는 tmux 대역
    assert r.returncode == 0, r.stderr
    (row,) = to_of(env, PLANNER)
    assert len(queue(env)) == 1 and "팀 스레드 답글" in row["body"] and "https://fake.slack.com/archives/C1/p" in row["body"]

