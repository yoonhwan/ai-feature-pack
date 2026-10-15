"""Synthetic scenarios of the three-stage chain wrapper (design arch-20261015-opa-popup-design-r8 §4).

The wrapper runs the reviewed tools unchanged — launchd probe (N1), the E1 terminal table (N2), the same E1 under
``taskpolicy -b`` (N3) — and goes on only when the tool's exit code AND its closed-schema result JSON pass the
gate. Everything here is synthetic: fake tools (``_chain_fake_tool.py``) that write fake result files, fake clocks.
No real op, no real launchctl, no real taskpolicy, no network, no operating file.
"""

from __future__ import annotations

import importlib.util
import itertools
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

import pytest

from test_probe_opa import alive, wait_until

OPS = Path(__file__).resolve().parents[1] / "ops" / "probe-opa"
CHAIN_SH = OPS / "chain.sh"
CHAIN_PY = OPS / "chain.py"
FAKE_TOOL = Path(__file__).with_name("_chain_fake_tool.py")

SENTINELS = ["SYNTH_CH_STDOUT_8801", "SYNTH_CH_STDERR_8802", "SYNTH_CH_ENV_8803", "ops_synthetic_chain_token_8804"]
P_NAME = "20261015-210000-111-222"          # a probe folder name (date-time-pid-random)
E1_NAME = "compare-20261015-211000-333-444.result.json"
E1_NAME_2 = "compare-20261015-211100-555-666.result.json"
E1_NAME_3 = "compare-20261015-211200-777-888.result.json"
PLAN6 = [("A", 1), ("B", 1), ("C", 1), ("A", 2), ("B", 2), ("C", 2)]


