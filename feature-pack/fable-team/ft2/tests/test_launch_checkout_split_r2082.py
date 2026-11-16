"""r2082 BYZ 큰 리포 열기 — 남의 팀 design 폴더 제외(기준 sha 의 TEAMS.md «폴더» 칸) + 파일 수 상한으로 나눠 풀기 (반례 ①~⑦ · 변이 M1~M8 · 보정 1).
임시 git 리포(design/TEAMS.md + 팀 폴더 3개 + 파일 30개) + 진짜 launch.py(감싼 실행기 = sparse·checkout 호출 상한만 3초 · 상한 값 변경 0) ·
가짜 git(진짜 git 에 넘김 · k 번째 `sparse-checkout set` 만 FAKE_SET_FAIL(rc1) 또는 FAKE_SET_HANG(PART 뒤 멈춤 = 상한 넘김)) ·
기준 sha 읽기(ls-tree·cat-file) 중 FAKE_READ 하위 명령만 rc9 또는 FAKE_READ_HANG(멈춤) · 가짜 tmux(has-session rc = FAKE_ALIVE · 기본 1) · 파일 수 상한 = env FT2_CHECKOUT_FILES · sleep 0(시험 쪽).
"""
import importlib.util, json, os, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
pl = _mod("r2082_pl", HERE / "test_pi_launch.py")
GIT = '#!/bin/sh\necho "$*" >> "$GLOG"\ncase " $* " in\n' \
      '  *" ls-tree "*|*" cat-file "*) if [ -n "$FAKE_READ" ] && [ "$3" = "$FAKE_READ" ]; then [ -n "$FAKE_READ_HANG" ] && exec sleep 30; echo "fake rc9" >&2; exit 9; fi;;\n' \
      '  *" sparse-checkout set "*) n=$(grep -c " sparse-checkout set " "$GLOG")\n' \
      '    [ "$n" = "$FAKE_SET_FAIL" ] && exit 1\n    if [ "$n" = "$FAKE_SET_HANG" ]; then cd "$2" && eval "$PART"; exec sleep 30; fi;;\nesac\nexec "$REAL_GIT" "$@"\n'
TMUX = '#!/bin/sh\necho "$1" >> "$TLOG"\n[ "$1" = has-session ] && exit "${FAKE_ALIVE:-1}"\nexit 0\n'
WRAP = '''import importlib.util, sys
spec = importlib.util.spec_from_file_location("ft2_r2082_launch", %r)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
real = m.call
m.call = lambda cmd, cwd, env, t: real(cmd, cwd, env, 3 if {"sparse-checkout", "ls-tree", "cat-file"} & set(cmd) or list(cmd[-2:]) == ["checkout", "-q"] else t)
sys.exit(m.main(sys.argv[1:]))
'''
PART = 'echo partial > design/harness/h1.part; touch "$("$REAL_GIT" rev-parse --git-path index.lock)"'   # 끊긴 풀기 = 쓴 파일 1개(??) + 죽은 git 의 lock
TEAMS = "# 팀\n\n| 팀 | 폴더 | 상태 |\n|---|---|---|\n| harness | `design/harness/` | 현역 |\n| v65 | `design/v65/` | 현역 |\n| knowledge | `design/teams/knowledge/` | 현역 |\n"
CARD = "design/harness/indices/대기/W1.md"
BASE = ["/*", "!/design/teams/*/", "/design/teams/harness/"]
def files(teams=TEAMS):
    """파일 30개 = 바로 밑 4(README·.gitignore·design/README·TEAMS) + evidence 6 + harness 6(짝 카드 포함) + knowledge 3 + v65 5 + src 6."""
    got = {"README.md": "r\n", ".gitignore": ".fable-team/\n", "design/README.md": "d\n", "design/TEAMS.md": teams, CARD: "card\n"}
    for name, n in (("design/evidence/e", 6), ("design/harness/h", 5), ("design/teams/knowledge/k", 3), ("design/v65/v", 5), ("src/s", 6)):
        got.update({"%s%d" % (name, i): "%s%d\n" % (name, i) for i in range(1, n + 1)})
    return {k: v for k, v in got.items() if v is not None}
def git(root, *a):
    return subprocess.run(["git", "-C", str(root)] + list(a), capture_output=True, text=True, timeout=25, check=True)
