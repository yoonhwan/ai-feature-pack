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
        self.envnames = tmp_path / "op-env-names.txt"
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
            f'env | sed -e "s/=.*//" >> "{self.envnames}"\n'
            'case "$1" in\n'
            f'  --version)\n    {version_pre}\n    echo "{version}"; exit {version_rc};;\n'
            f'  user)\n    {acct_pre}\n    {stderr}\n    echo \'{acct}\'; exit {acct_rc};;\n'
            'esac\nexit 2\n'
        )
        return self.script("op", body)

    def make_log(self) -> Path:
        """A fake `log`: refuses calls without --info --debug --predicate --style, records every call, and prints
        secret-free lines shaped like tccd's AUTHREQ_CTX / AUTHREQ_ATTRIBUTION compact output (msgID links them)."""
        code = f"""
import json, pathlib, sys, time
root = pathlib.Path({str(self.root)!r})
args = sys.argv[1:]
calls = root / "log-calls.jsonl"
n = len(calls.read_text().splitlines()) + 1 if calls.exists() else 1
end = None
if "--end" in args:
    end = time.mktime(time.strptime(args[args.index("--end") + 1], "%Y-%m-%d %H:%M:%S"))
with calls.open("a") as handle:
    handle.write(json.dumps({{"args": args, "now": time.time(), "end": end}}) + "\\n")
if not (args[:1] == ["show"] and all(flag in args for flag in ("--info", "--debug", "--predicate", "--style"))):
    sys.exit(2)
modes = pathlib.Path({str(self.seq)!r}).read_text().split()
mode = modes[n - 1] if n <= len(modes) else modes[-1]
if mode == "fail":
    sys.exit(1)
recorded = sorted(pathlib.Path({str(self.base)!r}).glob("*/pids.json"), key=lambda path: path.stat().st_mtime)
children = json.loads(recorded[-1].read_text()).get("children") if recorded else None
mine = str(children[-1]["pid"]) if children else "0"  # the probe's own record: independent of the stub's start-up
def group(msg, service, pid):
    ts = "2026-10-15 17:00:01.000000+0900 0x1f3      Info        0x0                  412    0    tccd: [com.apple.TCC:access] "
    print(ts + f"AUTHREQ_CTX: msgID={{msg}}, function=TCCAccessRequest, service={{service}}, preflight=no, query=0,")
    print(ts + f"AUTHREQ_ATTRIBUTION: msgID={{msg}}, attribution={{{{responsible={{{{TCCDProcess: identifier=org.python.python, pid={{pid}}, auid=501, euid=501, responsible_path=/synthetic/python, binary_path=/synthetic/python}}}}, accessing={{{{TCCDProcess: identifier=com.1password.op, pid={{pid}}, auid=501, euid=501, responsible_path=, binary_path=/synthetic/op}}}}, requesting={{{{TCCDProcess: identifier=com.1password.op, pid={{pid}}, auid=501, euid=501, responsible_path=, binary_path=/synthetic/op}}}},}}}},")
print("Timestamp               Ty Process[PID:TID]")
if mode == "other":          # another service, even attributed to our child: not an AppData request
    group("100.1", "kTCCServiceCamera", mine)
elif mode == "attributed":
    group("412.1", "kTCCServiceSystemPolicyAppData", mine)
elif mode == "unattributed":
    group("412.1", "kTCCServiceSystemPolicyAppData", "1")
elif mode == "no_msgid":       # an explicit AppData request that carries no msgID at all
    ts = "2026-10-15 17:00:01.000000+0900 0x1f3      Info        0x0                  412    0    tccd: [com.apple.TCC:access] "
    print(ts + "AUTHREQ_CTX: function=TCCAccessRequest, service=kTCCServiceSystemPolicyAppData, preflight=no,")
elif mode == "odd_msgid":      # an id format the parser does not know
    ts = "2026-10-15 17:00:01.000000+0900 0x1f3      Info        0x0                  412    0    tccd: [com.apple.TCC:access] "
    print(ts + "AUTHREQ_CTX: msgID=abc/def, function=TCCAccessRequest, service=kTCCServiceSystemPolicyAppData,")
elif mode == "partial_ours":   # only the attribution of our child was collected, the request line is missing
    ts = "2026-10-15 17:00:01.000000+0900 0x1f3      Info        0x0                  412    0    tccd: [com.apple.TCC:access] "
    print(ts + f"AUTHREQ_ATTRIBUTION: msgID=777.1, attribution={{{{accessing={{{{TCCDProcess: identifier=com.1password.op, pid={{mine}}, auid=501}}}},}}}},")
elif mode == "partial_other":  # a partial group about somebody else's pid
    ts = "2026-10-15 17:00:01.000000+0900 0x1f3      Info        0x0                  412    0    tccd: [com.apple.TCC:access] "
    print(ts + "AUTHREQ_ATTRIBUTION: msgID=778.1, attribution={{accessing={{TCCDProcess: identifier=x, pid=1, auid=501}},}},")
elif mode == "split_unlinked":  # AppData ctx under one msgID, our pid only under another: no link
    group("412.1", "kTCCServiceSystemPolicyAppData", "1")
    group("413.1", "kTCCServiceCamera", mine)
"""
        (self.bin / "log_stub.py").write_text(code, encoding="utf-8")
        return self.script("log", f'exec "{sys.executable}" "{self.bin / "log_stub.py"}" "$@"\n')

    def set_tcc(self, *modes: str) -> None:
        self.seq.write_text("\n".join(modes) + "\n", encoding="utf-8")

    def env(self, **extra: str) -> dict[str, str]:
        env = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.home), "TMPDIR": str(self.root),
            "PROBE_BASE": str(self.base), "PROBE_OP_BIN": str(self.op), "PROBE_TOKEN_FILE": str(self.token_file),
            "PROBE_LAUNCHCTL": str(self.launchctl), "PROBE_LOG_BIN": str(self.logbin), "PROBE_PYTHON": sys.executable,
            "PROBE_P4_STUB": "success",
            "PROBE_T_ATTEMPT": "3", "PROBE_T_REAP": "0.5", "PROBE_T_PIPE": "0.3", "PROBE_T_LOCAL": "8",
            "PROBE_T_TAIL": "0.3", "PROBE_T_CALL": "3",
            "PROBE_T_START": "10", "PROBE_T_RESULT": "20", "PROBE_T_CLEAN": "10",
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
    assert "<string>-I</string>" in plist and "<string>--mode</string>" in plist and "<string>selftest</string>" in plist
    assert result["mode"] == "selftest"
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
    assert elapsed < 20 + 10  # the scaled stand-in for the 75 second hard cap (60 + 15)
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
           "aborted_class": None, "mode": "selftest"}
    for status in NINE:
        assert probe.validate_result({**doc, "steps": [{**base, "status": status}]}), status
    assert not probe.validate_result({**doc, "steps": [{**base, "status": "skipped"}]})
    assert not probe.validate_result({**doc, "steps": [{**base, "status": "Success"}]})
    assert not probe.validate_result({**doc, "steps": [{**base, "tcc_observation": "seen"}]})
    assert not probe.validate_result({**doc, "steps": [{**base, "stdout": "body"}]})  # no free-text fields
    assert not probe.validate_result({**doc, "conclusion": "all_good"})
    assert not probe.validate_result({**doc, "extra": 1})
    assert not probe.validate_result({**doc, "mode": "normal"})
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


