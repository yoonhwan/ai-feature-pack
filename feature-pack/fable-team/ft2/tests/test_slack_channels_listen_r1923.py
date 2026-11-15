"""r1923 Slack 듣기 목록 CHANNELS — 가입 채널 자동 발견(A hello · B 봇 가입)·공식 채널 등록/삭제·채널 owner 라우팅 시험.
반례 ①~⑰(DA 보정 R1 예산·R2 snapshot·B 종류·MPDM 포함) · 임시 root · 가짜 ws·web·깨움 · 실 Slack·launchd·우편함 0 · sleep 0."""
import importlib.util, json, os, shlex, sys, uuid  # noqa: E401
import pytest

SLACK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "adapters", "slack")
W, M, ADM, U, BOT = "TFAKE", "CMAIN", "CADM", "UOPPA", "UBOT"
MASTER, DESK, AIFP = "byz-planner-master-pi#1", "byz-planner-desk-pi#1", "aifp-ft-master-pi#13"
HELLO = {"type": "hello", "num_connections": 1}
WAKE = "import json, os, sys\nopen(os.environ['FAKE_WAKE_OUT'], 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1923_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


sock = _load("socket")


def _seed(root):  # 명부 2개 — 수신기 root 1곳
    (fable := root / ".fable-team").mkdir(parents=True)
    (fable / "seats-planner.json").write_text(json.dumps({"_master": MASTER, "_desk": DESK}), encoding="utf-8")
    (fable / "seats-issues.json").write_text(json.dumps({"_master": "byz-issues-master-sol#1"}), encoding="utf-8")
    return root


@pytest.fixture
def env(tmp_path, monkeypatch):  # 고유 하위 root — 통과 시험 tmp 폴더 이름 재사용 시 listen.log logger(경로 이름 캐시) 엇갈림 방지
    _seed(tmp_path := tmp_path / uuid.uuid4().hex[:8])
    (tmp_path / "aifp.json").write_text(json.dumps({"_master": AIFP}), encoding="utf-8")
    (tmp_path / "roots.tsv").write_text("# 명부\n", encoding="utf-8")
    (script := tmp_path / "wake.py").write_text(WAKE, encoding="utf-8")
    monkeypatch.setenv("FT2_SLACK_WAKE", "%s %s" % (sys.executable, script))
    monkeypatch.setenv("FAKE_WAKE_OUT", str(tmp_path / "wakes.jsonl"))
    monkeypatch.setenv("FT2_ROOTS_TSV", str(tmp_path / "roots.tsv"))
    return tmp_path


def _rows(root, name):
    path = os.path.join(str(root), ".fable-team", "teams", "planner", "slack", name)
    with open(path, encoding="utf-8") if os.path.exists(path) else open(os.devnull) as handle:
        return [json.loads(line) if name.endswith("jsonl") else line.rstrip("\n").split("\t") for line in handle if line.strip()]


def _wakes(root, to=None):
    path = os.path.join(str(root), "wakes.jsonl")
    rows = [json.loads(line) for line in open(path, encoding="utf-8")] if os.path.exists(path) else []
    return [row for row in rows if to is None or row[1] == to]


def _log(root):
    path = os.path.join(str(root), ".fable-team", "teams", "planner", "slack", "listen.log")
    return open(path, encoding="utf-8").read() if os.path.exists(path) else ""


def _msg(ts, channel, user=U, text=None, **extra):
    return {"type": "events_api", "envelope_id": "E" + ts, "payload": {"team_id": W, "event": dict(
        {"type": "message", "user": user, "channel": channel, "ts": ts, "text": text or "글 " + ts}, **extra)}}


def _ev(kind, channel, user=BOT):
    return {"type": "events_api", "envelope_id": "J" + kind + channel, "payload": {"event": {"type": kind, "channel": channel, "user": user}}}


class WS:
    def __init__(self, frames):
        self.frames = list(frames)
    def __enter__(self):
        return self
    def __exit__(self, *exc):
        return False
    def recv(self, timeout=None):
        return json.dumps(self.frames.pop(0) if self.frames else {"type": "disconnect"})
    def send(self, data):
        pass


