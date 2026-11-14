"""post_guard — 게시 «전» 비밀·내부어 검사 (R205 · 설계 §5). 가짜 슬랙 API — 실제 호출 0 · 걸리면 게시 0 + rc≠0.

실행: python3 -m pytest tests/scripts/test_post_guard.py -q
"""
import logging
import os
import time

import pytest
from _proposal_fakes import slack  # noqa: F401 — slack fixture (키트 경로를 sys.path 에)
from _thread_fakes import (  # noqa: F401 — status_head_file 은 autouse fixture 로 등록된다(r1089)
    STATUS_HEAD,
    body_after_status_head,
    card,
    ledger,
    resume_script,
    status_head_file,
)

import byz_thread_post as tp
import post_guard as pg
import status_head as sh

UID = "feature/F-x-proposal"
SECRET = {  # 1묶음 — 패턴 이름 : 샘플
    "slack-token": "토큰은 xoxb-123 입니다", "aws-key": "key AKIAABCDEFGHIJKLMNOP", "private-key": "-----BEGIN RSA PRIVATE KEY-----",
    "sk-key": "sk-abcdefghijklmnop1234", "password": "DB Password=hunter2", "postgres-dsn": "postgresql://u@h/db", "redis-dsn": "redis://localhost:6379",
}
INTERNAL = {  # 2묶음
    "seat-name": "byz-planner-master-claude#4 에게", "abs-path": "/Users/someone/x", "worktree-path": "a/.worktrees/b",
    "cost": "비용 $12 입니다", "verdict-number": "판정 1779 로 확정",
}


@pytest.fixture(autouse=True)
def _no_human_channels(monkeypatch):
    monkeypatch.delenv(pg.HUMAN_CHANNELS_ENV, raising=False)


@pytest.fixture
def env(slack, tmp_path):  # noqa: F811
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n")
    (tmp_path / "hermes.env").write_text("SLACK_BOT_TOKEN=xoxb-secret-2\n")
    return tmp_path


def run(env, slack, cmd, *extra, channel="C1", card_path=None):  # noqa: F811
    argv = [cmd, "--ledger", str(env / "threads.json"), "--token-file", str(env / "tok.env"), "--hermes-env", str(env / "hermes.env"),
            "--slack-base", slack.base, "--channel", channel]
    if cmd in ("start", "progress", "result"):
        argv += ["--card", str(card_path or card(env)), "--issue", "#893", "--seat", "s#1", "--canon", "없음", "--next", "오빠 결정",
                 "--resume-script", str(resume_script(env))]
    return tp.main(argv + list(extra))


@pytest.mark.parametrize("name", sorted(SECRET))
def test_group1_sample_is_rejected_on_any_channel(name):
    with pytest.raises(pg.PostGuardError, match=f"묶음1:{name}"):
        pg.check(SECRET[name], "C-any")


@pytest.mark.parametrize("name", sorted(INTERNAL))
def test_group2_sample_is_rejected_on_human_channel(name):
    with pytest.raises(pg.PostGuardError, match=f"묶음2:{name}"):
        pg.check(INTERNAL[name], "C-any", human=True)


def test_group2_is_not_checked_on_machine_channels_but_group1_is(monkeypatch):
    for sample in INTERNAL.values():
        pg.check(sample, "C-machine")  # #byz-planner 기계 발행은 판정 번호를 쓴다 — 통과
    monkeypatch.setenv(pg.HUMAN_CHANNELS_ENV, "C-talk, C-other")
    with pytest.raises(pg.PostGuardError, match="묶음2"):
        pg.check(INTERNAL["verdict-number"], "C-talk")
    pg.check(INTERNAL["verdict-number"], "C-machine")


def test_clean_text_passes_everywhere():
    pg.check("안녕하세요. 요청을 팀에 전달했어요. https://github.com/org/repo/issues/12", "C-talk", human=True)


def test_mutation_emptying_group2_is_caught_by_the_sample_test(monkeypatch):
    monkeypatch.setattr(pg, "INTERNAL", {})
    with pytest.raises(pytest.fail.Exception):  # 샘플 검사가 «DID NOT RAISE» 로 실패해야 한다 = 변이를 잡는다
        test_group2_sample_is_rejected_on_human_channel("seat-name")


