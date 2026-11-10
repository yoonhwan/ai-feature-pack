"""byz_mbox_slack_mirror — 가짜 Slack 서버·가짜 요약기로 exactly-once·스레드·사람 말 포맷·가드를 시험한다 (실 Slack·LLM 호출 0)."""
import json
import subprocess
import sys
from pathlib import Path

import pytest
from _slack_fakes import FAKE_SUMMARIZER, FakeSlack
from _thread_fakes import resume_script

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
SCRIPT = KIT / "byz_mbox_slack_mirror.py"
SEAT = r"^byz-planner-arch#\d+$"
INBOX = str(Path(__file__).resolve().parent / "_fake_inbox.sh")
TO = "byz-planner-arch#2"
R1294_BODY_224912 = "\n".join((
    "골좌표: 2 — 말풍선 정상화 — 강의",
    "[결정] 문서 PR 5918 착지 승인 요청(② 순수 이동 · 재요청): head f21434407decfabd3a4bfe62b921ee6cd888cdc9 (gh 재확인: OPEN · CLEAN · 3파일) · 카드 L86·L101·L103 진행→완성 R100 3개 · 내용 0 · base = ① 5917 착지 main be466043ba · 이게 착지돼야 나노 L86·L101·L103 ft-nano-close 가능(석 반납)",
    "비가역: 없음(문서 PR · 카드 이동)",
    "선례: 5917 착지(h5766)와 같은 문서 절차",
    "선택지: A) 5918 승인 h(추천) B) 보류",
))

@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


@pytest.fixture
def env(tmp_path: Path) -> Path:
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-test\n", encoding="utf-8")
    (tmp_path / "fake_sum.py").write_text(FAKE_SUMMARIZER, encoding="utf-8")
    resume_script(tmp_path)
    return tmp_path


@pytest.fixture
def run_env(tmp_path: Path) -> Path:
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-test\n", encoding="utf-8")
    (tmp_path / "fake_sum.py").write_text(FAKE_SUMMARIZER, encoding="utf-8")
    resume_script(tmp_path)
    return tmp_path


def rows_file(tmp: Path, *rows: tuple[int, str, str]) -> Path:
    (tmp / "seats-fixture.json").write_text(json.dumps({"src#1": {"role": "nano"}}), encoding="utf-8")  # r846 r2: 보낸 이 src#1 = 명부 좌석(질문을 열 수 있다)
    p = tmp / "mailbox.log.jsonl"
    with open(p, "a", encoding="utf-8") as f:
        for seq, to, body in rows:
            f.write(json.dumps({"seq": seq, "ts": "t", "to": to, "from": "src#1", "body": body}, ensure_ascii=False) + "\n")
    return p


def run(tmp: Path, slack: FakeSlack, *extra: str):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--project", "byz", "--mailbox", str(tmp / "mailbox.log.jsonl"),
         "--seat", SEAT, "--channel", "C1", "--repo", "o/r", "--state-dir", str(tmp / "st"), "--token-file", str(tmp / "tok.env"),
         "--api-base", slack.base, "--mention", "U0AC2JF0M7D", "--once", "--inbox-bin", INBOX, "--resume-script", str(tmp / "resume.sh"),
         "--summarizer-cmd", f"{sys.executable} {tmp / 'fake_sum.py'}", "--planner-seats", str(tmp / "seats-planner.json"), *extra],
        capture_output=True, text=True, timeout=60,
    )


def start(env: Path, slack: FakeSlack) -> None:
    """baseline 만 만든다(첫 실행은 과거를 쏟아내지 않는다)."""
    rows_file(env, (1, TO, "옛 보고"))
    assert run(env, slack).returncode == 0 and slack.msgs == []


def state(env: Path) -> dict:
    return json.loads((env / "st" / "byz_mbox_slack_mirror.byz.json").read_text(encoding="utf-8"))


def threads(env: Path) -> dict:
    return json.loads((env / "st" / "byz_slack_threads.C1.json").read_text(encoding="utf-8"))["threads"]