class Web:  # rounds = hello 마다 쪽 목록 1벌([(ID, 이름)] 쪽들) · fail = 발견 예외 · info = 채널별 conversations.info 덧칸
    def __init__(self, *rounds, fail=None, info=None, clock=None, cost=None):  # cost = 메서드별 가짜 소요 초(clock 전진)
        self.rounds, self.fail, self.info, self.clock, self.calls, self.posts = list(rounds), fail, info or {}, clock, [], []
        self.cost, self.deadlines = cost or {}, []
    def __call__(self, method, token, params=None, retry=True, **budget):
        params = params or {}
        self.calls.append((method, params.get("channel")))
        self.deadlines.append((method, budget.get("deadline")))
        if self.clock:
            self.clock[0] += self.cost.get(method, 0)
        if method == "apps.connections.open":
            return {"ok": True, "url": "ws://fake"}
        if method == "chat.postMessage":
            self.posts.append(dict(params))
            return {"ok": True, "ts": "1800000099.%06d" % len(self.posts)}
        if method == "conversations.info":
            return {"ok": True, "channel": dict({"is_member": True, "is_channel": True, "name": "n"}, **self.info.get(params["channel"], {}))}
        if self.fail:
            raise self.fail
        pages, at = (self.rounds[0] if self.rounds else [[]]), int(params.get("cursor") or 0)
        if at + 1 >= len(pages) and self.rounds and len(self.rounds) > 1:
            self.rounds.pop(0)
        return {"ok": True, "channels": [{"id": c, "name": n} for c, n in pages[at]],
                "response_metadata": {"next_cursor": str(at + 1) if at + 1 < len(pages) else ""}}


def _li(root, web, *scripts, channel=M + "," + ADM, mono=lambda: 0.0, notes=None):
    scripts = list(scripts)
    return sock.Listener(str(root), channel=channel, app_token="xapp-F", bot_token="xoxb-F", master=MASTER, desk=DESK,
                         users=(U,), bot_users=(BOT,), web=web, connect=lambda url: WS(scripts.pop(0) if scripts else []),
                         sleep=lambda s: None, mono=mono, notify=notes.append if notes is not None else None,
                         clock=lambda: "2026-11-14T00:00:00")


def _write(root, *rows):
    path = root / ".fable-team" / "teams" / "planner" / "slack" / "CHANNELS"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join("\t".join(r) + "\n" for r in rows), encoding="utf-8")


BASE = ([M, "", "on", "main", "-"], [ADM, "", "on", "admin", "-"])


def test_1_hello_discovers_joined_and_binds_new_channel(env):  # ① + M1
    li = _li(env, Web([[(M, "dev"), ("C2", "a"), ("C9", "new")]]), [HELLO, _msg("1800000001.000100", "C9")])
    assert li.run(sessions=1) == 0 and li.receive.allowed_channels == {M, ADM, "C2", "C9"}
    assert [(b["key"][1], b["seat"]) for b in _rows(env, "bindings.jsonl")] == [("C9", DESK)]
    assert [r["key"][1] for r in _rows(env, "route.jsonl") if r["t"] == "route"] == ["C9"]
    assert "자동 채널 +C9" in _log(env) and li.receive.allowed_channels is li.chan.allowed


def test_1b_hello_budget_end_no_more_web_keeps_listening(env):  # ① R1 + M8 — 예산 끝 뒤 info 0 · 명시 행 수신 계속
    clock = [0]
    web = Web([[("C2", "a")]], clock=clock, cost={"users.conversations": 51})
    li = _li(env, web, [HELLO, _msg("1800000001.000200", M)], mono=lambda: clock[0])
    assert li.run(sessions=1) == 0 and [c for c in web.calls if c[0] == "conversations.info"] == []
    assert "판정 불가 hello 예산 끝" in _log(env)
    assert [r["state"] for r in _rows(env, "receive.jsonl")] == ["received", "dispatched"]


def test_2_3_member_joined_bot_adds_without_restart_other_user_ignored(env):  # ② ③ + M2·M3
    frames = [HELLO, _ev("member_joined_channel", "C8", user="UOTHER"), _ev("member_joined_channel", "C7"),
              _msg("1800000002.000100", "C7"), _msg("1800000002.000200", "C8")]
    li = _li(env, Web([[]]), frames)
    assert li.run(sessions=1) == 0 and "C7" in li.chan.allowed and "C8" not in li.chan.allowed
    assert _log(env).count("자동 채널 +C7") == 1
    assert [(r["key"][1], r["state"]) for r in _rows(env, "receive.jsonl")] == [
        ("C7", "received"), ("C7", "dispatched"), ("C8", "ignored")]


def test_b_mpdm_join_not_added(env):  # B 종류 경계 + M9 — MPDM 가입 = 더함 0
    li = _li(env, Web([[]], info={"G1": {"is_channel": False, "is_group": True, "is_mpim": True}}),
             [HELLO, _ev("member_joined_channel", "G1")])
    assert li.run(sessions=1) == 0 and "G1" not in li.chan.allowed and "종류 밖" in _log(env)


