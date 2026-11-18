"""r2027 ft2 keeper 다음 카드 — 카드 본문 «- 선행:»·«- 배정: 대기(선행» 줄로 막힘 판정 (T1~T6 · 변이 M1·M2).
대역 = r1871 world(r1812 keeper_world 임시 root·git·가짜 tmux·launch·record) · 카드 루트 = 임시 byz 리포 origin/main.
실 리포·실 나노·tmux·명부·mbox·설치 0 · sleep 0. 기준판 = T1·T3·T4 Red(원장 행이 없으면 선행 카드를 고름).
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2027_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
P, DEP = "p1-prereq", "r9001-dep"
KN = "adapters/pi/keeper_next.py"
ROOT = "design/harness/indices/%s/%s.md"


def put(w, stage, stem, head=""):
    w.commit("byz", {ROOT % (stage, stem): "# 인덱스: %s\n%s- 상태: 대기\n" % (stem, head)}, "main")


def blocked(w, why):
    assert base.launched(w) == [] and base.count(w, "accept", P) == 0, base.launched(w)
    assert len(base.notes(w)) == 1 and (" %s 1" % why) in base.notes(w)[0], base.notes(w)


def t1(w):   # T1 선행 r9001 · r9001 = 대기(seat) → 고르지 않음 · why 선행 1
    put(w, "대기", DEP)
    kw._put(w.state / "card-assign" / (DEP + ".json"), {"state": "seat", "seat": "byz-harness-nano-dep#0"})
    w.round()
    blocked(w, "선행")


def t2(w, stage="완성"):   # T2 같은 카드 · r9001 = 완성 → 고름
    put(w, stage, DEP)
    w.round()
    assert base.launched(w) == [P] and base.notes(w) == []


def t2a(w):   # T2′ (DA R1) r9001 = 월별 아카이브/2026-11/ → 고름
    t2(w, "아카이브/2026-11")


def t3(w):   # T3 r 참조 없는 선행 → 고르지 않음 · 판정 불가 로그 1줄
    lines = w.round()
    assert lines.count("판정 불가 harness %s 선행 줄 판독 불가(번호 참조 없음) — 건너뜀 · 고칠 꼴 «- 선행: 없음» 또는 «- 선행: r<번호>»" % P) == 1, lines
    blocked(w, "선행불명")


def t4(w):   # T4 «- 배정: 대기(선행 · …)» → 고르지 않음
    w.round()
    blocked(w, "선행")


def t5(w):   # T5 «- 선행: 없음» · 원장 행 없음 → 고름
    w.round()
    assert base.launched(w) == [P] and base.notes(w) == []


def t6(w):   # T6 원장 reason 선행 · 카드 선행 줄 없음 → 고르지 않음(지금 그대로)
    kw._put(w.state / "card-assign" / (P + ".json"), {"state": "waiting", "reason": "선행", "since": 1.0})
    w.round()
    blocked(w, "선행")


LINE = "- 선행: r9001 착지\n"
CASES = {"T1": (t1, LINE), "T2": (t2, LINE), "T2′": (t2a, LINE), "T3": (t3, "- 선행: #8596 착지\n"),
         "T4": (t4, "- 배정: 대기(선행 · 2026-11-02T10:45:51)\n"), "T5": (t5, "- 선행: 없음\n"), "T6": (t6, "")}
MUTANTS = {"M1": ('if any(s & {"대기", "진행"} for s in seen):', "if False:", "T1"),
           "M2": ('return "선행불명", "번호 참조 없음"   # ④', 'return "", ""   # ④', "T3")}


def run(name, tmp, mp, ft2=kw.FT2):
    case, head = CASES[name]
    w = base.world(tmp, mp, {P: head}, ft2=ft2)
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
