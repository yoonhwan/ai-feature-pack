"""r1806 ft2 Slack Socket 상주 수신기 시험 — 사례 ①~⑨(③′·③″) · 대역 ws 127.0.0.1 임의 포트 · 대역 Web API 주입.
실 Slack·자격·LaunchAgents 0 · sleep 0(재연결 간격 = 주입 sleep 기록 · 유휴 = 주입 시계) · 기준판에서 ①③ Red."""
import importlib.util, json, os, plistlib, re, subprocess, sys, threading  # noqa: E401
import pytest
from websockets.sync.server import serve

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCKET = os.path.join(FT2, "adapters", "slack", "socket.py")
PLIST = os.path.join(FT2, "adapters", "slack", "launchd", "com.byz.ft2-slack-listen.plist.in")
CLI = os.path.join(FT2, "core", "cli.py")
W, C, U, BOT, MASTER = "TFAKE", "CFAKE", "UOPPA", "UBOT", "byz-planner-master-pi#1"
TOKENS = re.compile(r"xapp-|xoxb-")
HELLO = {"type": "hello", "num_connections": 1}

def _sock():
    spec = importlib.util.spec_from_file_location("ft2_slack_socket_t", SOCKET)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # 기준판 = 파일 없음 → Red
    return module

def _rows(root, name):
    path = os.path.join(str(root), ".fable-team", "teams", "planner", "slack", name)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]

def _env(eid, event, kind="events_api"):
    return {"type": kind, "envelope_id": eid, "payload": {"team_id": W, "event": event}}

def _msg(ts, **extra):
    return dict({"type": "message", "user": U, "channel": C, "ts": ts, "text": "새 업무 " + ts}, **extra)

_command = "slack:%s:%s:%%s" % (W, C)

class Band:
    """대역 = ws 서버(연결마다 대본 1개) + Web API(호출 계수). 확인이 오는 순간 receive.jsonl 상태를 찍는다."""
    def __init__(self, root, scripts):
        self.root, self.scripts, self.acks, self.calls, self.posts, self.sleeps = root, list(scripts), [], [], [], []
        self.replies = []  # 보충 대역 응답(conversations.replies)
        self.server = serve(self._handler, "127.0.0.1", 0)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = "ws://127.0.0.1:%d" % self.server.socket.getsockname()[1]
    def _handler(self, ws):
        for frame in (self.scripts.pop(0) if self.scripts else []):
            ws.send(json.dumps(frame))
            if frame.get("envelope_id"):
                ack = json.loads(ws.recv(timeout=10))
                self.acks.append((ack["envelope_id"], [r["state"] for r in _rows(self.root, "receive.jsonl")]))
    def web(self, method, token, params=None, retry=True, **budget):  # r1923 연결 deadline 인자
        self.calls.append(method)
        if method == "apps.connections.open":
            return {"ok": True, "url": self.url}
        if method == "chat.postMessage":
            self.posts.append(dict(params))
            return {"ok": True, "ts": "1800000099.%06d" % len(self.posts)}
        return {"ok": True, "messages": self.replies, "has_more": False}

@pytest.fixture
def band_of():
    bands = []
    def make(root, scripts):
        bands.append(Band(str(root), scripts))
        return bands[-1]
    yield make
    for band in bands:
        band.server.shutdown()

def _listener(sock, root, band, **extra):
    return sock.Listener(str(root), channel=C, app_token="xapp-FAKE", bot_token="xoxb-FAKE", master=MASTER,
                         users=(U,), bot_users=(BOT,), web=band.web, sleep=band.sleeps.append,
                         mono=extra.pop("mono", lambda: 0.0), clock=lambda: "2026-11-13T00:00:00", **extra)

def test_1_credentials_undecidable_without_values(tmp_path):
    (seats := tmp_path / "seats.json").write_text(json.dumps({"_master": MASTER}), encoding="utf-8")
    (only_bot := tmp_path / "only-bot.env").write_text("SLACK_BOT_TOKEN=xoxb-SECRET-1\nSLACK_BOT_USER_ID=UBOT\n", encoding="utf-8")
    for env in (tmp_path / "none.env", only_bot):
        out = subprocess.run([sys.executable, CLI, "slack", "listen", "--root", str(tmp_path), "--team", "planner",
                              "--channel", C, "--env", str(env), "--owner-seats", str(seats)],
                             capture_output=True, text=True, timeout=20)
        assert out.returncode == 3 and "판정 불가" in out.stdout, (out.returncode, out.stdout)
        assert not TOKENS.search(out.stdout + out.stderr)

def test_2_rival_consumer_rc4(tmp_path, band_of):
    band, notes = band_of(tmp_path, [[dict(HELLO, num_connections=2)]]), []
    assert _listener(_sock(), tmp_path, band, notify=notes.append).run(sessions=1) == 4
    assert len(notes) == 1 and _rows(tmp_path, "receive.jsonl") == []

