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


def test_I2_block_issue_and_card_cells_are_none_whatever_the_body_quotes(env: Path, slack: FakeSlack):
    """본문 머리 발주 #seq · PR+Issue 혼합 · 이전 카드 인용 · 여러 단위 → 정형 필드만 권위: Issue·카드 칸 전부 `없음`(DA §4)."""
    start(env, slack)
    rows_file(env, (2, TO, "[발주 #62227] 이슈 #799 PR #812 카드 design/feature/indices/진행/F-old.md 이전 #801 도 보라"))
    assert run(env, slack).returncode == 0
    text = slack.replies(slack.roots[0])[0]["text"]
    assert "↳ 이어가기 · Issue 없음 · 카드 없음 · 담당 src#1 · 정본 bodies/2.txt@mbox" in text
    assert text.count("Issue ") == 1 and "F-old" not in text.split("↳ 이어가기")[1]  # 블록 안에 본문 인용 0
