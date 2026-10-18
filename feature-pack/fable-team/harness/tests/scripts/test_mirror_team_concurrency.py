"""팀 뿌리 글 동시성·재시작 — T9 두 writer 교차 · T10 늦은 update · T11 저장 뒤/답글 뒤 종료 (판정 623 r2 · 공용 잠금 1개)."""
import threading
import time
from pathlib import Path

import pytest
from _slack_fakes import FakeSlack
from _team_fakes import World, lib, tr


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


def test_t9_two_writers_cross_and_both_events_survive(tmp_path: Path, slack: FakeSlack):
    a, b = World(tmp_path, slack, {1: ["team:ops"]}), None
    a.send("#1", "k0")  # 뿌리 글 확보
    b = World(tmp_path, slack, {1: ["team:ops"]})  # 같은 파일·다른 프로세스 흉내
    ts = [threading.Thread(target=w.send, args=("#1", iid)) for w, iid in ((a, "k1"), (b, "k2"))]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert set(a.state()["roots"]["team:ops:2026-10-09"]["events"]) == {"k0", "k1", "k2"}
    assert "진행 3" in a.root("ops")["text"]


def test_t10_a_slow_update_cannot_overwrite_the_newer_screen(tmp_path: Path, slack: FakeSlack, monkeypatch):
    a, b = World(tmp_path, slack, {1: ["team:ops"]}), World(tmp_path, slack, {1: ["team:ops"]})
    a.send("#1", "m0")
    real, slow = lib.api_call, threading.Event()

    def laggy(base, token, method, params, **kw):
        if method == "chat.update" and not slow.is_set():
            slow.set()
            time.sleep(0.4)  # A 의 첫 update 가 늦다
        return real(base, token, method, params, **kw)

    monkeypatch.setattr(lib, "api_call", laggy)
    ta = threading.Thread(target=a.send, args=("#1", "m1"))
    ta.start()
    slow.wait(2)
    b.send("#1", "m2")  # 공용 잠금 때문에 A 의 update 가 끝난 뒤 실행 → 최신 상태로 그림
    ta.join()
    assert "진행 3" in a.root("ops")["text"]


def test_t11_crash_after_state_save_or_after_reply_recovers_without_duplicates(tmp_path: Path, slack: FakeSlack, monkeypatch):
    w = World(tmp_path, slack, {1: ["team:ops"]})
    w.send("#1", "n0")
    # (a) 상태 저장 뒤·update 전 종료
    monkeypatch.setattr(tr.TeamRoots, "_update", lambda self, ts, text: (_ for _ in ()).throw(SystemExit(1)))
    with pytest.raises(SystemExit):
        w.send("#1", "n1")
    monkeypatch.undo()
    w.rebuild()
    w.send("#1", "n1", resume=True)  # pending 재개 — 답글은 마커로 건너뜀 · 원장은 멱등
    assert len(w.replies_of("ops")) == 2 and "진행 2" in w.root("ops")["text"]
    # (b) 답글 뒤·원장 전 종료
    real = tr.TeamRoots.record
    monkeypatch.setattr(tr.TeamRoots, "record", lambda *a, **k: (_ for _ in ()).throw(SystemExit(1)))
    with pytest.raises(SystemExit):
        w.send("#1", "n2")
    monkeypatch.setattr(tr.TeamRoots, "record", real)
    w.send("#1", "n2", resume=True)
    assert len(w.replies_of("ops")) == 3 and "진행 3" in w.root("ops")["text"] and "n2" in w.state()["roots"]["team:ops:2026-10-09"]["events"]
