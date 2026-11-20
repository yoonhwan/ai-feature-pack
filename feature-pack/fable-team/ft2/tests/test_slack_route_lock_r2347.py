"""r2347 ft2 Slack 보충·실시간 중복 깨움 — 반례 ①~⑧ + 변이 M1~M5 (기준판 Red = ① ② ⑧).

대역 = 가짜 ws(보낸 envelope 기록) + 가짜 Web API + 가짜 mbox(깨움 기록) + 두 스레드 경합 흉내.
경합은 주입 장벽(threading.Event — receive.handle 의 prior 읽기 직후 멈춤 · 다른 스레드 진입)으로만 만든다.
실 Slack·실 쪽지·실 자격 0 · sleep 0(기다림은 Event·wait_for 뿐) · 시험 1개 70초 안.
"""
import json, os, shutil, sys, threading, time  # noqa: E401
import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_slack_listen_reconnect_r2341 as base  # noqa: E401 — 회귀(⑦)는 그 판 사례를 그대로 돌린다
from test_slack_listen_reconnect_r2341 import (  # noqa: E401 — r2341 대역 그대로 쓴다
    FT2, Band, Clock, HELLO, env, ledger, listen_lines, make_listener, msg, pack_of, run_listener, wait_for)


class Rows(list):
    """장부 꼴 이름 1개(receive.jsonl · route.jsonl · bindings.jsonl) — 읽기만."""

    def __init__(self, root, name):
        super().__init__(ledger(root, name))
        self.name, self.root = name, root

    def where(self, **want):
        return [row for row in self if all(row.get(k) == v for k, v in want.items())]


class Gate:
    """주입 장벽 — n번째 latest() 읽기가 끝난 자리에서 멈춘다(잠금이면 다른 스레드는 그 앞에서 선다)."""

    def __init__(self, inner, nth=1, opened=False):
        self.inner, self.nth, self.n, self.opened = inner, nth, 0, opened
        self.entered, self.release = threading.Event(), threading.Event()

    def __call__(self):
        self.n += 1
        out = self.inner()
        if self.n == self.nth and not self.opened:  # opened = 변이·기준판 대조에서 장벽을 안 쓰는 판
            self.entered.set()
            self.release.wait(20)
        return out


class TrackWs:
    """가짜 ws — 보낸 envelope 을 «그때 그 글의 RECEIVED 장부 줄이 있었나» 와 함께 남긴다(차례 = ④·⑧)."""

    def __init__(self, rows, watch=None):
        self.rows, self.watch, self.sent = rows, watch, []  # watch = 그 글의 ts

    def send(self, data):
        self.sent.append((json.loads(data)["envelope_id"], self.seen()))

    def seen(self):
        return any(row.get("state") == "received" and row.get("key", [0, 0, ""])[2] == self.watch
                   for row in ledger(self.rows.root, self.rows.name))

    def recv(self, timeout=None):
        raise TimeoutError("유휴")


def bench(tmp, pack=None, ws=None):
    """Listener 하나 + 대역 — run 을 안 돌리고 route·_frame_of 를 시험이 직접 부른다."""
    clock = Clock()  # 대역 시계 1개로 ts·mono·ISO 를 같이 돌린다
    band = Band(tmp, clock)
    listener = make_listener(pack if pack is not None else pack_of(), band, clock)  # Pack 은 빈 dict = 거짓
    listener.ws = ws or TrackWs(Rows(tmp, "receive.jsonl"))
    listener.worker.start()  # 깨움 기록(가짜 mbox)까지 보려면 일꾼이 살아야 한다
    return listener, band, clock


def both(listener, first, second, gate):
    """두 스레드 경합 — 앞 스레드는 장벽(부르는 쪽이 꽂는다)에서 멈추고, 뒤 스레드가 그 사이에 진입한다."""
    done, out = threading.Event(), {}

    def call(name, event):
        out[name] = listener.route(event)

    front = threading.Thread(target=call, args=("front", first), daemon=True)
    front.start()
    assert gate.entered.wait(20), "장벽에 못 닿음"
    back = threading.Thread(target=call, args=("back", second), daemon=True)
    back.start()
    done.wait(0.5)  # 잠금이면 여기서 안 끝난다(막혀 있음) — 안 잠그면 뒤 스레드가 먼저 끝난다
    gate.release.set()
    front.join(20), back.join(20)
    return out


def wakes_of(listener, band):
    """가짜 mbox 끝줄 수 — 일꾼 큐가 비면 그 subprocess 도 끝났다(깨움 1회 = 1줄)."""
    assert wait_for(lambda: listener.worker.queue.unfinished_tasks == 0, limit=20)
    return len(band.ends())


def case_01(tmp, pack=None):
    """① 같은 글 1개가 두 스레드로 동시에 → dispatched 1 · duplicate 1 · 깨움 1 (M1·M4)."""
    listener, band, clock = bench(tmp, pack)
    gate = Gate(listener.receive.latest)
    listener.receive.latest = gate
    same = msg(clock.ts())
    both(listener, same, dict(same), gate)
    wakes = wakes_of(listener, band)
    listener.worker.stop()
    band.close()
    assert len(Rows(tmp, "route.jsonl").where(t="route", state="dispatched")) == 1
    assert len(Rows(tmp, "receive.jsonl").where(state="duplicate")) == 1
    assert wakes == 1  # 기준판 = 2(같은 글로 두 번 깨어난다)


