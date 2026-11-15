"""r2065 행 G Slack 글 접수 뒤 깨움 실패 = 유휴 회차에 다시 보낸다 — ㉞가~㉞파 13칸 + 인수 칸 ㉞하·㉞거·㉞자·㉞타 · 변이 M34~M38.

임시 root · 가짜 mbox(subprocess.run 대역 = 회차별 rc·출력·적재 줄) · 가짜 clock · 가짜 장부(seq 경계) · 실 Slack·
실 우편함·실 명부 0 · sleep 0 · 사례 1개 70초 안. 기준판(wiring 재전송 없음)에서 ㉞가·㉞다·㉞아·㉞차 Red.
"""
import importlib.util
import inspect
import json
import os
import shutil
import subprocess
import time
import types

import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, C, U = "TFAKE", "CFAKE", "UOPPA"
MASTER, DESK, HMASTER = "byz-planner-master-pi#1", "byz-planner-desk-pi#1", "byz-harness-master-pi#1"
WR, RX = "adapters/slack/wiring.py", "adapters/slack/receive.py"
SENDER = "ft2-slack-listen"


def _mods(base=None, tag="base"):
    """ft2 사본 하나에서 wiring 을 읽는다 — wiring 이 스스로 읽는 route·receive·binding 도 같은 사본이다(변이용)."""
    root = str(base or os.environ.get("FT2_WAKE_BASE") or FT2)
    spec = importlib.util.spec_from_file_location("r2065g_%s_wiring" % tag, os.path.join(root, WR))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


M = _mods()


class Clock:  # 초 단위 가짜 시계 — at 문자열(time.strftime)과 now(초)를 같은 값에서 만든다
    def __init__(self, base=1794624000):
        self.t = float(base)

    def tick(self, seconds):
        self.t += seconds

    def stamp(self):
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(self.t))

    def now(self):
        return self.t


class Run:  # subprocess.run 대역 — 좌석 깨움은 회차별 rc·출력·적재(장부 seq 줄) · 알림·[긴급]은 alert 대본
    def __init__(self, root, steps, alert=None):
        self.root, self.steps, self.calls = str(root), list(steps or [{"rc": 0}]), []
        self.alert, self.seats, self.alerts = alert or {"rc": 0}, 0, 0
        self.ledger = os.path.join(self.root, ".fable-team", "comm", "mailbox.log.jsonl")

    def __call__(self, argv, timeout=None, **kw):
        self.calls.append(list(argv))
        if argv[-1].startswith(("[Slack] 알림", "[긴급]")):
            step, self.alerts = self.alert, self.alerts + 1
        else:
            step, self.seats = self.steps[min(self.seats, len(self.steps) - 1)], self.seats + 1
        if step.get("land"):
            with open(self.ledger, "a", encoding="utf-8") as handle:
                handle.write(json.dumps({"seq": step["seq"], "to": argv[-3], "from": argv[-2], "body": argv[-1]},
                                        ensure_ascii=False) + "\n")
        if step.get("timeout"):
            raise subprocess.TimeoutExpired(argv, timeout, output=str(step.get("out") or "").encode())
        return subprocess.CompletedProcess(argv, step.get("rc", 0), stdout=step.get("out") or "", stderr="")


class NoHub:  # 기준판에는 후보 표·재전송이 없다 — 계약 자리에서 FAIL 이 보이도록 빈 몸만 준다
    candidates = {}
    ledger = types.SimpleNamespace(tail_rows=lambda: None)

    def entries(self, *args, **kwargs):
        return []

    def wake(self, *args, **kwargs):
        return -1

    def critical(self, *args, **kwargs):
        return None


