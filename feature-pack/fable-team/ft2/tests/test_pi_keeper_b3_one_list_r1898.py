"""r1898 keeper B3 = 바퀴당 tmux list-sessions 1회 · stall 초 ROUND 칸 · ROUND-CAP 다음 바퀴 이어 돌기 — 반례 ①~⑥ · 변이 M1~M3.
r1812 대역(keeper_world_r1812.World) 재사용 · tmux·ft-seat-close = 같은 프로세스 가짜 call(호출 기록) · 주입 시계 · 실 tmux 0 · sleep 0.
"""
import importlib.util
import json
import shutil
import types
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r1898", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
World, FT2, _put = kw.World, kw.FT2, kw._put
LIVE = ["byz-harness-nano-x-r1#0", "byz-desk-a#0", "byz-room-b#0"]   # 그중 첫째만 `_replaced_by` 행 이름
def b3(w, ls=(0, ""), rows=3000, extra=None, held=None, skip=(), opened=None):
    """명부 `_replaced_by` rows 행(+ extra) · 살아 있는 세션 LIVE · list-sessions 결과 ls(rc, err) → (keeper, 호출 목록)."""
    seats = {"_master": "M", LIVE[0]: {"_replaced_by": "byz-harness-nano-x-r1#1"}}
    seats.update({"byz-harness-nano-old-%d#0" % i: {"_replaced_by": "n#%d" % i} for i in range(rows)})
    _put(w.root / ".fable-team" / "seats-harness.json", dict(seats, **(extra or {})))
    k, calls = w.keeper(), []
    k.skip, k.state["held"], k.state["open"] = set(skip), dict(held or {}), dict(opened or {})
    def call(argv, timeout=7, retry=0):
        calls.append(argv)
        if argv[1] == "list-sessions":   # 서버 응답 = LIVE 줄들 · has-session = 옛 probe 길(변이 M1 이 탐)
            return (ls[0], "".join(x + "\n" for x in LIVE) if ls[0] == 0 else "", ls[1])
        if argv[0] == "bash":   # 이미 닫은 좌석을 또 닫으면 rc 3(세션 없음 실패 → HELD-SEAT)
            return (3, "", "no session") if argv[2] in [a[2] for a in calls[:-1] if a[0] == "bash"] else (0, "STUB", "")
        return ((0, "", "") if argv[-1][1:] in LIVE else (1, "", "can't find session")) if argv[1] == "has-session" else (1, "", "?")
    k.call = call
    return k, calls if k.retired() is None else None
def verb(calls, name):
    return [a for a in calls if a[1] == name or (name == "close" and a[0] == "bash")]
def c1(w):   # ① 3000 행 + 생존 3(1개만 행 이름) → list-sessions 1 · has-session 0 · ft-seat-close 1
    _, calls = b3(w)
    assert [len(verb(calls, v)) for v in ("list-sessions", "has-session", "close")] == [1, 0, 1], calls[:3]
    assert verb(calls, "close")[0][2] == LIVE[0]
def c2(w):   # ② 대상 = 옛 probe 규칙(행 ∧ 생존 ∧ 제외 팀 밖 ∧ held 10분 밖)과 같음
    extra = {LIVE[1]: {"_replaced_by": "d#1"}, LIVE[2]: {"_replaced_by": "r#1"}}
    k, calls = b3(w, rows=50, extra=extra, held={LIVE[1]: w.t - 60}, skip=("room",))
    assert [a[2] for a in verb(calls, "close")] == [LIVE[0]] and set(k.state["open"]) == {LIVE[1]}
def c3(w):   # ③ 서버 없음 → 닫기 0 · 판정 불가 0 · open 비움
    k, calls = b3(w, ls=(1, "no server running on /tmp/x"), rows=5, opened={LIVE[0]: {"team": "harness", "since": 0}})
    assert verb(calls, "close") == [] and not [x for x in k.lines if "판정 불가" in x] and k.state["open"] == {}
