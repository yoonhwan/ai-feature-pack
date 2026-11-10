"""r486 — sparse 나노 워크트리(r444)에서 «tracked 인데 디스크에 없는» 팀 폴더를 SPARSE-HIDDEN 으로 말하는가.

픽스처 = 임시 리포(design/TEAMS.md 팀 a·b·c · a·b 폴더만 커밋) + sparse 워크트리(/* !/design/teams/*/ /design/teams/a/).
실 루트·외부 호출 0 · GIT_* env 0(BOOT 25).
"""
import importlib.util
import os
import subprocess
from pathlib import Path

import pytest
import sys as _rsg_sys  # noqa: E402  r541
_rsg_sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

ROOT = Path(__file__).resolve().parents[2]
COPIES = [ROOT / "harness/kit/fable-team/bin", ROOT / "harness/bin"]
TEAMS = "| 팀 | 폴더 |\n|---|---|\n| a | design/teams/a/ | x |\n| b | design/teams/b/ | x |\n| c | design/teams/c/ | x |\n"


def _env():
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k not in ("FT_REPO_ROOT", "FT_TEAMS_MD")}
    env["FT_ALLOW_TRACKED_BIN"] = "1"
    return env


def _git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True, env=_env())


@pytest.fixture(scope="module")
def repo(tmp_path_factory):
    for k in [k for k in os.environ if k.startswith("GIT_")]:
        os.environ.pop(k)
    d = tmp_path_factory.mktemp("r486")
    full = d / "full"
    (full / "design/teams/a").mkdir(parents=True)
    (full / "design/teams/b").mkdir(parents=True)
    (full / "design/TEAMS.md").write_text(TEAMS, encoding="utf-8")
    (full / "design/teams/a/x.md").write_text("a\n", encoding="utf-8")
    (full / "design/teams/b/y.md").write_text("b\n", encoding="utf-8")
    _git(full, "init", "-q")
    _git(full, "add", "-A")
    _git(full, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
    sparse = d / "sparse"
    _git(full, "worktree", "add", "-q", "--no-checkout", str(sparse), "-b", "nano/x", "HEAD")
    subprocess.run(["git", "-C", str(sparse), "sparse-checkout", "set", "--no-cone", "--stdin"],
                   input="/*\n!/design/teams/*/\n/design/teams/a/\n", text=True, check=True, capture_output=True, env=_env())
    _git(sparse, "checkout", "-q")
    assert (sparse / "design/teams/a/x.md").is_file() and not (sparse / "design/teams/b").exists()
    return full, sparse


def _lib(bindir):
    spec = importlib.util.spec_from_file_location(f"ftl_{bindir.parent.name}", bindir / "ft_team_lib.py")
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_a_sparse_hidden_other_team(repo, bindir):
    lib = _lib(bindir)
    _, sparse = repo
    with pytest.raises(lib.SparseHidden) as e:
        lib.team_in(sparse, "b")
    assert isinstance(e.value, lib.TeamPathError)
    msg = str(e.value)
    assert msg.startswith("SPARSE-HIDDEN design/teams/b ") and "ft-scratch-repo.sh" in msg
    with pytest.raises(lib.SparseHidden):
        lib.team_in_ref(sparse, "b", "HEAD")


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_b_own_team_ok(repo, bindir):
    lib = _lib(bindir)
    _, sparse = repo
    assert lib.team_in(sparse, "a") == sparse / "design/teams/a"
    assert lib.team_in_ref(sparse, "a", "HEAD") == sparse / "design/teams/a"


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_c_full_checkout_ok(repo, bindir):
    lib = _lib(bindir)
    full, _ = repo
    assert lib.team_in(full, "b") == full / "design/teams/b"
    assert lib.team_in_ref(full, "b", "HEAD") == full / "design/teams/b"


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_d_untracked_folder_keeps_old_behavior(repo, bindir):
    lib = _lib(bindir)
    full, sparse = repo
    for root in (full, sparse):
        assert lib.team_in(root, "c") == root / "design/teams/c"  # 없음 = 옛 동작 그대로(경로 반환)
        with pytest.raises(lib.TeamPathError) as e:
            lib.team_in_ref(root, "c", "HEAD")
        assert not isinstance(e.value, lib.SparseHidden) and "SPARSE-HIDDEN" not in str(e.value)
        assert "실재 후보 0개" in str(e.value)
    # 후보 목록은 «실재 여부 무관» 그대로 — sparse 에서도 예외 0
    assert lib.team_cands_ref(sparse, "b", "HEAD") == []


def _sh(bindir, root, script):
    return subprocess.run(["bash", "-c", f'. "{bindir}/ft-team-lib.sh"; {script}'], cwd=root,
                          capture_output=True, text=True, env=_env())


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_shell_team_root(repo, bindir):
    full, sparse = repo
    r = _sh(bindir, sparse, "ft_team_in \"$PWD\" b")
    assert r.returncode == 1 and r.stdout == ""
    lines = r.stderr.strip().splitlines()
    assert len(lines) == 1 and lines[0].startswith("SPARSE-HIDDEN design/teams/b ") and "ft-scratch-repo.sh" in lines[0]
    r = _sh(bindir, sparse, "ft_team_in \"$PWD\" a")
    assert r.returncode == 0 and r.stdout.strip() == f"{sparse}/design/teams/a"
    r = _sh(bindir, full, "ft_team_in \"$PWD\" b")
    assert r.returncode == 0 and r.stdout.strip() == f"{full}/design/teams/b" and r.stderr == ""
    r = _sh(bindir, sparse, "ft_team_in \"$PWD\" c")
    assert r.returncode == 0 and "SPARSE-HIDDEN" not in r.stderr
    # 후보 목록 함수는 «실재 여부 무관» — sparse 에서도 rc0 · SPARSE 글자 0
    r = _sh(bindir, sparse, "ft_team_cands_ref \"$PWD\" b HEAD")
    assert r.returncode == 0 and r.stdout.splitlines()[0] == f"{sparse}/design/teams/b" and "SPARSE" not in r.stderr


def test_python_shell_same_message(repo):
    lib = _lib(COPIES[0])
    _, sparse = repo
    with pytest.raises(lib.SparseHidden) as e:
        lib.team_in(sparse, "b")
    r = _sh(COPIES[0], sparse, "ft_team_in \"$PWD\" b")
    assert r.stderr.strip() == str(e.value)


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_spawn_body_has_sparse_line(bindir):
    text = (bindir / "ft-nano-spawn.sh").read_text(encoding="utf-8")
    spx = [ln for ln in text.splitlines() if ln.startswith("_SPX=")]
    assert len(spx) == 1 and "광역 pytest 금지" in spx[0] and "ft-scratch-repo.sh <base>" in spx[0] and "SPARSE-HIDDEN" in spx[0]
    body = [ln for ln in text.splitlines() if ln.startswith("BODY=")]
    assert len(body) == 1 and "${_SPX}" in body[0]
    assert text.count('echo "BODY+${_SPX}"') == 1  # dry-run PLAN 바로 뒤에도 같은 글자
    plan = text.index('echo "PLAN seat=')
    assert plan < text.index('echo "BODY+${_SPX}"') < text.index('if [ "$DRY" = 1 ]; then [ "$RESEARCH"')
    assert subprocess.run(["bash", "-n", str(bindir / "ft-nano-spawn.sh")]).returncode == 0
    assert subprocess.run(["bash", "-n", str(bindir / "ft-team-lib.sh")]).returncode == 0
