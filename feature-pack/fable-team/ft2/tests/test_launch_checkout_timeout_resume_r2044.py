"""r2044 checkout 시간 초과 → 이 워크트리 index.lock 만 정리 + --resume 1회 이어 열기 (반례 ①~⑥ · 변이 M1~M2 · ⑦ = 기존 시험 그대로).
임시 git 리포 + 진짜 launch.py(감싼 실행기 = checkout 호출 상한만 짧게 · 그 밖 git 25초 · 상한 값 변경 0) · 가짜 git(진짜 git 에 넘김 ·
checkout 만 FAKE_HANG(lock 만들고 멈춤 = 상한 넘김) 또는 FAKE_CO(rc1)) · 가짜 tmux(has-session rc = FAKE_ALIVE · 기본 1) · sleep 0(시험 쪽).
"""
import importlib.util, json, shutil, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
hw = _mod("r2044_hw", HERE / "test_launch_half_worktree_r1967.py")
pl = hw.pl
GIT = '#!/bin/sh\necho "$*" >> "$GLOG"\ncase " $* " in\n' \
      '  *" checkout -q "*) if [ -n "$FAKE_HANG" ]; then cd "$2" && eval "$FAKE_HANG"; exec sleep 30; fi\n' \
      '    if [ -n "$FAKE_CO" ]; then cd "$2" && eval "$FAKE_CO"; exit 1; fi;;\nesac\nexec "$REAL_GIT" "$@"\n'
WRAP = '''import importlib.util, sys
spec = importlib.util.spec_from_file_location("ft2_r2044_launch", %r)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
real = m.call
m.call = lambda cmd, cwd, env, t: real(cmd, cwd, env, 1.5 if list(cmd[-2:]) == ["checkout", "-q"] else t)
sys.exit(m.main(sys.argv[1:]))
'''
PART = 'echo 2 > g; touch "$("$REAL_GIT" rev-parse --git-path index.lock)"'   # 끊긴 checkout = 쓴 파일 1개(??) + 죽은 git 의 lock
def setup(tmp, ft2, pre=None):
    root, fake = hw.world(tmp)
    (fake / "git").write_text(GIT, encoding="utf-8")
    (tmp / "wrap.py").write_text(WRAP % str(ft2 / "adapters" / "pi" / "launch.py"), encoding="utf-8")
    if pre:
        pre(root)
    return root, fake
def run(tmp, root, fake, *extra, **env):
    base = dict(REAL_GIT=shutil.which("git"), TLOG=str(tmp / "tmux.log"), GLOG=str(tmp / "git.log"), MARK=str(tmp / "mark"))
    out, rc = pl._launch(root, fake, tmp / "wrap.py", extra=extra, env_extra=dict(base, **env))
    logs = [(tmp / n).read_text().splitlines() if (tmp / n).exists() else [] for n in ("tmux.log", "git.log")]
    return out, rc, json.loads(pl._intent(root).read_text(encoding="utf-8")), logs
def lock(root):
    return root / ".git" / "worktrees" / pl._worktree(root).name / "index.lock"
def c1(tmp, ft2):   # ① 시간 초과 · 영수 있음 → 보존 · lock 없음 · resumable=checkout
    root, fake = setup(tmp, ft2)
    out, rc, it, (tlog, _) = run(tmp, root, fake, FAKE_HANG=PART)
    assert (rc, it["state"], it["step"], it.get("resumable")) == (2, "failed", "git checkout", "checkout"), (out, it)
    assert it["cleanup"].startswith("보존") and pl._worktree(root).is_dir() and not lock(root).exists(), it
    assert "이어 열기 가능(checkout)" in out["reason"] and "new-session" not in tlog, (out, tlog)
    return root, fake
def c2(tmp, ft2):   # ② ① 뒤 --resume → opened · tmux new-session 1회
    root, fake = c1(tmp, ft2)
    out, rc, it, (tlog, _) = run(tmp, root, fake, "--resume", FAKE_ALIVE="0")
    assert (rc, out["result"], out.get("opened"), it["state"]) == (0, "접수 성공", True, "opened"), (out, it)
    assert tlog.count("new-session") == 1 and (pl._worktree(root) / "a" / "f").exists(), tlog
    return root, fake
def c3(tmp, ft2):   # ③ ② 를 한 번 더 --resume → 이미 열림·이미 복구 예약 · 바깥 호출 0
    root, fake = c2(tmp, ft2)
    before = [(tmp / n).read_text() for n in ("tmux.log", "git.log")]
    out, rc, it, _ = run(tmp, root, fake, "--resume", FAKE_ALIVE="0")
    assert rc in (0, 1) and ("이미 열림" in out["reason"] or "이미 복구 예약" in out["reason"]) and it["state"] == "opened", out
    assert [(tmp / n).read_text() for n in ("tmux.log", "git.log")] == before
def c4(tmp, ft2):   # ④ checkout rc1(시간 초과 아님) → lock 손 0 · resumable 0 · --resume 거절
    root, fake = setup(tmp, ft2)
    out, rc, it, _ = run(tmp, root, fake, FAKE_CO=PART)
    assert (rc, it["step"], "resumable" in it) == (2, "git checkout", False) and lock(root).exists(), (out, it)
    out, rc, it, (tlog, _) = run(tmp, root, fake, "--resume", FAKE_ALIVE="0")
    assert (rc, it["state"]) == (2, "failed") and "의도에 남은 실패" in out["reason"] and "new-session" not in tlog, out
def c5(tmp, ft2):   # ⑤ 영수 없음(경로가 미리 있음) + 시간 초과 → lock 손 0 · resumable 0
    root, fake = setup(tmp, ft2, pre=lambda root: pl._worktree(root).mkdir(parents=True))
    out, rc, it, _ = run(tmp, root, fake, FAKE_HANG=PART)
    assert (rc, it["step"], "resumable" in it, it.get("cleanup")) == (2, "git checkout", False, "보존 · 생성 영수 없음"), (out, it)
    assert lock(root).exists(), it
def c6(tmp, ft2):   # ⑥ .git 파일 깨짐(index_lock 판독 실패) → 지우기 0 · resumable 0 · 본 리포 lock 손 0
    root, fake = setup(tmp, ft2)
    hang = 'L="$("$REAL_GIT" rev-parse --git-path index.lock)"; echo 2 > g; touch "$L" "$MAIN_LOCK"; echo broken > .git'
    out, rc, it, _ = run(tmp, root, fake, FAKE_HANG=hang, MAIN_LOCK=str(root / ".git" / "index.lock"))
    assert (rc, it["step"], "resumable" in it) == (2, "git checkout", False) and it["cleanup"].startswith("보존"), (out, it)
    assert lock(root).exists() and (root / ".git" / "index.lock").exists(), it
CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6}
LC, LA = "adapters/pi/launch_cleanup.py", "adapters/pi/launch.py"
MUTANTS = {"M1": (LC, "        os.unlink(lock)\n    except FileNotFoundError", "        pass\n    except FileNotFoundError", "①"),
           "M2": (LA, 'rc is None and step == "git checkout"', 'True', "④")}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](tmp_path, FT2)
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, case = MUTANTS[name]
    shutil.copytree(FT2, tree := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    [(tmp_path / sub).mkdir() for sub in ("w1", "w2")]
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "w1", tree)
    CASES[case](tmp_path / "w2", FT2)   # 원본으로 같은 사례 1회 더 = PASS
if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
