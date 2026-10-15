"""Synthetic --selftest scenarios (a)-(m) of the 1Password popup probe (design arch-20261015-opa-popup-design-r4 §4).

Everything here is synthetic: a fake `op`, a fake `launchctl`, a fake `log`, a synthetic token. No real op,
no real launchd, no network, no operating file. The probe's time constants are scaled down by environment
overrides that only `--selftest` accepts.
"""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

import pytest

OPS = Path(__file__).resolve().parents[1] / "ops" / "probe-opa"
PROBE_SH = OPS / "probe.sh"
PROBE_PY = OPS / "probe.py"
FAKE_LAUNCHCTL = Path(__file__).with_name("_probe_fake_launchctl.py")

TOKEN = "ops_synthetic_service_token_4f1d9c2b"
TOKEN_LIKE = "ops_eyJsaWtlLWEtdG9rZW4ifQ_synthetic_lookalike"
STDOUT_MARK = "SYNTH_STDOUT_BODY_7731"
STDERR_MARK = "SYNTH_STDERR_BODY_5519"
NINE = ("success", "auth_error", "network_error", "timeout", "spawn_error", "unsupported",
        "observation_unknown", "skipped_prior_unresolved", "skipped_not_applicable")
STEP_ORDER = ["P4", "P0", "P2", "P1", "P1b"]


def load_probe():
    spec = importlib.util.spec_from_file_location("probe_opa", PROBE_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Sandbox:
    def __init__(self, tmp_path: Path):
        self.root = tmp_path
        self.home = tmp_path / "home"
        self.bin = tmp_path / "bin"
        self.state = tmp_path / "lc-state"
        self.base = tmp_path / "probe-base"
        for path in (self.home, self.bin, self.state):
            path.mkdir()
        self.token_file = tmp_path / "token"
        self.token_file.write_text(TOKEN + "\n", encoding="utf-8")
        self.oppids = tmp_path / "op-pids.txt"
        self.opcalls = tmp_path / "op-calls.txt"
        self.marker = tmp_path / "descendant-done"
        self.seq = tmp_path / "tcc-seq.txt"
        self.launchctl = self.bin / "launchctl"
        self.launchctl.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{FAKE_LAUNCHCTL}" "$@"\n', encoding="utf-8")
        self.launchctl.chmod(0o755)
        self.op = self.make_op()
        self.logbin = self.make_log()
        self.set_tcc("other")
        self.extra: dict[str, str] = {}

    def script(self, name: str, body: str) -> Path:
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body, encoding="utf-8")
        path.chmod(0o755)
        return path

    def make_op(self, *, version="2.31.0", acct='{"type":"SERVICE_ACCOUNT","id":"synthetic"}', version_rc=0,
                acct_rc=0, version_pre="", acct_pre="", acct_stderr="") -> Path:
        stderr = f'echo "{acct_stderr}" >&2' if acct_stderr else ""
        body = (
            f'echo $$ >> "{self.oppids}"\n'
            f'echo "$1 TOK=${{OP_SERVICE_ACCOUNT_TOKEN:+yes}} HOME=$HOME CFG=${{OP_CONFIG_DIR:-none}}" >> "{self.opcalls}"\n'
            'case "$1" in\n'
            f'  --version)\n    {version_pre}\n    echo "{version}"; exit {version_rc};;\n'
            f'  user)\n    {acct_pre}\n    {stderr}\n    echo \'{acct}\'; exit {acct_rc};;\n'
            'esac\nexit 2\n'
        )
        return self.script("op", body)

    def make_log(self) -> Path:
        body = (
            f'count_file="{self.root}/log-count"\n'
            'n=$(cat "$count_file" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$count_file"\n'
            f'mode=$(sed -n "${{n}}p" "{self.seq}"); [ -n "$mode" ] || mode=$(tail -n 1 "{self.seq}")\n'
            'echo "Timestamp               Ty Process[PID:TID]"\n'
            'case "$mode" in\n'
            '  empty) ;;\n'
            '  other) echo "2026-10-15 17:00:01.000000+0900 Df tccd[311:2a] [com.apple.TCC:access] unrelated request kTCCServiceCamera";;\n'
            f'  attributed) echo "2026-10-15 17:00:01.000000+0900 Df tccd[311:2a] [com.apple.TCC:access] kTCCServiceSystemPolicyAppData 1password.group pid=$(tail -n 1 "{self.oppids}")";;\n'
            '  unattributed) echo "2026-10-15 17:00:01.000000+0900 Df tccd[311:2a] [com.apple.TCC:access] kTCCServiceSystemPolicyAppData 1password.group pid=1";;\n'
            '  fail) exit 1;;\n'
            'esac\n'
        )
        return self.script("log", body)

    def set_tcc(self, *modes: str) -> None:
        self.seq.write_text("\n".join(modes) + "\n", encoding="utf-8")

    def env(self, **extra: str) -> dict[str, str]:
        env = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.home), "TMPDIR": str(self.root),
            "PROBE_BASE": str(self.base), "PROBE_OP_BIN": str(self.op), "PROBE_TOKEN_FILE": str(self.token_file),
            "PROBE_LAUNCHCTL": str(self.launchctl), "PROBE_LOG_BIN": str(self.logbin), "PROBE_PYTHON": sys.executable,
            "PROBE_P4_STUB": "success",
            "PROBE_T_ATTEMPT": "1.5", "PROBE_T_REAP": "0.5", "PROBE_T_PIPE": "0.3", "PROBE_T_LOCAL": "8",
            "PROBE_T_START": "4", "PROBE_T_RESULT": "14", "PROBE_T_CLEAN": "6",
            "FAKE_LC_STATE": str(self.state),
        }
        env.update(self.extra)
        env.update(extra)
        return env

    def start(self, *args: str, **extra: str) -> subprocess.Popen:
        return subprocess.Popen(
            ["/bin/bash", str(PROBE_SH), "--selftest", *args], env=self.env(**extra), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True,
            preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL),
        )

    def run(self, *args: str, timeout: float = 90, **extra: str) -> subprocess.CompletedProcess:
        process = self.start(*args, **extra)
        out, err = process.communicate(timeout=timeout)
        return subprocess.CompletedProcess(process.args, process.returncode, out, err)

    def probe_dir(self) -> Path:
        dirs = [p for p in self.base.iterdir() if p.is_dir()]
        assert len(dirs) == 1, dirs
        return dirs[0]

    def result(self) -> dict:
        return json.loads((self.probe_dir() / "result.json").read_text(encoding="utf-8"))

    def loaded(self) -> list[str]:
        return [p.name for p in self.state.glob("com.airag.probe-opa-*.json")]

    def lc_calls(self) -> list[str]:
        path = self.state / "calls.txt"
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []

    def tree_text(self, proc: subprocess.CompletedProcess) -> str:
        parts = [proc.stdout, proc.stderr]
        for path in self.base.rglob("*"):
            if path.is_file():
                parts.append(path.read_text(encoding="utf-8", errors="replace"))
        return "\n".join(parts)


