"""ft2 keeper 선행 줄 쪽지 ㊵더 — 세 표식 0 · 팀장 있음 = 앞 카드(ft2-prereq-unreadable-once) 사례 ㉟가~거 가 전부 그대로 통과한다
(카드 ft2-prereq-alarm-hold · 회귀 고정 칸 · 사례·세계는 `test_prereq_alarm_hold.py` 와 같은 r1871 대역).

이 칸 하나가 56초라 파일을 나눴다(DA 312085 «새 시험은 쪼개 70초 안» — 70초 상한은 한 파일 실행 기준).
여기 = 앞 카드 사례 중 가벼운 칸 · 무거운 칸(㉟파·㉟거)은 `test_prereq_alarm_hold_compat_b.py` 가 돈다.
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


HERE_CASES = [name for name in pu.CASES if name not in ("㉟파", "㉟거")]   # 무거운 두 칸은 _compat_b


def c_deo(tmp, mp, mk):   # ㊵더(앞) 세 표식 0 · 팀장 있음 → 앞 카드 사례 13칸 그대로 rc0
    for i, name in enumerate(HERE_CASES):
        pu.run(name, tmp / ("p%d" % i), mp)


def test_deo(tmp_path, monkeypatch):
    c_deo(tmp_path, monkeypatch, ah.mkf(monkeypatch))
