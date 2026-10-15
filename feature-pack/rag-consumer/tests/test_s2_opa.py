"""Synthetic scenarios of the S2 key-read timing measurement (design arch-20261015-opa-popup-design-r4 §6.1).

Everything is synthetic: a fake `op` that prints synthetic 64-hex "keys", a fake `launchctl`, a fake `pgrep`, a
synthetic token. No real op, no real launchd, no network, no operating file. The time constants are scaled
down by environment overrides that only `--selftest` accepts.
"""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time

import pytest

from test_probe_opa import Sandbox, alive, production_env, recorded_pids, wait_until

OPS = Path(__file__).resolve().parents[1] / "ops" / "probe-opa"
S2_SH = OPS / "s2.sh"
S2_PY = OPS / "s2.py"

KEYS = ["ab" * 32, "cd" * 32, "ef" * 32]
REFS = ["op://synthetic/consumer", "op://synthetic/projection", "op://synthetic/archive"]
TOKEN = "ops_synthetic_s2_service_token_77c1"
ROUNDS = 6


def load_s2():
    spec = importlib.util.spec_from_file_location("s2_opa", S2_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class S2Sandbox(Sandbox):
    def __init__(self, tmp_path: Path):
        super().__init__(tmp_path)
        self.token_file.write_text(TOKEN + "\n", encoding="utf-8")
        self.credentials = tmp_path / "credentials.json"
        self.pgrep_count = tmp_path / "pgrep-count"
        self.pgrep_count.write_text("2", encoding="utf-8")
        self.shim = tmp_path / "shim"
        self.shim.mkdir()
        self.set_pgrep()
        self.make_op()
        self.write_credentials()

    def set_pgrep(self, grow: bool = False) -> None:
        body = (
            f'#!/bin/sh\nn=$(cat "{self.pgrep_count}")\n'
            + (f'echo $((n+1)) > "{self.pgrep_count}"\n' if grow else "")
            + 'i=0; while [ $i -lt $n ]; do echo $((1000+i)); i=$((i+1)); done\n[ "$n" -gt 0 ]\n'
        )
        (self.shim / "pgrep").write_text(body, encoding="utf-8")
        (self.shim / "pgrep").chmod(0o755)

    def write_credentials(self, **override) -> None:
        document = {"token_file": str(self.token_file), "op": str(self.op),
                    "references": dict(zip(NAMES, REFS)), **override}
        self.credentials.write_text(json.dumps(document), encoding="utf-8")

    def make_op(self, *, pre: dict[int, str] | None = None, values: list[str] | None = None, rc: int = 0,
                stderr: str = "", disk: str = "constant") -> Path:
        """A fake `op read`: ``pre`` holds shell snippets per key index, run before the value is printed."""
        values = values or KEYS
        pre = pre or {}
        cases = "\n".join(f'  "{ref}") IDX={i}; VALUE="{values[i]}";;' for i, ref in enumerate(REFS))
        pre_cases = "\n".join(f"  {i}) {snippet};;" for i, snippet in pre.items())
        write = ('mkdir -p "$HOME/.config/op"; printf x >> "$HOME/.config/op/state"' if disk == "grow"
                 else 'mkdir -p "$HOME/.config/op"; echo state > "$HOME/.config/op/state"')
        body = (
            f'echo $$ >> "{self.oppids}"\n'
            f'echo "$2 TOK=${{OP_SERVICE_ACCOUNT_TOKEN:+yes}} HOME=$HOME CFG=${{OP_CONFIG_DIR:-none}}" >> "{self.opcalls}"\n'
            f'env | sed -e "s/=.*//" >> "{self.envnames}"\n'
            '[ "$1" = read ] || exit 2\n'
            'case "$2" in\n' + cases + "\n  *) exit 3;;\nesac\n"
            f'n=$(cat "{self.root}/cnt$IDX" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "{self.root}/cnt$IDX"\n'
            + write + "\n"
            + ('case "$IDX" in\n' + pre_cases + "\nesac\n" if pre else "")
            + (f'echo "{stderr}" >&2\n' if stderr else "")
            + f'echo "$VALUE"\nexit {rc}\n'
        )
        self.op = self.script("op", body)
        if hasattr(self, "credentials") and self.credentials.exists():
            self.write_credentials()
        return self.op

    def env(self, **extra: str) -> dict[str, str]:
        env = super().env(**extra)
        env["PATH"] = f"{self.shim}:{env['PATH']}"
        # Generous defaults: a run that must SUCCEED may not depend on how busy the machine is. A fake op is a few
        # forks and the clean-up asks `ps` once per recorded pid (37 of them) through a python start each; at machine
        # load 100 the old 2 s attempt / 6 s clean-up budget / 10 s start wait were used up by the machine, not by the
        # tool. The tests whose point IS a short limit (d e f p q) set their own scaled values below.
        env.update({"PROBE_S2_T_ATTEMPT": "8.0", "PROBE_S2_T_DEADLINE": "16.0", "PROBE_S2_T_GAP": "0.2",
                    "PROBE_T_RESULT": "600", "PROBE_T_CLEAN": "60", "PROBE_T_START": "10", "PROBE_T_REAP": "3",
                    "PROBE_T_PIPE": "1", "PROBE_T_CALL": "30"})
        env.update(self.extra)
        env.update(extra)
        return env

    def start(self, *args: str, **extra: str) -> subprocess.Popen:
        import signal
        return subprocess.Popen(
            ["/bin/bash", str(S2_SH), "--selftest", "--credentials", str(self.credentials), *args],
            env=self.env(**extra), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True, preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL),
        )

    def probe_dir(self) -> Path:
        dirs = [p for p in self.base.iterdir() if p.is_dir()]
        assert len(dirs) == 1, dirs
        return dirs[0]

    def run(self, *args: str, timeout: float = 240, **extra: str) -> subprocess.CompletedProcess:
        self.last = super().run(*args, timeout=timeout, **extra)
        return self.last

    def result(self) -> dict:
        """The result file; when it is missing say what the wrapper printed (a load-dependent refusal to start or a
        time-capped step must show its own message in the failure, not only a FileNotFoundError)."""
        path = self.probe_dir() / "result.json"
        if not path.exists():
            last = getattr(self, "last", None)
            pytest.fail(f"no result.json in {path.parent.name}: exit={getattr(last, 'returncode', '?')} "
                        f"stdout={getattr(last, 'stdout', '')!r} stderr={getattr(last, 'stderr', '')!r}")
        return json.loads(path.read_text(encoding="utf-8"))


