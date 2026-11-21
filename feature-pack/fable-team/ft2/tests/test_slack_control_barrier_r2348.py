"""r2348 ft2 Slack 제어 사건(봇 가입·관리 명령) 일꾼 + 장벽 — 반례 ①~⑬ + 변이 M1~M7.

대역 = r2341 시험의 ws·Web·mbox 대역 그대로(import) + 넣은 차례대로 흘리는 가짜 ws(Feed · ⑪ ⑬ 의 사이 시점).
실 Slack·실 쪽지·실 자격 0 · sleep 0(기다림은 Event·wait_for 뿐) · 시험 1개 70초 안 · 동시 4.
단계별 초 = 실행 끝 요약(`R2348 단계별 초`).
"""
import json, os, queue, shutil, sys, threading, time  # noqa: E401
import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_slack_listen_reconnect_r2341 import (  # noqa: E401 — r2341 대역 그대로 쓴다
    BOT, CH, FT2, HELLO, HUMAN, Band, Clock, FakeConnect, channels_rows, env, ledger, listen_lines,
    make_listener, msg, pack_of, wait_for)

C9, C8, C10, CHADMIN, CHOLD = "C0NEW00009", "C0NEW00008", "C0NEW00010", "C0ADMIN001", "C0OLD00007"
WORKER = "ft2-slack-worker"


def soon(check, limit=8.0):  # 사건은 밀리초 안에 난다 — 대기 상한은 짧게(변이 판이 길어지지 않게)
    return wait_for(check, limit)


def join(ts, channel=C9, user=BOT):  # 봇 가입 = 제어 사건(conversations.info 1회)
    return {"type": "member_joined_channel", "user": user, "channel": channel, "ts": ts}


def seed(*channels):  # CHANNELS 씨앗 — 1번째 main · 2번째 admin · 나머지 req
    return ",".join(channels)


def tape_web(band, gate=None, fail=()):  # band.web 감싸기 — «어느 스레드가 어느 method» + 붙잡기·실패 주입
    calls, inner = [], band.web

    def web(method, token, params=None, retry=True, **budget):
        channel = (params or {}).get("channel")
        calls.append((threading.current_thread().name, method, channel))
        if method in fail:
            raise OSError("대역 실패 " + method)
        if gate is not None:
            release = gate(method, channel)
            if release is not None:
                release.wait(20)
        out = inner(method, token, params, retry=retry, **budget)
        if method == "chat.postMessage":
            out = dict(out, ts=out.get("ts") or "9999.000001")  # 명령 답글 ts 대역
        return out

    band.web = web
    return calls


def run_hooked(pack, band, clock, scripts, session=1, prepare=None, connect=None, **kw):
    """대역 ws(또는 Feed) + 실 수신 루프 — 시작 전에 prepare(listener) 로 사본 손질."""
    band.scripts = [list(script) for script in scripts]
    listener = make_listener(pack, band, clock, **({"connect": connect} if connect else {}), **kw)
    if prepare is not None:
        prepare(listener)
    thread = threading.Thread(target=lambda: listener.run(sessions=session), daemon=True)
    thread.start()
    return listener, thread


class Feed:
    """시험이 프레임을 넣는 가짜 ws — 넣을 때까지 recv 는 timeout 초만큼 기다린다(유휴 = 1초 폴링 그대로).

    사이 시점(⑪ ⑬)을 시험이 쥐려고 큐 대역을 하나 더 둔다 — 실제 ws 처럼 «기다렸다 없으면 TimeoutError».
    """

    def __init__(self):
        self.frames, self.sent, self.cond = [], [], threading.Condition()

    def put(self, frame):
        with self.cond:
            self.frames.append(frame)
            self.cond.notify_all()

    def recv(self, timeout=None):
        with self.cond:
            if not self.frames:
                self.cond.wait(timeout)
            if not self.frames:
                raise TimeoutError("유휴")
            return json.dumps(self.frames.pop(0))

    def send(self, data):
        with self.cond:
            self.sent.append(json.loads(data)["envelope_id"])

    def acked(self, count):  # 그만큼 확인을 보냈나(프레임 하나 = 확인 하나)
        with self.cond:
            return len(self.sent) >= count


