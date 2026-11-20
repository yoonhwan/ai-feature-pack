"""r2284 변이 M1~M2 — 사본 ft2 에서만 · 변이마다 원본으로 같은 사례 1회 더 (자매 = test_keeper_done_close_stuck_r2284.py · 70초 나눔).
M1 stage_card 뒤 캐시 지우기 끔 → ① FAIL · M2 cpu 표본 상한(CPU_SAMPLE_MAX) 끔 → ③(4000초) FAIL.
r2354 K1 이 C2 표본 수명을 좌석 판 대조로 바꾼 뒤의 변이 = 표본 수명 변이 5개는 test_keeper_cpu_sample_visit_gap_r2354.py M1~M5 로 옮겼다.
"""
import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2284_cases", str(Path(__file__).with_name("test_keeper_done_close_stuck_r2284.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
KP, KS = "adapters/pi/keeper.py", "adapters/pi/keeper_settle.py"
MUTANTS = {
    "M1": (KP, [("        if out:   # r2284 C1", "        if False:   # r2284 C1")], T.c1),
    "M2": (KS, [('or now - v.get("at", 0) > CPU_SAMPLE_MAX', "or False")], T.c3),   # r2354 K1 상한 끔 = 오래된 표본도 남김
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, pairs, case = MUTANTS[name]
    T.mutant(tmp_path, monkeypatch, rel, pairs, case)