NAMES = ("AIRAG_CONSUMER_KEY_HEX", "AIRAG_PROJECTION_KEY_HEX", "AIRAG_ARCHIVE_KEY_HEX")


@pytest.fixture
def sb(tmp_path):
    return S2Sandbox(tmp_path)


def cond(result: dict, name: str) -> dict:
    return next(c for c in result["conditions"] if c["name"] == name)


def calls_of(result: dict, name: str) -> list[dict]:
    return [call for rnd in cond(result, name)["rounds"] for call in rnd["calls"]]


def attempts_of(result: dict, name: str) -> list[dict]:
    return [a for call in calls_of(result, name) for a in call["attempts"]]


# ---------------------------------------------------------------------------------------------------------
# (a) a normal run: both conditions, 6 rounds x 3 keys, first-try success everywhere
def test_a_normal_run_measures_both_conditions_and_meets_the_criteria(sb):
    s2 = load_s2()
    proc = sb.run()
    result = sb.result()
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert s2.validate_result(result) and result["complete"] is True and result["mode"] == "selftest"
    assert [c["name"] for c in result["conditions"]] == ["default", "dedicated"]
    for name in ("default", "dedicated"):
        rounds = cond(result, name)["rounds"]
        assert [r["round"] for r in rounds] == list(range(ROUNDS))
        assert [r["kind"] for r in rounds] == ["cold"] + ["warm"] * 5
        for rnd in rounds:
            assert [c["key"] for c in rnd["calls"]] == [0, 1, 2] and rnd["keys_distinct"] is True
        attempts = attempts_of(result, name)
        assert len(attempts) == 18 and {a["status"] for a in attempts} == {"success"}
        assert {a["attempt"] for a in attempts} == {1} and {a["retried"] for a in attempts} == {False}
        assert {a["value_format_ok"] for a in attempts} == {True}
        crit = cond(result, name)["criteria"]
        assert crit["first_try_success_count"] == 18 and crit["all_first_try_success"] is True
        assert crit["no_retries"] is True and crit["retries_used"] == 0
        assert crit["attempts_within_limit"] is True and crit["calls_within_deadline"] is True
        assert crit["op_count_not_increased"] is True and crit["cold_over_limit"] is False
        assert crit["meets_all"] is True
    assert cond(result, "default")["criteria"]["disk_not_increased"] is None
    assert cond(result, "dedicated")["criteria"]["disk_not_increased"] is True
    assert result["comparison"] == "both_meet"
    assert sb.loaded() == []
    assert not any(alive(pid) for pid in recorded_pids(sb))


