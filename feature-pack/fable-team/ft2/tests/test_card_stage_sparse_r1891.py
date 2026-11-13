"""r1891 card_stage 임시 worktree sparse 시험 (카드 반례 ①② · 변이 M1 · DA 설계 APPROVE).
r1859 꼴 그대로 — keeper_world_r1812 대역 · 임시 bare 원격(byz.git) + 임시 루트만 쓴다(실 원격·실 장부 0).
① 큰 리포 모형 = 카드 밖 파일 3000개 · mv 직전 임시 worktree 의 풀린 파일 = indices 아래만.
② worktree add 시간 초과(등록 전·등록 뒤) = remove --force 1회 + 판정 불가(Traceback 0 · OSError 0). sleep 0.
기준판 = 전체 checkout · add 가 try 밖 → ①② Red.
"""
import importlib.util
import os
import subprocess
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1891", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, OPS = kw.TEAM, "ops/main-base"
CARD = "design/harness/indices/%s/r9-x.md"
BULK = 3000


def world(tmp, mp, bulk=0):
    w = kw.World(tmp, mp)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        kw._git(w.root, "config", k, v)
    if bulk:
        w.commit("byz", {"big/d%02d/f%04d.txt" % (i % 50, i): "x%d\n" % i for i in range(bulk)}, OPS)
    w.card("r9", refs=(OPS,))
    w.work("r9", done=True, intent=False, turn=None)
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def spy(w, monkeypatch, on_add=None):
    """git 대역 · 호출 기록 · mv 직전 풀린 파일 목록 · on_add = worktree add 를 갈아끼운다."""
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs91_%d" % id(w))
    real, seen, files = mod.git, [], []

    def fake(cwd, *a):
        seen.append(a[:2])
        if a[:1] == ("mv",):
            files.extend(os.path.relpath(os.path.join(d, f), cwd) for d, dirs, fs in os.walk(cwd)
                         if ".git" not in Path(d).relative_to(cwd).parts for f in fs if f != ".git")
        if a[:2] == ("worktree", "add") and on_add:
            return on_add(real, cwd, *a)
        return real(cwd, *a)
    monkeypatch.setattr(mod, "git", fake)
    return mod, seen, files


def call(w, capsys, mod):
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"])
    return rc, capsys.readouterr().out.strip()


def wt_count(w):
    return len(kw._git(w.root, "worktree", "list").splitlines())


def test_1_big_repo_checks_out_indices_only(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, BULK)
    assert len(bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()) > BULK
    mod, seen, files = spy(w, monkeypatch)
    rc, out = call(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    assert files and all(f.startswith("design/harness/indices/") for f in files), files[:5]
    assert CARD % "진행" in files and len(files) < 10, len(files)
    assert CARD % "완성" in bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert "big/d00/f0000.txt" in bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert seen.count(("worktree", "remove")) == 1 and wt_count(w) == 1


def slow(real, cwd, *a):
    raise subprocess.TimeoutExpired(["git", "worktree", "add"], 7)


def late(real, cwd, *a):   # 등록·빈 자리까지 된 뒤에 끊긴다
    real(cwd, *a)
    raise subprocess.TimeoutExpired(["git", "worktree", "add"], 7)


def test_2_add_timeout_before_register_cleans_once(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    sha = bare(w, "rev-parse", OPS)
    mod, seen, _ = spy(w, monkeypatch, slow)
    rc, out = call(w, capsys, mod)   # Traceback·OSError 이면 여기서 시험이 깨진다
    assert rc == 3 and out.startswith("판정 불가 "), out
    assert seen.count(("worktree", "remove")) == 1 and wt_count(w) == 1
    assert bare(w, "rev-parse", OPS) == sha


def test_3_add_timeout_after_register_cleans_once(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    sha = bare(w, "rev-parse", OPS)
    mod, seen, _ = spy(w, monkeypatch, late)
    rc, out = call(w, capsys, mod)
    assert rc == 3 and out.startswith("판정 불가 "), out
    assert seen.count(("worktree", "remove")) == 1 and wt_count(w) == 1
    assert bare(w, "rev-parse", OPS) == sha