def load_chain(monkeypatch, env: dict[str, str] | None = None):
    monkeypatch.setattr(sys, "argv", ["chain.py", "--mode", "selftest"])
    for name, value in (env or {}).items():
        monkeypatch.setenv(name, value)
    spec = importlib.util.spec_from_file_location("chain_opa", CHAIN_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ------------------------------------------------------------------------------------------ synthetic documents
def step(name: str, status: str, **kw) -> dict:
    skipped = status.startswith("skipped")
    doc = {"step": name, "status": status, "rc": None if skipped else 0, "elapsed_ms": 0 if skipped else 25,
           "started_utc_ms": 1, "ended_utc_ms": 2, "child_pid": None if skipped else 123,
           "child_exited": None if skipped else True, "reaped": False if skipped else True,
           "child_exit_unconfirmed": False, "descendants_may_hold_pipe": False, "account_type_confirmed": None,
           "tcc_observation": None if skipped else "none_logged_ok"}
    doc.update(kw)
    return doc


def probe_doc(**top) -> dict:
    """A complete probe result in which everything went fine (conclusion no_repro_twice)."""
    doc = {"schema_version": 1, "complete": True, "tcc_unknown": False, "conclusion": "no_repro_twice",
           "timed_out_wait": False, "aborted_class": None, "mode": "production",
           "s0": {"consumer_disabled": "true", "consumer_loaded": "false", "op_process_count": 2,
                  "op_socket_mtime_utc_ms": 1},
           "steps": [step("P4", "success"), step("P0", "success"),
                     step("P2", "success", account_type_confirmed=True),
                     step("P1", "success", account_type_confirmed=True),
                     step("P1b", "success", account_type_confirmed=True)]}
    doc.update(top)
    return doc


def p0_blocked_doc() -> dict:
    """The observation this experiment is about (the real 10-15 19:45 shape): P0 timed out, reaped, TCC unknown,
    everything after it skipped (reaped=false because nothing was started) — NOT an error."""
    return probe_doc(conclusion="p0_blocked", tcc_unknown=True, steps=[
        step("P4", "success", elapsed_ms=707),
        step("P0", "timeout", rc=-9, elapsed_ms=7038, tcc_observation="unknown_log_unavailable"),
        step("P2", "skipped_prior_unresolved"), step("P1", "skipped_prior_unresolved"),
        step("P1b", "skipped_prior_unresolved")])


def e1_round(variant: str, number: int, status: str = "success", **kw) -> dict:
    doc = {"variant": variant, "round": number, "status": status, "elapsed_ms": 30, "rc": 0, "reaped": True,
           "child_exit_unconfirmed": False}
    doc.update(kw)
    return doc


def e1_doc(**top) -> dict:
    doc = {"v": 1, "rounds": [e1_round(v, n) for v, n in PLAN6],
           "conditions": {"A": "fast", "B": "fast", "C": "fast"}, "op_count_before": 2, "op_count_after": 2,
           "sock_mtime_changed": False, "removed_name_count_A": 20, "leftover_check_required": False,
           "complete": True, "exit_class": "ran_all", "conclusion": "terminal_all_fast"}
    doc.update(top)
    return doc


def e1_all_timeout_doc() -> dict:
    return e1_doc(rounds=[e1_round(v, n, "timeout", rc=-9, reaped=True) for v, n in PLAN6],
                  conditions={"A": "slow", "B": "slow", "C": "slow"}, conclusion="terminal_all_slow")


def as_text(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, separators=(",", ":"))


# ---------------------------------------------------------------------------------- the gates as pure functions
def test_the_synthetic_documents_are_valid_for_the_reviewed_probe_schema(monkeypatch):
    chain = load_chain(monkeypatch)
    assert chain.probe.validate_result(probe_doc()) and chain.probe.validate_result(p0_blocked_doc())


def test_g1_passes_the_observation_this_experiment_is_about(monkeypatch):
    chain = load_chain(monkeypatch)
    assert chain.gate_probe(probe_doc()) is None
    assert chain.gate_probe(p0_blocked_doc()) is None          # P0 timeout (reaped) + TCC unknown + skipped (reaped=false)
    blocked = p0_blocked_doc()
    blocked["steps"][0]["status"] = "network_error"            # P4 network_error / auth_error are observations
    blocked["steps"][2:] = [step("P2", "auth_error", rc=1)]
    assert chain.gate_probe(blocked) is None


def test_g1_never_inspects_a_skipped_step_for_exit_state(monkeypatch):
    """Design §4.3: only steps that were actually run (status not skipped_*) are checked — a skipped step passes even
    with reaped=false and a recorded pid, so a step the probe did not start can never stop the chain."""
    chain = load_chain(monkeypatch)
    doc = p0_blocked_doc()
    doc["steps"][2].update(child_pid=123, reaped=False, child_exited=False, descendants_may_hold_pipe=True,
                           child_exit_unconfirmed=True)
    assert chain.probe.validate_result(doc) and chain.gate_probe(doc) is None


def _mut_probe(path):
    doc = probe_doc()
    path(doc)
    return doc


@pytest.mark.parametrize("mutation,reason", [
    (lambda d: d.update(complete=False), "probe_incomplete"),
    (lambda d: d.update(timed_out_wait=True), "probe_incomplete"),
    (lambda d: d.update(aborted_class="OSError"), "probe_incomplete"),
    (lambda d: d.update(conclusion="observation_unknown"), "probe_incomplete"),
    (lambda d: d["steps"][1].update(child_exit_unconfirmed=True), "probe_exit_unconfirmed"),
    (lambda d: d["steps"][2].update(descendants_may_hold_pipe=True), "probe_exit_unconfirmed"),
    (lambda d: d["steps"][3].update(reaped=False), "probe_exit_unconfirmed"),     # started (child_pid) but not reaped
    (lambda d: d["steps"][1].update(status="spawn_error", child_pid=None, child_exited=None, reaped=False, rc=None,
                                    tcc_observation=None), "probe_step_error"),
    (lambda d: d["steps"][2].update(status="observation_unknown"), "probe_step_error"),
    (lambda d: d["steps"][2].update(status="unsupported"), "probe_step_error"),
])
def test_g1_stops_on_each_single_change(monkeypatch, mutation, reason):
    chain = load_chain(monkeypatch)
    assert chain.gate_probe(_mut_probe(mutation)) == reason


def test_g1_rejects_a_document_that_breaks_the_closed_schema(monkeypatch):
    chain = load_chain(monkeypatch)
    extra = probe_doc()
    extra["note"] = "free text"
    wrong_type = probe_doc()
    wrong_type["steps"][0]["elapsed_ms"] = "25"
    missing = probe_doc()
    del missing["steps"][0]["reaped"]
    for doc in (extra, wrong_type, missing, [], "x", None):
        assert chain.gate_probe(doc) == "result_schema"


def test_g2_passes_all_fast_and_all_slow_observations(monkeypatch):
    chain = load_chain(monkeypatch)
    assert chain.gate_e1(e1_doc()) is None
    assert chain.gate_e1(e1_all_timeout_doc()) is None          # a confirmed slow measurement is an observation


def _mut_e1(mutation):
    doc = e1_doc()
    mutation(doc)
    return doc


@pytest.mark.parametrize("mutation,reason", [
    (lambda d: d.update(complete=False), "e1_incomplete"),
    (lambda d: d.update(exit_class="incomplete"), "e1_incomplete"),
    (lambda d: d.update(exit_class="cancelled"), "e1_incomplete"),
    (lambda d: d.update(conclusion="cancelled_incomplete"), "e1_incomplete"),
    (lambda d: d.update(conclusion="incomplete_missing_rounds"), "e1_incomplete"),
    (lambda d: d["rounds"].pop(), "e1_incomplete"),
    (lambda d: d["rounds"][5].update(status="skipped_budget", elapsed_ms=None, rc=None, reaped=False), "e1_incomplete"),
    (lambda d: d.update(conclusion="incomplete_exit_unconfirmed"), "e1_exit_unconfirmed"),
    (lambda d: d["rounds"][2].update(child_exit_unconfirmed=True, reaped=False), "e1_exit_unconfirmed"),
    (lambda d: d["rounds"][4].update(reaped=False), "e1_exit_unconfirmed"),
    (lambda d: d.update(leftover_check_required=True), "e1_leftover_check_required"),
    (lambda d: d.update(op_count_after=3), "e1_count_changed"),
    (lambda d: d.update(op_count_after=1), "e1_count_changed"),
    (lambda d: d.update(op_count_after=None), "e1_count_changed"),
    (lambda d: d.update(op_count_before=None, op_count_after=None), "e1_count_changed"),   # None == None is no proof
    (lambda d: d.update(conclusion="inconclusive_error"), "e1_inconclusive_error"),
    (lambda d: d["rounds"][1].update(status="spawn_error", rc=None, reaped=False), "e1_inconclusive_error"),
    (lambda d: d["rounds"][3].update(status="bad_output"), "e1_inconclusive_error"),
])
def test_g2_stops_on_each_single_change(monkeypatch, mutation, reason):
    chain = load_chain(monkeypatch)
    assert chain.gate_e1(_mut_e1(mutation)) == reason


def test_g2_counterexamples_of_the_design_review_all_stop(monkeypatch):
    """Count 2->3 with exit code 0 and the leftover flag; second-round spawn_error with inconclusive_error."""
    chain = load_chain(monkeypatch)
    grown = e1_doc(op_count_after=3, leftover_check_required=True)
    assert chain.gate_e1(grown) == "e1_leftover_check_required"
    errored = e1_doc(conclusion="inconclusive_error")
    errored["rounds"][1] = e1_round("B", 1, "spawn_error", rc=None, reaped=False)
    assert chain.gate_e1(errored) == "e1_inconclusive_error"


def test_g2_rejects_a_document_that_breaks_the_closed_schema(monkeypatch):
    chain = load_chain(monkeypatch)
    extra = e1_doc()
    extra["stdout"] = "free text"
    wrong_type = e1_doc(leftover_check_required="false")
    bool_as_int = e1_doc(op_count_before=True, op_count_after=True)
    bad_round = e1_doc()
    bad_round["rounds"][0]["extra"] = 1
    bad_enum = e1_doc(conclusion="solved")
    bad_variant = e1_doc()
    bad_variant["rounds"][0]["variant"] = "Z"
    for doc in (extra, wrong_type, bool_as_int, bad_round, bad_enum, bad_variant, {}, [], None):
        assert chain.gate_e1(doc) == "result_schema"


# ------------------------------------------------------------------------------- the tools' command lines
def test_the_tools_are_the_unmodified_reviewed_scripts_and_n3_is_taskpolicy_b(monkeypatch):
    chain = load_chain(monkeypatch)
    tools = chain.build_tools(Path("/x/probe-opa"), "/py/python")
    assert tools["N1"] == ["/bin/bash", "/x/probe-opa/probe.sh", "--python", "/py/python"]
    assert tools["N2"] == ["/bin/bash", "/x/probe-opa/compare.sh", "--python", "/py/python"]
    assert tools["N3"] == ["/usr/sbin/taskpolicy", "-b", "/bin/bash", "/x/probe-opa/compare.sh", "--python",
                           "/py/python"]


def test_production_numbers_are_the_design_numbers(monkeypatch):
    chain = load_chain(monkeypatch)
    assert chain.STEP_S == 75.0 and chain.TRANSITION_S == 3.0 and chain.SLOT_S == 80.0
    assert chain.START_NEED_S == 83.0 and chain.OVERRUN_S == 77.0 and chain.GRACE_S == 3.0
    assert chain.plan_total(3) == 240.0                       # the one canonical overall limit (not 3 x 75)
    # the fallbacks get their own totals (design review minor: 150 s did not fit 2 x (75+3) and the 83 s start)
    assert chain.plan_total(2) == 162.0 and chain.plan_total(1) == 84.0
    for count in (1, 2, 3):                                   # the last stage must be startable, normal path
        assert chain.plan_total(count) - (count - 1) * (chain.STEP_S + chain.TRANSITION_S) >= chain.START_NEED_S
        # and the overrun path (start + 77 + 3 grace) plus the final display still fits
        last_start = (count - 1) * (chain.STEP_S + chain.TRANSITION_S)
        assert last_start + chain.OVERRUN_S + chain.GRACE_S + 2.0 <= chain.plan_total(count)


# ---------------------------------------------------------------------------------------- the process sandbox
class ChainSandbox:
    def __init__(self, tmp_path: Path):
        self.root = tmp_path
        self.base = tmp_path / "probe-base"
        self.specs = tmp_path / "specs"
        self.specs.mkdir()
        self.tools = {n: [sys.executable, str(FAKE_TOOL), n] for n in ("N1", "N2", "N3")}
        self.good()

    def spec(self, name: str, **spec) -> None:
        (self.specs / f"{name}.json").write_text(json.dumps(spec), encoding="utf-8")

    def good(self, n1=None, n2=None, n3=None) -> None:
        self.spec("N1", write=[{"name": f"{P_NAME}/result.json", "text": as_text(n1 or probe_doc())}])
        self.spec("N2", write=[{"name": E1_NAME, "text": as_text(n2 or e1_doc())}])
        self.spec("N3", write=[{"name": E1_NAME_2, "text": as_text(n3 or e1_doc())}])

    def env(self, **extra: str) -> dict[str, str]:
        env = {
            "PATH": "/usr/bin:/bin", "HOME": str(self.root), "TMPDIR": str(self.root), "PROBE_BASE": str(self.base),
            "CH_SPEC_DIR": str(self.specs), "PROBE_CH_TOOLS": json.dumps(self.tools),
            "PROBE_CH_T_STEP": "2.0", "PROBE_CH_T_TRANSITION": "0.5", "PROBE_CH_T_SLOT": "3.0",
            "PROBE_CH_T_OVERRUN": "2.6", "PROBE_CH_T_GRACE": "0.6", "PROBE_CH_T_CANCEL": "2.0",
        }
        env.update(extra)
        return env

    def start(self, *args: str, selftest: bool = True, python: str | None = None, **extra: str) -> subprocess.Popen:
        argv = ["/bin/bash", str(CHAIN_SH)]
        if selftest:
            argv.append("--selftest")
        argv += ["--python", python or sys.executable, *args]
        return subprocess.Popen(
            argv, env=self.env(**extra), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True, preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))

    def run(self, *args: str, timeout: float = 60, **extra: str) -> subprocess.CompletedProcess:
        process = self.start(*args, **extra)
        out, err = process.communicate(timeout=timeout)
        return subprocess.CompletedProcess(process.args, process.returncode, out, err)

    def calls(self) -> list[str]:
        path = self.specs / "calls.txt"
        return [line.split()[0] for line in path.read_text().splitlines()] if path.exists() else []

    def pids(self, name: str) -> list[int]:
        path = self.specs / "calls.txt"
        return [int(line.split()[1]) for line in path.read_text().splitlines() if line.split()[0] == name] \
            if path.exists() else []

    def signals(self, name: str) -> list[int]:
        path = self.specs / f"{name}.signals"
        return [int(x) for x in path.read_text().split()] if path.exists() else []

    def tree_text(self, proc: subprocess.CompletedProcess) -> str:
        parts = [proc.stdout, proc.stderr]
        for path in self.base.rglob("*") if self.base.exists() else []:
            if path.is_file():
                parts.append(path.read_text(encoding="utf-8", errors="replace"))
        return "\n".join(parts)