# ---------------------------------------------------------------------------------------------------------
# DA r1 (REJECT 1/4/2): each counterexample as a regression test
def log_calls(sb: Sandbox) -> list[dict]:
    path = sb.root / "log-calls.jsonl"
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


def process_line(pid: int) -> str:
    return subprocess.run(["ps", "-o", "lstart=,comm=", "-p", str(pid)], capture_output=True, text=True,
                          env={"LC_ALL": "C", "PATH": "/usr/bin:/bin"}).stdout.strip()


# B1 — one 7 second deadline per attempt, fixed before the process starts
def test_b1_pid_record_time_is_taken_out_of_the_attempt(tmp_path, monkeypatch):
    probe = load_probe()
    book, budget = probe.PidBook(tmp_path), probe.Budget(5)
    monkeypatch.setattr(probe, "ATTEMPT_S", 0.5)
    real_ps = probe.ps_line
    monkeypatch.setattr(probe, "ps_line", lambda pid: (time.sleep(0.3), real_ps(pid))[1])
    seen: list = []
    real_communicate = subprocess.Popen.communicate

    def spy(self, input=None, timeout=None):
        if self.args and self.args[0] == "/bin/sleep":
            seen.append(timeout)
        return real_communicate(self, input, timeout)

    monkeypatch.setattr(subprocess.Popen, "communicate", spy)
    info = probe.run_child("P0", ["/bin/sleep", "5"], {"PATH": "/bin"}, book, budget)
    assert info["status"] == "timeout" and info["reaped"] is True
    assert seen[0] is not None and seen[0] <= 0.5 - 0.3 + 0.02  # only what is left of the attempt


