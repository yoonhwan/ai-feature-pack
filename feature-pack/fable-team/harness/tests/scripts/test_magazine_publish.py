"""설계 §9 시험 7 + 2b(push 계약) — 가짜 Slack HTTP 서버 · 임시 리포+가짜 origin. 실 슬랙·실 push·실 LLM 0.

★장애 주입 4종 — 각각 «다음 실행 뿌리 게시 추가 = 0» 줄을 출력한다 (pytest -s 로 보인다).
실행: python3 -m pytest tests/scripts/test_magazine_publish.py -q
"""
import json
import time
from pathlib import Path

import pytest
from _magazine_fakes import FakeMagazineSlack

import magazine_publish as mp
from magazine_slack import Target, find_root, marker
from mirror_lib import MirrorError

DATE = "2026-10-08"


@pytest.fixture
def slack() -> FakeMagazineSlack:
    return FakeMagazineSlack()


def make_day(tmp_path: Path) -> mp.Day:
    pdf = tmp_path / "m.pdf"
    pdf.write_bytes(b"%PDF-fake")
    return mp.Day(DATE, f"*{marker(DATE)}*\n요약", pdf, time.time() - 3600, "sha")


def tgt(slack: FakeMagazineSlack) -> Target:
    return Target(slack.base, "tok", "C1", "U1")


def phase(state: Path) -> str:
    return json.loads(state.read_text())[DATE]["phase"]


def test_full_flow_then_done_is_skipped(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    r = mp.publish_day(tgt(slack), day, st)
    assert r["action"] == "published" and len(slack.roots) == 1 and phase(st) == "done"
    assert slack.uploads == [b"%PDF-fake"] and slack.files[0]["thread_ts"] == slack.roots[0]["ts"]
    assert mp.publish_day(tgt(slack), day, st)["action"] == "skip" and len(slack.roots) == 1
    assert mp.publish_day(tgt(slack), day, st, force=True)["action"] == "published" and len(slack.roots) == 2


def test_slack_unreachable_raises_before_any_state(tmp_path):
    st = tmp_path / "s.json"
    dead = Target("http://127.0.0.1:9", "tok", "C1", "U1")
    with pytest.raises(MirrorError):
        mp.publish_day(dead, make_day(tmp_path), st)
    assert not st.exists()  # 표식 확인(history)에서 먼저 raise — 게시 시도도 상태도 없다


def test_inject1_response_lost_next_run_adopts_marker(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    slack.drop_after_create = True
    with pytest.raises(MirrorError):
        mp.publish_day(tgt(slack), day, st)
    before = len(slack.roots)
    mp.publish_day(tgt(slack), day, st)
    print(f"[응답 유실] 다음 실행 뿌리 게시 추가 = {len(slack.roots) - before}")
    assert before == 1 and len(slack.roots) == 1 and slack.files[0]["thread_ts"] == slack.roots[0]["ts"] and phase(st) == "done"


def test_inject2_state_write_fails_after_root(slack, tmp_path, monkeypatch):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    real, calls = mp.save_state, []

    def flaky(path, data):
        calls.append(1)
        if len(calls) == 2:  # posting 은 쓰고, 뿌리 성공 뒤 posted 쓰기는 실패
            raise PermissionError("read-only")
        real(path, data)

    monkeypatch.setattr(mp, "save_state", flaky)
    with pytest.raises(mp.PublishError, match="상태 쓰기 실패"):
        mp.publish_day(tgt(slack), day, st)
    monkeypatch.setattr(mp, "save_state", real)
    before = len(slack.roots)
    mp.publish_day(tgt(slack), day, st)
    print(f"[상태 쓰기 실패] 다음 실행 뿌리 게시 추가 = {len(slack.roots) - before}")
    assert before == 1 and len(slack.roots) == 1 and phase(st) == "done"


def test_inject3_pdf_upload_fails_next_run_retries_pdf_only(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    slack.fail_complete = True
    with pytest.raises(MirrorError):
        mp.publish_day(tgt(slack), day, st)
    assert phase(st) == "posted" and not slack.files
    slack.fail_complete = False
    before = len(slack.roots)
    mp.publish_day(tgt(slack), day, st)
    print(f"[PDF 실패] 다음 실행 뿌리 게시 추가 = {len(slack.roots) - before}")
    assert before == 1 and len(slack.roots) == 1 and len(slack.files) == 1 and phase(st) == "done"


def test_inject4_posting_without_marker_refuses_then_force_root(slack, tmp_path):
    st, day = tmp_path / "s.json", make_day(tmp_path)
    st.write_text(json.dumps({DATE: {"phase": "posting", "at": "t"}}))
    with pytest.raises(mp.PublishError, match="불명 상태") as e:
        mp.publish_day(tgt(slack), day, st)
    print(f"[posting+표식 없음] 다음 실행 뿌리 게시 추가 = {len(slack.roots)} ({e.value})")
    assert len(slack.roots) == 0 and phase(st) == "posting"
    mp.publish_day(tgt(slack), day, st, force_root=True)
    assert len(slack.roots) == 1 and phase(st) == "done"


def test_find_root_needs_exact_first_line_not_mirror_posts(slack, tmp_path):
    """같은 봇·같은 채널의 슬랙 미러 글(첫 줄에 표식 문구가 «들어 있을» 뿐)을 매거진 뿌리 글로 오인하면 안 된다."""
    oldest = time.time() - 3600
    slack.msgs.append({"ts": f"{time.time():.6f}", "text": f"#885 시작 — {marker(DATE)} 수동 발행 시험\n상세", "bot_id": "B1", "thread_ts": ""})
    print(f"[미러식 첫 줄] find_root = {find_root(tgt(slack), DATE, oldest)}")
    assert find_root(tgt(slack), DATE, oldest) is None
    st, day = tmp_path / "s.json", make_day(tmp_path)
    mp.publish_day(tgt(slack), day, st)
    own = slack.roots[1]
    assert len(slack.roots) == 2 and own["text"].startswith(f"*{marker(DATE)}*")
    assert slack.files[0]["thread_ts"] == own["ts"] != slack.roots[0]["ts"]  # PDF 는 미러 스레드가 아니라 내 뿌리 글에
    print(f"[정확한 첫 줄] find_root = ts 채택({find_root(tgt(slack), DATE, oldest) == own['ts']})")
    assert find_root(tgt(slack), DATE, oldest) == own["ts"]
