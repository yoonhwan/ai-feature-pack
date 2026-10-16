"""Tick probe (r16 + errata 1/2): per-key `op read` attempt record, closed schema, recovery chain, rule-12 limits.

Everything here is synthetic: the fake `op` is a scripted ``subprocess.run`` stand-in plus an injected clock, so
no real `op` is ever started. The behavior-unchanged claim is checked on the *final written* log and stdout line:
strip ``probe`` and the rest must equal a baseline run whose probe stage is forced to fail (= the line the tick
wrote before the probe existed), with the same ``op read`` call count and per-call timeouts.
"""

from __future__ import annotations

import copy
from decimal import Decimal
import json
import math
import os
from pathlib import Path
import re
import subprocess
import threading
import types

import pytest

import _tick_baseline_e529d96 as baseline  # frozen pre-probe tick.py (e529d96), for behavior comparison only
from airag_consumer import tick
from test_tick import (
    KEYS, REFERENCES, _one_key_missing_env, base_environment, credentials, run_tick, stub_op, synthetic_service,
)

MISSING = "AIRAG_ARCHIVE_KEY_HEX"  # the one key `_one_key_missing_env` leaves for `op`
GOOD_KEY = KEYS[MISSING]
LIMITS = (0.2, 0.4)  # fast, clock-injected limits for the scenario table (constants are asserted separately)


def _boom(*args, **kwargs):
    raise RuntimeError("injected probe failure")


def _step(advance, kind="ok", **extra):
    return {"advance": advance, "kind": kind, **extra}


def _run_scenario(tmp_path, monkeypatch, capsys, name, steps, *, limits=LIMITS, baseline=False, mutate=None,
                  env=None, scripted_by_reference=None, gate=None):
    """One tick with a scripted `op read` and a fake clock; returns what was really written."""
    run_dir = tmp_path / name
    run_dir.mkdir()
    item, hooks = synthetic_service(run_dir)
    op, _ = stub_op(run_dir)
    creds = credentials(run_dir, op)
    timeouts: list[float] = []
    with monkeypatch.context() as m:
        now = [1000.0]
        m.setattr(tick, "time", types.SimpleNamespace(monotonic=lambda: now[0]))
        if limits is not None:
            m.setattr(tick, "OP_ATTEMPT_TIMEOUT_S", limits[0])
            m.setattr(tick, "OP_CALL_DEADLINE_S", limits[1])
        m.setattr(os, "getloadavg", lambda: (1.5, 1.0, 0.5))
        if baseline:  # probe stage forced down to the last recovery step: the pre-probe line
            m.setattr(tick, "_make_probe", _boom)
            m.setattr(tick, "_minimal_probe", _boom)
        if mutate is not None:
            mutate(m)
        real = subprocess.run

        def run(argv, **kwargs):
            if len(argv) > 1 and argv[1] == "read":
                timeouts.append(kwargs["timeout"])
                if gate is not None:  # the failing key raises only once the others are under way, then they answer
                    failing, raised, started = gate
                    if argv[2] == failing:
                        for _ in range(len(REFERENCES) - 1):
                            started.acquire(timeout=5)
                        raised.set()
                    else:
                        started.release()
                        raised.wait(5)
                script = steps if scripted_by_reference is None else scripted_by_reference[argv[2]]
                index = len(timeouts) - 1 if scripted_by_reference is None else 0
                step = script[min(index, len(script) - 1)]
                now[0] += step["advance"]
                if step["kind"] == "timeout":
                    raise subprocess.TimeoutExpired(argv, kwargs["timeout"], output=step.get("output"))
                if step["kind"] == "oserror":
                    raise PermissionError(13, "MARKER_MESSAGE_SECRET")
                return types.SimpleNamespace(
                    returncode=step.get("rc", 0), stdout=step.get("stdout", GOOD_KEY + "\n"), stderr="",
                )
            return real(argv, **kwargs)

        m.setattr(subprocess, "run", run)
        code = run_tick(run_dir, item, hooks, credentials_path=creds, env=_one_key_missing_env() if env is None else env)
    out = capsys.readouterr().out
    file_line = (run_dir / "logs" / "tick-20260927.log").read_text(encoding="utf-8")
    return types.SimpleNamespace(code=code, timeouts=timeouts, file=file_line, stdout=out, dir=run_dir)


def _without_probe(text):
    data = json.loads(text)
    data.pop("probe", None)
    data.pop("integrity", None)  # the first tick of each run carries the DB check's own (timing) record
    return data