def test_3_new_root_bind_receipt_then_role_reply(tmp_path, band_of):
    sock, ts = _sock(), "1800000001.000100"
    band = band_of(tmp_path, [[HELLO, _env("E1", _msg(ts))]])
    assert (listener := _listener(sock, tmp_path, band)).run(sessions=1) == 0
    assert [(b["state"], b["seat"], b["gen"]) for b in _rows(tmp_path, "bindings.jsonl")] == [("bound", MASTER, 1)]
    assert band.acks == [("E1", ["received"])]  # 기록 → 확인 → 입구
    assert [r["state"] for r in _rows(tmp_path, "receive.jsonl")] == ["received", "dispatched"]
    assert listener.receive.client.lookup(_command % ts).result == "접수 성공"
    assert _rows(tmp_path, "publish.jsonl") == [] and band.posts == []  # r1818 접수 = 장부만 · 게시 0
    key = sock.binding.thread_key(W, C, ts)  # ③″ 접수 뒤 같은 key·업무 command 역할 답 = posted(첫 반응)
    assert listener.publish.reply(key, _command % ts, "역할 답", seat=MASTER, gen=1)["state"] == "posted"
    assert [(p["thread_ts"], p["text"]) for p in band.posts] == [(ts, "역할 답")]

def test_3b_closed_thread_no_bind_no_receipt(tmp_path, band_of):
    sock, ts = _sock(), "1800000002.000100"
    key = sock.binding.thread_key(W, C, ts)
    ledger = sock.binding.ThreadBinding(str(tmp_path), "planner")
    ledger.bind(key, MASTER), ledger.close(key)
    band = band_of(tmp_path, [[HELLO, _env("E2", _msg(ts))]])
    _listener(sock, tmp_path, band).run(sessions=1)
    assert [b["state"] for b in _rows(tmp_path, "bindings.jsonl")] == ["bound", "closed"]
    assert band.posts == [] and _rows(tmp_path, "publish.jsonl") == []
    assert [r["kind"] for r in _rows(tmp_path, "route.jsonl") if r["t"] == "route"] == ["재개 필요"]

def test_4_redelivery_duplicate_no_publish(tmp_path, band_of):
    ts = "1800000003.000100"
    band = band_of(tmp_path, [[HELLO, _env("E3", _msg(ts)), _env("E4", _msg(ts))]])
    (listener := _listener(_sock(), tmp_path, band)).run(sessions=1)
    assert [a[0] for a in band.acks] == ["E3", "E4"]
    assert [r["state"] for r in _rows(tmp_path, "receive.jsonl")] == ["received", "dispatched", "duplicate"]
    assert _rows(tmp_path, "publish.jsonl") == [] and band.posts == []  # r1818 접수 게시 0
    assert len(_rows(tmp_path, "bindings.jsonl")) == 1
    assert listener.receive.client.lookup(_command % ts).attempt == _command % ts + "#a1"

def test_5_bot_foreign_slash_ack_only(tmp_path, band_of):
    band = band_of(tmp_path, [[HELLO, _env("E5", _msg("1800000004.000100", bot_id="B1", user=BOT)),
                               _env("E6", _msg("1800000005.000100", channel="COTHER")),
                               {"type": "slash_commands", "envelope_id": "E7", "payload": {"command": "/x"}}]])
    (listener := _listener(_sock(), tmp_path, band)).run(sessions=1)
    assert [a[0] for a in band.acks] == ["E5", "E6", "E7"]
    assert [r["state"] for r in _rows(tmp_path, "receive.jsonl")] == ["ignored", "ignored"]
    assert band.posts == [] and _rows(tmp_path, "bindings.jsonl") == [] and listener.receive.client.records() == []
    log = os.path.join(str(tmp_path), ".fable-team", "teams", "planner", "slack", "listen.log")
    assert "버림 slash_commands" in open(log, encoding="utf-8").read()

def test_6_disconnect_reconnect_backfill_once(tmp_path, band_of):
    sock, root_ts = _sock(), "1800000006.000100"
    sock.binding.ThreadBinding(str(tmp_path), "planner").bind(sock.binding.thread_key(W, C, root_ts), MASTER)
    band = band_of(tmp_path, [[HELLO, {"type": "disconnect", "reason": "refresh_requested"}], [HELLO]])
    band.replies = [_msg("1800000006.000200", thread_ts=root_ts)]  # 끊긴 사이 새 사람 답글 1
    assert _listener(sock, tmp_path, band).run(sessions=2) == 0
    assert [r["reason"] for r in _rows(tmp_path, "backfill.jsonl")] == ["reconnect"]
    assert [c for c in band.calls if c != "users.conversations"] == [  # r1923 hello 발견 호출 허용
        "apps.connections.open", "apps.connections.open", "conversations.replies"]
    assert band.sleeps == [1] and band.posts == []  # 보충 dispatched → 접수 게시 0(r1818)
    assert [r["command"] for r in _rows(tmp_path, "receive.jsonl") if r["state"] == "dispatched"] == [
        _command % "1800000006.000200"]