def world(root, monkeypatch, clock, steps, m=M, mail=None):
    """임시 root 1개 = 명부·장부·가짜 mbox · (run, receive, router, hub) 반환."""
    fable = root / ".fable-team"
    (fable / "comm").mkdir(parents=True)
    (fable / "seats-planner.json").write_text(json.dumps({"_master": MASTER, "_desk": DESK}), encoding="utf-8")
    (fable / "seats-harness.json").write_text(json.dumps({"_master": HMASTER}), encoding="utf-8")
    (fable / "seats-issues.json").write_text(json.dumps({"_master": "byz-issues-master-sol#1"}), encoding="utf-8")
    rows = [{"seq": 100, "body": "다른 쪽지"}] if mail is None else mail
    (fable / "comm" / "mailbox.log.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    monkeypatch.setenv("FT2_SLACK_WAKE", "fake-wake")
    run = Run(root, steps)
    monkeypatch.setattr(subprocess, "run", run)
    receive = m.receive.SlackReceive(str(root), ack=lambda event: None, team="planner", allowed_users=(U,),
                                     allowed_channels=(C,), clock=clock.stamp)
    extra = {"now": clock.now} if "now" in inspect.signature(m.wire).parameters else {}
    router, _notify = m.wire(str(root), receive=receive, bindings=m.binding.ThreadBinding(str(root), "planner"),
                             team="planner", clock=clock.stamp, **extra)
    return run, receive, router, getattr(getattr(receive, "resend", None), "__self__", None) or NoHub()


def say(router, ts, text="글"):
    """그 thread 를 좌석에 묶고 글 1건 접수(Listener.route 와 같은 binding → router 순서)."""
    router.binding.bind(M.binding.thread_key(W, C, ts), MASTER)
    return router.route({"type": "message", "team": W, "channel": C, "user": U, "ts": ts, "text": text})


def head_of(ts):
    return "[Slack] 새 업무 · thread %s · command %s" % (ts, cmd(ts))


def cmd(ts):
    return "slack:%s:%s:%s" % (W, C, ts)


def wrows(root, kind="wake"):
    path = os.path.join(str(root), ".fable-team", "teams", "planner", "slack", "wire.jsonl")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return [row for row in map(json.loads, filter(str.strip, handle)) if kind in (None, row.get("t"))]


def seat_wakes(root):
    """좌석 깨움 줄만 — 알림 wake([Slack] 알림 …)는 G1 후보가 아니므로 따로 센다."""
    return [row for row in wrows(root) if not str(row.get("head") or "").startswith("[Slack] 알림")]


def wakes(run, to=None):
    return [call for call in run.calls if to is None or call[-3] == to]


def bodies(run, to=MASTER):
    return [call[-1] for call in wakes(run, to)]


# ── ㉞가·㉞라·㉞마 : G1·G2 유휴 회차 재전송 ──────────────────────────────────────────────
def test_ga_timeout_then_idle_resend_one_body(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"timeout": True}, {"rc": 0}])
    ts = "1794624001.000100"
    say(router, ts)
    assert [row["rc"] for row in seat_wakes(tmp_path)] == [-1]   # 처음 시도 = 실패 1줄(재시도 0)
    clock.tick(60)
    assert receive.pass_idle()["reason"] == "재전송 2/3"
    assert [row["rc"] for row in seat_wakes(tmp_path)] == [-1, 0]
    lines = bodies(run)[-1].splitlines()
    assert lines[0] == head_of(ts) and lines[-1] == "재전송 2/3"
    clock.tick(60)
    assert receive.pass_idle()["reason"] == "무변화" and len(bodies(run)) == 2


def test_ra_idle_before_60s_resends_nothing(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"timeout": True}, {"rc": 0}])
    say(router, "1794624002.000100")
    clock.tick(30)
    assert receive.pass_idle()["reason"] == "무변화" and len(bodies(run)) == 1


def test_ma_two_candidates_one_per_idle(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, _hub = world(tmp_path, monkeypatch, clock,
                                      [{"timeout": True}, {"timeout": True}, {"rc": 0}, {"rc": 0}])
    say(router, "1794624003.000100"), say(router, "1794624003.000200")
    assert len(bodies(run)) == 2
    clock.tick(60)
    receive.pass_idle()
    assert len(bodies(run)) == 3                                  # 한 유휴 회차에 1통
    clock.tick(60)
    receive.pass_idle()
    assert len(bodies(run)) == 4
    assert [w.splitlines()[-1] for w in bodies(run)[2:]] == ["재전송 2/3", "재전송 2/3"]


# ── ㉞나·㉞자 : G1 적재 있음·알림은 후보 아님 ────────────────────────────────────────────
def test_na_landed_after_timeout_not_resent(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"timeout": True, "land": True, "seq": 101}])
    say(router, "1794624004.000100")
    assert wrows(tmp_path)[0]["landed"] == "있음"
    clock.tick(120)
    assert receive.pass_idle()["reason"] == "무변화" and len(bodies(run)) == 1


