"""r2391 ft2 Slack 수신 스레드 = ack 와 큐 넣기 둘뿐 — 반례 ①~⑦ ⑪ + 변이 M1~M3 (기준판 Red = ① ③ ④).

대역 = r2341 판(ws·Web·쪽지) + 넣는 차례대로 흘리는 Feed(r2348). 실 Slack·실 쪽지·실 자격 0.
기다림은 Event·wait_for 뿐 — 다만 ⑤ 는 «일감이 머문 초» 를 관측 칸에서 읽으려고 0.4초 지연을 한 번 주입한다.
시험 1개 70초 안 · 단계별 초 = 실행 끝 요약(`R2391 단계별 초`).
"""
import os, re, shutil, sys, threading, time  # noqa: E401
import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_slack_listen_reconnect_r2341 import (  # noqa: E401 — r2341 대역 그대로
    CH, CH2, HELLO, HUMAN, MASTER, W, Band, Clock, FakeConnect, channels_rows, env, ledger,
    listen_lines, msg, pack_of, wait_for)
from test_slack_control_barrier_r2348 import C9, Feed, join, seed, tape_web  # noqa: E401

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKER = "ft2-slack-worker"


def soon(check, limit=8.0):  # 사건은 밀리초 안에 난다 — 대기 상한은 짧게(변이 판이 길어지지 않게)
    return wait_for(check, limit)


def routed(tmp, ts):  # 그 글의 route 장부 state 목록(차례 그대로)
    return [row.get("state") for row in ledger(tmp, "route.jsonl") if row.get("t") == "route" and row["key"][2] == ts]


class Watch:
    """route 대역 — 부른 스레드 이름과 ts 만 남기고 그대로 넘긴다(붙잡지 않는다)."""

    def __init__(self):
        self.seen = []
        self.entered = threading.Event()

    def wrap(self, listener):
        inner = listener.route

        def route(event):
            self.seen.append((threading.current_thread().name, (event or {}).get("ts")))
            self.entered.set()
            return inner(event)

        listener.route = route


class Gate(Watch):
    """route 를 붙잡는 대역 — release 가 설 때까지 머문다(처리 25초 흉내 · sleep 0)."""

    def __init__(self):
        super().__init__()
        self.release = threading.Event()

    def wrap(self, listener):
        inner = listener.route

        def route(event):
            self.seen.append((threading.current_thread().name, (event or {}).get("ts")))
            self.entered.set()
            self.release.wait(20)
            return inner(event)

        listener.route = route


def _listener(pack, band, clock, prepare=None, **kw):
    os.environ["FT2_SLACK_WAKE"] = band.mbox()  # 가짜 쪽지 — 실 mbox 0
    known = dict(channel=CH, app_token="xapp-FAKE", bot_token="xoxb-FAKE", master=MASTER,
                 users=(HUMAN,), bot_users=("UBOT",), web=band.web, sleep=lambda seconds: None,
                 mono=clock.mono, now=clock.now, clock=clock.iso, alert=None, notify=lambda row: None)
    known.update(kw)
    listener = pack["socket"].Listener(str(band.root), **known)
    if prepare is not None:
        prepare(listener)
    return listener


def feed_start(pack, band, clock, prepare=None, **kw):
    """Feed 연결로 수신 루프 시작 — 시험이 프레임을 넣고 ack 를 직접 본다(대본 없음)."""
    band.scripts = []
    feed = Feed()
    feed.put(HELLO)
    listener = _listener(pack, band, clock, prepare, connect=FakeConnect(feed), **kw)
    thread = threading.Thread(target=lambda: listener.run(sessions=1), daemon=True)
    thread.start()
    assert soon(lambda: listener.ws is feed)
    return listener, thread, feed


def stop(feed, thread, band):
    feed.put({"type": "disconnect"})
    thread.join(60)
    band.close()


