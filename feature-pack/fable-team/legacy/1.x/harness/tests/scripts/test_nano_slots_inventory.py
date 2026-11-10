"""ft-nano-slots.sh --inventory (M7 범위 5 · REVIEW arch141 §2-6) — 미랜딩 nano/* 브랜치 전수 행.

분모 = `git for-each-ref --no-merged=<feat> refs/heads/nano/` − 랜딩 원장(FT_NANO_LANDING_LEDGER · jsonl {branch, tip, squash_sha}).
squash 는 조상 관계를 안 만들어 원장 없이는 랜딩된 브랜치가 영원히 «미랜딩». 브랜치별 `git cherry` 금지(590개에 120 s+).
출력: 머리 1줄 `INVENTORY unlanded=<N> …` + 행 `<브랜치>\t<마지막 커밋 날짜>\t<미랜딩 커밋 수>\t<카드 상태 대기|진행|완성|없음>`.
"""

import json
import os
import stat
import subprocess

import pytest
from ft_git_helpers import BIN, REAL_GIT, commit, git, init_repo


def _branch(repo, name, files, msg="work"):
    git(repo, "checkout", "-q", "-b", name, "feat")
    commit(repo, files, msg)
    git(repo, "checkout", "-q", "feat")


@pytest.fixture
def repo(tmp_path):
    r = init_repo(tmp_path / "repo")
    _branch(r, "nano/unlanded-a", {"a.py": "1"})
    _branch(r, "nano/unlanded-b", {"b.py": "1"})
    git(r, "checkout", "-q", "-b", "nano/ancestor", "feat")
    git(r, "checkout", "-q", "feat")
    _branch(r, "nano/squashed", {"s.py": "1"})
    git(r, "merge", "-q", "--squash", "nano/squashed")
    git(r, "commit", "-q", "-m", "squash")
    cards = r / "design/v65/indices"
    (cards / "진행").mkdir(parents=True)
    (cards / "진행" / "unlanded-a.md").write_text("x")
    return r


def _ledger(tmp_path, repo, branches):
    p = tmp_path / "nano-landing.jsonl"
    rows = [{"branch": b, "tip": git(repo, "rev-parse", b).strip(), "squash_sha": git(repo, "rev-parse", "feat").strip()} for b in branches]
    p.write_text("".join(json.dumps(r) + "\n" for r in rows))
    return p


def _inv(repo, ledger, path_prefix=None):
    env = {**os.environ, "FT_NANO_FEAT": "feat", "FT_NANO_LANDING_LEDGER": str(ledger), "FT_INDEX_DIR": str(repo / "design/v65/indices")}
    if path_prefix:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env['PATH']}"
    return subprocess.run(["bash", str(BIN / "ft-nano-slots.sh"), "--inventory"], capture_output=True, text=True, cwd=repo, env=env)


def test_lists_only_unlanded_excluding_ancestor_and_ledgered(tmp_path, repo):
    r = _inv(repo, _ledger(tmp_path, repo, ["nano/squashed"]))
    assert r.returncode == 0, r.stderr
    assert r.stdout.startswith("INVENTORY unlanded=2")
    assert "nano/unlanded-a" in r.stdout and "nano/unlanded-b" in r.stdout
    assert "nano/ancestor" not in r.stdout and "nano/squashed" not in r.stdout


def test_without_ledger_entry_squashed_branch_still_counts(tmp_path, repo):
    r = _inv(repo, _ledger(tmp_path, repo, []))
    assert r.stdout.startswith("INVENTORY unlanded=3") and "nano/squashed" in r.stdout


def test_row_columns_branch_date_ahead_card(tmp_path, repo):
    r = _inv(repo, _ledger(tmp_path, repo, ["nano/squashed"]))
    row = next(ln for ln in r.stdout.splitlines() if ln.startswith("nano/unlanded-a")).split("\t")
    assert len(row) == 4 and row[2] == "1" and row[3] == "진행"
    other = next(ln for ln in r.stdout.splitlines() if ln.startswith("nano/unlanded-b")).split("\t")
    assert other[3] == "없음"


def test_header_states_denominator_definitions(tmp_path, repo):
    r = _inv(repo, _ledger(tmp_path, repo, []))
    assert "조상" in r.stdout and "원장" in r.stdout


def test_missing_ledger_file_is_treated_as_empty_not_error(tmp_path, repo):
    r = _inv(repo, tmp_path / "absent.jsonl")
    assert r.returncode == 0 and r.stdout.startswith("INVENTORY unlanded=3")


def test_never_runs_per_branch_git_cherry(tmp_path, repo):
    shim = tmp_path / "shim"
    shim.mkdir()
    g = shim / "git"
    g.write_text(f'#!/bin/bash\nfor a in "$@"; do [ "$a" = cherry ] && {{ echo "cherry called" >&2; exit 97; }}; done\nexec {REAL_GIT} "$@"\n')
    g.chmod(g.stat().st_mode | stat.S_IEXEC)
    r = _inv(repo, _ledger(tmp_path, repo, []), path_prefix=shim)
    assert r.returncode == 0 and r.stdout.startswith("INVENTORY") and "cherry called" not in r.stderr