def test_ja_alert_wake_failure_never_resent(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, hub = world(tmp_path, monkeypatch, clock, [{"rc": 3, "out": "REJECT 알림"}])
    hub.wake(DESK, "[Slack] 알림 용량 부족 · thread 1 · command c1", "c1")
    assert hub.candidates == {}                                    # 알림 재귀 0
    clock.tick(120)
    assert receive.pass_idle()["reason"] == "무변화" and len(wakes(run)) == 1


# ── ㉞다 : G3·G8 3회 뒤 멈춤 + harness _master [긴급] 1통 ────────────────────────────────
def test_da_three_failures_then_critical_once(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, hub = world(tmp_path, monkeypatch, clock,
                                      [{"rc": 3, "out": "REJECT 좌석 이름"}])
    ts = "1794624005.000100"
    say(router, ts)
    for _ in range(3):                                             # 2회째·3회째 재전송
        clock.tick(60)
        receive.pass_idle()
    assert len(bodies(run, MASTER)) == 3                           # 4회째 0
    urgent = bodies(run, HMASTER)
    assert len(urgent) == 1 and urgent[0].startswith("[긴급] Slack 글 깨움 3회 실패")
    assert ("thread %s" % ts) in urgent[0] and ("command %s" % cmd(ts)) in urgent[0]
    assert "REJECT 좌석 이름" in urgent[0]
    assert [row["rc"] for row in seat_wakes(tmp_path)] == [3, 3, 3]
    assert [r["why"] for r in wrows(tmp_path, "alert")] == ["깨움 실패", "깨움 3회 실패"]
    clock.tick(120)
    receive.pass_idle()
    hub.critical(cmd(ts), MASTER, {})                               # 같은 command 둘째 [긴급] 0(dedup)
    assert len(bodies(run, MASTER)) == 3 and len(bodies(run, HMASTER)) == 1


# ── ㉞바·㉞사·㉞파 : G5 늦은 적재 확인 · G6 seq 경계 ────────────────────────────────────
def test_ba_late_landing_before_resend_sends_nothing(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"timeout": True}, {"rc": 0}])
    ts = "1794624006.000100"
    say(router, ts)
    assert len(bodies(run)) == 1
    with open(tmp_path / ".fable-team" / "comm" / "mailbox.log.jsonl", "a", encoding="utf-8") as handle:
        handle.write(json.dumps({"seq": 101, "to": MASTER, "from": SENDER, "body": head_of(ts) + "\n본문"},
                                ensure_ascii=False) + "\n")
    clock.tick(60)
    assert receive.pass_idle()["reason"] == "늦은 적재 확인"
    assert len(bodies(run)) == 1                                   # 같은 글 2통 0
    assert [(r["rc"], r.get("why")) for r in seat_wakes(tmp_path)] == [(-1, "상한 초과 · 적재 없음"), (0, "늦은 적재 확인")]


def test_sa_seq_boundary_ignores_older_same_head(tmp_path, monkeypatch):
    clock = Clock()
    ts = "1794624007.000100"
    old = {"seq": 100, "to": MASTER, "from": SENDER, "body": head_of(ts) + "\n본문"}
    run, receive, router, hub = world(tmp_path, monkeypatch, clock, [{"timeout": True}, {"rc": 0}], mail=[old])
    say(router, ts)
    assert wrows(tmp_path)[0]["seq0"] == 100                       # 경계 = 100
    assert wrows(tmp_path)[0]["landed"] == "없음"                   # 같은 초 이전 글은 적재가 아니다
    assert cmd(ts) in hub.candidates
    clock.tick(60)
    receive.pass_idle()
    assert len(bodies(run)) == 2 and bodies(run)[-1].splitlines()[-1] == "재전송 2/3"


