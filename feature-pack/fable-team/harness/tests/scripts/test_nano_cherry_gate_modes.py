"""ft-nano-cherry-gate.sh --mode land|close (M7 · REVIEW arch141 §2-3 · single_set_testing §2 규칙 2).

land  = 랜딩 «요청» 시점 — nano 가 feat HEAD 를 포함(조상)하지 않으면 REJECT.
close = 기존 동작(기본값) — squash 뒤엔 feat 가 앞서 가 «포함»이 항상 거짓이므로 이 검사를 걸지 않는다.
"""

import pytest
from ft_git_helpers import commit, git, init_repo, run_script


@pytest.fixture
def repo(tmp_path):
    r = init_repo(tmp_path / "repo")
    git(r, "branch", "nano", "feat")
    return r


def _gate(repo, *extra):
    return run_script("ft-nano-cherry-gate.sh", "feat", "nano", "--repo", str(repo), *extra)


def _nano_work_then_feat_moves(repo):
    git(repo, "checkout", "-q", "nano")
    commit(repo, {"a.py": "nano"}, "nano work")
    git(repo, "checkout", "-q", "feat")
    commit(repo, {"b.py": "feat"}, "feat moved")


def test_land_rejects_when_feat_head_not_contained(repo):
    _nano_work_then_feat_moves(repo)
    r = _gate(repo, "--mode", "land")
    assert r.returncode == 1 and r.stdout.startswith("REJECT") and "feat HEAD" in r.stdout


def test_land_reject_names_feat_head_and_merge_base(repo):
    _nano_work_then_feat_moves(repo)
    r = _gate(repo, "--mode", "land")
    assert git(repo, "rev-parse", "--short", "feat").strip() in r.stdout
    assert git(repo, "merge-base", "feat", "nano").strip()[:7] in r.stdout


def test_land_passes_root_check_after_feat_merged_into_nano(repo):
    _nano_work_then_feat_moves(repo)
    git(repo, "checkout", "-q", "nano")
    git(repo, "merge", "-q", "--no-edit", "feat")
    r = _gate(repo, "--mode", "land")
    assert r.returncode != 2 and "feat HEAD 를 포함" not in r.stdout


def test_land_with_nano_equal_feat_is_ok(repo):
    r = _gate(repo, "--mode", "land")
    assert r.returncode == 0 and r.stdout.startswith("OK")


def test_close_mode_does_not_apply_root_check(repo):
    _nano_work_then_feat_moves(repo)
    r = _gate(repo, "--mode", "close")
    assert r.returncode != 2 and "feat HEAD 를 포함" not in r.stdout


def test_default_mode_is_close(repo):
    _nano_work_then_feat_moves(repo)
    assert _gate(repo).stdout == _gate(repo, "--mode", "close").stdout


def test_unknown_mode_is_usage_error(repo):
    r = _gate(repo, "--mode", "bogus")
    assert r.returncode == 2


def _squash_nano_into_feat(repo):
    git(repo, "checkout", "-q", "nano")
    commit(repo, {"a.py": "one"}, "nano 1")
    commit(repo, {"c.py": "two"}, "nano 2")
    git(repo, "checkout", "-q", "feat")
    commit(repo, {"other.txt": "feat moved"}, "feat moved")
    git(repo, "merge", "--squash", "nano")
    git(repo, "commit", "-q", "-m", "squash nano")


def test_squash_landing_then_close_passes(repo):
    """squash 는 커밋별 patch-id 를 깨 `git cherry` 가 «+» 를 낸다 — close 통과 = merge-tree 경로 ①(design/ 밖 delta 0)뿐."""
    _squash_nano_into_feat(repo)
    r = _gate(repo, "--mode", "close")
    assert r.returncode == 0, r.stdout
    assert "content_landed_via_merge_tree" in r.stdout


def test_squash_landing_then_land_mode_rejects(repo):
    _squash_nano_into_feat(repo)
    assert _gate(repo, "--mode", "land").returncode == 1
