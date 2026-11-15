"""r2081 B Slack 새 업무 본문 = 앞서 넘긴 글과 새 글을 갈라 싣는다 · 적재된 쪽지에는 «깨움 실패» 알림 0 — 반례 ⑤~⑦ · 변이 M3~M5.

임시 root · 가짜 mbox(subprocess.run 대역) · 가짜 clock · 실 Slack·실 우편함·실 명부 0 · sleep 0 · 사례 1개 70초 안.
세계(world)·대역(Run·Clock) = test_slack_wake_resend.py 의 것을 그대로 읽는다(같은 꼴을 다시 만들지 않는다).
기준판 = FT2_R2081_BASE=<팩 origin/main 의 ft2 사본> 로 돌린다(표시 줄 없음 · 적재돼도 알림 1통 = ⑤·⑦ Red).
"""
import importlib.util
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
COMM = os.path.join(os.path.dirname(FT2), "legacy", "1.x", "harness", "comm")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


R = _load("r2081_resend_world", os.path.join(HERE, "test_slack_wake_resend.py"))
M = R._mods(os.environ.get("FT2_R2081_BASE") or FT2, tag="r2081")
DESK, W, C = R.DESK, R.W, R.C
MARK = "앞 글 %d줄(이미 넘긴 글 · 새 일 아님)"
ROOT, THIRD = "1794625001.000100", "1794625001.000300"


def _lineage():  # r1842 묶음 키 = 하네스 comm 의 thread_key 그대로(읽기만)
    sys.path.insert(0, COMM)
    try:
        return _load("r2081_mbox_lineage", os.path.join(COMM, "mbox_lineage.py"))
    finally:
        sys.path.remove(COMM)


def reply(router, root, ts, text):  # 같은 thread 답글 1건(binding 은 root 를 묶은 그대로)
    return router.route({"type": "message", "team": W, "channel": C, "user": R.U, "ts": ts, "thread_ts": root,
                         "text": text})


def third_post(root_dir, monkeypatch, steps, m=M):
    """같은 thread 3번째 글까지 + 사이에 다른 thread 글 1건 — (run, receive, router, hub, clock)."""
    clock = R.Clock()
    run, receive, router, hub = R.world(root_dir, monkeypatch, clock, steps, m=m)
    R.say(router, ROOT, "첫 글")
    reply(router, ROOT, "1794625001.000200", "둘째 글")
    R.say(router, "1794625009.000100", "다른 thread 글")
    reply(router, ROOT, THIRD, "셋째 글")
    return run, receive, router, hub, clock


def marks(body):  # 갈래 표시 2줄
    return [line for line in body.splitlines() if line.startswith("앞 글 ") or line == "새 글"]


# ── ⑤ B1 갈래 표시 ─────────────────────────────────────────────────────────────────────
def case_five(m, root_dir, monkeypatch):
    run = third_post(root_dir, monkeypatch, [{"rc": 0}], m=m)[0]
    bodies = [b for b in R.bodies(run) if " · thread %s · " % ROOT in b.splitlines()[0]]
    return bodies[0].splitlines(), bodies[-1].splitlines()


def test_five_third_post_marks_prior_and_new(tmp_path, monkeypatch):
    first, third = case_five(M, tmp_path, monkeypatch)
    assert first == ["[Slack] 새 업무 · thread %s · command %s" % (ROOT, R.cmd(ROOT)), "%s %s 첫 글" % (ROOT, R.U)]  # 1줄 = 기준판 바이트
    assert len(third) == 6 and third[1] == MARK % 2 and third[4] == "새 글"
    assert [line.split()[-2] for line in third[2:4] + third[5:]] == ["첫", "둘째", "셋째"]
    assert "다른" not in "\n".join(third)  # 다른 thread 글은 섞이지 않는다