@pytest.fixture
def sb(tmp_path):
    return Sandbox(tmp_path)


def steps_of(result: dict) -> dict[str, dict]:
    return {step["step"]: step for step in result["steps"]}


def statuses(result: dict) -> dict[str, str]:
    return {name: step["status"] for name, step in steps_of(result).items()}


def alive(pid: int) -> bool:
    out = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return bool(out) and not out.startswith("Z")


def recorded_pids(sb: Sandbox) -> list[int]:
    return [int(line) for line in sb.oppids.read_text().split()] if sb.oppids.exists() else []


def wait_until(predicate, seconds: float) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.1)
    return predicate()


# ---------------------------------------------------------------------------------------------------------
# (a) normal run
def test_a_normal_run_succeeds_everywhere_and_cleans_up(sb):
    probe = load_probe()
    proc = sb.run()
    result = sb.result()
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert probe.validate_result(result) and result["complete"] is True
    assert list(steps_of(result)) == STEP_ORDER
    assert set(statuses(result).values()) == {"success"}
    tcc = {name: step["tcc_observation"] for name, step in steps_of(result).items()}
    assert tcc == {"P4": None, "P0": "none_logged_ok", "P2": "none_logged_ok", "P1": "none_logged_ok",
                   "P1b": "none_logged_ok"}
    assert result["conclusion"] == "no_repro_twice" and result["tcc_unknown"] is False
    assert [steps_of(result)[n]["account_type_confirmed"] for n in ("P0", "P2", "P1", "P1b")] == [None, True, True, True]
    assert result["s0"]["consumer_disabled"] == "true" and result["s0"]["consumer_loaded"] == "false"
    assert sb.loaded() == []
    calls = [line for line in sb.lc_calls() if line.startswith(("bootstrap", "bootout"))]
    assert [c.split()[0] for c in calls] == ["bootstrap", "bootout"]
    # token boundary: P0 has none; P2 gets the dedicated HOME + OP_CONFIG_DIR; P1/P1b get the real HOME only
    lines = sb.opcalls.read_text().splitlines()
    assert len(lines) == 4
    assert lines[0].startswith("--version TOK= ") and "CFG=none" in lines[0]
    assert "TOK=yes" in lines[1] and "/.local/share/airag/op-home" in lines[1] and "/.config/op" in lines[1]
    for line in lines[2:]:
        assert "TOK=yes" in line and "CFG=none" in line and "op-home" not in line
    plist = (sb.probe_dir() / "job.plist").read_text(encoding="utf-8")
    assert "com.airag.probe-opa-" in plist and "RunAtLoad" in plist and "/dev/null" in plist
    assert "KeepAlive" not in plist and "StartInterval" not in plist and TOKEN not in plist
    assert TOKEN not in sb.tree_text(proc)


