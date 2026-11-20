"""r2341 ft2 Slack 재연결 멈춤 — 반례 ①~⑳ + 변이 M1~M12 (기준판 Red = ①).

대역 = ws 서버(연결마다 대본 1개) + Web API(history·replies·info·발견) + 가짜 mbox(쪽지 기록·hold 지연·rc).
실 Slack·실 쪽지·실 자격 0 · sleep 0(지연은 대역 시계와 hold 파일로만) · 시험 1개 70초 안.
단계별 초 = 실행 끝 요약(`R2341 단계별 초`).
"""
import importlib.util, json, os, shutil, sys, threading, time  # noqa: E401
import pytest
from websockets.sync.server import serve

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(FT2, "adapters", "slack")
TEAM, CH, CH2, CHUMAN = "planner", "C0MAIN0001", "C0AUTO0002", "C0HUMAN003"
HUMAN, BOT, MASTER, DESK = "UOPPA", "UBOT", "byz-planner-master-pi#1", "byz-planner-desk-pi#2"
HELLO, W = {"type": "hello", "num_connections": 1}, "TFAKE"
MBOX_PY = '''
import json, os, sys, time
root, args = sys.argv[1], sys.argv[2:]
path, hold, rcfile = os.path.join(root, "wakes.jsonl"), os.path.join(root, "hold"), os.path.join(root, "rc")
def line(**row):
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, ensure_ascii=False) + "\\n")
line(t="start", to=args[1], at=time.time())
limit = time.time() + 30
while os.path.exists(hold) and time.time() < limit:
    time.sleep(0.02)
rc = int(open(rcfile, encoding="utf-8").read().strip() or 0) if os.path.exists(rcfile) else 0
line(t="end", to=args[1], at=time.time(), rc=rc)
sys.exit(rc)
'''


class Clock:
    """대역 시계 — Slack ts·단조 예산 초(mono)·ISO 장부 시각을 한 곳에서 돌린다."""

    def __init__(self, start=1700000000.0, step=1.0):
        self.t, self.step, self.mono_t = float(start), float(step), 1000.0

    def now(self):
        return self.t

    def iso(self):
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(self.t))

    def mono(self):  # 호출마다 step 초 — 50초 예산 판정을 시험 안에서 돌린다
        self.mono_t += self.step
        return self.mono_t

    def go(self, seconds):
        self.t += float(seconds)

    def ts(self):
        return "%.6f" % self.t


def msg(ts, channel=CH, user=HUMAN, text="사람 글", thread=None, **extra):
    row = dict({"type": "message", "team": W, "channel": channel, "ts": ts, "user": user, "text": text}, **extra)
    if thread:
        row["thread_ts"] = thread
    return row


def env(eid, event, kind="events_api"):
    return {"type": kind, "envelope_id": eid, "payload": {"team_id": W, "event": event}}


class Band:
    """ws 대역(연결마다 대본 1개) + Web API 대역 + 가짜 mbox(쪽지 기록·hold 지연·rc)."""

    def __init__(self, root, clock, scripts=()):
        self.root, self.clock = str(root), clock
        os.makedirs(self.root, exist_ok=True)
        self.scripts = [list(script) for script in scripts]
        self.calls, self.oldest, self.acks, self.reply_calls = [], [], [], []
        self.history, self.replies, self.info, self.discover = {}, {}, {}, []
        self.hold_history = None  # threading.Event 이면 history 호출이 여기서 기다린다(⑦)
        self.server = serve(self._handler, "127.0.0.1", 0)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = "ws://127.0.0.1:%d" % self.server.socket.getsockname()[1]

    def _handler(self, ws):
        for frame in (self.scripts.pop(0) if self.scripts else []):
            ws.send(json.dumps(frame))
            if frame.get("envelope_id"):
                self.acks.append((json.loads(ws.recv(timeout=20))["envelope_id"], time.time()))

    def web(self, method, token, params=None, retry=True, **budget):  # 7초 상한 대역(즉시 응답)
        params = params or {}
        self.calls.append(method)
        if method == "apps.connections.open":
            return {"ok": True, "url": self.url}
        if method == "users.conversations":
            return {"ok": True, "channels": [{"id": c, "name": c} for c in self.discover]}
        if method == "conversations.info":
            extra = self.info.get(params.get("channel"), {})
            return {"ok": True, "channel": dict({"is_channel": True, "is_group": False, "is_member": True}, **extra)}
        if method == "conversations.history":
            if self.hold_history is not None:  # ⑦ — 재전달 글이 먼저 처리되게 보충을 붙잡는다
                self.hold_history.wait(20)
            oldest = float(params.get("oldest") or 0)
            self.oldest.append((params.get("channel"), oldest))
            return {"ok": True, "has_more": False, "messages":
                    [m for m in self.history.get(params.get("channel"), []) if float(m["ts"]) > oldest]}
        if method == "conversations.replies":
            after = float(params.get("oldest") or 0)
            self.reply_calls.append((params.get("channel"), params.get("ts"), after))
            return {"ok": True, "has_more": False, "messages":
                    [m for m in self.replies.get(params.get("ts"), []) if float(m["ts"]) > after]}
        return {"ok": True, "has_more": False, "messages": []}

    def mbox(self):
        """가짜 mbox 스크립트 1개 — FT2_SLACK_WAKE 로 배선(실 쪽지 0)."""
        path = os.path.join(self.root, "fake_mbox.py")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(MBOX_PY)
        return "%s %s %s" % (sys.executable, path, self.root)

    def holds(self, hold=True):
        path = os.path.join(self.root, "hold")
        if hold:
            open(path, "w").close()
        elif os.path.exists(path):
            os.remove(path)

    def rc(self, value):
        with open(os.path.join(self.root, "rc"), "w", encoding="utf-8") as handle:
            handle.write(str(value))

    def wakes(self):
        path = os.path.join(self.root, "wakes.jsonl")
        if not os.path.exists(path):
            return []
        with open(path, encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]

    def ends(self):
        return [row for row in self.wakes() if row["t"] == "end"]

    def close(self):
        self.server.shutdown()


