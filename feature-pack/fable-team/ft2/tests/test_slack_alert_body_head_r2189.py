"""r2189 Slack 알림 쪽지 첫 줄 = 답 글 머리 · 질문 글 머리 — 반례 ②~⑨ · 변이 M1~M3 (① = 기존 tests/test_slack_*.py 재실행).

임시 root · 가짜 mbox(subprocess.run 대역) · 가짜 clock · 실 Slack·실 우편함·실 명부 0 · sleep 0 · 사례 1개 70초 안.
세계(world)·대역(Run·Clock) = test_slack_wake_resend.py 의 것을 그대로 읽는다.
기준판 = FT2_R2189_BASE=<팩 origin/main 의 ft2 사본> 로 돌린다(조각 0 = ② ③ ④ Red).
"""
import importlib.util
import json
import os

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


R = _load("r2189_resend_world", os.path.join(HERE, "test_slack_wake_resend.py"))
M = R._mods(os.environ.get("FT2_R2189_BASE") or FT2, tag="r2189")
DESK, W, C, U = R.DESK, R.W, R.C, R.U
Q, A = "1794902664.078689", "1794902756.417979"     # 질문(thread 첫 글) ts · 답 ts
QTEXT = "[질문 다시]  AGENTS.md 은퇴 도구(Serena·Context7) 지시를\n걷어내는 PR 9026 을 합쳐도 될까요? 다시 여쭙니다"
REOPEN = "재개 필요"


def fold(text):
    return " ".join(text.split())


def body(why, command, ts=Q, answer=None, question=None):
    parts = "".join(" · %s «%s»" % (name, text) for name, text in (("답", answer), ("질문", question)) if text)
    return "[Slack] 알림 %s%s · thread %s · command %s" % (why, parts, ts, command)


def world(root_dir, monkeypatch, m=M):
    run, receive, router, hub = R.world(root_dir, monkeypatch, R.Clock(), [{"rc": 0}], m=m)
    return run, receive, router, hub


def bot_post(router, ts=Q, text=QTEXT, channel=C, thread=None):
    event = {"type": "message", "team": W, "channel": channel, "bot_id": "BTANK", "user": "UTANK", "ts": ts, "text": text}
    return router.route(dict(event, **({"thread_ts": thread} if thread else {})))


def human(router, ts, text, thread=None):
    event = {"type": "message", "team": W, "channel": C, "user": U, "ts": ts, "text": text}
    return router.route(dict(event, **({"thread_ts": thread} if thread else {})))


def desk_bodies(run):
    return R.bodies(run, DESK)


# ── ② 실사건 꼴 · ⑦ 머리와 재귀 ─────────────────────────────────────────────────────
def case_two(m, root_dir, monkeypatch):
    run, _receive, router, _hub = world(root_dir, monkeypatch, m)
    bot_post(router)
    human(router, A, "네", thread=Q)
    return desk_bodies(run)


def test_two_real_case_answer_and_question_head(tmp_path, monkeypatch):
    got = case_two(M, tmp_path, monkeypatch)
    assert got == [body(REOPEN, R.cmd(A), answer="네", question=fold(QTEXT)[:40] + "…")]


def test_seven_head_and_no_recursion(tmp_path, monkeypatch):
    run, receive, router, hub = world(tmp_path, monkeypatch)
    run.alert = {"rc": 1}                                          # 알림 깨움 실패
    bot_post(router)
    row = human(router, A, "네", thread=Q)
    assert len(desk_bodies(run)) == 1 and desk_bodies(run)[0].startswith("[Slack] 알림")
    assert R.seat_wakes(tmp_path) == []                            # 좌석 깨움 후보 0(G1)
    hub.alert(row)                                                 # 같은 command · 사유 = 둘째 알림 0
    receive.pass_idle()
    assert len(desk_bodies(run)) == 1 and run.alerts == 1          # 알림의 알림 0


# ── ③ 긴 답 ─────────────────────────────────────────────────────────────────────
def case_three(m, root_dir, monkeypatch):
    run, _receive, router, _hub = world(root_dir, monkeypatch, m)
    bot_post(router)
    human(router, A, "가나다라마바사아자차\n카타파하거너더러머버\n서어저처커터퍼허고노도로모보", thread=Q)
    return desk_bodies(run)


def test_three_long_answer_cut_one_line(tmp_path, monkeypatch):
    got = case_three(M, tmp_path, monkeypatch)
    assert got == [body(REOPEN, R.cmd(A), answer="가나다라마바사아자차 카타파하거너더러머" + "…",
                        question=fold(QTEXT)[:40] + "…")]
    assert "\n" not in got[0]


# ── ④ 사람이 쓴 첫 글 ──────────────────────────────────────────────────────────────
def case_four(m, root_dir, monkeypatch):
    run, _receive, router, _hub = world(root_dir, monkeypatch, m)
    human(router, Q, "사람이 쓴 첫 질문 글입니다 머리 사십 자를 넘기려고 길게 길게 길게 씁니다")
    human(router, A, "네", thread=Q)
    return desk_bodies(run)[-1]


def test_four_human_first_post_is_question(tmp_path, monkeypatch):
    first = "사람이 쓴 첫 질문 글입니다 머리 사십 자를 넘기려고 길게 길게 길게 씁니다"
    assert case_four(M, tmp_path, monkeypatch) == body(REOPEN, R.cmd(A), answer="네", question=first[:40] + "…")


