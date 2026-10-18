"""byz_slack_mbox_inbound — 가짜 Slack·가짜 mbox 로 역방향(오빠 글 → 좌석 mbox)의 라우팅·exactly-once·장애 주입을 시험한다."""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest
from _slack_fakes import FakeSlack

HERE = Path(__file__).resolve().parent
KIT = HERE.parents[1] / "harness" / "kit" / "slack-mirror"
SCRIPT = KIT / "byz_slack_mbox_inbound.py"
HUMAN = "U0AC2JF0M7D"
PLANNER = "byz-planner-arch#3"
sys.path.insert(0, str(KIT))
import mirror_questions as mq  # noqa: E402


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


@pytest.fixture
def env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setenv("MIRROR_TMUX", "true")  # tmux 대역 = 세션 있음(실 tmux 0) — 시험이 `**extra` 로 덮을 수 있다
    (tmp_path / "comm").mkdir()
    shutil.copy(HERE / "_fake_mbox.sh", tmp_path / "comm" / "mbox.sh")
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-test\n", encoding="utf-8")
    (tmp_path / "seats.json").write_text("{}", encoding="utf-8")
    (tmp_path / "seats-planner.json").write_text(json.dumps({"_master": PLANNER}), encoding="utf-8")  # planner = 이 명부 `_master`(판정 497)
    return tmp_path


def run(env: Path, slack: FakeSlack, **extra: str):
    e = {**os.environ, "FAKE_MBOX": str(env / "comm" / "mbox.sh"), **extra}
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--channel", "C1", "--human", HUMAN, "--mbox", str(env / "comm" / "mbox.sh"),
         "--seats-file", str(env / "seats.json"), "--state-dir", str(env / "st"), "--token-file", str(env / "tok.env"),
         "--api-base", slack.base, "--inbox-bin", str(HERE / "_fake_inbox.sh"), "--once"], capture_output=True, text=True, timeout=60, env=e)


def queue(env: Path) -> list[dict]:
    p = env / "comm" / "mailbox.jsonl"
    return [json.loads(ln) for ln in p.read_text(encoding="utf-8").splitlines()] if p.exists() else []


def to_of(env: Path, who: str) -> list[dict]:
    return [r for r in queue(env) if r["to"] == who]


def start(env: Path, slack: FakeSlack) -> str:
    """baseline 만 만들고, 봇 루트 하나(스레드)를 둔다. 반환 = 그 스레드의 ts."""
    assert run(env, slack).returncode == 0
    return root(slack, "#820 시작 — x")


def root(slack: FakeSlack, text: str) -> str:
    ts = f"{time.time() + len(slack.msgs) * 0.001:.6f}"  # baseline 이후의 봇 루트(스레드)
    slack.msgs.append({"ts": ts, "text": text, "thread_ts": "", "bot_id": "B1"})
    return ts


def ask(env: Path, thread: str, seq: int, seat: str = "ft-impl#1", options: list[str] | None = None, key: str = "#820") -> None:
    (env / "st").mkdir(exist_ok=True)
    mq.add(env / "st" / "byz_slack_questions.C1.json", seq,
           {"key": key, "seat": seat, "what": "질문", "options": options or [], "thread_ts": thread})


def test_first_run_is_baseline_and_old_human_posts_are_not_replayed(env: Path, slack: FakeSlack):
    slack.human("옛 글")
    assert run(env, slack).returncode == 0 and queue(env) == []


