"""r1839 ft2 keeper 사람 화면 가드 — kill 직전 `#{session_attached}` (카드 반례 ④ ⑤ ⑥ ⑦ ⑨ ⑩ · 변이 M2 M4~M8).
대역 = r1812 keeper_world · r1813 World 재사용(가짜 tmux: `=이름:` 에만 숫자 · `=이름` 은 rc0 빈 줄 = 실제 tmux 꼴 · att/att_rc 주입).
실 tmux·launchd·명부·runtime 0 · sleep 0. 기준판(판정 없음) = ④ ⑤ ⑥ ⑩ Red. 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent


def _mod(name):
    spec = importlib.util.spec_from_file_location(name + "_r1839", str(HERE / (name + ".py")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


kw, st = _mod("keeper_world_r1812"), _mod("test_pi_keeper_stall_r1813")
FT2, W, M = kw.FT2, "r9839", 60
ATT = "#{session_attached}"


def _set(w, **kv):
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d.update(kv)
    w.tm.write_text(json.dumps(d), encoding="utf-8")


def _close_world(w, att, rc=0):
    w.enable(), w.card(W, w.pack_sha())
    holder = w.work(W, done=True, alive=True)
    _set(w, att={holder: att}, att_rc=rc)
    return holder


def _att_targets(w):     # ⑨ 판정 조회 대상 = `=<세션>:`
    return [a[a.index("-t") + 1] for a in w.tmux("display-message") if ATT in a]


def c4(w):    # ④ 유휴·턴 끝 · attached=2 → kill 0 · 영수 0 · HELD 1 → 다음 바퀴 attached=0 → kill 1 · 영수 1
    holder = _close_world(w, 2)
    lines = w.round()
    assert sum(x.startswith("HELD harness %s %s" % (W, holder)) and "사람 화면 attached=2" in x for x in lines) == 1
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0 and _att_targets(w) == ["=" + holder + ":"]
    assert not [x for x in lines if x.startswith("RECEIPT")]
    _set(w, att={holder: 0})
    assert [x.split()[0] for x in w.round() if W in x] == ["CLOSED-SESSION", "RECEIPT"]
    assert len(w.tmux("kill-session")) == 1 and w.kinds("close_receipt") == 1


def c5(w):    # ⑤ display-message 출력 `abc` → unknown · kill 0 · ⑤′ rc 1 → unknown · kill 0
    _close_world(w, "abc")
    assert any("판정 불가 attached" in x for x in w.round()) and w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0
    _set(w, att_rc=1)
    assert any("판정 불가 attached" in x for x in w.round()) and w.tmux("kill-session") == []


def c10(w):   # ⑩ attached=1 바퀴 뒤 state.open[holder] 가 같은 since 로 남음(지우기 0)
    holder = _close_world(w, 1)
    w.round()
    def since():
        return w.keeper().read_json(str(w.state / "ft2-keeper" / "state.json")).get("open", {}).get(holder, {}).get("since")
    first, w.t = since(), w.t + 300
    w.round()
    assert since() == first == kw.T0


def c6(w):    # ⑥ keeper_stall Working 아님 · attached=1 → kill 0 · assign·deliver·launch 0 · reassigned 0 · 크리티컬 0
    w.seat(), w.round()
    _set(w, att={st.H0: 1})
    lines = w.round(11 * M)
    assert any(x.startswith("HELD harness %s %s" % (st.W, st.H0)) and "사람 화면 attached=1" in x for x in lines)
    assert w.tmux("kill-session") == [] and w.tmux("new-session") == [] and w.kinds("dispatch") == 1
    assert w.k.state["reassigned"] == {} and w.notes() == []


def c7(w):    # ⑦ keeper_stall attached=0 → kill → assign → deliver → launch(지금 그대로) · ⑨ 대상 `=<세션>:`
    w.seat(), w.round()
    assert any(x.startswith("REASSIGNED harness %s %s" % (st.W, st.H0)) for x in w.round(11 * M))
    assert len(w.tmux("kill-session")) == 1 and len(w.tmux("new-session")) == 1 and w.kinds("dispatch") == 2
    assert [x["a"][x["a"].index("-t") + 1] for x in w.tmux("display-message") if ATT in x["a"]] == ["=" + st.H0 + ":"]


def c9(w):    # ⑨ keeper_close attached=0 → 지금처럼 kill·영수 · 판정 대상 `=<세션>:`
    holder = _close_world(w, 0)
    assert [x.split()[0] for x in w.round() if W in x] == ["CLOSED-SESSION", "RECEIPT"]
    assert _att_targets(w) == ["=" + holder + ":"] and len(w.tmux("kill-session")) == 1


CLOSE, STALL = {"④": c4, "⑤": c5, "⑨": c9, "⑩": c10}, {"⑥": c6, "⑦": c7}
KC, KS = "adapters/pi/keeper_close.py", "adapters/pi/keeper_stall.py"
MUTANTS = {"M2": (KC, 'return "unknown · %s %s" % (rc, err)', 'return "free"', c5),
           "M4": (KC, "if self.held_attached(team, work, holder):\n                return",
                  "if self.held_attached(team, work, holder):\n                return self.receipt(team, work, attempt, holder, gen)", c4),
           "M3": (KC, "if n >= 1:", "if n > 1:", c6),
           "M5": (KS, "if k.held_attached(team, work, holder):", "if False:", c6),
           "M6": (KS, "if k.held_attached(team, work, holder):\n            return",
                  "if k.held_attached(team, work, holder):\n            return self.stop(team, work, attempt, \"att\", \"x\")", c6),
           "M7c": (KC, '"=" + seat + ":", ', '"=" + seat, ', c9),
           "M7s": (KC, '"=" + seat + ":", ', '"=" + seat, ', c7),
           "M8": (KC, "if self.held_attached(team, work, holder):\n                return",
                  "if self.held_attached(team, work, holder):\n                return self.state[\"open\"].pop(holder, None)", c10)}


def _world(case, tmp, mp, ft2=FT2):
    return (kw.World if case in CLOSE.values() else st.World)(tmp, mp, ft2)


@pytest.mark.parametrize("name", list(CLOSE) + list(STALL))
def test_case(name, tmp_path, monkeypatch):
    case = {**CLOSE, **STALL}[name]
    case(_world(case, tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(_world(case, tmp_path / "w1", monkeypatch, tree))
    case(_world(case, tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