def append_row(env: Path, seq: int, to: str, sender: str, body: str) -> None:
    with (env / "mailbox.log.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps({"seq": seq, "ts": "t", "to": to, "from": sender, "body": body}, ensure_ascii=False) + "\n")


def test_first_run_is_baseline_then_root_and_reply_once(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[a->b] 새 보고 3줄입니다."), (3, "other#1", "남의 것"))
    assert run(env, slack).returncode == 0
    assert len(slack.roots) == 1 and slack.roots[0]["text"].startswith("[작업상황] src 시작 — 요약:")
    (reply,) = slack.replies(slack.roots[0])
    assert "bodies/2.txt@mbox" in reply["text"] and "담당 src#1" in reply["text"]
    assert run(env, slack).returncode == 0
    assert len(slack.msgs) == 2  # 같은 seq 두 번 0 · 루트도 두 번 0


def test_reply_is_two_human_lines_plus_two_block_lines_without_machine_tokens(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "ⓒ 미러 설치 완료 launchd pid 81977"))
    run(env, slack)
    lines = slack.replies(slack.roots[0])[0]["text"].split("\n")
    assert len(lines) == 4 and lines[3] == "↳ 다음: 없음 · 재개: RESUME-CMD(src#1)"
    assert lines[1] == "할 일 없음" and lines[2].startswith("↳ 이어가기 · Issue 없음 · 카드 없음 · 담당 src#1 · 정본 bodies/2.txt@mbox")
    whole = "\n".join(m["text"] for m in slack.msgs)
    assert not any(tok in whole for tok in ("[보고]", "★", "✅", "내용:"))


def test_hil_reply_mentions_fixed_user_and_body_mentions_are_neutralized(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[HIL] <!channel> <@UEVIL> & 판정 필요"))
    assert run(env, slack).returncode == 0
    reply = slack.replies(slack.roots[0])[0]["text"]
    lines = reply.split("\n")  # 판정 497: 답장 요구 0 — 멘션은 결정 자리 줄에만
    assert lines[1] == "정할 것: 전문 참고" and lines[2].startswith("<@U0AC2JF0M7D> 결정 자리:") and "답해 주세요" not in reply
    whole = "\n".join(m["text"] for m in slack.msgs)
    assert "<!channel>" not in whole and "<@UEVIL>" not in whole and "&lt;!channel&gt;" in whole


def test_one_issue_one_thread_and_pr_or_seq_numbers_are_not_confused(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "이슈 #799 수정 시작"), (3, TO, "#799 시험 통과"), (4, TO, "PR #812 머지"), (5, TO, "메일 #56635 인용만 있음"))
    assert run(env, slack).returncode == 0
    keys = [m["text"].split(" 시작")[0] for m in slack.roots]
    assert keys == ["[작업상황] #799", "[작업상황] #812", "[작업상황] src"]  # 5자리 seq 는 키가 아니다 → 좌석 스레드
    assert len(slack.replies(slack.roots[0])) == 2  # #799 두 건은 같은 스레드
    assert set(threads(env)) == {"#799", "#812", "src"}


def test_thread_map_persists_across_runs(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "#799 첫 보고"))
    run(env, slack)
    rows_file(env, (3, TO, "#799 둘째 보고"))
    run(env, slack)
    assert len(slack.roots) == 1 and len(slack.replies(slack.roots[0])) == 2


def test_slack_error_raises_then_recovers_without_duplicates(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "#799 보고"))
    slack.fail_post = True
    r = run(env, slack)
    assert r.returncode == 1 and "channel_not_found" in r.stderr and slack.msgs == []
    slack.fail_post = False
    assert run(env, slack).returncode == 0
    assert len(slack.roots) == 1 and len(slack.replies(slack.roots[0])) == 1


def test_crash_after_reply_before_marker_does_not_duplicate(env: Path, slack: FakeSlack):
    start(env, slack)
    slack.msgs += [{"ts": "1.0", "text": "#799 시작 — x", "thread_ts": ""},
                   {"ts": "2.0", "text": "문장\n할 일 없음\n(src#1 · #2)", "thread_ts": "1.0"}]
    pending = {"id": "#2", "seq": 2, "key": "#799", "what": "x", "text": "문장\n할 일 없음\n(src#1 · #2)"}
    sp = env / "st" / "byz_mbox_slack_mirror.byz.json"
    sp.write_text(json.dumps({"last_seq": 1, "pending": pending, "threads": {"#799": "1.0"}}), encoding="utf-8")
    assert run(env, slack).returncode == 0
    assert len(slack.msgs) == 2 and state(env)["last_seq"] == 2


def test_crash_after_root_before_map_save_reuses_the_root(env: Path, slack: FakeSlack):
    start(env, slack)
    slack.msgs.append({"ts": "1.0", "text": "#799 시작 — x", "thread_ts": ""})  # 루트만 올라간 상태
    pending = {"id": "#2", "seq": 2, "key": "#799", "what": "x", "text": "문장\n할 일 없음\n(src#1 · #2)"}
    sp = env / "st" / "byz_mbox_slack_mirror.byz.json"
    sp.write_text(json.dumps({"last_seq": 1, "pending": pending, "threads": {}}), encoding="utf-8")
    assert run(env, slack).returncode == 0
    assert len(slack.roots) == 1 and len(slack.replies(slack.roots[0])) == 1  # 루트 두 번째 0


