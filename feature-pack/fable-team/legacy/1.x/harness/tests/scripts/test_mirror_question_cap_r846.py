"""r846 — 질문 장부 상한: 도구(계보 번호 없는 보낸 이)는 질문을 열지 않고 · 좌석은 한 스레드에 열린 질문 1 · 여럿이면 planner 본문에 목록 (실 Slack·실 장부 0)."""
import argparse
import json
from pathlib import Path

import pytest
from _slack_fakes import FakeSlack
from test_byz_mbox_slack_mirror import TO, env, run, start  # noqa: F401  (env = 픽스처 재사용)

import mirror_lib as lib  # noqa: E402  (test_byz_mbox_slack_mirror 가 KIT 를 sys.path 에 올린 뒤)
import mirror_plan  # noqa: E402
import mirror_questions as mq  # noqa: E402

T = "1792571863.818449"
S1, S2 = "byz-cfo-master-claude#112", "byz-v65-master-claude#239"


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


def ask(qp: Path, seq: int, seat: str, what: str = "질문", thread: str = T) -> bool:
    return mq.add(qp, seq, {"key": f"#{seq}", "seat": seat, "what": what, "options": [], "thread_ts": thread})


def plan(tmp: Path, text: str, thread: str = T) -> dict:
    a = argparse.Namespace(api_base="http://invalid.example", channel="C1", state_dir=str(tmp))
    real, lib.paged = lib.paged, lambda *_a, **_k: []  # 스레드 답글 0 — 추정 좌석 없음
    try:
        return mirror_plan.plan(a, "tok", tmp / "byz_slack_questions.C1.json", {"text": text, "thread_ts": thread})
    finally:
        lib.paged = real


def test_a_tool_alarms_open_no_question_so_oppa_post_is_not_stuck(tmp_path: Path):
    qp = tmp_path / "byz_slack_questions.C1.json"
    assert not any(ask(qp, 100 + i, "ft-model-swap", f"[HIL] 자동 교대 불가 좌석{i}") for i in range(50))
    assert mq.load(qp)["open"] == {}
    p = plan(tmp_path, "큐 확인해 줘")
    assert "좌석을 정하지 못했어요" not in p["text"] and "추정: 열린 질문 없음" in p["text"] and p["recips"] == ["@planner"]


