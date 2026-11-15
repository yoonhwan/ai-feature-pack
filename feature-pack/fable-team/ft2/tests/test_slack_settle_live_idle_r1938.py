"""r1938 listen 기동 뒤 settle 요청 = 다음 idle 1회 안 settled · settle 무변화 idle = 읽기·쓰기 0 · 칸 0 이어도 요청 full = settled.
반례 ①깨짐 ②같은 요청 두 번 ③dispatched 요청 · 변이 M1~M3. 임시 root · 실 Intake · 실 Slack·실 원장 0 · sleep 0."""
import importlib.util, json, os, shutil  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T, C, U, DESK = "TFAKE", "CFAKE", "U", "byz-planner-desk-pi#1"
RX, RD = "adapters/slack/receive.py", "adapters/slack/reply_done.py"
cmd = lambda n: "slack:%s:%s:17946240%02d.000001" % (T, C, n)  # noqa: E731
msg = lambda n: {"type": "message", "team": T, "channel": C, "user": U, "ts": cmd(n).rsplit(":", 1)[1], "text": "글"}  # noqa: E731

def _mods(base=FT2, tag="base"):
    out = {}
    for name, rel in (("receive", RX), ("reply_done", RD)):
        spec = importlib.util.spec_from_file_location("r1938_%s_%s" % (tag, name), os.path.join(base, rel))
        spec.loader.exec_module(out.setdefault(name, importlib.util.module_from_spec(spec)))
    return type("M", (), out)

M = _mods()

def rx(m, root, capacity, logs=None):
    return m.receive.SlackReceive(str(root), ack=lambda e: None, team="planner", allowed_users=(U,), allowed_channels=(C,),
                                  client=m.receive.intake.Intake(str(root), "planner", capacity=capacity),
                                  notify=lambda row: None, log=logs.append if logs is not None else None)

def live(m, root, idx, logs=None, asked=()):  # 글 idx 칸 0 으로 full · asked 요청 · 그 뒤 listen 기동
    first = rx(m, root, 0)
    [first.handle(msg(n)) for n in idx]
    [ask(root, n) for n in asked]
    return rx(m, root, 8, logs)

def ask(root, n, line=None):
    with open(os.path.join(str(root), ".fable-team", "teams", "planner", "slack", "settle.jsonl"), "a") as fh:
        fh.write(line or json.dumps({"command": cmd(n), "by": DESK, "why": "처리함", "at": "-"}) + "\n")

states = lambda r: {c: e["state"] for c, e in r.latest().items()}  # noqa: E731

def s_after_start(m, root, mp=None):  # 기동 뒤 CLI 요청 1줄 → idle 1회
    r = live(m, root, [1])
    out = m.receive.settle(str(root), "planner", cmd(1), DESK, "ⓑ 집행")
    r.pass_idle()
    return out, r.latest()[cmd(1)]
def test_1_request_after_start_settled_in_one_idle(tmp_path):
    out, row = s_after_start(M, tmp_path)
    assert out == (0, "SETTLE-REQUESTED %s 적용=다음 idle" % cmd(1))
    assert (row["state"], row["reason"]) == ("settled", "처리 기록 %s · ⓑ 집행" % DESK)

def s_quiet(m, root, mp, asked_at_start=False):  # settle 무변화 idle 3회 → (settle 판독, receive 판독, 크기 변화, 이유)
    r = live(m, root, [1], asked=[1] if asked_at_start else ())
    if not asked_at_start:
        ask(root, 1)
        r.pass_idle()
    reads, rows, real, size = [], [], r.entries, os.path.getsize(r.path)
    mp.setattr(m.receive, "read_settle", lambda *a, **kw: reads.append(a) or {})
    mp.setattr(r, "entries", lambda: rows.append(1) or real())
    got = [r.pass_idle()["reason"] for _ in range(3)]
    return len(reads), len(rows), os.path.getsize(r.path) - size, got
@pytest.mark.parametrize("at_start", [False, True], ids=["after-apply", "asked-before-start"])
def test_2_unchanged_settle_idle_reads_and_writes_nothing(tmp_path, monkeypatch, at_start):
    assert s_quiet(M, tmp_path, monkeypatch, at_start) == (0, 0, 0, ["무변화"] * 3)

class Desk:  # _requeue 가 보는 두 칸만 — 남은 일 0 · 상한 0 = 칸 0
    ex, rs = type("Ex", (), {"_state_records": staticmethod(lambda: ({}, []))}), type("Rs", (), {"capacity": 0})

def s_room0(m, root, mp=None):  # 칸 0 · 미요청 full 이 앞(ts 작음) · 요청 full 이 뒤
    r = live(m, root, [1, 2], asked=[2])
    return m.reply_done._requeue(str(root), "planner", Desk()), states(r)
def test_3_room_zero_asked_full_settled_unasked_untouched(tmp_path):
    assert s_room0(M, tmp_path) == ([], {cmd(1): "full", cmd(2): "settled"})
def test_c1_broken_settle_logs_once_keeps_receiving_no_settled(tmp_path):
    logs = []
    r = live(M, tmp_path, [1], logs)
    ask(tmp_path, 1), ask(tmp_path, 0, "{broken")
    assert [r.pass_idle()["reason"] for _ in range(2)] == ["판정 불가 settle.jsonl", "무변화"]
    assert (len([x for x in logs if "판정 불가" in x]), states(r)[cmd(1)], r.handle(msg(3))["state"]) == (1, "full", "dispatched")
def test_c2_same_request_twice_one_settled(tmp_path):
    r = live(M, tmp_path, [1])
    for _ in range(2):
        ask(tmp_path, 1), r.pass_idle()
    assert [e["state"] for e in r.entries()].count("settled") == 1
def test_c3_dispatched_request_untouched(tmp_path):
    r = live(M, tmp_path, [])
    before = (r.handle(msg(1))["state"], open(r.path, "rb").read())
    ask(tmp_path, 1), r.pass_idle()
    assert before == ("dispatched", open(r.path, "rb").read())

def _mutant(tmp, rel, old, new):
    base = tmp / "ft2m"
    for part in ("core", "adapters"):
        shutil.copytree(os.path.join(FT2, part), base / part)
    text = (base / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, old  # 변이 자리 정확히 1곳
    (base / rel).write_text(text.replace(old, new), encoding="utf-8")
    return _mods(str(base), tag=tmp.name)

MUTANTS = [  # (변이, 파일, 바꿀 글, 새 글, 시나리오, 깨짐 판정)
    ("M1", RX, "asked = read_settle(self.settle_path, strict=True)", "asked = {}", s_after_start,
     lambda got: got[1]["state"] != "settled"),
    ("M2", RX, "if sig == self.settle_sig:", "if False:", s_quiet, lambda got: got[:2] != (0, 0)),
    ("M3", RD, '        if entry["command"] in asked:', '        if room <= 0:\n            break\n'
     '        if entry["command"] in asked:', s_room0, lambda got: got[1][cmd(2)] != "settled"),
]
@pytest.mark.parametrize("mid,rel,old,new,scenario,broken", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_caught(tmp_path, monkeypatch, mid, rel, old, new, scenario, broken):
    assert broken(scenario(_mutant(tmp_path, rel, old, new), tmp_path / "world", monkeypatch)), mid
