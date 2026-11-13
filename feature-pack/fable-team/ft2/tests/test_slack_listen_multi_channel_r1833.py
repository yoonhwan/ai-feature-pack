"""r1833 Slack 수신기 채널 여러 개(#byz-desk) + 깨움 상한 25초·적재 판정 시험 — 반례 ①~⑤(①′·②′·②″·④′).
임시 root · 가짜 ws(envelope 주입) · 가짜 web(conversations.info 주입) · 가짜 깨움(FT2_SLACK_WAKE · 지연·적재 주입)
· 실 Slack·자격·launchd·우편함 0 · sleep 0(지연 = subprocess.run 대역이 상한과 비교) · 기준판(2ea518)에서 ① ② ③ Red."""
import importlib.util, json, os, plistlib, subprocess, sys  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLACK = os.path.join(FT2, "adapters", "slack")
PLIST = os.path.join(SLACK, "launchd", "com.byz.ft2-slack-listen.plist.in")
W, A, B, U = "TFAKE", "CMAIN", "CDESK", "UOPPA"
MASTER, DESK = "byz-planner-master-pi#1", "byz-planner-desk-pi#1"
HELLO = {"type": "hello", "num_connections": 1}
WAKE = "import json, os, sys\nopen(os.environ['FAKE_WAKE_OUT'], 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1833_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


def _rows(root, name):
    path = os.path.join(str(root), ".fable-team", "teams", "planner", "slack", name)
    with open(path, encoding="utf-8") if os.path.exists(path) else open(os.devnull) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def _msg(ts, channel, **extra):
    return dict({"type": "message", "user": U, "channel": channel, "ts": ts, "team": W, "text": "글 " + ts}, **extra)


def _wakes(root, to=None):
    path = os.path.join(str(root), "wakes.jsonl")
    rows = [json.loads(line) for line in open(path, encoding="utf-8")] if os.path.exists(path) else []
    return [row for row in rows if to is None or row[1] == to]


@pytest.fixture
def env(tmp_path, monkeypatch):
    (fable := tmp_path / ".fable-team").mkdir()
    (fable / "seats-planner.json").write_text(json.dumps({"_master": MASTER, "_desk": DESK}), encoding="utf-8")
    (fable / "seats-issues.json").write_text(json.dumps({"_master": "byz-issues-master-sol#1"}), encoding="utf-8")
    (script := tmp_path / "wake.py").write_text(WAKE, encoding="utf-8")
    monkeypatch.setenv("FT2_SLACK_WAKE", "%s %s" % (sys.executable, script))
    monkeypatch.setenv("FAKE_WAKE_OUT", str(tmp_path / "wakes.jsonl"))
    monkeypatch.delenv("FT2_SLACK_WAKE_TIMEOUT", raising=False)
    return tmp_path


class WS:  # 가짜 ws — 대본 frame 을 차례로 주고 끝나면 disconnect
    def __init__(self, frames):
        self.frames, self.acks = list(frames), []
    def __enter__(self):
        return self
    def __exit__(self, *exc):
        return False
    def recv(self, timeout=None):
        return json.dumps(self.frames.pop(0) if self.frames else {"type": "disconnect"})
    def send(self, data):
        self.acks.append(json.loads(data)["envelope_id"])


class Web:  # 가짜 Web API — member = 채널별 True/False/예외
    def __init__(self, member):
        self.member, self.calls, self.posts = member, [], []
    def __call__(self, method, token, params=None, retry=True):
        self.calls.append((method, (params or {}).get("channel")))
        if method == "apps.connections.open":
            return {"ok": True, "url": "ws://fake"}
        if method == "chat.postMessage":
            self.posts.append(dict(params))
            return {"ok": True, "ts": "1800000099.%06d" % len(self.posts)}
        if method == "conversations.info":
            got = self.member[params["channel"]]
            if isinstance(got, Exception):
                raise got
            return {"ok": True, "channel": {"id": params["channel"], "is_member": got}}
        return {"ok": True, "messages": [], "has_more": False}