def test_b1_when_recording_outlasts_the_attempt_the_child_is_ended_without_a_fresh_wait(tmp_path, monkeypatch):
    probe = load_probe()
    book, budget = probe.PidBook(tmp_path), probe.Budget(5)
    monkeypatch.setattr(probe, "ATTEMPT_S", 1.2)
    monkeypatch.setattr(probe, "PIPE_DRAIN_S", 0.3)
    real_ps = probe.ps_line
    monkeypatch.setattr(probe, "ps_line", lambda pid: (time.sleep(1.4), real_ps(pid))[1])
    seen: list = []
    real_communicate = subprocess.Popen.communicate

    def spy(self, input=None, timeout=None):
        if self.args and self.args[0] == "/bin/sleep":
            seen.append(timeout)
        return real_communicate(self, input, timeout)

    monkeypatch.setattr(subprocess.Popen, "communicate", spy)
    info = probe.run_child("P0", ["/bin/sleep", "5"], {"PATH": "/bin"}, book, budget)
    assert info["status"] == "timeout" and info["child_exited"] is True
    assert seen and all(t is not None and t <= 0.31 for t in seen), seen  # only the short pipe drain, no new attempt


def test_b1_p4_dns_delay_is_inside_one_cancellable_deadline(tmp_path, monkeypatch):
    probe = load_probe()
    monkeypatch.setattr(probe, "SELFTEST", True)
    monkeypatch.setattr(probe, "ATTEMPT_S", 0.6)
    monkeypatch.setenv("PROBE_P4_FAKE_DNS_SLEEP", "6")
    monkeypatch.setenv("PROBE_P4_HOST", "127.0.0.1")
    monkeypatch.setenv("PROBE_P4_PORT", "9")
    book, budget = probe.PidBook(tmp_path), probe.Budget(5)
    started = time.monotonic()
    step = probe.stage_p4(book, budget)
    assert step["status"] == "timeout" and step["child_exited"] is True and step["reaped"] is True
    assert time.monotonic() - started < 2.5  # not the 6 s the name lookup would have taken
    assert [c["step"] for c in book.document["children"]] == ["P4"]


def test_b1_no_network_step_starts_once_the_deadline_is_spent():
    probe = load_probe()
    now = [0.0]
    started: list[str] = []

    def resolve(host, port, **kwargs):
        now[0] += 0.2
        return [(2, 1, 6, "", ("127.0.0.1", port))]

    def connect(address, timeout):
        started.append("connect")
        raise AssertionError

    def handshake(sock, host, timeout):
        started.append("tls")
        raise AssertionError

    got = probe.p4_attempt("h", 443, 0.1, now=lambda: now[0], resolve=resolve, connect=connect, handshake=handshake)
    assert got == "timeout" and started == []


