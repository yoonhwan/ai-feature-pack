"""r2122 keeper 나노 가지 모으기 — worktree HEAD 가지·git 공용 폴더를 파일로 읽고(git 0) 팀마다 journal 1회 · 예산 문(C5).
반례 ①~⑦ · ⑨(⑧ = 불변 목록 재실행 · 이 파일 밖) · 변이 M1~M5(사본에서만 · 원본으로 같은 사례 1회 더 = 반대 결과 대조).
가짜 keeper K = git 호출 셈(⑤ 는 대답을 정해 둔 가짜 · 나머지는 실제 git) · 실 runtime·tmux·원장 0 · sleep 0.
"""
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FT2, KF = Path(__file__).resolve().parents[1], "adapters/pi/keeper_fetch.py"
GIT = ["git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "init.defaultBranch=main"]


class Cut(BaseException):
    pass


def load(tree, name):
    spec = importlib.util.spec_from_file_location(name, str(tree / KF))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(cwd, *args):
    return subprocess.run(GIT + list(args), cwd=str(cwd), check=True, capture_output=True, text=True).stdout.strip()


class K:
    """keeper 대역 — root · handled · git(호출 셈 · 남은 몫 < 1초 = Cut, Keeper.call 과 같음) · read_json · left · cut_at."""
    def __init__(s, root, left=lambda: None, fake=None):
        s.root, s.state, s.calls, s.cuts, s._left, s.fake = str(root), {"handled": set()}, [], 0, left, fake or {}
        s.reads = []
    def left(s):
        return s._left()
    def cut_at(s):
        s.cuts += 1
        return Cut("cut")
    def git(s, repo, *args, **_):
        if (left := s.left()) is not None and left < 1:
            raise s.cut_at()
        s.calls.append((repo, args))
        if repo in s.fake:
            return 0, s.fake[repo][args[0] if args[1:2] != ("--path-format=absolute",) else "common"] + "\n", ""
        done = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True)
        return done.returncode, done.stdout, done.stderr
    def read_json(s, path):
        s.reads.append(path)
        try:
            with open(path, encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return {}


class W:
    """임시 root(팀 runtime journal · launch intent) + 임시 git 리포."""
    def __init__(s, tmp):
        s.tmp, s.root, s.seq = tmp, tmp / "root", {}
    def runtime(s, team):
        return s.root / ".fable-team" / "teams" / team / "runtime"
    def repo(s, name="repo"):
        path = s.tmp / name
        path.mkdir()
        git(path, "init", "-q")
        git(path, "commit", "-q", "--allow-empty", "-m", "c")
        return path
    def linked(s, repo, work, branch=None):
        tree = s.tmp / "wt" / work
        git(repo, "worktree", "add", "-q", "-b", branch or "nano/" + work, str(tree))
        return tree
    def dispatch(s, team, work, attempt="a1", holder="h#0"):
        s.seq[team] = n = s.seq.get(team, 0) + 1
        row = {"schema": 1, "team": team, "seq": n, "kind": "dispatch", "command": "c", "attempt": attempt,
               "at": "2026-11-16T00:00:00", "body": {}, "work": work, "holder": holder}
        s.runtime(team).mkdir(parents=True, exist_ok=True)
        with open(s.runtime(team) / "journal.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row) + "\n")
    def intent(s, team, work, tree, attempt="a1", holder="h#0", state="opened"):
        path = s.runtime(team) / "launch" / ("%s@%s.intent" % (work, attempt))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"FT2_HOLDER": holder, "state": state, "worktree": str(tree), "at": attempt}), encoding="utf-8")
    def job(s, team, work, tree, attempt="a1", state="opened"):
        s.dispatch(team, work, attempt), s.intent(team, work, tree, attempt, state=state)


def counted(kf):   # ends._rows 부름 셈(원본 감쌈) · 반환 = 셈 목록
    real, seen = kf.ends._rows, []
    kf.ends._rows = lambda k, team: (seen.append(team), real(k, team))[1]
    return seen
def rp(path):
    return os.path.realpath(str(path))
