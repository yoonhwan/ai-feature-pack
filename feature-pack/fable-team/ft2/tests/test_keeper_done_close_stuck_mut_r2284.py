"""r2284 변이 M1~M3 — 사본 ft2 에서만 · 변이마다 원본으로 같은 사례 1회 더 (자매 = test_keeper_done_close_stuck_r2284.py · 70초 나눔).
M1 stage_card 뒤 캐시 지우기 끔 → ① FAIL · M2 표본 수명 «직전 바퀴» 로 되돌림 → ② FAIL · M3 표본 수명 상한 끔 → ③ FAIL.
"""
import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2284_cases", str(Path(__file__).with_name("test_keeper_done_close_stuck_r2284.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
KP, KS = "adapters/pi/keeper.py", "adapters/pi/keeper_settle.py"
KEEP = ' and now - v.get("at", 0) > SAMPLE_KEEP]'
MUTANTS = {
    "M1": (KP, [("        if out:   # r2284 C1", "        if False:   # r2284 C1")], T.c1),
    "M2": (KS, [(KEEP, "]")], T.c2),   # 수명 = 직전 바퀴만(기준판 꼴)
    "M3": (KS, [('(prev is None or v.get("at", 0) < prev)' + KEEP, "False]")], T.c3),   # 상한 끔 = 오래된 표본도 남김
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, pairs, case = MUTANTS[name]
    T.mutant(tmp_path, monkeypatch, rel, pairs, case)