def _masked(text):
    """The line with the DB check's measured milliseconds blanked (they differ between two real runs)."""
    return re.sub(r'"ms":[0-9.]+', '"ms":0', text)


def _assert_behavior_unchanged(tmp_path, monkeypatch, capsys, name, steps, **kw):
    with_probe = _run_scenario(tmp_path, monkeypatch, capsys, name + "-p", steps, **kw)
    baseline = _run_scenario(tmp_path, monkeypatch, capsys, name + "-b", steps, baseline=True, **kw)
    assert "probe" in json.loads(with_probe.file) and "probe" not in json.loads(baseline.file)
    assert with_probe.code == baseline.code
    assert with_probe.timeouts == baseline.timeouts
    assert _without_probe(with_probe.file) == _without_probe(baseline.file)
    assert with_probe.stdout == with_probe.file and baseline.stdout == baseline.file  # file line == stdout line
    return with_probe, baseline


# name, steps, exit, code, type, timeouts, attempts as (start_ms, end_ms, outcome)
SCENARIOS = [
    ("success", [_step(0.05)], 0, None, None, [0.2], [(0.0, 50.0, "ok")]),
    ("timeout-then-ok", [_step(0.21, "timeout"), _step(0.05)], 0, None, None, [0.2, 0.19],
     [(0.0, 210.0, "timeout"), (210.0, 260.0, "ok")]),
    ("timeout-timeout", [_step(0.21, "timeout"), _step(0.15, "timeout")], 30, "OP_READ_UNAVAILABLE",
     "TimeoutExpired", [0.2, 0.19], [(0.0, 210.0, "timeout"), (210.0, 360.0, "timeout")]),
    ("timeout-with-output", [_step(0.21, "timeout", output=b"x")], 30, "OP_READ_UNAVAILABLE", "TimeoutExpired",
     [0.2], [(0.0, 210.0, "timeout")]),
    ("nonzero-rc", [_step(0.05, rc=5)], 30, "OP_KEY_READ_OR_FORMAT_FAILED", None, [0.2],
     [(0.0, 50.0, "nonzero_rc")]),
    ("bad-format", [_step(0.05, stdout="not-a-key\n")], 30, "OP_KEY_READ_OR_FORMAT_FAILED", None, [0.2],
     [(0.0, 50.0, "bad_format")]),
    ("oserror", [_step(0.0, "oserror")], 30, "OP_READ_UNAVAILABLE", "PermissionError", [0.2],
     [(0.0, 0.0, "exec_error")]),
    ("deadline-spent", [_step(0.45, "timeout")], 30, "OP_READ_UNAVAILABLE", "TimeoutExpired", [0.2],
     [(0.0, 450.0, "timeout")]),
]


@pytest.mark.parametrize("scenario", SCENARIOS, ids=[s[0] for s in SCENARIOS])
def test_probe_leaves_the_calls_the_retries_and_the_business_result_unchanged(tmp_path, monkeypatch, capsys, scenario):
    name, steps, exit_code, code, kind, timeouts, _ = scenario
    with_probe, _ = _assert_behavior_unchanged(tmp_path, monkeypatch, capsys, name, steps)
    line = json.loads(with_probe.file)
    assert with_probe.code == exit_code and line["exit"] == exit_code
    assert line.get("code") == code and line.get("type") == kind
    assert with_probe.timeouts == pytest.approx(timeouts)  # anchored on the pre-probe call pattern


@pytest.mark.parametrize("scenario", SCENARIOS, ids=[s[0] for s in SCENARIOS])
def test_probe_records_each_attempt_with_offsets_and_a_closed_outcome(tmp_path, monkeypatch, capsys, scenario):
    name, steps, _, _, _, _, attempts = scenario
    run = _run_scenario(tmp_path, monkeypatch, capsys, name, steps)
    probe = json.loads(run.file)["probe"]
    assert probe["v"] == 1 and probe["load1"] == 1.5 and "op_resident" not in probe and "probe_error" not in probe
    assert [key["name"] for key in probe["keys"]] == [MISSING]
    got = [(a["start_ms"], a["end_ms"], a["outcome"]) for a in probe["keys"][0]["attempts"]]
    assert [g[2] for g in got] == [a[2] for a in attempts]
    assert [g[:2] for g in got] == pytest.approx([a[:2] for a in attempts], abs=0.002)
    assert probe["tick_total_s"] == pytest.approx(attempts[-1][1] / 1000, abs=0.002)
    assert tick._probe_valid(probe) is True


