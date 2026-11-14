"""r1975 keeper fetch 대상 — FETCH_TARGETS(리포·ref 고르기) · 판정 대상 나노 가지 · 리포당 5 · 판정 뒤 전체 fetch 백그라운드(기다림 0 · 겹침 0).
반례 ①~⑨ · 변이 M1~M7 · r1812 대역(World) 재사용 · 실제 git · tmp bare 원격 · 시험 코드 sleep 0.
① 기준판 = 이 카드 앞 착지본(BASE) 의 ft2 트리를 git archive 로 꺼내 같은 세계에서 argv 를 기록 → 바이트 비교(임시 경로만 T 로).
⑧ 막힌 원격 = PATH 앞 가짜 git 이 `fetch … origin`(refspec 없음 = 전체) 만 fifo 읽기로 멈춤 · 나머지는 실제 git.
"""
import importlib.util
import os
import plistlib
import re
import shutil
import subprocess
import time
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r1975", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
World, FT2, _git, _put = kw.World, kw.FT2, kw._git, kw._put
BASE, PL = "aa49a3fa147a52c8c1c37fb6b9228dba8dfafb34", "adapters/pi/launchd/com.byz.ft2-keeper.plist.in"
KP, KF = "adapters/pi/keeper.py", "adapters/pi/keeper_fetch.py"
def spy(k):
    calls, real = [], k.call
    k.call = lambda argv, *a, **b: (calls.append(list(argv)), real(argv, *a, **b))[1]
    return calls
def git_of(w, calls, repo):   # 그 리포의 fetch·ls-remote argv
    return [a for a in calls if a[:3] == ["git", "-C", str(w.tmp / repo)] and a[3] in ("fetch", "ls-remote")]
def run(w):
    k = w.keeper()
    calls = spy(k)
    return calls, w.round(k)
def targets(w, body):
    _put(w.state / "ft2-keeper" / "FETCH_TARGETS", body)
