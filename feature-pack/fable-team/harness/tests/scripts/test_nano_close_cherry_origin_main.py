"""ft-nano-close.sh ⑤ — 팀 base 기준 cherry 게이트가 REJECT 일 때만 origin/main 기준으로 한 번 더 본다 (planner 판정 1280).
격리 임시 저장소(bare origin) + tmux «서버 없음» 스텁 · role=tester 로 ⑥ 증거 줄을 비켜 ⑤ 만 본다.
게이트 호출은 ft-nano-cherry-gate.sh 를 로그 래퍼로 바꾼 bin 심링크 디렉터리로 센다(래퍼는 실 게이트를 그대로 exec).
"""

import json
import os
import stat
import subprocess

import pytest
from ft_git_helpers import BIN, commit, git, init_repo
from real_state_guard import guard_begin_module  # noqa: E402,F401  r684: 실 상태 지문 + 자식 HIL_DIR(실 /tmp/h<N> 쓰기 0)

SEAT = "ft-v65-temp-slug#0"
TEAM_BASE = "feat/feature-main"
REASON = "시험 사유 — 사람 우회"
CODE = "print('nano output')\n"


def _fixture(tmp_path, landed_on_main):
    repo = init_repo(tmp_path / "repo", "main")
    origin = tmp_path / "origin.git"
    subprocess.run(["git", "init", "-q", "--bare", str(origin)], check=True)
    git(repo, "remote", "add", "origin", str(origin))
    git(repo, "push", "-q", "origin", "main")
    git(repo, "branch", TEAM_BASE)  # 뒤처진 팀 base — 아래 main 커밋을 못 본다
    wt = repo / ".worktrees/v65-slug"
    git(repo, "worktree", "add", "-q", "-b", "nano/slug", str(wt), TEAM_BASE)
    commit(wt, {"code.py": CODE}, "nano-only code commit")
    # main 쪽: 나노 산출을 squash(다른 파일이 같이 묶여 patch-id 는 달라진다) 하거나, 무관한 커밋만 올린다
    commit(repo, {"code.py": CODE, "extra.txt": "e"} if landed_on_main else {"other.txt": "o"}, "main moves")
    git(repo, "push", "-q", "origin", "main")
    (repo / ".fable-team").mkdir()
    (repo / ".fable-team/seats.json").write_text(json.dumps({SEAT: {"role": "tester", "index": "x"}}))
    (repo / "ledger.md").write_text("")
    (repo / "result.txt").write_text("r")
    sh = tmp_path / "shim"
    sh.mkdir()
    tmux = sh / "tmux"
    tmux.write_text("#!/bin/bash\necho 'no server running on /tmp/x' >&2\nexit 1\n")
    tmux.chmod(tmux.stat().st_mode | stat.S_IEXEC)
    bindir = tmp_path / "bin"
    bindir.mkdir()
    for f in BIN.iterdir():
        if f.name != "ft-nano-cherry-gate.sh":
            (bindir / f.name).symlink_to(f)
    gate_log = tmp_path / "gate-calls.log"
    wrap = bindir / "ft-nano-cherry-gate.sh"
    wrap.write_text(f'#!/bin/bash\necho "$*" >> "{gate_log}"\nexec bash "{BIN / "ft-nano-cherry-gate.sh"}" "$@"\n')
    wrap.chmod(wrap.stat().st_mode | stat.S_IEXEC)
    return {"repo": repo, "sh": sh, "tmp": tmp_path, "bin": bindir, "gate_log": gate_log, "override_ledger": tmp_path / "ov.log"}


def _close(env, feat=TEAM_BASE, *extra):
    repo = env["repo"]
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_NANO_LEDGER": str(repo / "ledger.md"),
         "FT_NANO_LEDGER_WT": str(repo), "FT_WT_CLEAN_DIR": str(env["tmp"] / "wtc"), "FT_WT_AUTOCLEAN": "0",
         "FT_NANO_FEAT": feat, "FT_CHERRY_OVERRIDE_LEDGER": str(env["override_ledger"])}
    return subprocess.run(["bash", str(env["bin"] / "ft-nano-close.sh"), SEAT, "--result", str(repo / "result.txt"), "--recv", "1", *extra],
                          capture_output=True, text=True, cwd=repo, env=e)


def _gate_calls(env):
    return env["gate_log"].read_text(encoding="utf-8").splitlines() if env["gate_log"].exists() else []


def test_team_base_reject_origin_main_pass_passes_5_with_info(tmp_path):
    env = _fixture(tmp_path, landed_on_main=True)
    r = _close(env)
    assert "- ⑤" not in r.stdout and "content_on_origin_main" in r.stdout
    calls = _gate_calls(env)
    assert len(calls) == 2 and calls[0].startswith(f"{TEAM_BASE} nano/slug") and calls[1].startswith("origin/main nano/slug")


def test_both_reject_keeps_reject_and_shows_origin_main_first_line(tmp_path):
    env = _fixture(tmp_path, landed_on_main=False)
    r = _close(env)
    assert "- ⑤" in r.stdout and "content_on_origin_main" not in r.stdout
    assert "origin/main 기준" in r.stdout
    assert len(_gate_calls(env)) == 2


@pytest.mark.parametrize("feat", ["origin/main", "main"])
def test_team_base_already_main_runs_gate_once(tmp_path, feat):
    env = _fixture(tmp_path, landed_on_main=False)
    r = _close(env, feat)
    assert "- ⑤" in r.stdout and len(_gate_calls(env)) == 1


def test_origin_fetch_failure_keeps_reject_and_never_uses_stale_ref(tmp_path):
    env = _fixture(tmp_path, landed_on_main=True)  # 로컬 refs/remotes/origin/main 은 이미 나노 산출을 가진 옛값
    git(env["repo"], "remote", "set-url", "origin", str(tmp_path / "no-such-origin.git"))
    r = _close(env)
    assert "- ⑤" in r.stdout and "content_on_origin_main" not in r.stdout
    assert "origin/main fetch 실패" in r.stdout
    assert len(_gate_calls(env)) == 1


def test_cherry_override_goes_to_first_run_only(tmp_path):
    env = _fixture(tmp_path, landed_on_main=False)
    r = _close(env, TEAM_BASE, "--cherry-override", REASON)
    assert "- ⑤" not in r.stdout and "OVERRIDE cherry 게이트" in r.stdout
    calls = _gate_calls(env)
    assert len(calls) == 1 and "--override" in calls[0]
    assert len(env["override_ledger"].read_text(encoding="utf-8").splitlines()) == 1
