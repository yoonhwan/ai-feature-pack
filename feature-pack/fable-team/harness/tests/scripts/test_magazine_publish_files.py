"""설계 §9 시험 5 (파일 첨부 · DA HOLD-F1) — 가짜 Slack 의 장애 주입. 실 슬랙 0.

★각 주입은 «다음 실행 파일 추가 = N» 줄을 출력한다 (pytest -s 로 보인다).
실행: python3 -m pytest tests/scripts/test_magazine_publish_files.py -q -s
"""
import json
import time
from pathlib import Path

import pytest
from _magazine_fakes import FakeMagazineSlack

import magazine_publish as mp
from magazine_attach import AttachError, attach
from magazine_slack import Target, marker
from mirror_lib import MirrorError

DATE = "2026-10-08"
PDF_T, HTML_T = f"아침 매거진 {DATE} PDF r0", f"아침 매거진 {DATE} HTML r0"


@pytest.fixture
def slack() -> FakeMagazineSlack:
    return FakeMagazineSlack()


def make_day(tmp_path: Path, html: bool = True) -> mp.Day:
    pdf, easy = tmp_path / "m.pdf", tmp_path / "m.html"
    pdf.write_bytes(b"%PDF-fake")
    easy.write_text("<html>쉬운 판</html>")
    return mp.Day(DATE, f"*{marker(DATE)}*\n요약", pdf, time.time() - 3600, "sha", easy if html else None)


def tgt(slack: FakeMagazineSlack) -> Target:
    return Target(slack.base, "tok", "C1", "U1")


def rec(state: Path) -> dict:
    return json.loads(state.read_text())[DATE]


def titles(slack: FakeMagazineSlack) -> list[str]:
    return slack.titles(slack.roots[0]["ts"])


