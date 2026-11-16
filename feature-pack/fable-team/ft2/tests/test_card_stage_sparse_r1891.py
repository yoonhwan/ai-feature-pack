"""r1891 card_stage 큰 리포·시간초과 시험 (옛 임시 worktree sparse 판 · rH 에서 worktree 자체가 없어졌다).
r1859 꼴 그대로 — keeper_world_r1812 대역 · 임시 bare 원격(byz.git) + 임시 루트만 쓴다(실 원격·실 장부 0).
① 큰 리포 모형 = 카드 밖 파일 3000개 → 실행이 worktree 등록·checkout·sparse-checkout 을 부르지 않는다(옛 «add 끊김 정리» 자리 · 카드 완료 조건 4 · ㊱나).
② read-tree 시간 초과 = 7초 상한 그대로 · 등록·원격 변화 0 · Traceback 0(옛 «정리 실패 등록 잔존» 자리).
sleep 0 · 네트워크 0 · 사례 1개 70초 안.
"""
import importlib.util
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
    w.card("r9", "1a" * 20, refs=(OPS,))   # r2147 — 착지 줄 있는 카드만 옮김
    w.work("r9", done=True, intent=False, turn=None)
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def tool(w):
    return kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs91_%d" % id(w))


def call(w, capsys, mod):
    return mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"]), capsys.readouterr().out.strip()


def spy(w, monkeypatch):
    """git 대역 — 부른 인자 기록(새 판 = spawn · 기준판에는 spawn 이 없어 git)."""
    mod, seen = tool(w), []
    name = "spawn" if hasattr(mod, "spawn") else "git"
    real = getattr(mod, name)
    if name == "spawn":
        monkeypatch.setattr(mod, name, lambda cwd, args, env=None: seen.append(tuple(args)) or real(cwd, args, env))
    else:
        monkeypatch.setattr(mod, name, lambda cwd, *a: seen.append(tuple(a)) or real(cwd, *a))
    return mod, seen


def timeout_on(mod, monkeypatch, verb):
    real = subprocess.run

    def run(argv, **opts):
        if list(argv[3:4]) == [verb]:
            raise subprocess.TimeoutExpired(argv, 7)
        return real(argv, **opts)
    import types
    monkeypatch.setattr(mod, "subprocess", types.SimpleNamespace(run=run, TimeoutExpired=subprocess.TimeoutExpired))


def wt_count(w):
    return len(kw._git(w.root, "worktree", "list").splitlines())


def test_1_big_repo_no_checkout_no_worktree(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, BULK)
    assert len(bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()) > BULK
    mod, seen = spy(w, monkeypatch)
    rc, out = call(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    tree = bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
    assert CARD % "완성" in tree and CARD % "진행" not in tree and "big/d00/f0000.txt" in tree
    flat = [a for args in seen for a in args]
    assert "worktree" not in flat and "checkout" not in flat and "sparse-checkout" not in flat, seen
    assert wt_count(w) == 1


def test_2_read_tree_timeout_keeps_remote_and_worktrees(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    sha = bare(w, "rev-parse", OPS)
    mod = tool(w)
    timeout_on(mod, monkeypatch, "read-tree")
    rc, out = call(w, capsys, mod)   # Traceback·OSError 이면 여기서 시험이 깨진다
    assert (rc, out) == (3, "판정 불가 git read-tree 시간초과 7초"), out
    assert bare(w, "rev-parse", OPS) == sha and wt_count(w) == 1
    assert CARD % "진행" in bare(w, "ls-tree", "-r", "--name-only", OPS).splitlines()