# (b) conditions and environments: the dedicated path is a fresh 0700 directory of this run, the token is only
# in the children, and an op child sees nothing but the allow-listed names
def test_b_default_uses_the_real_home_and_dedicated_a_fresh_private_home(sb):
    sb.run()
    lines = sb.opcalls.read_text().splitlines()
    assert len(lines) == 36
    default, dedicated = lines[:18], lines[18:]
    assert all(f"HOME={sb.home} " in line and "CFG=none" in line and "TOK=yes" in line for line in default)
    home = sb.probe_dir() / "op-home"
    assert all(f"HOME={home} " in line and f"CFG={home}/.config/op" in line and "TOK=yes" in line
               for line in dedicated)
    assert home.is_dir() and not home.is_symlink() and home.stat().st_mode & 0o777 == 0o700
    names = set(sb.envnames.read_text().split())
    assert names <= {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR",
                     "OP_SERVICE_ACCOUNT_TOKEN", "OP_CONFIG_DIR", "PWD", "SHLVL", "_", "OLDPWD"}
    assert not [n for n in names if n.startswith(("PROBE_", "FAKE_"))]


# (c) the three keys of a round are read in parallel
def test_c_the_three_reads_of_a_round_run_in_parallel(sb):
    sb.make_op(pre={0: "sleep 3", 1: "sleep 3", 2: "sleep 3"})
    sb.run()
    result = sb.result()
    for rnd in cond(result, "default")["rounds"]:
        assert all(a["elapsed_ms"] >= 2900 for c in rnd["calls"] for a in c["attempts"])
        assert rnd["ended_utc_ms"] - rnd["started_utc_ms"] < 8500  # sequential reads would take 9000+


# (d) a silent timeout is retried once and recorded as such
def test_d_a_silent_timeout_is_retried_once(sb):
    sb.make_op(pre={1: 'if [ "$n" -eq 1 ]; then exec sleep 30; fi'})
    sb.extra.update(PROBE_S2_T_ATTEMPT="3.0", PROBE_S2_T_DEADLINE="7.0")
    sb.run()
    result = sb.result()
    first = calls_of(result, "default")[1]
    assert [(a["attempt"], a["status"], a["retried"]) for a in first["attempts"]] == [
        (1, "timeout", False), (2, "success", True)]
    assert first["outcome"] == "success" and first["call_total_ms"] <= 7000 + 2000
    crit = cond(result, "default")["criteria"]
    assert crit["retries_used"] == 1 and crit["no_retries"] is False
    assert crit["first_try_success_count"] == 17 and crit["all_first_try_success"] is False
    assert crit["meets_all"] is False and cond(result, "dedicated")["criteria"]["meets_all"] is True
    assert result["comparison"] == "dedicated_only_meets"


# (e) a timeout after partial output is not retried
def test_e_a_timeout_after_partial_output_is_not_retried(sb):
    sb.make_op(pre={2: 'if [ "$n" -eq 1 ]; then printf x; exec sleep 30; fi'})
    sb.extra.update(PROBE_S2_T_ATTEMPT="4.0", PROBE_S2_T_DEADLINE="10.0")
    sb.run()
    call = calls_of(sb.result(), "default")[2]
    assert [(a["attempt"], a["status"]) for a in call["attempts"]] == [(1, "timeout")] and call["outcome"] == "timeout"


# (f) two timeouts: the second attempt is capped by what is left of the call deadline
def test_f_the_second_attempt_is_capped_by_the_remaining_call_deadline(sb):
    sb.make_op(pre={0: 'if [ "$n" -le 2 ]; then exec sleep 30; fi'})
    sb.extra.update(PROBE_S2_T_ATTEMPT="4.0", PROBE_S2_T_DEADLINE="5.0")
    sb.run()
    call = calls_of(sb.result(), "default")[0]
    assert [(a["attempt"], a["status"]) for a in call["attempts"]] == [(1, "timeout"), (2, "timeout")]
    assert call["outcome"] == "timeout"
    # about 1 s of the call deadline is left for the second attempt (an uncapped one would run the full 4 s)
    assert call["attempts"][1]["elapsed_ms"] <= 1000 + 1500, call["attempts"][1]
    assert call["call_total_ms"] <= 5000 + 1800   # uncapped: 4 s + 4 s = 8 s