# (b) timeout
def test_b_a_hanging_account_call_times_out_and_stops_the_chain(sb):
    sb.op = sb.make_op(acct_pre="sleep 10")
    sb.extra["PROBE_OP_BIN"] = str(sb.op)
    proc = sb.run()
    result = sb.result()
    assert proc.returncode == 0, proc.stdout + proc.stderr
    got = statuses(result)
    assert got == {"P4": "success", "P0": "success", "P2": "timeout",
                   "P1": "skipped_prior_unresolved", "P1b": "skipped_prior_unresolved"}
    assert result["conclusion"] == "dedicated_path_also_blocked"
    assert sb.loaded() == []
    assert not any(alive(pid) for pid in recorded_pids(sb))


# (c) SIGINT during the run
def test_c_sigint_during_the_run_cleans_up_and_exits_130(sb):
    sb.op = sb.make_op(version_pre="sleep 10")
    sb.extra.update(PROBE_OP_BIN=str(sb.op), PROBE_T_ATTEMPT="8")
    process = sb.start()
    assert wait_until(lambda: sb.oppids.exists() and recorded_pids(sb), 15)
    time.sleep(0.3)
    os.kill(process.pid, signal.SIGINT)
    out, err = process.communicate(timeout=60)
    assert process.returncode == 130, out + err
    assert sb.loaded() == []
    assert wait_until(lambda: not any(alive(pid) for pid in recorded_pids(sb)), 5)


# (d) bootout fails
def test_d_a_failed_bootout_is_reported_once_and_not_retried(sb):
    proc = sb.run(FAKE_LC_BOOTOUT_FAIL="1")
    assert proc.returncode != 0
    assert "잔존 확인 필요: com.airag.probe-opa-" in proc.stdout
    assert len([c for c in sb.lc_calls() if c.startswith("bootout")]) == 1
    assert len(sb.loaded()) == 1  # still loaded: the user is told, the script does not keep trying


# (e) nothing leaks
def test_e_synthetic_secrets_and_output_never_reach_results_or_streams(sb):
    sb.op = sb.make_op(
        acct_rc=1, acct_stderr=f"leak $OP_SERVICE_ACCOUNT_TOKEN {TOKEN_LIKE} {STDERR_MARK}",
        acct_pre=f'echo "{STDOUT_MARK} $OP_SERVICE_ACCOUNT_TOKEN"',
    )
    sb.extra["PROBE_OP_BIN"] = str(sb.op)
    proc = sb.run()
    assert proc.returncode == 0, proc.stdout + proc.stderr
    text = sb.tree_text(proc)
    for secret in (TOKEN, TOKEN_LIKE, STDOUT_MARK, STDERR_MARK, "OP_SERVICE_ACCOUNT_TOKEN"):
        assert secret not in text, secret
    assert statuses(sb.result())["P2"] == "observation_unknown"
    assert "Traceback" not in text


