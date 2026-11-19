"""r2287 변이 M1~M3 — 사본 ft2 에서만 · 변이마다 원본으로 같은 사례 1회 더 (자매 = test_keeper_b1_budget_gate_r2287.py · 70초 나눔).
M1 da_judge 를 주입 손 대신 subprocess.run 직접으로 되돌림 → ② FAIL · M2 남은 몫 문턱 7초 → 0초 → ① FAIL · M3 top 칸에서 주입 손 호출을 뺌 → ④ FAIL.
"""
import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2287_cases", str(Path(__file__).with_name("test_keeper_b1_budget_gate_r2287.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
KP, CS = "adapters/pi/keeper.py", "adapters/pi/card_stage.py"
MUTANTS = {
    "M1": (CS, [("p = body and proc([", "p = body and subprocess.run(["),
                 ('"x", lib, stem], 7, input=body.encode())', '"x", lib, stem], input=body.encode(), capture_output=True, timeout=7)')], T.c2),
    "M2": (KP, [("            if left is not None and left < CALL_S:\n", "            if left is not None and left < 0:\n")], T.c1),
    "M3": (KP, [("                self.note(head(*args), self.now() - at)\n", "                pass\n")], T.c4),
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, pairs, case = MUTANTS[name]
    T.mutant(tmp_path, monkeypatch, rel, pairs, case)