def test_error_names_the_pattern_but_never_echoes_the_text():
    with pytest.raises(pg.PostGuardError) as e:
        pg.check(SECRET["postgres-dsn"], "C1")
    assert "postgres-dsn" in str(e.value) and "u@h" not in str(e.value)


def started(env, slack):  # noqa: F811
    ledger(env)
    assert run(env, slack, "start", "--text", "발행") == 0
    return slack.roots[0]["ts"]


def reply(env, slack, text, ts, channel="C1"):  # noqa: F811
    f = env / "reply.txt"
    f.write_text(text, encoding="utf-8")
    return run(env, slack, "reply", "--ts", ts, "--text-file", str(f), channel=channel)


def test_reply_posts_one_thread_answer_without_card_or_ledger_or_files(env, slack, capsys):  # noqa: F811
    root = started(env, slack)
    before = (env / "threads.json").read_text()
    assert reply(env, slack, "확인했어요. 팀에 전달했어요.", root) == 0
    (r,) = slack.replies
    assert r["thread_ts"] == root and r["text"] == f"{STATUS_HEAD}\n확인했어요. 팀에 전달했어요."  # r1089 머리줄 + 본문 그대로
    assert not getattr(slack, "files", [])
    assert (env / "threads.json").read_text() == before and "reply ts=" in capsys.readouterr().out


@pytest.mark.parametrize("sample", [SECRET["slack-token"], INTERNAL["seat-name"], INTERNAL["cost"]])
def test_reply_rejects_secret_and_internal_words_with_zero_posts(env, slack, capsys, sample):  # noqa: F811
    root = started(env, slack)
    assert reply(env, slack, sample, root) == 1
    assert not slack.replies and len(slack.msgs) == 1  # 환경변수 없이도 reply 는 항상 사람 채널로 본다
    assert sample not in capsys.readouterr().err


def test_reply_rejects_bad_ts_and_empty_text(env, slack):  # noqa: F811
    started(env, slack)
    assert reply(env, slack, "x", "not-a-ts") == 1
    assert reply(env, slack, "   \n", "1700000000.000100") == 1 and not slack.replies


def test_start_with_a_secret_posts_nothing_and_leaves_the_card_untouched(env, slack):  # noqa: F811
    ledger(env)
    before = card(env).read_text(encoding="utf-8")
    assert run(env, slack, "start", "--text", SECRET["redis-dsn"]) == 1
    assert slack.msgs == [] and card(env).read_text(encoding="utf-8") == before  # 「시도」 줄도 안 남는다


def test_progress_and_update_are_guarded_too(env, slack, tmp_path):  # noqa: F811
    started(env, slack)
    assert run(env, slack, "progress", "--text", SECRET["aws-key"]) == 1 and not slack.replies
    f = tmp_path / "board.md"
    f.write_text(SECRET["private-key"], encoding="utf-8")
    assert run(env, slack, "update", "--key", "board:2026-10-15", "--text-file", str(f)) == 1 and len(slack.msgs) == 1


def test_start_on_a_configured_human_channel_rejects_verdict_numbers(env, slack, monkeypatch):  # noqa: F811
    ledger(env)
    monkeypatch.setenv(pg.HUMAN_CHANNELS_ENV, "C1")
    assert run(env, slack, "start", "--text", INTERNAL["verdict-number"]) == 1 and slack.msgs == []
    monkeypatch.delenv(pg.HUMAN_CHANNELS_ENV)
    assert run(env, slack, "start", "--text", INTERNAL["verdict-number"]) == 0  # 기계 채널은 통과


# ── R231a 교정 3 H2 — 명부 `_slack_channel` 타입 검증(손상 = 게시 0 · 키 없음 = 정상) ──


def _roster(tmp_path, monkeypatch, body):
    d = tmp_path / ".fable-team"
    d.mkdir()
    (d / "seats-x.json").write_text(body, encoding="utf-8")
    monkeypatch.setenv(pg.ROOT_ENV, str(tmp_path))


@pytest.mark.parametrize("body, want", [
    ('{"_slack_channel": "C1"}', {"C1"}), ('{"_slack_channel": ["C1", "C2"]}', {"C1", "C2"}), ('{"_master": "m#1"}', set()),
])
def test_roster_channel_field_valid_shapes(tmp_path, monkeypatch, body, want):
    _roster(tmp_path, monkeypatch, body)
    assert pg.human_channels() == want


