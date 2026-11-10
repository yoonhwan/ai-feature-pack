"""ft-scratch-repo.sh — «판정 끝남» 판별(--judged) + 같은 좌석 등록 사본 3개 초과 WARN (카드 r-disk-drop-worktree-scratch-census §구현 범위 2·3).
격리 임시 저장소 · 실 사본 접촉 0 · 시험에 GIT_* 환경을 걸지 않는다(BOOT 25).
"""

import os
import subprocess

import pytest
from ft_git_helpers import BIN, commit, git, init_repo
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

OLD = "2020-01-01T00:00:00"


@pytest.fixture
def env(tmp_path):
    repo = init_repo(tmp_path / "repo", "main")
    commit(repo, {".gitignore": ".worktrees/\n.fable-team/\n"}, "ignore")
    (repo / ".fable-team/state").mkdir(parents=True)
    (tmp_path / "scratch").mkdir()
    return {"repo": repo, "tmp": tmp_path}


def _run(env, *args, owner="byz-x-owner#1"):
    e = {**os.environ, "FT_RES_ROOT": str(env["repo"]), "FT_SCRATCH_DIR": str(env["tmp"] / "scratch"), "FT_SCRATCH_OWNER": owner, "FT_SCRATCH_MAIN": "main"}
    return subprocess.run(["bash", str(BIN / "ft-scratch-repo.sh"), *args], capture_output=True, text=True, cwd=env["repo"], env=e)


def _copy_of_unlanded(env, name="work"):
    """main 에 없는 커밋 위의 사본 — 착지 판정은 거짓."""
    git(env["repo"], "checkout", "-q", "-b", name)
    sha = commit(env["repo"], {f"{name}.txt": name}, f"{name} commit")
    git(env["repo"], "checkout", "-q", "main")
    r = _run(env, sha)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip(), sha


def test_judged_true_when_copy_head_is_landed_on_main(env):
    r = _run(env, "main")
    assert _run(env, "--judged", r.stdout.strip()).returncode == 0


def test_judged_true_when_sha_named_in_old_design_doc(env):
    path, sha = _copy_of_unlanded(env)
    commit(env["repo"], {"design/da/VERDICT-x.md": f"판정: 사본 {sha[:8]} APPROVE\n"}, "verdict", date=OLD)
    assert _run(env, "--judged", path).returncode == 0


def test_judged_false_when_verdict_commit_is_recent(env):
    path, sha = _copy_of_unlanded(env)
    commit(env["repo"], {"design/da/VERDICT-x.md": f"판정: 사본 {sha[:8]} APPROVE\n"}, "verdict")
    assert _run(env, "--judged", path).returncode == 1


def test_judged_false_when_unlanded_and_unnamed(env):
    path, _ = _copy_of_unlanded(env)
    assert _run(env, "--judged", path).returncode == 1


def test_judged_rejects_unregistered_or_missing_path(env):
    assert _run(env, "--judged", str(env["tmp"] / "nope")).returncode == 2


def test_warn_when_same_owner_has_more_than_three_copies_and_names_oldest_judged(env):
    first, sha = _copy_of_unlanded(env, "w1")
    commit(env["repo"], {"design/da/VERDICT-x.md": f"사본 {sha[:8]} 판정 끝\n"}, "verdict", date=OLD)
    for i in range(2, 4):
        _copy_of_unlanded(env, f"w{i}")
    r = _run(env, "main")  # 4번째
    assert r.returncode == 0 and r.stdout.strip().startswith(str(env["tmp"] / "scratch"))
    assert "WARN" in r.stderr and first in r.stderr and "--done" in r.stderr


def test_no_warn_at_three_copies(env):
    for i in range(1, 3):
        _copy_of_unlanded(env, f"w{i}")
    assert "WARN" not in _run(env, "main").stderr


def test_warn_counts_only_the_same_owner(env):
    for i in range(1, 4):
        _copy_of_unlanded(env, f"w{i}")
    assert "WARN" not in _run(env, "main", owner="byz-y-other#1").stderr
