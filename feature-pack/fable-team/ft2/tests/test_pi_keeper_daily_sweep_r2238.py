"""r2238 keeper — 하루 정리 생존 검사(state/disk-alarm.log 나이 ≥ 2일 = 판정 불가 1줄 + [긴급] 1통 · 하루 1회).
반례 ①~④(⑤ = 기존 test_pi_keeper_* 결과 수 대조 · 바퀴 초 늘어남 < 1초는 ①④ 가 잰다) · 변이 M1 M2.
r1812 대역(World) 재사용 · 가짜 mbox(인자 기록) · mtime = os.utime · 실 launchd·실 mbox 0 · sleep 0.
두 경로 = /tmp · /private/tmp(있으면) · R2238_FT2=<ft2 폴더> 로 대상 바꿈(기준판 대조).
"""
import datetime
import importlib.util
import os
import shutil
import tempfile
import time
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r2238", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
World = kw.World
FT2 = Path(os.environ.get("R2238_FT2") or kw.FT2)
HEAD, DAY = "판정 불가 하루 정리", 86400
BASES = [b for b in ("/tmp", "/private/tmp") if os.path.isdir(b)]


def log_path(w):
    return w.state / "disk-alarm.log"
def age(w, sec):   # disk-alarm.log mtime = 주입 시계 − sec
    os.utime(log_path(w), (w.t - sec, w.t - sec))
    return w.t - sec
def daily(lines):
    return [x for x in lines if x.startswith(HEAD)]
def sends(w):   # 가짜 mbox 기록 중 하루 정리 쪽지
    return [x for x in kw._lines(str(w.mbox) + ".log") if x.startswith("send ") and "하루 정리" in x]
def watch(k):   # O3 — keeper 바깥 호출 기록 + 검사 초(바퀴당 1초 상한)
    calls, spent, g = [], [], type(k).__init__.__globals__
    real_call, real_check = k.call, g["daily"].check
    k.call = lambda argv, *a, **b: (calls.append(list(argv)), real_call(argv, *a, **b))[1]
    def timed(kk, *a, **b):
        t = time.monotonic()
        try:
            return real_check(kk, *a, **b)
        finally:
            spent.append(time.monotonic() - t)
    g["daily"].check = timed
    return calls, spent
def no_side(w, calls, mtime):   # O3 쓰기 0 · launchctl·정리 도구 부름 0
    assert os.path.getmtime(log_path(w)) == mtime
    assert not [c for c in calls if any(("launchctl" in x or "sweep" in x or "disk-alarm" in x) for x in c[:2])], calls   # 명령·스크립트 칸만(쪽지 본문 제외)


def c1(w):   # ① mtime 10일 전 → 줄 1 · [긴급] 1통 · 기준판 = 0줄(Red)
    m = age(w, 10 * DAY + 5)
    k = w.keeper()
    calls, spent = watch(k)
    lines = w.round(k)
    last = datetime.datetime.fromtimestamp(m).strftime("%Y-%m-%d %H:%M")
    assert daily(lines) == ["%s 멈춤 10일(state/disk-alarm.log · 마지막 %s)" % (HEAD, last)], lines
    got = sends(w)
    assert len(got) == 1 and got[0].startswith("send M-harness ft2-keeper [긴급] 하루 정리 멈춤 10일"), got
    no_side(w, calls, m)
    assert len(spent) == 1 and spent[0] < 1.0, spent
def stats(k):   # O4 — 이 바퀴 stat 부른 횟수(표식 오늘 = 0)
    g, got = type(k).__init__.__globals__, []
    real = g["daily"].check
    g["daily"].check = lambda kk: real(kk, stat=lambda p: (got.append(p), os.stat(p))[1])
    return got
def c2(w):   # ② 같은 판 같은 날 바퀴 2번째 → 줄 0 · 쪽지 0(하루 1통) · 검사 0회
    c1(w)
    k = w.keeper()
    got = stats(k)
    lines = w.round(k)
    assert daily(lines) == [], lines
    assert len(sends(w)) == 1, sends(w)
    assert got == [], got
def c5(w):   # ② 경계 — 1바퀴 notify False(한 바퀴 3통 상한 다 참) → 줄 1 · 쪽지 0 / 2바퀴 → 줄 0 · 쪽지 1 / 3바퀴 → 검사 0
    age(w, 10 * DAY + 5)
    k = w.keeper()
    k.notify_used = 3   # 상한 다 참 = budget False → notify False(지문 0)
    lines = w.round(k)
    assert len(daily(lines)) == 1 and sends(w) == [], (lines, sends(w))
    lines = w.round()
    assert daily(lines) == [] and len(sends(w)) == 1, (lines, sends(w))
    k = w.keeper()
    got = stats(k)
    lines = w.round(k)
    assert daily(lines) == [] and len(sends(w)) == 1 and got == [], (lines, got)