@pytest.fixture
def sb(tmp_path):
    return ChainSandbox(tmp_path)


# ------------------------------------------------------------------------------------------ the normal run
def test_a_normal_run_executes_the_three_stages_in_order_and_ends_with_zero(sb):
    proc = sb.run()
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert sb.calls() == ["N1", "N2", "N3"]
    assert "N1" in proc.stdout and "N2" in proc.stdout and "N3" in proc.stdout
    assert "no_repro_twice" in proc.stdout and "terminal_all_fast" in proc.stdout   # enums from the result files
    assert "e1_" not in proc.stdout.replace("terminal", "")                         # no stop reason on a clean run


def test_p0_timeout_with_tcc_unknown_and_skipped_steps_goes_on_to_the_next_stage(sb):
    """The positive control: the thing we are looking for is not an error."""
    sb.good(n1=p0_blocked_doc())
    proc = sb.run()
    assert proc.returncode == 0, proc.stdout
    assert sb.calls() == ["N1", "N2", "N3"]
    assert "p0_blocked" in proc.stdout


def test_a_confirmed_slow_e1_is_an_observation_and_n3_still_runs(sb):
    sb.good(n2=e1_all_timeout_doc())
    proc = sb.run()
    assert proc.returncode == 0 and sb.calls() == ["N1", "N2", "N3"]