def test_a_failed_key_does_not_hide_what_the_other_keys_did(tmp_path, monkeypatch, capsys):
    failing = REFERENCES["AIRAG_CONSUMER_KEY_HEX"]
    # one key fails at once; the other two only answer after it has failed
    script = {
        failing: [_step(0.0, "oserror")],
        REFERENCES["AIRAG_PROJECTION_KEY_HEX"]: [_step(0.0, stdout=KEYS["AIRAG_PROJECTION_KEY_HEX"] + "\n")],
        REFERENCES["AIRAG_ARCHIVE_KEY_HEX"]: [_step(0.0)],
    }
    run = _run_scenario(tmp_path, monkeypatch, capsys, "gate", [], scripted_by_reference=script,
                        env=base_environment(), gate=(failing, threading.Event(), threading.Semaphore(0)))
    line = json.loads(run.file)
    assert (line["exit"], line["code"], line["type"]) == (30, "OP_READ_UNAVAILABLE", "PermissionError")
    outcomes = {key["name"]: [a["outcome"] for a in key["attempts"]] for key in line["probe"]["keys"]}
    assert outcomes == {
        "AIRAG_CONSUMER_KEY_HEX": ["exec_error"], "AIRAG_PROJECTION_KEY_HEX": ["ok"], "AIRAG_ARCHIVE_KEY_HEX": ["ok"],
    }
    assert [k["name"] for k in line["probe"]["keys"]] == list(tick.NAMES)  # fixed order, one entry per key


def test_a_pre_call_failure_still_carries_a_full_normal_record(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, hooks) == tick.EXIT_CONFIG  # no credentials file, keys missing: `op` never reached
    line = json.loads((tmp_path / "logs" / "tick-20260927.log").read_text())
    assert line["code"] == "CREDENTIAL_SETTINGS_UNAVAILABLE"
    probe = line["probe"]
    assert probe["keys"] == [] and probe["v"] == 1 and set(probe) == {"v", "keys", "tick_total_s", "load1"}
    assert tick._probe_valid(probe) is True
    assert capsys.readouterr().out.strip() == json.dumps(line, sort_keys=True, separators=(",", ":"))


def test_keys_already_in_the_environment_record_no_op_attempts(tmp_path, monkeypatch, capsys):
    run = _run_scenario(tmp_path, monkeypatch, capsys, "present", [], env={**base_environment(), **KEYS})
    line = json.loads(run.file)
    assert line["exit"] == 0 and line["probe"]["keys"] == [] and run.timeouts == []


def test_a_skipped_overlapping_tick_still_carries_a_record(tmp_path, capsys):
    import fcntl

    item, hooks = synthetic_service(tmp_path)
    (tmp_path / "logs").mkdir(mode=0o700)
    held = os.open(tmp_path / "logs" / "tick.lock", os.O_RDWR | os.O_CREAT, 0o600)
    fcntl.flock(held, fcntl.LOCK_EX)
    try:
        assert run_tick(tmp_path, item, hooks, env={**base_environment(), **KEYS}) == tick.EXIT_SKIPPED
    finally:
        os.close(held)
    line = json.loads((tmp_path / "logs" / "tick-20260927.log").read_text())
    assert line["code"] == "PREVIOUS_TICK_RUNNING" and line["probe"]["keys"] == []


# --- closed schema ---------------------------------------------------------------------------------------------

NAME_A, NAME_B, NAME_C = tick.NAMES
GOOD = {
    "v": 1, "tick_total_s": 0.05, "load1": 1.5,
    "keys": [{"name": NAME_A, "attempts": [{"start_ms": 0.0, "end_ms": 50.0, "outcome": "ok"}]}],
}


def _attempt(**changes):
    return {"start_ms": 0.0, "end_ms": 50.0, "outcome": "ok", **changes}


def _with(**changes):
    return {**copy.deepcopy(GOOD), **changes}


def _with_attempts(*attempts):
    return _with(keys=[{"name": NAME_A, "attempts": list(attempts)}])


