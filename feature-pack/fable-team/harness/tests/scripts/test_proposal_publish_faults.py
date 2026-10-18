# ruff: noqa: F401, F811
"""설계 §7-3 ★장애 주입(DA HOLD-P2)★ — 전부 «다음 실행 게시 추가 = 0» 줄을 출력한다 (pytest -s 로 보인다). 실 슬랙 0."""
import json

import pytest
from _proposal_fakes import KEY, build, make_md, pub, slack, t  # fixture(slack·t) 재사용 — 인자 이름이 import 이름과 같다(F811 의도)

from _thread_fakes import card, commit_all, ledger, resume_script

import byz_proposal_publish as bp
import proposal_state as ps
from magazine_attach import AttachError


def test_r0_response_lost_rerun_adopts_root(t, slack, tmp_path):
    md = make_md(tmp_path)
    slack.drop_next_post = True
    with pytest.raises(Exception):  # noqa: B017 — 응답 유실은 MirrorError
        pub(t, md, tmp_path)
    assert len(slack.roots) == 1
    pub(t, md, tmp_path)
    assert len(slack.roots) == 1 and len(slack.files) == 2
    print("[r0 응답 유실 → 재실행] 뿌리 글 추가 = 0")


def test_r1_response_lost_rerun_adopts_by_exact_first_line(t, slack, tmp_path):
    md = make_md(tmp_path)
    pub(t, md, tmp_path)
    slack.drop_next_post = True
    with pytest.raises(Exception):  # noqa: B017
        pub(t, md, tmp_path, "r1")
    pub(t, md, tmp_path, "r1")
    assert len(slack.replies) == 1
    print("[r1 응답 유실 → 재실행] 답글 추가 = 0")


def test_r1_state_write_failure_rerun_adopts(t, slack, tmp_path, monkeypatch):
    md = make_md(tmp_path)
    pub(t, md, tmp_path)
    real = ps.save_state

    def flaky(path, st):
        if st.get(KEY, {}).get("revs", {}).get("r1", {}).get("phase") == "posted":
            raise OSError("disk full")
        real(path, st)

    monkeypatch.setattr(ps, "save_state", flaky)
    with pytest.raises(bp.PublishError):
        pub(t, md, tmp_path, "r1")
    assert len(slack.replies) == 1
    monkeypatch.setattr(ps, "save_state", real)
    pub(t, md, tmp_path, "r1")
    assert len(slack.replies) == 1
    print("[r1 답글 뒤 상태 쓰기 실패 → 재실행] 답글 추가 = 0")


def test_r1_attach_failure_rerun_attaches_only(t, slack, tmp_path):
    md = make_md(tmp_path)
    pub(t, md, tmp_path)
    slack.fail_complete = True
    with pytest.raises(Exception):  # noqa: B017
        pub(t, md, tmp_path, "r1")
    assert len(slack.replies) == 1
    slack.fail_complete = False
    pub(t, md, tmp_path, "r1")
    assert len(slack.replies) == 1 and len(slack.files) == 4
    print("[r1 답글 뒤 첨부 실패 → 재실행] 답글 추가 = 0 (첨부만)")


def test_r1_posting_without_remote_mark_is_error_exit_1(slack, tmp_path, capsys):
    md = make_md(tmp_path)
    tok = tmp_path / "tok.env"
    tok.write_text("YOONHWAN_BOT_TOKEN=x\n")
    commit_all(tmp_path)
    argv = [str(md), "--state", str(tmp_path / "state.json"), "--token-file", str(tok), "--slack-base", slack.base, "--channel", "C1",
            "--card", str(card(tmp_path)), "--ledger", str(ledger(tmp_path)), "--seat", "s#1", "--resume-script", str(resume_script(tmp_path))]
    assert bp.run(bp.parse_args(argv)) == 0
    st = json.loads((tmp_path / "state.json").read_text())
    st[KEY]["revs"]["r1"] = {"phase": "posting"}
    (tmp_path / "state.json").write_text(json.dumps(st))
    n = len(slack.msgs)
    rc = bp.run(bp.parse_args(argv + ["--revision", "r1"]))
    err = capsys.readouterr().err
    print(f"[r1 posting + 표식 없음] rc={rc} · {err.strip().splitlines()[-1]} · 게시 추가 = {len(slack.msgs) - n}")
    assert rc == 1 and "불명" in err and "--force-post" in err and len(slack.msgs) == n


