"""세트 축 (M7 범위 4 · 603 카드 «설계 확정 ①~③·⑤» 정의 그대로 — REVIEW arch141 §2-4).

인터페이스(이 시험이 고정): bash ft-press-set-check.sh --runner <러너 파일> --worker-cwd <dir> --gateway-cwd <dir>
  ①러너 값 = 러너 파일이 속한 워크트리 `git rev-parse HEAD`(40-hex) · worker·gateway pid 의 cwd HEAD 와 같아야 한다.
  ②dirty 범위 = worker/ gateway/ shared/ clients/web/src/ tests/e2e/ scripts/server/ (tracked 변경) — design/·docs/ 는 세트 밖.
  ③b 기동 stamp(A4 · DA⑥ 관측): 서비스 «현재 cwd HEAD» 만 비교하면 기동 뒤 워크트리가 새 커밋으로 바뀌어도 옛 코드로 뜬 서비스가 통과한다 →
     --worker-start <epoch> --gateway-start <epoch>(서비스 pid 프로세스 시작시각 · 호출자 press-gate 가 ps lstart 로 계산)가 «그 워크트리 HEAD 가 마지막으로 움직인 시각»(HEAD reflog 최신 항목 %ct)
     이상이어야 한다 — 기동 뒤 HEAD 가 움직였으면 REJECT · stamp 인자가 없으면 REJECT.
  ⑤우회 = env PRESS_SET_MISMATCH_REASON(비어 있지 않음) → exit 0 + stderr ERROR + stdout «diagnostic» 표시. pid→cwd 해석(lsof)은 press-gate 쪽.
"""

import os
import stat
import subprocess
import time

import pytest
from ft_git_helpers import REAL_GIT, commit, git, init_repo, run_script

SET_FILES = {"worker/w.py": "w", "gateway/g.py": "g", "shared/s.py": "s", "clients/web/src/a.ts": "a", "tests/e2e/r.py": "r", "scripts/server/x.sh": "x", "design/d.md": "d"}


@pytest.fixture
def sets(tmp_path):
    main = init_repo(tmp_path / "main")
    commit(main, SET_FILES, "set files")
    wts = {}
    for name in ("runner", "svc"):
        wt = tmp_path / name
        git(main, "worktree", "add", "-q", "-b", f"b-{name}", str(wt), "feat")
        wts[name] = wt
    return wts


def _check(sets, *, runner="runner", worker="svc", gateway="svc", env=None, wstart="later", gstart="later"):
    now = int(time.time())
    stamp = {"later": now + 60, "early": now - 3600}
    args = ["--runner", str(sets[runner] / "tests/e2e/r.py"), "--worker-cwd", str(sets[worker]), "--gateway-cwd", str(sets[gateway])]
    if wstart:
        args += ["--worker-start", str(stamp[wstart])]
    if gstart:
        args += ["--gateway-start", str(stamp[gstart])]
    return run_script("ft-press-set-check.sh", *args, extra_env=env)


def test_same_head_clean_passes(sets):
    r = _check(sets)
    assert r.returncode == 0, r.stdout + r.stderr
    assert git(sets["runner"], "rev-parse", "HEAD").strip() in r.stdout


def test_worker_head_differs_from_runner_rejects(sets):
    commit(sets["svc"], {"worker/w.py": "w2"}, "svc moved")
    r = _check(sets)
    assert r.returncode == 1 and "REJECT" in r.stdout


def test_gateway_head_differs_rejects(sets):
    commit(sets["svc"], {"gateway/g.py": "g2"}, "gw moved")
    r = _check(sets, worker="runner", gateway="svc")
    assert r.returncode == 1 and "gateway" in r.stdout


@pytest.mark.parametrize("path", ["worker/w.py", "gateway/g.py", "shared/s.py", "clients/web/src/a.ts", "tests/e2e/r.py", "scripts/server/x.sh"])
def test_dirty_in_set_path_rejects(sets, path):
    (sets["svc"] / path).write_text("dirty")
    (sets["runner"] / path).write_text("dirty")
    r = _check(sets)
    assert r.returncode == 1 and "dirty" in r.stdout


def test_dirty_outside_set_paths_passes(sets):
    for wt in sets.values():
        (wt / "design/d.md").write_text("edited")
    assert _check(sets).returncode == 0


def test_runner_in_other_worktree_than_services_rejects(sets):
    commit(sets["runner"], {"tests/e2e/r.py": "r2"}, "runner moved")
    assert _check(sets).returncode == 1


def test_bypass_env_passes_with_error_and_diagnostic(sets):
    commit(sets["svc"], {"worker/w.py": "w2"}, "svc moved")
    r = _check(sets, env={"PRESS_SET_MISMATCH_REASON": "비교 회차"})
    assert r.returncode == 0 and "ERROR" in r.stderr and "diagnostic" in r.stdout


def test_empty_bypass_reason_does_not_bypass(sets):
    commit(sets["svc"], {"worker/w.py": "w2"}, "svc moved")
    assert _check(sets, env={"PRESS_SET_MISMATCH_REASON": " "}).returncode == 1


def test_worker_started_before_head_moved_rejects(sets):
    r = _check(sets, wstart="early")
    assert r.returncode == 1 and "worker" in r.stdout and "기동" in r.stdout


def test_gateway_started_before_head_moved_rejects(sets):
    r = _check(sets, gstart="early")
    assert r.returncode == 1 and "gateway" in r.stdout and "기동" in r.stdout


def test_missing_worker_start_rejects(sets):
    r = _check(sets, wstart=None)
    assert r.returncode == 1 and "stamp" in r.stdout


