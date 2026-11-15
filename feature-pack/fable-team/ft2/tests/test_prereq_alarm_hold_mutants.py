"""ft2 keeper 선행 줄 쪽지 변이 M85~M91 — 사례·세계는 `test_prereq_alarm_hold.py` 그대로 쓰고 ft2 사본에서만 고친다
(카드 ft2-prereq-alarm-hold · DA 312085 «새 시험은 쪼개 70초 안»).

원본 고침 파일은 손대지 않는다: 사본에 변이 한 줄을 넣고 → 그 변이가 잡혀야 하는 사례가 FAIL 하는지 본다.
"""
import importlib.util
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent


def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ah = _mod("prereq_alarm_hold_cases", HERE / "test_prereq_alarm_hold.py")


@pytest.mark.parametrize("name", list(ah.MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    ah.run_mutant(name, tmp_path, monkeypatch)
