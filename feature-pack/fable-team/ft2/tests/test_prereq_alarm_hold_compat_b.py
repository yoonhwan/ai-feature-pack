"""ft2 keeper 선행 줄 쪽지 ㊵더(뒤) — 앞 카드에서 무거운 두 칸(㉟파 15초·㉟거 10초)만 여기서 돈다
(카드 ft2-prereq-alarm-hold · `test_prereq_alarm_hold_compat.py` 와 같은 칸을 파일 70초 상한 때문에 나눴다).

사례·세계는 `test_prereq_alarm_hold.py` 그대로 · 세 표식 0 · 팀장 있음 = 앞 카드 시험 rc0.
"""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ah = _mod("prereq_alarm_hold_cases", HERE / "test_prereq_alarm_hold.py")
pu = ah.pu
HERE_CASES = ("㉟파", "㉟거")


def c_deo(tmp, mp, mk):   # ㊵더(뒤) 앞 카드 무거운 두 칸 그대로 rc0
    for i, name in enumerate(HERE_CASES):
        pu.run(name, tmp / ("p%d" % i), mp)


def test_deo(tmp_path, monkeypatch):
    c_deo(tmp_path, monkeypatch, ah.mkf(monkeypatch))