def slack_path(root, name):
    return os.path.join(str(root), ".fable-team", "teams", TEAM, "slack", name)


def ledger(root, name):
    path = slack_path(root, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def listen_lines(root):
    path = slack_path(root, "listen.log")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return [line.rstrip() for line in handle]


def channels_rows(root):
    path = slack_path(root, "CHANNELS")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return [line.rstrip("\n").split("\t") for line in handle if not line.startswith("#")]


def snoop(root):
    """장부·listen.log 파일 크기 — 유휴 1시간 쓰기 0 판정(⑮)."""
    base = os.path.dirname(slack_path(root, "x"))
    if not os.path.isdir(base):
        return {}
    return {name: os.path.getsize(os.path.join(base, name)) for name in sorted(os.listdir(base))}


def load(base, name):
    spec = importlib.util.spec_from_file_location("r2341_%s_%s" % (name, abs(hash(base)) % 99991),
                                                  os.path.join(base, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Pack(dict):
    """제품 모듈 팩 — 쓰는 것만 그때 읽는다(기준판에 없는 새 파일이 다른 사례를 막지 않는다)."""

    def __init__(self, base):
        super().__init__()
        self.base = base

    def __missing__(self, name):
        self[name] = value = load(self.base, name)
        return value


def pack_of(base=None):
    return Pack(base or SRC)


def make_listener(pack, band, clock, notes=None, channel=CH, **kw):
    os.environ["FT2_SLACK_WAKE"] = band.mbox()  # 가짜 쪽지 — 실 mbox 0
    known = dict(channel=channel, app_token="xapp-FAKE", bot_token="xoxb-FAKE", master=MASTER, desk=DESK,
                 users=(HUMAN,), bot_users=(BOT,), web=band.web, sleep=lambda seconds: None, mono=clock.mono,
                 now=clock.now, clock=clock.iso, alert=None,
                 notify=notes.append if notes is not None else (lambda row: None))
    known.update(kw)
    return pack["socket"].Listener(str(band.root), **known)


def run_listener(pack, band, clock, scripts, session=1, **kw):
    """ws 대역 + 실 수신 루프 — 별 스레드에서 돌리고 (listener, thread) 를 돌려준다."""
    band.scripts = [list(script) for script in scripts]
    listener = make_listener(pack, band, clock, **kw)
    thread = threading.Thread(target=lambda: listener.run(sessions=session), daemon=True)
    thread.start()
    return listener, thread


def wait_for(check, limit=20.0, step=0.02):
    end = time.time() + float(limit)
    while time.time() < end:
        if check():
            return True
        time.sleep(step)
    return False


class IdleWs:
    """recv(timeout) — 대본이 바닥나면 TimeoutError(유휴 1초)를 idle 번 돌려준다(⑮ · ㉑).

    `done` 을 세우면 연결이 끝난다(㉑ = 시험이 잡고 있는 동안 계속 유휴). pause = 유휴 1초의 실제 길이 대역.
    """

    def __init__(self, frames, idle=0, on_start=None, on_end=None, pause=0.0):
        self.frames, self.idle, self.sent = list(frames), int(idle), []
        self.on_start, self.on_end, self.pause, self.done = on_start, on_end, float(pause), False

    def recv(self, timeout=None):
        if self.frames:
            return json.dumps(self.frames.pop(0))
        if self.on_start is not None:
            self.on_start(), setattr(self, "on_start", None)
        if self.done or self.idle <= 0:
            if self.on_end is not None:
                self.on_end(), setattr(self, "on_end", None)
            raise RuntimeError("closed")
        self.idle -= 1
        if self.pause:
            time.sleep(self.pause)
        raise TimeoutError("유휴")

    def send(self, data):
        self.sent.append(data)


class FakeConnect:
    def __init__(self, ws):
        self.ws = ws

    def __call__(self, url):
        return self

    def __enter__(self):
        return self.ws

    def __exit__(self, *exc):
        return False


# ── ①~③ 보충 회차 단위(Backfill 직접 · route·fetch 대역)
class FakeRoute:
    """route 대역 — 판정표대로 돌려주고 부른 ts 를 남긴다."""

    def __init__(self, verdicts=()):
        self.verdicts, self.calls = list(verdicts), []

    def route(self, event):
        if not event:
            return {"t": "route", "kind": None, "to": None, "state": "idle"}
        self.calls.append(event.get("ts"))
        state, reason = self.verdicts.pop(0) if self.verdicts else ("dispatched", None)
        return {"t": "route", "kind": "새 업무", "to": DESK, "state": state, "reason": reason,
                "command": "slack:%s:%s:%s" % (W, CH, event.get("ts")), "receipt": state == "dispatched"}


class FakeFetch:
    def __init__(self, rows=(), fail=None):
        self.rows, self.fail, self.calls = list(rows), dict(fail or {}), []

    def __call__(self, channel, thread, after, limit):
        self.calls.append({"thread": thread, "after": after})
        if thread in self.fail:
            raise RuntimeError(self.fail[thread])
        pool = [r for r in self.rows if (not after or float(r["ts"]) > float(after))]
        return {"rows": pool[:limit], "next": None}


def backfill_of(pack, root, route, fetch, **kw):
    return pack["backfill"].Backfill(str(root), route=route, fetch=fetch, team=TEAM, **kw)


def case_01(tmp):
    """① open thread 에 bot 글 3 + 사람 글 1 → 1회 뒤 커서 = 마지막 글 ts · 2회째 판정 0 (M1)."""
    pack = pack_of()
    rows = [{"ts": "100.000001", "user": BOT}, {"ts": "100.000002", "user": BOT},
            {"ts": "100.000003", "user": HUMAN}, {"ts": "100.000004", "user": BOT}]
    route, fetch = FakeRoute([("ignored", "bot"), ("ignored", "bot"), ("dispatched", None), ("ignored", "bot")]), FakeFetch(rows)
    worker = backfill_of(pack, tmp, route, fetch)
    first = worker.run(pack["backfill"].RECONNECT, [("", CH, "100.000000")])
    assert (first["state"], first["pages"], first["dispatched"]) == ("done", 1, 1)
    assert worker.cursors.get("", "100.000000") == "100.000004"  # 마지막 봇 글까지 커서가 넘어간다
    second = worker.run(pack["backfill"].RECONNECT, [("", CH, "100.000000")])
    assert route.calls == ["100.000001", "100.000002", "100.000003", "100.000004"]  # 2회째 = 같은 판정 0
    assert (second["routed"], second["dispatched"]) == (0, 0)


def case_02(tmp):
    """② dispatched 를 바란 사람 글이 영수 0 → 커서 그 자리 · stale 1(지금 동작 유지)."""
    pack = pack_of()
    route, fetch = FakeRoute([("full", "용량 밖")]), FakeFetch([{"ts": "200.000001", "user": HUMAN}])
    worker = backfill_of(pack, tmp, route, fetch)
    row = worker.run(pack["backfill"].RECONNECT, [("seat-a", CH, "200.000000")])
    assert (row["state"], row["dispatched"]) == ("미완", 0)
    assert worker.cursors.get("seat-a", "200.000000") == "" and row["stale"]


def case_03(tmp):
    """③ thread_not_found 1 → «닫힌 thread» 1줄 · 다음 회차 대상 0 · gap 되풀이 0 (M8)."""
    pack = pack_of()
    route, fetch = FakeRoute(), FakeFetch(fail={"300.000000": "thread_not_found"})
    worker = backfill_of(pack, tmp, route, fetch)
    first = worker.run(pack["backfill"].RECONNECT, [("", CH, "300.000000")])
    with open(worker.path, encoding="utf-8") as handle:
        lines = [line for line in handle if "닫힌 thread" in line]
    assert len(lines) == 1 and first["gap"] is None
    second = worker.run(pack["backfill"].RECONNECT, [("", CH, "300.000000")])
    assert len(fetch.calls) == 1 and second["pages"] == 0  # 다음 회차 = 대상 0
    with open(worker.path, encoding="utf-8") as handle:
        assert not [line for line in handle if "thread_not_found" in line]


def case_04(tmp):
    """④ 끊긴 창에 open 아닌 thread 답글 1 → 재연결 뒤 route 1 · dispatched 1 · 깨움 1 (M2·M3)."""
    clock, band, pack = Clock(), None, pack_of()
    band = Band(tmp, clock)
    first = clock.ts()
    reply = "%.6f" % (clock.t + 20)
    band.history[CH] = [{"ts": reply, "thread_ts": "111.000000", "user": HUMAN, "text": "끊긴 창 답"}]
    band.replies["111.000000"] = [{"ts": "111.000000", "user": HUMAN, "text": "root"},
                                  {"ts": reply, "thread_ts": "111.000000", "user": HUMAN, "text": "끊긴 창 답"}]
    clock.go(140)  # 처리 10:00:00 → 재연결 10:02:20(M3 = 지금 − 60초면 답글이 창 밖)
    notes = []
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(first))],
                                                        [HELLO, {"type": "disconnect"}]], session=2, notes=notes)
    thread.join(60)
    band.close()
    routed = [row for row in ledger(tmp, "route.jsonl") if row.get("t") == "route" and row.get("state") == "dispatched"]
    assert [row["key"][2] for row in routed] == [first, "111.000000"]  # root 1 + 보충 답글 1
    assert [row["kind"] for row in notes if row.get("state") == "dispatched"] == ["재개 필요"]  # desk 몫 = 쪽지 1