# ----------------------------------------------------------------------------------- gates in the process
def test_design_counterexample_1_count_2_to_3_with_exit_zero_stops_before_n3(sb):
    sb.good(n2=e1_doc(op_count_after=3, leftover_check_required=True))
    proc = sb.run()
    assert proc.returncode == 5
    assert sb.calls() == ["N1", "N2"]
    assert "e1_leftover_check_required" in proc.stdout


def test_design_counterexample_2_second_round_spawn_error_stops_before_n3(sb):
    bad = e1_doc(conclusion="inconclusive_error")
    bad["rounds"][1] = e1_round("B", 1, "spawn_error", rc=None, reaped=False)
    sb.good(n2=bad)
    proc = sb.run()
    assert proc.returncode == 5 and sb.calls() == ["N1", "N2"]
    assert "e1_inconclusive_error" in proc.stdout


def test_design_counterexample_3_probe_spawn_error_stops_before_n2_and_n3(sb):
    doc = probe_doc(conclusion="cause_unconfirmed")
    doc["steps"][1] = step("P0", "spawn_error", rc=None, child_pid=None, child_exited=None, reaped=False,
                           tcc_observation=None)
    sb.good(n1=doc)
    proc = sb.run()
    assert proc.returncode == 5 and sb.calls() == ["N1"]
    assert "probe_step_error" in proc.stdout


@pytest.mark.parametrize("mutation,reason", [
    (lambda d: d.update(complete=False), "probe_incomplete"),
    (lambda d: d.update(aborted_class="RuntimeError"), "probe_incomplete"),
    (lambda d: d.update(timed_out_wait=True), "probe_incomplete"),
    (lambda d: d["steps"][1].update(child_exit_unconfirmed=True), "probe_exit_unconfirmed"),
])
def test_probe_gate_stops_the_chain_with_exit_five(sb, mutation, reason):
    doc = probe_doc()
    mutation(doc)
    sb.good(n1=doc)
    proc = sb.run()
    assert proc.returncode == 5 and sb.calls() == ["N1"] and reason in proc.stdout


