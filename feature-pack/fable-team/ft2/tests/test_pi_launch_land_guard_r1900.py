"""r1900 첫 본문 착지 금지 1구 + pre-push 나노 가드 (반례 ①~⑦ · 변이 M1~M3).
①은 launch_plan.first_body 직접 · ②~⑦은 로컬 bare repo + 훅 사본(tests/fixtures/byz-pre-push-r1900 = 실제 BYZ 훅 + 3줄)
+ tools/pre-push-nano-guard.sh. 실제 원격·명부·장부·설치 0 · sleep 0. 변이는 ft2 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, os, shutil, subprocess  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
LAND = ("· 산출 = 가지 nano/<work> push + master 보고까지 · main·ops/main-base push·병합·착지·설치·심링크·가지 삭제 0"
        "(= master·h 몫) · AGENTS.md «Landing the Plane» 은 이 좌석에 적용 0")
NANO, SEAT_ENV = "byz-harness-nano-x#1", ("FT2_HOLDER", "FT_SEAT_NAME")

def c1(tmp, ft2):   # ① 본문 끝 = 고정 1구 · body_mark = r1895 꼴 그대로
    spec = importlib.util.spec_from_file_location("lp_r1900", str(ft2 / "adapters" / "pi" / "launch_plan.py"))
    lp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(lp)
    env = {"FT2_TEAM": "harness", "FT2_WORK": "r9", "FT2_ATTEMPT": "a1", "FT2_HOLDER": NANO}
    mark, text = lp.first_body(env, ("/r", "origin/main", "design/harness/indices"))
    assert mark == "[발주] ft2 harness r9@a1" and text.startswith(mark + " 좌석 " + NANO) and text.endswith(" " + LAND), text

def git(cwd, *a, env=None, ok=True):
    e = {k: v for k, v in os.environ.items() if k not in SEAT_ENV and not k.startswith("GIT_")}
    p = subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=cwd, env=dict(e, **(env or {})),
                       capture_output=True, text=True, timeout=20)
    assert not ok or p.returncode == 0, (a, p.stderr)
    return p

def repo(tmp, ft2):   # bare 원격 + clone(main 1커밋 · origin/main) + 훅 폴더(훅 사본 + 가드)
    hooks = tmp / "hooks"
    hooks.mkdir()
    shutil.copy(ft2 / "tests" / "fixtures" / "byz-pre-push-r1900", hooks / "pre-push")
    shutil.copy(ft2 / "tools" / "pre-push-nano-guard.sh", hooks / "pre-push-nano-guard.sh")
    os.chmod(hooks / "pre-push", 0o755)
    git(tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
    git(tmp, "clone", "-q", str(tmp / "remote.git"), "c")
    c = tmp / "c"
    git(c, "commit", "-q", "--allow-empty", "-m", "base")
    git(c, "push", "-q", "origin", "HEAD:main")
    git(c, "config", "core.hooksPath", str(hooks))
    git(c, "commit", "-q", "--allow-empty", "-m", "next")
    return c

def tip(c, ref):
    p = git(c, "ls-remote", "origin", ref)
    return p.stdout.split()[0] if p.stdout else None

def push(c, env, *refs):
    return git(c, "push", "origin", *refs, env=env, ok=False)

def denied(c, env, *refs):
    before = {r: tip(c, "refs/heads/" + r.split(":")[1]) for r in refs}
    p = push(c, env, *refs)
    assert p.returncode != 0 and "PUSH_DENIED" in p.stderr, p.stderr
    assert {r: tip(c, "refs/heads/" + r.split(":")[1]) for r in refs} == before
    return p

def c2(tmp, ft2):   # ② 나노 env → main push 거절 · 원격 main 그대로
    assert "나노 좌석 %s 의 refs/heads/main" % NANO in denied(repo(tmp, ft2), {"FT2_HOLDER": NANO}, "HEAD:main").stderr

def c3(tmp, ft2):   # ③ 나노 env → nano/x push 통과
    c = repo(tmp, ft2)
    assert push(c, {"FT2_HOLDER": NANO}, "HEAD:nano/x").returncode == 0 and tip(c, "refs/heads/nano/x")

def c4(tmp, ft2):   # ④ env 없음(master·사람) → main push 통과
    c = repo(tmp, ft2)
    assert push(c, {}, "HEAD:main").returncode == 0 and tip(c, "refs/heads/main") == git(c, "rev-parse", "HEAD").stdout.strip()

def c5(tmp, ft2):   # ⑤ 1.x 좌석(FT_SEAT_NAME) → ops/main-base push 거절
    c = repo(tmp, ft2)
    git(c, "push", "-q", "origin", "HEAD~1:refs/heads/ops/main-base")
    denied(c, {"FT_SEAT_NAME": "byz-planner-nano-y#0"}, "HEAD:ops/main-base")

def c6(tmp, ft2):   # ⑥ 연결 회귀: 가드 통과(nano/x) 뒤에도 기존 gate 가 같은 ref 줄을 받아 제품코드 거절
    c = repo(tmp, ft2)
    git(c, "switch", "-q", "-c", "feat/v6-realtime-live")
    (c / "worker").mkdir()
    (c / "worker" / "a.py").write_text("x = 1\n", encoding="utf-8")
    git(c, "add", "worker")
    git(c, "commit", "-q", "-m", "product")
    p = push(c, {"FT2_HOLDER": NANO}, "HEAD:nano/x")
    assert p.returncode != 0 and "제품코드" in p.stderr and tip(c, "refs/heads/nano/x") is None, p.stderr

def c7(tmp, ft2):   # ⑦ mixed refs(nano/x + main) → 거절 · 두 ref 다 그대로
    denied(repo(tmp, ft2), {"FT2_HOLDER": NANO}, "HEAD:nano/x", "HEAD:main")

CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}
MUTANTS = {"M1": ("adapters/pi/launch_plan.py", [(" + LAND", "")], "①"),
           "M2": ("tools/pre-push-nano-guard.sh", [("refs/heads/main|refs/heads/ops/main-base)", "refs/heads/main)")], "⑤"),
           "M3": ("tests/fixtures/byz-pre-push-r1900", [("refs=$(cat)", "refs="),
                  ("printf '%s\\n' \"$refs\" | sh", "sh"), ("printf '%s\\n' \"$refs\" | gate", "gate")], "⑥")}

@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](tmp_path, FT2)

@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, subs, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    for old, new in subs:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / rel).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "w1", tree)
    CASES[case](tmp_path / "w2", FT2)