INVALID = {
    "four keys": _with(keys=[{"name": n, "attempts": [_attempt()]} for n in (*tick.NAMES, "OTHER_KEY_HEX")]),
    "duplicate name": _with(keys=[{"name": NAME_A, "attempts": [_attempt()]}] * 2),
    "name outside NAMES": _with(keys=[{"name": "op://vault/item", "attempts": [_attempt()]}]),
    "no attempts": _with(keys=[{"name": NAME_A, "attempts": []}]),
    "three attempts": _with_attempts(_attempt(), _attempt(), _attempt()),
    "negative start": _with_attempts(_attempt(start_ms=-0.001)),
    "nan end": _with_attempts(_attempt(end_ms=math.nan)),
    "inf end": _with_attempts(_attempt(end_ms=math.inf)),
    "end before start": _with_attempts(_attempt(start_ms=10.0, end_ms=9.999)),
    "outcome outside list": _with_attempts(_attempt(outcome="boom")),
    "int start": _with_attempts(_attempt(start_ms=5)),
    "bool start": _with_attempts(_attempt(start_ms=True)),
    "decimal end": _with_attempts(_attempt(end_ms=Decimal("50.0"))),
    "301 digit int": _with_attempts(_attempt(start_ms=10 ** 300, end_ms=10 ** 300)),
    "past the time range": _with_attempts(_attempt(end_ms=120000.001)),
    "v bool": _with(v=True),
    "v two": _with(v=2),
    "v float": _with(v=1.0),
    "extra top key": {**copy.deepcopy(GOOD), "extra": 1},
    "extra key item": _with(keys=[{"name": NAME_A, "attempts": [_attempt()], "ref": "x"}]),
    "extra attempt key": _with_attempts(_attempt(note="x")),
    "total over a day": _with(tick_total_s=86400.001),
    "total negative": _with(tick_total_s=-0.001),
    "total int": _with(tick_total_s=1),
    "load1 over": _with(load1=10000.01),
    "load1 int": _with(load1=2),
    "process count field": _with(op_resident=3),
    "process count null": _with(op_resident=None),
    "load1 null without reason": _with(load1=None),
    "process count reason": _with(probe_error=["op_resident_unavailable"]),
    "reason without null": _with(probe_error=["load_unavailable"]),
    "reason outside list": _with(load1=None, probe_error=["load_unavailable", "disk_full"]),
    "duplicate reason": _with(load1=None, probe_error=["load_unavailable", "load_unavailable"]),
    "reason not a list": _with(load1=None, probe_error="load_unavailable"),
    "missing total": {k: v for k, v in copy.deepcopy(GOOD).items() if k != "tick_total_s"},
}


def test_the_closed_schema_accepts_a_good_record_and_the_documented_variants():
    assert tick._probe_valid(copy.deepcopy(GOOD)) is True
    assert tick._probe_valid(_with(keys=[])) is True
    assert tick._probe_valid(_with(load1=None, probe_error=["load_unavailable"])) is True
    assert tick._probe_valid(_with(probe_error=["collect_failed"])) is True
    assert tick._probe_valid(_with_attempts(_attempt(outcome="timeout"), _attempt(start_ms=50.0, end_ms=120000.0))) is True
    for reason in ("collect_failed", "probe_invalid", "probe_too_large"):
        assert tick._probe_valid({"v": 1, "keys": [], "probe_error": [reason]}) is True


@pytest.mark.parametrize("label", list(INVALID))
def test_the_closed_schema_rejects_every_documented_violation(label):
    assert tick._probe_valid(INVALID[label]) is False


@pytest.mark.parametrize("record", [
    {"v": 1, "keys": [], "probe_error": ["load_unavailable"]},  # a minimal record only carries a recovery reason
    {"v": 1, "keys": [], "probe_error": ["probe_invalid", "collect_failed"]},
    {"v": 1, "keys": [], "probe_error": []},
    {"v": 1, "keys": [], "tick_total_s": 1.0, "probe_error": ["probe_invalid"]},
    {"v": 1, "keys": [{"name": NAME_A, "attempts": [_attempt()]}], "probe_error": ["probe_invalid"]},
])
def test_a_minimal_record_is_exactly_version_empty_keys_and_one_recovery_reason(record):
    assert tick._probe_valid(record) is False


