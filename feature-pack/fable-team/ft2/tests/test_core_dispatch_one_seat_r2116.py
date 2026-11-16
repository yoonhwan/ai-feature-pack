"""ft2 배정 한 좌석 한 work 시험 (카드 r2116 · master #317972 · DA HOLD R1 #318309 · 결정 #318429).
반례 ①~⑥ · ①b · ③b = 카드 «반례 집합» 그대로 · 앞 꼴 = S1 이 W1 dispatch · 완료 0 · 격리 tmp · 고정 시계 ·
가짜 probe · 실 원장·명부·tmux 0 · sleep 0. 변이(core 사본만 · 하나씩) M1 done 거르기 뺌 → ①b · M2 영수 거르기 뺌 → ③ ·
M4 영수 대조 = work 이름만 → ③b · M3 «다른 work» 조건 뺌 → ⑥. 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조)."""
import importlib.util
import os
import shutil
from pathlib import Path
from types import SimpleNamespace

import pytest

CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core")
TEAM, NOW, EV, S1, S2 = "harness", "2026-11-16T19:00:00", ("v1", "v2"), "S1", "S2"
OK, HOLD, REFUSED = "접수 성공", "완료 유보", "접수 거부"
TAIL = "새 좌석 열기 또는 앞 work complete 뒤"


def _core(path=CORE, alias="ft2_test_r2116_"):
    out = {}
    for name in ("dispatch", "close_next"):
        spec = importlib.util.spec_from_file_location(alias + name, os.path.join(path, name + ".py"))
        out[name] = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(out[name])
    return SimpleNamespace(dispatch=out["dispatch"], cn=out["close_next"])


M = _core()


def _d(root, m):
    return m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)


def _base(root, m, works=("W1", "W2", "W3")):
    """앞 꼴 — W1·W2·W3 접수 영수 · S1 이 W1 dispatch(gen 1 · a1) · 완료 0."""
    os.makedirs(str(root), exist_ok=True)
    d = _d(root, m)
    assert [d.rs.submit("c-" + w, "x" * 8, w).result for w in works] == [OK] * len(works)
    assert d.assign("W1", S1, evidence=EV).result == OK
    return d


def _raw(d, kind, work, holder=None, gen=None, extra=None, state_extra=None):
    """옛 원장·close 줄 꼴을 그대로 1줄 쓴다(배정 경로 밖 · 이 카드 전 원장 재현용)."""
    state, records = d.ex._state_records()
    rec = M.dispatch.record.build(TEAM, (records[-1]["seq"] if records else 0) + 1, work, "a1", NOW, work, work,
                                   kind=kind, holder=holder, gen=gen, extra=extra)
    d._write(state, records, rec, state_extra)


def _snap(d):
    return len(d.rs.records()), d.ex._state_records()[0]["revision"]


def _receipt(root, m, event="e1"):
    """close_next 영수(seat S1 · gen 1 · work W1 · next W2 · next_holder S1) — 표식은 시험이 직접 둔다."""
    node = m.cn.CloseNext(str(root), TEAM, clock=lambda: NOW, probe=lambda seat: "absent")
    Path(node.marker).parent.mkdir(parents=True, exist_ok=True)
    Path(node.marker).write_text("enabled %s\n" % NOW, encoding="utf-8")
    return node.receipt(S1, 1, "W1", event, S1, EV, next_work="W2")


def c1(root, m):      # ① W1 complete(표식 · reassess 로 owner 빠짐) → S1 에 W2 → OK
    d = _base(root, m)
    assert [d.deliver("W1", "a1").result, d.complete("W1", "a1").result] == [OK, OK]
    assert "W1" not in d.ex._state_records()[0]["owners"]
    assert d.assign("W2", S1, evidence=EV).result == OK


def c1b(root, m):     # ①b W1 close 줄로 done(owner 줄 남음) → S1 에 W2 → OK
    d = _base(root, m)
    _raw(d, "close", "W1", state_extra={"done": {"W1": {"attempt": "a1", "at": NOW, "marker": ""}}})
    state = d.ex._state_records()[0]
    assert "W1" in state["done"] and state["owners"]["W1"]["holder"] == S1
    assert d.assign("W2", S1, evidence=EV).result == OK


