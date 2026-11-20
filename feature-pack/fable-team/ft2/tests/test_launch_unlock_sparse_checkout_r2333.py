"""r2333 좌석 열기 시간 초과 정리 — checkout 이 끊긴 뒤 이 워크트리 gitdir 에 남는 lock 3개(index · info/sparse-checkout · config.worktree)를 지운다 (반례 ①~⑨ · ②b · 변이 M1a·M1b~M4).
머리: unlock 은 시간 초과된 git 이 죽은 뒤에만 불린다(r2044 전제 그대로) — 그 git 이 부른 하위 명령이 sparse-checkout set 이면 남는 lock 은 index.lock 이 아니다.
임시 git 리포 + 진짜 launch.py(감싼 실행기 = checkout·sparse-checkout 호출 상한만 1.5초 · 그 밖 git 25초 · 상한 값 변경 0) · 가짜 git(진짜 git 에 넘김 ·
checkout 만 FAKE_HANG(lock 손으로 만들고 멈춤 = 상한 넘김) 또는 FAKE_CO(rc1)) · 가짜 tmux(has-session rc = FAKE_ALIVE · 기본 1) · sleep 0(시험 쪽).
"""
import importlib.util, json, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
hw = _mod("r2333_hw", HERE / "test_launch_half_worktree_r1967.py")
pl = hw.pl
GIT = '#!/bin/sh\necho "$*" >> "$GLOG"\ncase " $* " in\n' \
      '  *" checkout -q "*) if [ -n "$FAKE_HANG" ]; then cd "$2" && eval "$FAKE_HANG"; exec sleep 30; fi\n' \
      '    if [ -n "$FAKE_CO" ]; then cd "$2" && eval "$FAKE_CO"; exit 1; fi;;\nesac\nexec "$REAL_GIT" "$@"\n'
WRAP = '''import importlib.util, sys
spec = importlib.util.spec_from_file_location("ft2_r2333_launch", %r)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
real = m.call
short = lambda cmd: "sparse-checkout" in cmd or list(cmd[-2:]) == ["checkout", "-q"]
m.call = lambda cmd, cwd, env, t: real(cmd, cwd, env, 1.5 if short(cmd) else t)
sys.exit(m.main(sys.argv[1:]))
'''
G = 'G="$("$REAL_GIT" rev-parse --absolute-git-dir)"; mkdir -p "$G/info"; echo 2 > g; '   # 반쪽 checkout(?? g) = 보존 꼴
CLEAN = G.replace("echo 2 > g; ", "")   # 전부 «D  » = 치움 꼴(⑤)
INDEX, SPARSE = G + 'touch "$G/index.lock"', G + 'touch "$G/info/sparse-checkout.lock"'
BOTH, THREE = SPARSE + ' "$G/index.lock"', SPARSE + ' "$G/index.lock" "$G/config.worktree.lock"'
CONFIG, CHMOD = G + 'touch "$G/config.worktree.lock"', BOTH + '; chmod 0500 "$G/info"'
OUT = G + 'mkdir -p "$OUT/info"; printf \'gitdir: %s\\n\' "$OUT" > .git; touch "$OUT/index.lock" "$OUT/info/sparse-checkout.lock"'
MAIN = G + 'C="$("$REAL_GIT" rev-parse --path-format=absolute --git-common-dir)"; touch "$C/index.lock" "$C/info/sparse-checkout.lock"'
def run(tmp, ft2, hang=None, co=None, pre=None, env=None):
    root, fake = hw.world(tmp)
    (fake / "git").write_text(GIT, encoding="utf-8")
    (tmp / "wrap.py").write_text(WRAP % str(ft2 / "adapters" / "pi" / "launch.py"), encoding="utf-8")
    if pre:
        pre(root)
    base = dict(REAL_GIT=shutil.which("git"), TLOG=str(tmp / "tmux.log"), GLOG=str(tmp / "git.log"), MARK=str(tmp / "mark"))
    out, rc = pl._launch(root, fake, tmp / "wrap.py", env_extra=dict(base, FAKE_HANG=hang or "", FAKE_CO=co or "", **(env or {})))
    return root, out, rc, json.loads(pl._intent(root).read_text(encoding="utf-8"))
def gdir(root):
    return root / ".git" / "worktrees" / pl._worktree(root).name
def locks(root):
    return (gdir(root) / "index.lock", gdir(root) / "info" / "sparse-checkout.lock", gdir(root) / "config.worktree.lock")
def switched(out, it, rc):   # 공통 = checkout 시간 초과 → 보존 · resumable=checkout · 이어 열기 1줄
    assert (rc, it["state"], it["step"], it.get("resumable")) == (2, "failed", "git checkout", "checkout"), (out, it)
    assert it["cleanup"].startswith("보존") and "이어 열기 가능(checkout)" in out["reason"], (out, it)
def c1(tmp, ft2):   # ① 시간 초과 · 영수 ∧ 보존 · sparse-checkout.lock 만 → 지움 · resumable=checkout
    root, out, rc, it = run(tmp, ft2, hang=SPARSE)
    switched(out, it, rc)
    assert pl._worktree(root).is_dir() and not locks(root)[1].exists() and not locks(root)[0].exists(), it
    assert "new-session" not in (tmp / "tmux.log").read_text(), it
def c2(tmp, ft2):   # ② index.lock · sparse-checkout.lock 둘 다 → 둘 다 지움
    root, out, rc, it = run(tmp, ft2, hang=BOTH)
    switched(out, it, rc)
    assert [lock.exists() for lock in locks(root)[:2]] == [False, False], it