def test_pa_unreadable_ledger_is_undecided_and_resent(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, hub = world(tmp_path, monkeypatch, clock, [{"timeout": True}, {"rc": 0}])
    ts = "1794624008.000100"
    (tmp_path / ".fable-team" / "comm" / "mailbox.log.jsonl").unlink()
    say(router, ts)
    assert wrows(tmp_path)[0]["landed"] == "판정 불가" and cmd(ts) in hub.candidates
    clock.tick(60)
    receive.pass_idle()
    assert len(bodies(run)) == 2 and bodies(run)[-1].splitlines()[-1] == "재전송 2/3"


# ── ㉞아 : G7 실패 출력 기록 ──────────────────────────────────────────────────────────────
def test_a_out_records_guard_reason(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, hub = world(tmp_path, monkeypatch, clock,
                                      [{"rc": 3, "out": "arena\nREJECT 좌석 이름 꼴 틀림 x\n"}])
    ts = "1794624009.000100"
    say(router, ts)
    row = wrows(tmp_path)[0]
    assert (row["rc"], row["out"]) == (3, "REJECT 좌석 이름 꼴 틀림 x")
    assert cmd(ts) in hub.candidates


# ── ㉞차·㉞카·㉞하·㉞거 : G9 재기동 · 인수 칸 ────────────────────────────────────────────
def _restart(tmp_path, monkeypatch, clock, steps, m=M):
    receive = m.receive.SlackReceive(str(tmp_path), ack=lambda event: None, team="planner", allowed_users=(U,),
                                     allowed_channels=(C,), clock=clock.stamp)
    extra = {"now": clock.now} if "now" in inspect.signature(m.wire).parameters else {}
    router, _notify = m.wire(str(tmp_path), receive=receive,
                             bindings=m.binding.ThreadBinding(str(tmp_path), "planner"), team="planner",
                             clock=clock.stamp, **extra)
    run = Run(tmp_path, steps)
    monkeypatch.setattr(subprocess, "run", run)
    return run, receive, router, getattr(getattr(receive, "resend", None), "__self__", None) or NoHub()


def test_cha_restart_resumes_attempt_count(tmp_path, monkeypatch):
    clock = Clock()
    _run, _receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"timeout": True}])
    ts = "1794624010.000100"
    say(router, ts)
    clock.tick(30)
    run, _receive, router, hub = _restart(tmp_path, monkeypatch, clock, [{"rc": 3, "out": "REJECT"}])
    assert hub.candidates[cmd(ts)]["attempts"] == 1
    router.recovered({"state": "dispatched", "command": cmd(ts), "key": [W, C, ts]})
    assert [row["rc"] for row in seat_wakes(tmp_path)] == [-1, 3]   # 실패한 깨움 = 넘긴 글이 아니다
    assert hub.candidates[cmd(ts)]["attempts"] == 2                 # 시도 수를 이어 센다
    assert len(bodies(run)) == 1


def test_ka_restart_after_success_wakes_nothing(tmp_path, monkeypatch):
    clock = Clock()
    _run, _receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"rc": 0}])
    ts = "1794624011.000100"
    say(router, ts)
    run, _receive, router, hub = _restart(tmp_path, monkeypatch, clock, [{"rc": 0}])
    assert hub.candidates == {}
    router.recovered({"state": "dispatched", "command": cmd(ts), "key": [W, C, ts]})
    assert len(seat_wakes(tmp_path)) == 1 and bodies(run) == []


def test_ha_restart_waits_60s_from_last_attempt(tmp_path, monkeypatch):
    clock = Clock()
    _run, _receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"timeout": True}])
    ts = "1794624012.000100"
    say(router, ts)
    later = Clock(base=clock.t + 30)                                # 마지막 시도에서 30초
    run, receive, _router, _hub = _restart(tmp_path, monkeypatch, later, [{"rc": 0}])
    assert receive.pass_idle()["reason"] == "무변화" and bodies(run) == []
    later.tick(30)                                                  # 60초
    assert receive.pass_idle()["reason"] == "재전송 2/3" and len(bodies(run)) == 1


def test_geo_restart_after_three_failures_sends_nothing(tmp_path, monkeypatch):
    clock = Clock()
    _run, receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"rc": 3}])
    ts = "1794624013.000100"
    say(router, ts)
    for _ in range(2):
        clock.tick(60)
        receive.pass_idle()
    assert len(seat_wakes(tmp_path)) == 3
    run, receive, _router, hub = _restart(tmp_path, monkeypatch, clock, [{"rc": 0}])
    assert hub.candidates == {}
    clock.tick(300)
    assert receive.pass_idle()["reason"] == "무변화" and bodies(run) == []


