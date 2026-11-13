"""r1889 card_stage 대기/ 원본 시험 (카드 반례 ①~④ · 변이 M1 · DA 설계 APPROVE).
r1884 꼴 그대로 — keeper_world_r1812 대역 · 임시 bare 원격(byz.git · main·ops/main-base) + 임시 루트만 쓴다(실 원격·실 장부 0).
기준판 = 진행/ 만 원본 → ① Red(판정 불가 진행 카드 0개). sleep 0.
"""
import importlib.util
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1889", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, MAIN, OPS = kw.TEAM, "main", "ops/main-base"
CARD = "design/harness/indices/%s/r9-x.md"


def world(tmp, mp, stages, done=True):
    w = kw.World(tmp, mp)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        kw._git(w.root, "config", k, v)
    for stage in stages:
        w.card("r9", stage=stage, refs=(OPS,))
    w.work("r9", done=done, intent=False, turn=None)
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def names(w, branch):
    return bare(w, "ls-tree", "-r", "--name-only", branch).splitlines()


def heads(w):
    return {b: bare(w, "rev-parse", b) for b in (MAIN, OPS)}


def run(w, capsys):
    mod = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs89_%d" % id(w))
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9"])
    return rc, capsys.readouterr().out.strip()


def test_1_done_waiting_only_stages_waiting_to_complete(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ("대기",))
    before = heads(w)
    rc, out = run(w, capsys)
    assert rc == 0 and out.startswith("STAGED r9-x 대기→완성 "), out
    after = names(w, OPS)
    assert CARD % "완성" in after and CARD % "대기" not in after and CARD % "진행" not in after
    body = bare(w, "show", OPS + ":" + CARD % "완성")
    assert "\n- 상태: 완성 · %s · ft2 complete " % kw.NOW in body
    assert body.rstrip().splitlines()[-1].startswith("- %s · ft2 card_stage 대기→완성" % kw.NOW), body
    assert out.split()[-1] == bare(w, "rev-parse", OPS) and bare(w, "rev-parse", OPS + "~1") == before[OPS]
    assert heads(w)[MAIN] == before[MAIN]
    assert len(kw._git(w.root, "worktree", "list").splitlines()) == 1


def test_2_done_doing_only_unchanged(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ("진행",))
    before = heads(w)
    rc, out = run(w, capsys)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    assert CARD % "완성" in names(w, OPS) and CARD % "진행" not in names(w, OPS)
    body = bare(w, "show", OPS + ":" + CARD % "완성")
    assert body.rstrip().splitlines()[-1].startswith("- %s · ft2 card_stage 진행→완성" % kw.NOW), body
    assert heads(w)[MAIN] == before[MAIN]


def test_3_doing_and_waiting_both_is_unsure(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ("진행", "대기"))
    before = heads(w)
    rc, out = run(w, capsys)
    assert rc == 3 and out.startswith("판정 불가 "), out
    assert heads(w) == before


def test_4_not_done_waiting_rejects_without_write(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ("대기",), done=False)
    before = heads(w)
    rc, out = run(w, capsys)
    assert (rc, out) == (1, "REJECT done 없음 r9"), out
    assert heads(w) == before and CARD % "대기" in names(w, OPS)