def case_05(tmp):
    """⑤ 끊긴 창에 새 root 글 1 → route 1 (M3)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    first = clock.ts()
    fresh = "%.6f" % (clock.t + 20)
    band.history[CH] = [{"ts": fresh, "user": HUMAN, "text": "끊긴 창 새 글"}]
    clock.go(140)
    notes = []
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(first))],
                                                        [HELLO, {"type": "disconnect"}]], session=2, notes=notes)
    thread.join(60)
    band.close()
    routed = [row for row in ledger(tmp, "route.jsonl") if row.get("t") == "route" and row.get("state") == "dispatched"]
    assert [row["key"][2] for row in routed] == [first, fresh]
    assert len(band.ends()) == 2  # root 1 + 끊긴 창 새 root 1 = 좌석 깨움 2


def case_06(tmp):
    """⑥ 끊긴 창 밖(09:58) 활동 thread → 보충 0(그 thread 쪽 0)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    first = clock.ts()
    band.history[CH] = [{"ts": "%.6f" % (clock.t - 120), "thread_ts": "222.000000", "user": HUMAN},
                        {"ts": "%.6f" % (clock.t - 119), "user": HUMAN, "text": "옛 root"}]
    clock.go(140)
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(first))],
                                                        [HELLO, {"type": "disconnect"}]], session=2)
    thread.join(60)
    band.close()
    assert [call for call in band.reply_calls if call[1] == "222.000000"] == []
    assert [row for row in ledger(tmp, "route.jsonl") if row.get("key", [None] * 3)[2] == "222.000000"] == []