def _listener(root, channel, web, scripts=(), notes=None):
    return _load("socket").Listener(
        str(root), channel=channel, app_token="xapp-FAKE", bot_token="xoxb-FAKE", master=MASTER, users=(U,),
        web=web, connect=lambda url: WS(scripts.pop(0) if scripts else []), sleep=lambda s: None,
        notify=None if notes is None else notes.append, clock=lambda: "2026-11-13T00:00:00")


def _log(root):
    path = os.path.join(str(root), ".fable-team", "teams", "planner", "slack", "listen.log")
    return open(path, encoding="utf-8").read() if os.path.exists(path) else ""


def test_1_aux_channel_thread_reply_received_desk_wake(env):  # ① B 묶임 없는 thread 답 = 허용 · 재개 필요 · 깨움 1
    web, ts = Web({A: True, B: True}), "1800000001.000200"
    _listener(env, "%s,%s" % (A, B), web).route(_msg(ts, B, thread_ts="1800000001.000100"))
    assert [r["state"] for r in _rows(env, "receive.jsonl")] == ["received", "dispatched"]
    assert [(r["kind"], r["to"]) for r in _rows(env, "route.jsonl") if r["t"] == "route"] == [("재개 필요", "@team-desk")]
    assert len(_wakes(env)) == 1 and len(_wakes(env, DESK)) == 1
    assert web.posts == [] and _rows(env, "publish.jsonl") == [] and _rows(env, "bindings.jsonl") == []


def test_1b_bind_only_main_channel_no_post(env):  # ①′ B 새 root = 묶기 0 · A 새 root = 2ea518 그대로 · 게시 0
    web, tb, ta = Web({A: True, B: True}), "1800000002.000100", "1800000003.000100"
    listener = _listener(env, "%s,%s" % (A, B), web)
    listener.route(_msg(tb, B))
    assert _rows(env, "bindings.jsonl") == [] and web.posts == [] and _rows(env, "publish.jsonl") == []
    listener.route(_msg(ta, A))
    assert [(b["state"], b["key"][1]) for b in _rows(env, "bindings.jsonl")] == [("bound", A)]
    assert [r["state"] for r in _rows(env, "receive.jsonl") if r["key"][1] == A] == ["received", "dispatched"]
    assert len(_wakes(env, MASTER)) == 1 and web.posts == [] and _rows(env, "publish.jsonl") == []


def test_2_member_check_start_and_reconnect(env):  # ② B 미참여 = notify 1줄 · 수신 계속 · A 줄 0
    web, notes, ts = Web({A: True, B: False}), [], "1800000004.000100"
    listener = _listener(env, "%s,%s" % (A, B), web, [[HELLO, _msg_env("E1", _msg(ts, A))], [HELLO]], notes)
    assert listener.run(sessions=2) == 0
    line = "수신 불가 채널 %s — 봇 미참여(/invite 필요)" % B
    assert [n.get("reason") for n in notes] == [line, line]  # 시작 1 + 재연결 1
    assert [c for c in web.calls if c[0] == "conversations.info"] == [("conversations.info", A),
                                                                      ("conversations.info", B)] * 2
    assert _log(env).count(line) == 2 and A not in "".join(n["reason"] for n in notes)
    assert [r["state"] for r in _rows(env, "receive.jsonl")] == ["received", "dispatched"]
    assert "xoxb-" not in _log(env) and "xapp-" not in _log(env)


@pytest.mark.parametrize("fail", [OSError("대역 실패"), RuntimeError("conversations.info channel_not_found")])
def test_2b_member_check_undecided_keeps_listening(env, fail):  # ②′ OSError · ②″ web_api RuntimeError(ok:false)
    web, notes, ts = Web({A: True, B: fail}), [], "1800000005.000100"
    listener = _listener(env, "%s,%s" % (A, B), web, [[HELLO, _msg_env("E1", _msg(ts, A))]], notes)
    assert listener.run(sessions=1) == 0
    assert [n["reason"] for n in notes] == ["판정 불가 채널 %s — %s" % (B, type(fail).__name__)]
    assert [r["state"] for r in _rows(env, "receive.jsonl")] == ["received", "dispatched"]


def _msg_env(eid, event):
    return {"type": "events_api", "envelope_id": eid, "payload": {"team_id": W, "event": event}}