def world(tmp, ft2, tree, card=CARD, pre=None):
    root, fake = pl._paths(tmp)
    for name, body in (("git", GIT), ("tmux", TMUX)):
        (fake / name).write_text(body, encoding="utf-8")
    (tmp / "wrap.py").write_text(WRAP % str(ft2 / "adapters" / "pi" / "launch.py"), encoding="utf-8")
    run = lambda *a: git(root, *a)  # noqa: E731
    run("init", "-q")
    for rel, text in tree.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True), (root / rel).write_text(text, encoding="utf-8")
    run("add", "-A"), run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "i"), run("update-ref", "refs/remotes/origin/main", "HEAD")
    if pre:   # 호출 리포만 바꿈(origin/main 그대로) = 기준 sha 와 다른 caller
        pre(root), run("add", "-A"), run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "caller")
    pl._runtime(root)
    if card:
        (root / ".fable-team" / "teams" / "harness" / "runtime" / "cards.tsv").write_text("W1\t%s\n" % card, encoding="utf-8")
    return root, fake
def launch(tmp, root, fake, *extra, **env):
    base = dict(REAL_GIT=shutil.which("git"), TLOG=str(tmp / "tmux.log"), GLOG=str(tmp / "git.log"), PART=PART)
    out, rc = pl._launch(root, fake, tmp / "wrap.py", extra=extra, env_extra=dict(base, **env))
    glog = (tmp / "git.log").read_text(encoding="utf-8").splitlines() if (tmp / "git.log").exists() else []
    tlog = (tmp / "tmux.log").read_text(encoding="utf-8").splitlines() if (tmp / "tmux.log").exists() else []
    it = json.loads(pl._intent(root).read_text(encoding="utf-8")) if pl._intent(root).exists() else {}   # 의도 전 실패 = {}
    return out, rc, it, glog, tlog
def sets(glog):
    """`sparse-checkout set` 호출마다 패턴 목록."""
    return [line.split(" --no-cone ", 1)[1].split(" ") for line in glog if " sparse-checkout set " in line]
def tree_of(root):
    wt = pl._worktree(root)
    return sorted(str(p.relative_to(wt)) for p in wt.rglob("*") if p.is_file() and ".git" not in p.relative_to(wt).parts)
def patterns(root):
    return subprocess.run(["git", "-C", str(pl._worktree(root)), "sparse-checkout", "list"], capture_output=True, text=True, timeout=25).stdout.split()
def opened(tmp, ft2, tree, card=CARD, pre=None, **env):
    tmp.mkdir(parents=True, exist_ok=True)
    root, fake = world(tmp, ft2, tree, card, pre)
    out, rc, it, glog, tlog = launch(tmp, root, fake, FAKE_ALIVE="0", **env)
    assert (rc, out.get("opened"), it.get("state")) == (0, True, "opened"), (out, it)
    return root, it, glog
def c1(tmp, ft2):   # ① harness 나노 → design/v65/ · design/teams/knowledge/ 파일 0 · harness · design 바로 밑 · evidence · 짝 카드 있음
    root, _, glog = opened(tmp, ft2, files())
    got = tree_of(root)
    assert not [p for p in got if p.startswith(("design/v65/", "design/teams/knowledge/"))], got
    assert {"design/harness/h1", "design/README.md", "design/TEAMS.md", "design/evidence/e1", CARD, "src/s1", "README.md"} <= set(got), got
def c1b(tmp, ft2):  # ①b 짝 카드 폴더가 남의 팀 폴더 안 → 짝 카드 폴더는 포함 · 그 팀의 나머지는 0
    tree = dict(files(), **{"design/v65/indices/대기/W1.md": "card\n"})
    root, _, _ = opened(tmp, ft2, tree, card="design/v65/indices/대기/W1.md")
    got = tree_of(root)
    assert "design/v65/indices/대기/W1.md" in got and "design/v65/v1" not in got, got
def c1r(tmp, ft2):  # ①r(판정문 R1) 호출 리포 표에서 v65 행을 지운 clean 가지 · base = origin/main(3팀 표) → design/v65/ 파일 0
    drop = lambda root: (root / "design/TEAMS.md").write_text(TEAMS.replace("| v65 | `design/v65/` | 현역 |\n", ""), encoding="utf-8")  # noqa: E731
    root, _, _ = opened(tmp, ft2, files(), pre=drop)
    assert git(root, "status", "--porcelain").stdout == "" and "v65" not in (root / "design/TEAMS.md").read_text(encoding="utf-8")
    got = tree_of(root)
    assert not [p for p in got if p.startswith("design/v65/")] and "design/harness/h1" in got, got
def c2(tmp, ft2):   # ② 표를 못 쓸 때 — 없음 = 기준판 인자 · 칸 0 / «폴더» 칸 없음 = 기준판 인자 + 1칸 / 내 팀 없음 = 표의 모든 팀 폴더 제외
    note = "팀 폴더 표 못 읽음 — 제외 0"
    _, it, glog = opened(tmp / "a", ft2, {k: v for k, v in files().items() if k != "design/TEAMS.md"}, card=None)
    assert sets(glog) == [BASE] and note not in json.dumps(it, ensure_ascii=False), (glog, it)
    _, it, glog = opened(tmp / "b", ft2, files("| 팀 | 좌석 |\n|---|---|\n| harness | x |\n"), card=None)
    assert sets(glog) == [BASE] and it.get("sparse_note") == note, (glog, it)
    _, it, glog = opened(tmp / "c", ft2, files(TEAMS.replace("| harness | `design/harness/` | 현역 |\n", "")), card=None)
    assert sets(glog) == [BASE + ["!/design/v65/", "!/design/teams/knowledge/"]] and "sparse_note" not in it, (glog, it)