def case_07(tmp):
    """⑦ 끊긴 창 글이 Slack 재전달로 이미 받음 → duplicate · 깨움 0."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    root_ts = clock.ts()
    reply = "%.6f" % (clock.t + 20)
    band.history[CH] = [{"ts": reply, "thread_ts": root_ts, "user": HUMAN, "text": "끊긴 창 답"}]
    band.replies[root_ts] = [{"ts": root_ts, "user": HUMAN, "text": "root"},
                             {"ts": reply, "thread_ts": root_ts, "user": HUMAN, "text": "끊긴 창 답"}]
    band.hold_history = threading.Event()  # 보충을 붙잡고 재전달 글을 먼저 처리한다
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(root_ts))],
                                                        [HELLO, env("E2", msg(reply, thread=root_ts))]], session=2)
    assert wait_for(lambda: any(eid == "E2" for eid, _at in band.acks))
    band.hold_history.set()
    thread.join(60)
    band.close()
    states = [row["state"] for row in ledger(tmp, "receive.jsonl")]
    assert states.count("dispatched") == 2 and "duplicate" in states  # root 1 + 재전달 답 1 + 보충 = duplicate
    assert len(band.ends()) == 2  # root 1 + 재전달 1 · 보충은 깨움 0


def case_08(tmp):
    """⑧ 끊김 흉내 → 재연결 → thread 글 1개 깨움 1 · 깨움 시각 − 글 시각 = 지연 초."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    root_ts = clock.ts()
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(root_ts))], [HELLO]], session=2)
    wait_for(lambda: len(listener.bindings.entries()) == 1)
    clock.go(1)
    late = clock.ts()  # 끊긴 창에 온 글
    clock.go(3)  # 그 글을 3초 늦게 받았다(깨움 시각 − 글 시각 = 3)
    band.history[CH] = [{"ts": late, "thread_ts": root_ts, "user": HUMAN, "text": "끊긴 창 답"}]
    band.replies[root_ts] = [{"ts": root_ts, "user": HUMAN, "text": "root"},
                             {"ts": late, "thread_ts": root_ts, "user": HUMAN, "text": "끊긴 창 답"}]
    thread.join(60)
    band.close()
    latency = round(clock.now() - float(late), 3)
    assert len(band.ends()) == 2  # root 1 + 끊긴 창 답 1
    assert latency == 3.0, "지연 초 %s" % latency  # 깨움 시각 − 글 시각