def c3(w):   # ③ 파일 없음 → «없음» 1줄 · 1통
    log_path(w).unlink()
    k = w.keeper()
    calls, _ = watch(k)
    lines = w.round(k)
    assert daily(lines) == ["%s 멈춤 -일(state/disk-alarm.log · 마지막 없음)" % HEAD], lines
    assert len(sends(w)) == 1, sends(w)
    assert not log_path(w).exists()
def c3s(w):   # ③ 가짜 stat 실패 → «판독 실패» 1줄 · 쪽지 0
    k = w.keeper()
    g = type(k).__init__.__globals__
    real = g["daily"].check
    def boom(path):
        raise PermissionError(13, "fake", path)
    g["daily"].check = lambda kk: real(kk, stat=boom)
    lines = w.round(k)
    assert daily(lines) == ["%s 판독 실패" % HEAD], lines
    assert sends(w) == [], sends(w)
def c4(w):   # ④ mtime 1시간 전 → 줄 0 · 쪽지 0 · keeper 로그 바이트 기준판(검사 0)과 같음
    def run(off):
        age(w, 3600)
        k = w.keeper()
        calls, spent = watch(k)
        if off:
            type(k).__init__.__globals__["daily"].check = lambda kk: None
        lines = w.round(k)
        return [x for x in lines if not x.startswith(("ROUND", "SLOW-CELL"))], kw._lines(str(w.mbox) + ".log"), calls, spent
    base_lines, base_mbox, _, _ = run(True)
    (w.state / "ft2-keeper" / "state.json").unlink()   # 같은 판을 처음 바퀴로 되돌림(표식 0)
    lines, mbox, calls, spent = run(False)
    assert daily(lines) == [] and sends(w) == [], lines
    assert lines == base_lines and mbox == base_mbox * 2, (lines, base_lines)
    no_side(w, calls, w.t - 3600)
    assert len(spent) == 1 and spent[0] < 1.0, spent
CASES = {"c1": c1, "c2": c2, "c3": c3, "c3s": c3s, "c4": c4, "c5": c5}


def world(base, monkeypatch, tree=FT2):
    tmp = Path(tempfile.mkdtemp(prefix="r2238.", dir=base))
    (tmp / "w").mkdir()
    return tmp, World(tmp / "w", monkeypatch, tree)


@pytest.mark.parametrize("base", BASES)
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, base, monkeypatch):
    tmp, w = world(base, monkeypatch)
    try:
        CASES[name](w)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def mutant(monkeypatch, old, new):
    tmp = Path(tempfile.mkdtemp(prefix="r2238m.", dir=BASES[0]))
    tree = tmp / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = tree / "adapters/pi/keeper_daily.py"
    text = path.read_text(encoding="utf-8")
    assert text.count(old) == 1
    path.write_text(text.replace(old, new), encoding="utf-8")
    (tmp / "w").mkdir()
    return tmp, World(tmp / "w", monkeypatch, tree)


def test_mutant_m1(monkeypatch):   # M1 하루 1회 표식 뺌 → ② 2번째 바퀴 검사 1회(FAIL) · 원본 = 0회(test_case c2)
    tmp, w = mutant(monkeypatch, '    if k.state.get("daily_sweep") == day:\n        return None\n', "")
    try:
        with pytest.raises(AssertionError):
            c2(w)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_mutant_m3(monkeypatch):   # M3 표식 먼저 쓰기(보정 전 꼴) → c5 2바퀴 쪽지 0(FAIL) · 원본 = 1통(test_case c5)
    old = '    if k.state.get("daily_sweep") == day:\n        return None\n'
    tmp, w = mutant(monkeypatch, old, old + '    k.state["daily_sweep"] = day\n')
    try:
        with pytest.raises(AssertionError):
            c5(w)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_mutant_m2(monkeypatch):   # M2 나이 문턱 0 → ④ 1줄(FAIL) · 원본 = 0(test_case c4)
    tmp, w = mutant(monkeypatch, "age < threshold(k.env)", "age < 0")
    try:
        with pytest.raises(AssertionError):
            c4(w)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
