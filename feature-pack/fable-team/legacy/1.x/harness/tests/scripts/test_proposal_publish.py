# ruff: noqa: F401, F811
"""설계 §7-3 — byz_proposal_publish 기본 동작: 3줄 뿌리 글 · text/markdown 첨부 · rN 답글 · 잘못된 제안서 · dry-run. 실 슬랙 0.

실행: python3 -m pytest tests/scripts/test_proposal_publish.py tests/scripts/test_proposal_publish_faults.py -q
"""
import time

import pytest
from _proposal_fakes import KEY, build, make_md, pub, slack, t  # fixture(slack·t) 재사용 — 인자 이름이 import 이름과 같다(F811 의도)

from _thread_fakes import card, commit_all, ledger, resume_script

import byz_proposal_publish as bp


def test_root_text_is_the_three_columns_and_md_is_attached(t, slack, tmp_path):
    md = make_md(tmp_path)
    r = pub(t, md, tmp_path)
    root = slack.roots[0]["text"]
    print(f"[뿌리 글]\n{root}")
    assert r["action"] == "published" and len(slack.roots) == 1
    lines = root.split("\n")  # 판정 497 — 머리표 + 결정할 것 아래 결정 자리 줄(이름은 환경 의존 → 접두만 본다)
    assert lines[:3] == [f"[작업상황] *제안서 {KEY}*", "결론: word-break 한 줄이면 된다.", "결정할 것: &lt;적용할까요&gt; 승인 / 수정 / 폐기?"]
    assert lines[3].startswith("결정 자리:") and lines[4:] == ["되돌림: CSS 한 줄 revert.", "질문은 #byz-desk 에"]
    assert slack.upload_types == ["text/markdown", "text/html"] and slack.files[0]["thread_ts"] == slack.roots[0]["ts"]
    n = len(slack.msgs)
    assert pub(t, md, tmp_path)["action"] == "skip" and len(slack.msgs) == n
    print("[같은 r0 재실행] 게시 추가 = 0")


def test_revision_is_a_thread_reply_with_new_attachment(t, slack, tmp_path):
    md = make_md(tmp_path)
    pub(t, md, tmp_path)
    md2 = make_md(tmp_path, status="수정 요청 r1")
    pub(t, md2, tmp_path, "r1")
    rep = slack.replies[0]
    assert rep["thread_ts"] == slack.roots[0]["ts"] and rep["text"].split("\n", 1)[0] == f"[작업상황] *제안서 {KEY} r1*"
    assert len(slack.files) == 4 and slack.files[3]["thread_ts"] == slack.roots[0]["ts"] and slack.upload_types == ["text/markdown", "text/html"] * 2
    assert pub(t, md2, tmp_path, "r1")["action"] == "skip" and len(slack.replies) == 1
    print("[같은 r1 재실행] 답글 추가 = 0")


@pytest.mark.parametrize("why,kw", [
    ("칸 누락", {"mutate": lambda s: s.replace("## 되돌림\nCSS 한 줄 revert.\n", "")}),
    ("120줄 초과", {"mutate": lambda s: s + "x\n" * 130}),
    ("승인 하이픈", {"status": "승인 - 판정 351"}),
    ("승인 판정 0", {"status": "승인 — 판정 0"}),
    ("머리 상태 줄 2개", {"mutate": lambda s: s.replace("- 상태: 컨펌 대기\n", "- 상태: 컨펌 대기\n- 상태: 폐기 — 판정 352\n")}),
])
def test_bad_proposal_raises_before_any_post(slack, tmp_path, why, kw):
    md = make_md(tmp_path, **kw)
    with pytest.raises(bp.PublishError):
        bp.parse(md)
    assert slack.msgs == []
    print(f"[{why}] raise · 게시 0")


def test_approved_proposal_is_published_as_record_not_decision_request(t, slack, tmp_path):
    md = make_md(tmp_path, status="승인 — 판정 351")
    r = pub(t, md, tmp_path)
    root = slack.roots[0]["text"].split("\n")
    print(f"[기록 뿌리 글]\n{chr(10).join(root)}")
    assert r["action"] == "published" and len(slack.roots) == 1
    assert root[0] == f"[작업상황] *제안서 {KEY} · 기록 판정 351*" and "결정할 것: 없음 — 판정 351 으로 승인됨" in root
    assert not any(ln.startswith("결정 자리") or "planner" in ln for ln in root) and len(root) == 5 and root[-1] == "질문은 #byz-desk 에"
    assert slack.upload_types == ["text/markdown", "text/html"]
    n = len(slack.msgs)
    assert pub(t, md, tmp_path)["action"] == "skip" and len(slack.msgs) == n
    print("[같은 r0 재실행] 게시 추가 = 0")


