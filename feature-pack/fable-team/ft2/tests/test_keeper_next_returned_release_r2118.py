"""r2118 ft2 keeper 다음 카드 — master 가 반환(r1990 returned)한 최신 attempt 는 r2111 A1 «전달됨» 셈에서 빠진다(반례 ①~⑦ · 변이 M1~M4).
B1 returned[w].attempt == deliveries[w] 의 마지막 → w 의 전달 전부 뺌 · B2 dict 아님·attempt 없음·낡음 → 빼지 않음 · B3 앞 칸(배정됨) 그대로.
대역 = r1871 world(임시 root·git·가짜 tmux·launch·record) + 실 CLI return + launch/<work>@<att>.intent. ⑤ ⑥ = delivered 직접 부름(state 손 dict).
실 tmux·명부·ft2 원장·우편함·설치 0 · sleep 0. 기준판 = ① ② Red(반환된 카드를 «전달됨» 으로 막음).
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent


def _load(name, file):
    spec = importlib.util.spec_from_file_location(name, str(HERE / file))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


r2111 = _load("keeper_next_r2118_r2111", "test_keeper_next_delivered_reopen_r2111.py")
r1990 = _load("keeper_next_r2118_r1990", "test_core_return_delivered_r1990.py")
base, kw = r2111.base, r2111.kw
S, W, T0, T2, KN = r2111.S, r2111.W, r2111.T0, r2111.T2, "adapters/pi/keeper_next.py"


def give_back(w, mp, work, attempt="a1"):
    """실 CLI return(현역 master = seats-harness.json `_master`) · 접수 성공만 통과."""
    seats = w.root / ".fable-team" / "seats-harness.json"
    old = json.loads(seats.read_text(encoding="utf-8")) if seats.exists() else {}
    kw._put(seats, dict(old, _master=r1990.MASTER))
    out, rc = r1990.give_back(w.CLI, w.root, mp, attempt=attempt, work=work)
    assert (out["result"], rc) == ("접수 성공", 0), out


def c2(w, mp):   # ② deliveries [a1] · returned a1 · 원장 없음 · intent a1 → 고름 · launch 1 · NEXT-SKIP 0
    give_back(w, mp, S, r2111.hand(w, S, T0))
    lines = w.round()
    assert base.launched(w) == [S] and base.count(w, "dispatch", S) == 2, lines
    assert r2111.skip(lines, "") == [], lines


def c3(w, mp):   # ③ 짝 W [a1] 반환 · S [a1] 반환 없음 → 고르지 않음 / S 도 반환 → 고름
    r2111.base_pair(w)
    give_back(w, mp, W, r2111.hand(w, W, T0))
    att = r2111.hand(w, S, T2)
    lines = w.round()
    assert not r2111.picked(w) and len(r2111.skip(lines, "전달됨")) == 1, lines
    give_back(w, mp, S, att)
    lines = r2111.again(w)
    assert base.launched(w) == [S], lines


def c4(w, mp):   # ④ ② 뒤(keeper 가 a2 엶 · core 가 returned 지움) 다음 바퀴 → 다시 고르지 않음 · 둘째 열기 0
    c2(w, mp)
    lines = r2111.again(w)
    assert base.launched(w) == [S] and base.count(w, "dispatch", S) == 2, lines


def direct(w, deliveries, returned):
    """delivered 직접 부름 = 손 state(returned 꼴 자유) · intent 는 attempt 마다 T0 · 원장 없음."""
    for a in deliveries:
        kw._put(w.runtime() / "launch" / ("%s@%s.intent" % (S, a)), {"FT2_HOLDER": "h", "state": "opened", "at": T0})
    k = w.keeper()
    return w.K.closing.keeper_next.delivered(k, "harness", S, {S}, {"deliveries": {S: deliveries}, "returned": returned}, {}), k.lines


def c5(w, mp):   # ⑤ deliveries [a1, a2] · returned a1(낡음) → «전달됨»
    why, lines = direct(w, ["a1", "a2"], {S: {"attempt": "a1"}})
    assert why == "전달됨" and len(r2111.skip(lines, "전달됨")) == 1, lines


def c6(w, mp):   # ⑥ returned 문자열 / {} / attempt None → 셋 다 «전달됨» · 예외 0
    for bad in ("a1", {}, {"attempt": None}):
        assert direct(w, ["a1"], {S: bad})[0] == "전달됨", bad


def c7(w, mp):   # ⑦ ② 에 원장 seat → 고르지 않음 · 사유 «배정됨»
    give_back(w, mp, S, r2111.hand(w, S, T0))
    kw._put(w.state / "card-assign" / (S + ".json"), {"state": "seat", "seat": "x", "since": 1.0})
    lines = w.round()
    assert not r2111.picked(w) and r2111.skip(lines, "전달됨") == [], lines
    assert any("막힌 사유별 배정됨 1" in x for x in base.notes(w)), base.notes(w)


CASES = {"①": None, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}
MUTANTS = {"M1": ("sorted(set(works) - gone)", "sorted(works)", ("①", "②")),
           "M2": ("and got.get(\"attempt\") == (deliveries.get(w) or [None])[-1]", "", ("⑤",)),
           "M3": ("for w, got in returned.items()", "for w, got in returned.items() if w == stem", ("③",)),
           "M4": ("isinstance(got, dict) and ", "", ("⑥",))}


def run(name, tmp, mp, ft2=kw.FT2):
    if name == "①":   # ① r1990 test_returned_reopens_same_card 그대로(dispatch 2 · accept 1 · 남은 일 원래대로)
        return r1990.c1(tmp, mp, ft2)
    w = base.world(tmp, mp, {S: ""}, ft2=ft2)
    CASES[name](w, mp)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        bad, good = tmp_path / ("bad" + case), tmp_path / ("good" + case)
        bad.mkdir(), good.mkdir()
        with pytest.raises((AssertionError, AttributeError)):
            run(case, bad, monkeypatch, tree)
        run(case, good, monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