def test_a_stop_after_the_last_stage_is_still_exit_five_and_recorded(sb):
    sb.good(n3=e1_doc(leftover_check_required=True))
    proc = sb.run()
    assert proc.returncode == 5 and sb.calls() == ["N1", "N2", "N3"]
    assert "e1_leftover_check_required" in proc.stdout


# --------------------------------------------------------------------------- finding the result of this run
def test_result_discovery_uses_only_new_entries_of_this_run_not_a_stale_file(sb):
    sb.base.mkdir()
    (sb.base / P_NAME).mkdir()
    (sb.base / P_NAME / "result.json").write_text(as_text(probe_doc()), encoding="utf-8")   # an old, valid result
    sb.spec("N1")                                                                           # writes nothing new
    proc = sb.run()
    assert proc.returncode == 5 and sb.calls() == ["N1"] and "result_missing" in proc.stdout


def test_two_new_result_entries_are_ambiguous(sb):
    other = "20261015-210100-999-888"
    sb.spec("N1", write=[{"name": f"{P_NAME}/result.json", "text": as_text(probe_doc())},
                         {"name": f"{other}/result.json", "text": as_text(probe_doc())}])
    proc = sb.run()
    assert proc.returncode == 5 and sb.calls() == ["N1"] and "result_ambiguous" in proc.stdout


def test_a_kept_temp_home_folder_is_not_mistaken_for_the_e1_result(sb):
    sb.spec("N2", write=[{"name": E1_NAME, "text": as_text(e1_doc())},
                         {"name": "compare-20261015-211000-333-444", "dir": True},
                         {"name": "compare-20261015-211000-333-444/.keep", "text": ""}])
    proc = sb.run()
    assert proc.returncode == 0 and sb.calls() == ["N1", "N2", "N3"]


def test_a_folder_named_like_an_e1_result_is_not_a_result_file(sb):
    sb.spec("N2", write=[{"name": E1_NAME, "text": as_text(e1_doc())},
                         {"name": "compare-20261015-211000-999-999.result.json", "dir": True}])
    proc = sb.run()
    assert proc.returncode == 0 and sb.calls() == ["N1", "N2", "N3"]


def test_unrelated_new_entries_do_not_count(sb):
    sb.spec("N1", write=[{"name": f"{P_NAME}/result.json", "text": as_text(probe_doc())},
                         {"name": "s2-20261015-212000-1-2/note.txt", "text": "x"}, {"name": "stray.txt", "text": "x"}])
    proc = sb.run()
    assert proc.returncode == 0


@pytest.mark.parametrize("text,reason", [
    ('{"v":1,"rounds":[', "result_unreadable"),                      # cut off
    ("", "result_unreadable"),
    ('{"not":"the schema"}', "result_schema"),
    (json.dumps({**e1_doc(), "v": "1"}), "result_schema"),          # wrong type
])
def test_unusable_e1_result_files_stop_before_n3(sb, text, reason):
    sb.spec("N2", write=[{"name": E1_NAME, "text": text}])
    proc = sb.run()
    assert proc.returncode == 5 and sb.calls() == ["N1", "N2"] and reason in proc.stdout


def test_a_missing_required_field_in_the_probe_result_stops_the_chain(sb):
    doc = probe_doc()
    del doc["conclusion"]
    sb.good(n1=doc)
    proc = sb.run()
    assert proc.returncode == 5 and sb.calls() == ["N1"] and "result_schema" in proc.stdout


def test_a_symlinked_result_is_not_followed(sb):
    real = sb.root / "elsewhere.json"
    real.write_text(as_text(e1_doc()), encoding="utf-8")
    # N2 "writes" a symlink as its result: a tiny tool that links instead of writing
    link_tool = sb.root / "link_tool.py"
    link_tool.write_text(
        "import os,sys\nos.symlink(sys.argv[1], os.path.join(os.environ['PROBE_BASE'], sys.argv[2]))\n",
        encoding="utf-8")
    sb.tools["N2"] = [sys.executable, str(link_tool), str(real), E1_NAME]
    proc = sb.run()
    assert proc.returncode == 5 and "result_missing" in proc.stdout and sb.calls() == ["N1"]


# --------------------------------------------------------------------------------------- tool exit codes
@pytest.mark.parametrize("code", [4, 1, 2, 3, 130, 143, 129])
def test_a_nonzero_probe_exit_code_is_passed_on_and_nothing_follows(sb, code):
    sb.spec("N1", rc=code, write=[{"name": f"{P_NAME}/result.json", "text": as_text(probe_doc())}])
    proc = sb.run()
    assert proc.returncode == code and sb.calls() == ["N1"]


@pytest.mark.parametrize("code", [1, 2, 130, 143, 129])
def test_a_nonzero_e1_exit_code_is_passed_on_and_n3_does_not_run(sb, code):
    sb.spec("N2", rc=code, write=[{"name": E1_NAME, "text": as_text(e1_doc())}])
    proc = sb.run()
    assert proc.returncode == code and sb.calls() == ["N1", "N2"]


def test_a_tool_ended_by_a_signal_gives_the_shell_style_code(sb):
    sb.spec("N1", self_kill=int(signal.SIGKILL))
    proc = sb.run()
    assert proc.returncode == 128 + int(signal.SIGKILL) and sb.calls() == ["N1"]