# (f) results that are absent or not complete
def test_f_a_partial_or_absent_result_reads_as_observation_unknown(sb, tmp_path):
    probe = load_probe()
    directory = tmp_path / "partial"
    directory.mkdir()
    assert probe.read_result(directory)["conclusion"] == "observation_unknown"
    (directory / "result.json").write_text(json.dumps({"schema_version": 1, "steps": [], "complete": False}))
    got = probe.read_result(directory)
    assert got["conclusion"] == "observation_unknown" and got["complete"] is False
    (directory / "result.json").write_text("{not json")
    assert probe.read_result(directory)["conclusion"] == "observation_unknown"
    report = subprocess.run([sys.executable, str(PROBE_PY), "--report", str(directory)], capture_output=True, text=True)
    assert report.returncode != 0 and "observation_unknown" in report.stdout


def test_f_a_wait_that_runs_out_closes_the_result_as_observation_unknown(sb):
    sb.op = sb.make_op(version_pre="sleep 20")
    sb.extra.update(PROBE_OP_BIN=str(sb.op), PROBE_T_ATTEMPT="15", PROBE_T_RESULT="4")
    proc = sb.run()
    result = sb.result()
    assert load_probe().validate_result(result)
    assert result["complete"] is True and result["timed_out_wait"] is True
    assert result["conclusion"] == "observation_unknown"
    assert proc.returncode != 0
    assert sb.loaded() == []
    assert wait_until(lambda: not any(alive(pid) for pid in recorded_pids(sb)), 5)


# (g) interrupted right after bootstrap, before any flag is recorded
def test_g_interrupt_right_after_bootstrap_is_found_by_the_label_itself(sb):
    proc = sb.run(FAKE_LC_BOOTSTRAP_SIGNAL="INT")
    assert proc.returncode == 130, proc.stdout + proc.stderr
    assert sb.loaded() == []
    assert any(c.startswith("bootout") for c in sb.lc_calls())


# (h) bootout fails and a directly created op is still running
def test_h_after_a_failed_bootout_recorded_pids_are_stopped_and_rechecked(sb):
    sb.op = sb.make_op(version_pre="sleep 30")
    sb.extra.update(PROBE_OP_BIN=str(sb.op), PROBE_T_ATTEMPT="25", PROBE_T_RESULT="4")
    proc = sb.run(FAKE_LC_BOOTOUT_FAIL="1")
    assert proc.returncode != 0
    assert "잔존 확인 필요: com.airag.probe-opa-" in proc.stdout
    assert "잔존 확인 필요: pid" not in proc.stdout  # the recorded processes did go away
    pids = json.loads((sb.probe_dir() / "pids.json").read_text())
    assert pids["children"] and not alive(pids["children"][0]["pid"]) and not alive(pids["self"]["pid"])


# (i) launchctl lookup errors are never read as "absent"
def test_i_an_unrelated_launchctl_error_is_unknown_check_required(sb):
    proc = sb.run(FAKE_LC_PRINT_ERROR_ALWAYS="1")
    assert proc.returncode != 0 and "unknown_check_required" in proc.stdout
    assert sb.opcalls.exists() is False  # nothing ran


def test_i_an_error_during_cleanup_stays_unknown_and_is_reported(sb):
    proc = sb.run(FAKE_LC_PRINT_ERROR_WHEN_LOADED="1", FAKE_LC_BOOTOUT_FAIL="1")
    assert proc.returncode != 0
    assert "unknown_check_required" in proc.stdout and "잔존 확인 필요: com.airag.probe-opa-" in proc.stdout


# (j) no launchctl at all
def test_j_a_missing_launchctl_is_unknown_check_required(sb):
    proc = sb.run(PROBE_LAUNCHCTL=str(sb.root / "no-such-launchctl"))
    assert proc.returncode != 0 and "unknown_check_required" in proc.stdout
    assert sb.opcalls.exists() is False


