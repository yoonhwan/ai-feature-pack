"""ft2 card_stage 임시 index 판 시험 (설계 r2 DESIGN-pH-card-stage-git-7s · DA BYZ 310291 APPROVE-DESIGN · 사례 ㊱가~㊱파 13칸 · 변이 M47~M50 · M59~M61).
r1812 대역(keeper_world_r1812) 그대로 — 임시 bare 원격(byz.git) + 임시 clone(tmp_path) 만 쓴다(실 리포·실 원격·네트워크 0 · sleep 0).
가짜 git = 부른 인자 기록(㊱나·㊱파) · 사례가 정한 자리에서 멈춤(㊱차·㊱카) · 상한 넘김(㊱라·㊱사) · tree 섞기(㊱타).
기준판 = 임시 worktree 판(worktree add·checkout·mv·commit) → ㊱나·㊱라·㊱차·㊱타·㊱파 Red.
"""
import importlib.util
import re
import subprocess
import types
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("keeper_world_rH", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, OPS, MAIN = kw.TEAM, "ops/main-base", "main"
CARD = "design/harness/indices/%s/r9-x.md"
MOVED = CARD % "완성"
BULK = 3000
B_NOW = "2026-11-13T10:00:05"   # ㊱카 전용 — B 커밋을 A 와 다른 sha 로 만드는 시계
HEX40 = re.compile(r"[0-9a-f]{40}")


# ── 대역 ──────────────────────────────────────────────────────────────
def world(tmp, mp, stage="진행", refs=(OPS,), work="r9", done=True, cards=()):
    w = kw.World(tmp, mp)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        kw._git(w.root, "config", k, v)
    for name in (work,) + tuple(cards):
        w.card(name, stage=stage, refs=refs)
        w.work(name, done=done, intent=False, turn=None)
    return w


def bare(w, *a):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), *a)


def names(w, branch=OPS):
    return bare(w, "ls-tree", "-r", "--name-only", branch).splitlines()


def head(w, branch=OPS):
    return bare(w, "rev-parse", branch)


def wt_lines(w):
    return len(kw._git(w.root, "worktree", "list").splitlines())


def diff_rows(w, old, new):
    """diff-tree 한 줄 = (상태, 경로) · -z 로 읽어 한글 경로의 quoting 을 피한다."""
    toks = bare(w, "diff-tree", "-r", "--no-renames", "--name-status", "-z", old, new).split("\0")
    return [(toks[i], toks[i + 1]) for i in range(0, len(toks) - 1, 2)]


def tool(w, tag=""):
    return kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "csh_%s_%d" % (tag, id(w)))


def call(w, capsys, mod=None, work="r9"):
    rc = (mod or tool(w)).main(["--root", str(w.root), "--team", TEAM, "--work", work])
    return rc, capsys.readouterr().out.strip()


def spy(mod, monkeypatch, on=None):
    """부른 git 인자 전부 기록 · 새 판 = spawn(모든 호출) · 기준판에는 spawn 이 없어 git 으로 대신한다.
    on(cwd, args, env, real) = 그 자리에서 갈아끼우는 대역(멈춤·섞기)."""
    seen = []

    if hasattr(mod, "spawn"):
        real = mod.spawn

        def fake(cwd, args, env=None):
            seen.append(tuple(args))
            return real(cwd, args, env) if on is None else on(cwd, tuple(args), env, real)
    else:
        real = mod.git
        pos = lambda cwd, args, env=None: real(cwd, *args)   # noqa: E731 — 기준판 git(cwd, *a) 꼴로 잇는다

        def fake(cwd, *a):
            seen.append(tuple(a))
            return pos(cwd, tuple(a)) if on is None else on(cwd, tuple(a), None, pos)
    monkeypatch.setattr(mod, "spawn" if hasattr(mod, "spawn") else "git", fake)
    return seen


