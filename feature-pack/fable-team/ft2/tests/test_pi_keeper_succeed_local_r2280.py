"""r2280 ft2 keeper 승계 C2 — 구 나노 커밋을 원격 push 대신 로컬 ref 로 보존한다 (카드 반례 ①~⑤ · 변이 M1~M3 · 사전 DA#29 보정).
입력 = r2276 시험 대역(실제 core · 실제 launch.py · bare 원격) + 업무 repo pre-push 훅 대역(호출 기록 1줄 + 10초 · BYZ 물리 게이트 꼴)
+ ④ git 대역(for-each-ref --points-at 만 rc 128 또는 8초 · 나머지 = 실제 git). 기준판(push 갈래) = ① ③ Red.
"""
import importlib.util, os, shutil, subprocess  # noqa: E401
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("r2276_cases_for_r2280", str(FT2 / "tests" / "test_pi_keeper_succeed_r2276.py"))
S = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(S)
B, W2, M, H0, H1 = S.B, S.W2, S.M, S.H0, S.H1
KEEP = "refs/ft2/keep/%s/g1" % W2   # claim 으로 받은 work = dispatch 0 → attempt = g<세대>
REAL_GIT = shutil.which("git")
HOOK = '#!/bin/sh\necho push >> "%s"\nsleep 10\nexit 1\n'
FAKE_GIT = ('#!/bin/sh\ncase " $* " in *" for-each-ref --points-at "*) %s ;; esac\nexec "%s" "$@"\n')


def world(tmp, mp, ft2=FT2):
    """r2276 world + pre-push 훅 대역(push 호출 기록 · 10초 · 거절)."""
    w = S.world(tmp, mp, ft2)
    w.pushlog = tmp / "push.log"
    hook = Path(B._git(w.repo, "rev-parse", "--git-common-dir"))
    hook = (hook if hook.is_absolute() else w.repo / hook) / "hooks" / "pre-push"
    B._put(hook, HOOK % w.pushlog)
    os.chmod(hook, 0o755)
    return w


def pushes(w):
    return w.pushlog.read_text(encoding="utf-8").splitlines() if w.pushlog.exists() else []


def ref(tree, name):
    done = subprocess.run(["git", "-C", str(tree), "rev-parse", "--verify", "-q", name], capture_output=True, text=True, timeout=25)
    return done.stdout.strip()


def fetched(tree):
    path = Path(B._git(tree, "rev-parse", "--git-path", "FETCH_HEAD"))
    return (path if path.is_absolute() else Path(tree) / path).exists()


def ok(w, lines, tree, name):
    """승계 SUCCEEDED · push 0 · fetch 0 · launch --base = 구 HEAD · 인계 바탕 줄 = 구 HEAD + 보존 이름."""
    assert [x for x in lines if x.startswith("SUCCEEDED harness %s %s -> %s" % (W2, H0, H1))], lines
    assert pushes(w) == [] and S.remote(w, W2) in ("", w.c1) and not fetched(tree)
    last = S.dispatches(w, W2)[-1]
    intent = S.json.loads((w.runtime() / "launch" / ("%s@%s.intent" % (W2, last["attempt"]))).read_text(encoding="utf-8"))
    assert intent["base_sha"] == w.c2 and intent["FT2_HOLDER"] == H1
    text = "\n".join(w.notes())
    assert "구 HEAD %s · 보존 %s" % (w.c2, name) in text[text.index("send %s " % H1):], text


def held(w, lines, word):
    """판정 불가 1줄 · 승계 0 · kill 0 · push 0."""
    assert [x for x in lines if x.startswith("판정 불가 harness") and word in x], lines
    assert not [x for x in lines if x.startswith("SUCCEEDED")] and pushes(w) == []
    S.untouched(w, W2)


