"""매거진 CLI — 가짜 요약·가짜 PDF·가짜 Slack · 실제 magazine_collect.collect 접점(date, *, repo, gh_repo, mailbox).

실행: python3 -m pytest tests/scripts/test_magazine_cli.py -q
"""
import inspect
import json
import sys
from datetime import datetime
from pathlib import Path

import pytest
from _magazine_detail_fixture import EASY_HTML, detail_fixture, fake_eli5, fake_full_model, fake_pdf
from _magazine_fakes import SUMMARY_OK, FakeMagazineSlack, fake_model, git, make_repo

import byz_morning_magazine as cli
import magazine_collect
from magazine_slack import marker
from magazine_window import KST, MagazineError

DATE = "2026-10-08"


@pytest.fixture
def slack() -> FakeMagazineSlack:
    return FakeMagazineSlack()


@pytest.fixture
def repo(tmp_path):
    return make_repo(tmp_path)


# ── CLI: 가짜 요약·가짜 PDF·가짜 Slack ───────────────────────────────────────────
@pytest.fixture
def cli_env(slack, tmp_path, monkeypatch):
    (tmp_path / "model.json").write_text(json.dumps(fake_full_model()), encoding="utf-8")
    (tmp_path / "sum.py").write_text(SUMMARY_OK, encoding="utf-8")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n")
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf())
    monkeypatch.setitem(sys.modules, "magazine_eli5", fake_eli5())
    base = ["--model-file", str(tmp_path / "model.json"), "--summary-cmd", f"python3 {tmp_path / 'sum.py'}", "--out-dir", str(tmp_path / "out"),
            "--state", str(tmp_path / "state.json"), "--token-file", str(tmp_path / "tok"), "--slack-base", slack.base, "--channel", "C1"]
    return base, tmp_path


