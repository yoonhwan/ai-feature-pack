"""r1887 ft2 keeper 다음 카드 — 끝난(done) work 의 짝 카드·stem 카드는 고르지 않음 (반례 ①~⑤ · 변이 M1·M2).
대역 = r1871 world(r1812 keeper_world 임시 root·git·가짜 tmux·launch·record) + 짝 표 cards.tsv(임시 root).
실 tmux·명부·ft2 원장·mbox·설치 0 · sleep 0. 기준판 = ①·② Red(끝난 짝·stem 카드를 고름) · ③ Red(짝 work owner 를 못 봄).
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r1887_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
P8, R9, Z9, DONE_W = "p8-goal-table", "r9878", "z9-other", "r9879"
KN = "adapters/pi/keeper_next.py"


def pair(w, work, stem):
    """짝 표 1줄 = work → 대기 카드 경로 (keeper_land.cardmap 이 읽는 꼴)."""
    path = w.runtime() / "cards.tsv"
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    kw._put(path, old + "%s\tdesign/teams/harness/indices/대기/%s.md\n" % (work, stem))


def c1(w):   # ① 짝 표 r9→P8 · r9 done → P8 안 고름 · 사유 «끝남 1»
    pair(w, R9, P8)
    w.work(R9, done=True)
    w.round()
    assert base.launched(w) == [] and base.count(w, "accept", P8) == 0
    assert len(base.notes(w)) == 1 and "막힌 사유별 끝남 1" in base.notes(w)[0], base.notes(w)


def c2(w):   # ② 대기 카드 stem = r9 · r9 done → 안 고름
    w.work(R9, done=True)
    w.round()
    assert base.launched(w) == [] and len(base.notes(w)) == 1 and "끝남 1" in base.notes(w)[0], base.notes(w)


def c3(w):   # ③ 짝 표 r9→P8 · r9 owner 있음(done 아님) → 안 고름 · 사유 «배정됨 1»
    pair(w, R9, P8)
    w.work(R9, done=False, intent=False, turn=None)
    w.round()
    assert base.launched(w) == [] and base.count(w, "accept", P8) == 0
    assert any("막힌 사유별 배정됨 1" in x for x in base.notes(w)), base.notes(w)


def c4(w):   # ④ 짝 표 없음 · done 없음 → 지금처럼 P8 고름
    w.round()
    assert base.launched(w) == [P8] and base.notes(w) == []


def c5(w):   # ⑤ 끝남 1(P8 짝) + 고를 카드 1(Z9) → Z9 고름
    pair(w, DONE_W, P8)
    w.work(DONE_W, done=True)
    w.round()
    assert base.launched(w) == [Z9] and base.count(w, "accept", P8) == 0 and base.notes(w) == []


CASES = {"①": (c1, {P8: ""}), "②": (c2, {R9: ""}), "③": (c3, {P8: ""}), "④": (c4, {P8: ""}), "⑤": (c5, {P8: "", Z9: ""})}
MUTANTS = {"M1": ("pair.setdefault(os.path.basename(p)[:-3], set()).add(work)", "pass", ("①", "③")),
           "M2": ('"끝남" if stem in done or ', '"끝남" if ', ("②",))}


def run(name, tmp, mp, ft2=kw.FT2):
    case, cards = CASES[name]
    w = base.world(tmp, mp, cards, ft2=ft2)
    case(w)


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
        with pytest.raises(AssertionError):
            run(case, bad, monkeypatch, tree)
        run(case, good, monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
