"""ft2 호출자 좌석 열기 시험 (r1765 · 축 ④ «좌석은 정한 순서로 열린다»).

반례 ①~⑮ = 카드 그대로다. 팀 런타임은 `core/cli.py` 동사(submit→assign→deliver)로만 만들고, 바깥 호출은
PATH 앞의 가짜 `git`·`tmux`(argv·env 를 파일에 1줄씩 기록 · rc 는 `FAKE_<이름>_RC`)가 받는다 — 실 tmux·
실 git worktree·실 좌석 0 · 격리 tmp 뿐 · sleep 0 · 70초 안.
`--repo` 사례만 가짜 git 이 `rev-parse` 를 진짜 git 에 넘긴다(실 리포·실 아닌 폴더를 가른다) — `FAKE_GIT_REAL_REVPARSE=1`.
r1780: 가짜 git 은 기준 ref 확인(`rev-parse --verify`) rc0 에 유효 40자 sha(`FAKE_GIT_SHA`)를 낸다 · 기준 ref 사례(B①~B⑤ ·
B①b)는 임시 리포(HEAD=B ≠ origin/main=A)에서 진짜 rev-parse 를 쓴다 · B①b 만 `worktree add` 도 진짜 git(임시 리포 안).
변이 M1~M9 는 ft2 사본에서만 고치고, 변이마다 «원본으로 같은 사례 1회 더» 를 같은 시험에서 돌린다.
"""
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
CLI = FT2 / "core" / "cli.py"
LAUNCH = FT2 / "adapters" / "pi" / "launch.py"
GUARD = FT2 / "tools" / "legacy_guard.py"
TEAM, WORK, HOLDER, NOW = "harness", "W1", "harness-seat#0", "2026-11-12T01:00:00"
ATTEMPT = "a1"
ENV0 = dict(os.environ, FT_NOW=NOW)
SEAT_ENV = ("FT2_ROOT", "FT2_TEAM", "FT2_WORK", "FT2_HOLDER", "FT2_ATTEMPT")
SESSION_ARGV = ["--model", "claude-opus-5-5", "--thinking", "medium"]
FAKE_SHA = "0123456789abcdef0123456789abcdef01234567"     # 가짜 git 기준 ref 확인의 40자 sha(r1780)
BASE = "origin/main"
FAKE = '''#!__PY__
import json, os, sys
name, argv = os.path.basename(sys.argv[0]), sys.argv[1:]
sub = argv[2] if len(argv) > 2 and argv[0] == "-C" else (argv[0] if argv else "")
rec = {"prog": name, "argv": argv, "sub": sub,
       "elapsed": os.environ.get("FAKE_" + name.upper() + "_ELAPSED"),
       "env": {k: os.environ.get(k) for k in __SEAT__}}
with open(os.environ["FAKE_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec, ensure_ascii=False) + "\\n")
real = os.environ.get("REAL_GIT") or ""
if name == "git" and sub == "rev-parse" and os.environ.get("FAKE_GIT_REAL_REVPARSE") == "1":
    if "--verify" in argv and os.environ.get("FAKE_GIT_MOVE_REF"):   # B①b: 확인 «뒤» 같은 ref 를 옮긴다(경주)
        import subprocess
        done = subprocess.run([real] + argv, capture_output=True, text=True, timeout=25)
        ref, to = os.environ["FAKE_GIT_MOVE_REF"].split("=", 1)
        subprocess.run([real, "-C", argv[1], "update-ref", ref, to], check=True, timeout=25)
        sys.stdout.write(done.stdout)
        sys.stderr.write(done.stderr)
        sys.exit(done.returncode)
    os.execv(real, [real] + argv)
if name == "git" and sub == "worktree" and os.environ.get("FAKE_GIT_REAL_WORKTREE") == "1":
    os.execv(real, [real] + argv)
key = "FAKE_" + name.upper() + ("_REV_RC" if sub == "rev-parse" else "_SPARSE_RC" if sub == "sparse-checkout" else "_RC")
rc = int(os.environ.get(key) or 0)
if name == "git" and sub == "rev-parse" and "--verify" in argv and rc == 0:
    sys.stdout.write((os.environ.get("FAKE_GIT_SHA") or "__SHA__") + "\\n")
sys.exit(rc)
'''


def _paths(tmp):
    """격리 루트 + 가짜 bin. 실행 비트는 tmp 안에서만 준다(추적 파일 아님)."""
    root, fake = Path(tmp) / "root", Path(tmp) / "bin"
    root.mkdir(parents=True)
    fake.mkdir()
    body = FAKE.replace("__PY__", sys.executable).replace("__SHA__", FAKE_SHA).replace("__SEAT__", str(list(SEAT_ENV)).replace("'", '"'))
    (root / ".fable-team" / "state").mkdir(parents=True)   # r1895: 첫 본문 카드 경로 = 카드 루트 표 행(없음 = launch 거절)
    (root / ".fable-team" / "state" / "directive-roots.tsv").write_text("harness\t.\torigin/main\tdesign/*/indices\n", encoding="utf-8")
    for name in ("git", "tmux", "pi"):                # r1892: pi = 가짜 bin 의 절대 경로로 tmux 에 간다
        (fake / name).write_text(body, encoding="utf-8")
        (fake / name).chmod(0o755)
    return root, fake