def _thread_to_r2(t, tmp_path):
    """r0(컨펌 대기) · r1 · r2(수정 요청) 가 올라간 스레드 — 이어서 같은 파일을 승인으로 바꾼다."""
    pub(t, make_md(tmp_path), tmp_path)
    pub(t, make_md(tmp_path, status="수정 요청 r1"), tmp_path, "r1")
    pub(t, make_md(tmp_path, status="수정 요청 r2"), tmp_path, "r2")


def test_approved_proposal_with_existing_thread_is_recorded_as_rn_reply(t, slack, tmp_path):
    _thread_to_r2(t, tmp_path)
    root_ts, n, files = slack.roots[0]["ts"], len(slack.replies), len(slack.files)
    md = make_md(tmp_path, status="승인 — 판정 351")
    assert pub(t, md, tmp_path, "r3")["action"] == "published"
    rep = slack.replies[n:]
    assert len(rep) == 1 and len(slack.roots) == 1 and rep[0]["thread_ts"] == root_ts
    lines = rep[0]["text"].split("\n")
    print(f"[기록 r3 답글]\n{rep[0]['text']}")
    assert lines[0] == f"[작업상황] *제안서 {KEY} r3 · 기록 판정 351*" and "결정할 것: 없음 — 판정 351 으로 승인됨" in lines
    assert not any(ln.startswith("결정 자리") for ln in lines) and len(slack.files) == files + 2
    assert slack.upload_types[-2:] == ["text/markdown", "text/html"] and all(f["thread_ts"] == root_ts for f in slack.files[files:])
    total = len(slack.msgs)
    assert pub(t, md, tmp_path, "r3")["action"] == "skip" and len(slack.msgs) == total
    print("[같은 기록 r3 재실행] 게시 추가 = 0")


def test_approved_proposal_without_revision_still_raises_pinned_hint(t, slack, tmp_path):
    _thread_to_r2(t, tmp_path)
    n = len(slack.msgs)
    with pytest.raises(bp.PublishError, match=r"다음 rN\(--revision\)"):
        pub(t, make_md(tmp_path, status="승인 — 판정 351"), tmp_path)
    assert len(slack.msgs) == n


def test_approved_proposal_with_revision_but_no_thread_raises_no_root(t, slack, tmp_path):
    with pytest.raises(bp.PublishError, match="뿌리 글 없음"):
        pub(t, make_md(tmp_path, status="승인 — 판정 351"), tmp_path, "r1")
    assert slack.msgs == []


def test_revision_finds_record_r0_root_when_state_is_lost(t, slack, tmp_path):
    md = make_md(tmp_path, status="승인 — 판정 351")
    pub(t, md, tmp_path)  # 기록 r0 뿌리
    (tmp_path / "state.json").unlink()
    assert pub(t, md, tmp_path, "r1")["action"] == "published"
    assert len(slack.roots) == 1 and len(slack.replies) == 1 and slack.replies[0]["thread_ts"] == slack.roots[0]["ts"]
    assert slack.replies[0]["text"].split("\n", 1)[0] == f"[작업상황] *제안서 {KEY} r1 · 기록 판정 351*"


def test_record_dry_run_with_revision_prints_record_rn_first_line(slack, tmp_path, capsys):
    md = make_md(tmp_path, status="승인 — 판정 351")
    commit_all(tmp_path)
    argv = [str(md), "--revision", "r3", "--dry-run", "--token-file", str(tmp_path / "없음.env"), "--card", str(card(tmp_path)), "--seat", "s#1",
            "--resume-script", str(resume_script(tmp_path))]
    assert bp.run(bp.parse_args(argv)) == 0
    assert capsys.readouterr().out.startswith(f"[작업상황] *제안서 {KEY} r3 · 기록 판정 351*\n") and slack.msgs == []