def test_reply_goes_to_question_seat_and_planner_with_tokens(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    ts = slack.human("그렇게 해 주세요", t)
    assert run(env, slack).returncode == 0
    (seat_row,) = to_of(env, "ft-impl#1")
    (plan_row,) = to_of(env, PLANNER)
    assert "그렇게 해 주세요" in seat_row["body"] and "질문 Q100" in seat_row["body"] and f"slack:{ts}:ft-impl#1" in seat_row["body"]
    assert seat_row["from"] == "slack-oppa" and f"slack:{ts}:@planner" in plan_row["body"]  # 전달 표식은 역할(@planner) 로 박힌다
    data = mq.load(env / "st" / "byz_slack_questions.C1.json")
    assert data["open"]["100"]["state"] == "delivered"
    assert run(env, slack).returncode == 0 and len(queue(env)) == 2  # 재실행 중복 0


def test_bots_other_users_and_subtypes_are_ignored(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    slack.human("남의 글", t, user="U999")
    slack.msgs.append({"ts": "9999999999.0", "text": "봇", "thread_ts": t, "user": HUMAN, "bot_id": "B2"})
    slack.msgs.append({"ts": "9999999999.1", "text": "수정됨", "thread_ts": t, "user": HUMAN, "subtype": "message_changed"})
    assert run(env, slack).returncode == 0 and queue(env) == []


def test_number_answer_is_expanded_to_the_option_text_and_out_of_range_stays_raw(env: Path, slack: FakeSlack):
    t = start(env, slack)
    t2 = root(slack, "#821 시작 — y")
    ask(env, t, 100, options=["폴링", "소켓"])
    ask(env, t2, 101, seat="ft-b#1", options=["a", "b"], key="#821")
    slack.human("2번", t)
    slack.human("7", t2)
    assert run(env, slack).returncode == 0
    assert "선택 2: 소켓" in to_of(env, "ft-impl#1")[0]["body"]
    assert "\n7\n" in to_of(env, "ft-b#1")[0]["body"]  # 범위 밖 번호는 원문 그대로


def test_root_human_post_goes_to_planner_only(env: Path, slack: FakeSlack):
    start(env, slack)
    slack.human("새 요청이에요")
    assert run(env, slack).returncode == 0
    assert [r["to"] for r in queue(env)] == [PLANNER] and "오빠 새 글" in queue(env)[0]["body"]


def test_two_open_questions_without_q_asks_back_and_does_not_guess(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100, seat="ft-a#1")
    ask(env, t, 101, seat="ft-b#1")
    slack.human("1", t)
    assert run(env, slack).returncode == 0
    assert [r["to"] for r in queue(env)] == [PLANNER]
    assert "질문이 2개라 좌석을 정하지 못했어요" in to_of(env, PLANNER)[0]["body"]  # 추정하지 않고 원문을 planner 에게
    slack.human("Q101 진행해요", t)
    assert run(env, slack).returncode == 0
    assert "진행해요" in to_of(env, "ft-b#1")[0]["body"] and to_of(env, "ft-a#1") == []


def test_no_open_question_uses_last_report_seat_marked_inferred_and_ignores_quoted_fake_tail(env: Path, slack: FakeSlack):
    t = start(env, slack)
    slack.msgs.append({"ts": f"{time.time():.6f}", "text": "요약\n할 일 없음\n(ft-real#2 · #55)\n\n전문\n> (ft-fake#9 · #1)", "thread_ts": t, "bot_id": "B1"})
    slack.human("확인했어요", t)
    assert run(env, slack).returncode == 0
    assert len(to_of(env, "ft-real#2")) == 1 and to_of(env, "ft-fake#9") == []
    assert "추정" in to_of(env, "ft-real#2")[0]["body"] and len(to_of(env, PLANNER)) == 1


def _crashed_state(env: Path, ts: str, done: dict[str, bool], attempt: int = 1, thread: str = "", seat: str = "ft-impl#1") -> None:
    (env / "st").mkdir(exist_ok=True)
    entry = {"recips": [seat, PLANNER], "text": "오빠(Slack) 발화 — 원문 · #820 스레드 · 질문 Q100:\n네", "q": 100,
             "thread": thread, "done": done, "attempt": {seat: attempt}}
    (env / "st" / "byz_slack_mbox_inbound.C1.json").write_text(json.dumps({"baseline": "1.0", "ledger": {ts: entry}}), encoding="utf-8")


@pytest.mark.parametrize("log_fail", [False, True])
def test_crash_after_queue_before_done_does_not_resend_but_sends_the_rest(env: Path, slack: FakeSlack, log_fail: bool):
    t = start(env, slack)
    ask(env, t, 100)
    ts = slack.human("네", t)
    (env / "comm" / "mailbox.jsonl").write_text(
        json.dumps({"seq": 1, "to": "ft-impl#1", "from": "slack-oppa", "body": f"x\n(slack:{ts}:ft-impl#1)"}) + "\n", encoding="utf-8")
    if not log_fail:
        shutil.copy(env / "comm" / "mailbox.jsonl", env / "comm" / "mailbox.log.jsonl")
    _crashed_state(env, ts, {})
    assert run(env, slack).returncode == 0
    assert len(to_of(env, "ft-impl#1")) == 1 and len(to_of(env, PLANNER)) == 1  # 주인 중복 0 · planner 는 보냄


def test_attempt_without_any_trace_is_resent_and_human_typed_token_is_not_a_false_positive(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    ts = slack.human("네", t)
    (env / "comm" / "mailbox.jsonl").write_text(
        json.dumps({"seq": 1, "to": "ft-impl#1", "from": "someone", "body": f"(slack:{ts}:ft-impl#1)"}) + "\n", encoding="utf-8")
    _crashed_state(env, ts, {})
    assert run(env, slack).returncode == 0
    assert len([r for r in to_of(env, "ft-impl#1") if r["from"] == "slack-oppa"]) == 1  # 흔적 없음 → 재전송 1회


def test_marker_found_in_rotated_log(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    ts = slack.human("네", t)
    row = {"seq": 1, "to": "ft-impl#1", "from": "slack-oppa", "body": f"(slack:{ts}:ft-impl#1)"}
    (env / "comm" / "mailbox.log.jsonl.1").write_text(json.dumps(row) + "\n", encoding="utf-8")
    _crashed_state(env, ts, {})
    assert run(env, slack).returncode == 0 and to_of(env, "ft-impl#1") == []


def test_replies_in_two_threads_are_all_delivered_regardless_of_ts_order(env: Path, slack: FakeSlack):
    t = start(env, slack)
    t2 = root(slack, "#821 시작 — y")
    ask(env, t, 100, seat="ft-a#1")
    ask(env, t2, 101, seat="ft-b#1", key="#821")
    slack.human("B 먼저", t2)
    slack.human("A 나중", t)
    assert run(env, slack).returncode == 0
    assert len(to_of(env, "ft-a#1")) == 1 and len(to_of(env, "ft-b#1")) == 1


def test_pagination_reads_every_page(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    slack.page_size = 1
    for i in range(3):
        slack.human(f"답 {i}", t)
    assert run(env, slack).returncode == 0
    assert len(to_of(env, "ft-impl#1")) == 3


def test_mbox_failure_raises_then_recovers_once(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    slack.human("네", t)
    r = run(env, slack, FAKE_FAIL_TO="ft-impl#1")
    assert r.returncode == 1 and "mbox 전달 실패" in r.stderr and queue(env) == []
    assert run(env, slack).returncode == 0
    assert len(to_of(env, "ft-impl#1")) == 1 and len(to_of(env, PLANNER)) == 1


def test_full_queue_defers_delivery_notifies_slack_once_and_delivers_after_it_drains(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    slack.human("네", t)
    q = env / "comm" / "mailbox.jsonl"
    q.write_text("".join(json.dumps({"seq": i, "to": "ft-impl#1", "from": "x", "body": "b"}) + "\n" for i in range(10)), encoding="utf-8")
    assert run(env, slack).returncode == 0
    assert [r for r in to_of(env, "ft-impl#1") if r["from"] == "slack-oppa"] == []  # 밀려나게 두지 않고 보내지 않음
    assert any("가득" in m["text"] for m in slack.msgs)
    assert run(env, slack).returncode == 0 and sum("가득" in m["text"] for m in slack.msgs) == 1  # 알림은 1번
    q.write_text("", encoding="utf-8")  # 좌석이 읽음
    assert run(env, slack).returncode == 0
    assert len([r for r in to_of(env, "ft-impl#1") if r["from"] == "slack-oppa"]) == 1


def test_second_instance_is_refused(env: Path, slack: FakeSlack):
    import fcntl

    (env / "st").mkdir()
    with open(env / "st" / "byz_slack_mbox_inbound.C1.lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        r = run(env, slack)
    assert r.returncode == 2 and "다른 inbound" in r.stderr


def test_planner_master_missing_holds_and_notices_then_delivers_once(env: Path, slack: FakeSlack):
    start(env, slack)
    slack.human("글")
    notices = lambda why: sum(f"planner 현역 세션 확인 불가({why})" in m["text"] for m in slack.msgs)  # noqa: E731
    (env / "seats-planner.json").write_text("{}", encoding="utf-8")  # `_master` 없음 → 보내지 않고 보관 + 슬랙 상태 알림 1 · rc 0
    assert run(env, slack).returncode == 0 and queue(env) == [] and notices("_master 없음") == 1
    (env / "seats-planner.json").write_text(json.dumps({"_master": PLANNER}), encoding="utf-8")
    assert run(env, slack, MIRROR_TMUX="false").returncode == 0 and queue(env) == [] and notices("세션 없음") == 1  # tmux 대역 false
    assert run(env, slack).returncode == 0 and len(queue(env)) == 1 and notices("_master 없음") + notices("세션 없음") == 2  # 현역이 되자 다음 패스에 정확히 1회 · 알림 추가 0


def test_resolved_question_is_not_reopened_and_existing_board_is_reused(env: Path, slack: FakeSlack):
    (env / "st").mkdir()
    qp = env / "st" / "byz_slack_questions.C1.json"
    assert mq.add(qp, 5, {"key": "#1", "seat": "s#1", "what": "w", "options": [], "thread_ts": "1.0"})
    assert mq.close(qp, 5) and not mq.add(qp, 5, {"key": "#1", "seat": "s#1", "what": "w", "options": [], "thread_ts": "1.0"})
    slack.msgs.append({"ts": "7.0", "text": "답을 기다리는 질문 3건 — 옛 보드", "thread_ts": "", "bot_id": "B1"})
    mq.update_board(qp, slack.base, "x", "C1", str(env / "seats-planner.json"))  # 옛 머리표 보드를 찾아 새 머리표 글로 제자리 갱신
    assert [m["text"] for m in slack.roots] == [f"{mq.BOARD_HEAD} 0건 — 결정 자리: {PLANNER}"] and mq.load(qp)["meta"]["board_ts"] == "7.0"


def test_partial_success_sends_only_the_missing_recipient(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    ts = slack.human("네", t)
    _crashed_state(env, ts, {"ft-impl#1": True})  # 주인은 이미 done — planner 만 남음(흔적 검색 없이도 주인을 다시 보내면 안 된다)
    assert run(env, slack).returncode == 0
    assert to_of(env, "ft-impl#1") == [] and len(to_of(env, PLANNER)) == 1


def test_token_match_is_exact_for_recipient_and_line(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100, seat="ft-a#1")
    ts = slack.human("네", t)
    rows = [  # 다른 수신자(ft-a#10) · 부분 문자열 · 다른 글 본문에 인용된 토큰 — 전부 전달 증거가 아니다
        {"seq": 1, "to": "ft-a#10", "from": "slack-oppa", "body": f"x\n(slack:{ts}:ft-a#10)"},
        {"seq": 2, "to": "ft-a#1", "from": "slack-oppa", "body": f"인용: slack:{ts}:ft-a#1 입니다"}]
    (env / "comm" / "mailbox.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    _crashed_state(env, ts, {}, seat="ft-a#1")
    assert run(env, slack).returncode == 0
    assert len([r for r in to_of(env, "ft-a#1") if "오빠(Slack)" in r["body"]]) == 1  # 증거 없음 → 1회 재전송


def test_second_attempt_without_trace_stops_and_tells_slack_instead_of_a_third_send(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    ts = slack.human("네", t)
    _crashed_state(env, ts, {}, attempt=2, thread=t)
    r = run(env, slack)
    assert r.returncode == 0 and to_of(env, "ft-impl#1") == []
    assert any("확인할 수 없어요" in m["text"] for m in slack.msgs) and "확인할 수 없어요" in r.stderr


def test_unfinished_ledger_entry_resumes_without_slack_even_after_seven_days(env: Path, slack: FakeSlack):
    start(env, slack)
    old = f"{__import__('time').time() - 9 * 86400:.6f}"  # Slack 창 밖 — 다시 발견될 수 없는 글
    _crashed_state(env, old, {"ft-impl#1": True}, attempt=1)
    assert run(env, slack).returncode == 0
    assert to_of(env, "ft-impl#1") == [] and len(to_of(env, PLANNER)) == 1  # planner 만 남은 몫을 보냄
    st = json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))
    assert old not in st["ledger"]  # 끝난 뒤에야 창 밖 항목이 정리된다(미완료는 지우지 않음 — 위에서 전달까지 확인)


def test_reply_in_a_thread_created_before_baseline_is_found(env: Path, slack: FakeSlack):
    old_root = f"{__import__('time').time() - 60:.6f}"  # 기동 1분 전 스레드, 열린 질문 없음
    slack.msgs.append({"ts": old_root, "text": "요약\n할 일 없음\n(ft-real#2 · #55)", "thread_ts": "", "bot_id": "B1"})
    assert run(env, slack).returncode == 0
    slack.human("확인했어요", old_root)
    assert run(env, slack).returncode == 0
    assert len(to_of(env, "ft-real#2")) == 1


def test_unknown_q_number_asks_back_and_q_glued_to_text_is_parsed(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    slack.human("Q999 진행", t)
    assert run(env, slack).returncode == 0
    assert to_of(env, "ft-impl#1") == [] and any("찾지 못했어요" in r["body"] for r in to_of(env, PLANNER))
    slack.human("Q100진행", t)
    assert run(env, slack).returncode == 0
    assert "\n진행\n" in to_of(env, "ft-impl#1")[0]["body"]


def test_delivered_and_open_questions_together_need_a_q_number(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100, seat="ft-a#1")
    ask(env, t, 101, seat="ft-b#1")
    mq.set_delivered(env / "st" / "byz_slack_questions.C1.json", 100, "1.0", 5)
    slack.human("이전 답 수정합니다", t)
    assert run(env, slack).returncode == 0
    assert to_of(env, "ft-a#1") == [] and to_of(env, "ft-b#1") == []  # 가로채지 않는다
    assert mq.load(env / "st" / "byz_slack_questions.C1.json")["open"]["101"]["state"] == "open"


def test_only_the_root_bots_tail_line_names_the_inferred_seat(env: Path, slack: FakeSlack):
    t = start(env, slack)
    slack.msgs.append({"ts": f"{time.time():.6f}", "text": "x\n할 일 없음\n(ft-wrong#1 · #123)", "thread_ts": t, "bot_id": "B-OTHER"})
    slack.human("답", t)
    assert run(env, slack).returncode == 0
    assert to_of(env, "ft-wrong#1") == []


def test_confirm_answer_closes_the_delivered_question(env: Path, slack: FakeSlack):
    t = start(env, slack)
    ask(env, t, 100)
    qp = env / "st" / "byz_slack_questions.C1.json"
    mq.set_delivered(qp, 100, "1.0", 5)
    slack.human("확인", t)
    assert run(env, slack).returncode == 0
    assert "100" not in mq.load(qp)["open"] and "100" in mq.load(qp)["resolved"]


def test_procedure_list_is_not_an_option_block_but_a_question_list_is():
    assert mq.parse_options("진행 절차\n1) 백업\n2) 배포\n자유롭게 답해 주세요") == []
    assert mq.parse_options("어느 쪽으로 갈까요?\n1) 폴링\n2) 소켓") == ["폴링", "소켓"]


# --- R241: desk 로 넘긴 오빠 글에 «받았어요» + 3분 미읽음 경보 (--ack · DESIGN-r241 §3) ---
DESK = "byz-planner-desk-claude#1"
T0 = 1_800_000_000


def run_ack(env: Path, slack: FakeSlack, now: int = T0, ack: bool = True, **extra: str):
    (env / "seats-planner.json").write_text(json.dumps({"_master": PLANNER, "_desk": DESK}), encoding="utf-8")  # R238: 수신 좌석 = 명부 키 _desk
    e = {**os.environ, "FAKE_MBOX": str(env / "comm" / "mbox.sh"), "FT_ACK_NOW": str(now), **extra}
    argv = [sys.executable, str(SCRIPT), "--channel", "C1", "--human", HUMAN, "--to-key", "_desk", "--mbox", str(env / "comm" / "mbox.sh"),
            "--seats-file", str(env / "seats.json"), "--state-dir", str(env / "st"), "--token-file", str(env / "tok.env"),
            "--api-base", slack.base, "--inbox-bin", str(HERE / "_fake_inbox.sh"), "--once", *(["--ack"] if ack else [])]
    return subprocess.run(argv, capture_output=True, text=True, timeout=60, env=e)


def posts(slack: FakeSlack, word: str) -> list[dict]:
    return [m for m in slack.msgs if m.get("bot_id") == "B1" and word in m["text"]]


def desk_read(env: Path) -> None:
    """desk 가 recv 로 읽었다 = 대기 큐에서 빠진다(사본 로그는 남는다)."""
    q = env / "comm" / "mailbox.jsonl"
    rows = [ln for ln in q.read_text(encoding="utf-8").splitlines() if json.loads(ln)["to"] != DESK]
    q.write_text("".join(r + "\n" for r in rows), encoding="utf-8")


def ack_start(env: Path, slack: FakeSlack) -> str:
    assert run_ack(env, slack).returncode == 0  # baseline
    return slack.human("desk 야 이거 봐줘")


def test_ack_posts_once_in_the_humans_thread_on_delivery_and_never_again(env: Path, slack: FakeSlack):
    ts = ack_start(env, slack)
    assert run_ack(env, slack).returncode == 0
    assert len(to_of(env, DESK)) == 1
    (ack,) = posts(slack, "받았어요")
    assert ack["thread_ts"] == ts and "desk 에 넘겼어요" in ack["text"]  # 루트 글이면 그 글의 스레드
    assert run_ack(env, slack, now=T0 + 10).returncode == 0
    assert len(posts(slack, "받았어요")) == 1 and len(to_of(env, DESK)) == 1  # 한 글 1회 · 재전달 0


def test_ack_on_a_thread_reply_goes_to_that_thread(env: Path, slack: FakeSlack):
    t = start_ack_thread(env, slack)
    slack.human("스레드 답", t)
    assert run_ack(env, slack).returncode == 0
    (ack,) = posts(slack, "받았어요")
    assert ack["thread_ts"] == t


def start_ack_thread(env: Path, slack: FakeSlack) -> str:
    assert run_ack(env, slack).returncode == 0
    return root(slack, "#241 시작 — x")


def test_unread_for_180s_alarms_once_in_thread_and_once_to_planner(env: Path, slack: FakeSlack):
    ts = ack_start(env, slack)
    assert run_ack(env, slack).returncode == 0
    assert run_ack(env, slack, now=T0 + 179).returncode == 0
    assert posts(slack, "못 읽었어요") == [] and to_of(env, PLANNER) == []  # 179초 = 아직
    assert run_ack(env, slack, now=T0 + 181).returncode == 0
    (alarm,) = posts(slack, "못 읽었어요")
    assert alarm["thread_ts"] == ts and "3분째" in alarm["text"] and "planner 에 알렸어요" in alarm["text"]
    (note,) = to_of(env, PLANNER)
    assert "[desk 대기 경보]" in note["body"] and ts in note["body"] and "쪽지 1" in note["body"]
    assert run_ack(env, slack, now=T0 + 900).returncode == 0
    assert len(posts(slack, "못 읽었어요")) == 1 and len(to_of(env, PLANNER)) == 1  # 글당 1회 · 재촉 0


def test_read_before_the_window_marks_read_and_never_alarms(env: Path, slack: FakeSlack):
    ack_start(env, slack)
    assert run_ack(env, slack).returncode == 0
    desk_read(env)
    assert run_ack(env, slack, now=T0 + 60).returncode == 0
    assert run_ack(env, slack, now=T0 + 600).returncode == 0
    assert posts(slack, "못 읽었어요") == [] and to_of(env, PLANNER) == []
    ledger = json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))["ledger"]
    assert all(v.get("read_seen") for v in ledger.values())


def test_without_ack_flag_nothing_is_posted(env: Path, slack: FakeSlack):
    assert run_ack(env, slack, ack=False).returncode == 0
    slack.human("desk 야 이거 봐줘")
    assert run_ack(env, slack, ack=False).returncode == 0
    assert len(to_of(env, DESK)) == 1
    assert run_ack(env, slack, now=T0 + 900, ack=False).returncode == 0
    assert posts(slack, "받았어요") == [] and posts(slack, "못 읽었어요") == [] and to_of(env, PLANNER) == []


def test_queue_lookup_failure_does_not_alarm_or_mark_read(env: Path, slack: FakeSlack):
    ack_start(env, slack)
    assert run_ack(env, slack).returncode == 0
    (env / "comm" / "mailbox.jsonl").unlink()  # 큐 파일을 못 읽는다 = 모름
    r = run_ack(env, slack, now=T0 + 900)
    assert "큐를 조회하지 못" in r.stderr and posts(slack, "못 읽었어요") == [] and to_of(env, PLANNER) == []
    ledger = json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))["ledger"]
    assert not any(v.get("read_seen") or v.get("alarm_at") for v in ledger.values())


def test_ack_post_failure_is_recorded_loud_and_does_not_redeliver(env: Path, slack: FakeSlack):
    ack_start(env, slack)
    slack.fail_post = True
    r = run_ack(env, slack)
    assert "ERROR" in r.stderr and "받았어요" in r.stderr
    assert len(to_of(env, DESK)) == 1  # 전달은 이미 끝났다
    slack.fail_post = False
    assert run_ack(env, slack, now=T0 + 5).returncode == 0
    assert len(to_of(env, DESK)) == 1 and posts(slack, "받았어요") == []  # 실패 기록 뒤 재시도·재전달 0
    ledger = json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))["ledger"]
    assert any(v.get("ack_failed") for v in ledger.values())

WINDOW = 7 * 86400  # 스크립트 WINDOW 와 같은 값 — 읽는 창·지우는 창 경계 시험용(R242)


def _clocked(env: Path, offset: float) -> dict[str, str]:
    """자식 프로세스의 time.time() 을 offset 초 앞당기는 환경 — 시계 진행 시험(R242)."""
    d = env / "clock"
    d.mkdir(exist_ok=True)
    (d / "sitecustomize.py").write_text("import os, time\n_r, _o = time.time, float(os.environ['FAKE_TIME_OFFSET'])\ntime.time = lambda: _r() + _o\n", encoding="utf-8")
    return {"PYTHONPATH": str(d), "FAKE_TIME_OFFSET": str(offset)}


def _reply_at(slack: FakeSlack, thread: str, age: float) -> str:
    ts = f"{time.time() - age:.6f}"
    slack.msgs.append({"ts": ts, "text": f"{age:.0f}초 전 답", "thread_ts": thread, "user": HUMAN})
    return ts


def _old_thread(env: Path, slack: FakeSlack) -> str:
    """7일 창 밖 루트 + 그 스레드에 열린 질문 — history 에 안 잡히고 «열린 질문 스레드는 항상 읽는다» 경로로만 읽힌다(실제 CFO 사례)."""
    start(env, slack)
    t = f"{time.time() - 10 * 86400:.6f}"
    slack.msgs.append({"ts": t, "text": "#820 옛 시작 — x", "thread_ts": "", "bot_id": "B1"})
    ask(env, t, 100)
    return t


def _old_baseline(env: Path, ledger: dict | None = None) -> None:
    """데몬 첫 실행 시각이 아주 오래된 상태(실제 CFO 사례 — baseline 이 7일보다 훨씬 전)."""
    p = env / "st" / "byz_slack_mbox_inbound.C1.json"
    st = json.loads(p.read_text(encoding="utf-8"))
    p.write_text(json.dumps({**st, "baseline": "1.0", **({} if ledger is None else {"ledger": ledger})}), encoding="utf-8")


def _passes(env: Path, slack: FakeSlack, offsets: tuple[float, ...]) -> list[int]:
    """패스마다 «그 패스에서 새로 도착한 전달 수». 좌석이 큐를 읽어 마커가 사라진 것까지 흉내 낸다(실제 CFO 재전달 조건)."""
    got = []
    for off in offsets:
        assert run(env, slack, **_clocked(env, off)).returncode == 0
        got.append(len([r for r in queue(env) if r["from"] == "slack-oppa"]))
        for name in ("mailbox.jsonl", "mailbox.log.jsonl"):
            (env / "comm" / name).unlink(missing_ok=True)
    return got


def test_reply_older_than_window_in_open_question_thread_is_not_redelivered_after_ledger_prune(env: Path, slack: FakeSlack):
    t = _old_thread(env, slack)
    ts = _reply_at(slack, t, 8 * 86400)
    _old_baseline(env, {ts: {"finished": True, "recips": [], "done": {}, "attempt": {}}})
    assert _passes(env, slack, (0, 0, 0)) == [0, 0, 0]  # 패스 1 에서 끝난 항목이 정리된 뒤에도 옛 답글을 읽으면 패스 2 부터 재전달된다(R242)


def test_new_reply_is_delivered_once_while_old_reply_in_same_thread_is_skipped(env: Path, slack: FakeSlack):
    t = _old_thread(env, slack)
    _reply_at(slack, t, 8 * 86400)
    new = _reply_at(slack, t, 60)
    _old_baseline(env)
    first = run(env, slack)
    assert first.returncode == 0
    rows = to_of(env, "ft-impl#1")
    assert len(rows) == 1 and f"slack:{new}:ft-impl#1" in rows[0]["body"]  # 새 답 1건만
    (env / "comm" / "mailbox.jsonl").unlink()  # 좌석이 읽음
    assert _passes(env, slack, (0, 0)) == [0, 0]  # 다음 패스들은 0


def test_reply_just_inside_window_is_delivered_once_then_never_again_as_clock_passes_the_window_edge(env: Path, slack: FakeSlack):
    t = _old_thread(env, slack)
    ts = _reply_at(slack, t, WINDOW - 10)
    _old_baseline(env)
    assert _passes(env, slack, (0, 20, 40)) == [2, 0, 0]  # 창 안(7일 − 10초) → 전달 1회(좌석+planner) · 시계가 창 가장자리를 넘어도 0
    st = json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))
    assert ts in st["ledger"]  # 7일 직후엔 끝난 항목도 하루 더 기억한다


def _file_post(slack: FakeSlack, files: list[dict], text: str = "메모 봐 주세요", subtype: str | None = None, user: str = HUMAN) -> str:
    ts = slack.human(text, "", user=user)
    slack.msgs[-1].update({"files": files, **({"subtype": subtype} if subtype else {})})
    return ts


_F1 = {"id": "F1", "name": "메모.md", "filetype": "markdown", "mimetype": "text/markdown", "size": 2048, "url_private": "https://files.slack.com/SECRET1", "url_private_download": "https://files.slack.com/SECRET2"}
_F2 = {"id": "F2", "name": "표.pdf", "filetype": "pdf", "mimetype": "application/pdf", "size": 3 * 1024 * 1024}


def test_human_post_with_files_gets_a_meta_line_per_file_without_urls(env: Path, slack: FakeSlack):
    assert run(env, slack).returncode == 0
    _file_post(slack, [_F1, _F2])
    assert run(env, slack).returncode == 0
    body = to_of(env, PLANNER)[0]["body"]
    assert "메모 봐 주세요" in body and "[파일 2개]" in body
    assert "메모.md · markdown · 2.0 KB · id=F1" in body and "표.pdf · pdf · 3.0 MB · id=F2" in body
    assert "files.slack.com" not in body and "SECRET" not in body  # URL·토큰 유출 0


def test_file_share_subtype_from_the_human_is_delivered(env: Path, slack: FakeSlack):
    assert run(env, slack).returncode == 0
    _file_post(slack, [_F1], text="", subtype="file_share")
    assert run(env, slack).returncode == 0
    assert "[파일 1개]" in to_of(env, PLANNER)[0]["body"]


def test_file_share_from_a_disallowed_user_is_not_delivered(env: Path, slack: FakeSlack):
    assert run(env, slack).returncode == 0
    _file_post(slack, [_F1], subtype="file_share", user="U999")
    assert run(env, slack).returncode == 0 and queue(env) == []


def test_post_without_files_body_is_unchanged(env: Path, slack: FakeSlack):
    assert run(env, slack).returncode == 0
    slack.human("파일 없는 글")
    assert run(env, slack).returncode == 0
    assert "[파일" not in to_of(env, PLANNER)[0]["body"]


# --- R241 DA⑥ H2: 단계별 완료 사건 (ack_ts|ack_failed · alarm_planner_seq|alarm_planner_unsure · alarm_slack_ts) ---
def ledger_of(env: Path) -> dict:
    return json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))["ledger"]