class Seq:
    """n번째 conversations.info 를 붙잡는다 — 시험이 차례로 풀어 스케줄을 흔든다(②)."""

    def __init__(self, *channels):
        self.channels, self.hits, self.lock, self.tokens = list(channels), 0, threading.Lock(), {}

    def __call__(self, method, channel):
        if method != "conversations.info" or channel not in self.channels:
            return None
        with self.lock:
            self.hits += 1
            return self.tokens.setdefault(channel, threading.Event())

    def hit(self, index):
        return self.channels[index] in self.tokens

    def release(self, index):
        self.tokens.pop(self.channels[index]).set()


def routed(tmp, ts):  # 그 글의 route 장부 state 목록(차례 그대로)
    return [row.get("state") for row in ledger(tmp, "route.jsonl") if row.get("t") == "route" and row["key"][2] == ts]


def says(tmp, *words):  # listen.log 줄 중 낱말을 다 담은 줄
    return [line for line in listen_lines(tmp) if all(word in line for word in words)]


# ── ①~⑦
def case_01(tmp):
    """① 봇 가입(C9) 직후 같은 연결 C9 사람 글 → add_auto 1 · 그 글 dispatched 1(장벽 없으면 옛 집합 = ignored)."""
    clock, pack, band = Clock(), pack_of(), None
    band = Band(tmp, clock)
    band.info[C9] = {"name": "c9"}
    gate = Seq(C9)
    tape_web(band, gate=gate)  # 효과를 붙잡아 «글 판정»이 먼저 오게 한다(순서 = 이 카드의 전부)
    stamp, ts = clock.ts(), "%.6f" % (clock.t + 1)
    listener, thread = run_hooked(pack, band, clock, [[HELLO, env("E1", join(stamp)), env("E2", msg(ts, channel=C9))]])
    assert soon(lambda: gate.hit(0))
    assert soon(lambda: len(band.acks) >= 2)  # 두 envelope 다 확인 = 글 판정이 이미 끝났다
    gate.release(0)
    thread.join(60)
    band.close()
    assert [row[0] for row in channels_rows(tmp) if row[3] == "auto"] == [C9]  # 효과 1(일꾼)
    assert routed(tmp, ts) == ["dispatched"]  # 새 허용 집합으로 판정
    assert listener.deferred == 0  # 장벽 풀림


def case_02(tmp):
    """② ① 을 100회 다른 스레드 스케줄로(장벽 멈춤 지점 주입) → 결과 같음 100/100."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    channels = ["C0R%05d" % index for index in range(100)]
    for channel in channels:
        band.info[channel] = {"name": channel.lower()}
    gate = Seq(*channels)
    tape_web(band, gate=gate)
    script, stamps = [HELLO], []
    for index, channel in enumerate(channels):
        stamps.append("%.6f" % (clock.t + index * 2 + 2))
        script += [env("J%d" % index, join("%.6f" % (clock.t + index * 2 + 1), channel)),
                   env("M%d" % index, msg(stamps[-1], channel=channel))]
    def room(listener):  # 좌석 용량 대역(기본 8) — 100건 다 dispatched 되게(② 는 판정 결과를 본다)
        listener.receive.client.capacity = 200

    listener, thread = run_hooked(pack, band, clock, [script], prepare=room)
    for index in range(100):
        assert soon(lambda index=index: gate.hit(index))  # 제어 사건이 일꾼에 들어갔다
        if index % 2:  # 홀수 = 그 글의 ack 를 본 뒤 풀기(미룬 글이 이미 큐에 있다)
            assert soon(lambda index=index: len(band.acks) >= 2 * (index + 1))
        gate.release(index)
    thread.join(60)
    band.close()
    assert [row[0] for row in channels_rows(tmp) if row[3] == "auto"] == channels
    assert [stamp for stamp in stamps if routed(tmp, stamp) == ["dispatched"]] == stamps  # 100/100


def case_03(tmp):
    """③ 관리 명령 «등록 #new» 직후 그 채널 글 → 등록 1 · 글 dispatched 1 · chat.postMessage 1(일꾼)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    calls = tape_web(band)
    cmd, ts = clock.ts(), "%.6f" % (clock.t + 1)
    feed = Feed()  # 연결을 시험이 닫는다 — 남은 일감이 수신 스레드 drain 으로 새지 않게
    feed.put(HELLO)
    listener, thread = run_hooked(pack, band, clock, [], connect=FakeConnect(feed), channel=seed(CH, CHADMIN))
    assert soon(lambda: listener.ws is feed)
    feed.put(env("E1", msg(cmd, channel=CHADMIN, text="등록 <#%s|c9>" % C9)))
    feed.put(env("E2", msg(ts, channel=C9)))
    assert soon(lambda: routed(tmp, ts) == ["dispatched"])  # 효과 뒤 = 새 허용 집합
    feed.put({"type": "disconnect"})
    thread.join(60)
    band.close()
    assert [row for row in channels_rows(tmp) if row[0] == C9] == [[C9, "c9", "on", "req", "-"]]
    assert routed(tmp, ts) == ["dispatched"]
    posts = [call for call in calls if call[1] == "chat.postMessage"]
    assert [call[0] for call in posts] == [WORKER]  # 답글 = 일꾼