# ── ①~④ K1 — 수신 스레드는 ack 와 큐 넣기 둘뿐
def case_01(tmp):
    """① 처리(붙잡힌 route) 중에도 다음 envelope 은 ack 된다 — 기준판은 수신이 막힌다."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band)
    gate = Gate()
    listener, thread, feed = feed_start(pack, band, clock, prepare=gate.wrap)
    first, second = "%.6f" % (clock.t + 1), "%.6f" % (clock.t + 2)
    feed.put(env("E1", msg(first)))
    assert soon(gate.entered.is_set)  # 첫 글 = 처리에 붙잡혀 있다
    feed.put(env("E2", msg(second)))
    assert soon(lambda: feed.acked(2), 3.0)  # 그동안 둘째 envelope 도 확인됐다
    assert feed.sent == ["E1", "E2"]  # 확인 = 받은 차례
    gate.release.set()
    assert soon(lambda: routed(tmp, second) == ["dispatched"])
    stop(feed, thread, band)
    assert sorted({row["key"][2] for row in ledger(tmp, "route.jsonl") if row.get("t") == "route"}) == [first, second]


def case_02(tmp):
    """② 사람 글 묶기·라우팅은 일꾼 스레드에서 — 수신 스레드가 부른 route 0 · 차례 = 받은 차례."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band)
    watch = Watch()
    listener, thread, feed = feed_start(pack, band, clock, prepare=watch.wrap)
    first, second = "%.6f" % (clock.t + 1), "%.6f" % (clock.t + 2)
    feed.put(env("E1", msg(first)))
    feed.put(env("E2", msg(second)))
    assert soon(lambda: len(watch.seen) == 2)
    assert [name for name, _ts in watch.seen] == [WORKER, WORKER]  # 둘 다 일꾼
    assert [ts for _name, ts in watch.seen] == [first, second]  # 차례 그대로
    stop(feed, thread, band)


def case_03(tmp):
    """③ 처리가 긴 동안 도착한 글 4개 = 다 ack · 연결 1회(끊겨서 잃는 것 0)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band)
    gate = Gate()
    listener, thread, feed = feed_start(pack, band, clock, prepare=gate.wrap)
    stamps = ["%.6f" % (clock.t + n) for n in range(1, 5)]
    feed.put(env("E1", msg(stamps[0])))
    assert soon(gate.entered.is_set)
    for index, ts in enumerate(stamps[1:], start=2):
        feed.put(env("E%d" % index, msg(ts)))
    assert soon(lambda: feed.acked(4), 3.0)  # 붙잡힌 채로 넷 다 확인
    gate.release.set()
    assert soon(lambda: [routed(tmp, ts) for ts in stamps] == [["dispatched"]] * 4)
    stop(feed, thread, band)
    assert band.calls.count("apps.connections.open") == 1  # 재연결 0


def case_04(tmp):
    """④ ack 는 처리 전 — 붙잡힌 동안 확인은 갔고 장부는 아직 0."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band)
    gate = Gate()
    listener, thread, feed = feed_start(pack, band, clock, prepare=gate.wrap)
    first = "%.6f" % (clock.t + 1)
    feed.put(env("E1", msg(first)))
    assert soon(gate.entered.is_set)
    assert soon(lambda: feed.acked(1), 3.0)  # 확인 먼저
    assert routed(tmp, first) == []  # 처리 전 = 장부 0
    gate.release.set()
    assert soon(lambda: routed(tmp, first) == ["dispatched"])
    stop(feed, thread, band)