def test_finished_but_unacked_item_is_resumed_by_the_next_pass(env: Path, slack: FakeSlack):
    ack_start(env, slack)
    assert run_ack(env, slack).returncode == 0
    sp = env / "st" / "byz_slack_mbox_inbound.C1.json"
    st = json.loads(sp.read_text(encoding="utf-8"))
    for e in st["ledger"].values():  # 전달 끝(finished) 저장 뒤 ack 직전에 죽은 상태를 만든다
        e.pop("ack_ts", None)
        e.pop("ack_at", None)
    sp.write_text(json.dumps(st), encoding="utf-8")
    slack.msgs[:] = [m for m in slack.msgs if "받았어요" not in m["text"]]
    assert run_ack(env, slack, now=T0 + 5).returncode == 0
    assert len(posts(slack, "받았어요")) == 1 and len(to_of(env, DESK)) == 1  # ack 1 · 재전달 0
    assert run_ack(env, slack, now=T0 + 6).returncode == 0 and len(posts(slack, "받았어요")) == 1


def test_enabling_ack_later_does_not_ack_old_finished_messages(env: Path, slack: FakeSlack):
    assert run_ack(env, slack, ack=False).returncode == 0
    slack.human("옛 글")
    assert run_ack(env, slack, ack=False).returncode == 0 and len(to_of(env, DESK)) == 1
    assert run_ack(env, slack, now=T0 + 10).returncode == 0
    assert posts(slack, "받았어요") == []  # --ack 를 켜기 전에 끝난 글에는 소급하지 않는다
    slack.human("새 글")
    assert run_ack(env, slack, now=T0 + 20).returncode == 0 and len(posts(slack, "받았어요")) == 1