def case_09(tmp):
    """⑨ 깨움 가짜가 붙잡힌 동안 글 20개 → ack 21 · 수신 간격 ≤ 1초 · 깨움은 차례로 (M4)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.holds(True)
    first = clock.ts()
    script = [HELLO, env("E0", msg(first))]
    script += [env("E%d" % n, msg("%.6f" % (clock.t + n), text="글 %d" % n)) for n in range(1, 21)]
    listener, thread = run_listener(pack, band, clock, [script], session=1)
    assert wait_for(lambda: len(band.acks) == 21, limit=10)  # 깨움 1건이 붙잡혀 있어도 21개 확인이 온다
    gaps = [b[1] - a[1] for a, b in zip(band.acks, band.acks[1:])]
    assert max(gaps) <= 1.0, "최대 수신 간격 %.2f초" % max(gaps)
    assert len(band.ends()) <= 1  # 첫 깨움은 아직 붙잡혀 있다(수신 스레드에서 돌면 여기서 멈춘다)
    band.holds(False)
    thread.join(60)
    band.close()
    assert len(band.ends()) == 21  # 차례대로 다 갔다


def case_10(tmp):
    """⑩ 보충 대상 120 thread · 예산 50초 → «보충 미완» 1줄 · 다음 재연결이 남은 것부터."""
    clock, pack = Clock(step=2.0), pack_of()
    band = Band(tmp, clock)
    first = clock.ts()
    threads = ["%.6f" % (clock.t + 10 + n) for n in range(120)]
    band.history[CH] = [{"ts": "%.6f" % (float(ts) + 1), "thread_ts": ts, "user": HUMAN, "text": "답"} for ts in threads]
    for ts in threads:
        band.replies[ts] = [{"ts": ts, "user": HUMAN, "text": "root"},
                            {"ts": "%.6f" % (float(ts) + 1), "thread_ts": ts, "user": HUMAN, "text": "답"}]
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(first))], [HELLO],
                                                        [HELLO]], session=3)
    thread.join(60)
    band.close()
    assert any("보충 미완" in line for line in listen_lines(tmp))
    runs = [row for row in ledger(tmp, "backfill.jsonl") if row.get("state") == "미완"]
    assert runs and runs[0]["left"]  # 예산 끝 = 남은 대상 보존
    left = runs[0]["left"]
    assert 0 < len(left) < 120
    cursors = {row["thread"] for row in ledger(tmp, "cursors.jsonl")}
    assert left[0][2] in cursors  # 다음 재연결이 남은 것부터 읽었다
    assert len([row for row in listener.bindings.entries() if row.get("state") == "bound"]) == 1  # 수신 계속


def case_11(tmp):
    """⑪ member_joined_channel(봇) → auto 줄 1 · 그 채널 history 1쪽 보충 1회 · 사람 가입 = 0."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.history[CH2] = [{"ts": clock.ts(), "user": HUMAN, "text": "가입 전 글"}]
    listener, thread = run_listener(pack, band, clock, [[HELLO,
                                                         env("E1", {"type": "member_joined_channel", "channel": CH2, "user": BOT}),
                                                         env("E2", {"type": "member_joined_channel", "channel": CHUMAN, "user": HUMAN})]],
                                    session=1)
    assert wait_for(lambda: any(row[0] == CH2 and row[3] == "auto" for row in channels_rows(tmp)), limit=20)
    thread.join(60)
    band.close()
    rows = channels_rows(tmp)
    assert [row for row in rows if row[0] == CH2 and row[2] == "on"] and not [row for row in rows if row[0] == CHUMAN]
    assert [call for call in band.oldest if call[0] == CH2] and not [call for call in band.oldest if call[0] == CHUMAN]
    assert [row for row in ledger(tmp, "route.jsonl") if row.get("key", [None] * 3)[2] == clock.ts()]