def c3(tmp, ft2):   # ③ 파일 30 · 상한 10 → 묶음 3 이상 · 묶음마다 git 호출 1회 · 끝 = 상한 큰 실행과 같음 / 혼자 15 → 혼자 1묶음
    small, it, glog = opened(tmp / "a", ft2, files(), FT2_CHECKOUT_FILES="10")
    n = it.get("checkout_batches", 1)
    assert n >= 3 and len(sets(glog)) == n and sum(" checkout -q" in x for x in glog) == 1, (n, glog)
    big, _, _ = opened(tmp / "b", ft2, files(), FT2_CHECKOUT_FILES="100000")
    assert (tree_of(small), patterns(small)) == (tree_of(big), patterns(big)), (tree_of(small), tree_of(big))
    tree = dict({"README.md": "r\n", ".gitignore": ".fable-team/\n"}, **{"big/b%d" % i: "%d\n" % i for i in range(15)}, **{"src/s%d" % i: "%d\n" % i for i in range(3)})
    _, it, glog = opened(tmp / "c", ft2, tree, card=None, FT2_CHECKOUT_FILES="10")
    negs = [set(p for p in x if p.startswith("!/") and "*" not in p) for x in sets(glog)] + [set()]
    assert any(negs[k] - negs[k + 1] == {"!/big/"} for k in range(len(negs) - 1)), negs
def c3r(tmp, ft2):  # ③r(판정문 R2) origin/main = 루트 2 + a·b·c 각 10 · 호출 리포 index 2파일 · 상한 10 → 묶음 4개
    tree = dict({"README.md": "r\n", ".gitignore": ".fable-team/\n"}, **{"%s/f%d" % (d, i): "%d\n" % i for d in "abc" for i in range(10)})
    root, it, glog = opened(tmp, ft2, tree, card=None, pre=lambda root: git(root, "rm", "-rq", "a", "b", "c"), FT2_CHECKOUT_FILES="10")
    assert len(git(root, "ls-files").stdout.split()) == 2 and len(tree_of(root)) == 32, tree_of(root)
    assert it.get("checkout_batches") == 4 and len(sets(glog)) == 4, (it, glog)
def c4(tmp, ft2):   # ④ 묶음 2 에서 git rc 1 → 실패 단계 «git checkout 2/3» · 묶음 3 호출 0 · 반쪽 치우기 = 기준판 규칙(깨끗 = 치움)
    root, fake = world(tmp, ft2, files())
    out, rc, it, glog, tlog = launch(tmp, root, fake, FT2_CHECKOUT_FILES="10", FAKE_SET_FAIL="2")
    assert (rc, it["state"], it["step"], out["step"]) == (2, "failed", "git checkout 2/3", "git checkout 2/3"), (out, it)
    assert len(sets(glog)) == 2 and "new-session" not in tlog and it.get("cleanup") == "치움", (glog, it)
def c5(tmp, ft2):   # ⑤ 묶음 2 시간 초과 → resumable + lock 정리 → --resume → 묶음 1 파일 그대로 · 묶음 2·3 생김 · 좌석 열림
    root, fake = world(tmp, ft2, files())
    out, rc, it, glog, _ = launch(tmp, root, fake, FT2_CHECKOUT_FILES="10", FAKE_SET_HANG="2")
    lock = root / ".git" / "worktrees" / pl._worktree(root).name / "index.lock"
    assert (rc, it["step"], it.get("resumable")) == (2, "git checkout 2/3", "checkout") and not lock.exists(), (out, it)
    one = [pl._worktree(root) / p for p in ("design/evidence/e1", "README.md")]
    [os.utime(p, (1000000000, 1000000000)) for p in one]
    seen = len(glog)
    out, rc, it, glog, tlog = launch(tmp, root, fake, "--resume", FT2_CHECKOUT_FILES="10", FAKE_ALIVE="0")
    assert (rc, out.get("opened"), it["state"]) == (0, True, "opened") and tlog.count("new-session") == 1, (out, it)
    again = glog[seen:]
    assert [p.stat().st_mtime for p in one] == [1000000000] * 2 and not any(" checkout -q" in x for x in again), again
    assert len(sets(again)) == 2 and {"design/harness/h1", "src/s1"} <= set(tree_of(root)), (again, tree_of(root))
