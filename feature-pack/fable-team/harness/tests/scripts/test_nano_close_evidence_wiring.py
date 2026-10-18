"""ft-nano-close.sh ⑥ 증거 줄 배선 (M7 범위 1) — role=nano 좌석만 카드 증거 줄이 현재 나노 HEAD 와 맞아야 한다.
tmux 는 «서버 없음» 스텁(ABSENT 경로) · 격리 임시 저장소만 쓴다. ⑤ cherry 등 다른 REJECT 는 무시하고 ⑥ 줄의 유무만 본다.
"""

import json
import os
import stat
import subprocess

import pytest
from ft_git_helpers import BIN, git, init_repo

SEAT = "ft-v65-temp-slug#0"


@pytest.fixture
def env(tmp_path):
    repo = init_repo(tmp_path / "repo", "feat/v6-realtime-live")
    wt = repo / ".worktrees/v65-slug"
    git(repo, "worktree", "add", "-q", "-b", "nano/slug", str(wt), "feat/v6-realtime-live")
    (repo / ".fable-team").mkdir()
    (repo / "design").mkdir()
    (repo / "design/card.md").write_text("## 상태\n")
    (repo / "ledger.md").write_text("")
    sh = tmp_path / "shim"
    sh.mkdir()
    tmux = sh / "tmux"
    tmux.write_text("#!/bin/bash\necho 'no server running on /tmp/x' >&2\nexit 1\n")
    tmux.chmod(tmux.stat().st_mode | stat.S_IEXEC)
    return {"repo": repo, "wt": wt, "sh": sh, "tmp": tmp_path}


def _close(env, role="nano", state_line=None, index="design/card.md"):
    repo = env["repo"]
    (repo / ".fable-team/seats.json").write_text(json.dumps({SEAT: {"role": role, "index": index}}))
    (repo / "design/card.md").write_text("## 상태\n" + (state_line or "") + "\n")
    (repo / "result.txt").write_text("r")
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_NANO_LEDGER": str(repo / "ledger.md"),
         "FT_NANO_LEDGER_WT": str(repo), "FT_WT_CLEAN_DIR": str(env["tmp"] / "wtc"), "FT_WT_AUTOCLEAN": "0", "FT_NANO_FEAT": "feat/v6-realtime-live"}
    return subprocess.run(["bash", str(BIN / "ft-nano-close.sh"), SEAT, "--result", str(repo / "result.txt"), "--recv", "1"],
                          capture_output=True, text=True, cwd=repo, env=e)


def _good_line(env):
    return f"- 세트: {git(env['wt'], 'rev-parse', 'HEAD').strip()} · 시험: pytest rc=0 · 이슈: 0"


def test_nano_without_evidence_line_gets_reject_6(env):
    r = _close(env)
    assert "⑥증거 줄" in r.stdout


def test_nano_with_valid_evidence_has_no_reject_6(env):
    r = _close(env, state_line=_good_line(env))
    assert "⑥" not in r.stdout and "OK 증거 줄" in r.stdout


def test_stale_head_in_evidence_gets_reject_6(env):
    line = _good_line(env)
    (env["wt"] / "x.txt").write_text("x")
    git(env["wt"], "add", "-A")
    git(env["wt"], "commit", "-q", "-m", "later")
    assert "⑥증거 줄" in _close(env, state_line=line).stdout


def test_non_nano_role_skips_evidence_check(env):
    r = _close(env, role="tester")
    assert "⑥" not in r.stdout and "증거 줄" not in r.stdout


def _set_created(env, created):
    (env["wt"] / ".worktree-info.json").write_text(json.dumps({"branch": "nano/slug", "created_at": created}))


def test_old_worktree_is_grandfathered_with_warn(env):
    _set_created(env, "2026-10-02 23:34:00")
    r = _close(env)
    assert "⑥" not in r.stdout.replace("WARN ⑥", "") and "WARN ⑥증거 줄 미충족(grandfather" in r.stdout


def test_new_worktree_without_evidence_is_rejected(env):
    _set_created(env, "2026-10-03 00:10:00")
    assert "- ⑥증거 줄" in _close(env).stdout


def test_unreadable_created_at_is_required_not_grandfathered(env):
    r = _close(env)
    assert "- ⑥증거 줄" in r.stdout and "grandfather" not in r.stdout


def test_doc_only_card_closes_without_reject_6(env):
    _set_created(env, "2026-10-03 00:10:00")
    git(env["wt"], "config", "user.email", "t@t")
    line = f"- 세트: {git(env['wt'], 'rev-parse', 'HEAD').strip()} · 시험: 없음(문서) — 감사 문서만 · 이슈: 0"
    r = _close(env, state_line=line)
    assert "- ⑥" not in r.stdout and "OK 증거 줄" in r.stdout


def test_nano_with_unfindable_card_is_rejected_not_silently_closed(env):
    r = _close(env, index="design/no-such-card.md")
    assert "- ⑥카드" in r.stdout and "no-such-card.md" in r.stdout


def test_unfindable_card_rejects_even_for_grandfathered_worktree(env):
    _set_created(env, "2026-10-02 23:34:00")
    assert "- ⑥카드" in _close(env, index="design/no-such-card.md").stdout


def test_nano_with_empty_index_field_is_rejected(env):
    assert "- ⑥카드" in _close(env, index="").stdout


def test_non_nano_role_with_unfindable_card_is_not_touched(env):
    assert "⑥" not in _close(env, role="tester", index="design/no-such-card.md").stdout