def case_12(tmp):
    """⑫ channel_archive(auto on 채널) → 줄 지움 1 · 고정(main) 채널 = 손 0 (M6)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.discover = [CH2]
    listener, thread = run_listener(pack, band, clock, [[HELLO,
                                                         env("E1", {"type": "channel_archive", "channel": CH2}),
                                                         env("E2", {"type": "channel_archive", "channel": CH})]], session=1)
    assert wait_for(lambda: not [row for row in channels_rows(tmp) if row[0] == CH2], limit=20)
    thread.join(60)
    band.close()
    rows = channels_rows(tmp)
    assert not [row for row in rows if row[0] == CH2]  # auto 줄 지움 1
    assert [row for row in rows if row[0] == CH and row[2] == "on"]  # 고정 채널 = 손 0
    assert any("자동 채널 −%s" % CH2 in line for line in listen_lines(tmp))


def case_13(tmp):
    """⑬ 일꾼 죽음 → 다음 on_idle 에 다시 띄움 · 큐 글 유실 0 (M5)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    listener = make_listener(pack, band, clock)
    done = []
    listener.worker.start()
    listener.worker.stop()  # 일꾼 죽음
    listener.worker.submit(done.append, "재개")
    assert listener.worker.queue.qsize() == 1 and done == []
    listener.on_idle()  # 다음 유휴 = 다시 띄움
    assert wait_for(lambda: done == ["재개"], limit=5)  # 큐 글 유실 0
    listener.worker.stop()
    band.close()


def case_14(tmp):
    """⑭ 일꾼 큐 가득(1000) → «일꾼 넘침» 1줄 · 알림 1통 · 넣는 쪽 막힘 0."""
    pack, clock = pack_of(), Clock()
    lines, notes, ran = [], [], []
    worker = pack["slack_worker"].Worker(log=lines.append, notify=notes.append, now=clock.now)
    for n in range(1000):
        worker.submit(ran.append, n)  # 큐 가득(일꾼 안 띄움)
    started = time.time()
    for n in range(5):
        assert worker.submit(ran.append, "버림 %d" % n) is False
    assert time.time() - started < 1.0  # 넣는 쪽(수신 스레드) 막힘 0
    assert len([line for line in lines if "일꾼 넘침" in line]) == 1
    worker.start()
    assert wait_for(lambda: notes, limit=10)  # 알림 1통(1시간 1회)
    worker.stop()
    assert len(notes) == 1 and notes[0]["state"] == "overflow"
    assert len([n for n in ran if isinstance(n, str)]) == 0  # 버린 일은 안 들어간다


def case_15(tmp):
    """⑮ 유휴 1시간 → Web 호출 0 · 장부 쓰기 0(폴링 0 · M7)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    seen = {}
    ws = IdleWs([HELLO], idle=3600, on_start=lambda: seen.setdefault("start", snoop(tmp)),
                on_end=lambda: seen.setdefault("end", snoop(tmp)))
    calls_at = {}

    def web(method, token, params=None, retry=True, **budget):
        if "start" in seen and "end" not in seen:
            calls_at.setdefault("idle", []).append(method)
        return band.web(method, token, params, retry, **budget)

    listener = make_listener(pack, band, clock, web=web, connect=FakeConnect(ws))
    assert listener.run(sessions=1) == 0
    band.close()
    assert calls_at.get("idle") in (None, [])  # 유휴 중 Web 호출 0
    assert seen["start"] == seen["end"]  # 장부 쓰기 0


def case_16(tmp):
    """⑯ «연결 끝» 줄 = 최장 처리 초 · 큐 최대 · 끊긴 시각 · 보충 글 수 4칸."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    first = clock.ts()
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(first)), {"type": "disconnect"}]], session=1)
    thread.join(60)
    band.close()
    ends = [line for line in listen_lines(tmp) if "연결 끝" in line]
    assert len(ends) == 1
    for cell in ("최장 처리", "큐 최대", "끊긴 시각", "보충 글"):
        assert cell in ends[0], ends[0]
    assert first in ends[0]  # 끊긴 시각 = 마지막 처리 글 ts