def c6(tmp, ft2):   # ⑥ 상한 큰 값(또는 env 없음) + TEAMS.md 없는 리포 → 읽기 호출(1회 · add 앞)을 뺀 git 호출 목록 = 기준판 / TEAMS 있음 = 읽기 2회 / dry-run = 바깥 호출 0
    for sub, env in (("a", {}), ("b", {"FT2_CHECKOUT_FILES": "100000"})):
        root, _, glog = opened(tmp / sub, ft2, {"README.md": "r\n", ".gitignore": ".fable-team/\n", "src/s": "s\n"}, card=None, **env)
        wt, sha = str(pl._worktree(root)), glog[2].split(" ")[-1]
        assert glog[1] == "-C %s ls-tree -r --name-only -z %s" % (root, sha), glog
        assert glog[:1] + glog[2:] == ["-C %s rev-parse --verify --quiet origin/main^{commit}" % root, "-C %s worktree add --no-checkout --detach %s %s" % (root, wt, sha),
                                       "-C %s sparse-checkout set --no-cone %s" % (wt, " ".join(BASE)), "-C %s checkout -q" % wt], glog
    root, _, glog = opened(tmp / "c", ft2, files(), FT2_CHECKOUT_FILES="100000")
    sha = glog[1].split(" ")[-1]
    assert [x.split(" ")[2] for x in glog[1:3]] == ["ls-tree", "cat-file"] and glog[2].endswith("blob %s:design/TEAMS.md" % sha) and " worktree add " in glog[3], glog
    (tmp / "d").mkdir()
    root, fake = world(tmp / "d", ft2, files())
    out, rc, it, glog, tlog = launch(tmp / "d", root, fake, "--dry-run")
    assert (rc, out.get("dry_run"), glog, tlog, it) == (0, True, [], [], {}), (out, glog)
def c7(tmp, ft2):   # ⑦ 기준 sha 읽기 실패(파일 목록 rc9 · blob rc9 · 파일 목록 시간 초과) → rc≠0 · 단계 = 하위 명령 · «판정 불가» · add·tmux 0 · 경로·resumable 0
    for sub, env, step in (("a", {"FAKE_READ": "ls-tree"}, "git ls-tree"), ("b", {"FAKE_READ": "cat-file"}, "git cat-file"),
                           ("c", {"FAKE_READ": "ls-tree", "FAKE_READ_HANG": "1"}, "git ls-tree")):
        (tmp / sub).mkdir(parents=True)
        root, fake = world(tmp / sub, ft2, files())
        out, rc, it, glog, tlog = launch(tmp / sub, root, fake, FT2_CHECKOUT_FILES="10", **env)
        assert (rc, out.get("opened"), out.get("step"), it.get("step")) == (2, False, step, step) and "판정 불가" in out["reason"], (sub, out, it)
        assert not any(" worktree add " in x for x in glog) and tlog == [] and not pl._worktree(root).exists() and "resumable" not in it, (sub, glog, it)
CASES = {"①": c1, "①b": c1b, "①r": c1r, "②": c2, "③": c3, "③r": c3r, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}
LP, LA = "adapters/pi/launch_plan.py", "adapters/pi/launch.py"
MUTANTS = {"M1": (LP, '    return (got, "") if got else ({}, UNREAD)', '    return ({}, "")', "①"),
           "M2": (LP, "    if at is None:\n        return {}, UNREAD", "    if at is None:\n        raise ValueError(UNREAD)", "②"),
           "M3": (LP, "    if len(groups) < 2:", "    if True:", "③"),
           "M4": (LA, "        if rc != 0:\n            return failed(plan, env, step,", '        if rc != 0 and "/" not in name:\n            return failed(plan, env, step,', "④"),
           "M5": (LP, "    if not head and failed_step in names[2:]:", "    if False:", "⑤"),
           "M6": (LA, '    if rc != 0:\n        return None, failed(plan, env, "git ls-tree",', '    if rc != 0 and False:\n        return None, failed(plan, env, "git ls-tree",', "⑦"),
           "M7": (LA, "        text = getattr(text, \"out\", text)", '        text = open(os.path.join(repo, planner.TEAMS), encoding="utf-8").read()', "①r"),
           "M8": (LP, '["git", "-C", repo, "ls-tree", "-r", "--name-only", "-z", sha]', '["git", "-C", repo, "ls-files", "-z"]', "③r")}
def _copy(dst, src):
    shutil.copytree(src, dst / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    return dst / "ft2"
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    _copy(tmp_path, FT2)
    CASES[name](tmp_path / "w", tmp_path / "ft2")
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, case = MUTANTS[name]
    tree = _copy(tmp_path / "m", FT2)
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    _copy(tmp_path / "o", FT2)
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "m" / "w", tree)
    CASES[case](tmp_path / "o" / "w", tmp_path / "o" / "ft2")   # 원본으로 같은 사례 1회 더 = PASS
if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