def test_b1_p4_maps_each_failure_class_and_success():
    probe = load_probe()
    import socket

    class Sock:
        def close(self):
            pass

    ok = dict(resolve=lambda h, p, **k: [(2, 1, 6, "", ("127.0.0.1", p))], connect=lambda a, t: Sock(),
              handshake=lambda s, h, t: None)
    assert probe.p4_attempt("h", 443, 10.0, now=lambda: 0.0, **ok) == "success"
    assert probe.p4_attempt("h", 443, 10.0, now=lambda: 0.0,
                            **{**ok, "connect": lambda a, t: (_ for _ in ()).throw(socket.timeout())}) == "timeout"
    assert probe.p4_attempt("h", 443, 10.0, now=lambda: 0.0,
                            **{**ok, "resolve": lambda h, p, **k: (_ for _ in ()).throw(socket.gaierror())}) == "network_error"
    assert probe.p4_attempt("h", 443, 10.0, now=lambda: 0.0,
                            **{**ok, "handshake": lambda s, h, t: (_ for _ in ()).throw(ConnectionResetError())}) == "network_error"


# M1 — one overall deadline: every launchctl call is capped, the clean-up has its own limit
def test_m1_a_hanging_bootstrap_is_cut_off_at_the_call_cap(sb):
    started = time.monotonic()
    proc = sb.run(FAKE_LC_BOOTSTRAP_SLEEP="14", PROBE_T_CALL="2")
    elapsed = time.monotonic() - started
    assert proc.returncode == 3 and "시간 초과" in proc.stdout
    assert elapsed < 9, elapsed
    assert sb.loaded() == [] and not sb.opcalls.exists()


def test_m1_a_hanging_cleanup_lookup_is_reported_not_waited_for(sb):
    started = time.monotonic()
    proc = sb.run(FAKE_LC_PRINT_SLEEP_WHEN_LOADED="14", PROBE_T_CALL="2")
    elapsed = time.monotonic() - started
    assert proc.returncode != 0 and "잔존 확인 필요: com.airag.probe-opa-" in proc.stdout
    assert elapsed < 20 + 10
    assert [c for c in sb.lc_calls() if c.startswith("bootout")] == []  # ownership could not be shown


def test_m1_a_hanging_bootout_is_tried_once_and_reported(sb):
    started = time.monotonic()
    proc = sb.run(FAKE_LC_BOOTOUT_SLEEP="14", PROBE_T_CALL="2")
    elapsed = time.monotonic() - started
    assert proc.returncode != 0 and "잔존 확인 필요: com.airag.probe-opa-" in proc.stdout
    assert len([c for c in sb.lc_calls() if c.startswith("bootout")]) == 1
    assert elapsed < 20 + 10


def test_m1_clean_up_budget_running_out_with_several_pids_is_reported(sb):
    stubborn = [subprocess.Popen(["/bin/sh", "-c", 'trap "" TERM; while :; do sleep 1; done']) for _ in range(3)]
    try:
        time.sleep(0.5)
        extra = "\n".join(f"{p.pid}|{process_line(p.pid)}" for p in stubborn)
        started = time.monotonic()
        proc = sb.run(PROBE_EXTRA_PIDS=extra, PROBE_T_CLEAN="5")  # 5 s clean-up window, 4 s of it reserved
        elapsed = time.monotonic() - started
        assert "잔존 확인 필요: pid" in proc.stdout
        assert elapsed < 20 + 5
        assert proc.returncode == 4
    finally:
        for p in stubborn:
            p.kill()
            p.wait()


# M2 — only a job this run started (its own PROBE_DIR in the loaded job) may be booted out
def test_m2_a_foreign_job_under_the_same_label_is_never_booted_out(sb):
    proc = sb.run(FAKE_LC_FOREIGN="1")
    assert proc.returncode == 2
    assert not any(c.startswith(("bootstrap", "bootout")) for c in sb.lc_calls())
    assert not sb.opcalls.exists()
    # a refused start looks at the label once (the preflight) and never again: clean-up has no label to own
    assert [c for c in sb.lc_calls() if c.startswith("print gui/") and "probe-opa" in c].__len__() == 1


def test_m2_an_unknown_preflight_never_boots_anything_out(sb):
    proc = sb.run(FAKE_LC_PRINT_ERROR_ALWAYS="1")
    assert proc.returncode == 2
    assert not any(c.startswith(("bootstrap", "bootout")) for c in sb.lc_calls())