def test_6b_failed_connects_wait_1_then_2(tmp_path, band_of):
    (listener := _listener(_sock(), tmp_path, band := band_of(tmp_path, []))).web = lambda method, *rest, **kw: (
        band.calls.append(method), (_ for _ in ()).throw(OSError("대역 연결 실패")))
    assert listener.run(sessions=3) == 0 and band.sleeps == [1, 2] and len(band.calls) == 3  # R2 계약 1·2·4…

def test_7_idle_61s_no_reads_no_model(tmp_path, band_of):
    now, band = [0.0], band_of(tmp_path, [])
    listener = _listener(_sock(), tmp_path, band, mono=lambda: now[0])
    for _ in range(61):  # sleep 0 — 주입 시계만 1초씩 민다
        now[0] += 1.0
        listener.on_idle()
    assert band.calls == [] and _rows(tmp_path, "receive.jsonl") == []
    assert not re.search(r"^\s*(import|from)\s+(anthropic|openai|litellm|claude_agent_sdk|google)",
                         open(SOCKET, encoding="utf-8").read(), re.M)

def test_8_restart_recover_lookup_first(tmp_path, band_of):
    sock, ts = _sock(), "1800000007.000100"
    sock.binding.ThreadBinding(str(tmp_path), "planner").bind(sock.binding.thread_key(W, C, ts), MASTER)
    sock.receive.intake.Intake(str(tmp_path), "planner").submit(_command % ts, "x", {})
    path = os.path.join(str(tmp_path), ".fable-team", "teams", "planner", "slack", "receive.jsonl")
    with open(path, "w", encoding="utf-8") as handle:  # 입구 영수까지 갔고 판정 줄 전에 죽은 꼴
        handle.write(json.dumps({"state": "received", "command": _command % ts, "key": [W, C, ts], "attempts": 1,
                                 "user": U, "text": "x", "acked": True}) + "\n")
    _listener(sock, tmp_path, band := band_of(tmp_path, [[HELLO]])).run(sessions=1)
    assert [(r["state"], r.get("via")) for r in _rows(tmp_path, "receive.jsonl")] == [
        ("received", None), ("dispatched", "lookup")]
    assert sock.receive.intake.Intake(str(tmp_path), "planner").lookup(_command % ts).attempt == _command % ts + "#a1"
    assert band.posts == []  # 복구 dispatched → 접수 게시 0(r1818 · 장부만)

def test_9_plist_template(tmp_path):
    home = tmp_path / "ft2"
    (home / "versions" / "9.9.9" / "core").mkdir(parents=True), (home / "CURRENT").write_text("9.9.9\n")
    (home / "versions" / "9.9.9" / "core" / "cli.py").write_text(
        "import json, sys\nprint(json.dumps(sys.argv[1:]))\n", encoding="utf-8")
    text = open(PLIST, encoding="utf-8").read()
    for name, value in {"@FT2_HOME@": str(home), "@ROOT@": str(tmp_path), "@ENV_FILE@": str(tmp_path / "x.env"),
                        "@OWNER_SEATS@": str(tmp_path / "seats.json"), "@USERS@": U, "@CHANNEL@": C}.items():
        text = text.replace(name, value)
    (out := tmp_path / "com.byz.ft2-slack-listen.plist").write_text(text, encoding="utf-8")
    assert subprocess.run(["plutil", "-lint", str(out)], capture_output=True).returncode == 0
    args = (data := plistlib.loads(text.encode("utf-8")))["ProgramArguments"]
    assert data["Label"] == "com.byz.ft2-slack-listen" and data["KeepAlive"] is True and os.path.isabs(args[0])
    assert not TOKENS.search(text) and "@" not in "".join(args)
    assert data["StandardOutPath"] == str(tmp_path) + "/.fable-team/teams/planner/slack/listen.log"
    ran = subprocess.run([sys.executable] + args[1:], capture_output=True, text=True, timeout=20)
    assert json.loads(ran.stdout)[:4] == ["slack", "listen", "--root", str(tmp_path)]  # CURRENT 버전 cli

def test_listen_log_rotation_cap(tmp_path, monkeypatch):
    monkeypatch.setattr(sock := _sock(), "SEG", 200), monkeypatch.setattr(sock, "TOTAL", 600)
    log = sock.listen_log(str(tmp_path))
    for index in range(80):
        log("줄 %03d" % index)
    sizes = [os.path.getsize(tmp_path / name) for name in os.listdir(tmp_path) if name.startswith("listen.log")]
    assert len(sizes) > 1 and max(sizes) <= 200 and sum(sizes) <= 600
