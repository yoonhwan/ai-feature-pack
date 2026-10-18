"""ft-nano-close.sh --cherry-override 전달 (M7) — ⑤ cherry 게이트의 코드 «+» REJECT 만 사람 사유로 우회한다.
tmux 는 «서버 없음» 스텁 · 격리 임시 저장소만 쓴다. role=tester 로 ⑥ 증거 줄을 비켜 ⑤ 만 본다.
"""

import json
import os
import stat
import subprocess

import pytest
from ft_git_helpers import BIN, commit, git, init_repo

SEAT = "ft-v65-temp-slug#0"
REASON = "338f8a1a8c·25e9aa028a = feat r2 로 대체(arch#141)"


@pytest.fixture
def env(tmp_path):
    repo = init_repo(tmp_path / "repo", "feat/v6-realtime-live")
    wt = repo / ".worktrees/v65-slug"
    git(repo, "worktree", "add", "-q", "-b", "nano/slug", str(wt), "feat/v6-realtime-live")
    commit(wt, {"code.py": "print('superseded')\n"}, "nano-only code commit")  # feat 에 없는 코드 «+»
    (repo / ".fable-team").mkdir()
    (repo / ".fable-team/seats.json").write_text(json.dumps({SEAT: {"role": "tester", "index": "x"}}))
    (repo / "ledger.md").write_text("")
    (repo / "result.txt").write_text("r")
    sh = tmp_path / "shim"
    sh.mkdir()
    tmux = sh / "tmux"
    tmux.write_text("#!/bin/bash\necho 'no server running on /tmp/x' >&2\nexit 1\n")
    tmux.chmod(tmux.stat().st_mode | stat.S_IEXEC)
    return {"repo": repo, "sh": sh, "tmp": tmp_path, "gate_ledger": tmp_path / "ov.log"}


def _close(env, *extra, result="result.txt"):
    repo = env["repo"]
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_NANO_LEDGER": str(repo / "ledger.md"),
         "FT_NANO_LEDGER_WT": str(repo), "FT_WT_CLEAN_DIR": str(env["tmp"] / "wtc"), "FT_WT_AUTOCLEAN": "0",
         "FT_NANO_FEAT": "feat/v6-realtime-live", "FT_CHERRY_OVERRIDE_LEDGER": str(env["gate_ledger"])}
    return subprocess.run(["bash", str(BIN / "ft-nano-close.sh"), SEAT, "--result", str(repo / result), "--recv", "1", *extra],
                          capture_output=True, text=True, cwd=repo, env=e)


def test_unlanded_code_without_override_is_rejected_5(env):
    r = _close(env)
    assert "- ⑤" in r.stdout and "OVERRIDE" not in r.stdout and not env["gate_ledger"].exists()


def test_override_passes_5_and_logs_one_row_with_seat_name(env):
    r = _close(env, "--cherry-override", REASON)
    assert "- ⑤" not in r.stdout and "OVERRIDE cherry 게이트" in r.stdout
    assert r.stdout.count("ERROR cherry 게이트 OVERRIDE") == 1
    rows = env["gate_ledger"].read_text(encoding="utf-8").splitlines()
    assert len(rows) == 1 and f"seat={SEAT}" in rows[0] and REASON in rows[0] and "nano=nano/slug" in rows[0]


@pytest.mark.parametrize("args", [["--cherry-override", ""], ["--cherry-override", "  "], ["--cherry-override"]])
def test_empty_or_missing_reason_is_usage_2(env, args):
    r = _close(env, *args)
    assert r.returncode == 2 and not env["gate_ledger"].exists()


def test_override_does_not_mask_other_gates(env):
    r = _close(env, "--cherry-override", REASON, result="no-such-result.txt")
    assert r.returncode == 1 and "REJECT" in r.stdout and "- ⑤" not in r.stdout
    assert "OVERRIDE cherry 게이트" in r.stdout  # ⑤ 는 통과했으나 ① 은 그대로 REJECT