# (k) the direct child is gone but a descendant keeps the pipes open
def test_k_a_descendant_holding_the_pipe_never_extends_the_wait(sb):
    sb.op = sb.make_op(version_pre=(
        f'echo {STDOUT_MARK}; echo {STDERR_MARK} >&2\n'
        f'    ( sleep 3; echo done > "{sb.marker}" ) &\n    sleep 6'))
    sb.extra.update(PROBE_OP_BIN=str(sb.op), PROBE_T_ATTEMPT="1.0", PROBE_T_REAP="0.5", PROBE_T_PIPE="0.3")
    started = time.monotonic()
    proc = sb.run()
    elapsed = time.monotonic() - started
    result = sb.result()
    p0 = steps_of(result)["P0"]
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert p0["status"] == "timeout"
    assert 1.0 <= p0["elapsed_ms"] / 1000 <= 1.0 + 0.5 + 0.3 + 1.0  # attempt + reap wait + pipe drain + slack
    assert p0["child_exited"] is True and p0["reaped"] is True and p0["child_exit_unconfirmed"] is False
    assert p0["descendants_may_hold_pipe"] is True
    assert elapsed < 4 + 14 + 6  # the scaled stand-in for the 75 second hard cap
    assert steps_of(result)["P2"]["status"] == "skipped_prior_unresolved"
    assert wait_until(sb.marker.exists, 8), "the descendant must be left alone and finish by itself"
    text = sb.tree_text(proc)
    assert STDOUT_MARK not in text and STDERR_MARK not in text


# (l) the P1b condition
@pytest.mark.parametrize("modes,runs_p1b", [
    (("empty", "other", "other"), False),   # the pinned counterexample: P0 tcc unknown
    (("other", "empty", "other"), False),
    (("other", "other", "empty"), False),
    (("other", "other", "other", "other"), True),
])
def test_l_p1b_runs_only_when_all_three_stages_are_success_and_none_logged_ok(sb, modes, runs_p1b):
    sb.set_tcc(*modes)
    proc = sb.run()
    result = sb.result()
    assert proc.returncode == 0, proc.stdout + proc.stderr
    p1b = steps_of(result)["P1b"]
    if runs_p1b:
        assert p1b["status"] == "success" and result["conclusion"] == "no_repro_twice"
        assert result["tcc_unknown"] is False
    else:
        assert p1b["status"] == "skipped_not_applicable"
        assert result["conclusion"] == "no_repro_tcc_unobservable"  # 재현 없음 + 팝업 관측 불가 → 변경 보류
        assert result["tcc_unknown"] is True
        assert len(sb.opcalls.read_text().splitlines()) == 3


def test_l_a_late_repeat_that_stops_is_an_intermittent_repro(sb):
    sb.op = sb.make_op(acct_pre=f'[ "$(wc -l < "{sb.opcalls}")" -ge 4 ] && sleep 10')
    sb.extra["PROBE_OP_BIN"] = str(sb.op)
    proc = sb.run()
    result = sb.result()
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert statuses(result)["P1b"] == "timeout" and result["conclusion"] == "intermittent_repro"


# (m) the nine statuses
def test_m_the_validator_accepts_exactly_the_nine_statuses(sb):
    probe = load_probe()
    assert tuple(probe.STATUSES) == NINE
    base = {
        "step": "P1b", "status": "success", "rc": 0, "elapsed_ms": 5, "started_utc_ms": 1, "ended_utc_ms": 6,
        "child_pid": 12, "child_exited": True, "reaped": True, "child_exit_unconfirmed": False,
        "descendants_may_hold_pipe": False, "account_type_confirmed": True, "tcc_observation": "none_logged_ok",
    }
    doc = {"schema_version": 1, "steps": [], "s0": {"consumer_disabled": "true", "consumer_loaded": "false",
                                                    "op_process_count": 0, "op_socket_mtime_utc_ms": None},
           "complete": True, "tcc_unknown": False, "conclusion": "no_repro_twice", "timed_out_wait": False,
           "aborted_class": None}
    for status in NINE:
        assert probe.validate_result({**doc, "steps": [{**base, "status": status}]}), status
    assert not probe.validate_result({**doc, "steps": [{**base, "status": "skipped"}]})
    assert not probe.validate_result({**doc, "steps": [{**base, "status": "Success"}]})
    assert not probe.validate_result({**doc, "steps": [{**base, "tcc_observation": "seen"}]})
    assert not probe.validate_result({**doc, "steps": [{**base, "stdout": "body"}]})  # no free-text fields
    assert not probe.validate_result({**doc, "conclusion": "all_good"})
    assert not probe.validate_result({**doc, "extra": 1})
    assert not probe.validate_result({k: v for k, v in doc.items() if k != "complete"})