def test_m2_a_different_job_under_the_label_after_our_bootstrap_is_left_alone(sb):
    proc = sb.run(FAKE_LC_FOREIGN_AFTER_BOOTSTRAP="1")
    assert any(c.startswith("bootstrap") for c in sb.lc_calls())
    assert not any(c.startswith("bootout") for c in sb.lc_calls())
    assert proc.returncode == 4 and "잔존 확인 필요: com.airag.probe-opa-" in proc.stdout


# M3 — AppData requests, linked to their attribution, observed after the window really closed
def test_m3_other_services_are_not_appdata_requests_even_when_attributed_to_us(sb):
    sb.set_tcc("other")
    sb.run()
    result = sb.result()
    assert steps_of(result)["P0"]["tcc_observation"] == "none_logged_ok"
    assert result["conclusion"] == "no_repro_twice"


def test_m3_an_appdata_request_not_ours_is_unattributed_even_if_another_service_names_our_pid(sb):
    sb.set_tcc("split_unlinked")
    sb.run()
    assert steps_of(sb.result())["P0"]["tcc_observation"] == "seen_unattributed"


def test_m3_the_log_is_asked_with_info_and_debug_once_the_window_has_closed(sb):
    sb.run()
    calls = log_calls(sb)
    assert len(calls) == 4
    for call in calls:
        args = call["args"]
        assert args[0] == "show" and "--info" in args and "--debug" in args
        assert "com.apple.TCC" in args[args.index("--predicate") + 1]
        assert call["now"] + 1.0 >= call["end"]  # asked only after end + tail (the end is rounded up to a whole second)


def test_m3_waiting_on_ops_does_not_use_up_the_observation_budget(sb):
    sb.op = sb.make_op(version_pre="sleep 1", acct_pre="sleep 1")
    sb.extra.update(PROBE_OP_BIN=str(sb.op), PROBE_T_ATTEMPT="4", PROBE_T_LOCAL="3")
    sb.run()
    result = sb.result()
    assert {s["tcc_observation"] for n, s in steps_of(result).items() if n != "P4"} == {"none_logged_ok"}
    assert result["tcc_unknown"] is False


def test_m3_a_window_that_cannot_be_secured_is_unknown_and_the_log_is_not_asked(sb):
    sb.extra.update(PROBE_T_TAIL="5", PROBE_T_LOCAL="1")
    sb.run()
    result = sb.result()
    assert {s["tcc_observation"] for n, s in steps_of(result).items() if n in ("P0", "P2", "P1")} == {
        "unknown_log_unavailable"}
    assert statuses(result)["P1b"] == "skipped_not_applicable" and result["tcc_unknown"] is True
    assert log_calls(sb) == []


# M4 — the worker's mode comes from an explicit argument, never from the surrounding environment
def production_env(sb: Sandbox, ambient: dict[str, str]) -> dict[str, str]:
    fakebin = sb.root / "prod-bin"
    fakebin.mkdir(exist_ok=True)
    shim = fakebin / "launchctl"
    shim.write_text(
        f'#!/bin/sh\nFAKE_LC_STATE="{sb.state}" FAKE_LC_AMBIENT_JSON=\'{json.dumps(ambient)}\' '
        f'exec "{sys.executable}" "{FAKE_LAUNCHCTL}" "$@"\n', encoding="utf-8")
    shim.chmod(0o755)
    return {"PATH": f"{fakebin}:/usr/bin:/bin", "HOME": str(sb.home), "TMPDIR": str(sb.root)}


def test_m4_a_normal_worker_refuses_ambient_selftest_variables(sb):
    ambient = {"PROBE_SELFTEST": "1", "PROBE_OP_BIN": str(sb.op), "PROBE_TOKEN_FILE": str(sb.token_file),
               "PROBE_LOG_BIN": str(sb.logbin), "PROBE_P4_STUB": "success", "PROBE_PYTHON": sys.executable}
    env = production_env(sb, ambient)
    proc = subprocess.run(["/bin/bash", str(PROBE_SH), "--python", sys.executable], env=env, capture_output=True,
                          text=True, timeout=60)
    base = sb.home / ".local" / "share" / "airag-probe"
    directory = next(p for p in base.iterdir() if p.is_dir())
    result = json.loads((directory / "result.json").read_text())
    assert load_probe().validate_result(result)
    assert result["mode"] == "production" and result["aborted_class"] == "AmbientOverrideRefused"
    assert result["steps"] == [] and result["conclusion"] == "observation_unknown"
    assert not sb.opcalls.exists() and log_calls(sb) == []  # nothing ran: no op, no log
    assert proc.returncode != 0
    plist = (directory / "job.plist").read_text()
    assert "<string>-I</string>" in plist and "<string>production</string>" in plist and "PROBE_" not in plist
    assert sb.loaded() == []


