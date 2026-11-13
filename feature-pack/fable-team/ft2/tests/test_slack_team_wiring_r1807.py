"""r1807 ft2 Slack 팀 도구 배선 시험 — 사례 ①~⑪(⑤′ 포함) · 보정1 ⑫(R1 허용 밖 채널) ⑬(R2 ack 직후 crash 복구) · 임시 root · 가짜 명부·깨움(FT2_SLACK_WAKE)·post.
실 우편함·실 Slack·실 명부 0 · sleep 0 · 기준판(wiring 없음)에서 ①⑦⑩ Red."""
import importlib.util, json, os, subprocess, sys  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLACK, CLI = os.path.join(FT2, "adapters", "slack"), os.path.join(FT2, "core", "cli.py")
W, C, U = "TFAKE", "CFAKE", "UOPPA"
MASTER, DESK, ISSUES = "byz-planner-master-pi#1", "byz-planner-desk-pi#1", "byz-issues-master-sol#1"
WAKE = ("import json, os, sys\nopen(os.environ['FAKE_WAKE_OUT'], 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n"
        "sys.exit(1 if os.environ.get('FAKE_WAKE_FAIL') == sys.argv[2] else 0)\n")
cmd = lambda ts: "slack:%s:%s:%s" % (W, C, ts)  # noqa: E731


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1807_" + name, os.path.join(SLACK, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _rows(root, name):
    path = os.path.join(str(root), ".fable-team", "teams", "planner", "slack", name)
    with open(path, encoding="utf-8") if os.path.exists(path) else open(os.devnull) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def _msg(ts, **extra):
    return dict({"type": "message", "user": U, "channel": C, "ts": ts, "team": W, "text": "글 " + ts}, **extra)


@pytest.fixture
def env(tmp_path, monkeypatch):
    (fable := tmp_path / ".fable-team").mkdir()
    (fable / "seats-planner.json").write_text(json.dumps({"_master": MASTER, "_desk": DESK}), encoding="utf-8")
    (fable / "seats-issues.json").write_text(json.dumps({"_master": ISSUES}), encoding="utf-8")
    (script := tmp_path / "wake.py").write_text(WAKE, encoding="utf-8")
    monkeypatch.setenv("FT2_SLACK_WAKE", "%s %s" % (sys.executable, script))
    monkeypatch.setenv("FAKE_WAKE_OUT", str(tmp_path / "wakes.jsonl"))
    monkeypatch.delenv("FAKE_WAKE_FAIL", raising=False)
    return tmp_path


def _wakes(root, to=None):
    path = os.path.join(str(root), "wakes.jsonl")
    rows = [json.loads(line) for line in open(path, encoding="utf-8")] if os.path.exists(path) else []
    return [row for row in rows if to is None or row[1] == to]


def _listener(root, posts):
    def web(method, token, params=None, retry=True):
        posts.append(dict(params or {}))
        return {"ok": True, "ts": "1800000099.%06d" % len(posts)}
    return _load("socket").Listener(str(root), channel=C, app_token="xapp-FAKE", bot_token="xoxb-FAKE",
                                    master=MASTER, users=(U,), web=web, sleep=lambda s: None,
                                    clock=lambda: "2026-11-13T00:00:00")


class Post:
    def __init__(self, fail=None):
        self.calls, self.fail = [], fail
    def __call__(self, channel, thread_ts, text, metadata):
        self.calls.append({"channel": channel, "thread_ts": thread_ts, "text": text, "metadata": metadata})
        if self.fail:
            raise self.fail
        return "1800000088.%06d" % len(self.calls)

def _cmd(root, verb, body="답", **opts):
    (path := root / ("body-%d.txt" % len(os.listdir(root)))).write_text(body, encoding="utf-8")
    argv = [verb, "--root", str(root), "--team", "planner", "--body-file", str(path)]
    return argv + [item for name, value in opts.items() for item in ("--" + name, value)]


def _run(capsys, argv, post, wiring=None):
    rc = (wiring or _load("wiring")).main(argv, post=post, sleep=lambda s: None)
    return rc, capsys.readouterr().out.strip()


def _bound(root, *roots):
    ledger, binding = _load("binding").ThreadBinding(str(root), "planner"), _load("binding")
    keys = [binding.thread_key(W, C, ts) for ts in roots]
    for key in keys:
        ledger.bind(key, MASTER)
    return ledger, keys


