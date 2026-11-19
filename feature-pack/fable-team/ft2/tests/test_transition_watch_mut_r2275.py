"""r2275 변이 M1~M3 — ft2 사본에서만 · 변이마다 원본으로 같은 사례 1회 더 (자매 = test_transition_watch_r2275.py · 70초 나눔).
M1 위임 칸도 알림 → ① FAIL · M2 선행 판정이 land_kind(구현 착지)를 안 부름 → ③ FAIL ·
M3a 지문에서 날짜를 뺌 → ⑦ⓐ 다음 날 칸 FAIL · M3b 지문(묶음 열쇠)에 카드 이름을 넣음 → ⑦ⓑ FAIL(1통 아님).
"""
import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2275_cases", str(Path(__file__).with_name("test_transition_watch_r2275.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
MUTANTS = {
    "M1": ([("        if items and not row[4]:", "        if items:")], T.c1),
    "M2": ([(' or s.impl(p) for p in pre)', ' for p in pre)')], T.c3),
    "M3a": ([('% (row[0], team, day, hashlib', '% (row[0], team, "-", hashlib')], T.c7a),
    "M3b": ([('hits.setdefault("%s|%s" % (c["team"], got[0][1]), [])', 'hits.setdefault("%s|%s|%s" % (c["team"], got[0][1], c["stem"]), [])')], T.c7b),
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    pairs, case = MUTANTS[name]
    T.mutant(tmp_path, monkeypatch, pairs, case)
