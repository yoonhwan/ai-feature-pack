"""r2380 (뒷 갈래 ⑭~⑳) — 기록 유지(F1·F2)·판정 불가·desk 없음·lint 스위치.

c14 점검이 안 나간 줄(6시간 안에 풀림)은 풀림 0통 · c15 F1 트리를 못 읽은 실행 = 풀림 0 + 기록 유지(다음 실행 풀림 1통)
c16 F2 + DA H1 6시간마다 다시 1통(30시간 = 점검 4통) · 기록은 풀림까지 · c17 가짜 git log rc1 = 경보 0 + «판정 불가 사람 대기 <카드>» 1줄 + 다른 카드 그대로
c18 desk 없음 = 팀 master 에 풀림 1통 + «판정 불가 desk» 1줄 · c19 ts 없는 자유 문장 선행 = 경보 0 + a 줄 기준판과 같음 · c20 바깥 FT_LINT_HUMAN_WAIT=reject 를 감시가 지운다
앞 갈래(c06~c13) = test_stall_human_wait_r2380.py
"""
from pathlib import Path

import pytest

from _stall_world import World
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)
from _r2380_world import BASE_BIN, BIN, HUMAN, PLAIN, TS, desk, human, make_repo, put, scan, shim_git  # noqa: F401


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def test_c14_no_check_no_done(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 1})
    desk(w)
    _ = scan(w)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    assert not human(w, "사람 대기 풀림"), (human(w, "사람 대기"), r.stdout)


def test_c15_unreadable_tree_keeps_record(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    desk(w)
    _ = scan(w)
    shim_git(w, 'case "$PWD" in */wt-t1/*) [ "$1" = ls-tree ] && exit 1;; esac')
    r = scan(w)
    assert not human(w, "사람 대기 풀림"), (human(w, "사람 대기 풀림"), r.stdout)
    assert "판정 불가 사람 대기 t1" in r.stdout, r.stdout
    p = w.stub / "shim" / "git"
    p.unlink()  # 가짜 git 걷어내고 같은 상황(줄 지움)을 다시 — 기록이 남아 있으면 여기서 풀림 1통
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    assert len(human(w, "사람 대기 풀림")) == 1, (human(w, "사람 대기 풀림"), r.stdout)


def test_c16_record_survives_beyond_window(w: World) -> None:
    """F2 + DA H1 — 6시간 창이 지나면 같은 사건에 다시 1통(30시간 대기 = 점검 4통) · 기록은 풀림까지 남는다(그 뒤 줄 지움 = 풀림 1통)."""
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    desk(w)
    _ = scan(w)  # 나이 7시간 = 점검 1통
    for _ in range(3):  # 6시간마다 1통씩 — 기록이 창 안이면 0통(같은 사건), 창이 지나면 다시 1통
        w.advance(6 * 3600)
        _ = scan(w)
    assert len(human(w, "사람 대기 점검")) == 4, (len(human(w, "사람 대기 점검")), human(w, "사람 대기 점검"))
    w.advance(12 * 3600)  # 카드 나이 25+12 = 30시간대 — 점검 기록은 6시간 창 밖이지만 남아 있어야 한다(F2)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    assert len(human(w, "사람 대기 풀림")) == 1, (human(w, "사람 대기"), r.stdout)
    assert len(human(w, "사람 대기 점검")) == 4, human(w, "사람 대기 점검")


def test_c17_git_log_failure_is_one_line_other_card_kept(w: World) -> None:
    make_repo(w, "t1", {"대기/bad.md": HUMAN, "대기/ok.md": HUMAN}, {"대기/bad.md": 7, "대기/ok.md": 7})
    shim_git(w, 'case "$*" in *"대기/bad.md"*) case "$*" in *log*) exit 1;; esac;; esac')  # 묶음 log·카드별 log 둘 다 실패
    r = scan(w)
    hits = human(w, "사람 대기 점검")
    assert len(hits) == 1 and "ok" in hits[0], (hits, r.stdout)
    assert "판정 불가 사람 대기 bad" in r.stdout, r.stdout


def test_c18_no_desk_falls_back_to_master(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    _ = scan(w)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    hits = human(w, "사람 대기 풀림")
    assert len(hits) == 1 and hits[0].startswith("send|t1-master#1|"), (hits, r.stdout)
    assert "판정 불가 desk" in r.stdout, r.stdout


def test_c19_free_text_prereq_stays_unknown(w: World) -> None:
    body = "# h\n- 선행: 오빠 승인 대기 (master#66 #340166)\n"  # thread ts 없음 = K4 판정 불가(경보 0 · a 줄은 지금 그대로)
    make_repo(w, "t1", {"대기/h.md": body, "대기/ok.md": PLAIN.replace("# h", "# ok")}, {"대기/h.md": 7, "대기/ok.md": 0})
    r = scan(w)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)
    line = next((ln for ln in r.stdout.splitlines() if ln.startswith("a ")), "")
    assert "선행 미판정 1장 제외" in line, r.stdout
    if BASE_BIN:
        b = scan(w, BASE_BIN)
        bline = next((ln for ln in b.stdout.splitlines() if ln.startswith("a ")), "")
        assert line == bline, (line, bline)


def test_c20_watch_drops_the_lint_switch(w: World) -> None:
    """③b K5 — 바깥 환경에 FT_LINT_HUMAN_WAIT=reject 가 있어도 정체 감시는 그 스위치를 «지우고» lint 를 부른다(카드 판정·a 줄 글자 그대로)."""
    stub = w.stub / "lint-reject.sh"
    _ = stub.write_text('#!/bin/sh\n[ "$FT_LINT_HUMAN_WAIT" = reject ] && { echo "REJECT $1"; exit 1; }\nexit 0\n')
    stub.chmod(0o755)
    w.env["FT_INDEX_LINT"] = str(stub)
    w.env["FT_LINT_HUMAN_WAIT"] = "reject"
    make_repo(w, "t1", {"대기/ok.md": PLAIN.replace("# h", "# ok")}, {"대기/ok.md": 0})
    r = scan(w)
    line = next((ln for ln in r.stdout.splitlines() if ln.startswith("a ")), "")
    assert "대기 카드 1장(ok)" in line, (line, r.stdout)
