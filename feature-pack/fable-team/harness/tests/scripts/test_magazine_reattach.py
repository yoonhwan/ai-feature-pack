"""설계 §9 시험 5 (reattach) — 상태 revs.rN · 답글 첫 줄 정확 채택 · 장애 주입. 가짜 Slack 만 — 실 슬랙 0.

실행: python3 -m pytest tests/scripts/test_magazine_reattach.py -q -s
"""
import json
import time
from pathlib import Path

import pytest
from _magazine_fakes import FakeMagazineSlack

import magazine_publish as mp
import magazine_reattach as mr
from magazine_attach import AttachError
from magazine_slack import Target, marker
from mirror_lib import MirrorError

DATE, REV = "2026-10-08", "r1"
FIRST = f"*아침 매거진 {DATE} 재첨부 {REV}*"


@pytest.fixture
def slack() -> FakeMagazineSlack:
    return FakeMagazineSlack()


def make_day(tmp_path: Path, html: bool = True) -> mp.Day:
    pdf, easy = tmp_path / "m.pdf", tmp_path / "m-eli5.pdf"
    pdf.write_bytes(b"%PDF-fake")
    easy.write_bytes(b"%PDF-easy")
    return mp.Day(DATE, f"*{marker(DATE)}*\n요약", pdf, time.time() - 3600, "sha", easy if html else None)


def tgt(slack: FakeMagazineSlack) -> Target:
    return Target(slack.base, "tok", "C1", "U1")


def date_rec(st: Path) -> dict:
    return json.loads(st.read_text())[DATE]


@pytest.fixture
def done_day(slack, tmp_path):
    """r0 이 이미 done 인 날 — (state, day, root_ts)."""
    st, day = tmp_path / "s.json", make_day(tmp_path)
    mp.publish_day(tgt(slack), day, st)
    return st, day, slack.roots[0]["ts"]


def go(slack, st, day, **kw):
    return mr.reattach(tgt(slack), day, st, REV, mr.reply_text(DATE, REV, kw.pop("warn", None)), **kw)


def test_reattach_replies_in_thread_with_two_files_and_keeps_date_record(slack, done_day):
    st, day, root = done_day
    before = date_rec(st)
    res = go(slack, st, day)
    reply = slack.replies_of(root)[0]
    assert res["action"] == "reattached" and len(slack.roots) == 1 and reply["text"].split("\n")[0] == FIRST
    assert slack.titles(root)[-2:] == [f"아침 매거진 {DATE} 풀 디테일 {REV}", f"아침 매거진 {DATE} 쉬운 판 {REV}"]
    after = date_rec(st)
    print(f"[reattach 뒤 날짜 레코드] phase {before['phase']}→{after['phase']} · ts {before['ts']}→{after['ts']} · at 불변={before['at'] == after['at']}")
    assert (after["phase"], after["ts"], after["at"]) == (before["phase"], before["ts"], before["at"]) and after["revs"][REV]["phase"] == "done"
    assert mr.rev_done_ts(st, DATE, REV) == res["ts"] and go(slack, st, day)["action"] == "skip" and len(slack.replies_of(root)) == 1


def test_reply_response_lost_rerun_adopts_exact_first_line(slack, done_day):
    st, day, root = done_day
    slack.drop_after_create = True
    with pytest.raises(MirrorError):
        go(slack, st, day)
    before = len(slack.replies_of(root))
    go(slack, st, day)
    print(f"[답글 응답 유실] 재실행 답글 추가 = {len(slack.replies_of(root)) - before}")
    assert before == 1 and len(slack.replies_of(root)) == 1 and mr.rev_done_ts(st, DATE, REV)