def _cli(root, *args):
    done = subprocess.run([sys.executable, str(CLI)] + list(args) + ["--root", str(root), "--team", TEAM],
                          cwd=str(FT2), env=ENV0, capture_output=True, text=True, timeout=25)
    assert "Traceback" not in done.stderr, done.stderr
    return json.loads(done.stdout), done.returncode


def _runtime(root, assign=True, deliver=True):
    """팀 런타임 1개 — 접수(submit) 뒤에만 배정·전달이 가능하다(코어 계약)."""
    assert _cli(root, "submit", "--command", "c-" + WORK, "--body", "본문-" + WORK, "--work", WORK)[1] == 0
    if assign:
        assert _cli(root, "assign", "--work", WORK, "--holder", HOLDER, "--evidence", "v1,v2")[1] == 0
    if deliver:
        assert _cli(root, "deliver", "--work", WORK)[1] == 0


def _env(fake, rc=None, extra=None):
    env = dict(ENV0, PATH=str(fake) + os.pathsep + os.environ["PATH"], FAKE_LOG=str(Path(fake) / "log.jsonl"))
    for name, value in (rc or {}).items():
        env["FAKE_" + name.upper() + "_RC"] = str(value)
    env.update(extra or {})
    return env


def _argv(launcher, root, extra=()):
    return [sys.executable, str(launcher), "--root", str(root), "--team", TEAM, "--work", WORK] + list(extra)


def _launch(root, fake, launcher=LAUNCH, extra=(), rc=None, env_extra=None):
    """명령 1회 = stdout JSON 1줄. rc 는 계약값 그대로다."""
    done = subprocess.run(_argv(launcher, root, extra), env=_env(fake, rc, env_extra),
                          capture_output=True, text=True, timeout=70)
    assert "Traceback" not in done.stderr, done.stderr
    assert done.stdout.count("\n") == 1, done.stdout
    return json.loads(done.stdout), done.returncode


def _log(fake):
    path = Path(fake) / "log.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _launch_dir(root):
    return Path(root) / ".fable-team" / "teams" / TEAM / "runtime" / "launch"


def _intent(root):
    return _launch_dir(root) / ("%s@%s.intent" % (WORK, ATTEMPT))


def _worktree(root):
    return Path(root) / ".fable-team" / "teams" / TEAM / "worktrees" / ("%s@%s" % (WORK, ATTEMPT))


def _snapshot(root):
    """런타임 바이트 1장 — dry-run 이 아무것도 쓰지 않았다는 증거."""
    return {str(path.relative_to(root)): path.read_bytes()
            for path in sorted(Path(root).rglob("*")) if path.is_file()}


def case_refused(tmp, launcher=LAUNCH):
    """① submit 만 된 일 → rc1 «접수 거부» · 의도 0 · 바깥 호출 0."""
    root, fake = _paths(tmp)
    _runtime(root, assign=False, deliver=False)
    out, rc = _launch(root, fake, launcher)
    assert (out["result"], rc) == ("접수 거부", 1), out
    assert _log(fake) == [], _log(fake)
    assert _intent(root).parent.exists() is False, "의도 0"


def case_dry(tmp, launcher=LAUNCH):
    """② dry-run → argv·env·경로 JSON 1줄 · 런타임 그대로 · 바깥 호출 0."""
    root, fake = _paths(tmp)
    _runtime(root)
    before = _snapshot(root)
    out, rc = _launch(root, fake, launcher, extra=["--dry-run"])
    assert rc == 0 and out["dry_run"] is True, out
    assert out["argv"]["git"] == ["git", "-C", str(root), "worktree", "add", "--no-checkout", "--detach", str(_worktree(root)), BASE], out["argv"]
    assert out["argv"]["tmux"][:5] == ["tmux", "new-session", "-d", "-s", HOLDER], out["argv"]
    assert out["argv"]["tmux"].count("-e") == 6, out["argv"]   # tmux env 5 + pi 좌석 도구 1(r1905)
    assert out["argv"]["tmux"][-5:-1] == SESSION_ARGV, out["argv"]
    assert sorted(out["env"]) == sorted(SEAT_ENV), out["env"]
    assert _log(fake) == [], _log(fake)
    assert _snapshot(root) == before, "런타임 바이트 그대로"