# ----------------------------------------------------------------------------------------- interruption
@pytest.mark.parametrize("sig,code", [(signal.SIGINT, 130), (signal.SIGTERM, 143), (signal.SIGHUP, 129)])
def test_a_signal_during_a_tool_is_forwarded_to_that_tool_only_and_the_code_is_kept(sb, sig, code):
    sb.spec("N1", sleep=20, cleanup_s=0.2)
    process = sb.start()
    assert wait_until(lambda: sb.pids("N1") != [], 15)
    time.sleep(0.2)
    os.kill(process.pid, sig)
    out, err = process.communicate(timeout=30)
    assert process.returncode == code, out + err
    assert sb.signals("N1") == [int(sig)]                      # the tool did its own clean-up on the signal
    assert sb.calls() == ["N1"]                                # the remaining stages are skipped
    assert not any(alive(pid) for pid in sb.pids("N1"))


def test_a_tool_that_ignores_the_forwarded_signal_is_not_signalled_again(sb):
    sb.spec("N1", sleep=12, ignore=True)
    process = sb.start()
    assert wait_until(lambda: sb.pids("N1") != [], 15)
    time.sleep(0.2)
    os.kill(process.pid, signal.SIGTERM)
    out, err = process.communicate(timeout=30)
    try:
        assert process.returncode == 143
        assert sb.signals("N1") == [int(signal.SIGTERM)]       # exactly once: no repeat, no kill
        assert alive(sb.pids("N1")[0])                         # the tool is left alone
        assert "확인" in out
    finally:
        for pid in sb.pids("N1"):
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass


def test_a_signal_between_stages_skips_the_rest_and_keeps_its_code(monkeypatch, tmp_path):
    sb = ChainSandbox(tmp_path)
    chain = load_chain(monkeypatch, {"PROBE_BASE": str(sb.base), "PROBE_CH_TOOLS": json.dumps(sb.tools),
                                     "CH_SPEC_DIR": str(sb.specs)})
    ran = []
    monkeypatch.setattr(chain, "run_tool", lambda argv, env: ran.append(argv[-1]) or
                        {"rc": 0, "overran": False, "left": False})

    def check(name, base, before):
        os.kill(os.getpid(), signal.SIGINT)                    # Ctrl-C lands in the gap after N1
        return None, ["ok"], "label"
    monkeypatch.setattr(chain, "check_stage", check)
    assert chain.main(["--mode", "selftest", "--python", sys.executable]) == 130
    assert ran == ["N1"]


# ------------------------------------------------------------------------------- the clock and the overrun
def _clock_chain(monkeypatch, tmp_path, *, plan: str, durations, tail=None):
    sb = ChainSandbox(tmp_path)
    chain = load_chain(monkeypatch, {"PROBE_BASE": str(sb.base), "PROBE_CH_TOOLS": json.dumps(sb.tools),
                                     "CH_SPEC_DIR": str(sb.specs)})
    clock = {"t": 5000.0}
    monkeypatch.setattr(chain, "clock", lambda: clock["t"])
    begin = clock["t"]
    started = []
    it = iter(durations)

    def fake_run(argv, env):
        started.append((chain.plan_total(len(chain.PLANS[plan])) - (clock["t"] - begin), argv[-1]))
        duration, overran = next(it)
        clock["t"] += duration
        return {"rc": None if overran else 0, "overran": overran, "left": False}

    def fake_check(name, base, before):
        clock["t"] += chain.TRANSITION_S
        return None, ["ok"], "label"
    monkeypatch.setattr(chain, "run_tool", fake_run)
    monkeypatch.setattr(chain, "check_stage", fake_check)
    code = chain.main(["--mode", "selftest", "--python", sys.executable, "--plan", plan])
    return chain, code, started, clock["t"] - begin


def test_the_worst_normal_path_ends_inside_the_240_seconds(monkeypatch, tmp_path):
    chain, code, started, total = _clock_chain(monkeypatch, tmp_path, plan="full",
                                               durations=[(75.0, False)] * 3)
    assert code == 0 and len(started) == 3 and total == 234.0 <= 240.0
    assert all(remaining >= chain.START_NEED_S for remaining, _ in started)


def test_the_overrun_path_signals_only_the_tool_waits_three_seconds_and_ends_with_six(monkeypatch, tmp_path):
    chain, code, started, total = _clock_chain(monkeypatch, tmp_path, plan="full",
                                               durations=[(75.0, False), (75.0, False), (80.0, True)])
    assert code == 6 and len(started) == 3
    assert total == 2 * 78.0 + 80.0 == 236.0 and total + 2.0 <= 240.0   # + the final display


