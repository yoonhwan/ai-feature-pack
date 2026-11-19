"""r2241 keeper — git fetch 가 실패한 리포의 묵은 ref 잠금(.lock · 나이 ≥ 60초)을 «판정 불가» 줄에 원인으로 적는다 · 지우기 0.
반례 ⑤~⑦ · 변이 M3. r1812 대역(World) 재사용 · 실제 git · tmp bare 원격 · mtime = os.utime · sleep 0.
두 경로 = /tmp · /private/tmp(있으면) · R2241_FT2=<ft2 폴더> 로 대상 바꿈(기준판 대조).
"""
import importlib.util
import os
import shutil
import tempfile
import time
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r2241", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
World, _git = kw.World, kw._git
FT2 = Path(os.environ.get("R2241_FT2") or kw.FT2)
FAIL, ALL = "판정 불가 git fetch 실패", "이 바퀴 B1·B2 0"
REF = "refs/remotes/origin/ops/main-base"
ERR = "error: fetching ref %s failed: reference already exists" % REF
BASES = [b for b in ("/tmp", "/private/tmp") if os.path.isdir(b)]


def lock(w, rel, age):   # 그 리포 .git 아래 잠금 파일 + mtime(지금 − age 초)
    p = w.root / ".git" / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("", encoding="utf-8")
    os.utime(p, (time.time() - age, time.time() - age))
    return p
def fake(k, w, err=ERR):   # BYZ 리포의 ls-remote·fetch = rc128 + stderr(가짜 git) · 나머지는 실제
    real = k.call
    k.call = lambda argv, *a, **b: (128, "", err) if argv[:3] == ["git", "-C", str(w.root)] and argv[3:4] in (["ls-remote"], ["fetch"]) else real(argv, *a, **b)
def notes(k):   # lock_note 부른 횟수(⑦ 찾기 0회)
    g, calls = type(k).__init__.__globals__, []
    real = g["kf"].lock_note
    g["kf"].lock_note = lambda *a: (calls.append(a), real(*a))[1]
    return calls
def fails(lines):
    return [x for x in lines if x.startswith(FAIL)]
def c5(w):   # ⑤ 가짜 fetch rc128 + ops/main-base.lock 15분 → 원인 칸 1개 · .lock 남음
    p, k = lock(w, REF + ".lock", 15 * 60 + 5), w.keeper()
    fake(k, w)
    lines = w.round(k)
    assert fails(lines) == ["%s %s — 묵은 ref 잠금 1개(%s.lock 15분) · %s" % (FAIL, w.root, REF, ALL)], lines
    assert p.exists()
def c5r(w):   # ⑤ 실제 git — 원격이 앞서고 ref .lock 15분이 남음 → 실제 fetch 실패 · 원인 칸 1개 · .lock 남음
    w.commit("byz", {"r.txt": "r"}, "ops/main-base")
    p = lock(w, REF + ".lock", 15 * 60 + 5)
    lines = w.round()
    assert fails(lines) == ["%s %s — 묵은 ref 잠금 1개(%s.lock 15분) · %s" % (FAIL, w.root, REF, ALL)], lines
    assert p.exists()
def c6(w):   # ⑥ 같은 실패 · .lock 10초(젊음) 또는 .lock 없음 → 줄 바이트 기준판과 같음
    for age in (10, None):
        p = lock(w, REF + ".lock", age) if age else None
        k = w.keeper()
        fake(k, w)
        lines = w.round(k)
        assert fails(lines) == ["%s %s — %s" % (FAIL, w.root, ALL)], (age, lines)
        p and p.unlink()
def c7(w):   # ⑦ fetch 성공 · 15분짜리 .lock 있음 → 찾기 0회 · 판정 불가 줄 0
    lock(w, "refs/remotes/origin/zzz.lock", 15 * 60)
    k = w.keeper()
    calls = notes(k)
    lines = w.round(k)
    assert not fails(lines) and calls == [] and not any("묵은 ref" in x for x in lines), lines
CASES = {"c5": c5, "c5r": c5r, "c6": c6, "c7": c7}


def world(base, monkeypatch, tree=FT2):
    tmp = Path(tempfile.mkdtemp(prefix="r2241.", dir=base))
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


def test_mutant_m3(monkeypatch):   # M3 keeper 원인 찾기 뺌 → ⑤ 원인 칸 0(FAIL) · 원본 PASS 는 test_case 가 본다
    tmp = Path(tempfile.mkdtemp(prefix="r2241m.", dir=BASES[0]))
    try:
        tree, old = tmp / "m" / "ft2", "kf.lock_note([r for r in (self.root, self.pack) if r in self.stale], self.fetch_err)"
        shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
        text = (tree / "adapters/pi/keeper.py").read_text(encoding="utf-8")
        assert text.count(old) == 1
        (tree / "adapters/pi/keeper.py").write_text(text.replace(old, '""'), encoding="utf-8")
        (tmp / "w").mkdir()
        with pytest.raises(AssertionError):
            c5(World(tmp / "w", monkeypatch, tree))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