def test_raw_values_are_checked_before_rounding():
    # round() would turn these out-of-range values into -0.0 / the exact limit, so a post-round check lets them in
    def probe_for(state, total):
        return tick._probe_for_line(state, total)

    bad = {"v": 1, "keys": [], "probe_error": ["probe_invalid"]}
    for attempt in [(-0.0004, 10.0, "ok"), (0.0, 120000.0001, "ok"), (5, 10.0, "ok"), (True, 10.0, "ok"),
                    (Decimal("1"), 10.0, "ok"), (0.0, math.inf, "ok"), (math.nan, 1.0, "ok")]:
        state = tick._ProbeState(0.0)
        state.attempts = {NAME_A: [attempt]}
        assert probe_for(state, 1.0) == bad, attempt
    for total in (-0.0004, 86400.0004, math.nan, math.inf, 3, True, None):
        state = tick._ProbeState(0.0)
        assert probe_for(state, total) == bad, total
    for load in (-0.004, 10000.004, math.nan, math.inf, 2, True, "1.0"):
        state = tick._ProbeState(0.0)
        state.load1 = load
        record = probe_for(state, 1.0)
        assert record["load1"] is None and record["probe_error"] == ["load_unavailable"], load


def test_values_are_rounded_once_when_the_record_is_made():
    state = tick._ProbeState(0.0)
    state.load1 = 1.23456
    state.attempts = {NAME_B: [(12.3456, 20.00049, "timeout")]}
    probe = tick._probe_for_line(state, 0.123456)
    assert probe["load1"] == 1.23 and probe["tick_total_s"] == 0.123
    assert probe["keys"] == [{"name": NAME_B, "attempts": [{"start_ms": 12.346, "end_ms": 20.0, "outcome": "timeout"}]}]


def test_collection_failures_become_null_fields_with_a_reason_and_keep_the_record():
    state = tick._ProbeState(0.0)
    state.failed = True  # an attempt record could not be taken
    record = tick._probe_for_line(state, 1.0)
    assert record["load1"] is None and "op_resident" not in record
    assert record["probe_error"] == ["load_unavailable", "collect_failed"]
    assert tick._probe_valid(record) is True


# --- size ---------------------------------------------------------------------------------------------------

def _worst_state(*, with_errors):
    state = tick._ProbeState(0.0)
    state.attempts = {name: [(119999.0004, 119999.9996, "nonzero_rc")] * 2 for name in tick.NAMES}
    state.load1, state.failed = (None, True) if with_errors else (9999.9949, False)
    return state


@pytest.mark.parametrize("with_errors", [True, False])
def test_the_worst_probe_stays_inside_one_kilobyte(with_errors):
    probe = tick._probe_for_line(_worst_state(with_errors=with_errors), 86399.9996)
    assert len(probe["keys"]) == 3 and all(len(k["attempts"]) == 2 for k in probe["keys"])
    assert tick._probe_valid(probe) is True
    assert len(tick._probe_text(probe).encode()) <= tick.PROBE_MAX_BYTES == 1024


def test_an_accepted_record_with_every_reason_still_fits():
    record = _with(load1=None, keys=[
        {"name": n, "attempts": [_attempt(start_ms=119999.999, end_ms=120000.0, outcome="nonzero_rc")] * 2}
        for n in tick.NAMES
    ], probe_error=["load_unavailable", "collect_failed", "probe_invalid", "probe_too_large"])
    assert tick._probe_valid(record) is True and len(tick._probe_text(record).encode()) <= 1024


def test_a_huge_summary_is_never_cut_and_the_line_grows_by_the_probe_only(tmp_path, monkeypatch, capsys):
    huge = 10 ** 400
    frame = {"exit": 0, "summary": {"sources": huge, "accepted": huge + 1}, "code": "", "type": ""}
    mutate = lambda m: m.setattr(tick, "_run_component", lambda *a, **k: frame)  # noqa: E731
    env = {**base_environment(), **KEYS}
    with_probe = _run_scenario(tmp_path, monkeypatch, capsys, "huge-p", [], env=env, mutate=mutate)
    baseline = _run_scenario(tmp_path, monkeypatch, capsys, "huge-b", [], env=env, mutate=mutate, baseline=True)
    line, base = json.loads(with_probe.file), json.loads(baseline.file)
    assert line["summary"]["sources"] == huge and line["summary"]["accepted"] == huge + 1
    assert _without_probe(with_probe.file) == base and with_probe.code == baseline.code == 0
    probe_text = tick._probe_text(line["probe"])
    assert len(probe_text.encode()) <= 1024
    growth = len(with_probe.file.encode()) - len(baseline.file.encode())
    assert growth == len(',"probe":') + len(probe_text.encode()) <= 1033


# --- recovery chain (mutations) ---------------------------------------------------------------------------------

SUCCESS_STEPS = [_step(0.05)]


