"""r495 — 쌍둥이 폴더(옛 꼴 design/<팀>/ + 새 꼴 design/teams/<팀>/ 둘 다 실재)를 team_in_ref·ft_team_in_ref 가 «ref 트리» 로 가르는가.

픽스처 = 임시 리포 · 체크아웃에 design/v65 + design/teams/v65 둘 다 · ref 3개(teams 만 · 둘 다 · 명단만).
ⓐ ref 한쪽 → 그 폴더 + WARN TWIN-STALE ⓑ ref 둘 다 → 명단 꼴 + WARN TWIN-BOTH ⓒ ref 둘 다 없음 → TeamPathError(후보 2개 · ref 에 둘 다 없음)
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
TEAMS = "| 팀 | 폴더 |\n|---|---|\n| v65 | `design/teams/v65/` | x |\n"


def _env():
    return {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k not in ("FT_REPO_ROOT", "FT_TEAMS_MD", "FT_TEAMS_REF")}


def _git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), "-c", "user.name=t", "-c", "user.email=t@t", *args],
                          check=True, capture_output=True, text=True, env=_env()).stdout.strip()


def _commit(repo, name, dirs):
    """ref <name> = 명단 + dirs 각 폴더에 keep 1파일(체크아웃·HEAD 무관 · 커밋은 plumbing)."""
    work = repo.parent / f"src-{name}"
    (work / "design").mkdir(parents=True)
    (work / "design/TEAMS.md").write_text(TEAMS, encoding="utf-8")
    for d in dirs:
        (work / d).mkdir(parents=True)
        (work / d / "keep").write_text("k\n", encoding="utf-8")
    _git(work, "init", "-q", "-b", "main")
    _git(work, "add", "-A")
    _git(work, "commit", "-qm", name)
    _git(repo, "fetch", "-q", str(work), f"main:refs/remotes/origin/{name}")


@pytest.fixture(scope="module")
def repo(tmp_path_factory):
    for k in [k for k in os.environ if k.startswith("GIT_")]:
        os.environ.pop(k)
    r = tmp_path_factory.mktemp("r495") / "co"
    r.mkdir()
    (r / "README").write_text("r\n", encoding="utf-8")
    _git(r, "init", "-q", "-b", "main")
    _git(r, "add", "-A")
    _git(r, "commit", "-qm", "base")
    _commit(r, "teams", ["design/teams/v65"])
    _commit(r, "both", ["design/teams/v65", "design/v65"])
    _commit(r, "onlylist", [])
    (r / "design/v65").mkdir(parents=True)
    (r / "design/teams/v65").mkdir(parents=True)
    return r


def _lib(bindir):
    spec = importlib.util.spec_from_file_location(f"ftl495_{bindir.parent.name}", bindir / "ft_team_lib.py")
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _sh(bindir, root, ref):
    return subprocess.run(["bash", "-c", f'. "{bindir}/ft-team-lib.sh"; ft_team_in_ref "$PWD" v65 {ref}'], cwd=root,
                          capture_output=True, text=True, env=_env())


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_a_ref_one_side_picks_it_with_stale_warn(repo, bindir, capsys):
    lib = _lib(bindir)
    assert lib.team_in_ref(repo, "v65", "origin/teams") == repo / "design/teams/v65"
    err = capsys.readouterr().err.strip().splitlines()
    assert err == [f"WARN TWIN-STALE {repo / 'design/v65'} (ref 에 없음 · 체크아웃 ref 뒤 1커밋)"]
    r = _sh(bindir, repo, "origin/teams")
    assert r.returncode == 0 and r.stdout.strip() == f"{repo}/design/teams/v65"
    assert r.stderr.strip().splitlines() == err  # 셸·파이썬 같은 글자


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_b_ref_both_picks_list_form_with_both_warn(repo, bindir, capsys):
    lib = _lib(bindir)
    assert lib.team_in_ref(repo, "v65", "origin/both") == repo / "design/teams/v65"
    err = capsys.readouterr().err.strip().splitlines()
    new, old = repo / "design/teams/v65", repo / "design/v65"
    assert err == [f"WARN TWIN-BOTH {new} {old} (ref 에 둘 다 · 명단 꼴 {new})"]
    r = _sh(bindir, repo, "origin/both")
    assert r.returncode == 0 and r.stdout.strip() == str(new) and r.stderr.strip().splitlines() == err


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_c_ref_neither_raises(repo, bindir, capsys):
    lib = _lib(bindir)
    with pytest.raises(lib.TeamPathError) as e:
        lib.team_in_ref(repo, "v65", "origin/onlylist")
    msg = str(e.value)
    assert msg.startswith("ERROR v65 폴더 실재 후보 2개 — 정확히 1개여야 한다(명단 origin/onlylist:design/TEAMS.md") and msg.endswith("(ref 에 둘 다 없음)")
    assert capsys.readouterr().err == ""
    r = _sh(bindir, repo, "origin/onlylist")
    assert r.returncode == 1 and r.stdout == "" and r.stderr.strip() == msg


@pytest.mark.parametrize("bindir", COPIES, ids=["kit", "bin"])
def test_d_single_hit_unchanged(repo, bindir, tmp_path, capsys):
    """쌍둥이 0(실재 1) → 지금과 같음 · WARN 0 · ls-tree 조회 0 에 해당(ref 에 그 폴더가 없어도 실재 1개면 그것)."""
    lib = _lib(bindir)
    (repo / "design/teams/v65").rmdir()
    try:
        assert lib.team_in_ref(repo, "v65", "origin/teams") == repo / "design/v65"
        assert capsys.readouterr().err == ""
        r = _sh(bindir, repo, "origin/teams")
        assert r.returncode == 0 and r.stdout.strip() == f"{repo}/design/v65" and r.stderr == ""
    finally:
        (repo / "design/teams/v65").mkdir()
