"""r1937 keeper fetch = keeper 가 읽는 ref 만(BYZ main·ops/main-base·directive-roots 표 ref · 팩 main) · --no-tags · 1회 7초 + 재시도 1.
반례 ①~⑥ · 변이 M1~M3 · r1812 대역(keeper_world_r1812.World) 재사용 · 실제 git · tmp bare 원격 · 시험 코드 sleep 0.
④ 느린 원격 = remote.origin.uploadpack 앞에 9초 지연(실제 git-upload-pack) · 7초 상한이면 실패 · 25초 상한이면 성공.
"""
import importlib.util
import shutil
import time
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r1937", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
World, FT2, _put, _git = kw.World, kw.FT2, kw._put, kw._git
KP = "adapters/pi/keeper.py"
FAIL = "판정 불가 git fetch 실패"


def ref(w, name, repo="root"):
    out = kw.subprocess.run(["git", "-C", str(w.tmp / repo), "rev-parse", "-q", "--verify", "refs/remotes/origin/" + name],
                            capture_output=True, text=True, timeout=25)
    return out.stdout.strip()
def c1(w):   # ① main·ops/main-base 갱신 · nano/x·docs/da 안 생김
    w.commit("byz", {}, "nano/x", new=True), w.commit("byz", {}, "docs/da", new=True)
    main, base = w.commit("byz", {"a": "1"}, "main"), w.commit("byz", {"b": "1"}, "ops/main-base")
    lines = w.round()
    assert not [x for x in lines if x.startswith(FAIL)], lines
    assert (ref(w, "main"), ref(w, "ops/main-base"), ref(w, "nano/x"), ref(w, "docs/da")) == (main, base, "", "")
def c2(w):   # ② 표 origin/foo 행 → origin/foo 도 갱신
    w.commit("byz", {}, "foo", new=True)
    _git(w.root, "fetch", "-q", "origin")   # 옛 전부 받기가 남긴 로컬 ref
    _put(w.state / "directive-roots.tsv", "*\t.\torigin/main\td/*/i\nharness\t.\torigin/foo\td/h/i\n")
    foo = w.commit("byz", {"f": "2"}, "foo")
    w.round()
    assert ref(w, "foo") == foo
def c3(w):   # ③ 표 깨짐(UTF-8 아님) → main·ops/main-base 만 받고 바퀴 계속
    (w.state).mkdir(parents=True, exist_ok=True)
    (w.state / "directive-roots.tsv").write_bytes(b"\xff\xfe\x00broken\t")
    main = w.commit("byz", {"a": "3"}, "main")
    lines = w.round()
    assert ref(w, "main") == main and lines[-1].startswith("ROUND") and not [x for x in lines if x.startswith(FAIL)], lines
def c4(w):   # ④ 9초 막히는 원격 → 7초×2 안에 실패 · 판정 불가 1줄 · B1·B2 0
    _git(w.root, "config", "remote.origin.uploadpack", "sleep 9; git-upload-pack")
    at = time.monotonic()
    lines = w.round()
    took = time.monotonic() - at
    bad = [x for x in lines if x.startswith(FAIL)]
    assert took < 7 * 2 + 4 and len(bad) == 1 and str(w.root) in bad[0] and "B1·B2 0" in bad[0], (took, lines)
def c5(w):   # ⑤ 팩 원격엔 main 만 → 팩은 main 만 요청 · rc 0
    sha = w.pack_sha()
    k = w.keeper()
    assert k.fetch_refs(str(w.tmp / "pack")) == ["+refs/heads/main:refs/remotes/origin/main"]
    lines = w.round(k)
    assert ref(w, "main", "pack") == sha and not [x for x in lines if x.startswith(FAIL)], lines
def c6(w):   # ⑥ 원격 새 태그 → 로컬 태그 0(--no-tags)
    w.commit("byz", {"t": "1"}, "main")
    _git(w.tmp / "seed-byz", "tag", "v-r1937"), _git(w.tmp / "seed-byz", "push", "-q", "origin", "v-r1937")
    w.round()
    assert _git(w.root, "tag", "-l") == ""
CASES = {"c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c6": c6}
MUTANTS = {"M1": ('"origin", *self.fetch_refs(repo)', '"origin"', c1),
           "M2": ("timeout=FETCH_S)", "timeout=GIT_S)", c4),
           "M3": ('if repo == self.root and r[1] == "."', "if False", c2)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KP).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w", monkeypatch, tree))