def test_4_13_off_row_never_allowed(env):  # ④ ⑬ + M6 — off 줄 = 발견·가입 이벤트에도 허용 0 · binding·wake 0
    _write(env, *BASE, ["C9", "x", "off", "auto", "-"])
    li = _li(env, Web([[("C9", "x")]]), [HELLO, _ev("member_joined_channel", "C9"), _msg("1800000004.000100", "C9")])
    assert li.run(sessions=1) == 0 and "C9" not in li.chan.allowed
    assert [r["state"] for r in _rows(env, "receive.jsonl")] == ["ignored"] and _rows(env, "bindings.jsonl") == []
    assert _wakes(env) == [] and _rows(env, "CHANNELS")[2] == ["C9", "x", "off", "auto", "-"]


@pytest.mark.parametrize("fail, pages", [(RuntimeError("users.conversations ratelimited"), None), (TimeoutError("7초"), None),
                                         (sock.publish.RateLimited(3), None), (None, [[("C2", "a")]] * 4)])
def test_5_discovery_fail_or_cursor_left_no_auto_change(env, fail, pages):  # ⑤ — 판정 불가 1줄 · auto 변화 0 · 수신 계속
    _write(env, *BASE, ["C3", "b", "on", "auto", "-"])
    li = _li(env, Web(pages or [[]], fail=fail), [HELLO, _msg("1800000005.000100", "C3")])
    assert li.run(sessions=1) == 0 and li.chan.allowed == {M, ADM, "C3"} and "판정 불가 자동 채널" in _log(env)
    assert [r["state"] for r in _rows(env, "receive.jsonl")] == ["received", "dispatched"]


def test_6_snapshot_replaces_auto_and_left(env):  # ⑥ R2 + M7 — 끊긴 동안 탈퇴 · channel_left
    li = _li(env, Web([[("C2", "a")]], [[("C3", "b"), ("C4", "c")]]), [HELLO],
             [HELLO, _ev("channel_left", "C4", user=None), _ev("channel_left", ADM, user=None)])
    assert li.run(sessions=2) == 0 and li.chan.allowed == {M, ADM, "C3"}
    assert "수신 불가 채널 %s" % ADM in _log(env) and [r[0] for r in _rows(env, "CHANNELS")] == [M, ADM, "C3"]


def test_1c_budget_starts_before_connections_open(env):  # DA impl R1 — 연결 전 시계 1개(합 50초) · hello 재설정 0
    clock = [0]
    web = Web([[("C2", "a")]], clock=clock, cost={"apps.connections.open": 30, "users.conversations": 25})
    li = _li(env, web, [HELLO, _msg("1800000001.000300", M)], mono=lambda: clock[0])
    assert li.run(sessions=1) == 0 and [c for c in web.calls if c[0] == "conversations.info"] == []
    assert [d for m, d in web.deadlines if m in ("apps.connections.open", "users.conversations")] == [50, 50]
    assert "판정 불가 hello 예산 끝" in _log(env) and [r["state"] for r in _rows(env, "receive.jsonl")] == ["received", "dispatched"]


def _cmd(ts, text, user=U, **extra):
    return _msg(ts, ADM, user=user, text=text, **extra)


def test_8_9_register_then_remove_by_name(env):  # ⑧ ⑨ — 재기동 0 · 답글 1씩 · router 0
    web = Web([[(M, "dev"), (ADM, "desk")]])
    li = _li(env, web, [HELLO, _cmd("1800000008.000100", "등록 <#C5|new>"), _msg("1800000008.000200", "C5"),
                        _cmd("1800000009.000100", "삭제 #new"), _msg("1800000009.000200", "C5")])
    assert li.run(sessions=1) == 0 and _rows(env, "CHANNELS")[2] == ["C5", "new", "off", "req", "-"]
    assert [(p["channel"], p["thread_ts"], p["text"]) for p in web.posts] == [
        (ADM, "1800000008.000100", "등록 C5 new · /invite @탱크 필요"), (ADM, "1800000009.000100", "삭제 C5 new")]
    assert [r["state"] for r in _rows(env, "receive.jsonl")] == ["received", "dispatched", "ignored"]
    assert {r["key"][1] for r in _rows(env, "route.jsonl")} == {"C5"}


@pytest.mark.parametrize("text, user", [("삭제 <#CMAIN>", U), ("삭제 #%s" % ADM, U), ("등록 <#C5|x>", "UOTHER"),
                                        ("등록 <#C6|x> 팀 모르는팀", U)])
