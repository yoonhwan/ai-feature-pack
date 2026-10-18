"""이어가기 블록 + 단일 입구 byz_thread_post + 스레드 장부 (판정 404 · 설계 §8-b I1·report). 가짜 슬랙 API — 실제 호출 0.

실행: python3 -m pytest tests/scripts/test_thread_post.py -q -s
"""
import json

import pytest
from _proposal_fakes import make_md, slack  # noqa: F401 — slack fixture
from _thread_fakes import card, commit_all, ledger, resume_script

import byz_proposal_publish as bp
import byz_thread_post as tp
import resume_block as rb
import thread_ledger as lg

UID = "feature/F-x-proposal"
VERDICT = "## §4 최종 판정 — 줄바꿈 CSS 승인\n본문\n"


@pytest.fixture
def env(slack, tmp_path):  # noqa: F811
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n")
    (tmp_path / "hermes.env").write_text("SLACK_BOT_TOKEN=xoxb-secret-2\n")
    (tmp_path / "verdict.md").write_text(VERDICT, encoding="utf-8")
    return tmp_path


def run(env, slack, cmd, *extra, canon="없음", card_path=None, led=None):  # noqa: F811
    c = card_path or card(env)
    argv = [cmd, "--card", str(c), "--ledger", str(led or env / "threads.json"), "--token-file", str(env / "tok.env"),
            "--hermes-env", str(env / "hermes.env"), "--slack-base", slack.base, "--channel", "C1"]
    if cmd in ("start", "progress", "result"):
        argv += ["--issue", "#893", "--seat", "s#1", "--canon", canon, "--next", "오빠 결정", "--resume-script", str(resume_script(env))]
    return tp.main(argv + list(extra))


def started(env, slack):  # noqa: F811
    ledger(env)
    assert run(env, slack, "start", "--text", "제안서 발행") == 0


def test_block_needs_all_six_cells():
    ok = dict(issue="#1", card="c.md", seat="s#1", canon="없음", next_="x", resume="r")
    assert rb.block(**ok).count("\n") == 1
    for cell in ok:
        for bad in ("", "  ", None):
            with pytest.raises(rb.BlockError):
                rb.block(**{**ok, cell: bad})


def test_canon_ref_is_path_at_sha_and_refuses_uncommitted(tmp_path):
    f = tmp_path / "a" / "PLAN.md"
    f.parent.mkdir()
    f.write_text("x")
    with pytest.raises(rb.BlockError, match="git"):
        rb.canon_ref(f)
    commit_all(tmp_path)
    ref = rb.canon_ref(f)
    assert ref.startswith("a/PLAN.md@") and len(ref.split("@")[1]) == 8
    f.write_text("y")
    with pytest.raises(rb.BlockError, match="미커밋"):
        rb.canon_ref(f)


def test_start_posts_one_root_and_attachments_in_the_same_thread(env, slack, capsys):  # noqa: F811
    ledger(env)
    att = env / "p.md"
    att.write_text("md")
    assert run(env, slack, "start", "--text", "제안서 발행", "--file", str(att)) == 0
    root = slack.roots[0]
    print(f"[가짜 슬랙 로그] chat.postMessage 뿌리 1 ts={root['ts']} · 첨부 complete thread_ts={slack.files[0]['thread_ts']}")
    assert len(slack.roots) == 1 and slack.files[0]["thread_ts"] == root["ts"] and not slack.replies
    assert root["text"].split("\n")[0] == f"[작업상황] [{UID}]" and "↳ 이어가기 · Issue #893" in root["text"] and "재개: RESUME-CMD(s#1)" in root["text"]
    assert f"- 슬랙: C1 {root['ts']}" in card(env).read_text(encoding="utf-8")
    assert json.loads((env / "threads.json").read_text())[UID]["root_ts"] == root["ts"]
    assert "xoxp" not in capsys.readouterr().out


def test_second_start_is_rejected_without_posting(env, slack):  # noqa: F811
    started(env, slack)
    assert run(env, slack, "start", "--text", "again") == 1 and len(slack.msgs) == 1


def test_start_with_missing_cell_posts_nothing_and_leaves_the_card(env, slack):  # noqa: F811
    ledger(env)
    before = card(env).read_text(encoding="utf-8")
    assert run(env, slack, "start", "--text", "x", canon=str(env / "없는파일.md")) == 1
    assert slack.msgs == [] and card(env).read_text(encoding="utf-8") == before


def test_missing_or_corrupt_ledger_raises_and_is_never_auto_created(env, slack):  # noqa: F811
    assert run(env, slack, "start", "--text", "x") == 1 and slack.msgs == [] and not (env / "threads.json").exists()
    (env / "threads.json").write_text("{broken")
    assert run(env, slack, "start", "--text", "x") == 1 and slack.msgs == []
    (env / "fresh.json").unlink(missing_ok=True)
    assert tp.main(["--init", "--ledger", str(env / "fresh.json")]) == 0 and json.loads((env / "fresh.json").read_text()) == {}