def c4(w):   # ④ 넘침(rc None)·rc1 다른 err → 판정 불가 1줄 · 닫기 0 · has-session 폴백 0
    for ls in ((None, "timed out"), (1, "error connecting")):
        k, calls = b3(w, ls=ls, rows=5)
        bad = [x for x in k.lines if x.startswith("판정 불가 tmux list-sessions rc %s" % ls[0]) and x.endswith("이 바퀴 B3 0")]
        assert len(bad) == 1 and verb(calls, "close") == [] and verb(calls, "has-session") == [], k.lines
def clocked(w, k, cut):
    """주입 시계 — 팀 1개 = monotonic +cut 초 · fetch·report·b3·full_alert 손 0 · 돈 팀 순서 반환."""
    clock, seen = [0.0], []
    type(k).__init__.__globals__["time"] = types.SimpleNamespace(monotonic=lambda: clock[0], time=__import__("time").time)
    k.git, k.report, k.retired = (lambda *a, **o: (0, "", "")), (lambda: None), (lambda: None)
    k.fa = types.SimpleNamespace(observe=lambda *a, **o: None)
    k.team_round = lambda team: (seen.append(team), clock.__setitem__(0, clock[0] + cut))
    assert k.run_once() == 0
    return seen, json.loads((w.state / "ft2-keeper" / "state.json").read_text(encoding="utf-8"))
def c6(w):   # ⑥ 3번째 팀에서 컷 → cap_next · 다음 바퀴 그 팀부터 · 컷 없는 바퀴 뒤 키 없음 · 목록 밖 = 원래 순서
    teams = ["t1", "t2", "t3", "t4"]
    for t in teams:
        _put(w.state / "ft20-switch" / (t + ".json"), "{}"), w.runtime(t).mkdir(parents=True)
    assert clocked(w, w.keeper(), 31)[0] == ["t1", "t2"]
    seen, st = clocked(w, w.keeper(), 0)
    assert seen == ["t3", "t4", "t1", "t2"] and "cap_next" not in st
    _put(w.state / "ft2-keeper" / "state.json", dict(st, cap_next="t3")), _put(w.state / "ft2-keeper" / "SKIP_TEAMS", "t3\n")
    assert clocked(w, w.keeper(), 0)[0] == ["t1", "t2", "t4"]
def c5(w):   # ⑤ ROUND 줄 stall= 칸 = stall.check 에 쓴 초 · s = fetch+b1+b2+b3+stall
    w.card("r9801"), w.work("r9801", intent=False), w.pack_sha()   # r1963 — 두 리포 다 바뀌어야 리포마다 fetch 1회(안 바뀐 리포 = fetch 0)
    k = w.keeper()
    def tick(dt, out=None):
        return setattr(w, "t", w.t + dt) or out
    git = k.git
    k.git = lambda repo, *a, **o: (tick(5) if a[0] == "fetch" else None, git(repo, *a, **o))[1]
    k.complete, k.retired, k.stall.check = (lambda *a: tick(10, False)), (lambda: tick(3)), (lambda *a: tick(7))
    assert [x for x in w.round(k) if x.startswith("ROUND")] == ["ROUND s=30 fetch=10 b1=10 b2c=0 b2f=0 b3=3 stall=7 slow=harness:b1:10"]   # r1969 b2c·b2f·slow
def c7(w):   # ⑦ DA R1 — 같은 생존 좌석이 seats-harness.json·seats.json 둘 다 `_replaced_by` → close 1 · 허위 HELD-SEAT 0
    _put(w.root / ".fable-team" / "seats.json", {LIVE[0]: {"_replaced_by": "byz-harness-nano-x-r1#1"}})
    k, calls = b3(w, rows=5)
    assert len(verb(calls, "close")) == 1 and not [x for x in k.lines if x.startswith("HELD-SEAT")], k.lines
CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}
KC, KP = "adapters/pi/keeper_close.py", "adapters/pi/keeper.py"
MUTANTS = {"M1": (KC, "if seat not in alive:", 'if self.probe(seat) != "alive":', c1),
           "M2": (KC, 'return self.log("판정 불가", text="tmux list-sessions', 'return set() if True else self.log("판정 불가", text="tmux list-sessions', c4),
           "M3": (KP, 'self.state["cap_next"] = team', "pass", c6)}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w", monkeypatch, tree))