def test_posted_state_write_fails_rerun_adopts_reply(slack, done_day, monkeypatch):
    st, day, root = done_day
    real, calls = mp.save_state, []

    def flaky(path, data):
        calls.append(1)
        if len(calls) == 2:  # posting 은 쓰고, 답글 성공 뒤 posted 쓰기는 실패
            raise PermissionError("read-only")
        real(path, data)

    monkeypatch.setattr(mp, "save_state", flaky)
    with pytest.raises(mp.PublishError, match="상태 쓰기 실패"):
        go(slack, st, day)
    monkeypatch.setattr(mp, "save_state", real)
    before = len(slack.replies_of(root))
    go(slack, st, day)
    print(f"[상태 쓰기 실패] 재실행 답글 추가 = {len(slack.replies_of(root)) - before}")
    assert before == 1 and len(slack.replies_of(root)) == 1 and mr.rev_done_ts(st, DATE, REV)


def test_posting_without_marker_is_unknown_error_not_a_repost(slack, done_day):
    st, day, root = done_day
    state = json.loads(st.read_text())
    state[DATE]["revs"] = {REV: {"phase": "posting", "at": "t"}}
    st.write_text(json.dumps(state))
    with pytest.raises(mp.PublishError, match="불명 상태") as e:
        go(slack, st, day)
    print(f"[posting+표식 없음] 답글 추가 = {len(slack.replies_of(root))} · {e.value}")
    assert slack.replies_of(root) == [] and len(slack.roots) == 1


def test_no_root_raises_and_posts_nothing(slack, tmp_path):
    day = make_day(tmp_path)
    with pytest.raises(mp.PublishError, match="뿌리 글 없음") as e:
        go(slack, tmp_path / "s.json", day)
    print(f"[뿌리 글 없음] raise · 게시 = {len(slack.msgs)} · {e.value}")
    assert slack.msgs == [] and not (tmp_path / "s.json").exists()


def test_root_found_only_in_channel_state_missing_still_threads_there(slack, tmp_path):
    day = make_day(tmp_path)
    slack.msgs.append({"ts": f"{time.time():.6f}", "text": f"*{marker(DATE)}*\n요약", "bot_id": "B1", "thread_ts": ""})
    go(slack, tmp_path / "s.json", day)
    assert len(slack.roots) == 1 and len(slack.replies_of(slack.roots[0]["ts"])) == 1


def test_rev_file_response_lost_rerun_adopts_by_rev_title(slack, done_day):
    st, day, root = done_day
    slack.drop_after_complete = True
    with pytest.raises(MirrorError):
        go(slack, st, day)
    go(slack, st, day)
    titles = slack.titles(root)
    print(f"[rN 파일 응답 유실] PDF rN 개수 = {titles.count(f'아침 매거진 {DATE} 풀 디테일 {REV}')} · 답글 = {len(slack.replies_of(root))}")
    assert titles.count(f"아침 매거진 {DATE} 풀 디테일 {REV}") == 1 and titles.count(f"아침 매거진 {DATE} 쉬운 판 {REV}") == 1
    assert len(slack.replies_of(root)) == 1 and date_rec(st)["revs"][REV]["files"]["pdf"]["phase"] in ("sharing", "failed")


def test_rev_unknown_file_blocks_with_no_new_upload(slack, done_day):
    st, day, root = done_day
    slack.drop_after_complete = slack.hide_shared_files = True
    with pytest.raises(MirrorError):
        go(slack, st, day)
    urls = slack.upload_url_calls
    with pytest.raises(AttachError, match="불명"):
        go(slack, st, day)
    assert slack.upload_url_calls == urls


def test_eli5_failed_day_reattaches_pdf_only_and_warning_is_escaped(slack, done_day):
    st, day, root = done_day
    no_html = mp.Day(day.date, day.text, day.pdf, day.oldest_epoch, day.md_sha, None)
    go(slack, st, no_html, warn="쉬운 판(HTML) 못 만들었어요 — 형식 오류 <@U9>")
    reply = slack.replies_of(root)[0]["text"]
    assert reply.splitlines()[-1] == "쉬운 판(HTML) 못 만들었어요 — 형식 오류 &lt;@U9&gt;"
    assert slack.titles(root)[-1] == f"아침 매거진 {DATE} 풀 디테일 {REV}" and "쉬운 판 r1" not in " ".join(slack.titles(root))
