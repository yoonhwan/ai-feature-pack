"""r2093 ft2 keeper — «NEW_CARD_HOLD 껍데기» 대기 카드는 고르지 않는다 + 건너뜀 1줄 (반례 ①~⑤ · 변이 M1·M2).
대역 = r1871 world(r1812 keeper_world 임시 root·git·가짜 tmux·launch·record) · 껍데기 = 실사건 13줄 꼴.
실 tmux·명부·카드·설치 0 · sleep 0. 기준판 = ① ② ③ ④ Red(껍데기를 보통 대기 카드로 고름).
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2093_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
SH, A, B, Z = "v65-gpu-connect-timeout-7s", "r9001-a", "r9002-b", "w9003-plain"
KN = "adapters/pi/keeper_next.py"
ROOT = "design/harness/indices/대기/%s.md"
SHELL13 = ("# 인덱스: %s — 끝: GPU 연결 7초 상한\n<!-- ledger: design/teams/v65/GOAL.md -->\n\n## 골 원문\n골 1줄\n\n"
           "## 배경\n껍데기 · planner 배분 전\n\n## 계약\n- 배분 뒤 채움\n\n## 상태\n- 대기(NEW_CARD_HOLD · 껍데기 · 착수 0 · 배분 = planner master)\n")
HEAD = "# 인덱스: %s\n- 긴급: 예\n- 상태: 대기(NEW_CARD_HOLD · 껍데기 · 착수 0)\n- 배정: 없음\n- 선행: 없음\n"
SKIP = "NEXT-SKIP harness %s 건너뜀 — NEW_CARD_HOLD 껍데기"


def world(tmp, mp, ft2, shells, cards=None):
    w = base.world(tmp, mp, cards, ft2=ft2, enable=False)
    w.commit("byz", {ROOT % s: body % s for s, body in shells.items()}, "main")
    w.enable()
    return w


def none_picked(w, k=None):
    lines = w.round(k)
    assert base.launched(w) == [] and base.count(w, "accept", SH) == 0 and not (w.state / "card-assign" / (SH + ".json")).exists(), base.launched(w)
    return lines


def c1(tmp, mp, ft2):   # ① 껍데기만 · 빈 석 1 → 배정 0 · 나노 열기 0
    none_picked(world(tmp, mp, ft2, {SH: SHELL13}))


def c2(tmp, mp, ft2):   # ② 껍데기(긴급 없음 · 이름순 먼저) + 보통 카드 1 → 보통 카드만
    w = world(tmp, mp, ft2, {SH: SHELL13}, {Z: ""})
    w.round()
    assert base.launched(w) == [Z] and base.count(w, "accept", SH) == 0, base.launched(w)


def c3(tmp, mp, ft2):   # ③ 머리 «- 상태: 대기(NEW_CARD_HOLD · …)» (긴급 예) → 배정 0
    none_picked(world(tmp, mp, ft2, {SH: HEAD}))


def c4(tmp, mp, ft2):   # ④ ① 의 keeper 기록에 건너뜀 1줄 · 두 번째 고르기(같은 keeper·새 keeper)에서 늘지 않음
    w = world(tmp, mp, ft2, {SH: SHELL13})
    k = w.keeper()
    none_picked(w, k)
    base.close(w, base.W2)   # 두 번째 닫기 = 닫기 뒤 pick 한 번 더
    lines = none_picked(w, k)
    assert lines.count(SKIP % SH) == 1, lines
    assert (SKIP % SH) not in none_picked(w)


def c5(tmp, mp, ft2):   # ⑤ 표식 없는 카드 2장(긴급 1 · 보통 1) → 긴급 먼저(기준판과 같음)
    w = world(tmp, mp, ft2, {}, {A: "", B: "- 긴급: 예\n"})
    w.round()
    assert base.launched(w) == [B], base.launched(w)


def cR1(tmp, mp, ft2):   # R1 (DA #313535) 표식 두 꼴 없이 «- 배정: 대기(껍데기)» 만 → 기준판처럼 배정 1(기존 배정 사유 불변)
    w = world(tmp, mp, ft2, {}, {"r9901-plain": "- 배정: 대기(껍데기)\n"})
    lines = w.round()
    assert base.launched(w) == ["r9901-plain"] and not any("건너뜀" in x for x in lines), (base.launched(w), lines)


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "R1": cR1}
MUTANTS = {"M1": ("if any(x.startswith(SHELL) for x in lines):", "if False:", ("①", "②", "③")),
           "M2": ('k.log("NEXT-SKIP", team, "%s 건너뜀 — NEW_CARD_HOLD 껍데기" % stem) or ', "", ("④",))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](tmp_path, monkeypatch, kw.FT2)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        (tmp_path / case / "m").mkdir(parents=True), (tmp_path / case / "o").mkdir()
        with pytest.raises(AssertionError):
            CASES[case](tmp_path / case / "m", monkeypatch, tree)
        CASES[case](tmp_path / case / "o", monkeypatch, kw.FT2)   # 원본으로 같은 사례 1회 더 = PASS
