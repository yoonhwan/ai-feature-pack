"""r1899 재기동 recover full 갈래 — 봇이 이미 답한 full 글 = settled(재배달 0) · 판정 불가 = 넣기 0 · 배치 예산 60초 · 굶음 0.
반례 ①~⑨ · 변이 M1~M5. 임시 root · 실 Intake · 가짜 replies·가짜 urlopen·가상 시계 · 실 Slack·설치·sleep 0."""
import importlib.util, json, os  # noqa: E401

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T, C, U = "TFAKE", "CFAKE", "U"
def _load(name):
    spec = importlib.util.spec_from_file_location("r1899_" + name, os.path.join(FT2, "adapters", "slack", name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module
receive, sock = _load("receive"), _load("socket")
TS = ["17945610%02d.000001" % i for i in range(40)]   # 글 ts — 번호가 클수록 새 글
cmd = lambda n: "slack:%s:%s:%s" % (T, C, TS[n])  # noqa: E731
bot = lambda n: {"ts": TS[n], "bot_id": "B1", "text": "답"}  # noqa: E731
states = lambda rx_, idx: [rx_.latest()[cmd(n)]["state"] for n in idx]  # noqa: E731

class Replies:   # thread → 메시지 목록 | 예외 · 호출 기록 · 가상 시계 cost 초
    def __init__(self, table, clock=None, cost=0):
        self.table, self.calls, self.clock, self.cost = table, [], clock, cost
    def __call__(self, channel, thread):
        self.calls.append(thread)
        self.clock and self.clock.__setitem__(0, self.clock[0] + self.cost)
        if isinstance(out := self.table.get(thread, []), Exception):
            raise out
        return out

def world(root, idx, used, replies=None, clock=None, threads=None):
    """full 글 idx(번호) · 재기동 수신기(남은 일 used → room = 8 − used)."""
    first = rx(root, 0, None)
    for n in sorted(idx):
        assert first.handle({"team": T, "channel": C, "user": U, "ts": TS[n], "text": "글 %d" % n})["state"] == receive.FULL
    with open(os.path.join(first.root, ".fable-team", "teams", "planner", "slack", "route.jsonl"), "a") as fh:
        for n, thread in (threads or {}).items():
            fh.write(json.dumps({"t": "route", "command": cmd(n), "key": [T, C, thread]}) + "\n")
    again = rx(root, 8, replies, clock)
    for i in range(used):
        assert again.client.submit("busy%d" % i, "body", "W%d" % i).result == receive.RESULT_OK
    return again

def rx(root, capacity, replies, clock=None):
    client = receive.intake.Intake(str(root), "planner", capacity=capacity)
    return receive.SlackReceive(str(root), ack=lambda e: None, client=client, team="planner", allowed_users=(U,),
                                allowed_channels=(C,), notify=lambda row: None, replies=replies,
                                deadline=None if clock is None else 60, mono=clock and (lambda: clock[0]))

def test_c1_c2_answered_settled_unanswered_submitted_redelivery_duplicate(tmp_path):
    again = world(tmp_path, [1, 2], 6, Replies({TS[1]: [bot(3)], TS[2]: []}))
    again.recover()
    assert states(again, [1, 2]) == ["settled", "dispatched"]
    assert "봇 답 있음 %s" % TS[3] in again.latest()[cmd(1)]["reason"]
    lines = len(again.entries())
    again.recover()                                                                       # ② 재기동 1번 더
    assert len(again.entries()) == lines
    out = again.handle({"team": T, "channel": C, "user": U, "ts": TS[1], "text": "글 1"})   # Slack 재전달
    assert out["state"] == "duplicate" and states(again, [1]) == ["duplicate"]

def test_c3_unknown_no_submit_full_kept_one_log(tmp_path):
    logs, err = [], RuntimeError("conversations.replies ratelimited")
    again = world(tmp_path, [1, 2], 6, Replies({TS[1]: err, TS[2]: err}))
    again.log = logs.append
    again.recover()
    assert states(again, [1, 2]) == ["full", "full"] and again.latest()[cmd(2)]["unknown"] == 1
    assert len([ln for ln in logs if "판정 불가" in ln]) == 1

def test_c4_bot_before_message_is_not_answer_c6_no_replies_same_as_before(tmp_path):
    again = world(tmp_path, [5], 6, Replies({TS[5]: [bot(4)]}))
    again.recover()
    assert states(again, [5]) == ["dispatched"]
    (plain := world(tmp_path / "b", [1, 2], 6)).recover()
    assert states(plain, [1, 2]) == ["dispatched", "dispatched"]

def test_c5_same_thread_one_call(tmp_path):
    fake = Replies({TS[0]: [bot(9)]})
    again = world(tmp_path, [1, 2, 3], 5, fake, threads={1: TS[0], 2: TS[0], 3: TS[0]})
    again.recover()
    assert fake.calls == [TS[0]] and states(again, [1, 2, 3]) == ["settled"] * 3

def test_c8_unknown_goes_back_no_starving(tmp_path):
    clock = [0]
    slow = Replies({TS[9]: TimeoutError("7초")}, clock, cost=60)     # A(새 글 9) 확인이 예산을 다 먹음
    world(tmp_path, [1, 9], 7, slow, clock).recover()
    clock[0] = 0
    again = rx(tmp_path, 8, Replies({TS[9]: TimeoutError("7초")}, clock, cost=60), clock)
    again.recover()
    assert again.replies.calls[0] == TS[1] and states(again, [1, 9]) == ["dispatched", "full"]

def test_c9_room_one_checks_only_until_filled(tmp_path):
    fake = Replies({TS[5]: [bot(20)], TS[4]: [bot(21)], TS[3]: []})
    again = world(tmp_path, [1, 2, 3, 4, 5], 7, fake)
    again.recover()
    assert states(again, [5, 4, 3, 2, 1]) == ["settled", "settled", "dispatched", "full", "full"]
    assert fake.calls == [TS[5], TS[4], TS[3]]

def test_c7_budget_60s_real_web_api_real_listen_log(tmp_path, monkeypatch):
    clock, opened = [0.0], []
    def urlopen(req, timeout):
        opened.append(timeout)
        clock[0] += timeout
        raise TimeoutError("가상 %s초" % timeout)
    monkeypatch.setattr(sock.urllib.request, "urlopen", urlopen)
    li = sock.Listener(str(tmp_path), channel=C, app_token="xapp-F", bot_token="xoxb-F", master="m#1", users=(U,),
                       team="planner", mono=lambda: clock[0], clock=lambda: "2026-11-14T00:00:00")
    for n in range(32):
        li.receive._append({"state": "full", "command": cmd(n), "key": [T, C, TS[n]], "attempts": 1, "text": "글"})
    clock[0] = 9.0                                              # 기동 고정비 가상 9초
    li.receive.recover()
    assert clock[0] <= 60 and opened == [7] * 7 + [2]          # API 51초 · 마지막 timeout 2초
    assert states(li.receive, range(32)) == ["full"] * 32
    log = (tmp_path / ".fable-team" / "teams" / "planner" / "slack" / "listen.log").read_text(encoding="utf-8")
    assert log.count("예산 끝") == 1 and "남은 full 27건" in log