@pytest.mark.parametrize("n,kind", [(1, "text/markdown"), (2, "text/html")])
def test_complete_ok_but_response_lost_rerun_adopts_title(t, slack, tmp_path, build, n, kind):
    md = make_md(tmp_path)
    slack.complete_faults[n] = "applied"
    with pytest.raises(Exception):  # noqa: B017 — 공유됐는데 응답 유실
        pub(t, md, tmp_path, build=build)
    pub(t, md, tmp_path, build=build)
    assert len(slack.files) == 2 and slack.upload_types.count(kind) == 1
    print(f"[{kind} complete 성공 뒤 응답 유실 → 재실행] 제목 표식 채택 · {kind} 업로드 추가 = 0")


def test_share_ok_then_state_write_fails_rerun_adopts(t, slack, tmp_path, build, monkeypatch):
    md = make_md(tmp_path)
    real = ps.save_state

    def flaky(path, st):
        if st.get(KEY, {}).get("revs", {}).get("r0", {}).get("files", {}).get("md", {}).get("phase") == "done":
            raise OSError("disk full")
        real(path, st)

    monkeypatch.setattr(ps, "save_state", flaky)
    with pytest.raises(bp.PublishError):
        pub(t, md, tmp_path, build=build)
    monkeypatch.setattr(ps, "save_state", real)
    pub(t, md, tmp_path, build=build)
    assert slack.upload_types.count("text/markdown") == 1 and len(slack.files) == 2
    print("[md 공유 뒤 상태 쓰기 실패 → 재실행] md 업로드 추가 = 0")


def test_sharing_without_remote_mark_is_blocked_not_absorbed(t, slack, tmp_path, build):
    md = make_md(tmp_path)
    slack.complete_faults[1] = "dropped"
    with pytest.raises(Exception):  # noqa: B017 — complete 응답 유실(공유 여부 불명)
        pub(t, md, tmp_path, build=build)
    uploads = len(slack.upload_types)
    with pytest.raises(AttachError, match="불명"):
        pub(t, md, tmp_path, build=build)
    assert len(slack.upload_types) == uploads and slack.files == [] and _phase(tmp_path) != "done"
    pub(t, md, tmp_path, build=build, force_file="md")
    assert len(slack.files) == 2
    print("[sharing + 표식 없음] 불명 차단 · 업로드 추가 = 0 · --force-file md 뒤에만 진행")


def test_every_phase_save_keeps_hash_files_and_omitted(t, slack, tmp_path, build, monkeypatch):
    md = make_md(tmp_path)
    build.fail = "AI 풀이 0건"
    seen = []
    real = ps.save_state
    monkeypatch.setattr(ps, "save_state", lambda path, st: (seen.append(json.loads(json.dumps(st[KEY]["revs"]["r0"]))), real(path, st))[1])
    pub(t, md, tmp_path, build=build)
    phases = [r["phase"] for r in seen]
    print(f"[저장 순서] {phases}")
    assert phases == ["posting", "posted", "posted", "posted", "done"]  # 글 전 · 글 뒤 · md 시도(sharing) · md 완료 · 전체 완료
    assert all(r.get("md_hash") and r["html"]["phase"] == "omitted" for r in seen)
    assert all(r["files"]["md"] for r in seen if r["phase"] != "posting" and "files" in r) and "md" in seen[-1]["files"]


def test_md_and_html_come_from_one_read_snapshot(t, slack, tmp_path, build):
    md = make_md(tmp_path)
    original = md.read_bytes()

    def mutating_build(text, key, cmd):
        md.write_text(text + "\n읽은 뒤에 바뀐 줄\n", encoding="utf-8")  # 읽기 «뒤» 파일이 바뀐다
        return build(text, key, cmd)

    pub(t, md, tmp_path, build=mutating_build)
    assert slack.upload_bodies[0] == original and build.calls[0][1] == original.decode("utf-8")
    print("[읽은 뒤 파일 변경] 올라간 md = 읽은 바이트 · HTML 입력 = 같은 바이트")


def test_changed_md_in_posting_state_raises_before_cache_or_post(t, slack, tmp_path, build):
    md = make_md(tmp_path)
    slack.drop_next_post = True
    with pytest.raises(Exception):  # noqa: B017
        pub(t, md, tmp_path, build=build)
    n, calls = len(slack.msgs), len(build.calls)
    md.write_text(md.read_text() + "\n바뀐 원문\n", encoding="utf-8")
    with pytest.raises(bp.PublishError, match="다음 rN"):
        pub(t, md, tmp_path, build=build)
    assert len(slack.msgs) == n and len(build.calls) == calls


def _phase(tmp_path):
    return json.loads((tmp_path / "state.json").read_text())[KEY]["revs"]["r0"]["phase"]