def case_open(tmp, launcher=LAUNCH):
    """③ 실제 실행 → git 1 · tmux 1(-s holder) · env 5개 · 의도 1 · rc0."""
    root, fake = _paths(tmp)
    _runtime(root)
    out, rc = _launch(root, fake, launcher)
    assert (out["result"], rc, out["opened"]) == ("접수 성공", 0, True), out
    lines = _log(fake)
    assert [line["prog"] for line in lines] == ["git"] * 4 + ["tmux"] * 2, lines   # r1892: new-session 뒤 has-session 1회
    assert lines[0]["argv"] == ["-C", str(root), "rev-parse", "--verify", "--quiet", BASE + "^{commit}"], lines[0]
    assert lines[1]["argv"] == ["-C", str(root), "worktree", "add", "--no-checkout", "--detach", out["worktree"], FAKE_SHA], lines[1]
    lines = lines[:2] + lines[4:]                     # r1846: sparse·checkout 2줄은 case_sparse_order 가 본다
    assert lines[2]["argv"][:5] == ["new-session", "-d", "-s", HOLDER, "-c"], lines[2]
    assert lines[2]["argv"][5] == out["worktree"], lines[2]
    pairs = lines[2]["argv"][6:16]
    assert pairs[::2] == ["-e"] * 5, pairs
    assert dict(item.split("=", 1) for item in pairs[1::2]) == {
        "FT2_ROOT": str(root), "FT2_TEAM": TEAM, "FT2_WORK": WORK,
        "FT2_HOLDER": HOLDER, "FT2_ATTEMPT": ATTEMPT}, pairs
    assert lines[2]["argv"][16] == str(Path(fake) / "pi") and lines[2]["argv"][-5:-1] == SESSION_ARGV, lines[2]["argv"]
    intents = list(_launch_dir(root).glob("*.intent"))
    assert [path.name for path in intents] == [_intent(root).name], intents
    assert json.loads(intents[0].read_text(encoding="utf-8"))["state"] == "opened"


def case_again(tmp, launcher=LAUNCH):
    """④ 같은 일 한 번 더 → tmux 0 · rc0 «이미 열림»."""
    root, fake = _paths(tmp)
    _runtime(root)
    assert _launch(root, fake, launcher)[1] == 0
    first = _log(fake)
    out, rc = _launch(root, fake, launcher)
    assert rc == 0 and out["opened"] is False and "이미 열림" in out["reason"], out
    assert _log(fake) == first, "바깥 호출 0"


def case_race(tmp, launcher=LAUNCH):
    """⑤ 같은 일 동시 2프로세스 → tmux 정확히 1."""
    root, fake = _paths(tmp)
    _runtime(root)
    procs = [subprocess.Popen(_argv(launcher, root), env=_env(fake), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True) for _ in range(2)]
    outs = [proc.communicate(timeout=70) for proc in procs]
    for (stdout, stderr), proc in zip(outs, procs):
        assert "Traceback" not in stderr, stderr
        assert json.loads(stdout)["result"] in ("접수 성공", "복구 필요"), stdout
        assert proc.returncode in (0, 2), proc.returncode
    assert [line["sub"] for line in _log(fake)].count("new-session") == 1, _log(fake)


def case_fail(tmp, launcher=LAUNCH):
    """⑥ 가짜 tmux rc1 → rc2 «복구 필요» · 의도 줄에 «tmux» · 다시 불러도 tmux 0."""
    root, fake = _paths(tmp)
    _runtime(root)
    out, rc = _launch(root, fake, launcher, rc={"tmux": 1})
    assert (out.get("result"), rc, out.get("step")) == ("복구 필요", 2, "tmux"), out
    got = json.loads(_intent(root).read_text(encoding="utf-8"))
    assert (got["state"], got["step"]) == ("failed", "tmux"), got
    calls = [line["prog"] for line in _log(fake)].count("tmux")
    again, rc2 = _launch(root, fake, launcher)
    assert (again.get("result"), rc2) == ("복구 필요", 2), again
    assert [line["prog"] for line in _log(fake)].count("tmux") == calls, "자동 재시도 0"


def case_role(tmp, launcher=LAUNCH):
    """⑦ 표에 없는 역할 → rc2 «불명» · 바깥 호출 0 · 의도 0."""
    root, fake = _paths(tmp)
    _runtime(root)
    out, rc = _launch(root, fake, launcher, extra=["--role", "implementer"])
    assert (out["result"], rc) == ("복구 필요", 2), out
    assert "불명" in out["reason"], out
    assert _log(fake) == [], _log(fake)
    assert _intent(root).exists() is False, "의도 0"


def case_guard(tmp, launcher=LAUNCH):
    """⑧ legacy_guard ft2 rc0 · launcher 안에 세션 종료 낱말 0."""
    done = subprocess.run([sys.executable, str(GUARD), str(FT2)],
                          capture_output=True, text=True, timeout=70)
    assert done.returncode == 0, done.stdout + done.stderr
    assert "kill" not in Path(launcher).read_text(encoding="utf-8").lower(), "세션 종료 0"


