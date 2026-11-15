"""카드 ft2-done-seat-short-idle 변이 시험 — 파일을 나눈 까닭 = 사례 묶음과 변이 묶음이 각각 70초 안에 끝나게.

사례·대역·변이 정의는 `test_done_seat_short_idle.py` 한 곳에 있다(사례 = 그 파일이 돈다 · 여기는 사본을 만들어 1칸씩 깬다).
변이 1칸 = ft2 사본(copytree) + 잡는 사례 1~2개가 FAIL + 원본 사본에서 같은 사례 1회 PASS.
이 파일 = M20·M21·M22·M44·M45 · 자매 파일 `test_done_seat_short_idle_mutants_b.py` = M51~M55(칸을 나눠 파일마다 70초 안).
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("done_seat_cases_pA", str(Path(__file__).with_name("test_done_seat_short_idle.py")))
cases = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cases)
world, MUTANTS, FT2 = cases.world, cases.MUTANTS, cases.FT2
NAMES = ("M20", "M21", "M22", "M44", "M45")


@pytest.mark.parametrize("name", [n for n in MUTANTS if n in NAMES])
def test_mutant(name, tmp_path, monkeypatch):
    """변이 사본 = 잡는 사례가 FAIL · 원본 사본 = 같은 사례 PASS(양성)."""
    path, old, new, picked = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old, text.count(old))
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(picked):
        (tmp_path / ("f%d" % i)).mkdir(exist_ok=True)
        with pytest.raises(AssertionError):
            case(world(tmp_path / ("f%d" % i), monkeypatch, tree))
    (tmp_path / "ok").mkdir(exist_ok=True)
    picked[0](world(tmp_path / "ok", monkeypatch))