def case_04(tmp):
    """④ «삭제 #old» 직후 그 채널 글 → 삭제 1 · 글 ignored(허용 밖) 1."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band)
    cmd, ts = clock.ts(), "%.6f" % (clock.t + 1)
    frames = [HELLO, env("E1", msg(cmd, channel=CHADMIN, text="삭제 <#%s|old>" % CHOLD)), env("E2", msg(ts, channel=CHOLD))]
    thread = run_hooked(pack, band, clock, [frames], channel=seed(CH, CHADMIN, CHOLD))[1]
    thread.join(60)
    band.close()
    assert [row[2] for row in channels_rows(tmp) if row[0] == CHOLD] == ["off"]
    assert routed(tmp, ts) == ["ignored"]


def case_05(tmp):
    """⑤ 제어 사건 처리 중 수신 스레드 Web 호출 0(가짜 Web 이 부른 스레드 이름 기록)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.info[C9], band.info[C8] = {"name": "c9"}, {"name": "c8"}
    calls = tape_web(band)
    join_ts, cmd = clock.ts(), "%.6f" % (clock.t + 1)
    feed = Feed()  # 연결을 시험이 닫는다 — 일감이 수신 스레드 drain 으로 새면 «수신 스레드 Web 0» 이 흔들린다
    feed.put(HELLO)
    listener, thread = run_hooked(pack, band, clock, [], connect=FakeConnect(feed), channel=seed(CH, CHADMIN))
    assert soon(lambda: listener.ws is feed)
    feed.put(env("E1", join(join_ts)))
    feed.put(env("E2", msg(cmd, channel=CHADMIN, text="등록 <#%s|c8>" % C8)))
    assert soon(lambda: [row for row in channels_rows(tmp) if row[0] == C8])  # 두 효과 다 끝났다
    assert soon(lambda: listener.deferred == 0)
    feed.put({"type": "disconnect"})
    thread.join(60)
    band.close()
    join_calls = [call for call in calls if (call[1] == "conversations.info" and call[2] in (C9, C8))
                  or call[1] == "chat.postMessage"]  # hello 몫(씨앗 채널 참여 확인)은 뺀다
    assert join_calls and [call[0] for call in join_calls] == [WORKER] * len(join_calls)
    discover = [call[0] for call in calls if call[1] == "users.conversations"]  # hello 1회(수신) + lookups 1회(일꾼)
    assert discover.count(WORKER) >= 1 and discover.count(thread.name) == 1