def test_read_failure_on_resume_raises_without_posting(env: Path, slack: FakeSlack):
    start(env, slack)
    pending = {"id": "#2", "seq": 2, "key": "#799", "what": "x", "text": "t"}
    sp = env / "st" / "byz_mbox_slack_mirror.byz.json"
    sp.write_text(json.dumps({"last_seq": 1, "pending": pending, "threads": {}}), encoding="utf-8")
    slack.fail_read = True
    r = run(env, slack)
    assert r.returncode == 1 and "missing_scope" in r.stderr and slack.msgs == []  # 중복보다 지연


def test_seq_gap_goes_to_the_other_thread_once(env: Path, slack: FakeSlack):
    rows_file(env, (10, TO, "x"))
    assert run(env, slack).returncode == 0
    rows_file(env, (13, TO, "공백 뒤 보고"))  # 11·12 가 사본에 없다
    assert run(env, slack).returncode == 0
    assert [m["text"].split(" 시작")[0] for m in slack.roots] == ["[작업상황] 기타", "[작업상황] src"]
    gap = slack.replies(slack.roots[0])[0]["text"]
    assert "#GAP-11-12" in gap and "2건" in gap
    assert run(env, slack).returncode == 0 and len(slack.msgs) == 4  # 공백 알림도 1회


@pytest.mark.parametrize("trigger", ["SUMFAIL", "SUMJUNK"])
def test_summary_failure_falls_back_visibly_without_losing_the_report(env: Path, slack: FakeSlack, trigger: str):
    start(env, slack)
    rows_file(env, (2, TO, f"{trigger} 원문 첫 문장이에요. 둘째 문장."))
    r = run(env, slack)
    assert r.returncode == 0 and "ERROR: 요약 실패 seq=2" in r.stderr  # 조용하지 않다
    lines = slack.replies(slack.roots[0])[0]["text"].split("\n")
    assert lines[0].startswith(f"[작업상황] {trigger} 원문 첫 문장이에요.") and "둘째" not in lines[0]
    assert "원문 그대로" in lines[2]


def test_missing_token_raises(env: Path, slack: FakeSlack):
    rows_file(env, (1, TO, "x"))
    (env / "tok.env").write_text("OTHER=1\n", encoding="utf-8")
    r = run(env, slack)
    assert r.returncode == 1 and "YOONHWAN_BOT_TOKEN" in r.stderr and "xoxp" not in r.stderr


def test_dry_run_prints_without_http_or_state(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "#799 미리보기"), (3, TO, "#799 둘째"), (4, "other#1", "남의 것"), (5, TO, "#799 셋째"))
    (env / "tok.env").unlink()  # dry-run 은 토큰 불필요
    r = run(env, slack, "--dry-run")
    assert r.returncode == 0 and "[thread #799]" in r.stdout and slack.msgs == []
    assert "GAP" not in r.stdout and r.stdout.count("[thread #799]") == 3  # 연속 행에 가짜 공백 0
    assert state(env)["last_seq"] == 1


def test_rotation_files_are_read_in_order(env: Path, slack: FakeSlack):
    start(env, slack)
    (env / "mailbox.log.jsonl").rename(env / "mailbox.log.jsonl.1")  # mbox.py 회전
    rows_file(env, (2, TO, "회전 뒤 첫 보고"))
    assert run(env, slack).returncode == 0
    assert len(slack.roots) == 1 and len(slack.replies(slack.roots[0])) == 1