def c2(root, m):      # ② W1 park(idle-done) → S1 에 W2 → OK
    d = _base(root, m)
    assert d.park("W1", "a1", "idle-done").result == OK
    assert d.assign("W2", S1, evidence=EV).result == OK


def c3(root, m):      # ③ close_next 영수 → W2 를 S1 에 배정 · 전달 OK
    _base(root, m)
    out = _receipt(root, m)
    assert (out.result, out.next, out.holder) == (OK, "W2", S1), out


def c3b(root, m):     # ③b 영수(S1 · gen 1 · W1) 뒤 W1 을 S2 에 rotation(gen 2) → S2 에 W3 → REFUSED · 쓰기 0
    d = _base(root, m)
    assert _receipt(root, m).result == OK
    rot = d.assign("W1", S2, evidence=EV, rotation=True)
    assert (rot.result, rot.gen, rot.holder) == (OK, 2, S2)
    before = _snap(d)
    out = d.assign("W3", S2, evidence=EV)
    assert (out.result, out.written, _snap(d)) == (REFUSED, False, before), out
    assert "W1" in out.reason


def c4(root, m):      # ④ 앞 꼴 → S1 에 W2 → REFUSED · 쓰기 0 · 사유 1줄
    d = _base(root, m)
    before = _snap(d)
    out = d.assign("W2", S1, evidence=EV)
    assert (out.result, out.stage, out.written, _snap(d)) == (REFUSED, "reject", False, before), out
    assert out.reason == "좌석 사용 중 W1 — " + TAIL
    assert len([r for r in d.rs.records() if r["kind"] == "dispatch"]) == 1


def c5(root, m):      # ⑤ S1 이 W3 · W1 둘 다 쥔 옛 원장 → S1 에 W2 → REFUSED · 앞 work = W1(이름 순 첫)
    os.makedirs(str(root), exist_ok=True)
    d = _d(root, m)
    assert [d.rs.submit("c-" + w, "x" * 8, w).result for w in ("W1", "W2", "W3")] == [OK] * 3
    for work in ("W3", "W1"):
        _raw(d, "dispatch", work, S1, 1, extra={"intent": {"attempt": "a1", "state": "pending"}},
             state_extra={"generations": {work: 1}, "owners": {work: {"holder": S1, "gen": 1, "at": NOW}}})
    before = _snap(d)
    out = d.assign("W2", S1, evidence=EV)
    assert (out.result, out.written, _snap(d)) == (REFUSED, False, before), out
    assert out.reason == "좌석 사용 중 W1 — " + TAIL


def c6(root, m):      # ⑥ 앞 꼴 → S2 에 W2 OK · S1 에 W1 rotation OK(새 attempt)
    d = _base(root, m)
    assert d.assign("W2", S2, evidence=EV).result == OK
    out = d.assign("W1", S1, evidence=EV, rotation=True)
    assert (out.result, out.attempt, out.holder) == (OK, "a2", S1), out


CASES = {"c1": c1, "c1b": c1b, "c2": c2, "c3": c3, "c3b": c3b, "c4": c4, "c5": c5, "c6": c6}


@pytest.mark.parametrize("name", sorted(CASES))
def test_case(name, tmp_path):
    CASES[name](tmp_path / "root", M)


MUTANTS = {   # 이름 → (원본 글자, 바꿀 글자, 잡는 사례)
    "M1": (" and name not in done", "", "c1b"),
    "M2": ("for c in closes))", "for c in ()))", "c3"),
    "M3": ("if name != work and ", "if ", "c6"),
    "M4": ('(c.get("work"), c.get("seat"), c.get("gen")) == (name, holder, row.get("gen"))',
           'c.get("work") == name', "c3b"),
}


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutant(name, tmp_path):
    old, new, case = MUTANTS[name]
    copy = tmp_path / "core"
    shutil.copytree(CORE, str(copy))
    src = (copy / "dispatch.py").read_text(encoding="utf-8")
    assert src.count(old) == 1, "변이 자리 0 또는 여럿: " + name
    (copy / "dispatch.py").write_text(src.replace(old, new), encoding="utf-8")
    CASES[case](tmp_path / "orig", M)                                   # 원본 = PASS
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "mut", _core(str(copy), "ft2_test_r2116_%s_" % name))
