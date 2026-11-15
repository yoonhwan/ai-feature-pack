"""r2081 B Slack 새 업무 본문 = 그 command 에 묶인 «이번 글» 과 같은 thread 의 다른 글(맥락)을 갈라 싣는다 · 적재된 쪽지에는
«깨움 실패» 알림 0 — 반례 ⑤~⑦ · 변이 M3~M5 · M8 · M9 (보정 판 카드 1d734f4f64 · DA HOLD-IMPL #311912 반례 = ⑤ ㉡ ㉢).

임시 root · 가짜 mbox(subprocess.run 대역) · 가짜 clock · 실 Slack·실 우편함·실 명부 0 · sleep 0 · 사례 1개 70초 안.
세계(world)·대역(Run·Clock) = test_slack_wake_resend.py 의 것을 그대로 읽는다(같은 꼴을 다시 만들지 않는다).
재전송 · 재기동 복구는 제품 길(receive.pass_idle → Wiring._resend → deliver · Wiring.recovered → deliver)을 그대로 돈다.
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
DESK, W, C, U = R.DESK, R.W, R.C, R.U
OTHER = "같은 thread 다른 글 %d줄(맥락 · 이 command 의 글 아님)"
THIS, UNREAD = "이번 글", "이번 글 판독 불가(command 의 글 ts 가 thread 기록에 없음)"
ROOT = "1794625001.000100"
TS = ["1794625001.%06d" % (100 + 100 * i) for i in range(6)]   # 같은 thread 글 ts(0번 = root)
NAMES = ["첫", "둘째", "셋째", "넷째", "다섯째", "여섯째"]


def _lineage():  # r1842 묶음 키 = 하네스 comm 의 thread_key 그대로(읽기만)
    sys.path.insert(0, COMM)
    try:
        return _load("r2081_mbox_lineage", os.path.join(COMM, "mbox_lineage.py"))
    finally:
        sys.path.remove(COMM)


def line(i):  # route NOTE 줄 꼴(ts 사용자 글)
    return "%s %s %s 글" % (TS[i], U, NAMES[i])


def post(router, i):  # 같은 thread i 번째 글 1건(0 = root · 나머지 = 답글)
    if i == 0:
        return R.say(router, ROOT, "%s 글" % NAMES[0])
    return router.route({"type": "message", "team": W, "channel": C, "user": U, "ts": TS[i], "thread_ts": ROOT,
                         "text": "%s 글" % NAMES[i]})


def thread_bodies(run):  # 이 thread 좌석 깨움 본문(줄 목록)
    return [b.splitlines() for b in R.bodies(run) if " · thread %s · " % ROOT in b.splitlines()[0]]


def head(i):
    return "[Slack] 새 업무 · thread %s · command %s" % (ROOT, R.cmd(TS[i]))


def marks(lines):  # 갈래 표시 줄만
    return [x for x in lines if x.startswith("같은 thread 다른 글 ") or x in (THIS, UNREAD)]


def world(root_dir, monkeypatch, steps, m):
    clock = R.Clock()
    run, receive, router, hub = R.world(root_dir, monkeypatch, clock, steps, m=m)
    return run, receive, router, hub, clock


# ── ⑤ B1 갈래 표시 — 사례마다 (얻은 값, 기대 값) 을 돌려준다(변이 판정이 같은 칸을 본다) ──────────────────
def case_normal(m, root_dir, monkeypatch):   # ㉠ A · B 적재 뒤 C (사이에 옆 thread 글) · 첫 글 1줄 = 기준판 바이트
    run, _receive, router, _hub, _clock = world(root_dir, monkeypatch, [{"rc": 0}], m)
    post(router, 0), post(router, 1)
    R.say(router, "1794625009.000100", "옆 thread 글")
    post(router, 2)
    bodies = thread_bodies(run)
    return (bodies[0], bodies[1], bodies[2]), (
        [head(0), line(0)],
        [head(1), OTHER % 1, line(0), THIS, line(1)],
        [head(2), OTHER % 2, line(0), line(1), THIS, line(2)])


def case_resend(m, root_dir, monkeypatch):   # ㉡ A 미적재(rc 1 · 적재 없음) → B 유입 → A 재전송(DA 반례)
    run, receive, router, _hub, clock = world(root_dir, monkeypatch, [{"rc": 1}, {"rc": 0}, {"rc": 0}], m)
    post(router, 0), post(router, 1)
    clock.tick(60)
    receive.pass_idle()
    return thread_bodies(run)[-1], [head(0), OTHER % 1, line(1), THIS, line(0), "재전송 2/3"]


def case_restart(m, root_dir, monkeypatch):  # ㉢ 같은 상태(A 미적재 → B)에서 재기동 복구 전달 = 이번 글 A
    run, _receive, router, hub, _clock = world(root_dir, monkeypatch, [{"rc": 1}, {"rc": 0}, {"rc": 0}], m)
    post(router, 0), post(router, 1)
    row = [r for r in router.entries(m.route.ROUTE) if r.get("command") == R.cmd(TS[0])][-1]
    hub.recovered({"state": m.route.DISPATCHED, "command": R.cmd(TS[0]), "key": row["key"]})
    return thread_bodies(run)[-1], [head(0), OTHER % 1, line(1), THIS, line(0)]


def case_six_posts(m, root_dir, monkeypatch):  # ㉣ 글 6개 thread 에서 1번째 글 재전송 = 이번 글 1번째 · 다른 글 = 최근 3줄
    run, receive, router, _hub, clock = world(root_dir, monkeypatch, [{"rc": 1}] + [{"rc": 0}] * 6, m)
    for i in range(6):
        post(router, i)
    clock.tick(60)
    receive.pass_idle()
    return thread_bodies(run)[-1], [head(0), OTHER % 3, line(3), line(4), line(5), THIS, line(0), "재전송 2/3"]


def case_unread(m, root_dir, monkeypatch):   # ㉤ command 가 slack 꼴 아님 · NOTE 에 그 ts 없음 = 판독 불가 1줄 + 최근 줄(기준판)
    run, _receive, router, hub, _clock = world(root_dir, monkeypatch, [{"rc": 0}], m)
    post(router, 0), post(router, 1)
    row = router.entries(m.route.ROUTE)[-1]
    recent = router.context(m.binding.thread_key(*row["key"]))
    got = []
    for command in ("receipt-x", R.cmd("1794625001.999999")):
        hub.deliver(R.MASTER, m.route.NEW, recent, dict(row, command=command), resend=True)
        got.append(R.bodies(run)[-1].splitlines())
    want = [["[Slack] 새 업무 · thread %s · command %s" % (ROOT, c), UNREAD] + recent
            for c in ("receipt-x", R.cmd("1794625001.999999"))]
    return got, want


@pytest.mark.parametrize("case", [case_normal, case_resend, case_restart, case_six_posts, case_unread],
                         ids=["normal", "resend_A_after_B", "restart_A_after_B", "six_posts", "unreadable"])
def test_five_this_post_is_the_command_post(tmp_path, monkeypatch, case):
    got, want = case(M, tmp_path, monkeypatch)
    assert got == want


def test_five_other_thread_not_mixed(tmp_path, monkeypatch):
    got, _want = case_normal(M, tmp_path, monkeypatch)
    assert "옆 thread" not in "\n".join("\n".join(b) for b in got)


# ── ⑥ B2 세 길(처음 · 재기동 복구 · 재전송)이 같은 조립을 지난다 ────────────────────────────
def case_six(m, root_dir, monkeypatch):
    steps = [{"rc": 0}, {"rc": 0}, {"timeout": True}, {"rc": 0}]
    run, receive, router, _hub, clock = world(root_dir / "resend", monkeypatch, steps, m)
    for i in range(3):
        post(router, i)
    clock.tick(60)
    receive.pass_idle()
    first, resent = thread_bodies(run)[-2], thread_bodies(run)[-1]
    run2, _receive2, router2, hub2, _clock2 = world(root_dir / "restart", monkeypatch, steps, m)
    for i in range(3):
        post(router2, i)
    row = [r for r in router2.entries(m.route.ROUTE) if r.get("command") == R.cmd(TS[2])][-1]
    hub2.recovered({"state": m.route.DISPATCHED, "command": R.cmd(TS[2]), "key": row["key"]})
    return first, thread_bodies(run2)[-1], resent


def test_six_three_paths_same_marks(tmp_path, monkeypatch):
    first, recovered, resent = case_six(M, tmp_path, monkeypatch)
    assert marks(first) == marks(recovered) == marks(resent) == [OTHER % 2, THIS]
    assert recovered == first and resent[:-1] == first and resent[-1] == "재전송 2/3"
    assert _lineage().thread_key({"from": R.SENDER, "body": "\n".join(resent), "seq": 1}) == (W, C, ROOT)  # r1842 묶음 키


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


# ── 변이 (사본에서만 · 원본 결과 = 위 사례 PASS) — ok(얻은 값) 가 거짓이어야 변이를 잡은 것 ─────────────────
def _same(got):
    return got[0] == got[1]


MUTANTS = [
    ("M3", '["같은 thread 다른 글 %d줄(맥락 · 이 command 의 글 아님)" % len(others)] + ', "", case_normal, _same),
    ("M4", "+ self.compose(row, command, lines) + tail", "+ (list(lines) if resend else self.compose(row, command, lines)) + tail",
     case_six, lambda got: marks(got[0]) == marks(got[2])),
    ("M5", ' and (self.last_wake or {}).get("landed") != "있음"', "",
     case_seven, lambda got: got[0] == (0, 0, 0)),
    ("M8", 'hit = [i for i, line in enumerate(notes) if ts and line.split(" ", 1)[0] == ts]',
     "hit = [len(notes) - 1] if notes else []", case_resend, _same),
    ("M9", "    if not hit:\n", "    if not hit and notes:\n        hit = [len(notes) - 1]\n    if not hit:\n",
     case_unread, _same),
]


@pytest.mark.parametrize("mid,old,new,scenario,ok", MUTANTS, ids=[row[0] for row in MUTANTS])
def test_mutants_caught(tmp_path, monkeypatch, mid, old, new, scenario, ok):
    if os.environ.get("FT2_R2081_BASE"):
        pytest.skip("기준판 회차 = 변이 0")
    assert not ok(scenario(R._mutant(tmp_path, R.WR, old, new), tmp_path / "world", monkeypatch)), mid
