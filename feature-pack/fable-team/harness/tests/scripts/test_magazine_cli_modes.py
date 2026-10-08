"""설계 §9 시험 6 — CLI 모드 계약(F2) · eli5 실패의 «보이는 실패» · --reattach. 가짜 요약·가짜 PDF·가짜 eli5·가짜 Slack.

실행: python3 -m pytest tests/scripts/test_magazine_cli_modes.py -q -s
"""
import json
import logging
import sys

import pytest
from _magazine_detail_fixture import EASY_HTML, fake_eli5, fake_full_model, fake_pdf
from _magazine_fakes import SUMMARY_OK, FakeMagazineSlack
from _thread_fakes import ledger, resume_script, seats

import byz_morning_magazine as cli

DATE = "2026-10-08"
WARN_PREFIX = "쉬운 판(HTML) 못 만들었어요 — "


@pytest.fixture
def slack() -> FakeMagazineSlack:
    return FakeMagazineSlack()


@pytest.fixture
def env(slack, tmp_path, monkeypatch):
    (tmp_path / "model.json").write_text(json.dumps(fake_full_model()), encoding="utf-8")
    (tmp_path / "sum.py").write_text(SUMMARY_OK, encoding="utf-8")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n")
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf(3))
    monkeypatch.setitem(sys.modules, "magazine_eli5", fake_eli5())
    base = ["--model-file", str(tmp_path / "model.json"), "--summary-cmd", f"python3 {tmp_path / 'sum.py'}", "--out-dir", str(tmp_path / "out"),
            "--state", str(tmp_path / "state.json"), "--token-file", str(tmp_path / "tok"), "--slack-base", slack.base, "--channel", "C1",
            "--ledger", str(ledger(tmp_path)), "--seats-file", str(seats(tmp_path)), "--resume-script", str(resume_script(tmp_path)),
            "--date", DATE, "--no-push"]
    return base, tmp_path


def published(env):
    base, _ = env
    assert cli.main(base) == 0


@pytest.mark.parametrize("conflict", ["--force", "--force-root"])
def test_f2_reattach_with_force_flags_exits_2_with_zero_remote_calls(env, slack, conflict, capsys):
    base, tmp = env
    published(env)
    posted = (len(slack.msgs), slack.upload_url_calls, slack.complete_calls)
    with pytest.raises(SystemExit) as e:
        cli.main([*base, "--reattach", "r1", conflict])
    err = capsys.readouterr().err  # print 보다 먼저 비운다(capsys 가 출력 줄을 삼키지 않게)
    extra = (len(slack.msgs), slack.upload_url_calls, slack.complete_calls) != posted
    print(f"[reattach r1 {conflict}] exit={e.value.code} · 원격 호출 추가 = {int(extra)}")
    assert e.value.code == 2 and not extra and "같이 쓸 수 없어요" in err


def test_reattach_needs_date_and_valid_rev(env):
    base, _ = env
    no_date = [a for a in base if a not in ("--date", DATE)]
    for bad in (["--reattach", "r0"], ["--reattach", "x1"]):
        with pytest.raises(SystemExit) as e:
            cli.main([*base, *bad])
        assert e.value.code == 2
    with pytest.raises(SystemExit) as e:
        cli.main([*no_date, "--reattach", "r1"])
    assert e.value.code == 2


def test_reattach_on_done_day_adds_reply_and_files_not_a_root_then_skips(env, slack, capsys):
    base, _ = env
    published(env)
    assert cli.main([*base, "--reattach", "r1"]) == 0
    out = capsys.readouterr().out.splitlines()[-1]
    print(f"[reattach 출력] {out}")
    root = slack.roots[0]["ts"]
    assert len(slack.roots) == 1 and out.startswith(f"reattached date={DATE} rev=r1 ts=") and "pages=3" in out and "-eli5.html" in out
    assert slack.replies_of(root)[0]["text"].startswith(f"*아침 매거진 {DATE} 재첨부 r1*") and len(slack.titles(root)) == 4
    assert cli.main([*base, "--reattach", "r1"]) == 0 and f"skip date={DATE} rev=r1" in capsys.readouterr().out and len(slack.titles(root)) == 4


def test_reattach_skip_happens_before_collect_summary_pdf(env, monkeypatch):
    base, _ = env
    published(env)
    assert cli.main([*base, "--reattach", "r1"]) == 0
    for name in ("summarize_model", "html_to_pdf", "build_eli5"):
        monkeypatch.setattr(cli, name, lambda *a, _n=name, **k: pytest.fail(f"rN done 인데 {_n} 호출"))
    assert cli.main([*base, "--reattach", "r1"]) == 0