def rnd(kf, k, teams):   # keeper._round 나노 모으기 꼴 그대로(팀마다 got.update · Cut = 모은 것만)
    got = {}
    try:
        for team in teams:
            got.update(kf.nanos(k, [team]))
    except Cut:
        pass
    return got


def c1(kf, w):   # ① linked worktree 2개(같은 리포 nano/a · nano/b) → {공용 폴더: [nano/a, nano/b]} · git 0
    repo = w.repo()
    for work in ("a", "b"):
        w.job("t", work, w.linked(repo, work))
    k = K(w.root)
    assert kf.nanos(k, ["t"]) == {rp(repo / ".git"): ["nano/a", "nano/b"]} and k.calls == [], k.calls
def c2(kf, w):   # ② 일반 clone(.git 폴더 · HEAD nano/c) → {clone/.git: [nano/c]} · git 0
    clone = w.repo("clone")
    git(clone, "checkout", "-q", "-b", "nano/c")
    w.job("t", "c", clone)
    k = K(w.root)
    assert kf.nanos(k, ["t"]) == {rp(clone / ".git"): ["nano/c"]} and k.calls == [], k.calls
def c3(kf, w):   # ③ worktree HEAD = main · detached → 가지 0 · git 0
    repo = w.repo()
    w.job("t", "m", repo)   # 리포 본체 HEAD = main
    tree = w.linked(repo, "d")
    git(tree, "checkout", "-q", "--detach")
    w.job("t", "d", tree)
    k = K(w.root)
    assert kf.nanos(k, ["t"]) == {} and k.calls == [], k.calls
def c4(kf, w):   # ④ commondir 상대(«../..») · 절대 두 꼴 → 같은 공용 폴더 키 1개
    repo = w.repo()
    w.job("t", "a", w.linked(repo, "a"))
    w.job("t", "b", w.linked(repo, "b"))
    rel = repo / ".git" / "worktrees" / "b" / "commondir"
    assert rel.read_text(encoding="utf-8").strip() == "../.."
    rel.write_text(rp(repo / ".git") + "\n", encoding="utf-8")
    k = K(w.root)
    assert kf.nanos(k, ["t"]) == {rp(repo / ".git"): ["nano/a", "nano/b"]} and k.calls == [], k.calls
def c5(kf, w):   # ⑤ .git 에 gitdir 줄 없음 · gitdir 경로 없음 · HEAD 없음 → 그 worktree 만 가짜 git 2회 · 결과 = git 길 · 예외 0
    repo, fake = w.repo(), {}
    w.job("t", "ok", w.linked(repo, "ok"))
    for work, body in (("x", "not a gitdir line\n"), ("y", "gitdir: %s\n" % (w.tmp / "nowhere")), ("z", None)):
        tree = w.tmp / "bad" / work
        tree.mkdir(parents=True)
        if body is None:   # gitdir 은 있으나 HEAD 없음
            (w.tmp / "gd").mkdir()
            body = "gitdir: %s\n" % (w.tmp / "gd")
        (tree / ".git").write_text(body, encoding="utf-8")
        fake[str(tree)] = {"rev-parse": "nano/" + work, "common": str(w.tmp / "common")}
        w.job("t", work, tree)
    k = K(w.root, fake=fake)
    got = kf.nanos(k, ["t"])
    assert got == {rp(repo / ".git"): ["nano/ok"], rp(w.tmp / "common"): ["nano/x", "nano/y", "nano/z"]}, got
    assert sorted(r for r, _ in k.calls) == sorted(list(fake) * 2), k.calls
def c6(kf, w):   # ⑥ 한 팀 안 닫힌 dispatch 5 · intent 3개 opened 아님(대체 길) → _rows 1회 · 결과 같음 · _rows 원복
    repo = w.repo()
    for i in range(5):
        tree = w.linked(repo, "w%d" % i)
        if i < 3:   # 최신 a2 = launching · 옛 a1 = opened(같은 holder) → 대체 길로 a1 worktree
            w.dispatch("t", "w%d" % i), w.intent("t", "w%d" % i, tree)
            w.job("t", "w%d" % i, w.tmp / "none", attempt="a2", state="launching")
        else:
            w.job("t", "w%d" % i, tree)
    seen = counted(kf)
    wrapped, k = kf.ends._rows, K(w.root)
    got = kf.nanos(k, ["t"])
    assert got == {rp(repo / ".git"): ["nano/w%d" % i for i in range(5)]} and seen == ["t"], (got, seen)
    assert kf.ends._rows is wrapped