# ── ⑤ K2 — 관측 칸 나눔
def case_05(tmp):
    """⑤ «연결 끝» 줄 = «수신 최장»·«최장 처리»(일꾼) 두 칸 · 긴 일은 일꾼 칸에만 선다."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band)
    gate = Gate()
    listener, thread, feed = feed_start(pack, band, clock, prepare=gate.wrap, mono=time.monotonic)  # 초를 실제로 잰다
    first = "%.6f" % (clock.t + 1)
    feed.put(env("E1", msg(first)))
    assert soon(gate.entered.is_set)
    time.sleep(0.4)  # 일감이 실제로 머문 초(관측 칸을 가르는 값)
    gate.release.set()
    assert soon(lambda: routed(tmp, first) == ["dispatched"])
    stop(feed, thread, band)
    line = [ln for ln in listen_lines(tmp) if "연결 끝" in ln][-1]
    for cell in ("수신 최장", "최장 처리", "큐 최대", "끊긴 시각", "보충 글"):
        assert cell in line, line
    recv_s = float(re.search(r"수신 최장 ([\d.]+)초", line).group(1))
    work_s = float(re.search(r"최장 처리 ([\d.]+)초", line).group(1))
    assert work_s >= 0.3, line  # 처리 = 일꾼 칸
    assert recv_s < 0.2, line  # 수신 스레드는 짧다


# ── ⑥⑦ K3 — 보충에서 남은 것은 같은 연결 안 일꾼 다음 차례
def _wander(clock, band, count=24):
    first = clock.ts()
    threads = ["%.6f" % (clock.t + 10 + n) for n in range(count)]
    band.history[CH] = [{"ts": "%.6f" % (float(ts) + 1), "thread_ts": ts, "user": HUMAN, "text": "답"} for ts in threads]
    for ts in threads:
        band.replies[ts] = [{"ts": ts, "user": HUMAN, "text": "root"},
                            {"ts": "%.6f" % (float(ts) + 1), "thread_ts": ts, "user": HUMAN, "text": "답"}]
    return first, threads


def _scripted(pack, band, clock, scripts, sessions=2, prepare=None):
    band.scripts = [list(script) for script in scripts]
    listener = _listener(pack, band, clock, prepare)
    thread = threading.Thread(target=lambda: listener.run(sessions=sessions), daemon=True)
    thread.start()
    return listener, thread


def _budget(listener, units):  # 보충 회차 예산만 좁힌다(대역 · 제품 상수 손 0)
    inner = listener.backfill.run

    def run(reason, targets, deadline=None, floor=""):
        return inner(reason, targets, deadline=listener.mono() + float(units), floor=floor)

    listener.backfill.run = run
    return listener


def case_06(tmp):
    """⑥ 보충 예산에 남은 것은 다음 재연결을 기다리지 않는다 — 재연결 1번에 보충 차례 여럿(남은 것 0)."""
    clock, pack = Clock(step=2.0), pack_of()
    band = Band(tmp, clock)
    first, threads = _wander(clock, band)
    inner, seen = band.web, []

    def web(method, token, params=None, retry=True, **budget):  # 첫 차례만 창을 준다 = 그 뒤로는 새 글 0
        if method == "conversations.history" and (params or {}).get("channel") == CH:
            seen.append(method)
            if len(seen) > 1:
                return {"ok": True, "has_more": False, "messages": []}
        return inner(method, token, params, retry=retry, **budget)

    band.web = web
    listener, thread = _scripted(pack, band, clock, [[HELLO, env("E1", msg(first))], [HELLO]],
                                 prepare=lambda item: _budget(item, 20))  # 차례마다 조금씩
    thread.join(60)
    band.close()
    runs = [row for row in ledger(tmp, "backfill.jsonl") if row.get("reason") == "reconnect"]
    assert len(runs) >= 2, runs  # 차례가 여럿 = 이어 돌았다
    assert all(row.get("left") for row in runs[:-1]), runs  # 앞 차례는 남은 것을 들고 끝났다
    assert not runs[-1].get("left"), runs  # 다음 차례에 다 끝냈다
    assert band.calls.count("apps.connections.open") == 2, band.calls  # 재연결은 1번뿐
    assert any("같은 연결 다음 차례" in ln for ln in listen_lines(tmp)), listen_lines(tmp)[-5:]
    cursors = {row["thread"] for row in ledger(tmp, "cursors.jsonl")}
    assert {item[2] for item in runs[0]["left"]} & set(threads) <= cursors  # 남은 것은 다음 차례에 다 읽혔다


def case_07(tmp):
    """⑦ 진전 0 이면 이어 돌지 않는다 — 예산 이미 지남 = 차례 1번 · «다음 재연결» 1줄(무한 0)."""
    clock, pack = Clock(step=2.0), pack_of()
    band = Band(tmp, clock)
    first = clock.ts()

    def prepare(listener):  # 열린 binding 1개 = 남는 대상 · 예산은 이미 지났다(전진 0 을 만든다)
        listener.bindings.bind((W, CH, "1700000000.500000"), MASTER)
        _budget(listener, -10)

    listener, thread = _scripted(pack, band, clock, [[HELLO, env("E1", msg(first))], [HELLO]], prepare=prepare)
    thread.join(60)
    band.close()
    runs = [row for row in ledger(tmp, "backfill.jsonl") if row.get("reason") == "reconnect"]
    assert len(runs) == 1, runs  # 진전 0 = 이어 돌지 않는다
    assert runs[0].get("left"), runs  # 남은 것은 보존
    lines = listen_lines(tmp)
    assert any("보충 미완" in ln and "다음 재연결" in ln for ln in lines), lines[-5:]
    assert not any("같은 연결 다음 차례" in ln for ln in lines)


def case_12(tmp):
    """⑫(보조 · 카드 ①~⑪ 밖) 일꾼 큐 넘침 = 수신 스레드가 그 자리에서 처리(유실 0 · «큐 넘침» 1줄)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band)

    def prepare(listener):  # 가득 찬 큐 대역 — 넣기 실패를 그 자리에서 본다
        listener.worker.alive = lambda: True
        listener.worker.submit = lambda *a, **k: False

    listener, thread, feed = feed_start(pack, band, clock, prepare=prepare)
    ts = "%.6f" % (clock.t + 1)
    feed.put(env("E1", msg(ts)))
    assert soon(lambda: routed(tmp, ts) == ["dispatched"])  # 버리지 않고 그 자리에서
    stop(feed, thread, band)
    assert any("큐 넘침" in ln for ln in listen_lines(tmp)), listen_lines(tmp)[-5:]