def test_reattach_dry_run_touches_nothing(env, slack, capsys):
    base, tmp = env
    published(env)
    before = (len(slack.msgs), slack.complete_calls, (tmp / "state.json").read_text())
    assert cli.main([*base, "--reattach", "r1", "--dry-run"]) == 0
    assert (len(slack.msgs), slack.complete_calls, (tmp / "state.json").read_text()) == before and "DRY-RUN reattach" in capsys.readouterr().out


def test_eli5_failure_is_visible_in_log_root_and_pdf_section_and_pdf_continues(env, slack, caplog, monkeypatch):
    base, tmp = env
    monkeypatch.setitem(sys.modules, "magazine_eli5", fake_eli5(fail="형식 오류 <@U123>\n둘째 줄"))
    with caplog.at_level(logging.ERROR, logger="byz_morning_magazine"):
        assert cli.main(base) == 0
    root = slack.roots[0]
    assert "본문은 스레드의 PDF(풀 디테일)에 있어요" in root["text"] and "HTML(쉬운 판)" not in root["text"]  # 쉬운 판이 없으면 안내하지 않는다
    assert root["text"].splitlines()[-3] == f"{WARN_PREFIX}형식 오류 &lt;@U123&gt;"  # 경고 줄 = 블록 2줄 바로 앞 · 원인 첫 줄 · 중화
    md = (tmp / "out" / "MAGAZINE-20261008.md").read_text(encoding="utf-8")
    assert f"{WARN_PREFIX}형식 오류 <@U123>" in md.split("## 근거")[1].split("## ")[0]  # PDF 근거 절에 같은 줄
    assert any("쉬운 판(eli5) 생성 실패" in r.message for r in caplog.records if r.levelno == logging.ERROR)
    assert slack.titles(root["ts"]) == [f"아침 매거진 {DATE} PDF r0"] and json.loads((tmp / "state.json").read_text())[DATE]["phase"] == "done"
    print(f"[eli5 실패] PDF 발행 계속={len(slack.uploads) == 1} · 뿌리 글 마지막 줄 = {root['text'].splitlines()[-1]}")


def test_eli5_failure_on_reattach_warns_in_reply_and_attaches_only_pdf(env, slack, monkeypatch):
    base, _ = env
    published(env)
    monkeypatch.setitem(sys.modules, "magazine_eli5", fake_eli5(fail="LLM 응답 없음"))
    assert cli.main([*base, "--reattach", "r1"]) == 0
    root = slack.roots[0]["ts"]
    assert slack.replies_of(root)[0]["text"].splitlines()[-1] == f"{WARN_PREFIX}LLM 응답 없음"
    assert slack.titles(root)[-1] == f"아침 매거진 {DATE} PDF r1" and len(slack.titles(root)) == 3


def test_missing_eli5_module_is_a_visible_failure_not_a_silent_skip(env, slack, monkeypatch):
    base, _ = env
    monkeypatch.setitem(sys.modules, "magazine_eli5", None)  # import → ImportError
    assert cli.main(base) == 0
    assert slack.roots[0]["text"].splitlines()[-3].startswith(WARN_PREFIX) and "magazine_eli5" in slack.roots[0]["text"]


def test_unexpected_eli5_bug_fails_the_whole_publish_visibly(env, slack, monkeypatch):
    base, _ = env
    mod = fake_eli5()
    mod.build = lambda *a: (_ for _ in ()).throw(TypeError("버그"))  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "magazine_eli5", mod)
    assert cli.main(base) == 1 and len(slack.msgs) == 1 and slack.msgs[0]["text"].startswith("매거진 발행 실패") and "TypeError" in slack.msgs[0]["text"]


def test_model_without_detail_fails_visibly_no_part1_only(env, slack, tmp_path):
    base, _ = env
    m = fake_full_model()
    del m["detail"]
    (tmp_path / "model.json").write_text(json.dumps(m), encoding="utf-8")
    assert cli.main(base) == 1 and "detail 칸 없음" in slack.msgs[0]["text"] and not slack.roots[1:] and slack.upload_url_calls == 0


def test_force_alone_keeps_old_behavior_new_root_even_when_done(env, slack):
    base, _ = env
    published(env)
    assert cli.main([*base, "--force"]) == 0 and len(slack.roots) == 2
    assert EASY_HTML.encode() in slack.uploads