@pytest.mark.parametrize("body", [
    '{"_slack_channel": {"channel": "C1"}}', '{"_slack_channel": 7}', '{"_slack_channel": null}', '{"_slack_channel": ""}',
    '{"_slack_channel": []}', '{"_slack_channel": ["C1", 3]}', '{"_slack_channel": ["C1", ""]}', '["C1"]', '"C1"',
])
def test_roster_channel_field_malformed_raises(tmp_path, monkeypatch, body):
    _roster(tmp_path, monkeypatch, body)
    with pytest.raises(pg.PostGuardError, match="사람 채널 판정 불가"):
        pg.human_channels()


# ── r1089 — 사람 채널 슬랙 글 머리의 카운팅 머리줄(계약↔시험 ⓐ~ⓕ · 변이 3) ──


def _posted(monkeypatch) -> list[dict]:
    """가짜 post — 인자를 기록하고 ts 를 돌려준다(실 슬랙 0)."""
    calls: list[dict] = []
    monkeypatch.setattr(pg, "post", lambda base, token, channel, text, thread_ts=None: calls.append(
        {"base": base, "channel": channel, "text": text, "thread_ts": thread_ts}) or "1793.000100")
    return calls


def _status(tmp_path, monkeypatch, first: str = STATUS_HEAD, age_min: float = 0.0) -> None:
    """임시 TEAM-STATUS — 첫 줄·나이(mtime)를 정한다."""
    f = tmp_path / "TEAM-STATUS.md"
    f.write_text(f"{first}\n둘째 줄\n", encoding="utf-8")
    os.utime(f, (time.time() - age_min * 60,) * 2)
    monkeypatch.setenv(sh.FILE_ENV, str(f))


def test_r1089_a_human_post_starts_with_the_status_first_line(tmp_path, monkeypatch):  # ⓐ · R1
    _status(tmp_path, monkeypatch)
    calls = _posted(monkeypatch)
    pg.guarded_post("http://x", "t", "C1", "본문 첫 줄\n둘째 줄", human=True)
    assert calls[0]["text"].split("\n")[0] == STATUS_HEAD and calls[0]["text"].endswith("본문 첫 줄\n둘째 줄")


def test_r1089_b_stale_file_gets_the_age_suffix(tmp_path, monkeypatch):  # ⓑ · R2
    _status(tmp_path, monkeypatch, age_min=40)
    calls = _posted(monkeypatch)
    pg.guarded_post("http://x", "t", "C1", "본문", human=True)
    assert calls[0]["text"].split("\n")[0] == f"{STATUS_HEAD} (낡음 40분)"


@pytest.mark.parametrize("first, reason", [(None, "파일 없음"), ("스크립트 셋 · 인터뷰 3 · 막힌 팀 대기 2", "형식")])
def test_r1089_c_unreadable_or_wrong_format_says_cannot_and_logs_error(tmp_path, monkeypatch, caplog, first, reason):
    # ⓒ · R3 · R4 — 파일 없음 / 형식 다름 → «카운팅 확인 불가(사유)» + ERROR 1줄 · 게시는 계속
    if first is None:
        monkeypatch.setenv(sh.FILE_ENV, str(tmp_path / "없는파일.md"))
    else:
        _status(tmp_path, monkeypatch, first=first)
    calls = _posted(monkeypatch)
    with caplog.at_level(logging.ERROR):
        pg.guarded_post("http://x", "t", "C1", "본문", human=True)
    assert calls[0]["text"].startswith(f"카운팅 확인 불가({reason})\n본문")
    assert sum(1 for r in caplog.records if r.levelno == logging.ERROR) == 1


def test_r1089_d_machine_channel_gets_no_head(tmp_path, monkeypatch):  # ⓓ · R5
    _status(tmp_path, monkeypatch)
    calls = _posted(monkeypatch)
    pg.guarded_post("http://x", "t", "C-machine", "본문 그대로")
    assert calls[0]["text"] == "본문 그대로"