def test_m1_production_needs_a_checked_consumer_python(sb):
    env = production_env(sb, {})
    for args in ([], ["--python", "python3"], ["--python", str(sb.root / "missing-python")]):
        proc = subprocess.run(["/bin/bash", str(PROBE_SH), *args], env=env, capture_output=True, text=True, timeout=30)
        assert proc.returncode == 2, (args, proc.stdout)
    assert sb.lc_calls() == [] and not (sb.home / ".local" / "share" / "airag-probe").exists()


# m2 — an op child sees only the allow-listed names (names only, never values)
ALLOWED_OP_NAMES = {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR",
                    "OP_SERVICE_ACCOUNT_TOKEN", "OP_CONFIG_DIR"}
SHELL_ADDED = {"PWD", "SHLVL", "_", "OLDPWD"}


def test_m2_op_children_receive_only_allowlisted_environment_names(sb):
    sb.run(FAKE_AMBIENT_SECRET_NAME="x")
    names = set(sb.envnames.read_text().split())
    assert names and names <= ALLOWED_OP_NAMES | SHELL_ADDED, names - ALLOWED_OP_NAMES - SHELL_ADDED
    assert not [n for n in names if n.startswith(("PROBE_", "FAKE_"))]


def test_m2_op_environment_copies_only_the_allowlist(monkeypatch):
    probe = load_probe()
    for name in ("SOME_API_TOKEN", "OP_EXTRA_SECRET", "PROBE_OP_BIN", "FAKE_X"):
        monkeypatch.setenv(name, "value")
    names = set(probe.op_environment("t")) | set(probe.op_environment("t", "/dedicated"))
    assert names <= ALLOWED_OP_NAMES
    assert "OP_SERVICE_ACCOUNT_TOKEN" not in probe.op_environment(None)


def test_recorded_pids_are_found_again_whatever_the_callers_locale(sb):
    # probe.py records `ps` text in the job's (C) locale; the shell clean-up runs in the user's locale.
    sb.op = sb.make_op(version_pre="sleep 30")
    sb.extra.update(PROBE_OP_BIN=str(sb.op), PROBE_T_ATTEMPT="25", PROBE_T_RESULT="4")
    proc = sb.run(FAKE_LC_BOOTOUT_FAIL="1", LANG="ko_KR.UTF-8")
    pids = json.loads((sb.probe_dir() / "pids.json").read_text())
    assert pids["children"] and not alive(pids["children"][0]["pid"]) and not alive(pids["self"]["pid"])
    assert "잔존 확인 필요: pid" not in proc.stdout


# ---------------------------------------------------------------------------------------------------------
# DA r2 (REJECT 1/3/1)
# B1 — the attempt's deadline is enforced even while the PID is being recorded
def _first_kill_after_spawn(probe, tmp_path, monkeypatch, *, attempt: float, record_delay: float) -> float:
    book, budget = probe.PidBook(tmp_path), probe.Budget(5)
    monkeypatch.setattr(probe, "ATTEMPT_S", attempt)
    real_ps = probe.ps_line
    monkeypatch.setattr(probe, "ps_line", lambda pid: (time.sleep(record_delay), real_ps(pid))[1])
    kills: list[float] = []
    real_kill = subprocess.Popen.kill

    def kill(self):
        if self.args and self.args[0] == "/bin/sleep":
            kills.append(time.monotonic())
        return real_kill(self)

    monkeypatch.setattr(subprocess.Popen, "kill", kill)
    started = time.monotonic()
    info = probe.run_child("P0", ["/bin/sleep", "30"], {"PATH": "/bin"}, book, budget)
    assert info["status"] == "timeout" and info["reaped"] is True
    assert kills, "the direct child must be ended"
    return min(kills) - started