def test_I1_ledger_write_fails_after_remote_post_then_repair(env, slack, monkeypatch):  # noqa: F811
    ledger(env)
    monkeypatch.setattr(lg, "create", lambda *a, **k: (_ for _ in ()).throw(lg.LedgerError("disk full")))
    assert run(env, slack, "start", "--text", "x") == 1 and len(slack.roots) == 1  # 원격은 성공, 장부는 실패
    monkeypatch.undo()
    assert run(env, slack, "check") == 3  # 카드 줄은 «게시 대상», 장부 불명
    assert run(env, slack, "repair") == 0 and len(slack.msgs) == 1  # 카드 줄 root_ts 로 복구 · 재발송 0
    assert run(env, slack, "check") == 1  # 게시 대상인데 결과 없음


def test_I1_attempt_only_line_repairs_from_channel_marker(env, slack):  # noqa: F811
    started(env, slack)
    (env / "threads.json").write_text("{}")
    c = card(env)
    c.write_text(c.read_text(encoding="utf-8").replace(f"- 슬랙: C1 {slack.roots[0]['ts']}", "- 슬랙: C1 · 시도 2026-10-08T13:40:00+09:00"), encoding="utf-8")
    assert run(env, slack, "check") == 3
    assert run(env, slack, "repair") == 0 and lg.get(env / "threads.json", UID)["root_ts"] == slack.roots[0]["ts"]
    slack.msgs.append(dict(slack.msgs[0], ts=str(float(slack.msgs[0]["ts"]) + 1)))  # 표식 글이 2건이면 사람 확인
    (env / "threads.json").write_text("{}")
    c.write_text(c.read_text(encoding="utf-8").replace(f"- 슬랙: C1 {slack.roots[0]['ts']}", "- 슬랙: C1 · 시도 2026-10-08T13:40:00+09:00"), encoding="utf-8")
    assert run(env, slack, "repair") == 1


def test_I1_deleted_key_is_unknown_and_card_without_slack_line_is_not_a_target(env, slack):  # noqa: F811
    started(env, slack)
    (env / "threads.json").write_text("{}")
    assert run(env, slack, "check") == 3
    plain = card(env, name="F-other")
    assert run(env, slack, "check", card_path=plain) == 0


def test_I1_same_unit_id_and_root_across_card_moves(env, slack):  # noqa: F811
    started(env, slack)
    old = card(env)
    new = env / "design/feature/indices/완성/F-x-proposal.md"
    new.parent.mkdir(parents=True)
    old.rename(new)
    assert run(env, slack, "progress", "--text", "착수", card_path=new) == 0
    rec = lg.get(env / "threads.json", UID)
    assert rec["root_ts"] == slack.roots[0]["ts"] and rec["card_path"] == str(new) and len(rec["progress"]) == 1
    assert slack.replies[0]["thread_ts"] == slack.roots[0]["ts"] and "↳ 이어가기" in slack.replies[0]["text"]


def test_result_uses_verdict_title_line_and_is_idempotent(env, slack):  # noqa: F811
    started(env, slack)
    v = f"{env / 'verdict.md'}#§4"
    assert run(env, slack, "result", "--verdict", v, "--landed", "abc1234") == 0
    r = slack.replies[0]["text"].split("\n")
    assert r[0] == f"[변경내용] [결과] {UID}" and r[1] == "§4 최종 판정 — 줄바꿈 CSS 승인" and r[2] == "랜딩 abc1234"
    assert run(env, slack, "check") == 0
    assert run(env, slack, "result", "--verdict", v) == 0 and len(slack.replies) == 1  # 이미 있음 → 재발송 0
    bare = card(env, name="F-bare")
    assert run(env, slack, "result", card_path=bare) == 1  # --verdict 없는 result 는 거부(결과 1줄은 판정문 제목 줄)


def test_result_ledger_failure_then_rerun_adopts_remote_marker_without_resend(env, slack, monkeypatch):  # noqa: F811
    started(env, slack)
    v = f"{env / 'verdict.md'}#§4"
    real = lg.update
    monkeypatch.setattr(lg, "update", lambda *a, **k: (_ for _ in ()).throw(lg.LedgerError("disk full")))
    assert run(env, slack, "result", "--verdict", v) == 1 and len(slack.replies) == 1
    monkeypatch.setattr(lg, "update", real)
    assert run(env, slack, "result", "--verdict", v) == 0 and len(slack.replies) == 1  # 표식 채택 · 장부만 채움
    assert len(lg.get(env / "threads.json", UID)["results"]) == 1 and run(env, slack, "check") == 0


def test_report_kind_cannot_be_set_by_the_tool_and_needs_no_result(env, slack):  # noqa: F811
    ledger(env, {"magazine/2026-10-08": {"channel": "C1", "root_ts": "1.0", "kind": "report", "card_path": "없음", "progress": [], "results": []}})
    c = card(env, team="harness", name="x")
    with pytest.raises(SystemExit):
        run(env, slack, "start", "--text", "x", "--kind", "report")
    assert "kind" not in tp.parse(["start", "--card", str(c), "--text", "x", "--issue", "1", "--seat", "s", "--canon", "없음", "--next", "n", "--resume-script", "r"]).__dict__
    with pytest.raises(lg.LedgerError):
        lg.create(env / "threads.json", "x/y", channel="C1", root_ts="2.0", kind="bogus", card_path="c")
    assert slack.msgs == []


