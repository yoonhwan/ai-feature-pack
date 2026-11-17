"""ft2 keeper 선행불명 뒤 사례 묶음 — list(CASES)[8:] (㉟자부터 · 뒤에 사례가 늘면 여기서 모은다)
(카드 r2212 · 파일 하나 35초 안 · 세계·CASES·run 은 `test_prereq_unreadable_once.py` 그대로 읽는다).
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


pu = _mod("prereq_unreadable_once_cases_b", HERE / "test_prereq_unreadable_once.py")


@pytest.mark.parametrize("name", list(pu.CASES)[8:])
def test_case(name, tmp_path, monkeypatch):
    pu.run(name, tmp_path, monkeypatch)
