"""ft-nano-spawn.sh 옛 nano 브랜치 슬러그 충돌 시험 — 격리 임시 git 저장소 + tmuxc/tmux/sleep shim 만 쓴다.

인덱스 M7-nano-spawn-existing-branch-slug-collision §구현범위 2:
브랜치 없음=기존 동작 · 반입된 옛 브랜치 → -r2 · -r2 도 있으면 -r3 · 미반입 옛 브랜치 → REJECT·삭제 0.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest
from ft_git_helpers import copy_py_helpers

BIN =Path(__file__).resolve().parents[3] / "harness" / "bin"
REAL_GIT: str = shutil.which("git") or "git"
CARD = "design/v65/indices/대기/M7-demo-card.md"
SLUG = "m7-demo-card"
GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@t",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@t",
}

SHIMS = {
    # tmuxc open <WTDIR> --name <NAME> … → 세션 «떴음» 기록
    "tmuxc": '#!/usr/bin/env bash\n[ "$1" = open ] || exit 0\ncase " $* " in *" --dry-run "*) exit 0;; esac\nprintf "%s\\n" "$4" >> "$SHIM_STATE/sessions"\nprintf "%s\\n" "$2" >> "$SHIM_STATE/opened"\n',
    "tmux": (
        "#!/usr/bin/env bash\n"
        'touch "$SHIM_STATE/sessions"\n'
        'case "$1" in\n'
        '  has-session) n="${3#=}"; grep -qxF -- "$n" "$SHIM_STATE/sessions";;\n'
        '  list-panes) while IFS= read -r s; do printf \'%s|%%1\\n\' "$s"; done < "$SHIM_STATE/sessions";;\n'
        "  show-option) echo 1;;\n"
        "  *) exit 0;;\n"
        "esac\n"
    ),
    "sleep": "#!/usr/bin/env bash\nexit 0\n",
}
STUBS = ("ft-index-lint.sh", "ft-proposal-gate.sh", "ft-index-move.sh", "ft-send-verified.sh", "ft-resource-gate.sh", "ft-agent-ready.sh")


def _git(repo: Path, *args: str) -> str:
    env = {**os.environ, **GIT_ENV}
    return subprocess.run(
        [REAL_GIT, "-C", str(repo), *args], check=True, capture_output=True, text=True, env=env
    ).stdout.strip()


def _commit(repo: Path, rel: str, body: str, msg: str) -> str:
    p = repo / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", msg)
    return _git(repo, "rev-parse", "HEAD")


def _exec(path: Path, body: str) -> None:
    path.write_text(body)
    path.chmod(0o755)


@pytest.fixture
def env(tmp_path: Path) -> dict[str, Path]:
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q", "-b", "feat")
    (repo / ".fable-team").mkdir()
    (repo / ".fable-team" / "seats.json").write_text("{}\n")
    _commit(repo, ".gitignore", ".worktrees/\n.fable-team/\n", "base")
    _commit(repo, "design/TEAMS.md", "| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | v65#1 | 현역 |\n", "teams")  # R383: v65 폴더는 design/TEAMS.md 로 푼다
    _commit(repo, "design/v65/SEATBELT-README.md", "# sb\n", "sb")  # R406: 발주 본문 README = 실재 1개
    _commit(repo, CARD, "# card\n", "card")
    bindir = tmp_path / "bin"
    bindir.mkdir()
    for name in ("ft-nano-spawn.sh", "ft-nano-cherry-gate.sh"):
        shutil.copy2(BIN / name, bindir / name)
    copy_py_helpers(bindir)  # 문지기 다음 단계 순수 판정 도우미 전부
    for name in STUBS:
        _exec(bindir / name, "#!/usr/bin/env bash\nexit 0\n")
    _exec(bindir / "ft-sheet-events.sh", '#!/usr/bin/env bash\ncase "$1" in key) echo k;; esac\nexit 0\n')  # 사건 원장 가짜 — 실제 원장 쓰기 0
    shimdir = tmp_path / "shim"
    shimdir.mkdir()
    for name, body in SHIMS.items():
        _exec(shimdir / name, body)
    state = tmp_path / "state"
    state.mkdir()
    return {"repo": repo, "bin": bindir, "shim": shimdir, "state": state}


def _spawn(e: dict[str, Path]) -> subprocess.CompletedProcess[str]:
    run_env = {
        **os.environ,
        **GIT_ENV,
        "SHIM_STATE": str(e["state"]),
        "FT_TEAMS_REF": "HEAD",  # R406: 픽스처 명단은 커밋된 HEAD 에만 있다(origin/main ref 0) — 실 리포는 origin/main
        "PATH": f"{e['shim']}{os.pathsep}{os.environ['PATH']}",
    }
    return subprocess.run(
        ["bash", str(e["bin"] / "ft-nano-spawn.sh"), CARD],
        cwd=e["repo"],
        capture_output=True,
        text=True,
        env=run_env,
    )


def _branches(repo: Path) -> set[str]:
    return set(_git(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/nano/").split())


def _landed_branch(repo: Path, branch: str, rel: str) -> str:
    """branch 에 코드 커밋 1개 → feat 로 cherry-pick (git cherry «-») 후 feat 로 복귀."""
    _git(repo, "checkout", "-q", "-b", branch, "feat")
    sha = _commit(repo, rel, f"{branch}\n", f"code {branch}")
    _git(repo, "checkout", "-q", "feat")
    _git(repo, "cherry-pick", "-x", sha)
    return _git(repo, "rev-parse", branch)


def test_no_branch_keeps_existing_behavior(env: dict[str, Path]) -> None:
    r = _spawn(env)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "old_branch=" not in r.stdout
    assert _branches(env["repo"]) == {f"nano/{SLUG}"}
    wt = env["repo"] / ".worktrees" / f"v65-{SLUG}"
    assert _git(wt, "rev-parse", "--abbrev-ref", "HEAD") == f"nano/{SLUG}"


def test_landed_old_branch_opens_r2(env: dict[str, Path]) -> None:
    repo = env["repo"]
    old_sha = _landed_branch(repo, f"nano/{SLUG}", "a.py")
    r = _spawn(env)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"old_branch=nano/{SLUG} landed=yes" in r.stdout
    wt = repo / ".worktrees" / f"v65-{SLUG}-r2"
    assert _git(wt, "rev-parse", "--abbrev-ref", "HEAD") == f"nano/{SLUG}-r2"
    assert _git(wt, "rev-parse", "HEAD") == _git(repo, "rev-parse", "feat")
    assert _git(repo, "rev-parse", f"nano/{SLUG}") == old_sha
    assert (env["state"] / "opened").read_text().strip() == str(wt)
    assert f"branch=nano/{SLUG}-r2" in r.stdout


def test_r2_also_present_opens_r3(env: dict[str, Path]) -> None:
    repo = env["repo"]
    old_sha = _landed_branch(repo, f"nano/{SLUG}", "a.py")
    r2_sha = _landed_branch(repo, f"nano/{SLUG}-r2", "b.py")
    r = _spawn(env)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"old_branch=nano/{SLUG} landed=yes" in r.stdout
    assert f"old_branch=nano/{SLUG}-r2 landed=yes" in r.stdout
    wt = repo / ".worktrees" / f"v65-{SLUG}-r3"
    assert _git(wt, "rev-parse", "--abbrev-ref", "HEAD") == f"nano/{SLUG}-r3"
    assert _git(repo, "rev-parse", f"nano/{SLUG}") == old_sha
    assert _git(repo, "rev-parse", f"nano/{SLUG}-r2") == r2_sha


def test_unlanded_old_branch_rejects_and_keeps_branch(env: dict[str, Path]) -> None:
    repo = env["repo"]
    _git(repo, "checkout", "-q", "-b", f"nano/{SLUG}", "feat")
    old_sha = _commit(repo, "a.py", "only on nano\n", "unlanded code")
    _git(repo, "checkout", "-q", "feat")
    r = _spawn(env)
    assert r.returncode == 1, r.stdout + r.stderr
    assert "REJECT" in r.stdout and "unlanded code" in r.stdout
    assert _branches(repo) == {f"nano/{SLUG}"}
    assert _git(repo, "rev-parse", f"nano/{SLUG}") == old_sha
    assert not (repo / ".worktrees").exists()
    assert not (env["state"] / "opened").exists()


def _r2_worktree(repo: Path) -> Path:
    """반입된 옛 base 브랜치 + 워크트리가 살아 있는 -r2 (DA⑥ 53519 H1 반례의 자리)."""
    _landed_branch(repo, f"nano/{SLUG}", "a.py")
    wt = repo / ".worktrees" / f"v65-{SLUG}-r2"
    _git(repo, "worktree", "add", "-q", str(wt), "-b", f"nano/{SLUG}-r2", "feat")
    return wt


def test_existing_unlanded_r2_worktree_rejects(env: dict[str, Path]) -> None:
    """DA⑥ 53519 H1: -r2 워크트리가 있고 미반입 커밋이 있으면 게이트 없이 재사용하지 않는다."""
    repo = env["repo"]
    wt = _r2_worktree(repo)
    r2_sha = _commit(wt, "unlanded.py", "not landed\n", "unlanded r2")
    r = _spawn(env)
    assert r.returncode == 1, r.stdout + r.stderr
    assert "REJECT" in r.stdout and "unlanded r2" in r.stdout
    assert _git(repo, "rev-parse", f"nano/{SLUG}-r2") == r2_sha
    assert wt.is_dir()
    assert _branches(repo) == {f"nano/{SLUG}", f"nano/{SLUG}-r2"}
    assert not (env["state"] / "opened").exists()


def test_existing_landed_r2_worktree_is_reused(env: dict[str, Path]) -> None:
    repo = env["repo"]
    wt = _r2_worktree(repo)
    r = _spawn(env)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"old_branch=nano/{SLUG}-r2 landed=yes" in r.stdout
    assert (env["state"] / "opened").read_text().strip() == str(wt)
    assert _branches(repo) == {f"nano/{SLUG}", f"nano/{SLUG}-r2"}