def test_cli_dry_run_posts_nothing(cli_env, slack, capsys):
    base, tmp = cli_env
    assert cli.main([*base, "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert "DRY-RUN" in out and "MAGAZINE-20261008.pdf" in out and "*아침 매거진 2026-10-08*" in out and "본문은 스레드의 PDF(풀 디테일)·HTML(쉬운 판)" in out
    assert "pages=3" in out and "-eli5.html" in out
    assert not slack.msgs and not (tmp / "state.json").exists() and (tmp / "out" / "MAGAZINE-20261008.md").exists()


def test_cli_no_push_makes_zero_git_calls_and_second_run_skips(cli_env, slack, monkeypatch, capsys):
    base, tmp = cli_env
    monkeypatch.setattr(cli, "publish_md", lambda *a, **k: pytest.fail("--no-push 인데 git 호출"))
    assert cli.main([*base, "--no-push"]) == 0 and cli.main([*base, "--no-push"]) == 0
    assert "skip date=2026-10-08" in capsys.readouterr().out and len(slack.roots) == 1
    root = slack.roots[0]["text"]
    assert root.startswith("*아침 매거진 2026-10-08*") and "main 에 두 건이 들어갔어요" in root and "<@U0AC2JF0M7D> 오빠 할 일이 1건" in root
    assert "&lt;script&gt;" not in root and slack.uploads == [b"%PDF-fake", EASY_HTML.encode()]
    assert slack.titles(slack.roots[0]["ts"]) == [f"아침 매거진 {DATE} PDF r0", f"아침 매거진 {DATE} HTML r0"]


def test_cli_push_link_uses_commit_sha(cli_env, slack, repo, monkeypatch):
    base, _ = cli_env
    origin, _, wt = repo
    assert cli.main([*base, "--worktree", str(wt), "--repo", "o/r"]) == 0
    sha = git(origin, "rev-parse", "ops/magazine")
    assert f"<https://github.com/o/r/blob/{sha}/design/harness/magazine/MAGAZINE-20261008.md|매거진 본문>" in slack.roots[0]["text"]


def test_cli_push_failure_posts_failure_line_not_a_root(cli_env, slack, tmp_path):
    base, _ = cli_env
    assert cli.main([*base, "--worktree", str(tmp_path / "none")]) == 1
    assert len(slack.msgs) == 1 and slack.msgs[0]["text"].startswith("매거진 발행 실패") and marker(DATE) not in slack.msgs[0]["text"]
    assert cli.main([*base, "--no-push"]) == 0 and len(slack.roots) == 2  # 실패 글을 뿌리 글로 오인하지 않는다


def test_cli_broken_model_fails_visibly(cli_env, slack, tmp_path):
    base, _ = cli_env
    bad = fake_model()
    del bad["mbox"]
    bad["detail"] = detail_fixture()
    (tmp_path / "model.json").write_text(json.dumps(bad), encoding="utf-8")
    assert cli.main([*base, "--no-push"]) == 1 and slack.msgs[0]["text"].startswith("매거진 발행 실패")


# ── 접점: 실제 magazine_collect.collect(date, *, repo, gh_repo, mailbox) ───────────
def test_collect_signature_contract():
    params = inspect.signature(magazine_collect.collect).parameters
    assert next(iter(params)) == "date"
    assert {n for n, p in params.items() if p.kind is inspect.Parameter.KEYWORD_ONLY} == {"repo", "gh_repo", "mailbox", "refs", "byz_root"}


def seen_collect(monkeypatch) -> dict:
    seen: dict = {}

    def fake(date, *, repo, gh_repo, mailbox):
        seen.update(date=date, repo=repo, gh_repo=gh_repo, mailbox=mailbox)
        return {**fake_model(), "date": date}

    monkeypatch.setattr(magazine_collect, "collect", fake)
    return seen


def parse(tmp_path, *extra):
    return cli.parse_args(["--repo-root", str(tmp_path), "--repo", "o/r", "--state", str(tmp_path / "s.json"), *extra])


def test_load_model_passes_the_three_keywords_with_default_mailbox(tmp_path, monkeypatch):
    seen = seen_collect(monkeypatch)
    cli.load_model(parse(tmp_path), datetime(2026, 10, 9, 7, 30, tzinfo=KST))  # 예약 모드, 08:00 전 → D = 어제
    assert seen == {"date": "2026-10-08", "repo": tmp_path, "gh_repo": "o/r", "mailbox": tmp_path / ".fable-team/comm/mailbox.log.jsonl"}
    cli.load_model(parse(tmp_path, "--mailbox", "/x/m.jsonl"), datetime(2026, 10, 9, 8, 1, tzinfo=KST))
    assert seen["date"] == "2026-10-09" and seen["mailbox"] == Path("/x/m.jsonl")


def test_load_model_manual_date_future_window_and_missing_root_raise(tmp_path, monkeypatch):
    seen_collect(monkeypatch)
    with pytest.raises(MagazineError, match="아직 닫히지"):
        cli.load_model(parse(tmp_path, "--date", "2026-10-09"), datetime(2026, 10, 9, 7, 59, tzinfo=KST))
    monkeypatch.delenv("BYZ_ROOT", raising=False)
    with pytest.raises(MagazineError, match="리포 루트"):
        cli.load_model(cli.parse_args(["--state", str(tmp_path / "s.json")]))


def test_load_model_marks_skipped_days_from_state(tmp_path, monkeypatch):
    seen_collect(monkeypatch)
    (tmp_path / "s.json").write_text(json.dumps({"2026-10-05": {"phase": "done"}, "2026-10-06": {"phase": "posted"}}))
    model = cli.load_model(parse(tmp_path, "--date", "2026-10-08"), datetime(2026, 10, 8, 9, 0, tzinfo=KST))
    assert model["skipped_days"] == ["2026-10-06", "2026-10-07"]


def test_cli_through_real_collect_composition(cli_env, slack, tmp_path, monkeypatch):
    """실 collect() 합성(창→leaf 3종→모델)을 거쳐 render→(가짜 PDF)→게시까지. leaf 만 가짜 — 슬랙 게시는 가짜 서버."""
    base, _ = cli_env
    m = fake_model()
    real_collect = magazine_collect.collect
    monkeypatch.setattr(magazine_collect, "collect", lambda *a, **k: {**real_collect(*a, **k), "detail": detail_fixture()})
    monkeypatch.setattr(magazine_collect, "collect_git", lambda *a: {k: m[k] for k in ("main", "merges", "docs")})
    monkeypatch.setattr(magazine_collect, "collect_gh", lambda *a: {k: m[k] for k in ("issues_opened", "issues_closed")})
    monkeypatch.setattr(magazine_collect, "collect_mbox", lambda *a: {k: m[k] for k in ("verdicts", "mbox", "seats")})
    no_detail = {k: [] for k in ("refs", "units", "verdict_sections", "seats_closed", "appendix")} | {"merge_bodies": {}}
    monkeypatch.setattr(magazine_collect, "collect_detail", lambda *a: no_detail)
    monkeypatch.setattr(magazine_collect, "collect_decisions", lambda *a: [])
    monkeypatch.setattr(magazine_collect, "last_comments", lambda *a: {})
    monkeypatch.setattr(magazine_collect, "collect_open", lambda *a: {"cards": [], "requests": [], "holds": [], "breaches": []})
    argv = [*base[2:], "--repo-root", str(tmp_path), "--date", "2026-10-08", "--no-push"]
    assert cli.main(argv) == 0 and len(slack.roots) == 1
    assert "슬랙 미러 요약" in (tmp_path / "out" / "MAGAZINE-20261008.md").read_text(encoding="utf-8")


def test_done_state_skips_before_collect_summary_pdf_git(cli_env, slack, tmp_path, monkeypatch, capsys):
    """§8 순서: 창 → 상태 읽기(done 이면 끝) → 수집… — done 이면 수집·요약·PDF·push 호출 0, rc=0."""
    base, tmp = cli_env
    (tmp / "state.json").write_text(json.dumps({DATE: {"phase": "done", "ts": "1.0"}}))
    calls: list[str] = []
    for mod, name in ((magazine_collect, "collect"), (cli, "summarize_model"), (cli, "html_to_pdf"), (cli, "publish_md")):
        monkeypatch.setattr(mod, name, lambda *a, _n=name, **k: calls.append(_n))
    assert cli.main([*base]) == 0  # --model-file 경로
    assert cli.main([*base[2:], "--repo-root", str(tmp), "--date", DATE]) == 0  # collect 경로
    assert cli.main([*base, "--dry-run"]) == 0
    out = capsys.readouterr().out
    print(f"[done 상태] collect·summary·pdf·git 호출 = {len(calls)} · 출력 = {out.splitlines()[0]}")
    assert calls == [] and out.count(f"skip date={DATE} ts=1.0") == 3 and not slack.msgs and not (tmp / "out").exists()


def test_force_ignores_done_and_republishes(cli_env, slack):
    base, tmp = cli_env
    (tmp / "state.json").write_text(json.dumps({DATE: {"phase": "done", "ts": "1.0"}}))
    assert cli.main([*base, "--no-push", "--force"]) == 0 and len(slack.roots) == 1
