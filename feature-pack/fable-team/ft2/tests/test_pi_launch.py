"""ft2 호출자 좌석 열기 시험 (r1765 · 축 ④ «좌석은 정한 순서로 열린다»).

반례 ①~⑧ = 카드 그대로다. 팀 런타임은 `core/cli.py` 동사(submit→assign→deliver)로만 만들고, 바깥 호출은
PATH 앞의 가짜 `git`·`tmux`(argv·env 를 파일에 1줄씩 기록 · rc 는 `FAKE_<이름>_RC`)가 받는다 — 실 tmux·
실 git worktree·실 좌석 0 · 격리 tmp 뿐 · sleep 0 · 70초 안.
변이 M1~M4 는 ft2 사본에서만 고치고, 변이마다 «원본으로 같은 사례 1회 더» 를 같은 시험에서 돌린다.
"""
import json
import os
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
FAKE = '''#!__PY__
import json, os, sys
name = os.path.basename(sys.argv[0])
rec = {"prog": name, "argv": sys.argv[1:],
       "env": {k: os.environ.get(k) for k in __SEAT__}}
with open(os.environ["FAKE_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec, ensure_ascii=False) + "\\n")
sys.exit(int(os.environ.get("FAKE_" + name.upper() + "_RC") or 0))
'''


def _paths(tmp):
    """격리 루트 + 가짜 bin. 실행 비트는 tmp 안에서만 준다(추적 파일 아님)."""
    root, fake = Path(tmp) / "root", Path(tmp) / "bin"
    root.mkdir(parents=True)
    fake.mkdir()
    body = FAKE.replace("__PY__", sys.executable).replace("__SEAT__", str(list(SEAT_ENV)).replace("'", '"'))
    for name in ("git", "tmux"):
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


def _env(fake, rc=None):
    env = dict(ENV0, PATH=str(fake) + os.pathsep + os.environ["PATH"], FAKE_LOG=str(Path(fake) / "log.jsonl"))
    for name, value in (rc or {}).items():
        env["FAKE_" + name.upper() + "_RC"] = str(value)
    return env


def _argv(launcher, root, extra=()):
    return [sys.executable, str(launcher), "--root", str(root), "--team", TEAM, "--work", WORK] + list(extra)


def _launch(root, fake, launcher=LAUNCH, extra=(), rc=None):
    """명령 1회 = stdout JSON 1줄. rc 는 계약값 그대로다."""
    done = subprocess.run(_argv(launcher, root, extra), env=_env(fake, rc),
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
    assert out["argv"]["git"] == ["git", "worktree", "add", "--detach", str(_worktree(root))], out["argv"]
    assert out["argv"]["tmux"][:5] == ["tmux", "new-session", "-d", "-s", HOLDER], out["argv"]
    assert out["argv"]["tmux"].count("-e") == 5, out["argv"]
    assert out["argv"]["tmux"][-4:] == SESSION_ARGV, out["argv"]
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
    assert [line["prog"] for line in lines] == ["git", "tmux"], lines
    assert lines[0]["argv"] == ["worktree", "add", "--detach", out["worktree"]], lines[0]
    assert lines[1]["argv"][:5] == ["new-session", "-d", "-s", HOLDER, "-c"], lines[1]
    assert lines[1]["argv"][5] == out["worktree"], lines[1]
    pairs = lines[1]["argv"][6:16]
    assert pairs[::2] == ["-e"] * 5, pairs
    assert dict(item.split("=", 1) for item in pairs[1::2]) == {
        "FT2_ROOT": str(root), "FT2_TEAM": TEAM, "FT2_WORK": WORK,
        "FT2_HOLDER": HOLDER, "FT2_ATTEMPT": ATTEMPT}, pairs
    assert lines[1]["argv"][16] == "pi" and lines[1]["argv"][-4:] == SESSION_ARGV, lines[1]["argv"]
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
    assert [line["prog"] for line in _log(fake)].count("tmux") == 1, _log(fake)


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
    git = [line for line in _log(fake) if line["prog"] == "git"][0]
    assert git["argv"] == ["worktree", "add", "--detach", out["worktree"]], git["argv"]
    assert "-b" not in git["argv"], git["argv"]


CASES = {"refused": case_refused, "dry": case_dry, "open": case_open, "again": case_again,
         "race": case_race, "fail": case_fail, "role": case_role, "guard": case_guard,
         "detach": case_detach}
MUTANTS = {
    "M1": ("    if holder is None:", "    if holder is None and False:"),
    "M2": ('    if given.get("dry"):',
           '    if given.get("dry"):\n        os.makedirs(os.path.dirname(plan["intent"]), exist_ok=True)\n'
           '        write_intent(plan["intent"], dict(env, state="opening"))'),
    "M3": ("os.O_CREAT | os.O_EXCL | os.O_WRONLY", "os.O_CREAT | os.O_WRONLY"),
    "M4": ('    rc, detail = call(plan["tmux"], None, dict(os.environ, **env))\n    if rc != 0:',
           '    rc, detail = call(plan["tmux"], None, dict(os.environ, **env))\n    rc = 0\n    if rc != 0:'),
    "M5": ('+ pairs + ["pi"]', '+ [] + ["pi"]'),
}
# 변이가 깨뜨려야 하는 사례 — 카드 §변이 그대로
MUTANT_CASE = {"M1": "refused", "M2": "dry", "M3": "again", "M4": "fail", "M5": "open"}


def _mutant(tmp, name):
    """ft2 사본 1개 + launch.py 손상 1곳(원본 무수정)."""
    needle, replacement = MUTANTS[name]
    dest = Path(tmp) / "mutant" / "feature-pack" / "fable-team" / "ft2"
    shutil.copytree(FT2, dest, ignore=shutil.ignore_patterns("__pycache__"))
    target = dest / "adapters" / "pi" / "launch.py"
    text = target.read_text(encoding="utf-8")
    assert needle in text, name
    target.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
    return target


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


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutants(tmp_path, name):
    """변이 1개 = 그 사례가 빨강 · 같은 사례를 원본으로 1회 더 = 초록."""
    case = CASES[MUTANT_CASE[name]]
    with pytest.raises(AssertionError):
        case(tmp_path / name, _mutant(tmp_path / name, name))
    case(tmp_path / (name + "-orig"), LAUNCH)