def test_r1089_e_the_same_head_is_not_added_twice(tmp_path, monkeypatch):  # ⓔ · R6
    _status(tmp_path, monkeypatch)
    calls = _posted(monkeypatch)
    pg.guarded_post("http://x", "t", "C1", f"{STATUS_HEAD}\n본문", human=True)
    assert calls[0]["text"] == f"{STATUS_HEAD}\n본문"


def test_r1089_f_head_line_passes_the_internal_word_check(tmp_path, monkeypatch):  # ⓕ · R7
    _status(tmp_path, monkeypatch)
    calls = _posted(monkeypatch)
    pg.guarded_post("http://x", "t", "C1", "번역 창은 확인했어요.", human=True)  # 거절 0(내부어 0)
    assert body_after_status_head(calls[0]["text"]) == "번역 창은 확인했어요."


# 변이 3 — 각각이 대응 시험을 실패시킨다(변이가 안 잡히면 그 시험은 계약을 안 재는 것이다)


def test_r1089_mutation_a_no_head_is_caught(tmp_path, monkeypatch):
    monkeypatch.setattr(pg, "with_status_head", lambda text: text)  # 붙이기 끔
    with pytest.raises(AssertionError):  # 대응 시험이 실패해야 변이가 잡힌 것이다
        test_r1089_a_human_post_starts_with_the_status_first_line(tmp_path, monkeypatch)


def test_r1089_mutation_b_no_age_check_is_caught(tmp_path, monkeypatch):
    monkeypatch.setattr(sh, "stale_minutes", lambda: 10**6)  # 나이 검사 끔
    with pytest.raises(AssertionError):  # 대응 시험이 실패해야 변이가 잡힌 것이다
        test_r1089_b_stale_file_gets_the_age_suffix(tmp_path, monkeypatch)


def test_r1089_mutation_e_always_prepend_is_caught(tmp_path, monkeypatch):
    monkeypatch.setattr(pg, "with_status_head", lambda text: f"{sh.head()}\n{text}")  # 중복 검사 끔
    with pytest.raises(AssertionError):  # 대응 시험이 실패해야 변이가 잡힌 것이다
        test_r1089_e_the_same_head_is_not_added_twice(tmp_path, monkeypatch)


# ── r1710 — 사람 채널 «머지 질문» 글은 PR 마다 head sha(40자)가 있어야 나간다(반례 ①~⑤ · 변이 W1~W3 원본 대조) ──
NO_SHA = "머지 질문에 PR head sha\\(40자\\)가 없음"


@pytest.fixture
def gate(tmp_path, monkeypatch):
    """가짜 리포(bare origin + 클론) — new = origin/main 을 품은 PR head · old = 품지 않은 PR head · calls = 가짜 게시 기록."""
    import subprocess
    from types import SimpleNamespace

    w = tmp_path / "w"
    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
           "GIT_CONFIG_GLOBAL": os.devnull}

    def g(*a, cwd=w):
        return subprocess.run(["git", *a], cwd=cwd, env=env, capture_output=True, text=True, timeout=7, check=True).stdout.strip()

    g("init", "-q", "--bare", "-b", "main", str(tmp_path / "origin.git"), cwd=tmp_path)
    g("clone", "-q", str(tmp_path / "origin.git"), str(w), cwd=tmp_path)
    g("checkout", "-q", "-B", "main"), g("commit", "-q", "--allow-empty", "-m", "c0"), g("push", "-q", "origin", "main")
    g("checkout", "-q", "-b", "pr-old"), g("commit", "-q", "--allow-empty", "-m", "pr")
    old = g("rev-parse", "HEAD")
    g("checkout", "-q", "main"), g("commit", "-q", "--allow-empty", "-m", "c1"), g("push", "-q", "origin", "main")
    g("checkout", "-q", "-b", "pr-new", "pr-old"), g("merge", "-q", "--no-edit", "main")
    new = g("rev-parse", "HEAD")
    g("commit", "-q", "--allow-empty", "-m", "pr2")  # new2 = main 을 품은 또 다른 PR head(묶음 질문용)
    monkeypatch.setenv(pg.GATE_REPOS_ENV, str(w))
    monkeypatch.delenv(pg.GATE_TARGET_ENV, raising=False)
    _status(tmp_path, monkeypatch)
    monkeypatch.setattr(pg, "desk_copy", lambda *a, **k: None)
    return SimpleNamespace(new=new, new2=g("rev-parse", "HEAD"), old=old, calls=_posted(monkeypatch))