def case_02(tmp, pack=None):
    """② 새 root 글 하나가 두 길로 동시에 → bind 1 · binding 장부 1줄 (M2 · Red = 장부 2줄).

    경합 자리 = bind 의 check-then-act(bindings.entries → bind) — prior 읽기가 아니라 여기서 멈춘다.
    """
    listener, band, clock = bench(tmp, pack)
    gate = Gate(listener.bindings.entries)
    listener.bindings.entries = gate
    fresh = msg(clock.ts(), text="새 root")
    both(listener, fresh, dict(fresh), gate)
    listener.worker.stop()
    band.close()
    rows = Rows(tmp, "bindings.jsonl")
    assert [row["key"][2] for row in rows.where(state="bound")] == [fresh["ts"]]
    assert len(rows) == 1  # 잠금 밖이면 같은 키가 bound + rejected 2줄(기준판·M2)


def case_03(tmp, pack=None):
    """③ 다른 글 2개가 두 스레드로 동시에 → dispatched 2 · 깨움 2."""
    listener, band, clock = bench(tmp, pack)
    gate = Gate(listener.receive.latest)
    listener.receive.latest = gate
    one, two = msg(clock.ts()), msg("%.6f" % (clock.t + 5))
    both(listener, one, two, gate)
    wakes = wakes_of(listener, band)
    listener.worker.stop()
    band.close()
    assert len(Rows(tmp, "route.jsonl").where(t="route", state="dispatched")) == 2
    assert wakes == 2


def case_04(tmp, pack=None):
    """④ 일꾼이 잠금을 쥔 동안 수신 스레드에 새 글 1 → 잠금이 풀린 뒤 처리 · dispatched 1 · envelope ack 1 · 유실 0 (M3)."""
    listener, band, clock = bench(tmp, pack)
    gate = Gate(listener.receive.latest)
    listener.receive.latest = gate
    worker = threading.Thread(target=lambda: listener.route(msg(clock.ts(), text="보충 글")), daemon=True)
    worker.start()
    assert gate.entered.wait(20), "일꾼이 잠금을 못 쥠"
    live = msg("%.6f" % (clock.t + 5), text="실시간 글")
    listener.ws.watch = live["ts"]
    recv = threading.Thread(target=lambda: listener._frame_of(env("E2", live)), daemon=True)
    recv.start()
    assert wait_for(lambda: listener.envelope == "E2", limit=10)  # 수신 스레드가 envelope 을 쥐고 잠금 앞에 선다
    gate.release.set()
    worker.join(20), recv.join(20)
    listener.worker.stop()
    band.close()
    assert len(Rows(tmp, "route.jsonl").where(t="route", state="dispatched")) == 2  # 둘 다 처리(유실 0)
    assert len(Rows(tmp, "receive.jsonl").where(state="received")) == 2
    assert listener.ws.sent == [("E2", True)]  # _frame_of 끝 1회 · 그 글의 RECEIVED 줄 뒤 = 유실 0


def case_05(tmp, pack=None):
    """⑤ 잠금을 쥔 채 Web·깨움 subprocess 호출 0(가짜 Web·가짜 mbox 기록)."""
    listener, band, clock = bench(tmp, pack)
    inside, held = [], []
    lock, web = listener.route_lock, listener.web

    class Tracked:  # 잠금 소지자만 적는다 — 잠금 밖 호출은 안 걸린다
        holder, depth = None, 0

        def __enter__(self):
            lock.acquire()
            Tracked.holder, Tracked.depth = threading.get_ident(), Tracked.depth + 1
            held.append(1)
            return self

        def __exit__(self, *exc):
            Tracked.depth -= 1
            Tracked.holder = None if not Tracked.depth else Tracked.holder
            lock.release()
            return False

        def locked(self):
            return lock.locked()

    listener.route_lock = Tracked()

    def web_of(method, token, params=None, retry=True, **budget):
        if Tracked.holder == threading.get_ident():
            inside.append(method)
        return web(method, token, params, retry, **budget)

    listener.web = web_of
    gate = Gate(listener.receive.latest)
    listener.receive.latest = gate
    both(listener, msg(clock.ts(), text="새 root"), msg("%.6f" % (clock.t + 5), text="답"), gate)
    listener.worker.stop()
    band.close()
    assert held  # 잠금이 실제로 잡혔다
    assert inside == []  # 잠금 안 Web 호출 0


def case_06(tmp, pack=None):
    """⑥ «연결 끝» 줄에 잠금 최장 칸 1개(값 판정 0)."""
    clock, pack = Clock(), pack if pack is not None else pack_of()
    band = Band(tmp, clock)
    first = clock.ts()
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(first)), {"type": "disconnect"}]], session=1)
    thread.join(60)
    band.close()
    ends = [line for line in listen_lines(tmp) if "연결 끝" in line]
    assert len(ends) == 1
    assert "잠금 최장" in ends[0] and ends[0].rstrip().endswith("초")  # 관측 칸 1(값은 안 본다)


