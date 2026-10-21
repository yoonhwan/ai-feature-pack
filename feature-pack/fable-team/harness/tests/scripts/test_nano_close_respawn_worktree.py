"""ft-nano-close.sh 재착수(-rN) 워크트리 경로 해석 (M7) — 좌석 key 의 워크트리가 v65-<key>-r2 여도 닫힌다.
tmux 는 스텁 · 격리 임시 저장소만 쓴다. role=tester 로 ⑥ 증거 줄을 비켜 ③(세션/워크트리)·⑤(cherry 브랜치)만 본다.
"""

import json
import os
import re
import stat
import subprocess
import time

import pytest
from ft_git_helpers import BIN, git, init_repo
from real_state_guard import guard_begin_module  # noqa: E402,F401  r684: 실 상태 지문 + 자식 HIL_DIR(실 /tmp/h<N> 쓰기 0)

SEAT = "ft-v65-temp-k#0"
FEAT = "feat/v6-realtime-live"


@pytest.fixture
def env(tmp_path):
    repo = init_repo(tmp_path / "repo", FEAT)
    (repo / ".fable-team").mkdir()
    (repo / ".fable-team/seats.json").write_text(json.dumps({SEAT: {"role": "tester", "index": "x"}}))
    (repo / "ledger.md").write_text("")
    (repo / "result.txt").write_text("r")
    (repo / "comm/bodies").mkdir(parents=True)  # ② master 회수 seq 1 실재
    (repo / "comm/bodies/1.txt").write_text("recv")
    future = time.time() + 3600  # ③ 파일 mtime 폴백(find -newer seats.json)이 아무것도 못 잡게 — 유휴 충족
    os.utime(repo / ".fable-team/seats.json", (future, future))
    sh = tmp_path / "shim"
    sh.mkdir()
    return {"repo": repo, "sh": sh, "tmp": tmp_path}


def _tmux(env, body):
    t = env["sh"] / "tmux"
    t.write_text("#!/bin/bash\n" + body)
    t.chmod(t.stat().st_mode | stat.S_IEXEC)


def _no_server(env):
    _tmux(env, "echo 'no server running on /tmp/x' >&2\nexit 1\n")


def _live_pane(env, cwd):
    _tmux(env, f'case "$1" in list-panes) echo "{SEAT}|%9";; display-message) echo "{cwd}";; *) exit 0;; esac\n')


def _wt(env, name, branch):
    wt = env["repo"] / ".worktrees" / name
    git(env["repo"], "worktree", "add", "-q", "-b", branch, str(wt), FEAT)
    return wt


def _close(env):
    repo = env["repo"]
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_NANO_LEDGER": str(repo / "ledger.md"),
         "FT_NANO_LEDGER_WT": str(repo), "FT_WT_CLEAN_DIR": str(env["tmp"] / "wtc"), "FT_WT_AUTOCLEAN": "0",
         "FT_NANO_FEAT": FEAT, "FT_INBOX_ROOT": str(repo / "comm")}
    return subprocess.run(["bash", str(BIN / "ft-nano-close.sh"), SEAT, "--result", str(repo / "result.txt"), "--recv", "1"],
                          capture_output=True, text=True, cwd=repo, env=e)


def _planned_wt(env):
    m = re.search(r"WT=(\S+);", (env["tmp"] / "wtc" / f"{SEAT}.sh").read_text())
    assert m, "계획 파일에 WT= 없음"
    return m.group(1).rstrip("\\")


def test_only_r2_worktree_exists_is_resolved_and_closed(env):
    _no_server(env)
    r2 = _wt(env, "v65-k-r2", "nano/k-r2")
    r = _close(env)
    assert r.returncode == 0 and "CLOSED-ABSENT" in r.stdout, r.stdout
    assert _planned_wt(env) == str(r2.resolve()) or _planned_wt(env) == str(r2)


def test_plain_worktree_still_resolved_regression(env):
    _no_server(env)
    k = _wt(env, "v65-k", "nano/k")
    r = _close(env)
    assert r.returncode == 0 and "CLOSED-ABSENT" in r.stdout, r.stdout
    assert _planned_wt(env) in (str(k), str(k.resolve()))


def test_both_worktrees_without_live_pane_is_rejected_fail_closed(env):
    _no_server(env)
    _wt(env, "v65-k", "nano/k")
    _wt(env, "v65-k-r2", "nano/k-r2")
    r = _close(env)
    assert r.returncode == 1 and "REJECT" in r.stdout and "CLOSED" not in r.stdout, r.stdout
    assert SEAT in (env["repo"] / ".fable-team/seats.json").read_text()  # 명부 불변


def test_live_pane_cwd_picks_its_branch_among_both(env):
    r2 = _wt(env, "v65-k-r2", "nano/k-r2")
    _wt(env, "v65-k", "nano/k")
    _live_pane(env, r2)
    r = _close(env)
    assert r.returncode == 0 and "CLOSED " in r.stdout, r.stdout
    assert _planned_wt(env) in (str(r2), str(r2.resolve()))


def test_candidate_without_seat_branch_is_not_chosen(env):
    _no_server(env)
    wt = _wt(env, "v65-k-r2", "other/x")  # 좌석 브랜치(nano/k·nano/k-rN)가 아닌 것을 체크아웃
    r = _close(env)
    assert r.returncode == 1 and "REJECT" in r.stdout and "CLOSED" not in r.stdout, r.stdout
    assert wt.exists()


def test_detached_head_candidate_is_not_chosen(env):
    _no_server(env)
    wt = env["repo"] / ".worktrees/v65-k-r2"
    git(env["repo"], "worktree", "add", "-q", "--detach", str(wt), FEAT)
    r = _close(env)
    assert r.returncode == 1 and "CLOSED" not in r.stdout, r.stdout


def test_h1_nonseat_live_cwd_with_two_candidates_is_rejected_before_close(env):
    """DA607 H1 — resolver 오류(후보 2+)는 cwd 가 비좌석(feat)이어도·tester 역할이어도 CLOSED·명부 삭제 전에 REJECT."""
    _wt(env, "v65-k", "nano/k")
    _wt(env, "v65-k-r2", "nano/k-r2")
    _live_pane(env, env["repo"])  # ROOT 의 feat 브랜치 — 좌석 브랜치 아님
    r = _close(env)
    assert r.returncode != 0 and "REJECT" in r.stdout and "CLOSED" not in r.stdout, r.stdout
    assert SEAT in (env["repo"] / ".fable-team/seats.json").read_text()  # 명부 불변
    assert not (env["tmp"] / "wtc" / f"{SEAT}.sh").exists()  # 정리 계획 생성 전


def test_h2_external_repo_worktree_cwd_is_not_adopted_into_cleanup_plan(env):
    """DA607 H2 — 외부 저장소의 같은 이름 브랜치 워크트리가 pane cwd 여도 정리 계획에 외부 경로가 들어가지 않는다."""
    own = _wt(env, "v65-k-r2", "nano/k-r2")
    ext = init_repo(env["tmp"] / "ext", FEAT)
    ext_wt = ext / ".worktrees/v65-k-r2"
    git(ext, "worktree", "add", "-q", "-b", "nano/k-r2", str(ext_wt), FEAT)
    _live_pane(env, ext_wt)
    r = _close(env)
    plan = (env["tmp"] / "wtc" / f"{SEAT}.sh").read_text()
    assert str(ext) not in plan and str(ext.resolve()) not in plan, plan
    assert r.returncode == 0 and _planned_wt(env) in (str(own), str(own.resolve())), r.stdout