def case_detach(tmp, launcher=LAUNCH):
    """⑨ worktree add 는 가지를 몰래 만들지 않는다(--detach) — 데이터 루트 가지 누적 0."""
    root, fake = _paths(tmp)
    _runtime(root)
    out, rc = _launch(root, fake, launcher)
    assert rc == 0, out
    git = [line for line in _log(fake) if line["prog"] == "git" and line["sub"] == "worktree"][0]
    assert git["argv"] == ["-C", str(root), "worktree", "add", "--no-checkout", "--detach", out["worktree"], FAKE_SHA], git["argv"]
    assert "-b" not in git["argv"], git["argv"]


def case_latest_dispatch(tmp, launcher=LAUNCH):
    """⑩ a1 배정·전달 뒤 같은 일을 #1 에 다시 배정(a2 미전달) → rc1 «접수 거부» · 의도 0 · 바깥 호출 0 (DA R1)."""
    root, fake = _paths(tmp)
    _runtime(root)                                   # a1 배정 → 전달
    got, arc = _cli(root, "assign", "--work", WORK, "--holder", "harness-seat#1", "--evidence", "v1,v2")
    assert (got.get("attempt"), arc) == ("a2", 0), got
    out, rc = _launch(root, fake, launcher)
    assert (out.get("result"), rc) == ("접수 거부", 1), out
    assert _intent(root).exists() is False, "의도 0"
    assert _log(fake) == [], "바깥 호출 0"


def _git(path, *args):
    """진짜 git 1회(임시 리포 만들기만) — stdout 1줄."""
    done = subprocess.run([shutil.which("git"), "-C", str(path), "-c", "user.name=t", "-c", "user.email=t@t",
                           "-c", "commit.gpgsign=false"] + list(args),
                          check=True, capture_output=True, text=True, timeout=25)
    return done.stdout.strip()


def _commits(path):
    """임시 리포에 커밋 A→B · HEAD=B · refs/remotes/origin/main=A(B 의 부모) · origin/release=B. (A, B) 40자."""
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run([shutil.which("git"), "init", "-q", str(path)], check=True, timeout=25)
    _git(path, "commit", "-q", "--allow-empty", "-m", "A")
    first = _git(path, "rev-parse", "HEAD")
    _git(path, "commit", "-q", "--allow-empty", "-m", "B")
    second = _git(path, "rev-parse", "HEAD")
    _git(path, "update-ref", "refs/remotes/origin/main", first)
    _git(path, "update-ref", "refs/remotes/origin/release", second)
    return first, second


def _git_repo(path):
    """실 리포 1개 — `rev-parse` 를 진짜 git 으로 부른다 · 기준 ref(origin/main) 준비(r1780 A5)."""
    _commits(path)
    return path


def _repo_env(extra=None):
    """가짜 git 이 `rev-parse` 를 진짜 git 에 넘기는 모드(r1769 · ⑫~⑮)."""
    return dict({"FAKE_GIT_REAL_REVPARSE": "1", "REAL_GIT": shutil.which("git")}, **(extra or {}))


def case_git_budget(tmp, launcher=LAUNCH):
    """⑪ 가짜 git 이 «24초 걸린 셈»(env 보고 · 실제 sleep 0) rc0 → git 상한 25초로 불러 rc0 «접수 성공» (기준판 7 = Red)."""
    root, fake = _paths(tmp)
    _runtime(root)
    caps = _launch(root, fake, launcher, extra=["--dry-run"])[0]["timeouts"]
    assert (caps["git"], caps["tmux"]) == (25, 7), caps
    out, rc = _launch(root, fake, launcher, env_extra={"FAKE_GIT_ELAPSED": "24"})
    assert (out["result"], rc, out["opened"]) == ("접수 성공", 0, True), out
    assert [line for line in _log(fake) if line["prog"] == "git"][0]["elapsed"] == "24", _log(fake)


def case_repo_target(tmp, launcher=LAUNCH):
    """⑫ `--repo <임시 리포 B>` → git argv = `-C B worktree add …` · tmux `-c <자리>` · rc0."""
    root, fake = _paths(tmp)
    _runtime(root)
    repo = _git_repo(Path(tmp) / "repoB")
    out, rc = _launch(root, fake, launcher, extra=["--repo", str(repo)], env_extra=_repo_env())
    assert (out["result"], rc) == ("접수 성공", 0), out
    lines = _log(fake)
    assert [line["prog"] for line in lines] == ["git"] * 5 + ["tmux"] * 2, lines
    assert lines[0]["argv"] == ["-C", str(repo), "rev-parse", "--show-toplevel"], lines[0]
    assert lines[1]["argv"] == ["-C", str(repo), "rev-parse", "--verify", "--quiet", BASE + "^{commit}"], lines[1]
    base_sha = _git(repo, "rev-parse", "refs/remotes/origin/main")
    assert lines[2]["argv"] == ["-C", str(repo), "worktree", "add", "--no-checkout", "--detach", str(_worktree(root)), base_sha], lines[2]
    assert lines[5]["argv"][5] == str(_worktree(root)), lines[5]