def timeout_on(mod, monkeypatch, verb):
    """subprocess.run 대역 — [git, -C, 리포, <verb>] 호출에서 상한 넘김(TimeoutExpired 7초) · 나머지는 진짜."""
    real = subprocess.run

    def run(argv, **opts):
        if list(argv[3:4]) == [verb]:
            raise subprocess.TimeoutExpired(argv, 7)
        return real(argv, **opts)
    monkeypatch.setattr(mod, "subprocess", types.SimpleNamespace(run=run, TimeoutExpired=subprocess.TimeoutExpired))
    return run


def stall_after(mod, monkeypatch, verb, then):
    """가짜 git — <verb> 를 진짜로 부른 뒤 then() 을 한 번 돌리고 그대로 잇는다(㊱차·㊱카)."""
    seen, once = [], []

    def on(cwd, args, env, real):
        out = real(cwd, args, env)
        seen.append(args)
        if args[:1] == (verb,) and not once:
            once.append(out)
            then()
        return out
    return spy(mod, monkeypatch, on)


# ── ㊱가 ────────────────────────────────────────────────────────────
def test_1_done_card_moves_with_one_index(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    parent, mod = head(w), tool(w)
    seen = spy(mod, monkeypatch)
    rc, out = call(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    assert out.split()[-1] == head(w)
    tree = names(w)
    assert MOVED in tree and CARD % "진행" not in tree
    body = bare(w, "show", OPS + ":" + MOVED)
    assert "\n- 상태: 완성 · %s · ft2 complete " % kw.NOW in body, body
    assert body.count("ft2 card_stage") == 1
    assert body.rstrip().splitlines()[-1].startswith("- %s · ft2 card_stage 진행→완성" % kw.NOW)
    assert diff_rows(w, parent, head(w)) == [("A", MOVED), ("D", CARD % "진행")]
    assert bare(w, "rev-parse", OPS + "~1") == parent         # 부모 = 시도 시작에 고정한 P
    assert any(a[:1] == ("read-tree",) for a in seen), seen   # 임시 index 경로


# ── ㊱나 (M47) ──────────────────────────────────────────────────────
def test_2_no_worktree_no_checkout(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    before = wt_lines(w)
    mod = tool(w)
    seen = spy(mod, monkeypatch)
    rc, out = call(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED "), out
    assert wt_lines(w) == before
    flat = [a for args in seen for a in args]
    assert "worktree" not in flat and "checkout" not in flat, [a for a in seen if {"worktree", "checkout"} & set(a)]
    assert "sparse-checkout" not in flat, flat


# ── ㊱다 ────────────────────────────────────────────────────────────
def test_3_waiting_card_moves(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, stage="대기")
    rc, out = call(w, capsys)
    assert rc == 0 and out.startswith("STAGED r9-x 대기→완성 "), out
    tree = names(w)
    assert MOVED in tree and CARD % "대기" not in tree
    assert bare(w, "show", OPS + ":" + MOVED).rstrip().splitlines()[-1].startswith(
        "- %s · ft2 card_stage 대기→완성" % kw.NOW)


# ── ㊱라 (M48) ──────────────────────────────────────────────────────
def test_4_read_tree_timeout_names_the_command(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    before = head(w)
    mod = tool(w)
    timeout_on(mod, monkeypatch, "read-tree")
    rc, out = call(w, capsys, mod)
    assert (rc, out) == (3, "판정 불가 git read-tree 시간초과 7초"), out
    assert head(w) == before and CARD % "진행" in names(w)


# ── ㊱마 (M49) ──────────────────────────────────────────────────────
def test_5_push_refused_once_rebuilds_on_new_tip(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    mod, ahead = tool(w), []

    def on(cwd, args, env, real):
        if args[:1] == ("push",) and not ahead:   # 첫 push 직전에 원격이 앞선다(다른 커밋 1)
            ahead.append(w.commit("byz", {"other.txt": "앞선 커밋"}, OPS))
        return real(cwd, args, env)
    seen = spy(mod, monkeypatch, on)
    rc, out = call(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    tree = names(w)
    assert "other.txt" in tree and MOVED in tree and CARD % "진행" not in tree
    assert bare(w, "rev-parse", OPS + "~1") == ahead[0]        # 새 끝의 부모 = 먼저 들어간 커밋
    assert len([a for a in seen if a[0] == "fetch"]) == 2, seen
    assert not [a for a in seen if a[0] == "rebase"], seen


# ── ㊱바 ────────────────────────────────────────────────────────────
def test_6_push_refused_twice_is_unknown(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    mod, pushes = tool(w), []

    def on(cwd, args, env, _real):
        pushes.append(args)
        return 1, ""
    seen = spy(mod, monkeypatch, lambda cwd, args, env, _real: on(cwd, args, env, _real) if args[:1] == ("push",)
               else _real(cwd, args, env))
    rc, out = call(w, capsys, mod)
    assert rc == 3 and out.startswith("판정 불가 push 결과 불명"), out
    assert len(pushes) == 2, seen
    assert CARD % "진행" in names(w) and MOVED not in names(w)


# ── ㊱사 ────────────────────────────────────────────────────────────
def test_7_push_timeout_is_unknown(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    mod = tool(w)
    timeout_on(mod, monkeypatch, "push")
    rc, out = call(w, capsys, mod)
    assert (rc, out) == (3, "판정 불가 push 결과 불명"), out
    assert CARD % "진행" in names(w)


# ── ㊱아 ────────────────────────────────────────────────────────────
def test_8_complete_is_noop_and_not_done_rejects(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, stage="완성")
    before = head(w)
    rc, out = call(w, capsys)
    assert (rc, out) == (0, "NOOP r9 이미 완성"), out
    assert head(w) == before
    sub = tmp_path / "notdone"
    sub.mkdir()
    w2 = world(sub, monkeypatch, done=False)
    before2 = head(w2)
    rc, out = call(w2, capsys)
    assert (rc, out) == (1, "REJECT done 없음 r9"), out
    assert head(w2) == before2 and CARD % "진행" in names(w2)


# ── ㊱자 ────────────────────────────────────────────────────────────
def test_9_rerun_is_noop_without_commit(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    assert call(w, capsys)[0] == 0
    before, count = head(w), bare(w, "rev-list", "--count", OPS)
    mod = tool(w)
    seen = spy(mod, monkeypatch)
    rc, out = call(w, capsys, mod)
    assert (rc, out) == (0, "NOOP r9 이미 완성"), out
    assert head(w) == before and bare(w, "rev-list", "--count", OPS) == count
    assert not [a for a in seen if a[0] in ("commit-tree", "push")], seen


# ── ㊱차 (M59) ──────────────────────────────────────────────────────
def test_10_other_card_push_during_attempt_keeps_both(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, cards=("r10",))
    mod, other = tool(w), tool(w, "b")
    done = []

    def then():
        rc, out = call(w, capsys, other, work="r10")     # B 가 다른 카드를 옮겨 push
        assert rc == 0 and out.startswith("STAGED r10-x 진행→완성 "), out
        done.append(head(w))
        kw._git(w.root, "fetch", "-q", "origin", OPS)    # A 리포에 fetch 까지 된 상태
    stall_after(mod, monkeypatch, "read-tree", then)
    rc, out = call(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    tree = names(w)
    assert MOVED in tree and CARD % "진행" not in tree
    assert "design/harness/indices/완성/r10-x.md" in tree and "design/harness/indices/진행/r10-x.md" not in tree
    assert bare(w, "rev-parse", OPS + "~1") == done[0], done   # A 커밋의 부모 = B 커밋


# ── ㊱카 (M60) ──────────────────────────────────────────────────────
def test_11_same_card_race_is_noop(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    mod, other = tool(w), tool(w, "b")
    done = []

    def then():
        # B 커밋이 A 커밋과 다른 sha 가 되게 시계를 5초 옮긴다(같은 tree·같은 초 = 같은 sha → A push 가 그냥 통과한다)
        monkeypatch.setenv("FT_NOW", B_NOW)
        rc, out = call(w, capsys, other)                 # B 가 같은 카드를 옮긴다
        monkeypatch.setenv("FT_NOW", kw.NOW)
        assert rc == 0 and out.startswith("STAGED "), out
        done.extend([head(w), bare(w, "rev-list", "--count", OPS)])
        kw._git(w.root, "fetch", "-q", "origin", OPS)
    seen = stall_after(mod, monkeypatch, "read-tree", then)
    rc, out = call(w, capsys, mod)
    assert (rc, out) == (0, "NOOP r9 이미 완성"), out
    assert head(w) == done[0] and bare(w, "rev-list", "--count", OPS) == done[1]
    assert len([a for a in seen if a[0] == "commit-tree"]) == 1   # NOOP 재시도 commit-tree 0
    body = bare(w, "show", OPS + ":" + MOVED)
    assert body.count("ft2 card_stage") == 1 and body.rstrip().splitlines()[-1].startswith(
        "- %s · ft2 card_stage 진행→완성" % B_NOW)


# ── ㊱타 (M61) ──────────────────────────────────────────────────────
def test_12_self_check_blocks_extra_change(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    before, mod, pushes = head(w), tool(w), []

    def on(cwd, args, env, real):
        out = real(cwd, args, env)
        if args[:1] == ("push",):
            pushes.append(args)
        if args[:1] == ("write-tree",) and env:          # tree 에 다른 파일 변화 1개를 섞는다
            extra = Path(env["GIT_INDEX_FILE"] + ".x")
            extra.write_text("x\n", encoding="utf-8")
            blob = real(cwd, ("hash-object", "-w", str(extra)), None)[1].strip()
            real(cwd, ("update-index", "--add", "--cacheinfo", "100644,%s,notes/extra.txt" % blob), env)
            out = real(cwd, ("write-tree",), env)
        return out
    spy(mod, monkeypatch, on)
    rc, out = call(w, capsys, mod)
    assert (rc, out) == (3, "판정 불가 card_stage 커밋 범위 밖 3줄"), out
    assert pushes == [] and head(w) == before
    assert CARD % "진행" in names(w)


# ── ㊱파 (M59) ──────────────────────────────────────────────────────
def test_13_reads_use_pinned_sha_only(tmp_path, monkeypatch, capsys):
    w, mod = world(tmp_path, monkeypatch), None
    mod = tool(w, "p")
    seen = spy(mod, monkeypatch)
    rc, out = call(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED "), out

    def target(args):
        if args[0] == "show":
            return args[1].split(":", 1)[0]
        if args[0] == "read-tree":
            return args[1]
        if args[0] == "ls-tree":
            return args[3]
        if args[0] == "commit-tree":
            return args[args.index("-p") + 1]
        return ""
    reads = [a for a in seen if a[0] in ("show", "read-tree", "ls-tree", "commit-tree")]
    assert [a[0] for a in reads].count("read-tree") == 1 and [a[0] for a in reads].count("commit-tree") == 1, reads
    assert all(HEX40.fullmatch(target(a) or "") for a in reads), reads
    named = [a for a in seen if a[0] not in ("fetch", "rev-parse", "push")]
    assert not [a for a in named if any("origin/" in x for x in a)], named
    assert {a[0] for a in seen} <= {"fetch", "rev-parse", "show", "ls-tree", "read-tree", "hash-object",
                                   "update-index", "write-tree", "commit-tree", "push", "diff-tree"}, seen


# ── 큰 리포(옛 r1891 ①) — 파일을 풀지 않는다 ───────────────────────────
def test_14_big_repo_untouched(tmp_path, monkeypatch, capsys):
    sub = tmp_path / "big"
    sub.mkdir()
    w = world(sub, monkeypatch)
    w.commit("byz", {"big/d%02d/f%04d.txt" % (i % 50, i): "x%d\n" % i for i in range(BULK)}, OPS)
    w.card("r9", refs=(OPS,))       # 카드를 bulk 위에 다시 올린다
    assert len(names(w)) > BULK
    before = wt_lines(w)
    rc, out = call(w, capsys)
    assert rc == 0 and out.startswith("STAGED "), out
    assert wt_lines(w) == before
    tree = names(w)
    assert MOVED in tree and "big/d00/f0000.txt" in tree and len(tree) > BULK