def _ask(text: str, human: bool = True) -> None:
    pg.guarded_post("http://x", "t", "C1", text, human=human)


def test_r1710_1_merge_question_without_sha_is_not_posted(gate):  # ① · A1·A2
    for q in ("팩 PR #950 r1326 유휴 깨우기 머지할까요?", "PR #950 Merge 해도 될까요?", "#950 병합 진행할까요"):
        with pytest.raises(pg.PostGuardError, match=NO_SHA):
            _ask(q)
    assert gate.calls == []


def test_r1710_2_merge_question_with_head_on_main_is_posted(gate):  # ② · A3
    _ask(f"팩 PR #950 머지할까요? head {gate.new}")
    assert len(gate.calls) == 1 and gate.new in gate.calls[0]["text"]


def test_r1710_3_merge_question_with_head_behind_main_is_not_posted(gate):  # ③ · A3 조상 검사
    with pytest.raises(pg.PostGuardError, match="품지 않음"):
        _ask(f"팩 PR #950 머지할까요? head {gate.old}")
    assert gate.calls == []


def test_r1710_4_non_questions_and_machine_channels_post_as_before(gate):  # ④ · A4
    _ask("팩 PR #950 머지됨 · LANDED")          # 묻는 꼴 0
    _ask("오늘 머지할까요? 건은 없습니다")       # PR 번호 0
    _ask("팩 PR #950 올렸어요. 확인할까요?")     # 머지 낱말 0
    _ask("팩 PR #950 머지할까요?", human=False)  # 기계 채널
    assert len(gate.calls) == 4


def test_r1710_5_batch_question_needs_one_sha_per_pr(gate):  # ⑤ · A2 묶음
    with pytest.raises(pg.PostGuardError, match=NO_SHA):
        _ask(f"7건 머지할까요?\n1. PR #950 {gate.new}\n2. PR #951")
    assert gate.calls == []
    with pytest.raises(pg.PostGuardError, match=NO_SHA):  # 같은 sha 를 두 번 적어도 1개로 센다
        _ask(f"2건 머지할까요?\n1. PR #950 {gate.new}\n2. PR #951 {gate.new}")
    assert gate.calls == []
    _ask(f"2건 머지할까요? (하네스 Issue #8375)\n1. PR #950 {gate.new}\n2. PR #951 {gate.new2}")  # «PR #N» 이 있으면 그 번호만 센다
    assert len(gate.calls) == 1


def _mutant(old: str, new: str):
    """post_guard 원문에서 old(정확히 1번)를 new 로 바꾼 사본 모듈 — 원본 pg 는 그대로."""
    import types
    from pathlib import Path

    src = Path(pg.__file__).read_text(encoding="utf-8")
    assert src.count(old) == 1, f"변이 자리 {src.count(old)}곳: {old}"
    mod = types.ModuleType("post_guard_mut")
    exec(compile(src.replace(old, new), pg.__file__, "exec"), mod.__dict__)
    return mod


def test_r1710_w1_no_merge_question_check_lets_case_1_through(gate):  # W1 → ① 이 깨진다
    _mutant("if human and MERGE_WORD.search(text)", "if False and MERGE_WORD.search(text)").approval_gate("팩 PR #950 머지할까요?", True)
    with pytest.raises(pg.PostGuardError, match=NO_SHA):  # 원본 = 반대 결과
        pg.approval_gate("팩 PR #950 머지할까요?", True)


def test_r1710_w2_no_ask_form_blocks_a_status_report(gate):  # W2 → ④(머지됨) 이 깨진다
    mut = _mutant('MERGE_WORD.search(text) and ASK.search(URL.sub("", text))', "MERGE_WORD.search(text)")
    with pytest.raises(mut.PostGuardError, match=NO_SHA):
        mut.approval_gate("팩 PR #950 머지됨 · LANDED", True)
    pg.approval_gate("팩 PR #950 머지됨 · LANDED", True)  # 원본 = 통과


def test_r1710_w3_any_one_sha_lets_a_batch_through(gate):  # W3 → ⑤ 가 깨진다
    q = f"7건 머지할까요?\n1. PR #950 {gate.new}\n2. PR #951"
    _mutant("if len(shas) < len(prs):", "if prs and not shas:").approval_gate(q, True)
    with pytest.raises(pg.PostGuardError, match=NO_SHA):  # 원본 = 반대 결과
        pg.approval_gate(q, True)