def case_repo_refused(tmp, launcher=LAUNCH):
    """⑬ `--repo <git 아닌 폴더>` → rc1 «접수 거부» · 의도 0 · tmux 0 · worktree add 0."""
    root, fake = _paths(tmp)
    _runtime(root)
    plain = Path(tmp) / "not-git"
    plain.mkdir()
    out, rc = _launch(root, fake, launcher, extra=["--repo", str(plain)], env_extra=_repo_env())
    assert (out["result"], rc) == ("접수 거부", 1), out
    assert [(line["prog"], line["sub"]) for line in _log(fake)] == [("git", "rev-parse")], _log(fake)
    assert _intent(root).exists() is False, "의도 0"


def case_git_failed(tmp, launcher=LAUNCH):
    """⑭ 가짜 git worktree add rc124(시간 초과 흉내) → rc2 «복구 필요» · 의도 failed step=git · 사유에 복구 2줄 · 재호출 0."""
    root, fake = _paths(tmp)
    _runtime(root)
    repo = _git_repo(Path(tmp) / "repoC")
    extra, bad = ["--repo", str(repo)], _repo_env({"FAKE_GIT_RC": "124"})
    out, rc = _launch(root, fake, launcher, extra=extra, env_extra=bad)
    assert (out["result"], rc, out.get("step")) == ("복구 필요", 2, "git add"), out
    reason = out["reason"]
    assert "worktree remove --force --force %s" % _worktree(root) in reason, reason
    assert "새 attempt" in reason, reason
    got = json.loads(_intent(root).read_text(encoding="utf-8"))
    assert (got["state"], got["step"]) == ("failed", "git add"), got
    calls = len(_log(fake))
    again, rc2 = _launch(root, fake, launcher, extra=extra, env_extra=bad)
    assert (again.get("result"), rc2) == ("복구 필요", 2), again
    assert len(_log(fake)) == calls, "재호출 0"


def case_repo_dry(tmp, launcher=LAUNCH):
    """⑮ `--repo` + `--dry-run` → JSON `repo` = B · 쓰기 0 · 바깥 호출 0(rev-parse 도 0)."""
    root, fake = _paths(tmp)
    _runtime(root)
    repo = _git_repo(Path(tmp) / "repoD")
    before = _snapshot(root)
    out, rc = _launch(root, fake, launcher, extra=["--repo", str(repo), "--dry-run"], env_extra=_repo_env())
    assert rc == 0 and out["dry_run"] is True, out
    assert out["repo"] == str(repo), out
    assert out["argv"]["git"] == ["git", "-C", str(repo), "worktree", "add", "--no-checkout", "--detach", str(_worktree(root)), BASE], out["argv"]
    assert _log(fake) == [], _log(fake)
    assert _snapshot(root) == before, "런타임 바이트 그대로"


def case_recovery_quoted(tmp, launcher=LAUNCH):
    """⑯ 공백 든 repo·root — 복구 안내 ⓐ 줄의 경로가 인용돼(quot) bash 로 넘겨도 갈라지지 않는다(DA 보정 291508)."""
    base = Path(tmp) / "space here"
    root, fake = _paths(base)
    _runtime(root)
    repo = _git_repo(base / "repo B")
    out, rc = _launch(root, fake, launcher, extra=["--repo", str(repo)],
                      env_extra=_repo_env({"FAKE_GIT_RC": "124"}))
    assert (out["result"], rc, out.get("step")) == ("복구 필요", 2, "git add"), out
    cmd = out["reason"].split("복구 ⓐ ", 1)[1].split(" (반쪽", 1)[0]
    assert shlex.split(cmd) == ["git", "-C", str(repo), "worktree", "remove", "--force", "--force",
                                str(_worktree(root))], cmd
    assert "새 attempt" in out["reason"], out["reason"]


def _base_root(tmp):
    """기준 ref 사례 공통(r1780) — 격리 루트 자체가 임시 리포(HEAD=B ≠ origin/main=A) · 런타임 = 배정·전달 끝."""
    root, fake = _paths(tmp)
    first, second = _commits(root)
    _runtime(root)
    return root, fake, first, second


def _worktree_call(fake):
    return [line for line in _log(fake) if line["prog"] == "git" and line["sub"] == "worktree"]


