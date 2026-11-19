"""r2276 승계 갈래 변이 M1~M3 (카드 «변이» · 사본에서만 · 변이마다 원본으로 같은 사례 1회 더) — 사례 파일과 70초 나눔.
M1 C2 보존 건너뜀(r2280 = 로컬 keep ref) → ①′ FAIL · M2 Working 재확인 뺌 → ② FAIL · M3 승계 키 = S4 키(reassigned) → ⑦′ FAIL.
M4(DA#28 H1) keeper_stall check 의 표식 갈래 줄 끔 → ②ⓓ FAIL.
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("r2276_cases_for_mut", str(FT2 / "tests" / "test_pi_keeper_succeed_r2276.py"))
S = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(S)
KS, KST = "adapters/pi/keeper_succeed.py", "adapters/pi/keeper_stall.py"
MUTANTS = {"M1": ((("why, name = self.keep(work, tree, attempt)", 'why, name = "", ""'),), S.c1b),
           "M2": ((("ok = k.stall.guard(team, work, holder, rows)", "ok = True"),), S.c2),
           "M3": ((('SLOT, CAP = "succeeded", 3', 'SLOT, CAP = "reassigned", 3'),
                   ('key, day = "%s|%s|g%d" % (team, work, gen), k.stamp()[:10]', 'key, day = "%s|%s" % (team, work), k.stamp()[:10]')), S.c7b),
           "M4": ((("if (team, work) in getattr(k, \"succeeding\", ()):", "if False:"),), S.c2d, KST)}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    pairs, case, ks = (MUTANTS[name] + (KS,))[:3]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / ks).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / ks).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(S.world(tmp_path / "w1", monkeypatch, tree))
    case(S.world(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