def test_b1_first_kill_comes_at_the_attempt_deadline_while_the_record_is_slow(tmp_path, monkeypatch):
    waited = _first_kill_after_spawn(load_probe(), tmp_path, monkeypatch, attempt=0.5, record_delay=1.2)
    assert waited <= 0.5 + 0.25, waited


def test_b1_first_kill_at_the_default_seven_seconds_with_a_7_4_second_record(tmp_path, monkeypatch):
    waited = _first_kill_after_spawn(load_probe(), tmp_path, monkeypatch, attempt=7.0, record_delay=7.4)
    assert 6.9 <= waited <= 7.0 + 0.3, waited  # the pinned counterexample: it used to be 7.405


def test_b1_no_child_is_started_when_the_preparation_used_the_attempt_up(tmp_path, monkeypatch):
    probe = load_probe()
    book, budget = probe.PidBook(tmp_path), probe.Budget(5)
    monkeypatch.setattr(probe, "ATTEMPT_S", 0.3)
    real_before = book.before
    monkeypatch.setattr(book, "before", lambda step: (time.sleep(0.6), real_before(step))[1])
    spawned: list = []
    real_init = subprocess.Popen.__init__
    monkeypatch.setattr(subprocess.Popen, "__init__",
                        lambda self, *a, **k: (spawned.append(a), real_init(self, *a, **k))[1])
    info = probe.run_child("P0", ["/bin/sleep", "30"], {"PATH": "/bin"}, book, budget)
    assert info["status"] == "timeout" and info["child_pid"] is None
    assert [a for a in spawned if a and a[0] and a[0][0] == "/bin/sleep"] == []


# M1 — the shell's own ps calls are bounded by the clean-up time that is left
def slow_ps_dir(sb: Sandbox) -> tuple[Path, Path]:
    directory = sb.root / "slow-ps-bin"
    directory.mkdir(exist_ok=True)
    flag = sb.root / "ps-slow-flag"
    shim = directory / "ps"
    shim.write_text(f'#!/bin/sh\n[ -f "{flag}" ] && sleep 3\nexec /bin/ps "$@"\n', encoding="utf-8")
    shim.chmod(0o755)
    return directory, flag


def test_m1_a_slow_ps_cannot_stretch_the_clean_up_past_its_budget(sb):
    directory, flag = slow_ps_dir(sb)
    started = time.monotonic()
    proc = sb.run(PATH=f"{directory}:/usr/bin:/bin:/usr/sbin:/sbin", FAKE_LC_SLOW_PS_FLAG=str(flag),
                  PROBE_T_CLEAN="8", PROBE_T_RESULT="20")
    elapsed = time.monotonic() - started
    assert elapsed < 4 + 8 + 4, elapsed  # run phase + clean-up window + a little (it was 19 s for 11 s of budget)
    assert proc.returncode == 4 and "잔존 확인 필요: pid" in proc.stdout  # unchecked pids are reported, not awaited
    assert sb.loaded() == []


def test_m1_no_ps_is_started_once_the_clean_up_time_is_gone(sb):
    directory, flag = slow_ps_dir(sb)
    log = sb.root / "ps-starts.txt"
    shim = directory / "ps"
    shim.write_text(f'#!/bin/sh\necho "$(date +%s)" >> "{log}"\n[ -f "{flag}" ] && sleep 3\nexec /bin/ps "$@"\n',
                    encoding="utf-8")
    sb.run(PATH=f"{directory}:/usr/bin:/bin:/usr/sbin:/sbin", FAKE_LC_SLOW_PS_FLAG=str(flag),
           PROBE_T_CLEAN="8", PROBE_T_RESULT="20")
    starts = [int(x) for x in log.read_text().split()]
    assert starts and max(starts) - min(starts) <= 4 + 8, (min(starts), max(starts))