def case_06(tmp):
    """⑥ 제어 사건 Web 7초 흉내 → 수신 스레드 ack 지연 0 · 다음 frame 즉시 처리(E3)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.info[C9], band.info[C10] = {"name": "c9"}, {"name": "c10"}
    gate = Seq(C9, C10)
    tape_web(band, gate=gate)
    stamp, second = clock.ts(), "%.6f" % (clock.t + 1)
    frames = [HELLO, env("E1", join(stamp)), env("E2", join(second, C10))]
    listener, thread = run_hooked(pack, band, clock, [frames])
    assert soon(lambda: gate.hit(0))  # 첫 제어 사건이 Web 에서 붙잡혀 있다
    assert soon(lambda: len(band.acks) >= 2)  # 그동안 두 envelope 다 확인됨 = 수신 루프 안 막힘
    assert listener.deferred == 2  # 둘 다 일꾼 큐 뒤
    gate.release(0)
    assert soon(lambda: gate.hit(1))
    gate.release(1)
    thread.join(60)
    band.close()
    assert [row[0] for row in channels_rows(tmp) if row[3] == "auto"] == [C9, C10]  # 효과는 결국 다 함


def case_07(tmp):
    """⑦ conversations.info 실패 → listen.log 1줄 · 효과 0 · 장벽 풀림 · 뒤 글 = 옛 허용 집합(ignored)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band, fail=("conversations.info",))
    stamp, ts = clock.ts(), "%.6f" % (clock.t + 1)
    frames = [HELLO, env("E1", join(stamp)), env("E2", msg(ts, channel=C9))]
    listener, thread = run_hooked(pack, band, clock, [frames])
    thread.join(60)
    band.close()
    assert len(says(tmp, "판정 불가 자동 채널", C9)) == 1
    assert [row[0] for row in channels_rows(tmp) if row[3] == "auto"] == []  # 효과 0
    assert listener.deferred == 0  # 장벽 풀림
    assert routed(tmp, ts) == ["ignored"]  # 옛 허용 집합


# ── ⑧~⑬
def case_08(tmp):
    """⑧ 장벽 중 일꾼 큐 가득(상한 흉내 1) → «장벽 넘침» 1줄 · 수신 스레드 직접 route."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.info[C9] = {"name": "c9"}
    gate = Seq(C9)
    tape_web(band, gate=gate)
    stamp, first, second = clock.ts(), "%.6f" % (clock.t + 1), "%.6f" % (clock.t + 2)

    def squeeze(listener):  # 일꾼 큐 1칸 — 제어 사건이 붙잡힌 동안 두 번째 글은 못 들어간다
        listener.worker.queue, listener.worker.cap = queue.Queue(maxsize=1), 1

    frames = [HELLO, env("E1", join(stamp)), env("E2", msg(first, channel=C9)), env("E3", msg(second, channel=C9))]
    listener, thread = run_hooked(pack, band, clock, [frames], prepare=squeeze)
    assert soon(lambda: gate.hit(0))
    assert soon(lambda: len(band.acks) >= 3)  # 세 frame 다 지나갔다(넘침 판정 포함)
    assert len(says(tmp, "장벽 넘침")) == 1
    gate.release(0)
    thread.join(60)
    band.close()
    assert routed(tmp, second) == ["ignored"]  # 넘침 = 그 자리 판정(옛 집합)
    assert routed(tmp, first) == ["dispatched"]  # 큐에 있던 글은 효과 뒤 = 새 집합


def case_09(tmp):
    """⑨ r2391 로 뜻이 바뀌었다 — 제어 사건 0 인 연결에서도 사람 글은 일꾼 큐(수신 스레드 = ack + 큐 넣기)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    tape_web(band)
    ts, seen = clock.ts(), []

    def watch(listener):
        inner = listener.route
        listener.route = lambda event: (seen.append((threading.current_thread().name, (event or {}).get("ts"))),
                                        inner(event))[1]

    listener, thread = run_hooked(pack, band, clock, [[HELLO, env("E1", msg(ts))]], prepare=watch)
    thread.join(60)
    band.close()
    assert seen == [(WORKER, ts)]  # r2391 — 일꾼이 묶고·라우팅한다(수신 스레드는 ack + 큐 넣기)
    assert says(tmp, "미룸") == []  # 장벽 0 = 미룸 줄 0
    assert routed(tmp, ts) == ["dispatched"]