# (g) error classes
@pytest.mark.parametrize("stderr,rc,status", [
    ("[ERROR] Unauthorized: invalid service account token", 1, "auth_error"),
    ("[ERROR] dial tcp: i/o timeout", 1, "network_error"),
    ("[ERROR] something else entirely", 1, "observation_unknown"),
])
def test_g_a_failed_read_is_classified_and_not_retried(sb, stderr, rc, status):
    sb.make_op(rc=rc, stderr=stderr, values=["", "", ""])
    sb.run()
    result = sb.result()
    attempts = attempts_of(result, "default")
    assert {a["status"] for a in attempts} == {status} and {a["attempt"] for a in attempts} == {1}
    assert cond(result, "default")["criteria"]["meets_all"] is False


# (h) the answer is only checked for the 64-hex shape; identical values are noticed
def test_h_a_badly_shaped_answer_is_unsupported_and_same_values_are_flagged(sb):
    sb.make_op(values=["short", KEYS[1], KEYS[2]])
    sb.run()
    result = sb.result()
    a = attempts_of(result, "default")
    assert [x["status"] for x in a[:3]] == ["unsupported", "success", "success"]
    assert [x["value_format_ok"] for x in a[:3]] == [False, True, True]
    assert all(x["attempt"] == 1 for x in a)


def test_h_identical_values_are_reported_as_not_distinct(sb):
    sb.make_op(values=[KEYS[0]] * 3)
    sb.run()
    assert [r["keys_distinct"] for r in cond(sb.result(), "default")["rounds"]] == [False] * ROUNDS


# (i) warm rounds start at least the gap after the previous round ended; round 0 is the cold one
def test_i_warm_rounds_are_spaced_by_the_gap(sb):
    sb.extra["PROBE_S2_T_GAP"] = "0.6"
    sb.run()
    for name in ("default", "dedicated"):
        rounds = cond(sb.result(), name)["rounds"]
        for before, after in zip(rounds, rounds[1:]):
            assert after["started_utc_ms"] - before["ended_utc_ms"] >= 600 - 30, (name, before["round"])


# (j) the dedicated path policy
def test_j_the_dedicated_path_policy(tmp_path):
    s2 = load_s2()
    good = tmp_path / "good"
    assert s2.dedicated_dir(good) == str(good.resolve()) and good.stat().st_mode & 0o777 == 0o700
    assert s2.dedicated_dir(good) == str(good.resolve())  # an existing, correct directory is fine
    loose = tmp_path / "loose"
    loose.mkdir(mode=0o755)
    os.chmod(loose, 0o755)
    assert s2.dedicated_dir(loose) is None
    real = tmp_path / "real"
    real.mkdir(mode=0o700)
    link = tmp_path / "link"
    link.symlink_to(real)
    assert s2.dedicated_dir(link) is None
    plain = tmp_path / "plainfile"
    plain.write_text("x")
    assert s2.dedicated_dir(plain) is None


# (k) an interrupt in the middle of the measurement cleans up
def test_k_sigint_during_the_run_cleans_up_and_exits_130(sb):
    import signal
    sb.make_op(pre={0: "sleep 2", 1: "sleep 2", 2: "sleep 2"})
    sb.extra.update(PROBE_S2_T_ATTEMPT="6.0", PROBE_S2_T_DEADLINE="12.0")
    process = sb.start()
    assert wait_until(lambda: sb.oppids.exists() and recorded_pids(sb), 90)
    time.sleep(0.3)
    os.kill(process.pid, signal.SIGINT)
    out, err = process.communicate(timeout=120)
    assert process.returncode == 130, out + err
    assert sb.loaded() == []
    assert wait_until(lambda: not any(alive(pid) for pid in recorded_pids(sb)), 30)


# (l) nothing of the values, the token or the references is written anywhere
def test_l_no_key_token_or_reference_reaches_results_or_streams(sb):
    sb.make_op(stderr=f"leak {TOKEN} {KEYS[0]} op://synthetic/consumer SYNTH_ERR_BODY_5519", rc=0)
    proc = sb.run()
    text = "\n".join([proc.stdout, proc.stderr] + [
        p.read_text(encoding="utf-8", errors="replace") for p in sb.base.rglob("*") if p.is_file()])
    for secret in (TOKEN, "SYNTH_ERR_BODY_5519", "op://", "OP_SERVICE_ACCOUNT_TOKEN", *KEYS):
        assert secret not in text, secret
    assert "Traceback" not in text


