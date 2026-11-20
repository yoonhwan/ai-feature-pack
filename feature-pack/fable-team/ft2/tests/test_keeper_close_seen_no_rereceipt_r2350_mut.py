"""r2350 변이 M1~M6 — 사본 ft2 에서만 · 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조).
자매 = test_keeper_close_seen_no_rereceipt_r2350.py(반례 ①~⑩ · 70초 나눔).
M1 seen 일 때도 영수 호출 되살림 → ① FAIL · M2 K2(다음 빔)에서 handled 안 씀 → ⑤ FAIL · M3 seen 일 때 reconcile 빼고 handled 만 → ① FAIL(record 0)
M4 seen 없을 때도 건너뜀 → ③ FAIL(영수 0) · M5 done 키 검사 지움 → ⑨ FAIL(영수 0) · M6 CLOSE-NEXT.enabled 검사 지움 → ⑩ FAIL(영수 0).
"""
import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2350_cases", str(Path(__file__).with_name("test_keeper_close_seen_no_rereceipt_r2350.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
GUARD = '    if seen is not None and seen_no_receipt(k, team, work, attempt, stem, book.get("done") or {}):'
MARK = ('    mark = os.path.join(k.root, ".fable-team", "teams", team, "CLOSE-NEXT.enabled")\n'
        '    if not os.path.exists(mark):\n        return False')
HANDLED = '            k.state["handled"]["%s|%s@%s" % (team, work, attempt)] = k.stamp()'
MUTANTS = {"M1": [(GUARD, "    if False:")],                                     # 영수 되살림 = seen 이어도 core 영수 1회
           "M2": [(HANDLED, "            pass")],                                # K2 에서 handled 안 씀
           "M3": [("return reconcile(k, team, work, attempt, stem, nh, None)",
                   'k.state["handled"]["%s|%s@%s" % (team, work, attempt)] = k.stamp()')],   # reconcile 빼고 handled 만
           "M4": [(GUARD, "    if True:")],                                      # seen 없을 때도 건너뜀
           "M5": [('    return not stem or "close:%s:keeper:%s@%s" % (team, work, attempt) in done', "    return True")],
           "M6": [(MARK, "    if False:\n        return False")]}                # 표식 검사 지움
CASE = {"M1": T.c1, "M2": T.c5, "M3": T.c1, "M4": T.c3, "M5": T.c9, "M6": T.c10}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    T.mutant(tmp_path, monkeypatch, MUTANTS[name], CASE[name])