# ── ㉞너·㉞더·㉞러 : DA 311009 반례 3칸(recovered 상한 · 성공 때 후보 제거 · 마지막 적재 있음) ──
def test_neo_recovered_respects_three_cap(tmp_path, monkeypatch):
    clock = Clock()
    _run, receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"rc": 3}])
    ts = "1794624014.000100"
    say(router, ts)
    for _ in range(2):
        clock.tick(60)
        receive.pass_idle()
    assert len(seat_wakes(tmp_path)) == 3                          # 처음 시도 + 2 재전송 = 상한
    clock.tick(30)
    run, receive, router, hub = _restart(tmp_path, monkeypatch, clock, [{"rc": 3}])
    router.recovered({"state": "dispatched", "command": cmd(ts), "key": [W, C, ts]})
    assert len(seat_wakes(tmp_path)) == 3 and bodies(run) == []     # 재기동해도 4회째 0(G3·G9)
    assert hub.candidates == {}
    clock.tick(300)
    assert receive.pass_idle()["reason"] == "무변화" and len(seat_wakes(tmp_path)) == 3


def test_deo_recovered_success_clears_candidate(tmp_path, monkeypatch):
    clock = Clock()
    _run, _receive, router, _hub = world(tmp_path, monkeypatch, clock, [{"rc": 3}])
    ts = "1794624015.000100"
    say(router, ts)
    clock.tick(30)
    run, receive, router, hub = _restart(tmp_path, monkeypatch, clock, [{"rc": 0}])
    assert cmd(ts) in hub.candidates                                # 실패한 깨움 = 다시 보낼 후보
    router.recovered({"state": "dispatched", "command": cmd(ts), "key": [W, C, ts]})
    assert [r["rc"] for r in seat_wakes(tmp_path)] == [3, 0]         # recovered 가 2회째로 성공
    assert hub.candidates == {}                                     # 성공하면 후보에서 뺀다(G1·G10)
    clock.tick(120)
    assert receive.pass_idle()["reason"] == "무변화"
    assert [r["rc"] for r in seat_wakes(tmp_path)] == [3, 0]         # 60초 뒤 중복 발신 0


