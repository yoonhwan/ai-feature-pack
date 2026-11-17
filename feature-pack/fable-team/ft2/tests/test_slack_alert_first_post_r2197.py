"""r2197 사람 새 thread 첫 글 알림 = 답 조각 1 · 질문 조각 0 — 반례 ②~⑥ · 변이 M1~M2 (① = r2189 시험 재실행).

임시 root · 가짜 mbox(subprocess.run 대역) · 가짜 clock · 실 Slack·네트워크 0 · sleep 0 · 사례 1개 70초 안.
세계·대역 = test_slack_alert_body_head_r2189.py 의 것을 그대로 읽는다(그 파일 고친 줄 0).
기준판 = FT2_R2197_BASE=<팩 origin/main 의 ft2 사본> 로 돌린다(② ④ Red).
"""
import importlib.util
import os

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


H = _load("r2197_head_world", os.path.join(HERE, "test_slack_alert_body_head_r2189.py"))
R = H.R
M = R._mods(os.environ.get("FT2_R2197_BASE") or FT2, tag="r2197")
W, C, Q, A, REOPEN, body = H.W, H.C, H.Q, H.A, H.REOPEN, H.body
FIRST = "사람이 새로 연 thread 첫 글"


# ── ② 사람 새 thread 첫 글 = 답 1 · 질문 0 ─────────────────────────────────────────────
def case_two(m, root_dir, monkeypatch):
    run, _receive, router, _hub = H.world(root_dir, monkeypatch, m)
    H.human(router, Q, FIRST)
    return H.desk_bodies(run)


def test_two_first_post_answer_only(tmp_path, monkeypatch):
    assert case_two(M, tmp_path, monkeypatch) == [body(REOPEN, R.cmd(Q), answer=FIRST)]


# ── ③ 같은 thread 의 사람 답글 = 두 조각 그대로 ──────────────────────────────────────────
def test_three_reply_keeps_both(tmp_path, monkeypatch):
    run, _receive, router, _hub = H.world(tmp_path, monkeypatch, M)
    H.human(router, Q, FIRST)
    H.human(router, A, "네", thread=Q)
    assert H.desk_bodies(run)[-1] == body(REOPEN, R.cmd(A), answer="네", question=FIRST)


# ── ④ 첫 글인데 digest 0 = 조각 0 바이트 ───────────────────────────────────────────────
def test_four_first_post_no_digest_no_fragment(tmp_path, monkeypatch):
    run, _receive, router, hub = H.world(tmp_path, monkeypatch, M)
    H.human(router, Q, FIRST)                                       # route 에 첫 글 digest 있음
    hub.alert({"command": R.cmd(Q), "kind": "다른 사유", "key": [W, C, Q], "digest": ""})
    assert H.desk_bodies(run)[-1] == "[Slack] 알림 다른 사유 · thread %s · command %s" % (Q, R.cmd(Q))


# ── ⑤ thread 없음 = 질문 0(기준판 그대로) ──────────────────────────────────────────────
def test_five_no_thread_no_question(tmp_path, monkeypatch):
    run, _receive, _router, hub = H.world(tmp_path, monkeypatch, M)
    hub.alert({"command": "c5", "kind": REOPEN, "key": [W, C, None], "digest": "답"})
    assert H.desk_bodies(run) == [body(REOPEN, "c5", ts=None, answer="답")]


# ── ⑥ 다른 글인데 답과 질문 글자가 우연히 같음 = 두 조각 그대로 ─────────────────────────────
def case_six(m, root_dir, monkeypatch):
    run, _receive, router, _hub = H.world(root_dir, monkeypatch, m)
    H.human(router, Q, "네")
    H.human(router, A, "네", thread=Q)
    return H.desk_bodies(run)[-1]


def test_six_same_text_other_post_keeps_both(tmp_path, monkeypatch):
    assert case_six(M, tmp_path, monkeypatch) == body(REOPEN, R.cmd(A), answer="네", question="네")


# ── 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더) ────────────────────────────────
MINE = "key[2] and command == receive.command_for(receive.Key(*key))"
MUTANTS = [
    ("M1", R.WR, "self.question(key) if not mine else None", "self.question(key)", case_two,
     test_two_first_post_answer_only),
    ("M2", R.WR, MINE, 'key[2] and row.get("digest") == self.question(key)', case_six,
     test_six_same_text_other_post_keeps_both),
]


def _passes(test, m, root_dir, monkeypatch):
    global M
    saved, M = M, m
    try:
        test(root_dir, monkeypatch)
        return True
    except AssertionError:
        return False
    finally:
        M = saved


@pytest.mark.parametrize("mid,rel,old,new,case,test", MUTANTS, ids=[row[0] for row in MUTANTS])
def test_mutants_caught(tmp_path, monkeypatch, mid, rel, old, new, case, test):
    if os.environ.get("FT2_R2197_BASE"):
        pytest.skip("기준판 회차 = 변이 0")
    mutant = R._mutant(tmp_path, rel, old, new)
    assert not _passes(test, mutant, tmp_path / ("m-" + case.__name__), monkeypatch), (mid, case.__name__)
    assert _passes(test, M, tmp_path / ("o-" + case.__name__), monkeypatch), (mid, "원본", case.__name__)