# (m) the closed result schema
def test_m_the_validator_is_closed(sb):
    s2 = load_s2()
    sb.run()
    good = sb.result()
    assert s2.validate_result(good)
    import copy
    for mutate in (
        lambda d: d.update(extra=1),
        lambda d: d.update(comparison="great"),
        lambda d: d["conditions"][0].update(name="third"),
        lambda d: d["conditions"][0]["rounds"][0]["calls"][0]["attempts"][0].update(status="skipped"),
        lambda d: d["conditions"][0]["rounds"][0]["calls"][0]["attempts"][0].update(stdout="body"),
        lambda d: d["conditions"][0]["rounds"][0].update(kind="hot"),
        lambda d: d.pop("complete"),
        lambda d: d.update(mode="normal"),
    ):
        broken = copy.deepcopy(good)
        mutate(broken)
        assert not s2.validate_result(broken)


def test_m_a_missing_or_partial_result_reads_as_incomplete(tmp_path):
    s2 = load_s2()
    assert s2.read_result(tmp_path)["comparison"] == "incomplete"
    (tmp_path / "result.json").write_text("{not json")
    assert s2.read_result(tmp_path)["comparison"] == "incomplete"
    report = subprocess.run([sys.executable, str(S2_PY), "--report", str(tmp_path)], capture_output=True, text=True)
    assert report.returncode != 0 and "incomplete" in report.stdout


# (n) the three counters: op processes after each round, dedicated disk bytes
def test_n_a_growing_op_process_count_fails_the_criterion(sb):
    sb.set_pgrep(grow=True)
    sb.run()
    crit = cond(sb.result(), "default")["criteria"]
    assert crit["op_count_not_increased"] is False and crit["meets_all"] is False


def test_n_growing_dedicated_disk_fails_only_the_dedicated_criterion(sb):
    sb.make_op(disk="grow")
    sb.run()
    result = sb.result()
    assert cond(result, "dedicated")["criteria"]["disk_not_increased"] is False
    assert cond(result, "dedicated")["criteria"]["meets_all"] is False
    assert cond(result, "default")["criteria"]["meets_all"] is True
    assert result["comparison"] == "default_only_meets"
    sizes = [r["dedicated_bytes"] for r in cond(result, "dedicated")["rounds"]]
    assert all(isinstance(x, int) for x in sizes) and sizes == sorted(sizes) and sizes[-1] > sizes[0]


# (o) production rules
def test_o_production_refuses_ambient_test_switches_and_needs_checked_arguments(sb):
    env = production_env(sb, {"PROBE_SELFTEST": "1", "PROBE_OP_BIN": str(sb.op)})
    proc = subprocess.run(["/bin/bash", str(S2_SH), "--python", sys.executable, "--credentials", str(sb.credentials)],
                          env=env, capture_output=True, text=True, timeout=60)
    directory = next(p for p in (sb.home / ".local" / "share" / "airag-probe").iterdir() if p.is_dir())
    result = json.loads((directory / "result.json").read_text())
    assert result["mode"] == "production" and result["aborted_class"] == "AmbientOverrideRefused"
    assert result["conditions"] == [] and not sb.opcalls.exists() and proc.returncode != 0
    plist = (directory / "job.plist").read_text()
    assert "<string>-I</string>" in plist and "<string>production</string>" in plist and "PROBE_" not in plist


def test_o_production_needs_a_checked_python_and_credentials_file(sb):
    env = production_env(sb, {})
    for args in ([], ["--python", sys.executable], ["--credentials", str(sb.credentials)],
                 ["--python", "python3", "--credentials", str(sb.credentials)],
                 ["--python", sys.executable, "--credentials", str(sb.root / "missing.json")],
                 ["--python", sys.executable, "--credentials", "relative.json"]):
        proc = subprocess.run(["/bin/bash", str(S2_SH), *args], env=env, capture_output=True, text=True, timeout=30)
        assert proc.returncode == 2, (args, proc.stdout)
    assert sb.lc_calls() == [] and not (sb.home / ".local" / "share" / "airag-probe").exists()