def test_a_tool_hil_row_still_posts_its_card_without_a_question(env: Path, slack: FakeSlack):  # noqa: F811
    start(env, slack)
    with open(env / "mailbox.log.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps({"seq": 2, "ts": "t", "to": TO, "from": "ft-model-swap", "body": "[HIL] #820 자동 교대 불가 — 어느 쪽?\n1) a\n2) b"}, ensure_ascii=False) + "\n")
    assert run(env, slack).returncode == 0
    assert "자동 교대 불가" in slack.replies(slack.roots[0])[0]["text"]
    assert json.loads((env / "st" / "byz_slack_questions.C1.json").read_text(encoding="utf-8"))["open"] == {}


def hil_row(root: Path, seq: int, frm: str) -> None:
    with open(root / "mailbox.log.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps({"seq": seq, "ts": "t", "to": TO, "from": frm, "body": f"[HIL] #82{seq} 어느 쪽?\n1) a\n2) b"}, ensure_ascii=False) + "\n")


def opened(root: Path) -> dict:
    p = root / "st" / "byz_slack_questions.C1.json"
    return json.loads(p.read_text(encoding="utf-8"))["open"] if p.exists() else {}


def test_r2_da_counterexample_tool_with_lineage_number_opens_no_question(env: Path, slack: FakeSlack):  # noqa: F811
    start(env, slack)
    hil_row(env, 2, "ft-model-swap#1")  # DA r1 반례 — «이름#N» 꼴이지만 명부에 없다
    assert run(env, slack).returncode == 0
    assert opened(env) == {} and "어느 쪽?" in slack.replies(slack.roots[0])[0]["text"]
    assert plan(env / "st", "1번")["recips"] == ["@planner"]


def test_r2_legacy_name_on_roster_opens_and_off_roster_name_does_not(env: Path, slack: FakeSlack):  # noqa: F811
    start(env, slack)
    (env / "seats-cfo.json").write_text(json.dumps({"_name": "cfo", "FB_CFO#46": {"role": "master"}}), encoding="utf-8")
    hil_row(env, 2, "FB_CFO#46")
    hil_row(env, 3, "byz-ghost-master-claude#1")
    assert run(env, slack).returncode == 0
    assert list(opened(env)) == ["2"] and opened(env)["2"]["seat"] == "FB_CFO#46"


def test_r2_broken_roster_opens_no_question_and_warns(env: Path, slack: FakeSlack):  # noqa: F811
    start(env, slack)
    (env / "seats-broken.json").write_text("{깨짐", encoding="utf-8")
    hil_row(env, 2, "src#1")
    r = run(env, slack)
    assert r.returncode == 0 and opened(env) == {} and "WARN: 명부 못 읽음" in r.stderr
    assert "어느 쪽?" in slack.replies(slack.roots[0])[0]["text"]


def test_r3_da_r2_counterexample_off_roster_lineage_number_opens_nothing_and_roster_seat_gets_answer(env: Path, slack: FakeSlack):  # noqa: F811
    start(env, slack)
    hil_row(env, 2, "src#999")  # DA r2 반례 — 명부엔 src#1 만 · 같은 계보 다른 번호
    assert run(env, slack).returncode == 0
    assert opened(env) == {} and any("#822" in r["text"] for r in slack.replies(slack.roots[0]))
    hil_row(env, 3, "src#1")
    assert run(env, slack).returncode == 0
    assert list(opened(env)) == ["3"]
    p = plan(env / "st", "진행해", thread=opened(env)["3"]["thread_ts"])
    assert p["recips"] == ["src#1", "@planner"] and p["q"] == 3


def test_r3_on_roster_exact_match_only(tmp_path: Path, capsys):
    (tmp_path / "seats-a.json").write_text(json.dumps({"_master": "x#0", S1: {}, "ft-harness-ops#2": {}}), encoding="utf-8")
    assert mq.on_roster(S1, tmp_path) and mq.on_roster("ft-harness-ops#2", tmp_path)
    assert not mq.on_roster("byz-cfo-master-claude#113", tmp_path) and not mq.on_roster("ft-harness-ops#0", tmp_path)  # 명부에 없는 같은 계보 번호 = 질문 0
    assert not mq.on_roster("ft-model-swap#1", tmp_path) and not mq.on_roster("x#0", tmp_path) and not mq.on_roster("byz-cfo-master#112", tmp_path)
    assert not mq.on_roster(S1, tmp_path / "없음") and "WARN: 명부 못 읽음" in capsys.readouterr().err
    (tmp_path / "seats-b.json").write_text("[1, 2]", encoding="utf-8")  # r4 ⓐ: 모양 틀린 파일만 건너뜀 — 정상 명부 seats-a 는 그대로
    assert mq.on_roster(S1, tmp_path) and "WARN: 명부 모양 틀림 — 건너뜀 · seats-b.json" in capsys.readouterr().err


def test_r4_da_r3_counterexample_misshaped_roster_file_is_skipped_card_posts_and_seat_still_opens(env: Path, slack: FakeSlack):  # noqa: F811
    start(env, slack)
    (env / "seats-broken.json").write_text("[[1, {}]]", encoding="utf-8")  # DA r3 반례 — dict([[1, {}]]) = {1: {}} → 키 int
    hil_row(env, 2, "src#1")
    r = run(env, slack)
    assert r.returncode == 0 and any("#822" in x["text"] for x in slack.replies(slack.roots[0]))
    assert r.stderr.count("WARN: 명부 모양 틀림 — 건너뜀 · seats-broken.json") == 1
    assert list(opened(env)) == ["2"] and opened(env)["2"]["seat"] == "src#1"


def test_r4_any_roster_read_exception_opens_no_question_and_card_still_posts(env: Path, slack: FakeSlack):  # noqa: F811
    start(env, slack)
    (env / "seats-dir.json").mkdir()  # 주입 — read_text 가 IsADirectoryError(파일별 모양 틀림 아님 → 함수 전체 예외)
    hil_row(env, 2, "src#1")
    r = run(env, slack)
    assert r.returncode == 0 and any("#822" in x["text"] for x in slack.replies(slack.roots[0]))
    assert r.stderr.count("WARN: 명부 못 읽음") == 1 and opened(env) == {}


def test_r4_on_roster_wraps_any_exception(tmp_path: Path, capsys, monkeypatch):
    (tmp_path / "seats-a.json").write_text(json.dumps({S1: {}}), encoding="utf-8")
    monkeypatch.setattr(mq.json, "loads", lambda *_a, **_k: (_ for _ in ()).throw(RuntimeError("주입")))
    assert not mq.on_roster(S1, tmp_path) and "WARN: 명부 못 읽음" in capsys.readouterr().err


def test_r5_da_r4_counterexample_deeply_nested_planner_roster_marks_board_and_card_still_posts(env: Path, slack: FakeSlack):  # noqa: F811
    start(env, slack)
    (env / "seats-planner.json").write_text("[" * 1500 + "]" * 1500, encoding="utf-8")  # DA r4 반례 — 1,500겹 중첩 배열 → json.loads RecursionError
    hil_row(env, 2, "src#1")
    r = run(env, slack)
    assert r.returncode == 0 and "Traceback" not in r.stderr
    assert any("#822" in x["text"] for x in slack.replies(slack.roots[0]))  # 카드 1
    assert r.stderr.count("ERROR: 명부 못 읽음 · seats-planner.json · RecursionError") >= 1
    board = [m["text"] for m in slack.msgs if m["text"].startswith("[상태] 결정 대기")]
    assert board and "확인 불가(JSON 오류 RecursionError)" in board[-1]  # 보드에 실패 표시
    assert opened(env) == {} and "WARN: 명부 못 읽음" in r.stderr  # 질문은 r4 규칙(못 읽는 명부 → 질문 0)


def test_r5_live_planner_reports_recursion_error_with_error_log(tmp_path: Path, capsys):
    import mirror_share as ms
    p = tmp_path / "seats-planner.json"
    p.write_text("[" * 1500 + "]" * 1500, encoding="utf-8")
    assert ms.live_planner(p) == (None, "JSON 오류 RecursionError")
    assert "ERROR: 명부 못 읽음 · seats-planner.json · RecursionError" in capsys.readouterr().err


@pytest.mark.parametrize("seat", ["ft-model-swap", "", "slack-oppa", "ft-hil", "byz-cfo-master-claude", "a#", "#3"])
def test_b_only_seat_names_with_a_lineage_number_open_questions(tmp_path: Path, seat: str):
    qp = tmp_path / "q.json"
    assert not ask(qp, 1, seat) and mq.load(qp)["open"] == {}


@pytest.mark.parametrize("seat", [S1, "byz-harness-nano-r846-slack-router-question-cap#0", "FB_CFO#46", "src#1"])
def test_b_seat_names_open_questions(tmp_path: Path, seat: str):
    assert ask(tmp_path / "q.json", 1, seat)


def test_c_same_seat_same_thread_new_question_supersedes_the_old_one(tmp_path: Path):
    qp = tmp_path / "byz_slack_questions.C1.json"
    assert ask(qp, 10, S1, "첫 질문") and ask(qp, 11, S1, "둘째 질문")
    data = mq.load(qp)
    assert list(data["open"]) == ["11"] and data["resolved"]["10"]["why"] == "superseded"
    assert not ask(qp, 10, S1, "첫 질문")  # tombstone — 재개 때 부활하지 않는다
    p = plan(tmp_path, "Q10 a 로 가")
    assert p["recips"] == ["@planner"] and "Q10 를 찾지 못했어요" in p["text"]
    p = plan(tmp_path, "a 로 가")
    assert p["recips"] == [S1, "@planner"] and p["q"] == 11


def test_c_delivered_question_is_superseded_too_but_other_threads_and_seats_stay(tmp_path: Path):
    qp = tmp_path / "q.json"
    ask(qp, 10, S1)
    mq.set_delivered(qp, 10, "1.0", 50)
    ask(qp, 12, S1, thread="other.1")
    ask(qp, 13, S2)
    ask(qp, 14, S1)
    assert sorted(mq.load(qp)["open"]) == ["12", "13", "14"]


def test_c_an_older_seq_arriving_late_does_not_close_the_newer_question(tmp_path: Path):
    qp = tmp_path / "q.json"
    ask(qp, 20, S1, "새 질문")
    assert not ask(qp, 19, S1, "옛 질문")
    data = mq.load(qp)
    assert list(data["open"]) == ["20"] and data["resolved"]["19"]["why"] == "superseded"


def test_d_several_seats_planner_body_lists_open_questions(tmp_path: Path):
    qp = tmp_path / "byz_slack_questions.C1.json"
    ask(qp, 30, S1, "결제 라이브 전환을 지금 할까요?\n세부 설명")
    ask(qp, 31, S2, "x" * 80)
    p = plan(tmp_path, "그냥 진행해")
    assert p["recips"] == ["@planner"] and p["q"] is None
    lines = p["text"].splitlines()
    assert "질문이 2개라 좌석을 정하지 못했어요" in lines[0] and "그냥 진행해" in p["text"]
    assert f"Q30 · {S1} · 결제 라이브 전환을 지금 할까요?" in lines and f"Q31 · {S2} · {'x' * 60}" in lines


def test_d_list_is_capped_at_five_lines(tmp_path: Path):
    qp = tmp_path / "byz_slack_questions.C1.json"
    for i in range(7):
        ask(qp, 40 + i, f"byz-t{i}-master-claude#1")
    text = plan(tmp_path, "아무거나")["text"]
    assert sum(ln.startswith("Q4") for ln in text.splitlines()) == 5 and "외 2개" in text


def test_e_single_numbered_team_and_fixed_modes_unchanged(tmp_path: Path):
    qp = tmp_path / "byz_slack_questions.C1.json"
    ask(qp, 50, S1)
    assert plan(tmp_path, "1번")["recips"] == [S1, "@planner"]
    ask(qp, 51, S2)
    p = plan(tmp_path, "Q51 그걸로")
    assert p["recips"] == [S2, "@planner"] and p["q"] == 51
    (tmp_path / "byz_slack_threads.C1.json").write_text(json.dumps({"threads": {"team:cfo": "900.1"}}), encoding="utf-8")
    assert plan(tmp_path, "팀 글", thread="900.1")["recips"] == ["@planner"]
    a = argparse.Namespace(api_base="http://invalid.example", channel="C1", state_dir=str(tmp_path), to_key="desk")
    fixed = mirror_plan.plan(a, "tok", qp, {"text": "1번", "thread_ts": T})
    assert fixed["recips"] == ["@planner"] and fixed["q"] is None