def case_base_default(tmp, launcher=LAUNCH):
    """B① 인자 없이 열기 → worktree add argv 끝 = origin/main 의 A 40자(로컬 HEAD B 아님) · 결과 rc0."""
    root, fake, first, second = _base_root(tmp)
    out, rc = _launch(root, fake, launcher, env_extra=_repo_env())
    assert (out["result"], rc) == ("접수 성공", 0), out
    calls = _worktree_call(fake)
    assert len(calls) == 1 and calls[0]["argv"][-1] == first != second, calls
    assert calls[0]["argv"][:-1] == ["-C", str(root), "worktree", "add", "--no-checkout", "--detach", str(_worktree(root))], calls


def case_base_race(tmp, launcher=LAUNCH):
    """B①b 확인(A 반환) 뒤 worktree add 전에 origin/main 을 B 로 옮김 → 만든 자리 HEAD = A = 의도 base_sha = argv 끝."""
    root, fake, first, second = _base_root(tmp)
    race = _repo_env({"FAKE_GIT_MOVE_REF": "refs/remotes/origin/main=" + second, "FAKE_GIT_REAL_WORKTREE": "1"})
    out, rc = _launch(root, fake, launcher, env_extra=race)
    assert (out["result"], rc) == ("접수 성공", 0), out
    assert _git(root, "rev-parse", "refs/remotes/origin/main") == second, "경주가 실제로 일어났다(ref 이동)"
    head = _git(_worktree(root), "rev-parse", "HEAD")
    got = json.loads(_intent(root).read_text(encoding="utf-8"))
    assert head == first == got.get("base_sha"), (head, first, got)
    assert _worktree_call(fake)[0]["argv"][-1] == first, _log(fake)


def case_base_named(tmp, launcher=LAUNCH):
    """B② `--base origin/release` → argv 끝 = origin/release 의 40자 · 의도 base=origin/release."""
    root, fake, first, second = _base_root(tmp)
    out, rc = _launch(root, fake, launcher, extra=["--base", "origin/release"], env_extra=_repo_env())
    assert (out["result"], rc) == ("접수 성공", 0), out
    assert _worktree_call(fake)[0]["argv"][-1] == second != first, _log(fake)
    got = json.loads(_intent(root).read_text(encoding="utf-8"))
    assert (got.get("base"), got.get("base_sha")) == ("origin/release", second), got


def case_base_missing(tmp, launcher=LAUNCH):
    """B③ `--base origin/없음` → 확인 실패 → rc1 «접수 거부» · 의도 0 · worktree add 0 · tmux 0."""
    root, fake, first, second = _base_root(tmp)
    out, rc = _launch(root, fake, launcher, extra=["--base", "origin/없음"], env_extra=_repo_env())
    assert (out.get("result"), rc) == ("접수 거부", 1), out
    assert [(line["prog"], line["sub"]) for line in _log(fake)] == [("git", "rev-parse")], _log(fake)
    assert _log(fake)[0]["argv"][-1] == "origin/없음^{commit}", _log(fake)
    assert _intent(root).exists() is False, "의도 0"
    assert _worktree(root).exists() is False, "자리 0"


def case_base_intent(tmp, launcher=LAUNCH):
    """B④ 열기 성공 → 의도 opened 줄 base=origin/main · base_sha=A 40자(= 실제 argv 끝)."""
    root, fake, first, second = _base_root(tmp)
    out, rc = _launch(root, fake, launcher, env_extra=_repo_env())
    assert (out["result"], rc) == ("접수 성공", 0), out
    got = json.loads(_intent(root).read_text(encoding="utf-8"))
    assert got["state"] == "opened", got
    assert (got.get("base"), got.get("base_sha")) == (BASE, first), got
    assert _worktree_call(fake)[0]["argv"][-1] == got["base_sha"], _log(fake)


def case_base_dry(tmp, launcher=LAUNCH):
    """B⑤ `--dry-run` → JSON base=origin/main · argv 끝 = 이름 `origin/main`(A4) · 바깥 호출 0(확인도 0)."""
    root, fake, first, second = _base_root(tmp)
    before = _snapshot(root)
    out, rc = _launch(root, fake, launcher, extra=["--dry-run"], env_extra=_repo_env())
    assert rc == 0 and out["dry_run"] is True, out
    assert out.get("base") == BASE and out["argv"]["git"][-1] == BASE, out
    assert _log(fake) == [], _log(fake)
    assert _snapshot(root) == before, "런타임 바이트 그대로"


def _sparse_argv(root):
    """r1846 ⓑⓒ — 패턴 = 1.x r835 ft_sparse_patterns 와 같은 3줄(자기 팀 design 만)."""
    path = str(_worktree(root))
    return (["-C", path, "sparse-checkout", "set", "--no-cone", "/*", "!/design/teams/*/", "/design/teams/%s/" % TEAM],
            ["-C", path, "checkout", "-q"])


