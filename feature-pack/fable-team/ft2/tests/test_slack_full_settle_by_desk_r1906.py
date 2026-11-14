"""r1906 desk 가 thread 밖으로 처리한 full 글 = settle 요청 1줄 → listen(recover·handle)이 settled 1줄 · 넣기 0 · 깨움 0.
반례 ①~⑧ · 변이 M1(최신 상태 검사)·M2(recover 읽기)·M3(handle 읽기). 임시 root · 실 Intake · 실 Slack·실 원장·sleep 0."""
import builtins, importlib.util, json, os, subprocess, sys  # noqa: E401

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLACK = os.path.join(FT2, "adapters", "slack")
T, C, U, DESK = "TFAKE", "CFAKE", "U", "byz-planner-desk-pi#1"
def _load(name):
    spec = importlib.util.spec_from_file_location("r1906_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module
receive, wiring, binding = _load("receive"), _load("wiring"), _load("binding")
TS = ["17945630%02d.000001" % i for i in range(9)]
cmd = lambda n: "slack:%s:%s:%s" % (T, C, TS[n])  # noqa: E731
msg = lambda n: {"type": "message", "team": T, "channel": C, "user": U, "ts": TS[n], "text": "글 %d" % n}  # noqa: E731
lines = lambda r: len(r.entries())  # noqa: E731

def rx(root, capacity, acks=None, submits=None):
    client = receive.intake.Intake(str(root), "planner", capacity=capacity)
    if submits is not None:
        client.submit = (lambda real: lambda *a, **kw: submits.append(a[0]) or real(*a, **kw))(client.submit)
    return receive.SlackReceive(str(root), ack=lambda e: acks is not None and acks.append(e), client=client, team="planner",
                                allowed_users=(U,), allowed_channels=(C,), notify=lambda row: None)

def world(root, idx, capacity=0):   # 글 idx 를 capacity 로 받음(0 = full) → (재기동 수신기, 제출 기록)
    first = rx(root, capacity)
    for n in idx:
        first.handle(msg(n))
    submits = []
    return rx(root, 8, submits=submits), submits

def settle(root, n, why="ⓑ 집행", command=None):
    argv = ["settle", "--root", str(root), "--team", "planner", "--command", command or cmd(n), "--by", DESK, "--why", why]
    return receive.main(argv)

def ask(root, n):   # 경합 꼴 — CLI 판정과 무관하게 요청 줄이 이미 있음
    with open(os.path.join(str(root), ".fable-team", "teams", "planner", "slack", "settle.jsonl"), "a") as fh:
        fh.write(json.dumps({"command": cmd(n), "by": DESK, "why": "경합", "at": "-"}) + "\n")

def test_c1_settle_request_then_recover_settled_no_submit_and_list(tmp_path, capsys):
    again, submits = world(tmp_path, [1])
    before = lines(again)
    out = subprocess.run([sys.executable, os.path.join(SLACK, "receive.py"), "settle", "--root", str(tmp_path), "--team",
                          "planner", "--command", cmd(1), "--by", DESK, "--why", "ⓑ 집행"], capture_output=True, text=True)
    assert (out.returncode, out.stdout.strip()) == (0, "SETTLE-REQUESTED " + cmd(1)) and lines(again) == before
    assert receive.main(["--list-full", "--root", str(tmp_path), "--team", "planner"]) == 0
    assert capsys.readouterr().out.strip() == "%s %s 글 1 요청됨" % (cmd(1), TS[1])
    assert again.recover() == [] and submits == []
    row = again.latest()[cmd(1)]
    assert row["state"] == "settled" and row["reason"] == "처리 기록 %s · ⓑ 집행" % DESK and lines(again) == before + 1

def test_c2_twice_one_settled_line(tmp_path):
    again, _ = world(tmp_path, [1])
    assert settle(tmp_path, 1) == 0 and settle(tmp_path, 1) == 0
    again.recover()
    after = lines(again)
    again.recover()
    assert lines(again) == after and [r["state"] for r in again.entries()].count("settled") == 1

def test_c3_dispatched_noop_and_no_overwrite(tmp_path, capsys):
    again, _ = world(tmp_path, [1], capacity=8)
    assert settle(tmp_path, 1) == 0 and capsys.readouterr().out.strip() == "NOOP %s dispatched" % cmd(1)
    assert not os.path.exists(os.path.join(again.root, ".fable-team", "teams", "planner", "slack", "settle.jsonl"))
    ask(tmp_path, 1)
    before = lines(again)
    again.recover()
    assert lines(again) == before and again.latest()[cmd(1)]["state"] == "dispatched"

def test_c4_reject_unknown_and_bad_form(tmp_path, capsys):
    world(tmp_path, [1])
    assert settle(tmp_path, 2) == 2 and settle(tmp_path, 0, command="slack:x") == 2
    assert [ln.split()[0] for ln in capsys.readouterr().out.splitlines()] == ["REJECT", "REJECT"]
    assert not os.path.exists(os.path.join(str(tmp_path), ".fable-team", "teams", "planner", "slack", "settle.jsonl"))

def test_c5_write_fail_rc3_and_read_fail_keeps_full(tmp_path, capsys, monkeypatch):
    again, submits = world(tmp_path, [1])
    real_open, real_read = os.open, builtins.open
    monkeypatch.setattr(receive.os, "open", lambda p, *a: (_ for _ in ()).throw(PermissionError(p)) if
                        str(p).endswith("settle.jsonl") else real_open(p, *a))
    assert settle(tmp_path, 1) == 3 and capsys.readouterr().out.startswith("판정 불가 slack settle " + cmd(1))
    monkeypatch.undo()
    ask(tmp_path, 1)
    monkeypatch.setattr(receive, "open", lambda p, *a, **kw: (_ for _ in ()).throw(PermissionError(p)) if
                        str(p).endswith("settle.jsonl") else real_read(p, *a, **kw), raising=False)
    logs, before = [], lines(again)
    again.log = logs.append
    again.recover()
    assert submits == [] and again.latest()[cmd(1)]["state"] == "full" and lines(again) == before
    assert len([ln for ln in logs if "판정 불가" in ln]) == 1

def test_c6_no_request_resubmitted_c7_race_after_dispatch(tmp_path):
    again, submits = world(tmp_path, [1])
    again.recover()
    assert submits == [cmd(1)] and again.latest()[cmd(1)]["state"] == "dispatched"
    ask(tmp_path, 1)
    before = lines(again)
    again.recover()
    assert lines(again) == before and again.latest()[cmd(1)]["state"] == "dispatched"

def test_c8_handle_redelivery_one_ack_no_wiring(tmp_path, monkeypatch):
    wakes, acks, submits = [], [], []
    monkeypatch.setattr(wiring.Wiring, "wake", lambda self, to, body, command: wakes.append(to) or 0)
    first = rx(tmp_path, 0, acks, submits)
    router, _ = wiring.wire(str(tmp_path), receive=first, bindings=binding.ThreadBinding(str(tmp_path), team="planner"))
    assert router.route(msg(1))["state"] == "full" and router.route(msg(2))["state"] == "full"
    ask(tmp_path, 1)
    acks.clear(), submits.clear(), wakes.clear()
    assert router.route(msg(1))["state"] == "settled"
    assert (len(acks), submits, wakes) == (1, [], []) and first.latest()[cmd(1)]["state"] == "settled"
    real_read = builtins.open
    monkeypatch.setattr(receive, "open", lambda p, *a, **kw: (_ for _ in ()).throw(PermissionError(p)) if
                        str(p).endswith("settle.jsonl") else real_read(p, *a, **kw), raising=False)
    assert router.route(msg(2))["state"] == "full" and first.latest()[cmd(2)]["state"] == "full"
    assert (len(acks), submits, wakes) == (2, [], [])
    assert not [r for r in router.entries("note")] and "dispatched" not in [r.get("state") for r in router.entries("route")]