def test_missing_gateway_start_rejects(sets):
    r = _check(sets, gstart=None)
    assert r.returncode == 1 and "stamp" in r.stdout


def test_non_numeric_start_rejects(sets):
    r = run_script("ft-press-set-check.sh", "--runner", str(sets["runner"] / "tests/e2e/r.py"), "--worker-cwd", str(sets["svc"]),
                   "--gateway-cwd", str(sets["svc"]), "--worker-start", "abc", "--gateway-start", "1")
    assert r.returncode == 1 and "stamp" in r.stdout


def test_bypass_env_also_covers_stale_start(sets):
    r = _check(sets, wstart="early", env={"PRESS_SET_MISMATCH_REASON": "비교 회차"})
    assert r.returncode == 0 and "diagnostic" in r.stdout


def _check_started(sets, start):
    return run_script("ft-press-set-check.sh", "--runner", str(sets["runner"] / "tests/e2e/r.py"), "--worker-cwd", str(sets["runner"]),
                      "--gateway-cwd", str(sets["runner"]), "--worker-start", str(start), "--gateway-start", str(start))


def _start_then_move_head(sets, files):
    """기동(now+10) 뒤(now+30)에 runner 워크트리 HEAD 를 `files` 커밋으로 옮긴다 — reflog 이벤트 시각을 GIT_COMMITTER_DATE 로 고정(sleep 0). 기동 epoch 반환."""
    now = int(time.time())
    commit(sets["runner"], files, "after start", date=f"{now + 30} +0000")
    return now + 10


def test_docs_only_commit_after_start_passes(sets):
    """M7: 기동 뒤 HEAD 이동이 design/·docs/ 문서 커밋뿐(실행 코드 경로 0)이면 PASS · evid 에 start_head·current_head 둘 다."""
    start_head = git(sets["runner"], "rev-parse", "HEAD").strip()
    start = _start_then_move_head(sets, {"design/note.md": "n", "docs/x.md": "x"})
    r = _check_started(sets, start)
    assert r.returncode == 0, r.stdout + r.stderr
    cur = git(sets["runner"], "rev-parse", "HEAD").strip()
    assert cur != start_head and f"start_head={start_head}" in r.stdout and f"current_head={cur}" in r.stdout, r.stdout


@pytest.mark.parametrize("path", ["worker/w.py", "gateway/g.py", "shared/s.py", "clients/web/src/a.ts", "tests/e2e/r.py", "scripts/server/x.sh"])
def test_set_path_commit_after_start_rejects(sets, path):
    start = _start_then_move_head(sets, {path: "changed"})
    r = _check_started(sets, start)
    assert r.returncode == 1 and "REJECT" in r.stdout and "기동" in r.stdout and path in r.stdout, r.stdout


def test_docs_plus_worker_commit_after_start_rejects_naming_only_set_file(sets):
    start = _start_then_move_head(sets, {"design/note.md": "n", "worker/w.py": "w2"})
    r = _check_started(sets, start)
    assert r.returncode == 1 and "worker/w.py" in r.stdout and "design/note.md" not in r.stdout, r.stdout


def test_checkout_back_to_older_set_commit_after_start_rejects(sets):
    """기동 뒤 HEAD 를 옛 커밋으로 되돌려도(checkout) 그 사이 실행 코드 경로 diff 가 있으면 REJECT — 이벤트 시각(reflog)으로 기동 시 HEAD 를 잡는다."""
    now = int(time.time())
    commit(sets["runner"], {"worker/w.py": "newer"}, "newer", date=f"{now - 5} +0000")  # 기동 «전» 커밋(이벤트 now-5)
    subprocess.run([REAL_GIT, "-C", str(sets["runner"]), "checkout", "-q", "--detach", "HEAD~1"], check=True, capture_output=True, text=True,
                   env={**os.environ, "GIT_COMMITTER_DATE": f"{now + 30} +0000", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})
    r = _check_started(sets, now + 10)
    assert r.returncode == 1 and "worker/w.py" in r.stdout, r.stdout


def test_start_before_reflog_begins_rejects(sets):
    """기동 시각이 reflog 최초 항목보다 앞서면 git 은 경고만 내고 가장 오래된 항목을 돌려준다 — 그 값을 기동 시 HEAD 로 믿으면 무음 통과(#0 RULE)."""
    r = _check_started(sets, int(time.time()) - 86400 * 365)
    assert r.returncode == 1 and "REJECT" in r.stdout and "기동" in r.stdout and "reflog" in r.stdout, r.stdout


def test_reflog_reader_failure_rejects(sets, tmp_path):
    """reflog 읽기 rc≠0 이면 «값을 못 읽음» = REJECT (DA⑥ r2: reader 의 rc 도 검사)."""
    shim = tmp_path / "shim"
    shim.mkdir()
    g = shim / "git"
    g.write_text(f'#!/bin/bash\nfor a in "$@"; do case "$a" in reflog|*HEAD@\\{{*) echo "boom" >&2; exit 9;; esac; done\nexec {REAL_GIT} "$@"\n')
    g.chmod(g.stat().st_mode | stat.S_IEXEC)
    t = int(time.time()) + 60
    r = run_script("ft-press-set-check.sh", "--runner", str(sets["runner"] / "tests/e2e/r.py"), "--worker-cwd", str(sets["svc"]),
                   "--gateway-cwd", str(sets["svc"]), "--worker-start", str(t), "--gateway-start", str(t),
                   extra_env={"PATH": f"{shim}{os.pathsep}{os.environ['PATH']}"})
    assert r.returncode == 1 and "reflog" in r.stdout