# ── ⑤ 조각 없음 = 기준판 바이트 ─────────────────────────────────────────────────────
def test_five_no_fragment_same_bytes(tmp_path, monkeypatch):
    run, _receive, _router, hub = world(tmp_path, monkeypatch)
    hub.alert({"command": "c9", "reason": M.receive.RESULT_FULL}, quiet=True)
    hub.alert({"command": "c8", "kind": REOPEN, "key": [W, C, "1794900000.000100"]})
    hub.alert({"command": "c7", "kind": REOPEN, "key": [W, C, "1794900000.000200"], "digest": ""})
    assert desk_bodies(run) == ["[Slack] 알림 %s · thread None · command c9" % M.receive.RESULT_FULL,
                                "[Slack] 알림 재개 필요 · thread 1794900000.000100 · command c8",
                                "[Slack] 알림 재개 필요 · thread 1794900000.000200 · command c7"]


# ── ⑥ 글자 ────────────────────────────────────────────────────────────────────────
def case_six(m, root_dir, monkeypatch):
    run, _receive, router, _hub = world(root_dir, monkeypatch, m)
    mark = root_dir / "pwned"
    human(router, Q, "질문 «인용» 글")
    human(router, A, '«네» `$(touch %s)` "q"' % mark, thread=Q)
    return run, mark


def test_six_quotes_shell_one_arg(tmp_path, monkeypatch):
    run, mark = case_six(M, tmp_path, monkeypatch)
    call = [c for c in run.calls if c[-3] == DESK][-1]
    expected = '‹네› `$(touch %s)` "q"' % mark
    assert call[-1] == body(REOPEN, R.cmd(A), answer=expected[:20] + "…", question="질문 ‹인용› 글")
    assert call[-3:-1] == [DESK, M.SENDER] and not mark.exists()               # 본문 인자 1개 · 표식 0


# ── ⑧ 옛 장부(head 칸 없음) ─────────────────────────────────────────────────────────
def test_eight_old_receive_line_no_question(tmp_path, monkeypatch):
    run, receive, router, _hub = world(tmp_path, monkeypatch)
    with open(receive.path, "a", encoding="utf-8") as handle:   # 옛 판이 쓴 봇 첫 글 ignored 줄(head 0)
        handle.write(json.dumps({"state": "ignored", "command": R.cmd(Q), "key": [W, C, Q], "reason": "bot",
                                 "attempts": 0, "acked": True, "schema": 1, "at": "2026-11-17T17:04:24"}) + "\n")
    human(router, A, "네", thread=Q)
    assert desk_bodies(run) == [body(REOPEN, R.cmd(A), answer="네")]


# ── ⑨ 다른 채널의 봇 첫 글 = head 0 ─────────────────────────────────────────────────
def test_nine_other_channel_bot_no_head(tmp_path, monkeypatch):
    run, receive, router, hub = world(tmp_path, monkeypatch)
    bot_post(router, channel="COTHER")
    bot_post(router, ts="1794902700.000100", thread=Q)              # 허용 채널 봇 답글(첫 글 아님) = head 0
    assert [r for r in receive.entries() if "head" in r] == []
    hub.alert({"command": "cx", "kind": REOPEN, "key": [W, "COTHER", Q], "digest": "네"})
    assert desk_bodies(run) == [body(REOPEN, "cx", answer="네")]


# ── 변이 (사본에서만 · 원본 결과 = 위 사례 PASS) ──────────────────────────────────────────
WR, RX = R.WR, R.RX
CLIP = '    text = " ".join(str(text or "").split()).replace("«", "‹").replace("»", "›")\n' \
       '    return text[:size] + "…" if len(text) > size else text\n'
MUTANTS = [
    ("M1", WR, 'row.get("digest"), self.question(key)', "None, self.question(key)", (case_two, case_three)),
    ("M2", RX, '            row["head"] = head\n', "", (case_two,)),
    ("M3", WR, CLIP, "    return str(text or \"\")\n", (case_three, case_six)),
]
ORIGINAL = {case_two: test_two_real_case_answer_and_question_head, case_three: test_three_long_answer_cut_one_line,
            case_six: test_six_quotes_shell_one_arg}


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


@pytest.mark.parametrize("mid,rel,old,new,cases", MUTANTS, ids=[row[0] for row in MUTANTS])
def test_mutants_caught(tmp_path, monkeypatch, mid, rel, old, new, cases):
    if os.environ.get("FT2_R2189_BASE"):
        pytest.skip("기준판 회차 = 변이 0")
    mutant = R._mutant(tmp_path, rel, old, new)
    for case in cases:
        test = ORIGINAL[case]
        assert not _passes(test, mutant, tmp_path / ("m-" + case.__name__), monkeypatch), (mid, case.__name__)
        assert _passes(test, M, tmp_path / ("o-" + case.__name__), monkeypatch), (mid, "원본", case.__name__)


def test_m2_keeps_four(tmp_path, monkeypatch):   # M2 receive head 0 이어도 ④ 는 PASS(사람 첫 글 = route 줄)
    if os.environ.get("FT2_R2189_BASE"):
        pytest.skip("기준판 회차 = 변이 0")
    mutant = R._mutant(tmp_path, RX, MUTANTS[1][2], "")
    assert _passes(test_four_human_first_post_is_question, mutant, tmp_path / "m4", monkeypatch)