def test_record_dry_run_next_cell_says_record_not_waiting(slack, tmp_path, capsys):
    md = make_md(tmp_path, status="승인 — 판정 351")
    commit_all(tmp_path)
    argv = [str(md), "--dry-run", "--token-file", str(tmp_path / "없음.env"), "--card", str(card(tmp_path)), "--seat", "s#1",
            "--resume-script", str(resume_script(tmp_path))]
    assert bp.run(bp.parse_args(argv)) == 0
    out = capsys.readouterr().out
    assert out.startswith(f"[작업상황] *제안서 {KEY} · 기록 판정 351*\n") and "결정 자리" not in out and "↳ 다음: 기록 — 판정 351 승인 · 결정 대기 아님" in out


def test_other_revision_reply_is_not_adopted_as_r1(t, slack, tmp_path):
    md = make_md(tmp_path)
    pub(t, md, tmp_path)
    root_ts = slack.roots[0]["ts"]
    slack.msgs.append({"ts": f"{time.time() + 5:.6f}", "text": f"*제안서 {KEY} r2*\n다른 개정", "bot_id": "B1", "thread_ts": root_ts})
    pub(t, md, tmp_path, "r1")
    firsts = [m["text"].split("\n", 1)[0] for m in slack.replies]
    assert firsts == [f"*제안서 {KEY} r2*", f"[작업상황] *제안서 {KEY} r1*"]
    print("[r2 답글만 있는 스레드] r1 은 채택 안 하고 새 답글 1개")


def test_revision_without_root_raises(t, slack, tmp_path):
    md = make_md(tmp_path)
    with pytest.raises(bp.PublishError, match="뿌리 글 없음"):
        pub(t, md, tmp_path, "r1")
    assert slack.msgs == []


def test_dry_run_prints_text_without_token_or_post(slack, tmp_path, capsys):
    md = make_md(tmp_path)
    commit_all(tmp_path)
    argv = [str(md), "--dry-run", "--token-file", str(tmp_path / "없음.env"), "--card", str(card(tmp_path)), "--seat", "s#1",
            "--resume-script", str(resume_script(tmp_path))]
    assert bp.run(bp.parse_args(argv)) == 0
    out = capsys.readouterr().out
    assert out.startswith(f"[작업상황] *제안서 {KEY}*\n결론:") and slack.msgs == []
    assert out.rstrip().endswith("↳ 다음: 결정 대기 — &lt;적용할까요&gt; 승인 / 수정 / 폐기? · 재개: RESUME-CMD(s#1)\n질문은 #byz-desk 에")  # 블록 2줄 + 안내 1줄이 꼬리


def test_dry_run_issue_flag_adds_issue_line_above_conclusion(slack, tmp_path, capsys, monkeypatch):
    """R77 r1(판정 826): `--issue #M` 이면 뿌리 글 «결론» 줄 바로 위에 제안 Issue URL 한 줄. 번호가 아니면(「없음」) 줄 0."""
    monkeypatch.delenv("GH_REPO", raising=False)
    md = make_md(tmp_path)
    commit_all(tmp_path)
    base = [str(md), "--dry-run", "--token-file", str(tmp_path / "없음.env"), "--card", str(card(tmp_path)), "--seat", "s#1", "--resume-script", str(resume_script(tmp_path))]
    assert bp.run(bp.parse_args(base + ["--issue", "#12"])) == 0
    lines = capsys.readouterr().out.splitlines()
    assert lines[1] == "Issue: https://github.com/SecondWindStudio/byz-agents/issues/12" and lines[2].startswith("결론:")
    assert bp.run(bp.parse_args(base)) == 0
    assert not any(ln.startswith("Issue: ") for ln in capsys.readouterr().out.splitlines())


def _rev(tmp_path, rev="r0"):
    import json
    return json.loads((tmp_path / "state.json").read_text())[KEY]["revs"][rev]


def test_set_is_md_plus_html_with_hash_titles(t, slack, tmp_path, build):
    md = make_md(tmp_path)
    pub(t, md, tmp_path, build=build)
    h8 = _rev(tmp_path)["md_hash"][:8]
    print(f"[첨부 제목] {[f['title'] for f in slack.files]}")
    assert [f["title"] for f in slack.files] == [f"제안서 {KEY} r0 MD {h8}", f"제안서 {KEY} r0 HTML {h8}"]
    assert slack.upload_types == ["text/markdown", "text/html"] and slack.upload_bodies[0] == md.read_bytes()
    rec = _rev(tmp_path)
    assert rec["phase"] == "done" and rec["files"]["md"]["phase"] == "done" and rec["files"]["html"]["phase"] == "done"