def test_planner_failure_keeps_slack_silent_then_recovers_with_one_note_and_one_line(env: Path, slack: FakeSlack):
    ts = ack_start(env, slack)
    assert run_ack(env, slack).returncode == 0
    r = run_ack(env, slack, now=T0 + 181, FAKE_FAIL_TO=PLANNER)
    assert "ERROR" in r.stderr and posts(slack, "못 읽었어요") == [] and to_of(env, PLANNER) == []  # planner 성공 전엔 «알렸어요» 0
    assert run_ack(env, slack, now=T0 + 200).returncode == 0
    assert len(to_of(env, PLANNER)) == 1 and len(posts(slack, "못 읽었어요")) == 1  # 다음 패스: 쪽지 1 + 슬랙 1
    assert posts(slack, "못 읽었어요")[0]["thread_ts"] == ts
    assert run_ack(env, slack, now=T0 + 900).returncode == 0
    assert len(to_of(env, PLANNER)) == 1 and len(posts(slack, "못 읽었어요")) == 1
    e = next(iter(ledger_of(env).values()))
    assert e.get("alarm_planner_seq") and e.get("alarm_slack_ts")


def test_unknown_planner_send_result_is_recorded_and_never_resent(env: Path, slack: FakeSlack):
    ack_start(env, slack)
    assert run_ack(env, slack).returncode == 0
    r = run_ack(env, slack, now=T0 + 181, FAKE_NO_QUEUED="1")  # mbox rc 0 인데 QUEUED 없음 = 결과 불명
    assert "ERROR" in r.stderr and posts(slack, "못 읽었어요") == []
    assert next(iter(ledger_of(env).values())).get("alarm_planner_unsure")
    assert run_ack(env, slack, now=T0 + 400).returncode == 0
    assert to_of(env, PLANNER) == [] and posts(slack, "못 읽었어요") == []  # 재전송 0 · 알렸다는 줄 0