def case_10(tmp):
    """⑩ 일꾼에서 도는 route 도 같은 길(binding·receive 장부) · ack 는 수신 스레드에서만(E5)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.info[C9] = {"name": "c9"}
    tape_web(band)
    stamp, ts = clock.ts(), "%.6f" % (clock.t + 1)
    frames = [HELLO, env("E1", join(stamp)), env("E2", msg(ts, channel=C9))]
    listener, thread = run_hooked(pack, band, clock, [frames])
    thread.join(60)
    band.close()
    assert [ack[0] for ack in band.acks] == ["E1", "E2"]  # envelope 1개 = 확인 1회(일꾼이 남의 것 0)
    assert [row for row in ledger(tmp, "bindings.jsonl") if row.get("key", [None, None, None])[2] == ts]
    assert [row["state"] for row in ledger(tmp, "receive.jsonl") if row.get("key", [None, None, None])[2] == ts] == ["received", "dispatched"]


def case_11(tmp):
    """⑪ 제어 C → 새 root 글 m1(미룸) → C 끝 → 같은 thread 답 m2 → m1 이 m2 보다 먼저 route · m2 binding 있음."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.info[C9] = {"name": "c9"}
    gate = Seq(C9)
    tape_web(band, gate=gate)  # 제어 사건을 Web 에서 붙잡아 둔다(그 사이 글이 온다)
    feed, seen, entered, release = Feed(), [], threading.Event(), threading.Event()
    stamp, first, second = clock.ts(), "%.6f" % (clock.t + 1), "%.6f" % (clock.t + 2)

    def watch(listener):  # m1 의 route 를 일꾼 안에서 붙잡는다(= 그 글이 아직 큐에 있다)
        inner = listener.route

        def route(event):
            seen.append((threading.current_thread().name, (event or {}).get("ts")))
            if (event or {}).get("ts") == first:
                entered.set()
                release.wait(20)
            return inner(event)

        listener.route = route

    feed.put(HELLO)  # hello 는 연결 즉시 읽는다 — 시작 전에 넣어 둔다
    listener, thread = run_hooked(pack, band, clock, [], connect=FakeConnect(feed), prepare=watch)
    assert soon(lambda: listener.ws is feed)
    feed.put(env("E1", join(stamp)))
    assert soon(lambda: gate.hit(0))  # 제어 사건이 일꾼 안에서 Web 에 붙잡혀 있다
    assert soon(lambda: listener.deferred == 1)
    feed.put(env("E2", msg(first, channel=C9)))
    assert soon(lambda: listener.deferred == 2)  # m1 도 큐 뒤
    gate.release(0)  # C 끝 → 일꾼이 m1 을 집는다
    assert soon(lambda: entered.is_set())  # m1 이 붙잡혔다(아직 안 끝남 = 셈 1)
    feed.put(env("E3", msg(second, channel=C9, thread=first)))
    assert soon(lambda: listener.deferred == 2)  # C 끝난 뒤 온 m2 도 m1 뒤(셈 = m1 + m2)
    release.set()
    assert soon(lambda: listener.deferred == 0)
    feed.put({"type": "disconnect"})
    thread.join(60)
    band.close()
    assert [ts for thread_name, ts in seen if ts in (first, second)] == [first, second]  # 차례 그대로
    assert [row for row in ledger(tmp, "bindings.jsonl") if row.get("key", [None, None, None])[2] == first]  # m1 이 묶었다
    assert routed(tmp, first) == ["dispatched", "dispatched"]  # m1·m2 둘 다 새 집합으로(차례 = seen)


