"""Synthetic scenarios of the E1 terminal condition table (design arch-20261015-opa-popup-design-r6 §6).

Everything is synthetic: a fake `op` that only answers `--version`, a fake `pgrep`, synthetic environment values
and a synthetic token file. No real op, no real launchd, no network, no operating file. The time constants are
scaled down by environment overrides that only `--selftest` accepts; the budget scenarios run the real
production numbers (7.0 s attempt, 75.0 s total, 5.0 s reserve) against a fake clock.
"""

from __future__ import annotations

import collections
import importlib.util
import itertools
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time

import pytest

from test_probe_opa import alive, wait_until

OPS = Path(__file__).resolve().parents[1] / "ops" / "probe-opa"
COMPARE_SH = OPS / "compare.sh"
COMPARE_PY = OPS / "compare.py"

STDOUT_MARK = "SYNTH_STDOUT_9001"
STDERR_MARK = "SYNTH_STDERR_9002"
TOKEN = "ops_synthetic_e1_service_token_3b9e"
PLAN = [("A", 1), ("B", 1), ("C", 1), ("A", 2), ("B", 2), ("C", 2)]
STATES = ("fast", "slow", "mixed")
SHELL_EXTRAS = {"PWD", "SHLVL", "_", "OLDPWD"}
ALLOWLIST = {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR"}

# ambient names the measurement must drop from condition A (matched by name only, case-insensitive) and names it keeps
DROPPED = {
    "OP_SERVICE_ACCOUNT_TOKEN": "SYNTH_VAL_OP_SA_5521", "OP_FOO": "SYNTH_VAL_OP_FOO_5522",
    "op_lower": "SYNTH_VAL_OP_LOW_5523", "MY_TOKEN": "SYNTH_VAL_TOKEN_5524", "some_Key": "SYNTH_VAL_KEY_5525",
    "AWS_SECRET_THING": "SYNTH_VAL_SECRET_5526", "DB_PASSWORD": "SYNTH_VAL_PASS_5527",
    "GCP_CREDENTIALS": "SYNTH_VAL_CRED_5528", "SSH_AUTH_SOCK": "SYNTH_VAL_AUTH_5529",
    "AUTHORITY": "SYNTH_VAL_AUTHY_5530",
}
KEPT = {"EDITOR": "SYNTH_VAL_EDITOR_5531", "FOO_HOME": "SYNTH_VAL_FOOHOME_5532"}


def load_compare(monkeypatch, env: dict[str, str] | None = None):
    """Import compare.py in selftest mode (probe.py reads ``--mode`` from argv and the overrides from the env)."""
    monkeypatch.setattr(sys, "argv", ["compare.py", "--mode", "selftest"])
    for name, value in (env or {}).items():
        monkeypatch.setenv(name, value)
    spec = importlib.util.spec_from_file_location("compare_opa", COMPARE_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CSandbox:
    def __init__(self, tmp_path: Path):
        self.root = tmp_path
        self.home = tmp_path / "home"
        self.bin = tmp_path / "bin"
        self.shim = tmp_path / "shim"
        self.base = tmp_path / "probe-base"
        for path in (self.home, self.bin, self.shim):
            path.mkdir()
        self.plan = tmp_path / "plan.txt"
        self.cnt = tmp_path / "cnt"
        self.oppids = tmp_path / "oppids"
        self.descpids = tmp_path / "descpids"
        self.pgrep_count = tmp_path / "pgrep-count"
        self.pgrep_count.write_text("2", encoding="utf-8")
        krb = self.home / ".config" / "krb"
        krb.mkdir(parents=True)
        (krb / "op-sa-token").write_text(TOKEN + "\n", encoding="utf-8")
        self.set_pgrep()
        self.set_plan()
        self.make_op()

    def set_pgrep(self, grow: bool = False) -> None:
        body = (
            f'#!/bin/sh\nn=$(cat "{self.pgrep_count}")\n'
            + (f'echo $((n+1)) > "{self.pgrep_count}"\n' if grow else "")
            + 'i=0; while [ $i -lt $n ]; do echo $((1000+i)); i=$((i+1)); done\n[ "$n" -gt 0 ]\n'
        )
        (self.shim / "pgrep").write_text(body, encoding="utf-8")
        (self.shim / "pgrep").chmod(0o755)

    def set_plan(self, *modes: str) -> None:
        self.plan.write_text("\n".join(modes) + "\n", encoding="utf-8")

    def make_op(self) -> Path:
        """A fake `op`: answers `--version` per call number according to the plan file; records its env."""
        root = self.root
        body = (
            "#!/bin/sh\n"
            f'n=$(cat "{root}/cnt" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "{root}/cnt"\n'
            f'echo $$ >> "{self.oppids}"\n'
            f'env > "{root}/envdump-$n.txt"\n'
            f'echo "$*" >> "{root}/args.txt"\n'
            '[ "$1" = "--version" ] && [ "$#" = 1 ] || exit 2\n'
            f'mode=$(sed -n "${{n}}p" "{self.plan}" 2>/dev/null); [ -n "$mode" ] || mode=fast\n'
            'case "$mode" in\n'
            "  fast) echo 2.32.1; exit 0;;\n"
            f'  mark) echo "2.32.1 {STDOUT_MARK}"; echo "{STDERR_MARK}" >&2; exit 0;;\n'
            "  badrc) echo 2.32.1; exit 1;;\n"
            '  badout) echo "garbage"; exit 0;;\n'
            "  slow) exec sleep 30;;\n"
            f'  desc) sleep 25 & echo $! >> "{self.descpids}"; exec sleep 30;;\n'
            "esac\nexit 3\n"
        )
        path = self.bin / "op"
        path.write_text(body, encoding="utf-8")
        path.chmod(0o755)
        return path

    def env(self, **extra: str) -> dict[str, str]:
        env = {
            "PATH": f"{self.shim}:{self.bin}:/usr/bin:/bin", "HOME": str(self.home), "TMPDIR": str(self.root),
            "PROBE_BASE": str(self.base), "PROBE_T_ATTEMPT": "0.6", "PROBE_T_REAP": "0.5", "PROBE_T_PIPE": "0.3",
            "PROBE_C_T_TOTAL": "40", "PROBE_C_T_RESERVE": "2", "PROBE_C_T_OBS": "1.0",
        }
        env.update(extra)
        return env

    def start(self, *args: str, selftest: bool = True, python: str | None = None, **extra: str) -> subprocess.Popen:
        argv = ["/bin/bash", str(COMPARE_SH)]
        if selftest:
            argv.append("--selftest")
        argv += ["--python", python or sys.executable, *args]
        return subprocess.Popen(
            argv, env=self.env(**extra), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True, preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL),
        )

    def run(self, *args: str, timeout: float = 120, **extra: str) -> subprocess.CompletedProcess:
        process = self.start(*args, **extra)
        out, err = process.communicate(timeout=timeout)
        return subprocess.CompletedProcess(process.args, process.returncode, out, err)

    def result_path(self) -> Path:
        paths = sorted(self.base.glob("compare-*.result.json"))
        assert len(paths) == 1, paths
        return paths[0]

    def result(self) -> dict:
        return json.loads(self.result_path().read_text(encoding="utf-8"))

    def temp_dirs(self) -> list[Path]:
        return [p for p in self.base.glob("compare-*") if p.is_dir()] if self.base.exists() else []

    def envdump(self, n: int) -> dict[str, str]:
        out = {}
        for line in (self.root / f"envdump-{n}.txt").read_text(encoding="utf-8").splitlines():
            if "=" in line:
                name, value = line.split("=", 1)
                out[name] = value
        return out

    def op_calls(self) -> int:
        return int(self.cnt.read_text()) if self.cnt.exists() else 0

    def tree_text(self, proc: subprocess.CompletedProcess) -> str:
        parts = [proc.stdout, proc.stderr]
        for path in self.base.rglob("*") if self.base.exists() else []:
            if path.is_file():
                parts.append(path.read_text(encoding="utf-8", errors="replace"))
            parts.append(path.name)
        return "\n".join(parts)


@pytest.fixture
def sb(tmp_path):
    return CSandbox(tmp_path)


def fake_round(variant: str, number: int, status: str, unconfirmed: bool = False) -> dict:
    return {"variant": variant, "round": number, "status": status, "elapsed_ms": 10, "rc": 0, "reaped": not unconfirmed,
            "child_exit_unconfirmed": unconfirmed}


def rounds_for(states: tuple[str, str, str]) -> list[dict]:
    """fast = both rounds success, slow = both timeout, mixed = the first success and the second timeout."""
    out = []
    for number, (variant, _) in itertools.product((1, 2), (("A", 0), ("B", 0), ("C", 0))):
        state = states["ABC".index(variant)]
        status = "success" if state == "fast" or (state == "mixed" and number == 1) else "timeout"
        out.append(fake_round(variant, number, status))
    return out


def expected_for(states: tuple[str, str, str]) -> str:
    """An independent restatement of the design table (rows 5-11)."""
    a, b, c = states
    if "mixed" in states:
        return "mixed_within_condition"
    if states == ("fast", "fast", "fast"):
        return "terminal_all_fast"
    if states == ("slow", "slow", "slow"):
        return "terminal_all_slow"
    if a == "fast" and b == "slow":
        return "env_axis_associated"
    if states == ("slow", "slow", "fast"):
        return "isolated_config_axis_associated"
    if states == ("fast", "fast", "slow"):
        return "isolated_only_slow"
    return "mixed_unexpected"


# ---------------------------------------------------------------------------------------------------------
# 1. the 27 combinations and the precedence of the incomplete / error rows
def test_conclusion_table_reaches_every_combination_with_the_designed_counts(monkeypatch):
    compare = load_compare(monkeypatch)
    seen = collections.Counter()
    for states in itertools.product(STATES, repeat=3):
        got = compare.conclude(rounds_for(states), cancelled=False)
        assert got == expected_for(states), states
        seen[got] += 1
    assert [seen[name] for name in ("mixed_within_condition", "terminal_all_fast", "terminal_all_slow",
                                    "env_axis_associated", "isolated_config_axis_associated",
                                    "isolated_only_slow", "mixed_unexpected")] == [19, 1, 1, 2, 1, 1, 2]


def test_incomplete_and_error_rows_win_over_every_combination_in_design_order(monkeypatch):
    compare = load_compare(monkeypatch)
    for states in itertools.product(STATES, repeat=3):
        base = rounds_for(states)
        unconfirmed = [dict(r) for r in base]
        unconfirmed[2] = fake_round("C", 1, "timeout", unconfirmed=True)
        skipped = [dict(r) for r in base]
        skipped[5] = fake_round("C", 2, "skipped_budget")
        errors = [dict(r) for r in base]
        errors[1] = fake_round("B", 1, "bad_output")
        errors_spawn = [dict(r) for r in base]
        errors_spawn[4] = fake_round("B", 2, "spawn_error")
        both = [dict(r) for r in unconfirmed]
        both[5] = fake_round("C", 2, "skipped_after_unconfirmed")
        assert compare.conclude(base, cancelled=True) == "cancelled_incomplete"
        assert compare.conclude(unconfirmed, cancelled=True) == "cancelled_incomplete"
        assert compare.conclude(unconfirmed, cancelled=False) == "incomplete_exit_unconfirmed"
        assert compare.conclude(both, cancelled=False) == "incomplete_exit_unconfirmed"
        assert compare.conclude(skipped, cancelled=False) == "incomplete_missing_rounds"
        both_skipped_error = [dict(r) for r in skipped]
        both_skipped_error[1] = fake_round("B", 1, "bad_output")
        assert compare.conclude(both_skipped_error, cancelled=False) == "incomplete_missing_rounds"
        assert compare.conclude(errors, cancelled=False) == "inconclusive_error"
        assert compare.conclude(errors_spawn, cancelled=False) == "inconclusive_error"
        assert compare.conclude(base[:4], cancelled=False) == "incomplete_missing_rounds"  # rounds that never ran


# ---------------------------------------------------------------------------------------------------------
# 2. the normal run: values, files, screen
def test_normal_run_records_six_rounds_in_order_without_values_and_removes_the_temp_folder(sb):
    sb.set_plan(*["mark"] * 6)
    ambient = {**DROPPED, **KEPT}
    proc = sb.run(**ambient)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    result = sb.result()
    assert result["complete"] is True and result["exit_class"] == "ran_all"
    assert result["conclusion"] == "terminal_all_fast"
    assert [(r["variant"], r["round"]) for r in result["rounds"]] == PLAN
    for r in result["rounds"]:
        assert set(r) == {"variant", "round", "status", "elapsed_ms", "rc", "reaped", "child_exit_unconfirmed"}
        assert r["status"] == "success" and r["rc"] == 0 and r["reaped"] is True and r["child_exit_unconfirmed"] is False
        assert isinstance(r["elapsed_ms"], int)
    assert set(result) == {"v", "rounds", "conditions", "op_count_before", "op_count_after", "sock_mtime_changed",
                           "removed_name_count_A", "leftover_check_required", "complete", "exit_class", "conclusion"}
    assert result["conditions"] == {"A": "fast", "B": "fast", "C": "fast"}
    assert result["op_count_before"] == 2 and result["op_count_after"] == 2
    assert result["sock_mtime_changed"] is False
    assert result["removed_name_count_A"] == len(DROPPED)
    assert result["leftover_check_required"] is False
    assert sb.op_calls() == 6
    assert (sb.root / "args.txt").read_text().split() == ["--version"] * 6   # nothing but `op --version`
    assert sb.temp_dirs() == []   # equal process counts: the folder of condition C is gone
    assert stat.S_IMODE(sb.result_path().stat().st_mode) == 0o600
    assert "terminal_all_fast" in proc.stdout or "7초" in proc.stdout   # a human-readable summary is printed


def test_no_value_reaches_the_screen_or_any_file(sb):
    sb.set_plan(*["mark"] * 6)
    ambient = {**DROPPED, **KEPT}
    proc = sb.run(**ambient)
    assert proc.returncode == 0
    text = sb.tree_text(proc)
    for value in (*ambient.values(), STDOUT_MARK, STDERR_MARK, TOKEN, "2.32.1"):
        assert value not in text, value
    for name in DROPPED:     # not even the names of the removed variables are written
        assert name not in text, name


def test_an_op_that_prints_garbage_or_fails_is_an_error_not_a_speed(sb):
    sb.set_plan("badout", "badrc", "fast", "fast", "fast", "fast")
    proc = sb.run()
    result = sb.result()
    assert proc.returncode == 0
    assert [r["status"] for r in result["rounds"]][:2] == ["bad_output", "bad_output"]
    assert result["conclusion"] == "inconclusive_error"
    assert result["complete"] is True and result["exit_class"] == "ran_all"


# ---------------------------------------------------------------------------------------------------------
# 3. the three environments
def test_environments_a_b_c_follow_the_design(sb):
    sb.set_plan(*["fast"] * 6)
    ambient = {**DROPPED, **KEPT}
    proc = sb.run(**ambient)
    assert proc.returncode == 0
    real_home = str(sb.home)
    ambient_tmp = str(sb.root)
    for call in range(1, 7):
        variant = "ABC"[(call - 1) % 3]
        env = sb.envdump(call)
        names = set(env) - SHELL_EXTRAS
        if variant == "A":
            assert env["HOME"] == real_home
            assert env["EDITOR"] == KEPT["EDITOR"] and env["FOO_HOME"] == KEPT["FOO_HOME"]
            upper = {n.upper() for n in names}
            assert not any(n.startswith("OP_") for n in upper), names
            for pattern in ("TOKEN", "KEY", "SECRET", "PASSWORD", "CREDENTIAL", "AUTH"):
                assert not any(pattern in n for n in upper), (pattern, names)
            assert "PATH" in env
        elif variant == "B":
            assert names <= ALLOWLIST, names - ALLOWLIST
            assert env["HOME"] == real_home and env["TMPDIR"] == ambient_tmp and "OP_CONFIG_DIR" not in env
        else:
            assert names <= ALLOWLIST | {"OP_CONFIG_DIR"}, names - ALLOWLIST - {"OP_CONFIG_DIR"}
            assert env["HOME"] != real_home and env["HOME"].startswith(str(sb.base / "compare-"))
            assert env["OP_CONFIG_DIR"] == env["HOME"] + "/.config/op"
            assert env["TMPDIR"] == ambient_tmp   # TMPDIR stays (design §6.1: only HOME and the config dir move)


def test_the_token_file_is_never_opened_and_nothing_is_started_in_process(monkeypatch, tmp_path):
    """Open calls are audited while main() runs in this process (the child is replaced by a fake)."""
    sb = CSandbox(tmp_path)
    compare = load_compare(monkeypatch, {"HOME": str(sb.home), "PROBE_BASE": str(sb.base),
                                         "PATH": f"{sb.shim}:{sb.bin}:/usr/bin:/bin"})
    opened: list[str] = []
    armed = {"on": True}

    def hook(event, args):
        if armed["on"] and event == "open" and args and args[0] is not None:
            opened.append(str(args[0]))
    sys.addaudithook(hook)

    def fake_attempt(argv, env, limit_s):
        return {"status": "success", "rc": 0, "child_exited": True, "reaped": True, "child_exit_unconfirmed": False,
                "descendants_may_hold_pipe": False, "stdout": b"2.32.1\n", "stderr": b""}
    monkeypatch.setattr(compare, "run_attempt", fake_attempt)
    try:
        assert compare.main(["--mode", "selftest"]) == 0
    finally:
        armed["on"] = False
    assert opened, "the audit hook saw no open at all"
    for path in opened:
        assert "op-sa-token" not in path and "/krb" not in path, path


def test_sources_have_no_token_read_no_foreign_kill_and_no_launchd():
    for source in (COMPARE_PY.read_text(encoding="utf-8"), COMPARE_SH.read_text(encoding="utf-8")):
        for forbidden in ("op-sa-token", "read_token", "OP_SERVICE_ACCOUNT_TOKEN", "os.kill", "os.killpg", "killpg",
                          "pkill", "killall", "launchctl", "kill -9", "kill -KILL"):
            assert forbidden not in source, forbidden
    py = COMPARE_PY.read_text(encoding="utf-8")
    assert ".kill(" not in py and ".terminate(" not in py   # the measured child is ended by probe._end_child only
    assert '"account"' not in py and "'signin'" not in py and "whoami" not in py   # no account command exists


# ---------------------------------------------------------------------------------------------------------
# 4. ending a child
def test_a_timed_out_child_is_ended_alone_and_a_descendant_holding_the_pipe_changes_no_deadline(sb):
    sb.set_plan(*["desc"] * 6)
    started = time.monotonic()
    try:
        proc = sb.run()
        elapsed = time.monotonic() - started
        result = sb.result()
        assert proc.returncode == 0, proc.stdout + proc.stderr
        assert [r["status"] for r in result["rounds"]] == ["timeout"] * 6
        assert all(r["reaped"] is True and r["child_exit_unconfirmed"] is False for r in result["rounds"])
        assert result["conclusion"] == "terminal_all_slow"
        assert 6 * 0.6 <= elapsed < 6 * (0.6 + 0.5 + 0.3) + 6.0, elapsed   # 6 attempts + bounded recovery, no waiting for the descendant
        descendants = [int(x) for x in sb.descpids.read_text().split()]
        assert len(descendants) == 6 and all(alive(pid) for pid in descendants)   # a descendant is never signalled
        assert not any(alive(int(x)) for x in sb.oppids.read_text().split())   # every direct child is gone
    finally:
        if sb.descpids.exists():
            for pid in sb.descpids.read_text().split():
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except OSError:
                    pass


def test_other_op_processes_are_never_ended(sb, tmp_path):
    """A look-alike `op` process (a renamed sleep) is a bystander: it must be alive after the run."""
    decoy_dir = tmp_path / "decoy"
    decoy_dir.mkdir()
    decoy = decoy_dir / "op"
    decoy.write_bytes(Path("/bin/sleep").read_bytes())
    decoy.chmod(0o755)
    other = subprocess.Popen([str(decoy), "60"])
    try:
        sb.set_plan(*["slow"] * 6)
        proc = sb.run()
        assert proc.returncode == 0
        assert other.poll() is None and alive(other.pid)
    finally:
        other.kill()
        other.wait()


# ---------------------------------------------------------------------------------------------------------
# 5. interruption: clean-up first, then the signal's exit code
@pytest.mark.parametrize("sig,code", [(signal.SIGINT, 130), (signal.SIGTERM, 143), (signal.SIGHUP, 129)])
def test_a_signal_in_condition_a_ends_the_child_and_removes_the_unused_folder(sb, sig, code):
    sb.set_plan("slow")
    process = sb.start()
    assert wait_until(lambda: sb.op_calls() >= 1 and sb.oppids.exists(), 15)
    time.sleep(0.15)
    os.kill(process.pid, sig)
    out, err = process.communicate(timeout=30)
    assert process.returncode == code, out + err
    result = sb.result()
    assert result["conclusion"] == "cancelled_incomplete" and result["exit_class"] == "cancelled"
    assert result["complete"] is False
    assert result["rounds"][-1]["status"] == "cancelled" and result["rounds"][-1]["reaped"] is True
    assert not any(alive(int(x)) for x in sb.oppids.read_text().split())
    assert sb.temp_dirs() == [] and result["leftover_check_required"] is False   # condition C never started


def test_a_signal_in_condition_c_keeps_the_folder_and_asks_for_a_check(sb):
    sb.set_plan("fast", "fast", "slow")
    process = sb.start()
    assert wait_until(lambda: sb.op_calls() >= 3, 15)
    time.sleep(0.15)
    os.kill(process.pid, signal.SIGTERM)
    out, err = process.communicate(timeout=30)
    assert process.returncode == 143, out + err
    result = sb.result()
    assert result["conclusion"] == "cancelled_incomplete" and result["leftover_check_required"] is True
    dirs = sb.temp_dirs()
    assert len(dirs) == 1 and stat.S_IMODE(dirs[0].stat().st_mode) == 0o700
    assert not any(alive(int(x)) for x in sb.oppids.read_text().split())


# ---------------------------------------------------------------------------------------------------------
# 6. the temp folder after a run: counts decide, and equal counts are not a proof (DA minor 1)
def test_a_growing_process_count_keeps_the_folder_and_asks_for_a_check(sb):
    sb.set_pgrep(grow=True)
    proc = sb.run()
    assert proc.returncode == 0
    result = sb.result()
    assert result["op_count_before"] == 2 and result["op_count_after"] == 3
    assert result["leftover_check_required"] is True
    dirs = sb.temp_dirs()
    assert len(dirs) == 1 and stat.S_IMODE(dirs[0].stat().st_mode) == 0o700
    assert "남은 것" in proc.stdout or "확인" in proc.stdout


def _count_case(monkeypatch, tmp_path, before, after, *, c_runs: bool = True, statuses=None):
    sb = CSandbox(tmp_path)
    compare = load_compare(monkeypatch, {"HOME": str(sb.home), "PROBE_BASE": str(sb.base),
                                         "PATH": f"{sb.shim}:{sb.bin}:/usr/bin:/bin"})
    counts = iter([before, after])
    monkeypatch.setattr(compare, "count_op", lambda: next(counts))
    calls = []

    def fake_attempt(argv, env, limit_s):
        calls.append(env)
        status = (statuses or ["success"] * 6)[len(calls) - 1] if len(calls) <= 6 else "success"
        return {"status": "success" if status == "success" else "timeout", "rc": 0 if status == "success" else None,
                "child_exited": status != "unconfirmed", "reaped": status not in ("unconfirmed",),
                "child_exit_unconfirmed": status == "unconfirmed",
                "descendants_may_hold_pipe": False, "stdout": b"2.32.1\n", "stderr": b""}
    monkeypatch.setattr(compare, "run_attempt", fake_attempt)
    code = compare.main(["--mode", "selftest"])
    return sb, code, sb.result()


@pytest.mark.parametrize("before,after,removed,leftover", [
    (2, 2, True, False),     # equal counts: the folder goes, but the screen never calls it proof of "no new daemon"
    (2, 3, False, True),     # grew
    (3, 2, False, True),     # shrank: the membership changed
    (None, 2, False, True),  # an unobserved count
    (2, None, False, True),
])
def test_folder_and_check_flag_follow_the_count_observation(monkeypatch, tmp_path, capsys, before, after, removed,
                                                            leftover):
    sb, code, result = _count_case(monkeypatch, tmp_path, before, after)
    assert code == 0
    assert (sb.temp_dirs() == []) is removed
    assert result["leftover_check_required"] is leftover
    assert result["op_count_before"] == before and result["op_count_after"] == after
    out = capsys.readouterr().out
    if removed:
        assert "증명" in out   # equal counts are only a count, said on screen


def test_an_unconfirmed_exit_keeps_the_folder_even_with_equal_counts_and_stops_the_rounds(monkeypatch, tmp_path):
    sb, code, result = _count_case(monkeypatch, tmp_path, 2, 2, statuses=["success", "success", "unconfirmed"])
    assert code == 1
    assert result["conclusion"] == "incomplete_exit_unconfirmed" and result["complete"] is False
    assert result["exit_class"] == "incomplete"
    assert [r["status"] for r in result["rounds"]][3:] == ["skipped_after_unconfirmed"] * 3
    assert result["rounds"][2]["child_exit_unconfirmed"] is True and result["rounds"][2]["reaped"] is False
    assert result["leftover_check_required"] is True and len(sb.temp_dirs()) == 1


def test_an_unused_folder_is_removed_even_when_the_counts_differ(monkeypatch, tmp_path):
    """Nothing ran in the folder (every round was skipped by the budget), so removing it loses nothing; the
    count mismatch still asks for a check of the processes."""
    sb = CSandbox(tmp_path)
    compare = load_compare(monkeypatch, {"HOME": str(sb.home), "PROBE_BASE": str(sb.base),
                                         "PATH": f"{sb.shim}:{sb.bin}:/usr/bin:/bin"})
    clock = FakeClock(monkeypatch, compare)
    counts = iter([2, 3])

    def slow_count():
        clock.t += 70.0   # the preparation alone uses the whole budget: no round can start
        return next(counts)
    monkeypatch.setattr(compare, "count_op", slow_count)
    monkeypatch.setattr(compare, "run_attempt", lambda *a, **k: pytest.fail("no attempt may start"))
    assert compare.main(["--mode", "selftest"]) == 1
    result = sb.result()
    assert [r["status"] for r in result["rounds"]] == ["skipped_budget"] * 6
    assert result["conclusion"] == "incomplete_missing_rounds" and result["leftover_check_required"] is True
    assert sb.temp_dirs() == []


# ---------------------------------------------------------------------------------------------------------
# 7. the clock: 75.0 s in all, a round only starts with 15.0 s left, never a shorter attempt
class FakeClock:
    def __init__(self, monkeypatch, compare):
        self.t = 1000.0
        monkeypatch.setattr(compare, "clock", lambda: self.t)


def _clock_case(monkeypatch, tmp_path, *, prep: float, round_s: float = 10.0, tail: float = 1.0, statuses=None):
    sb = CSandbox(tmp_path)
    compare = load_compare(monkeypatch, {"HOME": str(sb.home), "PROBE_BASE": str(sb.base),
                                         "PATH": f"{sb.shim}:{sb.bin}:/usr/bin:/bin"})
    clock = FakeClock(monkeypatch, compare)
    seen = []
    counts = iter([2, 2])
    steps = iter([prep, tail])

    def count():
        clock.t += next(steps)
        return next(counts)
    monkeypatch.setattr(compare, "count_op", count)

    def attempt(argv, env, limit_s):
        remaining = compare.TOTAL_S - (clock.t - begin)
        seen.append((remaining, limit_s))
        clock.t += round_s
        status = (statuses or {}).get(len(seen), "success")
        return {"status": "timeout" if status == "timeout" else "success", "rc": 0, "child_exited": True,
                "reaped": True, "child_exit_unconfirmed": False, "descendants_may_hold_pipe": False,
                "stdout": b"2.32.1\n", "stderr": b""}
    monkeypatch.setattr(compare, "run_attempt", attempt)
    begin = clock.t
    code = compare.main(["--mode", "selftest"])
    return sb, compare, code, sb.result(), seen, clock.t - begin


def test_production_numbers_are_the_design_numbers(monkeypatch):
    compare = load_compare(monkeypatch)
    assert compare.TOTAL_S == 75.0 and compare.RESERVE_S == 5.0 and compare.ATTEMPT_S == 7.0
    assert compare.probe.ATTEMPT_S == 7.0 and compare.probe.REAP_WAIT_S == 2.0 and compare.probe.PIPE_DRAIN_S == 1.0
    assert compare.START_NEED_S == 15.0


def test_a_slow_start_skips_the_last_round_and_no_attempt_runs_shorter_than_seven_seconds(monkeypatch, tmp_path):
    sb, compare, code, result, seen, total = _clock_case(monkeypatch, tmp_path, prep=11.0)
    assert code == 1
    assert [r["status"] for r in result["rounds"]] == ["success"] * 5 + ["skipped_budget"]
    assert result["conclusion"] == "incomplete_missing_rounds" and result["complete"] is False
    assert len(seen) == 5
    for remaining, limit in seen:
        assert limit == 7.0                       # never a shortened attempt that could pass for "slow"
        assert remaining >= 15.0                  # 7.0 attempt + 3.0 recovery + 5.0 reserve
    assert total <= 75.0


@pytest.mark.parametrize("prep", [0.0, 1.0, 3.0, 6.0, 9.0, 11.0, 12.0, 14.0, 20.0, 45.0, 60.0, 70.0])
def test_the_whole_run_never_exceeds_the_hard_limit(monkeypatch, tmp_path, prep):
    sb, compare, code, result, seen, total = _clock_case(monkeypatch, tmp_path, prep=prep)
    assert total <= 75.0, (prep, total)
    assert all(r >= 15.0 and limit == 7.0 for r, limit in seen)
    started = len(seen)
    assert [r["status"] for r in result["rounds"]].count("skipped_budget") == 6 - started


def test_a_prompt_run_uses_the_designed_worst_case_and_all_six_rounds(monkeypatch, tmp_path):
    sb, compare, code, result, seen, total = _clock_case(monkeypatch, tmp_path, prep=3.0)
    assert code == 0 and len(seen) == 6 and result["complete"] is True
    assert total <= 75.0   # 3 + 6 x 10 + 1 <= 68


# ---------------------------------------------------------------------------------------------------------
# 8. a confirmed timeout is an ordinary slow round (only an unconfirmed exit stops the run)
def test_confirmed_timeouts_are_slow_rounds_and_do_not_stop_the_run(monkeypatch, tmp_path):
    sb, compare, code, result, seen, total = _clock_case(monkeypatch, tmp_path, prep=0.0, round_s=10.0,
                                                          statuses={1: "timeout", 4: "timeout"})
    assert len(seen) == 6   # timeouts count as ordinary slow rounds when the exit was confirmed
    assert result["conditions"]["A"] == "slow"


# ---------------------------------------------------------------------------------------------------------
# 9. refusing to start
def test_production_mode_refuses_ambient_test_variables_before_doing_anything(sb):
    proc = sb.start(selftest=False, PROBE_BASE=str(sb.base))
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 2
    assert sb.op_calls() == 0 and not sb.base.exists()
    assert "PROBE_" in out + err


def test_a_relative_python_path_is_refused(sb):
    proc = sb.start(python="python3")
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 2 and sb.op_calls() == 0


def test_a_missing_op_is_refused_without_creating_anything(sb):
    (sb.bin / "op").unlink()
    proc = sb.run()
    assert proc.returncode == 2 and not sb.base.exists()   # refused before anything was created
    assert sb.op_calls() == 0


def test_a_symlinked_base_is_refused(sb, tmp_path):
    real = tmp_path / "real-base"
    real.mkdir()
    sb.base.symlink_to(real)
    proc = sb.run()
    assert proc.returncode == 2 and sb.op_calls() == 0 and list(real.iterdir()) == []


# ---------------------------------------------------------------------------------------------------------
# 10. scope: the existing files are untouched
def test_the_existing_probe_files_are_not_part_of_this_change():
    root = OPS.parents[2]
    out = subprocess.run(["git", "diff", "--name-only", "HEAD", "--",
                          "feature-pack/rag-consumer/ops/probe-opa/probe.py",
                          "feature-pack/rag-consumer/ops/probe-opa/probe.sh",
                          "feature-pack/rag-consumer/ops/probe-opa/s2.py",
                          "feature-pack/rag-consumer/ops/probe-opa/s2.sh",
                          "feature-pack/rag-consumer/tests/test_probe_opa.py",
                          "feature-pack/rag-consumer/tests/test_s2_opa.py"],
                         cwd=root, capture_output=True, text=True).stdout.split()
    assert out == []
