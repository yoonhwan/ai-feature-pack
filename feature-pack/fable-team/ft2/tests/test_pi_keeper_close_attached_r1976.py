"""r1976 keeper — 사람 화면 attached N 이어도 닫는다(NOTE 1줄 뒤 기존 절차) · unknown·Working 은 HELD 그대로 (카드 반례 ② ③ ④ · 변이 M1 M2 M3).
대역 = r1812 keeper_world(가짜 tmux · att/att_rc 주입) · 실 tmux·명부 0 · sleep 0. 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import json, shutil  # noqa: E401
import pytest
import keeper_world_r1812 as kw
W, KC = "r9976", "adapters/pi/keeper_close.py"
def _world(w, att, rc=0, **kv):
    w.enable(), w.card(W, w.pack_sha())
    holder = w.work(W, done=True, alive=True, **kv)
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d.update(att={holder: att}, att_rc=rc)
    w.tm.write_text(json.dumps(d), encoding="utf-8")
    return holder
def c2(w):   # ② 착지 끝 나노 · 유휴·턴 끝 · attached 2 → NOTE 1줄 → kill 1 → CLOSED-SESSION · 영수 1
    holder = _world(w, 2)
    lines = [x for x in w.round() if W in x]
    assert [x.split()[0] for x in lines] == ["NOTE", "CLOSED-SESSION", "RECEIPT"], lines
    assert lines[0] == "NOTE harness %s 사람 화면 attached=2 — 오빠 지시로 닫음 · %s" % (holder, W)
    assert len(w.tmux("kill-session")) == 1 and w.kinds("close_receipt") == 1
def c3(w):   # ③ attached 읽기 실패(rc 1) → HELD 판정 불가 그대로 · kill 0 · 영수 0 · NOTE 0
    _world(w, "", rc=1)
    lines = w.round()
    assert any("판정 불가 attached" in x for x in lines) and not [x for x in lines if x.startswith("NOTE")], lines
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0
def c4(w):   # ④ attached 1 이지만 Working → HELD(Working 가드 그대로) · kill 0 · NOTE 0
    _world(w, 1, pane="⠋ Working...\n")
    lines = w.round()
    assert any(x.startswith("HELD harness %s" % W) and "Working" in x for x in lines), lines
    assert not [x for x in lines if x.startswith("NOTE")] and w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0
CASES = {"②": c2, "③": c3, "④": c4}
MUTANTS = {"M1": ('if why == "free" or why.startswith("attached "):', 'if why == "free":', c2),   # attached 갈래 HELD 로 되돌림
           "M2": ('if why == "free" or why.startswith("attached "):', "if True:", c3),          # unknown 도 닫기
           "M3": ("if not self.idle(team, work, holder):\n                return", "if False:\n                return", c4)}   # Working 가드 삭제
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](kw.World(tmp_path, monkeypatch))
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KC).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KC).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        case(kw.World(tmp_path / "w1", monkeypatch, tree))
    case(kw.World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