@pytest.mark.parametrize("plan,lengths", [
    ("full", itertools.product((0.0, 40.0, 75.0, 77.0), repeat=3)),
    ("e1", itertools.product((0.0, 40.0, 75.0, 77.0), repeat=2)),
    ("probe", itertools.product((0.0, 75.0, 77.0), repeat=1)),
])
def test_no_start_below_83_seconds_left_and_never_past_the_plan_total(monkeypatch, tmp_path, plan, lengths):
    for index, combo in enumerate(lengths):
        case_dir = tmp_path / f"{plan}-{index}"
        case_dir.mkdir()
        with monkeypatch.context() as m:
            chain, code, started, total = _clock_chain(m, case_dir, plan=plan,
                                                       durations=[(d, False) for d in combo] + [(0.0, False)] * 3)
        assert total <= chain.plan_total(len(chain.PLANS[plan])), (plan, combo, total)
        assert all(remaining >= chain.START_NEED_S for remaining, _ in started), (plan, combo, started)
        if len(started) < len(chain.PLANS[plan]):
            assert code == 7                                            # skipped_budget


def test_too_little_time_for_the_next_stage_means_skipped_budget_and_exit_seven(monkeypatch, tmp_path, capsys):
    chain, code, started, total = _clock_chain(monkeypatch, tmp_path, plan="e1",
                                               durations=[(77.0, False), (1.0, False)])
    assert code == 7 and len(started) == 1                             # 162 - (77 + 3) = 82 < 83
    assert "skipped_budget" in capsys.readouterr().out


def test_the_fallback_plans_run_only_their_own_stages(sb):
    proc = sb.run("--plan", "e1")
    assert proc.returncode == 0 and sb.calls() == ["N2", "N3"]


def test_the_probe_only_fallback_runs_one_stage(tmp_path):
    sb = ChainSandbox(tmp_path)
    proc = sb.run("--plan", "probe")
    assert proc.returncode == 0 and sb.calls() == ["N1"]


# -------------------------------------------------------------------- the overrun with real processes
def test_a_tool_over_the_limit_gets_term_once_and_the_rest_is_skipped(sb):
    sb.spec("N1", sleep=30, cleanup_s=0.1)
    started = time.monotonic()
    proc = sb.run()
    assert proc.returncode == 6, proc.stdout
    assert time.monotonic() - started < 10.0
    assert sb.signals("N1") == [int(signal.SIGTERM)] and sb.calls() == ["N1"]
    assert not any(alive(pid) for pid in sb.pids("N1"))


def test_an_overrunning_tool_that_ignores_term_is_reported_and_left_alone(sb):
    sb.spec("N1", sleep=15, ignore=True)
    try:
        proc = sb.run()
        assert proc.returncode == 6
        assert sb.signals("N1") == [int(signal.SIGTERM)]                  # one TERM, never a second signal, never KILL
        assert alive(sb.pids("N1")[0])
        assert "확인" in proc.stdout and sb.calls() == ["N1"]
    finally:
        for pid in sb.pids("N1"):
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass


def test_other_op_processes_are_never_signalled(sb):
    other = subprocess.Popen(["/bin/bash", "-c", "exec -a op /bin/sleep 60"])
    try:
        assert wait_until(lambda: "op" in subprocess.run(["ps", "-o", "comm=", "-p", str(other.pid)],
                                                         capture_output=True, text=True).stdout.split("/")[-1], 5)
        sb.spec("N1", sleep=30, cleanup_s=0.1)
        sb.run()
        assert other.poll() is None and alive(other.pid)
    finally:
        other.kill()
        other.wait()


# --------------------------------------------------------------------------------------- no values anywhere
def test_nothing_a_tool_prints_or_the_environment_holds_reaches_the_screen_or_a_file(sb):
    for name in ("N1", "N2", "N3"):
        spec = json.loads((sb.specs / f"{name}.json").read_text())
        spec.update(stdout=SENTINELS[0], stderr=SENTINELS[1])
        sb.spec(name, **spec)
    proc = sb.run(SYNTH_AMBIENT=SENTINELS[2], OP_SERVICE_ACCOUNT_TOKEN=SENTINELS[3])
    assert proc.returncode == 0
    text = sb.tree_text(proc)
    for sentinel in SENTINELS:
        assert sentinel not in text, sentinel


def test_a_result_file_with_free_text_is_refused_and_the_text_is_not_shown(sb):
    doc = e1_doc()
    doc["note"] = SENTINELS[0]
    sb.good(n2=doc)
    proc = sb.run()
    assert proc.returncode == 5 and "result_schema" in proc.stdout
    assert SENTINELS[0] not in proc.stdout + proc.stderr


# ------------------------------------------------------------------------------------- start refusals
def test_production_mode_refuses_ambient_test_variables_before_anything(sb):
    proc = sb.start(selftest=False)
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 2 and sb.calls() == [] and "PROBE_" in out + err


def test_a_relative_python_path_is_refused(sb):
    proc = sb.start(python="python3")
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 2 and sb.calls() == []


def test_a_tool_that_is_not_there_is_refused_before_the_first_stage(sb):
    sb.tools["N3"] = ["/nonexistent/taskpolicy", "-b"]
    proc = sb.run()
    assert proc.returncode == 2 and sb.calls() == []


def test_a_symlinked_base_is_refused(sb, tmp_path):
    real = tmp_path / "real-base"
    real.mkdir()
    sb.base.symlink_to(real)
    proc = sb.run()
    assert proc.returncode == 2 and sb.calls() == []