def case_17(tmp):
    """⑰ 일꾼 깨움 rc≠0 → 다시 보낼 후보 1(지금 G1 동작 그대로 · M9)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.rc(1)
    first = clock.ts()
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(first)), {"type": "disconnect"}]], session=1)
    assert wait_for(lambda: [row for row in ledger(tmp, "wire.jsonl") if row.get("t") == "wake"], limit=10)
    thread.join(60)
    wakes = [row for row in ledger(tmp, "wire.jsonl") if row.get("t") == "wake"]
    assert wakes and wakes[0]["rc"] != 0 and wakes[0].get("landed")
    clock.go(61)  # G2 간격
    band.rc(0)
    listener.on_idle()  # 후보 1 = 유휴 회차가 다시 보낸다(일꾼이)
    assert wait_for(lambda: len([row for row in ledger(tmp, "wire.jsonl") if row.get("t") == "wake"]) >= 2, limit=10)
    band.close()
    assert len(band.ends()) >= 2


def case_18(tmp):
    """⑱ 같은 thread 글 2 연달아 → 깨움 차례 1 → 2 · 둘째는 첫째 끝난 뒤."""
    pack = pack_of()
    events = []
    worker = pack["slack_worker"].Worker()

    def job(name):
        events.append(("start", name))
        events.append(("end", name))

    worker.start()
    worker.submit(job, 1)
    worker.submit(job, 2)
    assert wait_for(lambda: len(events) == 4, limit=20)
    worker.stop()
    assert events == [("start", 1), ("end", 1), ("start", 2), ("end", 2)]


def case_19(tmp):
    """⑲ hello 직후 새 auto 채널 글 → 허용 판정 · route 1 · _discover 전이면 커서 그대로 (M10·M12)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.discover = [CH2]
    ts = clock.ts()
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(ts, channel=CH2)), {"type": "disconnect"}]],
                                    session=1)
    thread.join(60)
    band.close()
    routed = [row for row in ledger(tmp, "route.jsonl") if row.get("t") == "route" and row.get("state") == "dispatched"]
    assert [row["key"][2] for row in routed] == [ts]  # 허용으로 판정 · 유실 0
    # (b) _discover 전에 온 글 = «허용 밖 채널» → 커서 그대로(채널이 붙으면 다시 읽힌다 · M12)
    route, fetch = FakeRoute([("ignored", "허용 밖 채널")]), FakeFetch([{"ts": "400.000001", "user": HUMAN}])
    worker = backfill_of(pack, os.path.join(str(tmp), "late"), route, fetch)
    worker.run(pack["backfill"].RECONNECT, [("", CH2, "400.000000")])
    assert worker.cursors.get("", "400.000000") == ""


def case_20(tmp):
    """⑳ 처리 밀림 300초 중 끊김 · 밀린 글 ts 가 «받은 시각 − 60초» 보다 앞 → 재연결 보충 route 1 (M11)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    delayed = clock.ts()  # 글 ts = 10:00:00 · 받은 시각 = 10:05:00
    reply = "%.6f" % (clock.t + 120)  # 끊긴 창 10:02:00(받은 시각 − 60초 = 10:04:00 보다 앞)
    band.history[CH] = [{"ts": reply, "thread_ts": "555.000000", "user": HUMAN, "text": "밀린 글"}]
    band.replies["555.000000"] = [{"ts": "555.000000", "user": HUMAN, "text": "root"},
                                  {"ts": reply, "thread_ts": "555.000000", "user": HUMAN, "text": "밀린 글"}]
    clock.go(300)
    listener, thread = run_listener(pack, band, clock, [[HELLO, env("E1", msg(delayed)), {"type": "disconnect"}],
                                                        [HELLO]], session=2)
    thread.join(60)
    band.close()
    routed = [row for row in ledger(tmp, "route.jsonl") if row.get("t") == "route" and row.get("state") == "dispatched"]
    assert [row["key"][2] for row in routed] == [delayed, "555.000000"]


def case_21(tmp):
    """㉑ 유휴 재전송 깨움이 붙잡힌 동안 글 3개 → 수신 계속 · ack 3(마스터 덧줄 · M13)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.rc(1)  # 첫 깨움 = rc≠0 → 후보 표 1
    first = clock.ts()
    ws = IdleWs([HELLO, env("E1", msg(first))], idle=100000, pause=0.01)
    listener = make_listener(pack, band, clock, web=band.web, connect=FakeConnect(ws))
    thread = threading.Thread(target=lambda: listener.run(sessions=1), daemon=True)
    thread.start()
    assert wait_for(lambda: [row for row in ledger(tmp, "wire.jsonl") if row.get("t") == "wake"], limit=10)
    band.rc(0), band.holds(True)  # 재전송 깨움은 이제부터 붙잡힌다
    clock.go(61)  # G2 간격
    assert wait_for(lambda: len(band.wakes()) >= 3, limit=15)  # 재전송 시작(일꾼이 부른다)
    ws.frames += [env("E%d" % n, msg("%.6f" % (clock.t + n), text="글 %d" % n)) for n in range(1, 4)]
    assert wait_for(lambda: len(ws.sent) == 4, limit=10)  # 첫 글 1 + 붙잡힌 동안 수신·확인 3
    held = [row for row in band.wakes() if row["t"] == "end"]
    assert len(held) == 1  # 첫 깨움만 끝났다 = 재전송은 아직 붙잡혀 있다
    band.holds(False)
    ws.done = True  # 유휴 끝 → 연결 종료
    thread.join(60)
    band.close()
    assert len([row for row in band.wakes() if row["t"] == "end"]) >= 2  # 재전송도 갔다


CASES = {name: value for name, value in sorted(globals().items()) if name.startswith("case_")}
STEPS = {}


