"""r2352 변이 M1~M5 — 사본 ft2 에서만 · 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조).
자매 = test_keeper_superseded_ending_complete_r2352.py(반례 ①~⑦ · 70초 나눔).
M1 superseded 갈래 complete 호출 삭제 → ① FAIL · M2 관문 건너뜀 → ② FAIL · M3 되찾기 삭제(keeper.py) → ③ FAIL
M4 재시도 상한 삭제 → ④ FAIL · M5 suspended 도 complete → ⑥ FAIL.
"""
import importlib.util
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("r2352_cases", str(HERE / "test_keeper_superseded_ending_complete_r2352.py"))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
CLOSE, KEEPER = "adapters/pi/keeper_close.py", "adapters/pi/keeper.py"
CALL = ('            if ending[0] == "superseded":\n'
        '                self.superseded_complete(team, work, attempt, " · ".join(ending[1:]))')
GATE = "        card = followup.gate(self, team, work, attempt)"
BACK = "        backed = self.superseded_back(team, proj, latest) if self.sock and not self.halt else None"
CAP = "            if book.get(key, 0) >= SUPERSEDED_CAP:"
MUTANTS = {"M1": [(CLOSE, CALL, "            pass")],                                     # 대체 끝 complete 0 = 지금(고치기 전) 그대로
           "M2": [(CLOSE, GATE, '        card = "gate-skip"')],                          # 관문 건너뜀
           "M3": [(KEEPER, BACK, "        backed = None")],                              # 되찾기 삭제
           "M4": [(CLOSE, CAP, "            if False:")],                                # 재시도 상한 삭제
           "M5": [(CLOSE, '            if ending[0] == "superseded":',
                   '            if ending[0] in ("superseded", "suspended"):')]}          # suspended 도 complete
CASE = {"M1": ("①", T.c1), "M2": ("②", T.c2), "M3": ("③", T.c3), "M4": ("④", T.c4), "M5": ("⑥", T.c6)}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    T.mutant(tmp_path, monkeypatch, MUTANTS[name], CASE[name][1], CASE[name][0])
