"""설계 §6 push 계약(카드 범위 2b) — 임시 리포 + 가짜 origin 으로 ops/magazine 만 push · 워크트리 없음·다른 브랜치·미커밋·push 거부 → raise. 실 push 0.

실행: python3 -m pytest tests/scripts/test_magazine_git.py -q
"""
import subprocess

import pytest
from _magazine_fakes import git, make_repo

import magazine_git as mg

DATE = "2026-10-08"


@pytest.fixture
def repo(tmp_path):
    return make_repo(tmp_path)


def test_push_only_ops_magazine_main_untouched(repo):
    origin, _, wt = repo
    main_before = git(origin, "rev-parse", "main")
    sha = mg.publish_md(wt, "# 본문\n", "MAGAZINE-20261008.md", DATE)
    assert git(origin, "rev-parse", "ops/magazine") == sha and git(origin, "rev-parse", "main") == main_before
    assert git(origin, "for-each-ref", "--format=%(refname)") == "refs/heads/main\nrefs/heads/ops/magazine"
    assert git(origin, "show", f"{sha}:design/harness/magazine/MAGAZINE-20261008.md") == "# 본문"
    assert git(origin, "log", "-1", "--format=%s", sha) == "[docs] 아침 매거진 2026-10-08 (자동)"
    assert mg.publish_md(wt, "# 본문\n", "MAGAZINE-20261008.md", DATE) == sha  # 같은 내용 재실행 = 새 커밋 0
    assert mg.blob_url("o/r", sha, "X.md") == f"https://github.com/o/r/blob/{sha}/design/harness/magazine/X.md"


def test_push_contract_refusals(repo, tmp_path):
    origin, main, wt = repo
    with pytest.raises(mg.GitError, match="워크트리 없음"):
        mg.publish_md(tmp_path / "nope", "x", "M.md", DATE)
    (wt / "stray.txt").write_text("dirty")
    with pytest.raises(mg.GitError, match="미커밋"):
        mg.publish_md(wt, "x", "M.md", DATE)
    (wt / "stray.txt").unlink()
    git(wt, "checkout", "-q", "-b", "other")
    with pytest.raises(mg.GitError, match="ops/magazine 가 아님"):
        mg.publish_md(wt, "x", "M.md", DATE)
    assert git(origin, "for-each-ref", "--format=%(refname)") == "refs/heads/main"  # 거부 시 아무것도 안 나갔다
    git(wt, "checkout", "-q", "ops/magazine")
    hook = origin / "hooks" / "pre-receive"
    hook.write_text("#!/bin/sh\necho denied >&2\nexit 1\n")
    hook.chmod(0o755)
    with pytest.raises(mg.GitError, match="push 실패"):
        mg.publish_md(wt, "x", "M.md", DATE)


def test_no_force_diverged_remote_is_rejected(repo, tmp_path):
    origin, _, wt = repo
    other = tmp_path / "other"
    subprocess.run(["git", "clone", "-q", str(origin), str(other)], check=True, capture_output=True)
    for k, v in (("user.email", "t@t"), ("user.name", "t")):
        git(other, "config", k, v)
    (other / "z.txt").write_text("z")
    git(other, "add", "-A"); git(other, "commit", "-qm", "other"); git(other, "push", "-q", "origin", "HEAD:refs/heads/ops/magazine")  # noqa: E702
    with pytest.raises(mg.GitError, match="push 실패"):
        mg.publish_md(wt, "x", "M.md", DATE)  # fast-forward 아님 → force 없이는 거부