def _run_cases(names, tmp_path):
    for name in names:
        started = time.time()
        CASES[name](tmp_path / name)
        STEPS[name] = round(time.time() - started, 2)
    return STEPS


def test_cases_01_10(tmp_path):
    """①~⑩ — 커서·끊긴 창·일꾼(기준판 Red = ①)."""
    _run_cases(["case_%02d" % n for n in range(1, 11)], tmp_path)
    print("R2341 단계별 초 ①~⑩", STEPS)


def test_cases_11_21(tmp_path):
    """⑪~⑳ + ㉑ — 가입·보관·수명·넘침·관측·재전송·차례."""
    _run_cases(["case_%02d" % n for n in range(11, 22)], tmp_path)
    print("R2341 단계별 초 ⑪~㉑", STEPS)


# ── 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더 = 위 두 시험)
MUTANTS = {
    "M1": ("backfill.py", 'CURSOR_END = ("bot", "미인가 사용자")', "CURSOR_END = ()", ["case_01"]),
    "M2": ("socket.py", "for channel in self._scan_order():", "for channel in ():", ["case_04"]),
    "M3": ("socket.py", "oldest = max((float(self.watermark) if self.watermark else self.now()) - 60.0, 0.0)",
           "oldest = max(self.now() - 60.0, 0.0)", ["case_04", "case_05"]),
    "M4": ("socket.py", "self.router.deliver = self.worker.wrap(self.router.deliver)",
           "self.router.deliver = self.router.deliver", ["case_09"]),
    "M5": ("socket.py", "        self.worker.on_idle()  # S3", "        pass  # S3", ["case_13"]),
    "M6": ("socket.py", 'event.get("type") in ("channel_archive", "group_archive")', 'event.get("type") in ()',
           ["case_12"]),
    "M7": ("socket.py", "        self.worker.on_idle()  # S3",
           "        self.worker.on_idle(); self.worker.submit(self._backfill_job)  # S3", ["case_15"]),
    "M8": ("backfill.py", 'if "thread_not_found" in str(exc):', "if False:", ["case_03"]),
    "M9": ("socket.py", "self.router.deliver = self.worker.wrap(self.router.deliver)",
           "self.router.deliver = lambda *a, **k: None", ["case_17"]),
    "M10": ("socket.py", "done, seen = self._discover(deadline)",
            "done, seen = (self.worker.submit(self._discover, deadline), (True, {}))[1]", ["case_19"]),
    "M11": ("socket.py", 'self.watermark = str(event["ts"])', 'self.watermark = "%.6f" % self.now()', ["case_20"]),
    "M13": ("socket.py", "self.receive.resend = self.worker.wrap(self.receive.resend)",
            "self.receive.resend = self.receive.resend", ["case_21"]),
    "M12": ("backfill.py", 'CURSOR_END = ("bot", "미인가 사용자")',
            'CURSOR_END = ("bot", "미인가 사용자", "허용 밖 채널")', ["case_19"]),
}


def test_mutants(tmp_path):
    """M1~M12 — 사본에 변이를 넣으면 그 사례가 FAIL(원본 대조 = 위 두 시험)."""
    caught, took = {}, {}
    shutil.copytree(FT2, tmp_path / "pack", ignore=shutil.ignore_patterns("__pycache__", "tests"))
    pack_dir = os.path.join(str(tmp_path), "pack", "adapters", "slack")
    origin = {name: open(os.path.join(pack_dir, name), encoding="utf-8").read() for name in ("socket.py", "backfill.py")}
    for name, (fname, old, new, cases) in MUTANTS.items():
        assert old in origin[fname], "%s 자리 없음" % name
        with open(os.path.join(pack_dir, fname), "w", encoding="utf-8") as handle:
            handle.write(origin[fname].replace(old, new, 1))
        pack = pack_of(pack_dir)
        for case in cases:
            started = time.time()
            with pytest.raises(AssertionError):
                _with_pack(pack, CASES[case], tmp_path / (name + "-" + case))
            took["%s-%s" % (name, case)] = round(time.time() - started, 2)
            caught.setdefault(name, []).append(case)
        with open(os.path.join(pack_dir, fname), "w", encoding="utf-8") as handle:  # 원본 복구
            handle.write(origin[fname])
    assert sorted(caught) == sorted(MUTANTS)  # 변이 12개가 다 잡혔다
    print("R2341 변이 단계별 초", took)


def _with_pack(pack, case, path):
    """사본 팩 모듈로 같은 사례 1회 — 시험이 제품을 다시 읽지 않게 pack 을 꽂는다."""
    os.makedirs(str(path), exist_ok=True)
    original = globals()["pack_of"]
    globals()["pack_of"] = lambda base=None: pack if base is None else original(base)
    try:
        case(path)
    finally:
        globals()["pack_of"] = original