# ── r1710 보정 1 — 오탐 2건(ⓐ URL 물음표 · ⓑ Issue 번호) + 변이 Wa·Wb(원본 대조) ──
URL_REPORT = "PR #950 머지됨 https://x.com/a?b=1"
ISSUE_ASK = "Issue #8375 머지 관련 확인할까요?"


def test_r1710_a_url_question_mark_is_not_an_ask_form(gate):  # ⓐ 상태 보고의 링크 물음표는 묻는 꼴이 아니다
    _ask(URL_REPORT)
    assert len(gate.calls) == 1
    with pytest.raises(pg.PostGuardError, match=NO_SHA):  # 링크가 있어도 글이 묻는 꼴이면 그대로 막힌다
        _ask("PR #950 머지할까요? https://x.com/a?b=1")
    assert len(gate.calls) == 1


def test_r1710_b_issue_number_is_not_a_pr_number(gate):  # ⓑ «PR #N» 없을 때 Issue·이슈 번호는 PR 로 세지 않는다
    for q in (ISSUE_ASK, "이슈 #8375 병합 건 확인할까요?", "issue #8375 merge 볼까요?"):
        _ask(q)
    assert len(gate.calls) == 3
    with pytest.raises(pg.PostGuardError, match=NO_SHA):  # 같은 글에 맨 «#N» 이 있으면 그 번호는 센다
        _ask("Issue #8375 관련 #950 머지할까요?")
    assert len(gate.calls) == 3


def test_r1710_wa_ask_on_raw_text_blocks_a_url_report(gate):  # Wa → ⓐ 가 깨진다
    mut = _mutant('ASK.search(URL.sub("", text))', "ASK.search(text)")
    with pytest.raises(mut.PostGuardError, match=NO_SHA):
        mut.approval_gate(URL_REPORT, True)
    pg.approval_gate(URL_REPORT, True)  # 원본 = 통과


def test_r1710_wb_counting_issue_numbers_blocks_an_issue_ask(gate):  # Wb → ⓑ 가 깨진다
    mut = _mutant('{n for p, n in refs if not p or p.upper() == "PR"}', "{n for p, n in refs}")
    with pytest.raises(mut.PostGuardError, match=NO_SHA):
        mut.approval_gate(ISSUE_ASK, True)
    pg.approval_gate(ISSUE_ASK, True)  # 원본 = 통과


def test_r1710_r1_explicit_pr_and_bare_number_are_both_counted(gate):  # 보정 2 · DA HOLD R1 — «PR #N» 과 맨 «#N» 은 합쳐 센다
    with pytest.raises(pg.PostGuardError, match=NO_SHA):
        _ask(f"2건 머지할까요?\n1. PR #950 {gate.new}\n2. #951")
    assert gate.calls == []
    _ask(f"2건 머지할까요?\n1. PR #950 {gate.new}\n2. #951 {gate.new2}")  # PR 마다 sha 가 있으면 나간다
    assert len(gate.calls) == 1


R1927_TABLE, R1927_FENCED = "요약\n| a | b |\n|---|---|\n| 1 | 2 |", "요약\n```\n| a | b |\n|:---|---:|\n```"


def test_r1927_10_markdown_table_rejected_on_human_channel_only():  # ⑩ 사람 채널 = 거절 · 기계 채널 = 통과
    with pytest.raises(pg.PostGuardError, match="묶음2:마크다운 표"):
        pg.check(R1927_TABLE, "C-any", human=True)
    pg.check(R1927_TABLE, "C-machine")
    pg.check(R1927_FENCED, "C-any", human=True)  # 코드 블록 안 표 = 제외
    pg.check("a | b 는 파이프 1줄뿐", "C-any", human=True)


def test_r1927_m5_table_pattern_removed_is_caught(monkeypatch):  # M5 표 패턴 삭제 → ⑩ 깨짐
    monkeypatch.setattr(pg, "has_table", lambda text: False)
    with pytest.raises(pytest.fail.Exception):
        test_r1927_10_markdown_table_rejected_on_human_channel_only()