def case_sparse_order(tmp, launcher=LAUNCH):
    """S① git 단계 = ⓐ add --no-checkout → ⓑ sparse-checkout set → ⓒ checkout 순서 · tmux 는 그 뒤(기준판 add 1회 = Red)."""
    root, fake = _paths(tmp)
    _runtime(root)
    out, rc = _launch(root, fake, launcher)
    assert (out["result"], rc) == ("접수 성공", 0), out
    lines = _log(fake)
    assert [line["sub"] for line in lines] == ["rev-parse", "worktree", "sparse-checkout", "checkout", "new-session", "has-session"], lines
    assert "--no-checkout" in lines[1]["argv"], lines[1]
    assert (lines[2]["argv"], lines[3]["argv"]) == _sparse_argv(root), lines[2:4]


def case_sparse_fail(tmp, launcher=LAUNCH):
    """S② ⓑ rc1 → rc2 «복구 필요» step «git sparse» · 복구 2줄 · ⓒ·tmux 호출 0."""
    root, fake = _paths(tmp)
    _runtime(root)
    out, rc = _launch(root, fake, launcher, env_extra={"FAKE_GIT_SPARSE_RC": "1"})
    assert (out.get("result"), rc, out.get("step")) == ("복구 필요", 2, "git sparse"), out
    assert "worktree remove --force --force" in out["reason"], out
    assert [line["sub"] for line in _log(fake)] == ["rev-parse", "worktree", "sparse-checkout"], _log(fake)


def case_sparse_dry(tmp, launcher=LAUNCH):
    """S③ dry-run → 계획 줄에 git 3호출(add·sparse·checkout) · 의도 파일 쓰기 0 · 바깥 호출 0."""
    root, fake = _paths(tmp)
    _runtime(root)
    out, rc = _launch(root, fake, launcher, extra=["--dry-run"])
    assert rc == 0 and out["argv"]["git"][4:6] == ["add", "--no-checkout"], out["argv"]
    assert (out["argv"]["sparse"][1:], out["argv"]["checkout"][1:]) == _sparse_argv(root), out["argv"]
    assert _log(fake) == [] and _intent(root).exists() is False, _log(fake)


CASES = {"refused": case_refused, "dry": case_dry, "open": case_open, "again": case_again,
         "race": case_race, "fail": case_fail, "role": case_role, "guard": case_guard,
         "detach": case_detach, "latest": case_latest_dispatch, "budget": case_git_budget,
         "repo": case_repo_target, "repo_refused": case_repo_refused, "git_failed": case_git_failed,
         "repo_dry": case_repo_dry, "recovery_quoted": case_recovery_quoted,
         "base_default": case_base_default, "base_race": case_base_race, "base_named": case_base_named,
         "base_missing": case_base_missing, "base_intent": case_base_intent, "base_dry": case_base_dry,
         "sparse_order": case_sparse_order, "sparse_fail": case_sparse_fail, "sparse_dry": case_sparse_dry}
MUTANTS = {
    "M1": ("launch.py", "    if holder is None:", "    if holder is None and False:"),
    "M2": ("launch.py", '    if given.get("dry"):',
           '    if given.get("dry"):\n        os.makedirs(os.path.dirname(plan["intent"]), exist_ok=True)\n'
           '        write_intent(plan["intent"], dict(env, state="opening"))'),
    "M3": ("launch_plan.py", "os.link(tmp, path)", "shutil.copyfile(tmp, path)"),   # r1929 O_EXCL → link 예약 · 덮어쓰기 = 두 번 열림
    "M4": ("launch.py", '    rc, detail = call(plan["tmux"], None, dict(os.environ, **env), TMUX_TIMEOUT)\n    if rc != 0:',
           '    rc, detail = call(plan["tmux"], None, dict(os.environ, **env), TMUX_TIMEOUT)\n    rc = 0\n    if rc != 0:'),
    "M5": ("launch_plan.py", '+ pairs + [pi or "pi"]', '+ [] + [pi or "pi"]'),
    "M6": ("launch.py", "GIT_TIMEOUT, TMUX_TIMEOUT, USAGE = 25, 7, 64", "GIT_TIMEOUT, TMUX_TIMEOUT, USAGE = 7, 7, 64"),
    "M7": ("launch.py", 'repo = os.path.abspath(given.get("repo") or root)', 'repo = os.path.abspath(root)'),
    "M8": ("launch.py", '        if rc != 0:\n            os.unlink(plan["intent"])',
           '        if rc != 0 and False:\n            os.unlink(plan["intent"])'),
    "M9": ("launch.py", '    if step.startswith("git"):', '    if False:'),
    # r1780 기준 ref 변이(카드 M1~M5 · 이름 앞에 B)
    "BM1": ("launch_plan.py", "    return git[:-1] + [sha]", "    return git[:-1]"),
    "BM2": ("launch.py", 'given.get("base") or planner.DEFAULT_BASE', 'planner.DEFAULT_BASE'),
    "BM3": ("launch_plan.py", "return (0, sha) if sha else (1,", "return (0, sha) if True else (1,"),
    "BM4": ("launch.py", 'worktree=plan["worktree"], base=base, base_sha=sha,', 'worktree=plan["worktree"], base=base,'),
    "BM5": ("launch_plan.py", "    return git[:-1] + [sha]", "    return git"),
    # r1846 sparse 변이(카드 M1·M2 · 이름 앞에 S)
    "SM1": ("launch_plan.py", '"add", "--no-checkout", "--detach"', '"add", "--detach"'),
    "SM2": ("launch.py", "        if rc != 0:\n            return failed(plan, env, step,",
            '        if rc != 0 and step != "git sparse":\n            return failed(plan, env, step,'),
}
# 변이가 깨뜨려야 하는 사례 — 카드 §변이 그대로
MUTANT_CASE = {"M1": "refused", "M2": "dry", "M3": "again", "M4": "fail", "M5": "open",
               "M6": "budget", "M7": "repo", "M8": "repo_refused", "M9": "git_failed",
               "BM1": "base_default", "BM2": "base_named", "BM3": "base_missing", "BM4": "base_intent",
               "BM5": "base_race", "SM1": "sparse_order", "SM2": "sparse_fail"}