def test_legacy_root_with_hermes_token_replies_in_the_old_thread_and_never_prints_it(env, slack, capsys):  # noqa: F811
    ledger(env)
    assert run(env, slack, "result", "--legacy-root", "1791419075.000100", "--bot", "hermes", "--unit-id", "feature/887-line-break",
               "--text", "판정 355 오빠 승인 · PR #894 main 6b5bcf0b7b") == 0
    m = slack.replies[0]
    assert m["thread_ts"] == "1791419075.000100" and m["text"].split("\n")[0] == "[변경내용] [결과] feature/887-line-break"
    assert lg.get(env / "threads.json", "feature/887-line-break")["results"]
    out = capsys.readouterr()
    assert "xoxb" not in out.out + out.err and "xoxp" not in out.out + out.err


def test_proposal_publish_appends_block_and_records_card_and_ledger(env, slack):  # noqa: F811
    md = make_md(env)
    commit_all(env)
    c, led = card(env, name="F-guest-proposal"), ledger(env)
    argv = [str(md), "--state", str(env / "st.json"), "--token-file", str(env / "tok.env"), "--slack-base", slack.base, "--channel", "C1",
            "--card", str(c), "--ledger", str(led), "--seat", "s#1", "--resume-script", str(resume_script(env)), "--issue", "#893"]
    assert bp.run(bp.parse_args(argv)) == 0
    root = slack.roots[0]
    assert root["text"].split("\n")[0] == "[작업상황] *제안서 feature/ko-line-break*" and "↳ 이어가기 · Issue #893" in root["text"] and "정본 design/feature/PROPOSAL-ko-line-break-20261008.md@" in root["text"]
    assert f"- 슬랙: C1 {root['ts']}" in c.read_text(encoding="utf-8")
    assert lg.get(led, "feature/F-guest-proposal")["root_ts"] == root["ts"]
    assert bp.run(bp.parse_args([*argv, "--revision", "r1"])) == 0 and "↳ 이어가기" in slack.replies[0]["text"]
    assert len(slack.roots) == 1


ATTEMPT = "- 슬랙: C1 · 시도 2026-10-10T11:08:00+09:00"


def attempt_only(env, ts):
    """게시는 됐는데 카드는 「시도」 줄 · 장부는 비어 있는 R81 사고 상태."""
    c = card(env)
    c.write_text(c.read_text(encoding="utf-8").replace(f"- 슬랙: C1 {ts}", ATTEMPT), encoding="utf-8")
    (env / "threads.json").write_text("{}")
    return c


def test_R81_repair_root_fills_card_line_and_ledger_from_a_root_post(env, slack):  # noqa: F811
    started(env, slack)
    ts = slack.roots[0]["ts"]
    slack.msgs[0]["text"] = "[작업상황] *제안서 v65/x*\n본문"  # 제안서 글은 첫 줄이 단위 표식과 다르다 — 지금의 repair 는 표식 0건(HUMAN)
    c = attempt_only(env, ts)
    assert run(env, slack, "repair") == 1
    assert run(env, slack, "repair", "--root", ts) == 0
    assert f"- 슬랙: C1 {ts}" in c.read_text(encoding="utf-8") and lg.get(env / "threads.json", UID)["root_ts"] == ts
    plain = card(env, name="F-no-line")
    assert run(env, slack, "repair", "--root", ts, card_path=plain) == 0 and f"- 슬랙: C1 {ts}" in plain.read_text(encoding="utf-8")


def test_R81_repair_root_rejects_a_reply_ts_and_writes_nothing(env, slack):  # noqa: F811
    started(env, slack)
    assert run(env, slack, "progress", "--text", "착수") == 0
    c = attempt_only(env, slack.roots[0]["ts"])
    before = c.read_text(encoding="utf-8")
    assert run(env, slack, "repair", "--root", slack.replies[0]["ts"]) == 1
    assert c.read_text(encoding="utf-8") == before and json.loads((env / "threads.json").read_text()) == {}


def test_R81_repair_root_rejects_card_with_existing_root_and_non_bot_post(env, slack):  # noqa: F811
    started(env, slack)
    ts = slack.roots[0]["ts"]
    assert run(env, slack, "repair", "--root", ts) == 1  # 카드에 이미 뿌리 ts — 지금처럼 거부
    slack.msgs.append({"ts": "1.500000", "text": "사람 글", "bot_id": "", "thread_ts": ""})
    c = attempt_only(env, ts)
    assert run(env, slack, "repair", "--root", "1.500000") == 1 and ATTEMPT in c.read_text(encoding="utf-8")
    assert run(env, slack, "repair", "--root", "9.999999") == 1  # 없는 글