class Run:  # subprocess.run 대역 — 지연 초를 주입하고 상한과 비교(sleep 0) · 적재 = 우편함 log 에 쓰고 나서 잘림
    def __init__(self, root, delay, land=False):
        self.root, self.delay, self.land, self.calls = root, delay, land, []
    def __call__(self, argv, timeout=None, **kw):
        self.calls.append(timeout)
        if self.land:
            body = argv[-1]
            with open(os.path.join(str(self.root), ".fable-team", "comm", "mailbox.log.jsonl"), "a", encoding="utf-8") as h:
                h.write(json.dumps({"seq": 1, "to": argv[-3], "from": argv[-2], "body": body}, ensure_ascii=False) + "\n")
        if self.delay > timeout:
            raise subprocess.TimeoutExpired(argv, timeout)
        return subprocess.CompletedProcess(argv, 0)


def _wake_with(env, monkeypatch, run):
    (env / ".fable-team" / "comm").mkdir(exist_ok=True)
    (env / ".fable-team" / "comm" / "mailbox.log.jsonl").write_text('{"seq": 0, "body": "다른 쪽지"}\n', encoding="utf-8")
    hub = _load("wiring").Wiring(str(env), clock=lambda: "2026-11-13T00:00:00")
    monkeypatch.setattr(subprocess, "run", run)
    rc = hub.wake(MASTER, "[Slack] 새 업무 · thread 1 · command c1\n본문", "c1")
    monkeypatch.undo()
    return rc, [r for r in hub.entries("wake")]


def test_3_wake_8s_passes_default_25(env, monkeypatch):  # ③ 8초 지연 · 상한 기본 → rc 0
    rc, rows = _wake_with(env, monkeypatch, run := Run(env, 8))
    assert rc == 0 and run.calls == [25] and [r["rc"] for r in rows] == [0] and "why" not in rows[0]


@pytest.mark.parametrize("land, word", [(True, "있음"), (False, "없음")])
def test_4_wake_timeout_landed_verdict_no_retry(env, monkeypatch, land, word):  # ④ 적재 있음 · ④′ 적재 없음
    monkeypatch.setenv("FT2_SLACK_WAKE_TIMEOUT", "1")
    rc, rows = _wake_with(env, monkeypatch, run := Run(env, float("inf"), land))
    assert rc == -1 and run.calls == [1]  # 재시도 0 = 중복 쪽지 0
    assert [(r["rc"], r["why"]) for r in rows] == [(-1, "상한 초과 · 적재 " + word)]


def test_4c_wake_timeout_log_unreadable_undecided(env, monkeypatch):
    monkeypatch.setenv("FT2_SLACK_WAKE_TIMEOUT", "1")
    run = Run(env, float("inf"))
    hub = _load("wiring").Wiring(str(env), clock=lambda: "2026-11-13T00:00:00")
    monkeypatch.setattr(subprocess, "run", run)
    rc = hub.wake(MASTER, "[Slack] x", "c1")
    monkeypatch.undo()
    assert rc == -1 and [r["why"] for r in hub.entries("wake")] == ["상한 초과 · 적재 판정 불가"]


def test_5_single_channel_no_member_check(env):  # ⑤ 채널 1개 = 2ea518 동작 그대로(참여 확인 호출 0)
    web, notes = Web({}), []
    listener = _listener(env, A, web, [[HELLO, _msg_env("E1", _msg("1800000006.000100", A))]], notes)
    assert listener.run(sessions=1) == 0 and notes == []
    assert [c[0] for c in web.calls] == ["apps.connections.open"]
    assert listener.channel == A and listener.receive.allowed_channels == {A}


def test_5b_plist_channel_list_main_first(tmp_path):  # plist 틀 = @CHANNEL@ 1칸에 쉼표 목록(주 채널 먼저)
    text = open(PLIST, encoding="utf-8").read()
    assert "주 채널 먼저" in text
    args = plistlib.loads(text.replace("@CHANNEL@", "%s,%s" % (A, B)).encode("utf-8"))["ProgramArguments"]
    assert args[args.index("--channel") + 1] == "%s,%s" % (A, B)
