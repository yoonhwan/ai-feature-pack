"""ft2 재개 1건 시험의 변이 절 (r1727 · 시험 줄 상한 200 으로 test_core_team_reopen.py 에서 나눔 · 단언·사례 그대로).
변이(사본만) M1~M10 → 대응 사례 = 원 파일 docstring 대응표 · 사례 함수·_core 는 원 파일을 경로로 읽어 그대로 쓴다."""
import importlib.util
import os
import shutil
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("ft2_test_ro_cases", os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "test_core_team_reopen.py"))
_C = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_C)
CORE, _core = _C.CORE, _C._core
_r1, _r2, _r2c, _r2cu, _r2d, _r2r, _r2l, _r3sk, _r5, _a7_8 = (_C._r1, _C._r2, _C._r2c, _C._r2cu, _C._r2d, _C._r2r,
                                                              _C._r2l, _C._r3sk, _C._r5, _C._a7_8)

MUTANTS = (
    ("M1", "reopen.py", "if row is not None:", "if False:", (_r2, _r2c)),
    ("M2", "reopen.py", "dict.fromkeys(rows)", "rows", (_r5,)),
    ("M3", "record.py", 'elif kind == "reopen" and work:', "elif False:", (_r1, _r2c, _r2r)),
    ("M4", "reopen.py", "if self.lc._dormant_key() not in", "if False and self.lc._dormant_key() not in", (_r2d,)),
    ("M5", "reopen.py", "stale = self._current(revision, records)   # 저장 키도", "stale = None   # 저장 키도", (_r3sk,)),
    ("M6", "reopen.py", 'if seen == "absent":', 'if seen != "alive":', (_r2cu,)),
    ("M7", "record.py", 'done[rec["work"]] = {"attempt": rec.get("ack")', '_ = {"attempt": rec.get("ack")', (_r2r,)),
    ("M8", "journal.py", 'if done is None and work in (state.get("lifted") or {}):', "if False:", (_r2l,)),
    ("M9", "reopen.py", "if receipt != str(revision):", "if False:", (_a7_8,)),
    ("M10", "reopen.py", '"dispatched": works.get(command) in sent', '"dispatched": False', (_r5,)),
)

@pytest.mark.parametrize("label,name,old,new,cases", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_break_their_cases(tmp_path, label, name, old, new, cases):
    copy = Path(shutil.copytree(CORE, tmp_path / "core"))
    text = (copy / name).read_text(encoding="utf-8")
    assert text.count(old) == 1, label
    (copy / name).write_text(text.replace(old, new, 1), encoding="utf-8")
    mutant = _core(str(copy), "ft2_mut_ro_%s_" % label)
    for idx, case in enumerate(cases):
        with pytest.raises((AssertionError, KeyError, TypeError)):
            case(tmp_path / ("run%d" % idx), mutant)
