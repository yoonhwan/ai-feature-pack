"""r1884 card_stage main 기준 팀 시험 (카드 반례 ①~⑤ · 변이 M1·M2 · DA 설계 APPROVE).
r1812 대역(keeper_world_r1812) 재사용 · 임시 bare 원격(byz.git · main·ops/main-base 2가지) + 임시 루트만 쓴다(실 원격·실 장부 0).
기준판 = card_stage 가 ops/main-base 하나만 본다 → ①③④⑤ Red. sleep 0.
"""
import importlib.util
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1884", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, MAIN, OPS = kw.TEAM, "main", "ops/main-base"
CARD = "design/harness/indices/%s/r9-x.md"
NO_ROW = "| 팀 | 폴더 |\n|---|---|\n| planner | `design/teams/planner/` |\n"


def world(tmp, mp, refs, stage="진행", ops_row=True):
    w = kw.World(tmp, mp)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        kw._git(w.root, "config", k, v)
    if not ops_row:   # 실사건 — ops/main-base 의 TEAMS.md 에 팀 행 0 · main 에만 있음
        w.commit("byz", {"design/TEAMS.md": NO_ROW}, OPS)
    w.card("r9", stage=stage, refs=refs)
    w.work("r9", done=True, intent=False, turn=None)
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def names(w, branch):
    return bare(w, "ls-tree", "-r", "--name-only", branch).splitlines()


def heads(w):
    return {b: bare(w, "rev-parse", b) for b in (MAIN, OPS)}


def run(w, capsys, mod=None):
    mod = mod or kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs84_%d" % id(w))
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"])
    return rc, capsys.readouterr().out.strip()


def test_1_main_only_stages_on_main(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, (MAIN,), ops_row=False)
    before = heads(w)
    rc, out = run(w, capsys)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    assert CARD % "완성" in names(w, MAIN) and CARD % "진행" not in names(w, MAIN)
    assert out.split()[-1] == bare(w, "rev-parse", MAIN) and bare(w, "rev-parse", MAIN + "~1") == before[MAIN]
    assert "- 상태: 완성 · %s" % kw.NOW in bare(w, "show", MAIN + ":" + CARD % "완성")
    assert heads(w)[OPS] == before[OPS]
    assert len(kw._git(w.root, "worktree", "list").splitlines()) == 1


def test_2_ops_only_stays_on_ops(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, (OPS,))
    before = heads(w)
    rc, out = run(w, capsys)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    assert CARD % "완성" in names(w, OPS) and out.split()[-1] == bare(w, "rev-parse", OPS)
    assert heads(w)[MAIN] == before[MAIN]


def test_3_both_refs_doing_is_unsure(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, (MAIN, OPS))
    before = heads(w)
    rc, out = run(w, capsys)
    assert (rc, out) == (3, "판정 불가 두 가지에 진행 카드"), out
    assert heads(w) == before


def test_4_main_complete_only_is_noop(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, (MAIN,), stage="완성", ops_row=False)
    before = heads(w)
    rc, out = run(w, capsys)
    assert (rc, out) == (0, "NOOP r9 이미 완성"), out
    assert heads(w) == before


def test_5_main_push_rejected_rebases_on_main(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, (MAIN,), ops_row=False)
    before, seen, rebases = heads(w), [], []
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs84r_%d" % id(w))
    real = mod.git

    def spy(cwd, *a):
        if a[0] == "push" and not seen:   # 첫 push 직전에 원격 main 이 앞선다(다른 커밋 1)
            seen.append(w.commit("byz", {"other.txt": "앞선 커밋"}, MAIN))
        if a[0] in ("rebase", "fetch"):
            rebases.append(a)
        return real(cwd, *a)
    monkeypatch.setattr(mod, "git", spy)
    rc, out = run(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED "), out
    assert "other.txt" in names(w, MAIN) and CARD % "완성" in names(w, MAIN)
    assert bare(w, "merge-base", "--is-ancestor", seen[0], MAIN) == ""
    assert [a for a in rebases if a[0] == "rebase"] == [("rebase", "-q", "origin/main")], rebases
    assert not any("origin/ops/main-base" in a or a[-1:] == (OPS,) for a in rebases if a[0] == "rebase"), rebases
    assert heads(w)[OPS] == before[OPS]