def c1(w):   # ① 구 worktree 가지 nano/<work> · 원격 가지 0 · push 대역 10초 → push 0 · SUCCEEDED · keep ref 0
    tree = S.claimed(w)
    B._git(tree, "checkout", "-q", "-b", "nano/%s" % W2)
    S.marker(w, 10 * M)
    ok(w, w.round(), tree, "nano/%s" % W2)
    assert ref(tree, KEEP) == "" and S.remote(w, W2) == ""


def c2(w):   # ② 원격 가지 있음 · 로컬이 앞섬 → push 0 · fetch 0 · SUCCEEDED · 원격 그대로
    tree = S.claimed(w)
    B._git(w.repo, "push", "-q", "--no-verify", "origin", "%s:refs/heads/nano/%s" % (w.c1, W2))
    B._git(tree, "checkout", "-q", "-b", "nano/%s" % W2)
    S.marker(w, 10 * M)
    ok(w, w.round(), tree, "nano/%s" % W2)
    assert S.remote(w, W2) == w.c1


def c3(w):   # ③ 분리 HEAD · 끝 가진 가지 0 → keep ref = HEAD · SUCCEEDED · push 0
    tree = S.claimed(w)
    S.marker(w, 10 * M)
    ok(w, w.round(), tree, KEEP)
    assert ref(tree, KEEP) == w.c2 and S.remote(w, W2) == ""


def c3c(w):  # ③ⓒ 같은 keep ref 가 다른 sha 로 이미 있음 → 덮기 0 · 판정 불가 1줄 · 승계 0 · kill 0
    tree = S.claimed(w)
    B._git(tree, "update-ref", KEEP, w.c1)
    S.marker(w, 10 * M)
    held(w, w.round(), "keep ref 충돌")
    assert ref(tree, KEEP) == w.c1


def c3d(w):  # ③′ 같은 keep ref 가 이미 HEAD 와 같은 sha → 보존 됨(다시 쓰기 0) · SUCCEEDED
    tree = S.claimed(w)
    B._git(tree, "update-ref", KEEP, w.c2)
    S.marker(w, 10 * M)
    ok(w, w.round(), tree, KEEP)


def _fake(w, body):
    B._put(w.tmp / "bin" / "git", FAKE_GIT % (body, REAL_GIT))
    os.chmod(w.tmp / "bin" / "git", 0o755)


def c4(w, body="echo boom >&2; exit 128"):   # ④ for-each-ref 대역 rc 128 → 판정 불가 1줄 · 승계 0 · 쓰기 0
    tree = S.claimed(w)
    S.marker(w, 10 * M)
    _fake(w, body)
    held(w, w.round(), "for-each-ref")
    assert ref(tree, KEEP) == ""


def c4b(w):  # ④′ for-each-ref 대역 8초 → 판정 불가 1줄 · 승계 0 · 쓰기 0
    tree = S.claimed(w)
    S.marker(w, 10 * M)
    _fake(w, "sleep 8; exit 0")
    lines = w.round()
    assert [x for x in lines if x.startswith("판정 불가 harness")], lines
    assert not [x for x in lines if x.startswith("SUCCEEDED")] and pushes(w) == [] and ref(tree, KEEP) == ""
    S.untouched(w, W2)


CASES = {"①": c1, "②": c2, "③": c3, "③ⓒ": c3c, "③′": c3d, "④": c4, "④′": c4b, "⑤": S.c4}
KS = "adapters/pi/keeper_succeed.py"
MUTANTS = {"M1": (('"update-ref", keep, "HEAD", ""', '"update-ref", keep, "HEAD"'), c3c),
           "M2": (("k = self.k  # C1", 'k = self.k; self.k.git(tree, "push", "origin", "HEAD:refs/heads/nano/" + work, retry=1)'), c1),
           "M3": (('rc = k.git(tree, "update-ref", keep, "HEAD", "")[0]', "rc = 0"), c3)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    (old, new), case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KS).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KS).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(world(tmp_path / "w1", monkeypatch, tree))
    case(world(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