def test_o_a_bad_credentials_file_aborts_with_a_fixed_class_and_runs_nothing(sb):
    sb.credentials.write_text('{"token_file": 1, "references": "no"}', encoding="utf-8")
    proc = sb.run()
    result = sb.result()
    assert result["aborted_class"] == "CredentialSettingsInvalid" and result["conditions"] == []
    assert not sb.opcalls.exists() and "references" not in proc.stdout


# (p) the report: the three levels of daily calls, and the rule-exception line when a cold read is over the limit
def test_p_the_report_names_the_three_call_levels_and_the_exception_decision(sb):
    sb.make_op(pre={0: 'if [ "$n" -eq 1 ]; then exec sleep 30; fi'})
    sb.extra.update(PROBE_S2_T_ATTEMPT="3.0", PROBE_S2_T_DEADLINE="7.0")
    proc = sb.run()
    out = proc.stdout
    assert "864" in out and "1,728" in out and "미확인" in out
    assert "규칙 예외" in out and "오빠" in out
    assert "비교" in out and "dedicated_only_meets" in out
    assert cond(sb.result(), "default")["criteria"]["cold_over_limit"] is True


# (q) the budgets of the shell wrapper
def test_q_a_run_that_runs_out_of_time_is_closed_as_incomplete(sb):
    sb.make_op(pre={0: "sleep 30", 1: "sleep 30", 2: "sleep 30"})
    sb.extra.update(PROBE_S2_T_ATTEMPT="20", PROBE_S2_T_DEADLINE="40", PROBE_T_RESULT="5", PROBE_T_CLEAN="8")
    started = time.monotonic()
    proc = sb.run()
    assert time.monotonic() - started < 5 + 8 + 12   # a hang on the 30 s fake op would be >= 30
    result = sb.result()
    assert result["complete"] is True and result["timed_out_wait"] is True and result["comparison"] == "incomplete"
    assert proc.returncode != 0 and sb.loaded() == []
    assert wait_until(lambda: not any(alive(pid) for pid in recorded_pids(sb)), 30)


def test_q_a_hanging_bootstrap_is_cut_off(sb):
    started = time.monotonic()
    proc = sb.run(FAKE_LC_BOOTSTRAP_SLEEP="14", PROBE_T_CALL="2")
    assert proc.returncode == 3 and time.monotonic() - started < 9 + 8   # the fake bootstrap sleeps 14 s
    assert not sb.opcalls.exists()


def test_q_a_foreign_job_under_the_label_is_never_booted_out(sb):
    proc = sb.run(FAKE_LC_FOREIGN="1")
    assert proc.returncode == 2
    assert not any(c.startswith(("bootstrap", "bootout")) for c in sb.lc_calls())


def test_q_a_look_alike_job_after_our_bootstrap_is_never_booted_out(sb):
    proc = sb.run(FAKE_LC_STYLE="extra_arg")
    assert any(c.startswith("bootstrap") for c in sb.lc_calls())
    assert not any(c.startswith("bootout") for c in sb.lc_calls())
    assert proc.returncode == 4


# ---------------------------------------------------------------------------------------------------------
# pure functions
def test_evaluate_and_distribution_pure_cases():
    s2 = load_s2()
    attempt = {"attempt": 1, "status": "success", "elapsed_ms": 100, "retried": False, "value_format_ok": True,
               "child_exited": True, "reaped": True, "child_exit_unconfirmed": False,
               "descendants_may_hold_pipe": False}

    def rnd(i, ms, bytes_, count=2):
        calls = [{"key": k, "attempts": [{**attempt, "elapsed_ms": ms}], "call_total_ms": ms, "outcome": "success"}
                 for k in range(3)]
        return {"round": i, "kind": "cold" if i == 0 else "warm", "started_utc_ms": i, "ended_utc_ms": i,
                "keys_distinct": True, "op_count_after": count, "dedicated_bytes": bytes_, "calls": calls}

    rounds = [rnd(i, 100 + i, 50) for i in range(6)]
    crit = s2.evaluate({"name": "dedicated", "baseline_op_count": 2, "rounds": rounds})
    assert crit["meets_all"] is True and crit["cold_ms"] == {"min": 100, "median": 100, "max": 100}
    assert crit["warm_ms"] == {"min": 101, "median": 103, "max": 105}
    over = [rnd(0, 9000, 50)] + rounds[1:]
    assert s2.evaluate({"name": "default", "baseline_op_count": 2, "rounds": over})["attempts_within_limit"] is False
    unknown = [{**r, "op_count_after": None} for r in rounds]
    assert s2.evaluate({"name": "default", "baseline_op_count": 2, "rounds": unknown})["op_count_not_increased"] is False
    grown = [rnd(0, 100, 50)] + [rnd(i, 100, 51) for i in range(1, 6)]
    assert s2.evaluate({"name": "dedicated", "baseline_op_count": 2, "rounds": grown})["disk_not_increased"] is False
    assert s2.compare([{"name": "default", "criteria": {"meets_all": True}},
                       {"name": "dedicated", "criteria": {"meets_all": False}}], True) == "default_only_meets"
    assert s2.compare([], False) == "incomplete"