# ---------------------------------------------------------------------------------------------------------
# other rows of the design's tables
def test_overrides_are_refused_outside_selftest(sb):
    env = sb.env()
    env.pop("PROBE_P4_STUB")
    proc = subprocess.run(["/bin/bash", str(PROBE_SH)], env=env, capture_output=True, text=True, timeout=30)
    assert proc.returncode == 2 and "--selftest" in proc.stdout + proc.stderr
    assert not sb.base.exists() and sb.lc_calls() == []


def test_a_token_that_is_rejected_stops_the_chain_as_auth_error(sb):
    sb.op = sb.make_op(acct_rc=1, acct_stderr="[ERROR] Unauthorized: invalid service account token")
    sb.extra["PROBE_OP_BIN"] = str(sb.op)
    proc = sb.run()
    result = sb.result()
    assert proc.returncode == 0
    assert statuses(result) == {"P4": "success", "P0": "success", "P2": "auth_error",
                                "P1": "skipped_not_applicable", "P1b": "skipped_not_applicable"}
    assert result["conclusion"] == "auth_error"


@pytest.mark.parametrize("acct", ['{"type":"USER"}', "not json", '["SERVICE_ACCOUNT"]'])
def test_an_account_answer_that_is_not_a_service_account_is_unsupported(sb, acct):
    sb.op = sb.make_op(acct=acct)
    sb.extra["PROBE_OP_BIN"] = str(sb.op)
    sb.run()
    p2 = steps_of(sb.result())["P2"]
    assert p2["status"] == "unsupported" and p2["account_type_confirmed"] is False


def test_the_version_check_needs_exit_zero_and_a_version_shaped_answer(sb):
    sb.op = sb.make_op(version="not-a-version")
    sb.extra["PROBE_OP_BIN"] = str(sb.op)
    sb.run()
    assert statuses(sb.result())["P0"] == "unsupported"


def test_a_version_check_that_fails_is_observation_unknown_and_conclusion_is_unconfirmed(sb):
    sb.op = sb.make_op(version_rc=3)
    sb.extra["PROBE_OP_BIN"] = str(sb.op)
    sb.run()
    result = sb.result()
    assert statuses(result)["P0"] == "observation_unknown" and result["conclusion"] == "cause_unconfirmed"


def test_a_popup_attributed_to_our_process_stops_the_chain(sb):
    sb.set_tcc("attributed")
    proc = sb.run()
    result = sb.result()
    assert proc.returncode == 0
    assert steps_of(result)["P0"]["tcc_observation"] == "seen_attributed"
    assert statuses(result)["P2"] == "skipped_prior_unresolved" and result["conclusion"] == "p0_blocked"


def test_a_popup_without_our_pid_is_seen_unattributed(sb):
    sb.set_tcc("unattributed")
    sb.run()
    assert steps_of(sb.result())["P0"]["tcc_observation"] == "seen_unattributed"


def test_an_unavailable_log_is_unknown_log_unavailable(sb):
    sb.set_tcc("fail")
    sb.run()
    result = sb.result()
    assert steps_of(result)["P0"]["tcc_observation"] == "unknown_log_unavailable" and result["tcc_unknown"] is True


def test_unreachable_network_with_a_cli_timeout_is_a_reachability_candidate(sb):
    sb.op = sb.make_op(version_pre="sleep 10")
    sb.extra.update(PROBE_OP_BIN=str(sb.op), PROBE_P4_STUB="network_error")
    sb.run()
    result = sb.result()
    assert statuses(result)["P4"] == "network_error" and statuses(result)["P0"] == "timeout"
    assert result["conclusion"] == "network_reachability"


def test_probe_directory_and_label_are_unique_per_run_and_never_in_launchagents(sb):
    sb.run()
    sb.run()
    dirs = sorted(p.name for p in sb.base.iterdir())
    assert len(dirs) == 2 and dirs[0] != dirs[1]
    assert (sb.base / dirs[0]).stat().st_mode & 0o777 == 0o700
    assert not (sb.home / "Library").exists()