# ── ⑥ B2 세 길(처음 · 재기동 복구 · 재전송)이 같은 조립을 지난다 ────────────────────────────
def case_six(m, root_dir, monkeypatch):
    steps = [{"rc": 0}, {"rc": 0}, {"rc": 0}, {"timeout": True}, {"rc": 0}]
    run, receive, _router, _hub, clock = third_post(root_dir / "resend", monkeypatch, steps, m=m)
    clock.tick(60)
    receive.pass_idle()
    first, resent = R.bodies(run)[-2], R.bodies(run)[-1]
    run2, _receive2, router2, hub2, _clock2 = third_post(root_dir / "restart", monkeypatch, steps, m=m)
    command = R.cmd(THIRD)
    row = [r for r in router2.entries(m.route.ROUTE) if r.get("command") == command][-1]
    hub2.recovered({"state": m.route.DISPATCHED, "command": command, "key": row["key"]})
    return first, R.bodies(run2)[-1], resent


def test_six_three_paths_same_marks(tmp_path, monkeypatch):
    first, recovered, resent = case_six(M, tmp_path, monkeypatch)
    assert marks(first) == marks(recovered) == marks(resent) == [MARK % 2, "새 글"]
    assert recovered == first and resent.splitlines()[:-1] == first.splitlines()
    assert resent.splitlines()[-1] == "재전송 2/3"
    assert _lineage().thread_key({"from": R.SENDER, "body": resent, "seq": 1}) == (W, C, ROOT)  # r1842 묶음 키 그대로


# ── ⑦ B3·B4 적재된 쪽지 = 알림 0 · 나머지 알림은 기준판 ──────────────────────────────────
def case_seven(m, root_dir, monkeypatch):
    got = []
    for name, step in (("landed", {"rc": 1, "land": True, "seq": 101}), ("lost", {"rc": 1}),
                       ("slow", {"timeout": True, "land": True, "seq": 101})):
        run, _receive, router, hub = R.world(root_dir / name, monkeypatch, R.Clock(), [step], m=m)
        R.say(router, "1794625101.000100")
        got.append((len(R.wakes(run, DESK)), len(R.wrows(root_dir / name, "alert")), len(hub.candidates)))
    return got


def test_seven_landed_note_gets_no_alert(tmp_path, monkeypatch):  # (desk 알림 깨움, alert 줄, 후보)
    assert case_seven(M, tmp_path, monkeypatch) == [(0, 0, 0), (1, 1, 1), (0, 0, 0)]


def test_seven_other_alert_unchanged(tmp_path, monkeypatch):  # B4 — 다른 사유(용량 부족) 알림 = 1통 그대로
    run, _receive, _router, hub = R.world(tmp_path, monkeypatch, R.Clock(), [{"rc": 0}])
    hub.alert({"command": "c9", "reason": M.receive.RESULT_FULL}, quiet=True)
    assert [b.splitlines()[0] for b in R.bodies(run, DESK)] == [
        "[Slack] 알림 %s · thread None · command c9" % M.receive.RESULT_FULL]


# ── 변이 M3~M5 (사본에서만 · 원본 결과 = 위 사례) ─────────────────────────────────────────
MUTANTS = [
    ("M3", '["앞 글 %d줄(이미 넘긴 글 · 새 일 아님)" % (len(lines) - 1)] + ', "",
     case_five, lambda got: len(got[1]) == 6 and got[1][1] == MARK % 2),
    ("M4", "+ marked(lines) + tail", "+ (list(lines) if resend else marked(lines)) + tail",
     case_six, lambda got: marks(got[0]) == marks(got[2])),
    ("M5", ' and (self.last_wake or {}).get("landed") != "있음"', "",
     case_seven, lambda got: got[0] == (0, 0, 0)),
]


@pytest.mark.parametrize("mid,old,new,scenario,ok", MUTANTS, ids=[row[0] for row in MUTANTS])
def test_mutants_caught(tmp_path, monkeypatch, mid, old, new, scenario, ok):
    if os.environ.get("FT2_R2081_BASE"):
        pytest.skip("기준판 회차 = 변이 0")
    assert not ok(scenario(R._mutant(tmp_path, R.WR, old, new), tmp_path / "world", monkeypatch)), mid   # 변이 = 계약 칸 FAIL