def case_07(tmp, pack=None):
    """⑦ r2341 판 사례 ①~㉑ 그대로 통과 — 회귀(잠금을 넣어도 그 판 판정이 안 흔들린다)."""
    assert pack is None  # 회귀는 제품을 그대로 읽는 판에서만(사본 변이 판은 안 본다)
    steps = base._run_cases(["case_%02d" % n for n in range(1, 22)], tmp / "r2341")  # r2341 시험 묶음 21사례
    assert len(steps) == 21 and all(seconds < 70 for seconds in steps.values()), steps


def case_08(tmp, pack=None):
    """⑧ 수신 스레드가 E2 를 쥐고 잠금을 기다리는 동안 일꾼이 ack → E2 의 RECEIVED 줄 앞 send 0 · 뒤 1 (M5)."""
    listener, band, clock = bench(tmp, pack)
    gate = Gate(listener.receive.latest)
    listener.receive.latest = gate
    worker = threading.Thread(target=lambda: listener.route(msg(clock.ts(), text="보충 글")), daemon=True)
    worker.start()
    assert gate.entered.wait(20), "일꾼이 잠금을 못 쥠"
    live = msg("%.6f" % (clock.t + 5), text="실시간 글")
    listener.ws.watch = live["ts"]
    recv = threading.Thread(target=lambda: listener._frame_of(env("E2", live)), daemon=True)
    recv.start()
    assert wait_for(lambda: listener.envelope == "E2", limit=10)
    gate.release.set()
    worker.join(20), recv.join(20)
    listener.worker.stop()
    band.close()
    assert listener.ws.sent == [("E2", True)]  # 기준판(잠금만) = RECEIVED 줄 앞 1회 = [("E2", False)]


CASES = {name: value for name, value in sorted(globals().items()) if name.startswith("case_")}
STEPS = {}
LOCK = "        with self.route_lock:  # r2347 L1 — bind 확인부터 영수까지 한 번에 하나"
RETURN = "                return self._receipt(key, self.router.route(event)) if event else self.router.route(None)"
# ── 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더 = 위 사례 시험이 그 대조)
MUTANTS = {
    "M1": ("socket.py", [(LOCK, "        if True:  # r2347 L1")], ["case_01"]),
    "M2": ("socket.py", [(LOCK, "        if True:  # r2347 L1"),
                         (RETURN, "                with self.route_lock:\n                    " + RETURN.strip())],
           ["case_02"]),
    "M3": ("socket.py", [(LOCK, "        if not self.route_lock.acquire(blocking=False):  # r2347 L1\n"
                                 "            return {\"t\": \"route\", \"kind\": None, \"to\": None, \"state\": \"idle\"}")],
           ["case_04"]),
    "M4": ("socket.py", [(LOCK, "        with (self.route_lock if threading.get_ident() == self.recv_thread"
                                " else threading.Lock()):  # r2347 L1")],
           ["case_01"]),
    "M5": ("socket.py", [("        if threading.get_ident() != self.recv_thread:  # r2347 L4", "        if False:  # r2347 L4")],
           ["case_08"]),
}


def run_cases(names, tmp_path, pack=None):
    for name in names:
        started = time.time()
        path = tmp_path / name
        os.makedirs(str(path), exist_ok=True)
        CASES[name](path, pack)
        STEPS[name] = round(time.time() - started, 2)
    return STEPS


def test_cases_01_08(tmp_path):
    """①~⑧ — 잠금·차례·ack 자리(기준판 Red = ① ② ⑧)."""
    print("R2347 단계별 초", run_cases(["case_%02d" % n for n in range(1, 9)], tmp_path))


def test_mutants(tmp_path):
    """M1~M5 — 사본에 변이를 넣으면 그 사례가 FAIL(원본 대조 = 위 사례 시험)."""
    shutil.copytree(FT2, str(tmp_path / "pack"), ignore=shutil.ignore_patterns("__pycache__"))  # 어댑터가 core 를 읽는다
    pack_dir = str(tmp_path / "pack" / "adapters" / "slack")
    origin = open(os.path.join(pack_dir, "socket.py"), encoding="utf-8").read()
    caught, took = {}, {}
    for name, (fname, swaps, cases) in MUTANTS.items():
        body = origin
        for old, new in swaps:
            assert old in body, "%s 자리 없음" % name
            body = body.replace(old, new, 1)
        with open(os.path.join(pack_dir, fname), "w", encoding="utf-8") as handle:
            handle.write(body)
        for case in cases:
            started = time.time()
            with pytest.raises(AssertionError):
                path = tmp_path / (name + "-" + case)
                os.makedirs(str(path), exist_ok=True)
                CASES[case](path, pack_of(pack_dir))
            took["%s-%s" % (name, case)] = round(time.time() - started, 2)
            caught.setdefault(name, []).append(case)
    assert sorted(caught) == sorted(MUTANTS)  # 변이 5개가 다 잡혔다
    print("R2347 변이 단계별 초", took)
