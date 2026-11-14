"""r1921 ft2 keeper 오류 턴 깨움 — UNAVAILABLE 오류 120초 뒤 1회 깨움 · 또 오류 = 재배정 0 + [크리티컬] 하루 1 (카드 반례 ①~⑦′ · 변이 M1~M3).
입력 = r1813 시험 대역(World: 실제 core · 가짜 tmux·ps·세션 파일 · 주입 시계) 재사용 · sleep 0 · 실 tmux·pi 0.
기준판(팩 origin/main · 오류 갈래 없음) = ① ⑤ ⑥ ⑦ Red. 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import datetime, importlib.util, json, os, shutil  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("r1813_world_for_r1921", str(FT2 / "tests" / "test_pi_keeper_stall_r1813.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
W, M, H0, T0 = B.W, B.M, B.H0, B.T0
R1866 = '503 {"error":{"message":"auth_unavailable: no available credential for model claude-opus-5-5"}}'   # 11-13 실사건 꼴


def _err(w, msg, at, field="errorMessage"):
    """세션 마지막 줄 = 오류 턴(바깥 timestamp = ISO UTC) · mtime = 오류 시각."""
    f = w.session(w.tree(), at - T0)
    ts = datetime.datetime.fromtimestamp(at, datetime.timezone.utc).isoformat().replace("+00:00", "Z")
    last = {"type": "message", "timestamp": ts, "message": {"role": "assistant", "stopReason": "error", field: msg}}
    B._put(f, '{"type": "session"}\n' + json.dumps(last) + "\n")
    os.utime(f, (at, at))


def _seat(w, msg, age, step=-5 * M):
    w.seat(step=step, commit=step, mtime=-age)
    _err(w, msg, T0 - age)


def _mine(lines):
    return [x for x in lines if H0 in x]   # 착지 판독 줄(일 이름만 · holder 0)은 셈 밖


def c1(w):   # ① 503 · 121초 · Working 0 → Escape·문구·Enter · WOKE 1(본문 «오류 턴»)
    _seat(w, "503 Service Unavailable", 121)
    lines = w.round()
    keys = [x["a"][3:] for x in w.tmux("send-keys")]
    assert len(keys) == 3 and keys[0] == ["Escape"] and keys[1][0] == "-l" and "오류 턴 뒤 121초" in keys[1][1] and keys[2] == ["Enter"]
    assert [x for x in lines if x.startswith("WOKE harness %s %s" % (W, H0)) and "오류 턴" in x] and len(_mine(lines)) == 1, lines


def c2(w):   # ② 119초 → 키 0 · 로그 0
    _seat(w, "503 Service Unavailable", 119)
    assert w.tmux("send-keys") == [] and _mine(w.round()) == []


def c3(w):   # ③ LOGGEDOUT → LOGGEDOUT 줄 1 · 키 0(지금 그대로)
    _seat(w, "authentication_failed: Not logged in", 16 * M, step=-16 * M)
    assert sum(x.startswith("LOGGEDOUT harness %s" % W) for x in w.round()) == 1 and w.tmux("send-keys") == []


def c4(w):   # ④ RATELIMITED·UNKNOWN → 키 0
    for sub, msg in (("r", "rate_limit_error: slow down"), ("u", "something odd")):
        v = B.World(w.tmp / sub, w.mp, w.ft2)
        _seat(v, msg, 300)
        assert _mine(v.round()) == [] and v.tmux("send-keys") == [], sub


def c5(w):   # ⑤ 깨움 뒤 또 UNAVAILABLE → kill·assign·launch 0 · HELD-STALL 1 · [크리티컬] 1 · 같은 날 다음 바퀴 쪽지 0
    _seat(w, "503 Service Unavailable", 121)
    w.round()
    _err(w, "overloaded_error", T0 + 60)
    lines = w.round(200)
    assert w.tmux("kill-session") == [] and w.tmux("new-session") == [] and w.kinds("dispatch") == 1
    assert sum(x.startswith("HELD-STALL harness %s" % W) for x in lines) == 1, lines
    assert len(w.notes()) == 1 and "[크리티컬] ft2 keeper 오류 턴 반복 harness %s %s" % (W, H0) in w.notes()[0]
    assert not [x for x in w.round(400) if x.startswith("HELD-STALL")] and len(w.notes()) == 1 and len(w.tmux("send-keys")) == 3


def c6(w):   # ⑥ 깨움 뒤 정상 턴 · 진척 0 → S1 시계 그대로(woke 0 → 15분 뒤 S2 깨움 먼저 · S3 0)
    _seat(w, "503 Service Unavailable", 121)
    w.round()
    assert w.k.state["woke"] == {}
    w.session(w.tree(), 1 * M)
    assert _mine(w.round(14 * M)) == []
    lines = w.round(17 * M)
    assert ("WOKE harness %s %s" % (W, H0)) in lines and w.tmux("kill-session") == [] and len(w.tmux("send-keys")) == 6
    assert "진척 0" in w.tmux("send-keys")[4]["a"][-1]


def c7(w):   # ⑦ r1866 실사건 줄(503 · credential · AUTH 낱말 0) · ⑦′ connection reset by peer → UNAVAILABLE → 깨움
    S = B._mod(w.ft2 / "adapters" / "pi" / "keeper_stall.py", "ks_%d" % id(w))
    for sub, msg in (("a", R1866), ("b", "Error: Connection Reset By Peer")):
        v = B.World(w.tmp / sub, w.mp, w.ft2)
        _seat(v, msg, 121)
        got = S.error_turn(str(next(v.sess.rglob("*.jsonl"))))
        assert got and got[0] == "UNAVAILABLE" and abs(got[1] - (T0 - 121)) < 1, (sub, got)
        assert any(x.startswith("WOKE harness %s" % W) for x in v.round()), sub


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}
KS = "adapters/pi/keeper_stall.py"
MUTANTS = {"M1": ('hit = self.error(team, work, holder, key, facts["session"])', "hit = None", c1),
           "M2": ("if k.now() - at < self.err_s:", "if False:", c2),
           "M3": ('k.log("HELD-STALL", team, "%s %s 오류 턴 반복 — 재배정 0" % (work, holder))',
                  "return self.reassign(team, work, attempt, holder, tree, intent, rows)", c5)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](B.World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KS).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KS).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(B.World(tmp_path / "w1", monkeypatch, tree))
    case(B.World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