def test_reo_landed_on_last_attempt_is_success(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, router, hub = world(tmp_path, monkeypatch, clock,
                                      [{"rc": 3}, {"rc": 3}, {"timeout": True, "land": True, "seq": 101}])
    ts = "1794624016.000100"
    say(router, ts)
    for _ in range(2):
        clock.tick(60)
        receive.pass_idle()
    assert [(r["rc"], r["landed"]) for r in seat_wakes(tmp_path)] == [(3, "없음"), (3, "없음"), (-1, "있음")]
    assert bodies(run, HMASTER) == []                               # 적재 «있음» = 성공 · 거짓 3회 실패 [긴급] 0
    assert hub.candidates == {}
    assert [r["why"] for r in wrows(tmp_path, "alert")] == ["깨움 실패"]   # 첫 실패 알림 1통만


# ── ㉞타 : G10 빈 후보 표 = 읽기·쓰기·깨움 0 ────────────────────────────────────────────
def test_ta_empty_candidates_idle_reads_nothing(tmp_path, monkeypatch):
    clock = Clock()
    run, receive, _router, hub = world(tmp_path, monkeypatch, clock, [{"rc": 0}])
    reads = []
    monkeypatch.setattr(hub.ledger, "tail_rows", lambda: reads.append("ledger") or None)
    monkeypatch.setattr(hub, "entries", lambda *a, **kw: reads.append("wire") or [])
    before = [os.path.getsize(p) for p in (tmp_path / ".fable-team" / "teams").rglob("*.jsonl")]
    assert receive.pass_idle()["reason"] == "무변화"
    assert reads == [] and bodies(run) == []
    assert [os.path.getsize(p) for p in (tmp_path / ".fable-team" / "teams").rglob("*.jsonl")] == before


# ── 변이 M34~M38 ────────────────────────────────────────────────────────────────────────
def _mutant(tmp, rel, old, new):
    base = tmp / "ft2m"
    for part in ("core", "adapters"):
        shutil.copytree(os.path.join(FT2, part), base / part)
    text = (base / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, old                                # 변이 자리 정확히 1곳
    (base / rel).write_text(text.replace(old, new), encoding="utf-8")
    return _mods(base, tag=tmp.name)


def case_ga(m, root, monkeypatch):                                  # G1·G2 유휴 회차 재전송
    clock = Clock()
    run, receive, router, _hub = world(root, monkeypatch, clock, [{"timeout": True}, {"rc": 0}], m=m)
    say(router, "1794624104.000100")
    clock.tick(60)
    receive.pass_idle()
    return len(bodies(run))


def case_da(m, root, monkeypatch):                                  # 3회 실패 뒤 4회째 0
    clock = Clock()
    run, receive, router, _hub = world(root, monkeypatch, clock, [{"rc": 3, "out": "REJECT"}], m=m)
    say(router, "1794624100.000100")
    for _ in range(4):
        clock.tick(60)
        receive.pass_idle()
    return len(bodies(run, MASTER))


def case_ba(m, root, monkeypatch):                                  # G5 늦은 적재 확인
    clock = Clock()
    run, receive, router, _hub = world(root, monkeypatch, clock, [{"timeout": True}, {"rc": 0}], m=m)
    ts = "1794624101.000100"
    say(router, ts)
    with open(os.path.join(str(root), ".fable-team", "comm", "mailbox.log.jsonl"), "a", encoding="utf-8") as handle:
        handle.write(json.dumps({"seq": 101, "to": MASTER, "from": SENDER, "body": head_of(ts) + "\n본문"},
                                ensure_ascii=False) + "\n")
    clock.tick(60)
    receive.pass_idle()
    return len(bodies(run))


def case_sa(m, root, monkeypatch):                                  # G6 seq 경계
    clock = Clock()
    ts = "1794624102.000100"
    old = {"seq": 100, "to": MASTER, "from": SENDER, "body": head_of(ts) + "\n본문"}
    run, receive, router, _hub = world(root, monkeypatch, clock, [{"timeout": True}, {"rc": 0}], m=m, mail=[old])
    say(router, ts)
    clock.tick(60)
    receive.pass_idle()
    return len(bodies(run))


def case_cha(m, root, monkeypatch):                                 # G9 재기동
    clock = Clock()
    _run, _receive, router, _hub = world(root, monkeypatch, clock, [{"timeout": True}], m=m)
    ts = "1794624103.000100"
    say(router, ts)
    run, _receive, router, _hub = _restart(root, monkeypatch, clock, [{"rc": 0}], m=m)
    router.recovered({"state": "dispatched", "command": cmd(ts), "key": [W, C, ts]})
    return len(bodies(run))


MUTANTS = [  # (변이, 파일, 바꿀 글, 새 글, 시나리오, 깨짐 판정)
    ("M34", RX, "sent = self.resend() if self.resend else None", "sent = None",
     case_ga, lambda got: got != 2),
    ("M35", WR, "RESEND_GAP, RESEND_CAP, ALERT_HEAD = 60, 3,", "RESEND_GAP, RESEND_CAP, ALERT_HEAD = 60, 9,",
     case_da, lambda got: got != 3),
    ("M36", WR, "        if self.landed_after(cand.get(\"seq0\"), to, head) == \"있음\":", "        if False:",
     case_ba, lambda got: got != 1),
    ("M37", WR, "        got = self.ledger.arrived(seen, mark, to, head, sender=SENDER)",
     "        got = self.ledger.arrived(seen, -1, to, head, sender=SENDER)",
     case_sa, lambda got: got != 2),
    ("M38", WR, "or self.woke(command):", "or any(not str(r.get(\"head\") or \"\").startswith(\"[Slack] 알림\")"
     " for r in self.entries(\"wake\") if r.get(\"command\") == command):",
     case_cha, lambda got: got != 1),
]


@pytest.mark.parametrize("mid,rel,old,new,scenario,broken", MUTANTS, ids=[row[0] for row in MUTANTS])
def test_mutants_caught(tmp_path, monkeypatch, mid, rel, old, new, scenario, broken):
    assert broken(scenario(_mutant(tmp_path, rel, old, new), tmp_path / "world", monkeypatch)), mid