def case_12(tmp):
    """⑫ 장벽 중 글 1 → listen.log «미룸» 1 · 일꾼 route 뒤 «미룸 끝» 1(DA#44 B2)."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.info[C9] = {"name": "c9"}
    gate = Seq(C9)
    tape_web(band, gate=gate)
    stamp, ts = clock.ts(), "%.6f" % (clock.t + 1)
    frames = [HELLO, env("E1", join(stamp)), env("E2", msg(ts, channel=C9))]
    listener, thread = run_hooked(pack, band, clock, [frames])
    assert soon(lambda: gate.hit(0))
    assert soon(lambda: says(tmp, "미룸 %s %s" % (C9, ts)))  # 미룰 때 1줄
    assert says(tmp, "미룸 끝 %s" % ts) == []  # 아직 안 끝났다
    gate.release(0)
    thread.join(60)
    band.close()
    assert says(tmp, "미룸 끝 %s" % ts) and len(says(tmp, "미룸 %s %s" % (C9, ts))) == 1
    pairs = [line for line in listen_lines(tmp) if "미룸" in line]
    assert len([line for line in pairs if "미룸 끝" not in line]) == len([line for line in pairs if "미룸 끝" in line])


def case_13(tmp):
    """⑬ 장벽 중 사람 가입 = 셈 +0 · 뒤 글은 여전히 큐 뒤 · 장벽 밖 사람 가입 = 장벽 0·뒤 글 직접."""
    clock, pack = Clock(), pack_of()
    band = Band(tmp, clock)
    band.info[C9] = {"name": "c9"}
    gate = Seq(C9)
    tape_web(band, gate=gate)  # 제어 사건은 Web 에 붙잡아 둔다(사람 가입·뒤 글이 그 사이 온다)
    feed, seen = Feed(), []
    stamp, human, ts = clock.ts(), "%.6f" % (clock.t + 1), "%.6f" % (clock.t + 2)
    later = "%.6f" % (clock.t + 3)

    def watch(listener):
        inner = listener.route
        listener.route = lambda event: (seen.append((threading.current_thread().name, (event or {}).get("ts"))),
                                        inner(event))[1]

    feed.put(HELLO)  # hello 는 연결 즉시 읽는다 — 시작 전에 넣어 둔다
    listener, thread = run_hooked(pack, band, clock, [], connect=FakeConnect(feed), prepare=watch)
    assert soon(lambda: listener.ws is feed)
    feed.put(env("E1", join(stamp)))
    assert soon(lambda: gate.hit(0))  # 제어 사건이 일꾼 안에서 붙잡혀 있다
    assert soon(lambda: listener.deferred == 1)
    feed.put(env("E2", join(human, CH, HUMAN)))  # 장벽 중 사람 가입 = 제어 사건 아님
    assert soon(lambda: feed.acked(2))
    assert listener.deferred == 1  # 셈 +0
    assert [row for row in channels_rows(tmp) if row[0] == CH][0][3] == "main"  # 효과 0
    feed.put(env("E3", msg(ts, channel=C9)))
    assert soon(lambda: listener.deferred == 2)  # 뒤 글은 여전히 큐 뒤
    gate.release(0)
    assert soon(lambda: listener.deferred == 0)  # 제어·글 다 끝나면 풀린다
    feed.put(env("E4", join(later, CH, HUMAN)))  # 장벽 밖 사람 가입 = 장벽 0
    assert soon(lambda: feed.acked(4))
    feed.put(env("E5", msg(later, channel=CH)))
    assert soon(lambda: routed(tmp, later) == ["dispatched"])
    assert says(tmp, "미룸 %s %s" % (C9, ts)) and says(tmp, "미룸 %s" % later) == []  # 장벽 밖 = 미룸 0
    feed.put({"type": "disconnect"})
    thread.join(60)
    band.close()
    assert [ts for thread_name, ts in seen if thread_name != WORKER] == []  # r2391 — 장벽 밖 글도 일꾼


CASES = {name: value for name, value in sorted(globals().items()) if name.startswith("case_")}
STEPS = {}


def _run(names, tmp_path):
    for name in names:
        started = time.time()
        CASES[name](str(tmp_path / name))
        STEPS[name] = round(time.time() - started, 2)


def test_cases_01_07(tmp_path):
    """①~⑦ — 봇 가입·관리 명령 효과가 일꾼으로 · 그동안 온 글은 큐 뒤."""
    _run(["case_%02d" % number for number in range(1, 8)], tmp_path)
    print("R2348 단계별 초 ①~⑦", STEPS)


def test_cases_08_13(tmp_path):
    """⑧~⑬ — 넘침·제어 0·같은 길·차례·미룸 줄·사람 가입."""
    _run(["case_%02d" % number for number in range(8, 14)], tmp_path)
    print("R2348 단계별 초 ⑧~⑬", STEPS)


# ── 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더)
MUTANTS = {
    "M1": ("socket.py",  # r2391 — 글 차례는 큐가 지킨다 · 장벽 셈의 남은 몫 = 장벽 밖 글에 «미룸» 줄 0
           "            return self.deferred > 0", "            return True", ["case_09"]),
    "M2": ("socket.py", "            return self._control(self._admin_job, event)",
           "            return self._admin_job(event)", ["case_05"]),
    "M3": ("socket.py", "                self.deferred -= 1  # 끝난 일은 셈에서 뺀다",
           "                pass  # 끝난 일은 셈에서 뺀다", ["case_07"]),
    "M4": ("socket.py", "        job(event)  # 넘침 = 차례 포기",
           "        pass  # 넘침 = 차례 포기", ["case_08"]),
    "M5": ("socket.py", "        return self._defer(self.route, event) if self._barrier() else self._queue_route(event)",
           "        return self.route(event)", ["case_01"]),
    "M6": ("socket.py", "            self.deferred += 1  # 미룬 일도 셈(DA#44 B1 · ⑪)",
           "            pass  # 미룬 일도 셈(DA#44 B1 · ⑪)", ["case_11"]),
    "M7": ("socket.py", '            self.log("미룸 %s %s" % (channel, ts))  # 남은 쌍 = 손 복구 근거(DA#44 B2 ⓐ)',
           "            pass  # 남은 쌍 = 손 복구 근거(DA#44 B2 ⓐ)", ["case_12"]),
}
BELOW = {"M3": ["case_13"]}  # 변이 하나가 더 잡는 사례(카드 밖 · 실측: 장벽이 안 풀려 사람 가입 판정도 어긋난다)


def test_mutants(tmp_path):
    """M1~M7 — 사본에 변이를 넣으면 그 사례가 FAIL(원본 대조 = 위 두 시험)."""
    caught, took = {}, {}
    shutil.copytree(FT2, tmp_path / "pack", ignore=shutil.ignore_patterns("__pycache__", "tests"))
    pack_dir = os.path.join(str(tmp_path), "pack", "adapters", "slack")
    origin = open(os.path.join(pack_dir, "socket.py"), encoding="utf-8").read()
    for name, (fname, old, new, cases) in MUTANTS.items():
        assert old in origin, "%s 자리 없음" % name
        with open(os.path.join(pack_dir, fname), "w", encoding="utf-8") as handle:
            handle.write(origin.replace(old, new, 1))
        pack = pack_of(pack_dir)
        for case in cases + BELOW.get(name, []):
            started = time.time()
            try:
                with pytest.raises(AssertionError):
                    _with_pack(pack, CASES[case], tmp_path / (name + "-" + case))
            except pytest.fail.Exception as exc:
                raise AssertionError("%s-%s 변이 미검거" % (name, case)) from exc
            took["%s-%s" % (name, case)] = round(time.time() - started, 2)
            caught.setdefault(name, []).append(case)
        with open(os.path.join(pack_dir, fname), "w", encoding="utf-8") as handle:  # 원본 복구
            handle.write(origin)
    assert sorted(caught) == sorted(MUTANTS)  # 변이 7개가 다 잡혔다
    print("R2348 변이 단계별 초", took)


def _with_pack(pack, case, path):
    """사본 팩 모듈로 같은 사례 1회 — 시험이 제품을 다시 읽지 않게 pack 을 꽂는다."""
    os.makedirs(str(path), exist_ok=True)
    original = globals()["pack_of"]
    globals()["pack_of"] = lambda base=None: pack
    try:
        case(str(path))
    finally:
        globals()["pack_of"] = original