def test_pdf_then_html_flow_ends_pdf_done_then_done(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    assert mp.publish_day(tgt(slack), day, st)["action"] == "published"
    assert titles(slack) == [PDF_T, HTML_T] and rec(st)["phase"] == "done" and set(rec(st)["files"]) == {"pdf", "html"}  # files 칸 보존
    assert mp.publish_day(tgt(slack), day, st)["action"] == "skip" and len(titles(slack)) == 2


def test_html_fails_after_pdf_rerun_attaches_html_only(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    slack.fail_complete_at = {2}  # 두 번째 complete(HTML) 거절 — ok=false = 공유 안 된 것이 확실
    with pytest.raises(MirrorError):
        mp.publish_day(tgt(slack), day, st)
    assert rec(st)["phase"] == "pdf_done" and titles(slack) == [PDF_T]
    mp.publish_day(tgt(slack), day, st)
    print(f"[PDF 뒤 HTML 실패] 재실행 PDF 추가 = {titles(slack).count(PDF_T) - 1} · HTML 추가 = {titles(slack).count(HTML_T)}")
    assert titles(slack) == [PDF_T, HTML_T] and rec(st)["phase"] == "done"


def test_no_html_day_goes_pdf_done_to_done(slack, tmp_path):
    st = tmp_path / "s.json"
    mp.publish_day(tgt(slack), make_day(tmp_path, html=False), st)
    assert titles(slack) == [PDF_T] and rec(st)["phase"] == "done"


def test_f1_complete_ok_but_response_lost_rerun_adopts_by_title(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    slack.drop_after_complete = True  # PDF 공유는 성공했는데 응답이 유실
    with pytest.raises(MirrorError):
        mp.publish_day(tgt(slack), day, st)
    assert rec(st)["phase"] == "posted" and rec(st)["files"]["pdf"]["phase"] == "sharing"
    mp.publish_day(tgt(slack), day, st)
    print(f"[PDF complete 뒤 응답 유실] 재실행 PDF 파일 추가 = {titles(slack).count(PDF_T) - 1}")
    assert titles(slack).count(PDF_T) == 1 and titles(slack).count(HTML_T) == 1 and slack.upload_url_calls == 2


def test_f1_complete_ok_but_pdf_done_save_fails_rerun_adopts(slack, tmp_path, monkeypatch):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    real, calls = mp.save_state, []

    def flaky(path, data):
        calls.append(1)
        if len(calls) == 4:  # posting · posted · 시도 기록 은 쓰고, complete 성공 뒤 pdf_done 쓰기는 실패
            raise PermissionError("read-only")
        real(path, data)

    monkeypatch.setattr(mp, "save_state", flaky)
    with pytest.raises(mp.PublishError, match="상태 쓰기 실패"):
        mp.publish_day(tgt(slack), day, st)
    monkeypatch.setattr(mp, "save_state", real)
    mp.publish_day(tgt(slack), day, st)
    print(f"[pdf_done 저장 실패] 재실행 PDF 파일 추가 = {titles(slack).count(PDF_T) - 1}")
    assert titles(slack) == [PDF_T, HTML_T] and rec(st)["phase"] == "done"


def test_f1_html_complete_ok_done_save_fails_rerun_adopts(slack, tmp_path, monkeypatch):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    real, calls = mp.save_state, []

    def flaky(path, data):
        calls.append(1)
        if len(calls) == 6:  # posting · posted · pdf 시도 · pdf_done · html 시도 → 6번째 = done 쓰기
            raise PermissionError("read-only")
        real(path, data)

    monkeypatch.setattr(mp, "save_state", flaky)
    with pytest.raises(mp.PublishError):
        mp.publish_day(tgt(slack), day, st)
    monkeypatch.setattr(mp, "save_state", real)
    mp.publish_day(tgt(slack), day, st)
    print(f"[done 저장 실패] 재실행 HTML 파일 추가 = {titles(slack).count(HTML_T) - 1}")
    assert rec(st)["phase"] == "done" and titles(slack) == [PDF_T, HTML_T]


def test_f1_unknown_blocks_with_no_new_file_id_then_force_file(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    slack.drop_after_complete = slack.hide_shared_files = True  # 공유됐을 수도 있는데 스레드에 표식이 안 보임
    with pytest.raises(MirrorError):
        mp.publish_day(tgt(slack), day, st)
    urls, completes = slack.upload_url_calls, slack.complete_calls
    with pytest.raises(AttachError, match="불명") as e:
        mp.publish_day(tgt(slack), day, st)
    print(f"[불명] getUploadURL 추가 = {slack.upload_url_calls - urls} · complete 재호출 = {slack.complete_calls - completes} · {e.value}")
    assert slack.upload_url_calls == urls and slack.complete_calls == completes and rec(st)["phase"] == "posted"
    slack.hide_shared_files = False
    mp.publish_day(tgt(slack), day, st, force_file=("pdf",))
    assert slack.upload_url_calls == urls + 2 and rec(st)["phase"] == "done"  # PDF 새 첨부 1 + HTML 1


def test_similar_title_other_rev_is_not_adopted(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    mp.publish_day(tgt(slack), day, st)
    root = slack.roots[0]["ts"]
    attach(tgt(slack), root, "pdf", day.pdf, f"아침 매거진 {DATE} PDF r1", attempt=None, save=lambda a: None)
    assert slack.titles(root).count(f"아침 매거진 {DATE} PDF r1") == 1 and len(slack.titles(root)) == 3  # r1 은 r0 로 채택되지 않고 새로 붙음


def test_replies_lookup_failure_raises_and_sends_nothing(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    slack.fail_replies = True
    with pytest.raises(MirrorError):
        mp.publish_day(tgt(slack), day, st)
    assert slack.upload_url_calls == 0 and slack.uploads == []  # 조회 실패를 «표식 없음» 으로 삼키지 않는다


def test_attempt_save_failure_blocks_remote_send(slack, tmp_path, monkeypatch):
    st, day = tmp_path / "s.json", make_day(tmp_path)

    def boom(*_a):
        raise mp.PublishError("상태 쓰기 실패(pdf 시도)")

    monkeypatch.setattr(mp, "set_file_attempt", boom)
    with pytest.raises(mp.PublishError, match="pdf 시도"):
        mp.publish_day(tgt(slack), day, st)
    print(f"[시도 기록 저장 실패] 바이트 전송 = {len(slack.uploads)} · complete = {slack.complete_calls}")
    assert slack.uploads == [] and slack.complete_calls == 0  # 기록 «전» 에 공유하지 않는다


def test_set_phase_keeps_files_and_revs(tmp_path):
    st = tmp_path / "s.json"
    st.write_text(json.dumps({DATE: {"phase": "posted", "ts": "1.0", "files": {"pdf": {"phase": "sharing"}}, "revs": {"r1": {"phase": "done"}}}}))
    mp.set_phase(st, DATE, "pdf_done", ts="1.0")
    got = rec(st)
    assert got["phase"] == "pdf_done" and got["files"] == {"pdf": {"phase": "sharing"}} and got["revs"] == {"r1": {"phase": "done"}}
