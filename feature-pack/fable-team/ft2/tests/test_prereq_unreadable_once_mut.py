"""ft2 keeper 선행불명 변이 M39·M40·M41·M56·M57·M58 — 사례·세계·MUTANTS 는 `test_prereq_unreadable_once.py` 그대로 읽고 ft2 사본에서만 고친다
(카드 r2212 · 파일 하나 35초 안).
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent


def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pu = _mod("prereq_unreadable_once_cases_mut", HERE / "test_prereq_unreadable_once.py")
kw, MUTANTS, run = pu.kw, pu.MUTANTS, pu.run


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    path, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(cases):
        with pytest.raises(AssertionError):   # 변이 = 그 사례가 무너진다
            run(case, tmp_path / ("w%d" % i), monkeypatch, tree)