def test_html_attach_failure_rerun_attaches_html_only(t, slack, tmp_path, build):
    md = make_md(tmp_path)
    slack.complete_faults[2] = "rejected"
    with pytest.raises(Exception):  # noqa: B017 — 두 번째(HTML) complete 거절
        pub(t, md, tmp_path, build=build)
    assert [f["title"].split(" ")[2] for f in slack.files] == ["r0"] and _rev(tmp_path)["files"]["md"]["phase"] == "done"
    pub(t, md, tmp_path, build=build)
    assert slack.upload_types.count("text/markdown") == 1 and len(slack.files) == 2 and len(build.calls) == 1
    print("[md 완료 뒤 HTML 실패 → 재실행] md 업로드 추가 = 0 · LLM 추가 = 0")


def test_llm_zero_ships_md_only_with_visible_warning_and_no_retry(t, slack, tmp_path, build, caplog):
    md = make_md(tmp_path)
    build.fail = "AI 풀이 0건 — HTML 못 만들었어요"
    pub(t, md, tmp_path, build=build)
    root = slack.roots[0]["text"].split("\n")
    print(f"[LLM 0건] 뿌리 글 끝: {root[-1]} · 첨부 {slack.upload_types}")
    assert root[-2].startswith("쉬운 판(HTML) 못 만들었어요 — AI 풀이 0건") and root[-1] == "질문은 #byz-desk 에" and slack.upload_types == ["text/markdown"]
    assert any(r.levelname == "ERROR" for r in caplog.records) and _rev(tmp_path)["html"]["phase"] == "omitted"
    print("[omitted rN] 아래: md 첨부가 중간에 실패한 rN 을 다시 돌려도 HTML 재시도 0")


def test_omitted_record_survives_rerun_without_html_retry(t, slack, tmp_path, build):
    md = make_md(tmp_path)
    build.fail = "AI 풀이 0건"
    slack.complete_faults[1] = "rejected"
    with pytest.raises(Exception):  # noqa: B017 — md complete 거절 → 글(posted)·omitted 기록만 남는다
        pub(t, md, tmp_path, build=build)
    assert _rev(tmp_path)["phase"] == "posted" and _rev(tmp_path)["html"]["phase"] == "omitted"
    build.fail = ""
    pub(t, md, tmp_path, build=build)
    assert len(build.calls) == 1 and slack.upload_types.count("text/html") == 0 and len(slack.roots) == 1
    print("[omitted + posted rN 재실행] HTML 재시도 = 0 · 글 추가 = 0")


def test_html_cache_means_no_second_llm_call(t, slack, tmp_path, build):
    md = make_md(tmp_path)
    pub(t, md, tmp_path, build=build)
    (tmp_path / "state.json").unlink()
    pub(t, md, tmp_path, build=build)
    assert len(build.calls) == 1 and len(slack.roots) == 1 and len(slack.files) == 2 and slack.upload_types == ["text/markdown", "text/html"]
    print("[상태 분실 → 재실행] LLM 추가 = 0 · 글·첨부 추가 = 0 (캐시 + 원격 표식 채택)")


def test_same_rn_with_changed_md_raises_before_anything(t, slack, tmp_path, build):
    md = make_md(tmp_path)
    pub(t, md, tmp_path, build=build)
    n, files = len(slack.msgs), len(slack.files)
    md.write_text(md.read_text() + "\n## 근거\n바뀐 원문\n", encoding="utf-8")
    with pytest.raises(bp.PublishError, match="다음 rN"):
        pub(t, md, tmp_path, build=build)
    assert len(slack.msgs) == n and len(slack.files) == files and len(build.calls) == 1
    print("[같은 r0 에 원문 변경] raise · 게시 0 · 첨부 0 · LLM 0")


def test_legacy_done_record_without_hash_is_skipped(t, slack, tmp_path, build):
    import json
    (tmp_path / "state.json").write_text(json.dumps({KEY: {"revs": {"r0": {"phase": "done", "ts": "1.0"}}, "root_ts": "1.0"}}))
    assert pub(t, make_md(tmp_path), tmp_path, build=build)["action"] == "skip" and build.calls == [] and slack.msgs == []