# ── ⑪ K5 — 다른 길 그대로
def case_11(tmp):
    """⑪ 다른 길 그대로 — 봇 가입(제어 = 일꾼) · 보관(auto 줄 지움) · 사람 글 판정 셋이 그 꼴 그대로."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.info[C9] = {"name": "c9"}
    band.discover = [CH2]
    calls = tape_web(band)
    stamp, ts = clock.ts(), "%.6f" % (clock.t + 1)
    listener, thread = _scripted(pack, band, clock, [
        [HELLO, env("E1", join(stamp)), env("E2", {"type": "channel_archive", "channel": CH2}), env("E3", msg(ts))]],
        sessions=1)
    thread.join(60)
    band.close()
    rows = channels_rows(tmp)
    assert [row[0] for row in rows if row[3] == "auto"] == [C9]  # 봇 가입 = auto 1
    assert not [row for row in rows if row[0] == CH2]  # 보관 = auto 줄 지움
    assert routed(tmp, ts) == ["dispatched"]  # 사람 글 판정 그대로
    assert listener.deferred == 0  # 셈 다 풀림
    infos = [call[0] for call in calls if call[1] == "conversations.info" and call[2] == C9]
    assert infos == [WORKER], infos  # 제어 사건 Web = 일꾼(r2348 그대로)


CASES = {name: value for name, value in sorted(globals().items()) if name.startswith("case_")}
STEPS = {}


def _run(names, tmp_path, pack=None):
    for name in names:
        started = time.time()
        path = os.path.join(str(tmp_path), name)
        os.makedirs(path, exist_ok=True)
        if pack is None:
            CASES[name](path)
        else:
            _with_pack(pack, CASES[name], path)
        STEPS[name] = round(time.time() - started, 2)


def test_cases_01_04(tmp_path):
    """①~④ — 수신 스레드는 ack 와 큐 넣기 · 처리는 일꾼."""
    _run(["case_%02d" % number for number in range(1, 5)], tmp_path)
    print("R2391 단계별 초 ①~④", STEPS)


def test_cases_05_07(tmp_path):
    """⑤~⑦ — 관측 칸 나눔 · 보충 남은 차례(이어 돌기·무한 0)."""
    _run(["case_05", "case_06", "case_07"], tmp_path)
    print("R2391 단계별 초 ⑤~⑦", STEPS)


def test_case_11(tmp_path):
    """⑪ — 다른 길(제어·보관·판정) 그대로 + ⑫ 넘침 보조."""
    _run(["case_11", "case_12"], tmp_path)
    print("R2391 단계별 초 ⑪·⑫", STEPS)


# ── 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더 = 위 시험이 그 대조)
MUTANTS = {
    "M1": ("socket.py", "        return self._defer(self.route, event) if self._barrier() else self._queue_route(event)",
           "        return self._defer(self.route, event) if self._barrier() else self.route(event)",
           ["case_02", "case_04"]),
    "M2": ("socket.py", "        if self.worker.alive() and self.worker.submit(self.route, event):  # 장벽 셈 0",
           "        if self.worker.alive() and self.worker.submit(self.route, event) and not self.worker.queue.join():"
           "  # 장벽 셈 0",
           ["case_01"]),
    "M3": ("socket.py", "                and self.worker.submit(self._backfill_job):", "                and False:",
           ["case_06"]),
}


def test_mutants(tmp_path):
    """M1~M3 — 사본에 변이를 넣으면 그 사례가 FAIL(원본 대조 = 위 세 시험)."""
    caught = {}
    shutil.copytree(FT2, os.path.join(str(tmp_path), "pack"),
                    ignore=shutil.ignore_patterns("__pycache__", "tests"))
    pack_dir = os.path.join(str(tmp_path), "pack", "adapters", "slack")
    origin = open(os.path.join(pack_dir, "socket.py"), encoding="utf-8").read()
    for name, (fname, old, new, cases) in MUTANTS.items():
        assert old in origin, "%s 자리 없음" % name
        with open(os.path.join(pack_dir, fname), "w", encoding="utf-8") as handle:
            handle.write(origin.replace(old, new, 1))
        pack = pack_of(pack_dir)
        for case in cases:
            try:
                with pytest.raises(AssertionError):
                    _with_pack(pack, CASES[case], os.path.join(str(tmp_path), name + "-" + case))
            except pytest.fail.Exception as exc:
                raise AssertionError("%s-%s 변이 미검거" % (name, case)) from exc
            caught.setdefault(name, []).append(case)
        with open(os.path.join(pack_dir, fname), "w", encoding="utf-8") as handle:  # 원본 복구
            handle.write(origin)
    assert sorted(caught) == sorted(MUTANTS)
    print("R2391 변이 검거", caught)


def _with_pack(pack, case, path):
    """사본 팩 모듈로 같은 사례 1회 — 시험이 제품을 다시 읽지 않게 pack 을 꽂는다."""
    os.makedirs(path, exist_ok=True)
    original = globals()["pack_of"]
    globals()["pack_of"] = lambda base=None: pack
    try:
        case(path)
    finally:
        globals()["pack_of"] = original