def _mutant(tmp, name):
    """ft2 사본 1개 + launch.py·launch_plan.py 손상 1곳(원본 무수정). 치환 0 = 시험 빨강(RuntimeError · AssertionError 아님)."""
    filename, needle, replacement = MUTANTS[name]
    dest = Path(tmp) / "mutant" / "feature-pack" / "fable-team" / "ft2"
    shutil.copytree(FT2, dest, ignore=shutil.ignore_patterns("__pycache__"))
    target = dest / "adapters" / "pi" / filename
    text = target.read_text(encoding="utf-8")
    mutated = text.replace(needle, replacement, 1) if needle in text else text
    target.write_text(mutated, encoding="utf-8")
    if mutated == text or replacement not in target.read_text(encoding="utf-8"):
        raise RuntimeError("%s 치환 0 — needle 불일치(원본 손상 아님 · 사례를 통과로 세면 안 된다)" % name)
    return dest / "adapters" / "pi" / "launch.py"


def test_01_refused(tmp_path):
    case_refused(tmp_path)


def test_02_dry_run(tmp_path):
    case_dry(tmp_path)


def test_03_open(tmp_path):
    case_open(tmp_path)


def test_04_already_open(tmp_path):
    case_again(tmp_path)


def test_05_race(tmp_path):
    case_race(tmp_path)


def test_06_tmux_fail(tmp_path):
    case_fail(tmp_path)


def test_07_unknown_role(tmp_path):
    case_role(tmp_path)


def test_08_guard(tmp_path):
    case_guard(tmp_path)


def test_09_worktree_detach(tmp_path):
    case_detach(tmp_path)


def test_10_latest_dispatch_not_delivered(tmp_path):
    case_latest_dispatch(tmp_path)


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutants(tmp_path, name):
    """변이 1개 = 그 사례가 빨강 · 같은 사례를 원본으로 1회 더 = 초록. 변이 만들기(치환)가 실패하면 시험이 빨강."""
    case = CASES[MUTANT_CASE[name]]
    launcher = _mutant(tmp_path / name, name)
    with pytest.raises(AssertionError):
        case(tmp_path / name, launcher)
    case(tmp_path / (name + "-orig"), LAUNCH)


def test_11_git_timeout_25(tmp_path):
    case_git_budget(tmp_path)


def test_12_repo_target(tmp_path):
    case_repo_target(tmp_path)


def test_13_repo_not_git(tmp_path):
    case_repo_refused(tmp_path)


def test_14_git_step_recovery(tmp_path):
    case_git_failed(tmp_path)


def test_15_repo_dry_run(tmp_path):
    case_repo_dry(tmp_path)


def test_16_recovery_quoted_paths(tmp_path):
    case_recovery_quoted(tmp_path)


def test_b01_base_default_origin_main(tmp_path):
    case_base_default(tmp_path)


def test_b01b_base_race_records_checked_sha(tmp_path):
    case_base_race(tmp_path)


def test_b02_base_named(tmp_path):
    case_base_named(tmp_path)


def test_b03_base_missing_refused(tmp_path):
    case_base_missing(tmp_path)


def test_b04_base_in_intent(tmp_path):
    case_base_intent(tmp_path)


def test_b05_base_dry_run(tmp_path):
    case_base_dry(tmp_path)


def test_s01_sparse_order(tmp_path):
    case_sparse_order(tmp_path)


def test_s02_sparse_fail_stops(tmp_path):
    case_sparse_fail(tmp_path)


def test_s03_sparse_dry_run(tmp_path):
    case_sparse_dry(tmp_path)