def base_tree(tmp):
    (out := tmp / "base" / "ft2").mkdir(parents=True)
    top = subprocess.run(["git", "-C", str(FT2), "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=25, check=True).stdout.strip()
    tar = subprocess.run(["git", "-C", top, "archive", BASE + ":feature-pack/fable-team/ft2"], capture_output=True, timeout=25, check=True).stdout
    subprocess.run(["tar", "-x", "-C", str(out)], input=tar, timeout=25, check=True)
    return out
def argv_of(tmp, mp, ft2):   # 같은 세계(두 리포 다 바뀜 · 일 0) 한 바퀴의 바깥 호출 → 임시 경로 = T · 리포 동시라 정렬
    w = World(tmp, mp, ft2)
    w.commit("byz", {"a": "1"}, "main"), w.pack_sha()
    k = w.keeper()
    calls = spy(k)
    w.round(k)
    return sorted(" ".join(a).replace(str(tmp), "T") for a in calls)
def c1(tmp, mp, ft2=FT2):   # ① 파일 없음 → git argv 가 기준판과 바이트 같음
    (tmp / "a").mkdir(), (tmp / "b").mkdir()
    assert argv_of(tmp / "a", mp, ft2) == argv_of(tmp / "b", mp, base_tree(tmp))
def c2(w):   # ② 파일 = pack main 만 → BYZ fetch·ls-remote 0 · BYZ 를 읽는 판정 «판정 불가» 1줄 · complete 0
    w.card("r9201", w.pack_sha()), w.work("r9201", intent=False), targets(w, "# 팩만\npack\tmain\n")
    calls, lines = run(w)
    bad = [x for x in lines if x.startswith("판정 불가")]
    assert git_of(w, calls, "root") == [] and git_of(w, calls, "pack") and w.kinds("complete") == 0, calls
    assert bad == ["판정 불가 FETCH_TARGETS 밖 %s — fetch 0 · 이 바퀴 B1·B2 0" % w.root], lines
def c3(w):   # ③ 파일 = root main 1개 → ops/main-base refspec 0 · 팩 fetch 0
    w.commit("byz", {"a": "3"}, "main"), targets(w, "root\tmain\n")
    calls, lines = run(w)
    got = [a for a in git_of(w, calls, "root") if a[3] == "fetch"]
    assert [a[7:] for a in got] == [["+refs/heads/main:refs/remotes/origin/main"]] and git_of(w, calls, "pack") == [], calls
    assert "ops/main-base" not in " ".join(sum(git_of(w, calls, "root"), [])) and lines[-1].startswith("ROUND"), lines
def c4(w):   # ④ 모르는 별칭 → 판독 실패 1줄 · fetch·ls-remote 0(기본값 fallback 0) · B1·B2 0
    w.card("r9204", w.pack_sha()), w.work("r9204", intent=False), targets(w, "zzz\tmain\n")
    calls, lines = run(w)
    assert lines == ["판정 불가 FETCH_TARGETS 판독 실패 — 이 바퀴 B1·B2 0"] and calls == [] and w.kinds("complete") == 0, (lines, calls)
def c5(w):   # ⑤ 판정 앞 = 지정 ref 만 · 받은 ref 객체 누락 0 · 지정 밖 로컬 가지·원격 추적 ref 그대로 → 판정 뒤 백그라운드가 원격 추적만 맞춤(로컬 가지 손 0)
    w.commit("byz", {}, "keep", new=True)
    _git(w.root, "fetch", "-q", "origin"), _git(w.root, "branch", "keep", "origin/keep")
    old = _git(w.root, "rev-parse", "refs/heads/keep")
    new, main = w.commit("byz", {"k": "2"}, "keep"), w.commit("byz", {"m": "2"}, "main")
    k = w.keeper()
    w.round(k)
    assert _git(w.root, "rev-parse", "refs/remotes/origin/main") == main and _git(w.root, "cat-file", "-e", main + "^{commit}") == ""
    assert (_git(w.root, "rev-parse", "refs/heads/keep"), _git(w.root, "rev-parse", "refs/remotes/origin/keep")) == (old, old)
    k.picked = [str(w.root)]
    assert [p.wait(timeout=30) for p in background(w, k).bg.values()]
    assert (_git(w.root, "rev-parse", "refs/heads/keep"), _git(w.root, "rev-parse", "refs/remotes/origin/keep")) == (old, new)
    assert any(x.startswith("BG-FETCH root 성공 rc=0") for x in w.round(w.keeper())), "다음 바퀴 결과 1줄"
def background(w, k):   # main --once 와 같은 길: 바퀴 뒤 picked 마다 kf.background
    for repo in k.picked:
        type(k).__init__.__globals__["kf"].background(k, repo)
    return k
def c6(w):   # ⑥ ROUND 줄 fetch= 그대로 · fetch_root=·fetch_pack= 덧붙임 · r1963 두 리포 동시라 fetch= = 느린 쪽(max) · 합 아님(카드 ⑥ «합» 에서 바뀜 · DA 요청에 적음)
    _git(w.root, "fetch", "-q", "origin"), _git(w.tmp / "pack", "fetch", "-q", "origin"), w.pack_sha()
    k = w.keeper()
    git = k.git
    k.git = lambda repo, *a, **o: (setattr(w, "t", w.t + 4) if a[0] == "fetch" else None, git(repo, *a, **o))[1]
    row = [x for x in w.round(k) if x.startswith("ROUND")][0]
    cell = dict(re.findall(r"(\w+)=([\d.]+)", row))
    assert (cell["fetch"], cell["fetch_pack"]) == ("4", "4") and float(cell["fetch_root"]) <= 4 and float(cell["s"]) == 4, row   # 바뀐 팩 = 기다린 쪽
    assert max(float(cell["fetch_root"]), float(cell["fetch_pack"])) == float(cell["fetch"]), row
    assert any(x.startswith("FETCH-TRY %s 1/2 rc=0 s=4" % (w.tmp / "pack")) for x in k.lines), k.lines
def nano(w, n):   # 팩 나노 가지 n 개 = 일 n 개 · intent worktree = 팩 linked worktree(HEAD nano/<work>) · 원격 가지 있음
    for i in range(n):
        work = "r93%02d" % i
        w.commit("pack", {"n": work}, "nano/" + work, new=True)
        w.work(work)
        _git(w.tmp / "pack", "worktree", "add", "-q", "-b", "nano/" + work, str(w.tmp / "wt" / work))
    calls, lines = run(w)
    return [a[7:] for a in git_of(w, calls, "pack") if a[3] == "fetch"], lines
def c7(w):   # ⑦ 나노 가지 3 + main → 판정 앞 refspec 4
    got, lines = nano(w, 3)
    assert got and all(len(x) == 4 for x in got) and got[0][0] == "+refs/heads/main:refs/remotes/origin/main" and not [x for x in lines if x.startswith("FETCH-CAP")], (got, lines)
def c7b(w):  # ⑦′ 가지 7 → 앞 5 + «지정 ref 초과 3» 1줄
    got, lines = nano(w, 7)
    assert got and all(len(x) == 5 for x in got), got
    assert [x for x in lines if x.startswith("FETCH-CAP")] == ["FETCH-CAP %s 지정 ref 초과 3 — 앞 5 만" % (w.tmp / "pack")], lines
def c8(w):   # ⑧ 판정 뒤 백그라운드 전체 fetch 1회 · 막혀도 바퀴 끝 · 앞 것 살아 있음 → 새로 0 · 풀리면 다음 바퀴 결과 1줄
    fifo, real, b = w.tmp / "block", shutil.which("git"), w.tmp / "bin2"
    _put(b / "git", '#!/bin/sh\nfor a; do last=$a; done\n[ "$3" = fetch ] && [ "$last" = origin ] && exec cat "%s"\nexec "%s" "$@"\n' % (fifo, real))
    (b / "git").chmod(0o755), w.env.update(PATH="%s:%s" % (b, w.env["PATH"]))
    k, k2, _, _ = w.keeper(), w.keeper(), os.mkfifo(fifo), targets(w, "pack\tmain\n")
    try:
        w.round(k)
        at = time.monotonic()
        background(w, k)
        took = time.monotonic() - at
        assert took < 3 and len(k.bg) == 1 and k.bg[str(w.tmp / "pack")].poll() is None, took
        w.round(k2), background(w, k2)
        assert k2.bg == {} and "BG-FETCH %s 건너뜀 — 앞 백그라운드 살아 있음" % (w.tmp / "pack") in k2.lines, k2.lines
    finally:
        try:
            os.close(os.open(fifo, os.O_WRONLY | os.O_NONBLOCK))
        except OSError:
            pass
        for p in list(k.bg.values()) + list(k2.bg.values()):
            p.wait(timeout=30)
    assert any(x.startswith("BG-FETCH pack 성공") for x in w.round(w.keeper()))
def c9(w):   # ⑨ 설치 렌더 plist = ProcessType 키 0 · 나머지 키·값 기준판과 같음
    now = plistlib.loads((w.ft2 / PL).read_bytes())
    old = plistlib.loads(subprocess.run(["git", "-C", str(FT2), "show", "%s:feature-pack/fable-team/ft2/%s" % (BASE, PL)], capture_output=True, timeout=25, check=True).stdout)
    assert "ProcessType" not in now and old.pop("ProcessType") == "Background" and now == old
CASES = {"c2": c2, "c3": c3, "c4": c4, "c5": c5, "c6": c6, "c7": c7, "c7b": c7b, "c8": c8, "c9": c9}
MUTANTS = {"M1": (KP, "if not self.table or r in self.table]", "if r in (self.table or ())]", "c1"),   # 파일 없음 = 빈 목록
           "M2": (KP, "if self.table is None:", "if False:", c4),                                          # 판독 실패 = 기본값 fallback
           "M3": (KP, "if not self.table or r in self.table]", "if True]", c2),                            # 별칭 무시 · 두 리포 다
           "M4": (KP, "names[:kf.CAP]", "names", c7b),                                                     # 상한 5 삭제
           "M5": (KF, "k.bg[repo] = proc", "k.bg[repo] = proc; proc.wait()", c8),                          # 백그라운드 wait
           "M6": (KF, "if _alive(pid):", "if False:", c8),                                                 # 겹침 검사 삭제
           "M7": (KF, '"--no-tags", "origin"]', '"--no-tags", "origin", "+refs/heads/*:refs/heads/*"]', c5)}   # 지정 밖 가지 강제 덮음


def test_c1(tmp_path, monkeypatch):
    c1(tmp_path, monkeypatch)

@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))

@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):   # 변이 = 사본에서만 → 그 사례 FAIL
    path, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        c1(tmp_path / "w", monkeypatch, tree) if case == "c1" else case(World(tmp_path / "w", monkeypatch, tree))
