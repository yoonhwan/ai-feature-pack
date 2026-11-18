"""r2247 — keeper pre_attempt 의 base 존재 확인 = git_local(로컬 객체만 · lazy fetch 0).

대역 = test_keeper_git_no_lazy_fetch.World(bare 원격 + blob:none 클론 · 느린 upload-pack 기록 · git 자식 env 기록).

| 칸 | 입력 | 기대 |
|---|---|---|
| ① | partial clone · base = 리포에도 원격에도 없는 sha · 착지 sha 는 ref 의 조상 | 시각 비교 길 · upload-pack 0줄 · 1초 안 (기준판 = upload-pack 1줄 이상 · Red) |
| ② | ①과 같음 · 실 Keeper.call(주입 시계 · upload-pack 대역 8초 · call 상한 7초) | Ungraded 0 · «git 7초 넘음» 0줄 · 시각 비교 글자 (기준판 = Ungraded + 그 줄 1 · Red) |
| ③ | base 로컬 · 착지 sha 가 base 의 조상 | «옛 착지 줄(attempt 전) <sha8>» · upload-pack 0줄 (기준판과 같음) |
| ⑤ | git_local 안에서 self.git 이 예외 | 예외 그대로 · self.env 에 GIT_NO_LAZY_FETCH 없음 |
| M1 | pre_attempt 확인을 self.git 으로 되돌림 | ① FAIL · 원본 PASS |
| M2 | git_local 대신 self.env 에 GIT_NO_LAZY_FETCH=1 영구 | ⑤ FAIL · 원본 PASS |
"""
import importlib.util
import shutil
import time
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
LAND_PY = "adapters/pi/keeper_land.py"
KEEPER_PY = "adapters/pi/keeper.py"
TEAM, WORK = "harness", "r9300"
LINE = 'have = self.git_local(repo, "cat-file", "-e", base)[0] if base else 0'


def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


BASE = _mod(HERE / "test_keeper_git_no_lazy_fetch.py", "r2247_base_world")


def _land(ft2=FT2):
    return _mod(Path(ft2) / LAND_PY, "r2247_land_%d" % id(ft2))


def pre(w, land, sha, base, at):
    k = BASE.keeper(w, land)
    return k, k.pre_attempt(TEAM, WORK, w.pc, sha, {"base_sha": base, "at": at})


# ── ① partial clone · 어디에도 없는 base → 시각 비교 길 · lazy fetch 0
def test_1_base_absent_local_only(w, land=_land):
    k = BASE.keeper(w, land())
    t0 = time.monotonic()   # 재는 구간 = pre_attempt 호출 하나(모듈 로드·대역 생성 밖)
    out = k.pre_attempt(TEAM, WORK, w.pc, w.c1, {"base_sha": w.hidden, "at": "2030-01-01T00:00:00"})
    el = time.monotonic() - t0
    assert out == "옛 착지 줄(attempt 전 · 다른 repo 시각) " + w.c1[:8], out
    assert w.upn() == 0, w.up.read_text()
    assert el <= 1.0, el


# ── ② 실 Keeper.call · 느린 upload-pack(8초) · 상한 7초
def test_2_real_call_no_ungraded(w, ft2=FT2):
    slow = w.tmp / "slow-upload-pack.sh"
    slow.write_text('#!/bin/sh\necho x >> %s\nsleep 8\nexec "$(git --exec-path)/git-upload-pack" "$@"\n' % w.up, encoding="utf-8")
    slow.chmod(0o755)
    BASE._run([BASE.GIT, "-C", w.pc, "config", "remote.origin.uploadpack", slow], w.env)
    kmod = _mod(Path(ft2) / KEEPER_PY, "r2247_keeper_%d" % id(ft2))
    clock = [1_800_000_000.0]
    k = kmod.Keeper(str(w.pc), env=dict(w.env), now=lambda: clock[0])   # 주입 시계(벽시계 0)
    k.at, k.at_work = TEAM, WORK
    out = k.pre_attempt(TEAM, WORK, str(w.pc), w.c1, {"base_sha": w.hidden, "at": "2030-01-01T00:00:00"})
    assert out == "옛 착지 줄(attempt 전 · 다른 repo 시각) " + w.c1[:8], out
    assert [x for x in k.lines if "7초 넘음" in x] == [], k.lines
    assert w.upn() == 0, w.up.read_text()


# ── ③ base 로컬 · 착지 sha 가 base 의 조상 → 옛 줄 · lazy fetch 0
def test_3_base_local_ancestor(w, land=_land):
    base = w.local("base-local")   # pc 안 커밋 = 진짜 로컬 객체 · c1 의 자식
    w.clear()
    k, out = pre(w, land(), w.c1, base, "2030-01-01T00:00:00")
    assert out == "옛 착지 줄(attempt 전) " + w.c1[:8], out
    assert w.upn() == 0, w.up.read_text()


# ── ⑤ git_local 안 예외 → 그대로 · env 되돌림
def test_5_exception_restores_env(w, land=_land):
    k = BASE.keeper(w, land(), env=dict(w.env))
    k.exc = RuntimeError("끊김 예외 대역")
    with pytest.raises(RuntimeError):
        k.pre_attempt(TEAM, WORK, w.pc, w.c1, {"base_sha": w.hidden, "at": "2030-01-01T00:00:00"})
    assert "GIT_NO_LAZY_FETCH" not in k.env, k.env.get("GIT_NO_LAZY_FETCH")


# ── 변이 M1 · M2 — 사본 1곳만 바꿈 → 그 칸 FAIL · 같은 칸을 원본으로 1회 더 = PASS(반대 결과 대조)
MUTANTS = {
    "M1": (LINE, LINE.replace("self.git_local(", "self.git("), test_1_base_absent_local_only),
    "M2": (LINE, LINE.replace('self.git_local(repo, "cat-file"', 'self.env.update(GIT_NO_LAZY_FETCH="1") or self.git(repo, "cat-file"'),
           test_5_exception_restores_env),
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    old, new, case = MUTANTS[name]
    copy = tmp_path / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / LAND_PY).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, text.count(old))
    (copy / LAND_PY).write_text(text.replace(old, new), encoding="utf-8")
    mutant = _land(copy)
    with pytest.raises(AssertionError):
        case(BASE.World(tmp_path / "mut"), lambda: mutant)
    case(BASE.World(tmp_path / "orig"), _land)   # 원본 = PASS


@pytest.fixture()
def w(tmp_path):
    return BASE.World(tmp_path)