# --- R241 DA⑥ r2 H2-a: --ack 첫 패스 경계(ack_since + 옛 finished 제외)를 «전달 전에» 영속화 ---
def test_first_ack_pass_persists_boundary_before_delivery_so_a_crash_after_finished_still_acks_the_new_item(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    from types import SimpleNamespace

    import byz_slack_mbox_inbound as daemon

    monkeypatch.setattr(daemon.mh, "humans", lambda a: frozenset({"fixture"}))
    monkeypatch.setattr(daemon.mb, "sweep", lambda *a: None)
    posts: list[tuple] = []
    monkeypatch.setattr(daemon.mack.lib, "post", lambda *a: posts.append(a) or "ack.1")
    new_ts, old_ts = str(time.time()), str(time.time() - 3600)
    base = {"recips": ["@planner"], "done": {"@planner": "desk#1"}, "attempt": {"@planner": ["desk#1"]}, "thread": "", "mbox_seq": 1}
    st = {"baseline": "1", "seen": {}, "ledger": {old_ts: {**base, "finished": True}, new_ts: {**base, "finished": False}}}  # ack_since 없음 = --ack 를 처음 켠 데몬
    path = tmp_path / "state.json"
    path.write_text(json.dumps(st), encoding="utf-8")
    obj = object.__new__(daemon.Inbound)
    obj.a = SimpleNamespace(ack=True, to_key="_desk", api_base="stub", channel="C1", mbox="stub")
    obj.token, obj.comm, obj.spool, obj.planner_seats, obj.state_path, obj.qpath = "fixture", tmp_path, tmp_path, "fixture", path, tmp_path / "absent"
    monkeypatch.setattr(obj, "_candidates", lambda st: [], raising=False)

    def crash_after_finished(state: dict) -> None:  # finished 저장 직후, ACK 직전에 죽는다
        path.write_text(json.dumps(state), encoding="utf-8")
        if state["ledger"][new_ts].get("finished"):
            raise KeyboardInterrupt("after finished save, before ACK")

    monkeypatch.setattr(obj, "_save", crash_after_finished, raising=False)
    with pytest.raises(KeyboardInterrupt):
        obj.run_pass()
    assert posts == [] and json.loads(path.read_text(encoding="utf-8"))["ack_since"]  # 경계는 전달 전에 이미 저장됐다
    monkeypatch.setattr(obj, "_save", lambda state: path.write_text(json.dumps(state), encoding="utf-8"), raising=False)
    obj.run_pass()  # 재시작
    led = json.loads(path.read_text(encoding="utf-8"))["ledger"]
    assert len(posts) == 1 and led[new_ts].get("ack_ts") and not led[new_ts].get("ack_skipped")  # 이번 모드의 새 글 ACK 1
    assert led[old_ts].get("ack_skipped") and not led[old_ts].get("ack_ts")  # 옛 finished 는 ACK 0 그대로