def _chain_run(tmp_path, monkeypatch, capsys, name, mutate):
    with_probe, baseline = _assert_behavior_unchanged(tmp_path, monkeypatch, capsys, name, SUCCESS_STEPS, mutate=mutate)
    return with_probe, baseline


def _bad_schema(*args, **kwargs):
    return _with(keys=[{"name": n, "attempts": [_attempt()]} for n in (*tick.NAMES, "OTHER_KEY_HEX")])


@pytest.mark.parametrize("label,mutate,reason", [
    ("schema violation", lambda m: m.setattr(tick, "_make_probe", _bad_schema), "probe_invalid"),
    ("oversize", lambda m: m.setattr(tick, "PROBE_MAX_BYTES", 100), "probe_too_large"),
    ("build exception", lambda m: m.setattr(tick, "_make_probe", _boom), "collect_failed"),
])
def test_a_failed_probe_falls_back_to_the_minimal_record(tmp_path, monkeypatch, capsys, label, mutate, reason):
    with_probe, _ = _chain_run(tmp_path, monkeypatch, capsys, label.replace(" ", "-"), mutate)
    assert json.loads(with_probe.file)["probe"] == {"v": 1, "keys": [], "probe_error": [reason]}


def test_a_serialization_failure_of_the_full_record_falls_back_to_the_minimal_record(tmp_path, monkeypatch, capsys):
    real = tick._probe_text

    def text(record):
        if "tick_total_s" in record:
            raise ValueError("injected")
        return real(record)

    with_probe, _ = _chain_run(tmp_path, monkeypatch, capsys, "serialize", lambda m: m.setattr(tick, "_probe_text", text))
    assert json.loads(with_probe.file)["probe"] == {"v": 1, "keys": [], "probe_error": ["collect_failed"]}


def test_when_even_the_minimal_record_fails_the_line_is_the_pre_probe_line_byte_for_byte(tmp_path, monkeypatch, capsys):
    def mutate(m):
        m.setattr(tick, "_make_probe", _boom)
        m.setattr(tick, "_minimal_probe", _boom)

    with_probe = _run_scenario(tmp_path, monkeypatch, capsys, "last-p", SUCCESS_STEPS, mutate=mutate)
    baseline = _run_scenario(tmp_path, monkeypatch, capsys, "last-b", SUCCESS_STEPS, baseline=True)
    assert _masked(with_probe.file) == _masked(baseline.file)
    assert _masked(with_probe.stdout) == _masked(baseline.stdout)
    assert "probe" not in with_probe.file and with_probe.code == baseline.code == 0


def test_the_recovery_chain_ends_in_none_not_in_an_exception(monkeypatch):
    monkeypatch.setattr(tick, "_make_probe", _boom)
    monkeypatch.setattr(tick, "_minimal_probe", _boom)
    assert tick._probe_for_line(tick._ProbeState(0.0), 1.0) is None


def test_a_failing_load_collection_changes_nothing_but_the_probe_fields(tmp_path, monkeypatch, capsys):
    load_run, _ = _assert_behavior_unchanged(tmp_path, monkeypatch, capsys, "load", SUCCESS_STEPS,
                                             mutate=lambda m: m.setattr(os, "getloadavg", _boom))
    probe = json.loads(load_run.file)["probe"]
    assert probe["load1"] is None and probe["probe_error"] == ["load_unavailable"] and "op_resident" not in probe


def test_a_tick_starts_no_process_listing(tmp_path, monkeypatch, capsys):
    # the process-count field was dropped: its whole collection (spawn, reap, parse) could not be bounded to 1.0 s
    made = []
    real = subprocess.Popen

    class Spy(real):
        def __init__(self, argv, *args, **kwargs):
            made.append(os.path.basename(str(argv[0])))
            super().__init__(argv, *args, **kwargs)

    _run_scenario(tmp_path, monkeypatch, capsys, "nops", SUCCESS_STEPS, mutate=lambda m: m.setattr(subprocess, "Popen", Spy))
    assert "ps" not in made and not hasattr(tick, "_count_resident_op") and not hasattr(tick, "PROBE_COLLECT_TIMEOUT_S")


def test_a_failing_attempt_recorder_changes_nothing_but_the_probe_fields(tmp_path, monkeypatch, capsys):
    def mutate(m):
        m.setattr(tick._ProbeState, "record", _boom)

    with_probe, _ = _assert_behavior_unchanged(tmp_path, monkeypatch, capsys, "recorder", [_step(0.21, "timeout"), _step(0.05)],
                                               mutate=mutate)
    probe = json.loads(with_probe.file)["probe"]
    assert probe["keys"] == [] and probe["probe_error"] == ["collect_failed"]