def test_thread_map_is_capped(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    sys.path.insert(0, str(KIT))
    import mirror_deliver as md

    n = {"i": 0}

    def fake_post(*_a: object, **_k: object) -> str:
        n["i"] += 1
        return f"{n['i']}.0"

    monkeypatch.setattr(md.lib, "post", fake_post)
    d = md.Deliverer("http://unused", "x", "C1", tmp_path / "t.json", max_threads=3)
    for i in range(5):
        d.thread_ts({"key": f"#{i}", "what": "w"}, resume=False)
    assert list(md.load_threads(tmp_path / "t.json")) == ["#2", "#3", "#4"]  # 오래된 키부터 밀려남


def test_old_state_threads_seed_the_shared_map_once(env: Path, slack: FakeSlack):
    start(env, slack)
    slack.msgs.append({"ts": "1.0", "text": "#799 시작 — x", "thread_ts": ""})
    sp = env / "st" / "byz_mbox_slack_mirror.byz.json"
    sp.write_text(json.dumps({"last_seq": 1, "pending": None, "threads": {"#799": "1.0"}}), encoding="utf-8")
    rows_file(env, (2, TO, "#799 이어지는 보고"))
    assert run(env, slack).returncode == 0
    assert len(slack.roots) == 1 and threads(env) == {"#799": "1.0"}  # 루트 두 번째 0 · 이관됨


def test_two_processes_share_one_thread_per_key(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    sys.path.insert(0, str(KIT))
    import mirror_deliver as md

    posted: list[str] = []
    monkeypatch.setattr(md.lib, "post", lambda *_a, **_k: posted.append("r") or f"{len(posted)}.0")
    path = tmp_path / "t.json"
    a, b = md.Deliverer("u", "x", "C1", path), md.Deliverer("u", "x", "C1", path)
    assert a.thread_ts({"key": "#9", "what": "w"}, False) == b.thread_ts({"key": "#9", "what": "w"}, False)
    assert len(posted) == 1  # 같은 키의 루트는 하나


def test_seat_name_hash_is_not_an_issue_key(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[a->b] 부팅 보고 (승계 #0->#1) 모델 확인 · 이슈 #820 언급은 키가 아니다? 아니 키다"))
    rows_file(env, (3, TO, "승계 #0->#1 부팅 보고만 있음"))
    assert run(env, slack).returncode == 0
    assert [m["text"].split(" 시작")[0] for m in slack.roots] == ["[작업상황] #820", "[작업상황] src"]  # #0 가짜 작업 0


def test_relay_full_body_is_posted_in_the_thread_neutralized(env: Path, slack: FakeSlack):
    import os
    import uuid

    full = Path("/tmp/mbox") / f"pytest-{uuid.uuid4().hex}.txt"
    full.parent.mkdir(exist_ok=True)
    full.write_text("체크리스트 1\n체크리스트 2 <!channel>\n", encoding="utf-8")
    try:
        start(env, slack)
        rows_file(env, (2, TO, f"[#819] 체크리스트 1장\n상세(전문): {full} (30 B)"))
        assert run(env, slack).returncode == 0
        reply = slack.replies(slack.roots[0])[0]["text"]
        assert slack.roots[0]["text"].startswith("[작업상황] #819 시작")
        assert "> 체크리스트 1" in reply and "> 체크리스트 2 &lt;!channel&gt;" in reply and "<!channel>" not in reply
    finally:
        os.unlink(full)


def test_root_and_reply_carry_github_urls_with_comment_anchor(env: Path, slack: FakeSlack):
    start(env, slack)
    c = "https://github.com/o/r/issues/819#issuecomment-5978038"
    rows_file(env, (2, TO, "#819 체크리스트를 코멘트로 올렸어요"), (3, TO, f"#819 코멘트 갱신 {c}"))
    assert run(env, slack).returncode == 0
    assert slack.roots[0]["text"].endswith("\nhttps://github.com/o/r/issues/819")  # 루트 = Issue URL
    first, second = [m["text"] for m in slack.replies(slack.roots[0])]
    assert "링크: https://github.com/o/r/issues/819" in first  # 번호만 쓰지 않는다
    assert f"링크: {c}" in second  # 코멘트면 앵커까지


def questions(env: Path) -> dict:
    return json.loads((env / "st" / "byz_slack_questions.C1.json").read_text(encoding="utf-8"))


def test_hil_card_shows_options_registers_open_question_and_board(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[HIL] #820 어느 쪽으로 갈까요?\n1) 폴링으로 간다\n2) 소켓 모드로 간다\n3. 보류"))
    assert run(env, slack).returncode == 0
    card = slack.replies(slack.roots[0])[0]["text"]
    assert "1) 폴링으로 간다" in card and "2) 소켓 모드로 간다" in card and "3) 보류" in card
    assert "선택지(참고): 1) 폴링으로 간다 2) 소켓 모드로 간다 3) 보류" in card  # 판정 497: 답하는 법 문구 삭제 · 선택지는 참고 한 줄
    assert "답해 주세요" not in card and "<@U0AC2JF0M7D> 결정 자리:" in card
    q = questions(env)
    assert list(q["open"]) == ["2"] and q["open"]["2"]["seat"] == "src#1" and q["open"]["2"]["options"][0] == "폴링으로 간다"
    board = next(m for m in slack.msgs if m["ts"] == q["meta"]["board_ts"])
    assert board["text"].startswith("[상태] 결정 대기 1건 — 결정 자리:")  # 판정 497: 보드 머리 = [상태] 결정 대기 N건


def test_hil_without_options_asks_for_a_free_line_and_report_makes_no_question(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[HIL] #820 이름을 정해 주세요"), (3, TO, "#820 그냥 보고"))
    assert run(env, slack).returncode == 0
    card = slack.replies(slack.roots[0])[0]["text"]  # 판정 497: 슬랙은 읽기 전용 — 답장 요구 문구 0, 결정 자리만
    assert "답해 주세요" not in card and "한 줄로" not in card and "결정 자리:" in card
    assert list(questions(env)["open"]) == ["2"]


def test_delivered_question_closes_only_on_a_report_newer_than_the_answer(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[HIL] #820 어느 쪽?\n1) a\n2) b"))
    assert run(env, slack).returncode == 0
    qp = env / "st" / "byz_slack_questions.C1.json"
    import mirror_questions as mq
    mq.set_delivered(qp, 2, "1.0", 50)  # 답이 mbox seq 50 으로 전달됨
    rows_file(env, (3, TO, "#820 답 이전에 큐에 있던 옛 보고"))
    assert run(env, slack).returncode == 0
    assert "2" in questions(env)["open"]  # seq 3 < 50 → 닫지 않는다
    rows = [{"seq": 51, "ts": "t", "to": TO, "from": "src#1", "body": "#820 답대로 진행했어요"}]
    with open(env / "mailbox.log.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(rows[0], ensure_ascii=False) + "\n")
    assert run(env, slack).returncode == 0
    assert "2" not in questions(env)["open"] and "2" in questions(env)["resolved"]


def test_rows_from_slack_oppa_are_not_echoed_back_to_slack(env: Path, slack: FakeSlack):
    start(env, slack)
    p = rows_file(env, (2, TO, "[slack-oppa->x] 오빠(Slack) 발화 — 원문:\n머지 체크하라고\n(slack:1.0:x)"), (3, TO, "#820 일반 보고"))
    lines = p.read_text(encoding="utf-8").splitlines()
    first = {**json.loads(lines[1]), "from": "slack-oppa"}
    p.write_text(lines[0] + "\n" + json.dumps(first, ensure_ascii=False) + "\n" + lines[2] + "\n", encoding="utf-8")
    assert run(env, slack).returncode == 0
    assert len(slack.roots) == 1 and slack.roots[0]["text"].startswith("[작업상황] #820 시작")  # slack-oppa 루트 0
    assert state(env)["last_seq"] == 3  # 건너뛰되 처리선은 전진(가짜 공백 0)


def test_hil_is_mirrored_to_desk_with_mention(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[HIL] #820 어느 쪽으로 할까요?\n1) A\n2) B"))
    r = run(env, slack, "--desk-channel", "C2")
    assert r.returncode == 0, r.stderr
    roots = [m for m in slack.roots if m["text"].startswith(("[작업상황] #820 시작", "[결정] "))]
    assert len(roots) == 2 and all(len(slack.replies(root)) == 1 for root in roots)
    assert any("선택지(참고): 1) A 2) B" in reply["text"] for root in roots for reply in slack.replies(root))
    assert "<@U0AC2JF0M7D>" in "\n".join(m["text"] for m in slack.msgs)
    assert "#820" in json.loads((env / "st" / "byz_slack_threads.C2.json").read_text())["threads"]


@pytest.mark.parametrize("body", ["[긴급] API 장애 시작", "[결정 대기 경보] 선택이 필요합니다"])
def test_alarm_sender_is_urgent_in_mirror_and_copied_to_desk(env: Path, slack: FakeSlack, body: str):
    start(env, slack)
    rows_file(env, (2, TO, body))
    sender = "ft-api-outage" if body.startswith("[긴급]") else "ft-decision-count"
    p = env / "mailbox.log.jsonl"
    rows = [json.loads(line) for line in p.read_text(encoding="utf-8").splitlines()]
    rows[1]["from"] = sender
    p.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    r = run(env, slack, "--desk-channel", "C2")
    assert r.returncode == 0, r.stderr
    assert len(slack.roots) == 2 and len(slack.msgs) == 4
    assert all("[긴급]" in m["text"] for m in slack.msgs if m["thread_ts"])


def test_urgent_sender_to_desk_is_selected_by_urgent_seat(env: Path, slack: FakeSlack):
    start(env, slack)
    append_row(env, 2, "byz-planner-desk-claude#92", "ft-api-outage", "[API 장애 시작 14:33] 오류")
    r = run(env, slack, "--desk-channel", "C2", "--urgent-seat", r"^byz-planner-desk-claude#\d+$")
    assert r.returncode == 0, r.stderr
    assert len(slack.roots) == 2 and "[긴급]" in "\n".join(m["text"] for m in slack.msgs)


def test_explicit_urgent_row_to_desk_is_mirrored_in_same_pass(env: Path, slack: FakeSlack):
    start(env, slack)
    append_row(env, 2, "byz-planner-desk-claude#92", "src#1", "[긴급] API 장애 시작")
    r = run(env, slack, "--desk-channel", "C2", "--urgent-seat", r"^byz-planner-desk-claude#\d+$")
    assert r.returncode == 0, r.stderr
    assert len(slack.roots) == 2 and all("[긴급]" in m["text"] for m in slack.msgs if m["thread_ts"])


def test_explicit_urgent_row_without_desk_channel_keeps_single_delivery(env: Path, slack: FakeSlack):
    start(env, slack)
    append_row(env, 2, "byz-planner-desk-claude#92", "src#1", "[긴급] API 장애 시작")
    r = run(env, slack, "--urgent-seat", r"^byz-planner-desk-claude#\d+$")
    assert r.returncode == 0, r.stderr
    assert len(slack.roots) == 1 and len(slack.msgs) == 2


def test_block_team_report_is_mirrored_with_person_mention(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[BLOCK] <@U0AC2JF0M7D> 이슈 #820 긴급 조치가 필요합니다"))
    r = run(env, slack, "--desk-channel", "C2")
    assert r.returncode == 0, r.stderr
    roots = [m for m in slack.roots if m["text"].startswith("[작업상황] #820 시작")]
    desk_ts = json.loads((env / "st" / "byz_slack_threads.C2.json").read_text())["threads"]["#820"]
    desk_root = next(root for root in roots if root["ts"] == desk_ts)
    assert len(roots) == 2 and "<@U0AC2JF0M7D>" in slack.replies(desk_root)[0]["text"]


def test_nonurgent_rows_and_missing_desk_channel_keep_single_delivery(env: Path, slack: FakeSlack):
    start(env, slack)
    rows_file(env, (2, TO, "[정리] 정상 보고"))
    r = run(env, slack, "--desk-channel", "C2")
    assert r.returncode == 0, r.stderr
    assert len(slack.roots) == 1 and len(slack.msgs) == 2


def test_resume_checks_markers_in_both_channels_before_reposting(run_env: Path, slack: FakeSlack):
    start(run_env, slack)
    rows_file(run_env, (2, TO, "[BLOCK] #820 재시작 뒤 확인"))
    r = run(run_env, slack, "--desk-channel", "C2")
    assert r.returncode == 0, r.stderr
    before = len(slack.msgs)
    st = state(run_env)
    st.update(last_seq=1, pending={"id": "#2", "marker": "bodies/2.txt@mbox", "seq": 2, "key": "#820", "what": "확인",
                                   "text": slack.msgs[-1]["text"], "desk_dup": True, "threads": {}, "done": []})
    (run_env / "st" / "byz_mbox_slack_mirror.byz.json").write_text(json.dumps(st), encoding="utf-8")
    r = run(run_env, slack, "--desk-channel", "C2")
    assert r.returncode == 0, r.stderr
    assert len(slack.msgs) == before


def test_team_roots_resume_after_0800_after_main_post_before_done_save(tmp_path: Path, slack: FakeSlack, monkeypatch):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.path.insert(0, str(KIT))
    from types import SimpleNamespace
    from _team_fakes import World, kst
    import mirror_desk
    world = World(tmp_path, slack, labels={820: ["team:harness"]})
    item = world.item("#820", "#2", "긴급 확인", marker="bodies/2.txt@mbox", desk_dup=True)
    item["text"] += "\nbodies/2.txt@mbox"
    args = SimpleNamespace(desk_channel="C2", desk_mention="U0AC2JF0M7D", mention="U0AC2JF0M7D",
                           api_base=slack.base, state_dir=str(tmp_path))
    desk = mirror_desk.Desk(args, "tok")
    saves = []
    def send_main(row, resume, ts, ctx):
        world.deliv.send_fixed(row, ts, resume, ctx)
    send_fixed = world.deliv.send_fixed
    def crash_after_main_post(row, ts, resume, ctx):
        send_fixed(row, ts, resume, ctx)
        raise RuntimeError("crash after main POST")
    monkeypatch.setattr(world.deliv, "send_fixed", crash_after_main_post)
    with pytest.raises(RuntimeError, match="crash after main POST"):
        desk.send_both(world.deliv, item, False, lambda: saves.append(dict(item)), send_main)
    assert item["done"] == [] and "main" in item["threads"]
    old_day = world.teams.route(item).day
    world.clock.t = kst(2026, 10, 10, 9, 0)
    world.rebuild()
    assert world.teams.route(item).day != old_day
    desk.send_both(world.deliv, item, True, lambda: saves.append(dict(item)), send_main)
    team_roots = [root for root in slack.roots if "team:harness:" in root["text"]]
    main_posts = [m for root in team_roots for m in slack.replies(root) if "bodies/2.txt@mbox" in m["text"]]
    desk_ts = json.loads((tmp_path / "byz_slack_threads.C2.json").read_text())["threads"]["#820"]
    desk_root = next(m for m in slack.roots if m["ts"] == desk_ts)
    desk_posts = [m for m in slack.replies(desk_root) if "bodies/2.txt@mbox" in m["text"]]
    assert len(team_roots) == 1 and len(main_posts) == 1 and len(desk_posts) == 1 and "desk" in item["done"]


def test_desk_mention_is_removed_only_for_zero_decision_summary():
    sys.path.insert(0, str(KIT))
    import mirror_desk
    zero = "<@U0AC2JF0M7D> [정리] 할 일 없음 · 사람 결정 0"
    work = "<@U0AC2JF0M7D> [정리] 실행 부탁 · h5701 실행 부탁"
    plain = "<@U0AC2JF0M7D> 다른 건 할 일 없음. 오빠는 담당자에게 전화해 주세요."
    assert mirror_desk.desk_text(zero, "U0AC2JF0M7D") == "[정리] 할 일 없음 · 사람 결정 0"
    assert mirror_desk.desk_text(work, "U0AC2JF0M7D") == work
    assert mirror_desk.desk_text(plain, "U0AC2JF0M7D") == plain


def test_resume_marker_on_later_thread_page_prevents_duplicate(tmp_path: Path, slack: FakeSlack):
    sys.path.insert(0, str(KIT))
    import mirror_deliver
    root = slack.human("thread root")
    for i in range(120):
        slack.human(f"older reply {i}", root)
    slack.human("bodies/2.txt@mbox", root)
    before = len(slack.msgs)
    deliverer = mirror_deliver.Deliverer(slack.base, "token", "C1", tmp_path / "threads.json")
    deliverer._reply({"id": "#2", "marker": "bodies/2.txt@mbox"}, root, True, "would duplicate")
    assert len(slack.msgs) == before


def test_actual_decision_alarm_generator_output_is_mirrored(tmp_path: Path, run_env: Path, slack: FakeSlack):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import test_decision_count as decision_count
    start(run_env, slack)
    alarm_env = tmp_path / "decision"
    alarm_env.mkdir()
    fixture = decision_count.make_env(alarm_env)
    decision_count.put(fixture, [decision_count.row(7, "④", "byz-graphics-master-claude#3", ago=31)])
    generated = decision_count.run(fixture, "--alarm")
    assert generated.returncode == 0, generated.stderr
    args = (fixture["root"] / "mbox.log").read_text(encoding="utf-8").split("\n", 1)[0].split(" ", 3)
    assert args[2] == "ft-decision-count" and args[3].startswith("[결정 대기 경보]")
    append_row(run_env, 2, TO, args[2], args[3])
    r = run(run_env, slack, "--desk-channel", "C2")
    assert r.returncode == 0, r.stderr
    assert len(slack.roots) == 2 and all("[긴급]" in m["text"] for m in slack.msgs if m["thread_ts"])


def test_actual_api_outage_generator_to_desk_is_mirrored(tmp_path: Path, run_env: Path, slack: FakeSlack, monkeypatch):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import test_ft_api_outage as api_outage
    desk_seat = "byz-planner-desk-claude#92"
    monkeypatch.setattr(api_outage, "PLANNER", desk_seat)
    start(run_env, slack)
    outage_root = tmp_path / "outage"
    outage_root.mkdir()
    fixture = api_outage._outage_fx(outage_root)
    generated = fixture.run(api_outage.T0)
    assert generated.returncode == 0, generated.stderr
    dest, sender, body = next(call for call in fixture.calls() if call[0] == desk_seat)
    assert sender == "ft-api-outage" and body.startswith("[API 장애 시작")
    append_row(run_env, 2, dest, sender, body)
    r = run(run_env, slack, "--desk-channel", "C2", "--urgent-seat", r"^byz-planner-desk-claude#\d+$")
    assert r.returncode == 0, r.stderr
    assert len(slack.roots) == 2 and "[긴급]" in "\n".join(m["text"] for m in slack.msgs)


def test_actual_api_outage_to_cfo_keeps_queue_and_message_unchanged(tmp_path: Path, run_env: Path,
                                                                   slack: FakeSlack, monkeypatch):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import test_ft_api_outage as api_outage
    cfo = "byz-cfo-master-claude#1"
    monkeypatch.setattr(api_outage, "PLANNER", cfo)
    start(run_env, slack)
    root = tmp_path / "cfo-outage"
    root.mkdir()
    fixture = api_outage._outage_fx(root)
    generated = fixture.run(api_outage.T0)
    assert generated.returncode == 0, generated.stderr
    dest, sender, body = next(call for call in fixture.calls() if call[0] == cfo)
    queue = tmp_path / "cfo-queue.jsonl"
    queue.write_text("keep-1\nkeep-2\n", encoding="utf-8")
    before = queue.read_bytes()
    append_row(run_env, 2, dest, sender, body)
    r = run(run_env, slack, "--desk-channel", "C2", "--urgent-seat", r"^byz-planner-desk-claude#\d+$")
    assert r.returncode == 0, r.stderr
    assert body.startswith("[API 장애 시작") and queue.read_bytes() == before and slack.msgs == []


def test_I2_block_issue_and_card_cells_are_none_whatever_the_body_quotes(env: Path, slack: FakeSlack):
    """본문 머리 발주 #seq · PR+Issue 혼합 · 이전 카드 인용 · 여러 단위 → 정형 필드만 권위: Issue·카드 칸 전부 `없음`(DA §4)."""
    start(env, slack)
    rows_file(env, (2, TO, "[발주 #62227] 이슈 #799 PR #812 카드 design/feature/indices/진행/F-old.md 이전 #801 도 보라"))
    assert run(env, slack).returncode == 0
    text = slack.replies(slack.roots[0])[0]["text"]
    assert "↳ 이어가기 · Issue 없음 · 카드 없음 · 담당 src#1 · 정본 bodies/2.txt@mbox" in text
    assert text.count("Issue ") == 1 and "F-old" not in text.split("↳ 이어가기")[1]  # 블록 안에 본문 인용 0


def test_r1294_decision_body_keeps_question_format_in_desk(env: Path, slack: FakeSlack):
    start(env, slack)
    append_row(env, 2, TO, "byz-lecture-master-claude#201", R1294_BODY_224912)
    result = run(env, slack, "--desk-channel", "C2")
    assert result.returncode == 0, result.stderr
    desk_root = next(message for message in slack.roots if message["channel"] == "C2")
    (reply,) = slack.replies(desk_root)
    assert reply["text"].startswith("[이슈보고]")
    assert "정할 것:" in reply["text"] and "할 일 없음" not in reply["text"]
    assert "선택지: A) 5918 승인 h(추천) B) 보류" in reply["text"]


def test_r1297_decision_root_uses_decision_head(env: Path, slack: FakeSlack):
    start(env, slack)
    append_row(env, 2, TO, "byz-lecture-master-claude#201", R1294_BODY_224912)
    result = run(env, slack, "--desk-channel", "C2")
    assert result.returncode == 0, result.stderr
    root = next(message for message in slack.roots if message["channel"] == "C2")
    assert root["text"].startswith("[결정] ")
    assert "시작 —" not in root["text"]
    assert "정할 것: 전문 참고" in root["text"]
    assert "선택지: A) 5918 승인 h(추천) B) 보류" in root["text"]
    main_root = next(message for message in slack.roots if message["channel"] == "C1")
    assert main_root["text"].startswith("[작업상황] ") and " 시작 —" in main_root["text"]


def test_r1297_root_text_urgent_kind_and_default():
    sys.path.insert(0, str(KIT))
    import mirror_lib as lib

    assert lib.root_text("#225309", "작업이 멈췄어요", kind="긴급").startswith("[긴급] 작업이 멈췄어요")
    assert lib.root_text("#225309", "일반 진행").startswith("[작업상황] #225309 시작 — 일반 진행")


def test_r1297_explicit_options_line_fallback_only_when_needed(env: Path, slack: FakeSlack):
    start(env, slack)
    body = "\n".join(("골좌표: 5 — 선택지 줄 미러", "[결정] 진행 방식을 정해 주세요?", "선택지: 지금 착수 / 다음 회차"))
    append_row(env, 2, TO, "byz-lecture-master-claude#201", body)
    result = run(env, slack, "--desk-channel", "C2")
    assert result.returncode == 0, result.stderr
    root = next(message for message in slack.roots if message["channel"] == "C2")
    (reply,) = slack.replies(root)
    assert "선택지: 지금 착수 / 다음 회차" in reply["text"]


def test_r1297_summary_notice_is_not_copied_to_desk(env: Path, slack: FakeSlack):
    start(env, slack)
    append_row(env, 2, TO, "ft-card-assign-watch", "[정리] 배정 감시 판정 불가 묶음 2026-11-01 2회")
    result = run(env, slack, "--desk-channel", "C2")
    assert result.returncode == 0, result.stderr
    assert not any(message["channel"] == "C2" for message in slack.roots)
