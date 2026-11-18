"""r1871 ft2 keeper 다음 카드 변이 시험 — 파일을 나눈 까닭 = 사례 묶음과 변이 묶음이 각각 70초 안에 끝나게.

사례·대역·변이 정의(MUTANTS · KN · run · kw)는 `test_pi_keeper_next_card_r1871.py` 한 곳에 있다(사례 = 그 파일이 돈다 · 여기는 사본을 만들어 1칸씩 깬다).
변이 1칸 = ft2 사본(copytree) + 잡는 사례 1개가 FAIL + 원본으로 같은 사례 1회 PASS.
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("keeper_next_r1871_cases", str(Path(__file__).with_name("test_pi_keeper_next_card_r1871.py")))
cases = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cases)
MUTANTS, KN, run, kw = cases.MUTANTS, cases.KN, cases.run, cases.kw


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