# --- rule 12 limits --------------------------------------------------------------------------------------------

def test_op_limits_are_the_cli_rule_values_with_the_startup_cost():
    assert (tick.OP_ATTEMPT_TIMEOUT_S, tick.OP_CALL_DEADLINE_S) == (10.5, 21.0)
    assert tick.OP_CALL_DEADLINE_S <= 70
    source = Path(tick.__file__).read_text(encoding="utf-8")
    assert "규칙 12 CLI: 기동 고정비 3.5(잠정) + 7.0 / 재시도 포함 총 21.0 ≤ 70" in source
    for line in source.splitlines():
        if re.match(r"\s*OP_(ATTEMPT_TIMEOUT|CALL_DEADLINE)_S\s*=", line):
            assert not re.search(r"\b(70|600|300)(\.0)?\b", line.split("#")[0]), line


def _real_limit_run(tmp_path, monkeypatch, capsys, name, steps):
    return _run_scenario(tmp_path, monkeypatch, capsys, name, steps, limits=None)


def test_the_second_attempt_gets_the_remaining_deadline_when_it_is_shorter(tmp_path, monkeypatch, capsys):
    attempt, deadline = tick.OP_ATTEMPT_TIMEOUT_S, tick.OP_CALL_DEADLINE_S
    spent = attempt * 1.2  # more than one attempt, so less than a full attempt is left
    run = _real_limit_run(tmp_path, monkeypatch, capsys, "second", [_step(spent, "timeout"), _step(1.0, "timeout")])
    assert len(run.timeouts) == 2 and run.timeouts[0] == attempt
    assert run.timeouts[1] == pytest.approx(min(attempt, deadline - spent))
    assert json.loads(run.file)["code"] == "OP_READ_UNAVAILABLE"


def test_the_second_attempt_gets_a_full_attempt_when_the_deadline_leaves_room(tmp_path, monkeypatch, capsys):
    attempt = tick.OP_ATTEMPT_TIMEOUT_S
    run = _real_limit_run(tmp_path, monkeypatch, capsys, "room", [_step(attempt * 0.1, "timeout"), _step(0.1, "timeout")])
    assert run.timeouts == pytest.approx([attempt, attempt])


def test_no_retry_once_the_call_deadline_is_spent(tmp_path, monkeypatch, capsys):
    run = _real_limit_run(tmp_path, monkeypatch, capsys, "spent", [_step(tick.OP_CALL_DEADLINE_S + 0.5, "timeout")])
    assert len(run.timeouts) == 1 and json.loads(run.file)["code"] == "OP_READ_UNAVAILABLE"


def test_no_retry_after_output_and_never_a_third_attempt(tmp_path, monkeypatch, capsys):
    loud = _real_limit_run(tmp_path, monkeypatch, capsys, "loud", [_step(1.0, "timeout", output=b"x")])
    assert len(loud.timeouts) == 1
    never = _real_limit_run(tmp_path, monkeypatch, capsys, "never", [_step(0.1, "timeout")] * 5)
    assert len(never.timeouts) == 2
    assert [len(k["attempts"]) for k in json.loads(never.file)["probe"]["keys"]] == [2]


# --- retry budget is computed from the current time, as before the probe -----------------------------------------

def _direct_read(module, tmp_path, monkeypatch, *, limits, first_takes, classify_delay=0.0, record_delay=0.0):
    """`load_keys` of ``module`` with one key missing: a scripted first silent timeout, then a good answer."""
    now = [1000.0]
    timeouts: list[float] = []
    work = tmp_path / module.__name__.replace(".", "-")
    work.mkdir()
    op, _ = stub_op(work)
    creds = credentials(work, op)
    with monkeypatch.context() as m:
        m.setattr(module, "time", types.SimpleNamespace(monotonic=lambda: now[0]))
        m.setattr(module, "OP_ATTEMPT_TIMEOUT_S", limits[0])
        m.setattr(module, "OP_CALL_DEADLINE_S", limits[1])
        real_clean = module._clean_type

        def clean(value):  # error classification takes time
            now[0] += classify_delay
            return real_clean(value)

        m.setattr(module, "_clean_type", clean)
        if record_delay and hasattr(module, "_note_attempt"):
            real_note = module._note_attempt

            def note(*args, **kwargs):  # recording an attempt takes time
                now[0] += record_delay
                return real_note(*args, **kwargs)

            m.setattr(module, "_note_attempt", note)

        def run(argv, **kwargs):
            timeouts.append(kwargs["timeout"])
            if len(timeouts) == 1:
                now[0] += first_takes
                raise subprocess.TimeoutExpired(argv, kwargs["timeout"])
            now[0] += 0.01
            return types.SimpleNamespace(returncode=0, stdout=GOOD_KEY + "\n", stderr="")

        m.setattr(subprocess, "run", run)
        try:
            module.load_keys(_one_key_missing_env(), creds)
            outcome = "ok"
        except module.TickError as error:
            outcome = (error.exit_code, error.code, error.kind)
    return timeouts, outcome