def test_1_new_root_wakes_planner(env):
    ts = "1800000001.000100"
    _listener(env, []).route(_msg(ts))
    wakes = _wakes(env, MASTER)
    assert len(wakes) == 1 and wakes[0][0] == "send" and wakes[0][2] == "ft2-slack-listen"
    assert wakes[0][3].splitlines()[0] == "[Slack] 새 업무 · thread %s · command %s" % (ts, cmd(ts))


def test_2_wake_body_is_recent_context_only(env):
    root_a, root_b, listener = "1800000002.000100", "1800000002.000900", _listener(env, [])
    listener.route(_msg(root_a))
    listener.route(_msg(root_b)), listener.route(_msg("1800000002.000901", thread_ts=root_b))
    replies = ["1800000002.%06d" % (200 + i) for i in range(5)]
    for ts in replies:
        listener.route(_msg(ts, thread_ts=root_a))
    body = [w for w in _wakes(env, MASTER) if "thread " + root_a in w[3].splitlines()[0]][-1][3].splitlines()
    assert len(body) == 5 and [line.split()[0] for line in body[1:]] == replies[1:]
    assert root_a not in "\n".join(body[1:]) and replies[0] not in "\n".join(body) and root_b not in "\n".join(body)
    assert len(_rows(env, "bindings.jsonl")) == 2  # 답글은 bind 새 행 0


def test_3_closed_thread_alerts_desk_only(env):
    ts = "1800000003.000100"
    ledger, (key,) = _bound(env, ts)
    ledger.close(key)
    _listener(env, []).route(_msg(ts))
    assert len(_wakes(env, DESK)) == 1 and _wakes(env, MASTER) == []


def test_4_redelivery_no_wake_no_issues_no_post(env):
    ts, posts = "1800000004.000100", []
    listener = _listener(env, posts)
    listener.route(_msg(ts)), listener.route(_msg(ts))
    assert len(_wakes(env, MASTER)) == 1 and posts == []  # r1818 접수 게시 0
    assert len(_load("receive").intake.Intake(str(env), "issues").records()) == 1


def test_5_issues_same_command_record_only(env):
    ts = "1800000005.000100"
    listener = _listener(env, [])
    listener.route(_msg(ts))
    issues = _load("receive").intake.Intake(str(env), "issues")
    assert issues.lookup(cmd(ts)).result == "접수 성공" and _wakes(env, ISSUES) == []
    key = _load("binding").thread_key(W, C, ts)  # ⑤′ 같은 command 재전달
    listener.router.deliver(MASTER, "새 업무", listener.router.context(key))
    assert [r["command"] for r in issues.records()] == [cmd(ts)] and issues.lookup(cmd(ts)).attempt == cmd(ts) + "#a1"


def test_6_wake_failure_recorded_and_desk_alerted(env, monkeypatch):
    monkeypatch.setenv("FAKE_WAKE_FAIL", MASTER)
    ts = "1800000006.000100"
    _listener(env, []).route(_msg(ts))
    assert [r["state"] for r in _rows(env, "route.jsonl") if r["t"] == "route"] == ["dispatched"]
    assert [(r["to"], r["rc"]) for r in _rows(env, "wire.jsonl") if r["t"] == "wake" and r["rc"] != 0] == [(MASTER, 1)]
    assert len(_wakes(env, DESK)) == 1


def test_7_reply_after_receipt_then_duplicate_then_receipt_refused(env, capsys):
    ts, posts, post = "1800000007.000100", [], Post()
    _listener(env, posts).route(_msg(ts))
    assert posts == []  # r1818 — S-1 접수 게시 0(장부만)
    rc, out = _run(capsys, _cmd(env, "reply", thread=ts, command=cmd(ts), seat=MASTER), post)
    assert (rc, out) == (0, "state=posted ts=1800000088.000001") and post.calls[0]["thread_ts"] == ts
    assert post.calls[0]["channel"] == C and post.calls[0]["text"] == "답\n\n보낸이 planner-master"  # r1818 사람 글 + r1850 보낸이 줄
    assert post.calls[0]["metadata"]["event_payload"]["command"] == cmd(ts)
    rc, out = _run(capsys, _cmd(env, "reply", thread=ts, command=cmd(ts), seat=MASTER), post)
    assert (rc, out) == (0, "state=duplicate ts=1800000088.000001") and len(post.calls) == 1
    rc, _out = _run(capsys, _cmd(env, "reply", thread=ts, command="receipt:" + cmd(ts), seat=MASTER), post)
    assert rc == 2 and len(post.calls) == 1
    ran = subprocess.run([sys.executable, CLI, "slack"] + _cmd(env, "reply", thread=ts, command="receipt:x",
                                                                seat=MASTER), capture_output=True, text=True, timeout=20)
    assert ran.returncode == 2 and len(post.calls) == 1


