"""r1941 ft2 keeper 다음 카드 — «- 선행:» 값이 없음·충족·0·— 로 시작하면 지금처럼 고르고, 자연어 미충족 선행은 고르지 않는다(반례 ①~⑤ · 변이 M1·M2).
대역 = r2027 시험과 같은 r1871 world(임시 root·git·가짜 tmux·launch·record) · 실 리포·실 나노·명부·mbox·설치 0 · sleep 0.
기준판 = ② «충족(PR #1)»·«0»·«—» Red(r2027 판은 번호 참조 없는 값을 선행불명으로 막는다).
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r1941_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
P, Q = "p1-prereq", "p2-plain"
KN = "adapters/pi/keeper_next.py"


def picked(w, stem=P):
    w.round()
    assert base.launched(w) == [stem] and base.notes(w) == [], (base.launched(w), base.notes(w))


def c1(w):   # ① 자연어 미충족 선행 1장만 → 고르기 0 · [다음 없음] 막힌 사유에 선행 1(번호 참조 없음 = 선행불명 · r2027 칸)
    w.round()
    assert base.launched(w) == [] and base.count(w, "accept", P) == 0, base.launched(w)
    assert len(base.notes(w)) == 1 and " 선행불명 1" in base.notes(w)[0], base.notes(w)


def c4(w):   # ④ 선행 카드(긴급: 예) + 보통 카드 → 보통 카드를 고름
    picked(w, Q)


def c5(w):   # ⑤ 명부 `_master` 빈칸 팀이어도 선행 없는 카드는 고름(팀장 관문 0)
    kw._put(w.root / ".fable-team" / "seats-harness.json", {"_master": ""})
    picked(w)


CASES = {"①": (c1, {P: "- 선행: M4 migration 라이브 뒤\n"}),
         "②없음": (picked, {P: "- 선행: 없음\n"}),
         "②충족": (picked, {P: "- 선행: 충족(PR #1)\n"}),
         "②0": (picked, {P: "- 선행:  0\n"}),
         "②—": (picked, {P: "- 선행: —\n"}),
         "②줄없음": (picked, {P: ""}),
         "③": (picked, {P: "- 선행 PR: #12\n"}),
         "④": (c4, {P: "- 긴급: 예\n- 선행: M4 migration 라이브 뒤\n", Q: ""}),
         "⑤": (c5, {P: ""})}
MUTANTS = {"M1": ("우선|대상|선행|배정)\", r[2]", "우선|대상|배정)\", r[2]", "①"),
           "M2": ('"없음", "충족", "0", "—", "-"', '"없음", "0", "—", "-"', "②충족")}


def run(name, tmp, mp, ft2=kw.FT2):
    case, cards = CASES[name]
    w = base.world(tmp, mp, cards, ft2=ft2)
    case(w)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