@pytest.mark.parametrize("limits,first_takes", [((7.0, 14.0), 13.9), ((10.5, 21.0), 20.9)])
def test_a_retry_is_refused_when_classification_time_spends_the_deadline(tmp_path, monkeypatch, limits, first_takes):
    base = _direct_read(baseline, tmp_path, monkeypatch, limits=limits, first_takes=first_takes, classify_delay=0.2)
    now = _direct_read(tick, tmp_path, monkeypatch, limits=limits, first_takes=first_takes, classify_delay=0.2)
    assert base == ([limits[0]], (30, "OP_READ_UNAVAILABLE", "TimeoutExpired"))  # the pre-probe behavior
    assert now == base


@pytest.mark.parametrize("limits,first_takes", [((7.0, 14.0), 5.0), ((10.5, 21.0), 12.0)])
def test_the_retry_timeout_matches_the_pre_probe_value_when_there_is_room(tmp_path, monkeypatch, limits, first_takes):
    base = _direct_read(baseline, tmp_path, monkeypatch, limits=limits, first_takes=first_takes, classify_delay=0.2)
    now = _direct_read(tick, tmp_path, monkeypatch, limits=limits, first_takes=first_takes, classify_delay=0.2)
    assert len(base[0]) == 2 and base[1] == "ok"
    assert now == base


@pytest.mark.parametrize("limits,first_takes", [((7.0, 14.0), 13.9), ((10.5, 21.0), 20.9)])
def test_a_retry_is_refused_when_recording_time_spends_the_deadline(tmp_path, monkeypatch, limits, first_takes):
    timeouts, outcome = _direct_read(tick, tmp_path, monkeypatch, limits=limits, first_takes=first_takes, record_delay=0.2)
    assert timeouts == [limits[0]] and outcome == (30, "OP_READ_UNAVAILABLE", "TimeoutExpired")


# --- the last serialization is part of the recovery chain ---------------------------------------------------------

def _compose_spy(order, fail_kinds):
    real = tick._compose

    def compose(payload, record):
        kind = "normal" if "tick_total_s" in record else "minimal"
        order.append(kind)
        if kind in fail_kinds:
            raise ValueError("injected final serialization failure")
        return real(payload, record)

    return compose


def test_a_failed_final_serialization_of_the_normal_probe_steps_down_to_the_minimal_probe(tmp_path, monkeypatch, capsys):
    order: list[str] = []
    with_probe, _ = _assert_behavior_unchanged(
        tmp_path, monkeypatch, capsys, "compose", SUCCESS_STEPS,
        mutate=lambda m: m.setattr(tick, "_compose", _compose_spy(order, {"normal"})),
    )
    assert order == ["normal", "minimal"]
    assert json.loads(with_probe.file)["probe"] == {"v": 1, "keys": [], "probe_error": ["collect_failed"]}


def test_when_the_minimal_probe_cannot_be_serialized_either_the_pre_probe_line_is_written(tmp_path, monkeypatch, capsys):
    order: list[str] = []
    both = lambda m: m.setattr(tick, "_compose", _compose_spy(order, {"normal", "minimal"}))  # noqa: E731
    with_probe = _run_scenario(tmp_path, monkeypatch, capsys, "compose2-p", SUCCESS_STEPS, mutate=both)
    baseline_run = _run_scenario(tmp_path, monkeypatch, capsys, "compose2-b", SUCCESS_STEPS, baseline=True)
    assert order == ["normal", "minimal"]
    assert _masked(with_probe.file) == _masked(baseline_run.file)
    assert _masked(with_probe.stdout) == _masked(baseline_run.stdout)
    assert with_probe.code == baseline_run.code == 0