def test_10_11_17_refused_or_not_command(env, text, user):  # ⑩ ⑪ ⑰ + M4·M5 — 파일 변화 0
    _write(env, *BASE)
    web = Web([[(M, "dev"), (ADM, "CADM")]])
    assert _li(env, web, [HELLO, _cmd("1800000010.000100", text, user=user)]).run(sessions=1) == 0
    assert _rows(env, "CHANNELS") == [list(r) for r in BASE]
    assert [p["text"].split(" — ")[0] for p in web.posts] == ([] if user != U else ["거절"])


def test_12_duplicate_envelope_once(env):  # ⑫ — 파일 쓰기 1 · 답글 1
    web, frame = Web([[]]), _cmd("1800000012.000100", "등록 <#C5|new> 팀 aifp-ft")
    (env / "roots.tsv").write_text("aifp\t%s\t현역\n" % env, encoding="utf-8")
    (env / ".fable-team" / "seats-aifp.json").write_text(json.dumps({"_master": AIFP}), encoding="utf-8")
    assert _li(env, web, [HELLO, frame, frame]).run(sessions=1) == 0 and len(web.posts) == 1
    assert [r["t"] for r in _rows(env, "commands.jsonl")] == ["intent", "result", "reply"]
    assert _rows(env, "CHANNELS")[2] == ["C5", "new", "on", "req", str(env) + "/.fable-team/seats-aifp.json#_master"]


def test_14_seed_once_file_wins_corrupt_undecided(env, capsys):  # ⑭
    li = _li(env, Web(), channel="C1,C2")
    assert _rows(env, "CHANNELS") == [["C1", "", "on", "main", "-"], ["C2", "", "on", "admin", "-"]]
    _li(env, Web(), channel="C9,C8")
    assert li.chan.rows == _rows(env, "CHANNELS") and "CHANNELS 있음 — --channel 무시" in _log(env)
    (env / "e.env").write_text("SLACK_APP_TOKEN=xapp-F\nSLACK_BOT_TOKEN=xoxb-F\n", encoding="utf-8")
    argv = ["--root", str(env), "--env", str(env / "e.env"), "--owner-seats", str(env / ".fable-team" / "seats-planner.json")]
    _write(env, *BASE, ["C3", "b", "on"])
    assert sock.main(argv) == 3 and "판정 불가" in capsys.readouterr().out
    os.remove(env / ".fable-team" / "teams" / "planner" / "slack" / "CHANNELS")
    assert sock.main(argv) == 3 and "CHANNELS 없음" in capsys.readouterr().out


def test_15_22_owner_roster_routes_to_other_team(env):  # ⑮ ㉒ + M10·M13 · DA impl R2 — 공백 root 도 실제 argv 1칸
    root = _seed(env / "receiver with space")
    _write(root, *BASE, ["C0X", "aifp", "on", "req", str(env / "aifp.json") + "#_master"])
    li = _li(root, Web([[]]), [HELLO, _msg("1800000015.000100", "C0X"), _msg("1800000015.000200", M)])
    assert li.run(sessions=1) == 0 and [b["seat"] for b in _rows(root, "bindings.jsonl")] == [AIFP, MASTER]
    assert len(_wakes(env, AIFP)) == 1 and _wakes(env, DESK) == [] and "답글:" not in _wakes(env, MASTER)[0][-1]
    argv = shlex.split(_wakes(env, AIFP)[0][-1].splitlines()[-1])
    assert argv[:6] == ["답글:", "ft2", "slack", "reply", "--root", str(root)] and argv[6:10] == [
        "--team", "planner", "--thread", "1800000015.000100"] and argv[11].startswith("slack:")
    assert argv[10] == "--command" and argv[12:] == ["--seat", AIFP, "--body-file", "<파일>"]


def test_16_owner_roster_unreadable_no_bind_desk_alert(env):  # ⑯ — 묶기 0 · 판정 불가 1 · desk 알림 1 · planner 대체 0
    _write(env, *BASE, ["C0X", "aifp", "on", "req", str(env / "없음.json") + "#_master"])
    assert _li(env, Web([[]]), [HELLO, _msg("1800000016.000100", "C0X")]).run(sessions=1) == 0
    assert _rows(env, "bindings.jsonl") == [] and _log(env).count("판정 불가 채널 주인 C0X") == 1
    assert len(_wakes(env, DESK)) == 1 and _wakes(env, MASTER) == []
