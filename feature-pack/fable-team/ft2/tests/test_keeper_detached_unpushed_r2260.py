"""r2260 keeper unsafe — detached HEAD 의 커밋이 이름 다른 origin 가지에 있으면 «unpushed» 0 (카드 반례 ①~⑥ · 계약 O1 O2).
대역 = 임시 bare 리포(origin) + clone 1개 · 실 Keeper 인스턴스 · mail_gate = "" · done=True(hold 판독 0). 네트워크 0 · sleep 0 · 실 worktree 쓰기 0.
기준판(팩 origin/main 595fab27) = ① Red(«unpushed») · ②③④⑤ 같음 · ⑥ 새 길.
"""
import importlib.util
import os
import subprocess
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("ft2_keeper_r2260", str(FT2 / "adapters" / "pi" / "keeper.py"))
K = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(K)
O1 = "for-each-ref"


def git(cwd, *a):
    return subprocess.run(["git", "-C", str(cwd)] + list(a), capture_output=True, text=True, timeout=25, check=True).stdout.strip()


def repo(tmp):
    """origin(bare) · clone · main 커밋 1 push → (clone 경로, base sha)."""
    git(tmp, "init", "-q", "--bare", "-b", "main", str(tmp / "o.git"))
    git(tmp, "clone", "-q", str(tmp / "o.git"), str(tmp / "c"))
    c = tmp / "c"
    for k, v in (("user.name", "t"), ("user.email", "t@t"), ("commit.gpgsign", "false")):
        git(c, "config", k, v)
    git(c, "checkout", "-q", "-b", "main")
    commit(c, "base")
    git(c, "push", "-q", "origin", "main")
    return c, git(c, "rev-parse", "HEAD")


def commit(c, name):
    (c / name).write_text(name, encoding="utf-8")
    git(c, "add", "-A")
    git(c, "commit", "-q", "-m", name)


def keeper(tmp, rc=None):
    """실 Keeper · git 호출 기록 · rc 를 주면 O1 만 그 rc 로 바꾼다(가짜 git)."""
    (tmp / "root").mkdir(exist_ok=True)   # call() 의 cwd
    k = K.Keeper(str(tmp / "root"), env={**os.environ, "GIT_CONFIG_NOSYSTEM": "1"})
    real, k.calls = k.git, []

    def fake(repo_, *args, **kw):
        k.calls.append((args[:1], k.env.get("GIT_NO_LAZY_FETCH")))
        return (rc, "", "fake") if rc is not None and args[:1] == (O1,) else real(repo_, *args, **kw)
    k.git, k.mail_gate = fake, lambda *a: ""
    return k


def unsafe(k, c, base):
    return k.unsafe("harness", "w", "byz-harness-nano-w#0", {"worktree": str(c), "base_sha": base}, True)


def o1(k):
    return [lazy for head, lazy in k.calls if head == (O1,)]


def c1(tmp):   # ① detached · 커밋 1 · origin/nano/x 에 있음(이름 다름) → "" · O1 1회 · GIT_NO_LAZY_FETCH=1
    c, base = repo(tmp)
    git(c, "checkout", "-q", "--detach")
    commit(c, "x")
    git(c, "push", "-q", "origin", "HEAD:refs/heads/nano/x")
    k = keeper(tmp)
    assert unsafe(k, c, base) == "" and o1(k) == ["1"], k.calls


def c2(tmp):   # ② detached · 커밋 1 · origin 어디에도 없음 → «unpushed»
    c, base = repo(tmp)
    git(c, "checkout", "-q", "--detach")
    commit(c, "x")
    k = keeper(tmp)
    assert unsafe(k, c, base) == "unpushed" and o1(k) == ["1"], k.calls


def c3(tmp):   # ③ 가지 nano/x = origin/nano/x → "" · O1 부름 0
    c, base = repo(tmp)
    git(c, "checkout", "-q", "-b", "nano/x")
    commit(c, "x")
    git(c, "push", "-q", "origin", "nano/x")
    k = keeper(tmp)
    assert unsafe(k, c, base) == "" and o1(k) == [], k.calls


def c4(tmp):   # ④ 가지 nano/x · origin/nano/x 보다 1커밋 앞 · 다른 origin 가지에도 없음 → «unpushed»
    c, base = repo(tmp)
    git(c, "checkout", "-q", "-b", "nano/x")
    commit(c, "x")
    git(c, "push", "-q", "origin", "nano/x")
    commit(c, "y")
    k = keeper(tmp)
    assert unsafe(k, c, base) == "unpushed", k.calls


def c5(tmp):   # ⑤ detached · base 위 커밋 0 → "" · O1 부름 0
    c, base = repo(tmp)
    git(c, "checkout", "-q", "--detach")
    k = keeper(tmp)
    assert unsafe(k, c, base) == "" and o1(k) == [], k.calls


def c6(tmp):   # ⑥ O1 git rc≠0(가짜) → «git-error» · unpushed 0
    c, base = repo(tmp)
    git(c, "checkout", "-q", "--detach")
    commit(c, "x")
    git(c, "push", "-q", "origin", "HEAD:refs/heads/nano/x")
    k = keeper(tmp, rc=128)
    assert unsafe(k, c, base) == "git-error" and o1(k) == ["1"], k.calls


CASES = {"c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c6": c6}


@pytest.mark.parametrize("name", sorted(CASES))
def test_case(name, tmp_path):
    CASES[name](tmp_path)