# ------------------------------------------------- the real reviewed tools on synthetic stubs (schema fidelity)
def test_chain_over_the_real_probe_and_compare_scripts_with_synthetic_stubs(tmp_path):
    """probe.sh / compare.sh run unchanged on a fake launchctl / log / op (selftest mode): the result file names,
    the closed schemas and both gates must fit what the real tools write. N3 is the same E1 without taskpolicy."""
    from test_probe_opa import Sandbox
    stub = Sandbox(tmp_path)
    py = sys.executable
    tools = {"N1": ["/bin/bash", str(OPS / "probe.sh"), "--selftest", "--python", py],
             "N2": ["/bin/bash", str(OPS / "compare.sh"), "--selftest", "--python", py],
             "N3": ["/bin/bash", str(OPS / "compare.sh"), "--selftest", "--python", py]}
    env = stub.env(PATH=f"{stub.bin}:/usr/bin:/bin:/usr/sbin:/sbin", PROBE_CH_TOOLS=json.dumps(tools),
                   PROBE_CH_T_STEP="60", PROBE_CH_T_OVERRUN="60", PROBE_CH_T_SLOT="70", PROBE_CH_T_GRACE="3",
                   PROBE_CH_T_CANCEL="20", PROBE_CH_T_TRANSITION="3")
    done = subprocess.run(["/bin/bash", str(CHAIN_SH), "--selftest", "--python", py], env=env, capture_output=True,
                          text=True, timeout=180)
    assert done.returncode == 0, done.stdout + done.stderr
    assert "no_repro_twice" in done.stdout and "terminal_all_fast" in done.stdout
    assert done.stdout.count("통과") == 3
    assert stub.token_file.read_text().strip() not in done.stdout + done.stderr


@pytest.mark.parametrize("also_to_tool", [False, True])
def test_ctrl_c_during_the_real_probe_leaves_no_job_and_no_op_even_when_the_tool_gets_it_twice(tmp_path, also_to_tool):
    """A terminal Ctrl-C reaches the whole foreground group (chain + tool) and the chain forwards it once more:
    the real probe.sh (fake launchctl, a fake op that hangs) must still clean up and the code must stay 130."""
    from test_probe_opa import Sandbox
    stub = Sandbox(tmp_path)
    stub.op = stub.make_op(version_pre="sleep 20")
    py = sys.executable
    tools = {"N1": ["/bin/bash", str(OPS / "probe.sh"), "--selftest", "--python", py],
             "N2": ["/usr/bin/true"], "N3": ["/usr/bin/true"]}
    env = stub.env(PATH=f"{stub.bin}:/usr/bin:/bin:/usr/sbin:/sbin", PROBE_CH_TOOLS=json.dumps(tools),
                   PROBE_CH_T_STEP="60", PROBE_CH_T_OVERRUN="60", PROBE_CH_T_SLOT="70", PROBE_CH_T_CANCEL="25",
                   PROBE_T_ATTEMPT="15", PROBE_T_RESULT="40")
    proc = subprocess.Popen(["/bin/bash", str(CHAIN_SH), "--selftest", "--python", py], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
                            preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
    assert wait_until(lambda: stub.oppids.exists() and stub.oppids.read_text().strip() != "", 25)
    tool_pids = subprocess.run(["pgrep", "-P", str(proc.pid)], capture_output=True, text=True).stdout.split()
    assert tool_pids
    os.kill(proc.pid, signal.SIGINT)
    if also_to_tool:
        for pid in tool_pids:
            os.kill(int(pid), signal.SIGINT)
    out, err = proc.communicate(timeout=60)
    assert proc.returncode == 130, out + err
    assert stub.loaded() == []                                             # the temporary job was taken down
    assert not any(alive(int(x)) for x in stub.oppids.read_text().split())  # and no measurement child is left
    assert "남은 것 확인 필요" not in out


# --------------------------------------------------------------------------------------------- static scope
def test_no_code_path_can_signal_or_end_an_op_process_or_a_group_and_no_token_is_touched():
    for source in (CHAIN_PY.read_text(encoding="utf-8"), CHAIN_SH.read_text(encoding="utf-8")):
        for forbidden in ("os.kill", "killpg", "pkill", "killall", "kill -9", "kill -KILL", "launchctl", "op-sa-token",
                          "read_token", "OP_SERVICE_ACCOUNT_TOKEN", "shell=True", ".kill(", ".terminate("):
            assert forbidden not in source, forbidden
    py = CHAIN_PY.read_text(encoding="utf-8")
    for line in py.splitlines():
        if "send_signal(" in line and not line.lstrip().startswith("#"):
            assert "proc.send_signal(" in line, line                  # the direct tool child only


def test_the_existing_tools_and_tests_are_not_part_of_this_change():
    root = OPS.parents[2]
    names = ["probe.py", "probe.sh", "s2.py", "s2.sh", "compare.py", "compare.sh", "tick.py"]
    paths = [f"feature-pack/rag-consumer/ops/probe-opa/{n}" for n in names[:6]]
    paths += ["feature-pack/rag-consumer/tests/test_probe_opa.py", "feature-pack/rag-consumer/tests/test_s2_opa.py",
              "feature-pack/rag-consumer/tests/test_compare_opa.py"]
    out = subprocess.run(["git", "diff", "--name-only", "HEAD", "--", *paths], cwd=root, capture_output=True,
                         text=True).stdout.split()
    assert out == []