# M2 — an exact match of the loaded job's arguments and plist path, nothing looser
@pytest.mark.parametrize("style", ["suffix", "extra_arg", "env_only", "path_suffix", "prefix_dir"])
def test_m2_a_look_alike_job_is_never_booted_out(sb, style):
    proc = sb.run(FAKE_LC_FOREIGN_AFTER_BOOTSTRAP="0", FAKE_LC_STYLE=style)
    assert any(c.startswith("bootstrap") for c in sb.lc_calls())
    assert not any(c.startswith("bootout") for c in sb.lc_calls()), style
    assert proc.returncode == 4 and "잔존 확인 필요: com.airag.probe-opa-" in proc.stdout


def test_m2_our_own_job_is_still_booted_out_when_the_run_is_interrupted_right_after_bootstrap(sb):
    proc = sb.run(FAKE_LC_BOOTSTRAP_SIGNAL="INT")
    assert proc.returncode == 130
    assert sb.loaded() == [] and any(c.startswith("bootout") for c in sb.lc_calls())


# M3 — an AppData request that cannot be linked is never turned into "none"
@pytest.mark.parametrize("mode,expected", [
    ("no_msgid", "seen_unattributed"),
    ("odd_msgid", "seen_unattributed"),
    ("partial_ours", "unknown_log_unavailable"),
    ("partial_other", "none_logged_ok"),
])
def test_m3_unlinked_or_partial_tcc_lines_are_kept_conservatively(sb, mode, expected):
    sb.set_tcc(mode)
    sb.run()
    assert steps_of(sb.result())["P0"]["tcc_observation"] == expected


def test_m3_classifier_cases():
    probe = load_probe()
    head = "2026-10-15 17:00:01.000000+0900 0x1 Info 0x0 412 0 tccd: [com.apple.TCC:access] "
    ctx = head + "AUTHREQ_CTX: msgID=9.1, service=kTCCServiceSystemPolicyAppData,\n"
    attr = head + "AUTHREQ_ATTRIBUTION: msgID=9.1, attribution={accessing={TCCDProcess: pid=321, auid=501}},\n"
    camera = head + "AUTHREQ_CTX: msgID=5.1, service=kTCCServiceCamera,\n"
    assert probe.classify_tcc(ctx + attr, {321}) == "seen_attributed"
    assert probe.classify_tcc(ctx + attr, {999}) == "seen_unattributed"
    assert probe.classify_tcc(camera, {321}) == "none_logged_ok"
    assert probe.classify_tcc(head + "AUTHREQ_CTX: service=kTCCServiceSystemPolicyAppData, pid=321\n", {321}) \
        == "seen_unattributed"
    assert probe.classify_tcc("", {321}) == "unknown_log_unavailable"


# m1 — a refused input is never echoed back
CANARY = "CANARY_VALUE_8842_do_not_print"


def test_m1_production_refuses_test_switches_without_reading_their_values(sb):
    env = production_env(sb, {})
    env.update(PROBE_T_CLEAN=CANARY, PROBE_T_RESULT=CANARY)
    proc = subprocess.run(["/bin/bash", str(PROBE_SH), "--python", sys.executable], env=env, capture_output=True,
                          text=True, timeout=30)
    assert proc.returncode == 2
    assert CANARY not in proc.stdout + proc.stderr and "Bad" not in proc.stderr and "expression" not in proc.stderr
    assert sb.lc_calls() == [] and not (sb.home / ".local" / "share" / "airag-probe").exists()


@pytest.mark.parametrize("name", ["PROBE_T_CLEAN", "PROBE_T_CALL", "PROBE_T_RESULT", "PROBE_T_START"])
def test_m1_selftest_with_a_bad_number_gives_a_fixed_error(sb, name):
    proc = sb.run(**{name: CANARY})
    assert proc.returncode == 2 and CANARY not in proc.stdout + proc.stderr
    assert not sb.opcalls.exists()


def test_m1_selftest_python_side_bad_number_gives_a_fixed_error(sb):
    env = {**sb.env(), "PROBE_T_ATTEMPT": CANARY}
    proc = subprocess.run([sys.executable, str(PROBE_PY), "--report", str(sb.root), "--mode", "selftest"], env=env,
                          capture_output=True, text=True, timeout=30)
    assert CANARY not in proc.stdout + proc.stderr and "Traceback" not in proc.stderr
    assert proc.returncode == 2