# ---------------------------------------------------------------------------------------------------------
# one attempt: probe.py stays untouched (it is the file a human is about to run), so s2.py carries its own thin
# attempt runner built from probe's reviewed parts (_Deadline, _end_child, PidBook)
def test_s2_run_attempt_takes_a_per_call_limit_and_ends_its_child(tmp_path):
    s2 = load_s2()
    book, budget = s2.LockedPidBook(tmp_path), s2.probe.Budget(5)
    started = time.monotonic()
    info = s2.run_attempt("K0", ["/bin/sleep", "30"], {"PATH": "/bin"}, book, budget, 0.3)
    assert info["status"] == "timeout" and time.monotonic() - started < 10
    assert info["reaped"] is True and wait_until(lambda: not alive(info["child_pid"]), 0.5)


def test_s2_run_attempt_tells_whether_anything_was_printed_before_the_timeout(tmp_path):
    s2 = load_s2()
    book, budget = s2.LockedPidBook(tmp_path), s2.probe.Budget(5)
    silent = s2.run_attempt("K0", ["/bin/sleep", "30"], {"PATH": "/bin"}, book, budget, 0.3)
    loud = s2.run_attempt("K1", ["/bin/sh", "-c", "printf x; exec sleep 30"], {"PATH": "/bin"}, book, budget, 1.5)
    quiet_err = s2.run_attempt("K2", ["/bin/sh", "-c", "printf x >&2; exec sleep 30"], {"PATH": "/bin"}, book,
                               budget, 1.5)
    assert silent["status"] == loud["status"] == quiet_err["status"] == "timeout"
    assert silent["partial_output"] is False and loud["partial_output"] is True and quiet_err["partial_output"] is True
    for info in (silent, loud, quiet_err):
        assert info["stdout"] == b"" and info["stderr"] == b""  # only the bool survives


def test_s2_run_attempt_success_and_failure_shapes(tmp_path):
    s2 = load_s2()
    book, budget = s2.LockedPidBook(tmp_path), s2.probe.Budget(5)
    ok = s2.run_attempt("K0", ["/bin/echo", "hello"], {"PATH": "/bin"}, book, budget, 2.0)
    assert ok["status"] == "success" and ok["rc"] == 0 and ok["stdout"].strip() == b"hello" and ok["reaped"] is True
    bad = s2.run_attempt("K1", ["/nonexistent/op"], {"PATH": "/bin"}, book, budget, 2.0)
    assert bad["status"] == "spawn_error" and bad["child_pid"] is None


def test_s2_run_attempt_ends_the_child_when_the_record_fails(tmp_path, monkeypatch):
    s2 = load_s2()
    book, budget = s2.LockedPidBook(tmp_path), s2.probe.Budget(5)
    monkeypatch.setattr(book, "after", lambda step, pid: (_ for _ in ()).throw(OSError("disk")))
    info = s2.run_attempt("K0", ["/bin/sleep", "30"], {"PATH": "/bin"}, book, budget, 0.3)
    assert info["status"] == "observation_unknown" and info["reaped"] is True
    assert wait_until(lambda: not alive(info["child_pid"]), 0.5)


def test_s2_locked_pid_book_survives_concurrent_records(tmp_path):
    s2 = load_s2()
    book = s2.LockedPidBook(tmp_path)
    threads = [threading.Thread(target=lambda i=i: [book.before(f"K{i}") or book.after(f"K{i}", 4000 + i * 10 + j)
                                                    for j in range(20)]) for i in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    document = json.loads((tmp_path / "pids.json").read_text())
    assert len(document["children"]) == 60 and {c["pid"] for c in document["children"]} == {
        4000 + i * 10 + j for i in range(3) for j in range(20)}
