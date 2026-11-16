"""r2149 ft2 keeper — card_stage 성공 기억(staged)은 그날만 유효(D1) · 같은 날 기억·하루 3회 상한 그대로(D2) · 날 지난 키는 다시 적힐 때 덮임(D3).
대역 = r2140 시험 꼴(r1812 World · r2026 가짜 card_stage · 주입 시계 w.t) · 어제 기억 = 바퀴 1회 STAGED 뒤 w.t += 하루 · 실 BYZ 리포·실 push 0 · sleep 0.
①~⑤ · 변이 M1(비교를 «key ∈ staged» 로 되돌림 → ① ② ④) · M2(기억 비교 삭제 = 늘 부름 → ③)."""
import importlib.util
import shutil
from pathlib import Path

import pytest

_S = importlib.util.spec_from_file_location("r2149_ext", str(Path(__file__).with_name("test_pi_keeper_stage_external_done_r2140.py")))
ext = importlib.util.module_from_spec(_S)
_S.loader.exec_module(ext)
World, Fake, keeper, FT2, AT = ext.World, ext.Fake, ext.keeper, ext.FT2, ext.AT
TEAM, STAGED, DAY = ext.TEAM, ext.STAGED, 86400
NO_LAND = Fake.Unsure("판정 불가 착지 줄 없음")


def yesterday(w, mp, work):
    """쉼 + complete(keeper 밖 · K2 = 바퀴마다 stage_card 자리) → 바퀴 1회 STAGED = staged[key] 오늘 → 시계 하루 넘김 = 기억이 어제."""
    ext.ext_done(w, work, mp, "parked")
    k = keeper(w, Fake([STAGED]))
    w.round(k)
    old = k.state["staged"][TEAM + "|" + work]
    w.t += DAY
    return old


def turn(w, fake):
    k = keeper(w, fake)
    return k, w.round(k)


def c1(w, mp):   # ① 어제 기억 · STAGED(되돌린 카드가 착지) → 1회 · CARD-STAGE · staged = 오늘
    old = yesterday(w, mp, "r9491")
    fake = Fake([STAGED])
    k, lines = turn(w, fake)
    assert fake.calls == [(TEAM, "r9491", AT)] and len(ext.stages(lines, "CARD-STAGE")) == 1, (fake.calls, lines)
    assert k.state["staged"][TEAM + "|r9491"] == k.stamp()[:10] != old, k.state["staged"]


def c2(w, mp):   # ② 어제 기억 · Unsure 착지 줄 없음 → 1회 · Unsure · 하루 셈 1 · staged 그대로(어제)
    old = yesterday(w, mp, "r9492")
    fake = Fake([NO_LAND])
    k, lines = turn(w, fake)
    key = TEAM + "|r9492"
    assert fake.calls == [(TEAM, "r9492", AT)] and len(ext.stages(lines, "Unsure")) == 1, (fake.calls, lines)
    assert k.state["staging"][key] == [k.stamp()[:10], 1] and k.state["staged"][key] == old, k.state


def c3(w, mp):   # ③ 오늘 기억 → 0회 · 로그 0(K3 그대로)
    ext.ext_done(w, "r9493", mp, "parked")
    w.round(keeper(w, Fake([STAGED])))
    fake = Fake([STAGED])
    _k, lines = turn(w, fake)
    assert fake.calls == [] and not ext.stages(lines, "CARD-STAGE", "NOOP", "Unsure", "DEFER"), (fake.calls, lines)


def c4(w, mp):   # ④ 어제 기억 · None(이미 완성) → 1회 · NOOP · staged = 오늘 · 같은 날 다음 바퀴 0회
    old = yesterday(w, mp, "r9494")
    fake = Fake([None])
    k, lines = turn(w, fake)
    assert fake.calls == [(TEAM, "r9494", AT)] and len(ext.stages(lines, "NOOP")) == 1, (fake.calls, lines)
    assert k.state["staged"][TEAM + "|r9494"] == k.stamp()[:10] != old, k.state["staged"]
    _k, lines = turn(w, fake)
    assert len(fake.calls) == 1 and not ext.stages(lines, "CARD-STAGE", "NOOP", "Unsure"), (fake.calls, lines)


def c5(w, mp):   # ⑤ ② 를 같은 날 4바퀴 → 3회 · 4바퀴째 0회(하루 3회 상한)
    yesterday(w, mp, "r9495")
    fake = Fake([NO_LAND])
    for _ in range(4):
        turn(w, fake)
    assert len(fake.calls) == 3, fake.calls


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5}
KP = "adapters/pi/keeper.py"
NOW = 'self.state.setdefault("staged", {}).get(key) == day'
MUTANTS = {"M1": (NOW, 'key in self.state.setdefault("staged", {})', ("①", "②", "④")),
           "M2": (NOW, 'self.state.setdefault("staged", {}) is None', ("③",))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch), monkeypatch)


@pytest.mark.parametrize("name,case", [(m, c) for m, (_o, _n, cs) in MUTANTS.items() for c in cs])
def test_mutant(name, case, tmp_path, monkeypatch):
    old, new, _cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KP).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        CASES[case](World(tmp_path / "w", monkeypatch, tree), monkeypatch)