def c2b(tmp, ft2):  # ②b 셋 다 → 셋 다 지움 · config.worktree.lock 만 → 지움(기준판 = 남음)
    root, out, rc, it = run(tmp / "b1", ft2, hang=THREE)
    switched(out, it, rc)
    assert [lock.exists() for lock in locks(root)] == [False, False, False], it
    root, out, rc, it = run(tmp / "b2", ft2, hang=CONFIG)
    switched(out, it, rc)
    assert not locks(root)[2].exists(), it
def c3(tmp, ft2):   # ③ index.lock 만 → 지움(지금과 같음)
    root, out, rc, it = run(tmp, ft2, hang=INDEX)
    switched(out, it, rc)
    assert not locks(root)[0].exists(), it
def c4(tmp, ft2):   # ④ 영수 없음(경로가 미리 있음) → 두 lock 모두 남음 · resumable 0
    root, out, rc, it = run(tmp, ft2, hang=BOTH, pre=lambda root: pl._worktree(root).mkdir(parents=True))
    assert (rc, it["step"], "resumable" in it, it.get("cleanup")) == (2, "git checkout", False, "보존 · 생성 영수 없음"), (out, it)
    assert locks(root)[0].exists() and locks(root)[1].exists(), it
def c5(tmp, ft2):   # ⑤ 보존 아님(치움) → unlock 손 0 · resumable 0
    root, out, rc, it = run(tmp, ft2, co=CLEAN + 'touch "$G/index.lock" "$G/info/sparse-checkout.lock"')
    assert (rc, it["state"], it["step"], it.get("cleanup")) == (2, "failed", "git checkout", "치움"), (out, it)
    assert "resumable" not in it and "이어 열기 가능" not in out["reason"] and not pl._worktree(root).exists(), (out, it)
def c6(tmp, ft2):   # ⑥ sparse-checkout.lock 지우기 OSError(읽기 전용 폴더 흉내) → resumable 0 · index.lock 결과와 무관
    root = None
    try:
        root, out, rc, it = run(tmp, ft2, hang=CHMOD)
        assert (rc, it["state"], it["step"]) == (2, "failed", "git checkout") and it["cleanup"].startswith("보존"), (out, it)
        assert "resumable" not in it and "이어 열기 가능" not in out["reason"], (out, it)
        assert locks(root)[1].exists(), it
    finally:
        if root is not None and gdir(root).is_dir():
            (gdir(root) / "info").chmod(0o700)
def c7(tmp, ft2):   # ⑦ gitdir 이 worktrees 밖 → 손 0 · resumable 0
    outside = str(tmp / "outside")
    root, out, rc, it = run(tmp, ft2, hang=OUT.replace("$OUT", outside), env={"OUT": outside})
    assert (rc, it["state"], it["step"]) == (2, "failed", "git checkout") and it["cleanup"].startswith("보존"), (out, it)
    assert "resumable" not in it and Path(outside, "index.lock").exists() and Path(outside, "info", "sparse-checkout.lock").exists(), (out, it)
def c8(tmp, ft2):   # ⑧ 본 리포 .git/index.lock · .git/info/sparse-checkout.lock 은 그대로
    root, out, rc, it = run(tmp, ft2, hang=MAIN)
    switched(out, it, rc)
    assert (root / ".git" / "index.lock").exists() and (root / ".git" / "info" / "sparse-checkout.lock").exists(), it
def c9(tmp, ft2):   # ⑨ 끝까지 — 진짜 worktree add --no-checkout + sparse-checkout.lock 손으로 → unlock → sparse-checkout set rc0(기준판 = «File exists» fatal)
    root, _ = hw.world(tmp)
    cleaner = _mod("r2333_lc", ft2 / "adapters" / "pi" / "launch_cleanup.py")
    wt = pl._worktree(root)
    wt.parent.mkdir(parents=True, exist_ok=True)
    git = ["git", "-C", str(root)]
    subprocess.run(git + ["worktree", "add", "-q", "--no-checkout", "--detach", str(wt), "origin/main"], check=True, capture_output=True, timeout=25)
    inside = Path(subprocess.run(["git", "-C", str(wt), "rev-parse", "--absolute-git-dir"], check=True, capture_output=True, text=True, timeout=25).stdout.strip())
    (inside / "info").mkdir(parents=True, exist_ok=True)
    (inside / "info" / "sparse-checkout.lock").write_text("", encoding="utf-8")
    extra, note = cleaner.unlock({"worktree": str(wt)}, "0" * 40, dict(add_ok=True, path_new=True, cleanup="보존 · 시험"), "반쪽 보존(시험)")
    assert extra.get("resumable") == "checkout", (extra, note)
    done = subprocess.run(["git", "-C", str(wt), "sparse-checkout", "set", "--no-cone", "/*", "!/design/teams/*/"], capture_output=True, text=True, timeout=25)
    assert done.returncode == 0, done.stderr
CASES = {"①": c1, "②": c2, "②b": c2b, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9}
LC = "adapters/pi/launch_cleanup.py"
MUTANTS = {"M1a": (LC, '    return [index, os.path.join(gitdir, "info", "sparse-checkout.lock"),\n            os.path.join(gitdir, "config.worktree.lock")]',
                      '    return [index, os.path.join(gitdir, "config.worktree.lock")]', "①"),
           "M1b": (LC, ',\n            os.path.join(gitdir, "config.worktree.lock")]', "]", "②b"),
           "M2": (LC, 'if not (extra.get("add_ok") and extra.get("path_new") and str(extra.get("cleanup", "")).startswith("보존")):', "if False:", "④"),
           "M3": (LC, "    except OSError:\n        return False", "    except OSError:\n        return True", "⑥"),
           "M4": (LC, "gitdir = os.path.dirname(index)", "gitdir = os.path.dirname(os.path.dirname(os.path.dirname(index)))", "⑧")}
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