def test_8_reply_not_owner_or_old_seat_refused(env, capsys):
    ts, post = "1800000008.000100", Post()
    ledger, (key,) = _bound(env, ts)
    rc, out = _run(capsys, _cmd(env, "reply", thread=ts, command=cmd(ts), seat="someone"), post)
    assert rc == 2 and out.startswith("state=refused") and post.calls == []
    ledger.handover(key, "seat-b")
    rc, out = _run(capsys, _cmd(env, "reply", thread=ts, command=cmd(ts), seat=MASTER), post)
    assert rc == 2 and out.startswith("state=refused") and post.calls == []


def test_9_reply_429_twice_visible_failure(env, capsys):
    ts, wiring = "1800000009.000100", _load("wiring")
    _bound(env, ts)
    post = Post(fail=wiring.publish.RateLimited(1))
    rc, out = _run(capsys, _cmd(env, "reply", thread=ts, command=cmd(ts), seat=MASTER), post, wiring)
    assert rc == 1 and out.startswith("state=failed") and len(post.calls) == 2


def test_10_notify_named_thread_only_and_body_intent(env, capsys):
    one, two, post, listener = "1800000010.000100", "1800000010.000200", Post(), _listener(env, [])
    listener.route(_msg(one)), listener.route(_msg(two))  # 수신 채널 root = S-1 이 받아 묶은 thread
    assert _run(capsys, _cmd(env, "notify", "알림 가", thread=one, seat=DESK), post)[0] == 0
    assert [c["thread_ts"] for c in post.calls] == [one]
    rc, out = _run(capsys, _cmd(env, "notify", "알림 가", thread=one, seat=DESK), post)
    assert rc == 0 and out.startswith("state=duplicate") and len(post.calls) == 1
    rc, out = _run(capsys, _cmd(env, "notify", "알림 나", thread=one, seat=DESK), post)
    assert (rc, out.split()[0]) == (0, "state=posted") and [c["thread_ts"] for c in post.calls] == [one, one]


def test_11_notify_needs_open_named_thread(env, capsys):
    closed, post = "1800000011.000100", Post()
    ledger, (key,) = _bound(env, closed)
    ledger.close(key)
    assert _run(capsys, _cmd(env, "notify", seat=DESK), post)[0] == 2
    ran = subprocess.run([sys.executable, CLI, "slack"] + _cmd(env, "notify", seat=DESK),
                         capture_output=True, text=True, timeout=20)
    assert ran.returncode == 2
    for thread in ("1800000011.000999", closed):
        rc, out = _run(capsys, _cmd(env, "notify", thread=thread, seat=DESK), post)
        assert rc == 2 and out.startswith("state=refused")
    assert post.calls == []


def test_12_notify_refuses_foreign_channel_binding(env, capsys):  # 보정1 R1 — 수신 채널 thread 만
    ts, post, binding = "1800000012.000100", Post(), _load("binding")
    binding.ThreadBinding(str(env), "planner").bind(binding.thread_key(W, "COTHER", ts), MASTER)
    rc, out = _run(capsys, _cmd(env, "notify", thread=ts, seat=DESK), post)
    assert rc == 2 and out.startswith("state=refused") and post.calls == []


def test_13_crash_after_ack_recover_wakes_once(env):  # 보정1 R2 — 복구 dispatched 도 깨움·issues 1 · 재기동 중복 0
    ts, posts = "1800000013.000100", []
    first = _listener(env, posts)
    def crash(step):
        if step == "ack":
            raise RuntimeError("ack 직후 crash")
    first.receive.on_step = crash
    with pytest.raises(RuntimeError):
        first.route(_msg(ts))
    for _ in range(2):  # 재기동 2번 — 두 번째는 깨움·attempt·게시 0
        _listener(env, posts).run(sessions=0)
    intake = _load("receive").intake.Intake
    assert len(_wakes(env, MASTER)) == 1 and posts == []  # r1818 접수 게시 0
    assert [r["command"] for r in intake(str(env), "issues").records()] == [cmd(ts)]
    assert intake(str(env), "planner").lookup(cmd(ts)).attempt == cmd(ts) + "#a1"