def c7(kf, w):   # ⑦ _rows None(journal 깨짐) 팀 1 + 정상 팀 1 → 실패 팀 0가지 · 정상 팀 그대로
    repo = w.repo()
    w.job("bad", "a", w.linked(repo, "a"))
    with open(w.runtime("bad") / "journal.jsonl", "a", encoding="utf-8") as fh:
        fh.write("{broken\n")
    w.job("good", "b", w.linked(repo, "b"))
    assert kf.ends._rows(K(w.root), "bad") is None
    got = kf.nanos(K(w.root), ["bad", "good"])
    assert got == {rp(repo / ".git"): ["nano/b"]}, got
def c9(kf, w):   # ⑨ 예산 문 — 만료(−1) = Cut 1 · 판독 0 · 수집 0 / 앞 팀 보존 · 지금 팀 부분 버림 · Cut 1 / 바퀴 밖(None) = 끝까지
    repo0, repo = w.repo("repo0"), w.repo()
    w.job("t0", "p", w.linked(repo0, "p"))
    w.job("t", "a", w.linked(repo, "a"))
    w.job("t", "b", w.linked(repo, "b"))
    heads, real = [], getattr(kf, "_head", None)
    if real:   # worktree 파일 판독 셈(기준판 = 함수 없음)
        kf._head = lambda tree: (heads.append(tree), real(tree))[1]
    counted(kf)
    wrapped = kf.ends._rows
    k = K(w.root, left=lambda: -1.0)
    assert rnd(kf, k, ["t0"]) == {} and k.cuts == 1 and heads == [], (k.cuts, heads)
    assert kf.ends._rows is wrapped
    k = K(w.root)
    k._left = lambda: -1.0 if str(w.runtime("t") / "launch" / "a@a1.intent") in k.reads else 5.0   # 지금 팀 a 판독 뒤 만료
    got = rnd(kf, k, ["t0", "t"])
    assert got == {rp(repo0 / ".git"): ["nano/p"]} and k.cuts == 1, (got, k.cuts)
    assert kf.ends._rows is wrapped
    k = K(w.root)
    got = rnd(kf, k, ["t0", "t"])
    assert got == {rp(repo0 / ".git"): ["nano/p"], rp(repo / ".git"): ["nano/a", "nano/b"]} and k.cuts == 0, got
CASES = {"c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c6": c6, "c7": c7, "c9": c9}
MUTANTS = {"M1": ("    seen = _head(tree)\n", "    seen = None\n", ("c1", "c2")),                       # 파일 판독 대신 늘 git
           "M2": ("os.path.join(gitdir, fh.read().strip())", "os.path.abspath(fh.read().strip())", ("c4",)),   # commondir 상대 경로를 cwd 기준으로
           "M3": ("    seen = _head(tree)\n", "    seen = _head(tree) or ('', '')\n", ("c5",)),          # 못 읽음 = git 대신 가지 0
           "M4": ("rows if t_ == team else keep(k_, t_)", "keep(k_, t_)", ("c6",)),                          # _rows 를 work 마다 다시
           "M5": ("    if (left := k.left()) is not None and left < MIN_S:", "    if False:", ("c9",))}         # 예산 문 지움


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](load(FT2, "kf_r2122_" + name), W(tmp_path))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):   # 변이 = 사본에서만 → 사례 FAIL · 원본으로 같은 사례 1회 더 = PASS(반대 결과 대조)
    old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KF).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KF).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        (tmp_path / ("o" + case)).mkdir(), (tmp_path / ("x" + case)).mkdir()
        CASES[case](load(FT2, "kf_r2122_o_" + name + case), W(tmp_path / ("o" + case)))
        with pytest.raises(AssertionError):
            CASES[case](load(tree, "kf_r2122_x_" + name + case), W(tmp_path / ("x" + case)))
