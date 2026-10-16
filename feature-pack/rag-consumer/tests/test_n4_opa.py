"""Synthetic scenarios of N4 (design arch-20261016-opa-popup-design-r10 §4 + the three implementation conditions of
da-20261016-sol-opa-design-r10): the launchd probe run with only ``op --version`` (P4 + P0, no token), once with
``ProcessType=Background`` and once without the key, in the order Background -> unset -> Background.

Everything is synthetic: a fake ``op`` / ``launchctl`` / ``log``, synthetic result files written by fake tools, fake
clocks. No real op, no real launchctl, no real taskpolicy, no network, no operating file, no token file.
"""

from __future__ import annotations

import importlib.util
import itertools
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import time

import pytest

from test_chain_opa import CHAIN_SH, FAKE_TOOL, ChainSandbox, as_text, load_chain, probe_doc, step
from test_probe_opa import OPS, PROBE_PY, PROBE_SH, TOKEN, Sandbox, alive, load_probe, recorded_pids, wait_until

P0_ARGS = ("--p0-only",)
P_NAMES = {"N4-A1": "20261016-100000-111-222", "N4-B": "20261016-100100-111-223",
           "N4-A2": "20261016-100200-111-224"}
STAGES = tuple(P_NAMES)
EXPECT = {"N4-A1": True, "N4-B": False, "N4-A2": True}

# The default (full) probe as it is at HEAD before N4: the part of job.plist before the environment block, and the
# report with the numbers made neutral (golden, design §4.7-10).
GOLDEN_PLIST_HEAD = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.airag.probe-opa-<ID></string>
  <key>ProgramArguments</key>
  <array>
    <string><PY></string>
    <string>-I</string>
    <string><OPS>/probe.py</string>
    <string>--run</string>
    <string><DIR></string>
    <string>--mode</string>
    <string>selftest</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>/dev/null</string>
  <key>StandardErrorPath</key>
  <string>/dev/null</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/bin:/bin:/usr/sbin:/sbin</string>
"""
PT_LINES = "  <key>ProcessType</key>\n  <string>Background</string>\n"
GOLDEN_REPORT = """== 1Password 연결 점검 프로브 결과 (후보 축소일 뿐 — 변경 보류가 기본, 진단 성공은 운영 재개 승인이 아님) ==
mode=selftest
S0: consumer disabled=true loaded=false op 프로세스=N
P4: success tcc=- Nms
P0: success tcc=none_logged_ok Nms
P2: success tcc=none_logged_ok Nms
P1: success tcc=none_logged_ok Nms
P1b: success tcc=none_logged_ok Nms
결론: no_repro_twice — 이번 시점 재현 없음(2회) — 팝업 부재 보증 아님, 변경 보류, S2
공통: consumer 는 disabled 유지
결과 파일: <DIR>/result.json
"""
PROFILE_KEYS = {"profile_version", "profile", "process_type_set", "load_before", "load_after"}


def neutral(text: str, sb: Sandbox) -> str:
    directory = sb.probe_dir()
    text = text.replace(str(directory), "<DIR>").replace(directory.name, "<ID>").replace(str(OPS), "<OPS>")
    text = text.replace(sys.executable, "<PY>").replace(str(sb.root), "<TMP>")
    return re.sub(r"op 프로세스=\d+", "op 프로세스=N", re.sub(r"\d+ms", "Nms", text))


def plist_of(sb: Sandbox) -> dict:
    return plistlib.loads((sb.probe_dir() / "job.plist").read_bytes())


def profile_of(sb: Sandbox) -> dict:
    return json.loads((sb.probe_dir() / "profile.json").read_text(encoding="utf-8"))


def valid_profile_doc(process_type_set: bool = True, **over) -> dict:
    doc = {"profile_version": 1, "profile": "p0only", "process_type_set": process_type_set,
           "load_before": [1.5, 2.0, 2.5], "load_after": [1.6, 2.0, 2.5]}
    doc.update(over)
    return doc


# ======================================================================================================== N4 worker
def test_p0only_runs_p4_and_p0_and_never_the_account_steps(tmp_path):
    sb = Sandbox(tmp_path)
    probe = load_probe()
    proc = sb.run(*P0_ARGS)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    result = sb.result()
    assert probe.validate_result(result) and result["complete"] is True and result["aborted_class"] is None
    by = {s["step"]: s for s in result["steps"]}
    assert list(by) == ["P4", "P0", "P2", "P1", "P1b"]
    assert by["P4"]["status"] == "success" and by["P0"]["status"] == "success"
    for name in ("P2", "P1", "P1b"):
        assert by[name]["status"] == "skipped_not_applicable" and by[name]["child_pid"] is None
        assert by[name]["account_type_confirmed"] is None
    assert result["conclusion"] == "cause_unconfirmed" and sb.loaded() == []
    assert sb.opcalls.read_text().splitlines() and len(sb.opcalls.read_text().splitlines()) == 1
    assert sb.opcalls.read_text().startswith("--version TOK= ")


def test_a_p0only_timeout_is_a_valid_v1_result_too(tmp_path):
    sb = Sandbox(tmp_path)
    sb.op = sb.make_op(version_pre="sleep 10")
    sb.extra["PROBE_OP_BIN"] = str(sb.op)
    proc = sb.run(*P0_ARGS)
    result = sb.result()
    assert load_probe().validate_result(result) and result["complete"] is True
    by = {s["step"]: s for s in result["steps"]}
    assert by["P0"]["status"] == "timeout" and by["P0"]["reaped"] is True
    assert [by[n]["status"] for n in ("P2", "P1", "P1b")] == ["skipped_not_applicable"] * 3
    assert result["conclusion"] == "p0_blocked" and proc.returncode == 0
    assert (sb.probe_dir() / "profile.json").exists() and sb.loaded() == []


@pytest.mark.parametrize("args,expected_set", [
    (("--p0-only",), True), (("--p0-only", "--process-type", "background"), True),
    (("--p0-only", "--process-type", "unset"), False)])
def test_the_process_type_reaches_the_worker_plist_and_profile(tmp_path, args, expected_set):
    sb = Sandbox(tmp_path)
    assert sb.run(*args).returncode == 0
    document = plist_of(sb)
    if expected_set:
        assert document["ProcessType"] == "Background"
    else:
        assert "ProcessType" not in document and "<key>ProcessType</key>" not in (
            sb.probe_dir() / "job.plist").read_text()
    wanted = ["--p0-only", "--process-type-set", "true" if expected_set else "false"]
    assert document["ProgramArguments"][-3:] == wanted and document["ProgramArguments"][-5:-3] == [
        "--mode", "selftest"]
    profile = profile_of(sb)
    assert set(profile) == PROFILE_KEYS and profile["profile"] == "p0only" and profile["profile_version"] == 1
    assert profile["process_type_set"] is expected_set


def test_only_the_process_type_lines_and_value_differ_between_the_two_profiles(tmp_path):
    texts = {}
    for kind in ("background", "unset"):
        (tmp_path / kind).mkdir()
        sb = Sandbox(tmp_path / kind)
        assert sb.run("--p0-only", "--process-type", kind).returncode == 0
        texts[kind] = neutral((sb.probe_dir() / "job.plist").read_text(), sb).split("<key>EnvironmentVariables")[0]
    background = texts["background"]
    assert PT_LINES in background and PT_LINES not in texts["unset"]
    assert background.replace(PT_LINES, "").replace("<string>true</string>", "<string>false</string>") == \
        texts["unset"]


def test_profile_json_is_closed_private_and_written_atomically(tmp_path):
    sb = Sandbox(tmp_path)
    sb.run(*P0_ARGS)
    path = sb.probe_dir() / "profile.json"
    assert path.stat().st_mode & 0o777 == 0o600 and not (sb.probe_dir() / "profile.json.tmp").exists()
    profile = json.loads(path.read_text())
    assert set(profile) == PROFILE_KEYS
    for key in ("load_before", "load_after"):
        value = profile[key]
        assert value is None or (len(value) == 3 and all(
            type(x) in (int, float) and 0 <= x < 10000 for x in value))
    assert TOKEN not in path.read_text()


def test_the_load_is_rounded_and_an_unreadable_load_is_null(monkeypatch):
    monkeypatch.setattr(sys, "argv", ["probe.py", "--mode", "selftest"])
    probe = load_probe()
    values = iter([(1.234, 2.0, 3.0), (4.0, 5.0, 6.999)])
    monkeypatch.setattr(probe.os, "getloadavg", lambda: next(values))
    assert probe.load_triplet() == [1.23, 2.0, 3.0]
    assert probe.load_triplet() == [4.0, 5.0, 7.0]
    for bad in (OSError("no"), (float("nan"), 1.0, 1.0), (float("inf"), 1.0, 1.0), (-0.5, 1.0, 1.0),
                (10000.0, 1.0, 1.0)):
        def broken(bad=bad):
            if isinstance(bad, Exception):
                raise bad
            return bad
        monkeypatch.setattr(probe.os, "getloadavg", broken)
        assert probe.load_triplet() is None, bad


def test_the_load_before_comes_before_the_op_call_and_the_load_after_comes_after_it(monkeypatch, tmp_path):
    sb = Sandbox(tmp_path)
    for key, value in sb.env().items():
        monkeypatch.setenv(key, value)
    directory = tmp_path / "run"
    directory.mkdir()
    monkeypatch.setattr(sys, "argv", ["probe.py", "--run", str(directory), "--mode", "selftest", "--p0-only",
                                      "--process-type-set", "true"])
    probe = load_probe()
    calls = []

    def fake_load():
        calls.append(len(sb.opcalls.read_text().splitlines()) if sb.opcalls.exists() else 0)
        return (0.5 + len(calls), 1.0, 1.0)
    monkeypatch.setattr(probe.os, "getloadavg", fake_load)
    probe.execute(directory)
    assert calls == [0, 1]
    profile = json.loads((directory / "profile.json").read_text())
    assert profile["load_before"][0] == 1.5 and profile["load_after"][0] == 2.5


def test_the_profile_is_complete_before_the_result_says_complete(tmp_path):
    """DA note 1: the wrapper starts to take its job down as soon as result.json says complete=true, so the final
    profile.json must already be there (an atomic tmp -> rename) at that moment."""
    sb = Sandbox(tmp_path)
    directory = tmp_path / "run"
    directory.mkdir()
    env = sb.env(PROBE_P0_PROFILE_DELAY="1.5")
    proc = subprocess.Popen([sys.executable, "-I", str(PROBE_PY), "--run", str(directory), "--mode", "selftest",
                             "--p0-only", "--process-type-set", "true"], env=env, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    saw_waiting, violations = False, []
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        result_path, profile_path = directory / "result.json", directory / "profile.json"
        complete = False
        if result_path.exists():
            try:
                complete = json.loads(result_path.read_text()).get("complete") is True
            except ValueError:
                complete = False
        if profile_path.exists():
            try:
                assert set(json.loads(profile_path.read_text())) == PROFILE_KEYS   # never a partial file
            except ValueError:
                violations.append("partial profile")
        if complete and not profile_path.exists():
            violations.append("complete before profile")
        if result_path.exists() and not complete and not profile_path.exists():
            saw_waiting = True
        if proc.poll() is not None:
            break
        time.sleep(0.02)
    proc.wait(timeout=30)
    assert violations == [] and saw_waiting
    assert json.loads((directory / "result.json").read_text())["complete"] is True


def _worker_with_wrapped_writes(monkeypatch, tmp_path, *, op_kind="success"):
    """Run the p0only worker in this process with every write_json_atomic call wrapped: at each publication of
    result.json with complete=true, note whether profile.json already exists and is the closed, valid document."""
    sb = Sandbox(tmp_path)
    if op_kind == "timeout":
        sb.op = sb.make_op(version_pre="sleep 10")
        sb.extra["PROBE_OP_BIN"] = str(sb.op)
    for key, value in sb.env().items():
        monkeypatch.setenv(key, value)
    directory = tmp_path / "run"
    directory.mkdir()
    monkeypatch.setattr(sys, "argv", ["probe.py", "--run", str(directory), "--mode", "selftest", "--p0-only",
                                      "--process-type-set", "true"])
    probe = load_probe()
    original = probe.write_json_atomic
    seen = {"complete": [], "writes": []}

    def wrapped(path, document):
        name = Path(path).name
        seen["writes"].append(name)
        if name == "result.json" and document.get("complete") is True:
            try:
                profile = json.loads((directory / "profile.json").read_text())
                seen["complete"].append(set(profile) == PROFILE_KEYS and profile["profile"] == "p0only")
            except (OSError, ValueError):
                seen["complete"].append(False)
        return original(path, document)
    monkeypatch.setattr(probe, "write_json_atomic", wrapped)
    probe.execute(directory)
    return seen, directory


@pytest.mark.parametrize("op_kind", ["success", "timeout"])
def test_every_complete_publication_finds_a_finished_profile_already_there(monkeypatch, tmp_path, op_kind):
    """DA r1 minor 2: no sleep, no polling — the moment of the complete=true write is looked at directly."""
    seen, directory = _worker_with_wrapped_writes(monkeypatch, tmp_path, op_kind=op_kind)
    assert seen["complete"] == [True]                  # exactly one complete publication, and the profile was there
    assert seen["writes"].index("profile.json") < len(seen["writes"]) - 1
    assert seen["writes"][-1] == "result.json"         # the last write of the run is the completion itself
    assert json.loads((directory / "result.json").read_text())["complete"] is True


def test_the_wrapper_does_not_take_the_job_down_before_the_profile_exists(tmp_path):
    sb = Sandbox(tmp_path)
    proc = sb.run(*P0_ARGS, PROBE_P0_PROFILE_DELAY="2")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert set(profile_of(sb)) == PROFILE_KEYS and sb.result()["complete"] is True and sb.loaded() == []


# --------------------------------------------------------------------------------------- the sentinel (no token)
@pytest.mark.parametrize("op_kind", ["success", "timeout"])
def test_p0only_never_reads_the_token_file_in_process(monkeypatch, tmp_path, op_kind):
    sb = Sandbox(tmp_path)
    if op_kind == "timeout":
        sb.op = sb.make_op(version_pre="sleep 10")
        sb.extra["PROBE_OP_BIN"] = str(sb.op)
    for key, value in sb.env().items():
        monkeypatch.setenv(key, value)
    directory = tmp_path / "run"
    directory.mkdir()
    monkeypatch.setattr(sys, "argv", ["probe.py", "--run", str(directory), "--mode", "selftest", "--p0-only",
                                      "--process-type-set", "false"])
    probe = load_probe()
    reads = []
    original = Path.read_text

    def audited(self, *args, **kwargs):
        reads.append(str(self))
        return original(self, *args, **kwargs)
    monkeypatch.setattr(Path, "read_text", audited)

    def boom(*args, **kwargs):
        raise AssertionError("read_token was called")
    monkeypatch.setattr(probe, "read_token", boom)
    probe.execute(directory)
    assert str(sb.token_file) not in reads and not [r for r in reads if "op-sa-token" in r]
    result = json.loads((directory / "result.json").read_text())
    assert result["complete"] is True and result["aborted_class"] is None
    assert {s["step"]: s["status"] for s in result["steps"]}["P0"] == ("success" if op_kind == "success" else "timeout")


@pytest.mark.parametrize("op_kind", ["success", "timeout"])
def test_p0only_end_to_end_has_no_sentinel_anywhere_and_no_account_call(tmp_path, op_kind):
    sb = Sandbox(tmp_path)
    if op_kind == "timeout":
        sb.op = sb.make_op(version_pre="sleep 10")
        sb.extra["PROBE_OP_BIN"] = str(sb.op)
    proc = sb.run(*P0_ARGS)
    assert proc.returncode == 0
    calls = sb.opcalls.read_text().splitlines()
    assert len(calls) == 1 and calls[0].startswith("--version TOK= ") and "CFG=none" in calls[0]
    names = set(sb.envnames.read_text().split())
    assert "OP_SERVICE_ACCOUNT_TOKEN" not in names and "OP_CONFIG_DIR" not in names
    assert TOKEN not in sb.tree_text(proc)
    assert not (sb.home / ".local" / "share" / "airag" / "op-home").exists()   # the dedicated home was never made


def test_the_p0only_branch_has_no_token_signal_or_group_code():
    probe = load_probe()
    import inspect
    source = inspect.getsource(probe.run_p0only)
    for forbidden in ("read_token", "token", "OP_SERVICE_ACCOUNT_TOKEN", "os.kill", "killpg", "pkill", "dedicated_home",
                      "account"):
        assert forbidden not in source, forbidden
    shell = PROBE_SH.read_text(encoding="utf-8")
    assert "pkill" not in shell and "killall" not in shell and "kill -9" not in shell


# ------------------------------------------------------------------------------------------ argument errors (11)
@pytest.mark.parametrize("args", [
    ("--process-type", "unset"), ("--process-type", "background"), ("--p0-only", "--process-type", "weird"),
    ("--p0-only", "--process-type"), ("--p0-only", "--process-type", ""), ("--p0-only", "--p0-only-typo")])
def test_a_bad_wrapper_argument_ends_with_two_before_anything_is_registered(tmp_path, args):
    sb = Sandbox(tmp_path)
    proc = sb.run(*args)
    assert proc.returncode == 2, proc.stdout + proc.stderr
    assert not any(c.startswith(("bootstrap", "bootout", "print gui/")) for c in sb.lc_calls())
    assert not sb.opcalls.exists() and not (sb.base.exists() and any(sb.base.iterdir()))
    assert sb.loaded() == []


@pytest.mark.parametrize("args", [
    ["--run", "<D>", "--mode", "selftest", "--p0-only"],
    ["--run", "<D>", "--mode", "selftest", "--process-type-set", "true"],
    ["--run", "<D>", "--mode", "selftest", "--p0-only", "--process-type-set", "maybe"],
    ["--run", "<D>", "--mode", "selftest", "--p0-only", "--process-type-set"],
    ["--report", "<D>", "--mode", "selftest", "--p0-only", "--process-type-set", "true"],
    ["--close-timeout", "<D>", "--mode", "selftest", "--p0-only", "--process-type-set", "true"],
    ["--list-pids", "<D>", "--mode", "selftest", "--p0-only", "--process-type-set", "true"],
    ["--validate", "<D>/x.json", "--mode", "selftest", "--p0-only", "--process-type-set", "true"],
    ["--p4-worker", "localhost", "1", "1", "--mode", "selftest", "--p0-only", "--process-type-set", "true"],
])
def test_the_worker_refuses_misplaced_p0only_arguments_and_runs_nothing(tmp_path, args):
    sb = Sandbox(tmp_path)
    directory = tmp_path / "d"
    directory.mkdir()
    argv = [a.replace("<D>", str(directory)) for a in args]
    done = subprocess.run([sys.executable, "-I", str(PROBE_PY), *argv], env=sb.env(), capture_output=True, text=True,
                          timeout=30)
    assert done.returncode == 2, (argv, done.stdout, done.stderr)
    assert not any(directory.iterdir()) and done.stdout == ""
    assert not sb.opcalls.exists()


def test_the_default_probe_still_accepts_no_p0only_argument_set_by_the_imports(tmp_path):
    """s2.py and compare.py import probe.py with their own argv (no p0only argument): they get the full behaviour."""
    for name in ("s2", "compare"):
        spec = importlib.util.spec_from_file_location(f"n4_{name}", OPS / f"{name}.py")
        old = sys.argv
        sys.argv = [f"{name}.py", "--mode", "selftest"]
        try:
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        finally:
            sys.argv = old
        assert module.probe.P0_ONLY is False and module.probe.PROCESS_TYPE_SET is None


# ---------------------------------------------------------------------------------------- the default probe (10)
def test_the_default_probe_is_byte_identical_to_before(tmp_path):
    sb = Sandbox(tmp_path)
    proc = sb.run()
    assert proc.returncode == 0
    assert neutral((sb.probe_dir() / "job.plist").read_text(), sb).startswith(GOLDEN_PLIST_HEAD)
    assert neutral(proc.stdout, sb) == GOLDEN_REPORT and proc.stderr == ""
    assert not (sb.probe_dir() / "profile.json").exists()
    result = sb.result()
    assert len(result["steps"]) == 5 and set(result) == {"aborted_class", "complete", "conclusion", "mode", "s0",
                                                         "schema_version", "steps", "tcc_unknown", "timed_out_wait"}
    assert plist_of(sb)["ProgramArguments"][-2:] == ["--mode", "selftest"]


def test_the_p0only_report_names_the_profile_in_plain_words(tmp_path):
    for kind, wording in (("background", "Background"), ("unset", "지정 안 함")):
        (tmp_path / kind).mkdir()
        sb = Sandbox(tmp_path / kind)
        proc = sb.run("--p0-only", "--process-type", kind)
        assert wording in proc.stdout and "낮은 우선순위" not in proc.stdout
        if kind == "unset":
            assert "Standard" in proc.stdout and "가벼운 제한" in proc.stdout


# ------------------------------------------------------------------------------------------ owner check (12)
@pytest.mark.parametrize("style", ["drop_p0", "flip_pt"])
def test_a_job_of_another_profile_under_our_label_is_never_booted_out(tmp_path, style):
    sb = Sandbox(tmp_path)
    proc = sb.run("--p0-only", FAKE_LC_FOREIGN_AFTER_BOOTSTRAP="0", FAKE_LC_STYLE=style)
    assert any(c.startswith("bootstrap") for c in sb.lc_calls())
    assert not any(c.startswith("bootout") for c in sb.lc_calls()), style
    assert proc.returncode == 4 and "잔존 확인 필요: com.airag.probe-opa-" in proc.stdout


def test_a_full_run_does_not_own_a_job_that_carries_p0only_arguments(tmp_path):
    sb = Sandbox(tmp_path)
    proc = sb.run(FAKE_LC_FOREIGN_AFTER_BOOTSTRAP="0", FAKE_LC_STYLE="add_p0")
    assert not any(c.startswith("bootout") for c in sb.lc_calls())
    assert proc.returncode == 4


def test_our_own_p0only_job_is_still_taken_down(tmp_path):
    sb = Sandbox(tmp_path)
    proc = sb.run("--p0-only", "--process-type", "unset")
    calls = [c.split()[0] for c in sb.lc_calls() if c.startswith(("bootstrap", "bootout"))]
    assert calls == ["bootstrap", "bootout"] and sb.loaded() == [] and proc.returncode == 0


# ============================================================================================ the N4 gate G4 / table
def write_probe_dir(base: Path, name: str, doc: dict, *, expect_set: bool, profile="ok", plist="ok") -> Path:
    directory = base / name
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "result.json").write_text(as_text(doc), encoding="utf-8")
    if profile == "ok":
        (directory / "profile.json").write_text(json.dumps(valid_profile_doc(expect_set)), encoding="utf-8")
    elif profile is not None:
        (directory / "profile.json").write_text(profile, encoding="utf-8")
    if plist == "ok":
        document = {"Label": "x", "RunAtLoad": True}
        if expect_set:
            document["ProcessType"] = "Background"
        (directory / "job.plist").write_bytes(plistlib.dumps(document))
    elif plist is not None:
        (directory / "job.plist").write_bytes(plist if isinstance(plist, bytes) else plist.encode())
    return directory


def p0only_doc(p4="success", p0="success", **top) -> dict:
    steps = [step("P4", p4)]
    if p0 == "timeout":
        steps.append(step("P0", "timeout", rc=-9, elapsed_ms=7038, tcc_observation="unknown_log_unavailable"))
    else:
        steps.append(step("P0", p0))
    steps += [step(n, "skipped_not_applicable") for n in ("P2", "P1", "P1b")]
    doc = probe_doc(steps=steps, tcc_unknown=p0 == "timeout")
    doc["conclusion"] = load_probe().conclude({s["step"]: s for s in steps})
    doc.update(top)
    return doc


@pytest.fixture
def chain(monkeypatch):
    return load_chain(monkeypatch)


def gate(chain, tmp_path, doc, expect_set=True, **kw):
    directory = write_probe_dir(tmp_path, "d", doc, expect_set=expect_set, **kw)
    return chain.gate_n4(directory, doc, expect_set)


def test_the_four_valid_p0only_models_and_what_the_existing_functions_make_of_them(chain, tmp_path):
    """DA minor 1: P4/P0 combinations -> the (unchanged) conclusion and the (unchanged) probe gate."""
    cases = [("success", "success", "cause_unconfirmed", None), ("success", "timeout", "p0_blocked", None),
             ("network_error", "timeout", "network_reachability", None),
             ("spawn_error", "timeout", "p0_blocked", "probe_step_error")]
    for index, (p4, p0, conclusion, reason) in enumerate(cases):
        doc = p0only_doc(p4, p0)
        assert chain.probe.validate_result(doc) and doc["conclusion"] == conclusion, (p4, p0)
        assert chain.gate_probe(doc) == reason, (p4, p0)
        case_dir = tmp_path / str(index)
        case_dir.mkdir()
        assert gate(chain, case_dir, doc) == reason, (p4, p0)


def test_g4_passes_an_ordinary_a_and_b_stage(chain, tmp_path):
    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    assert gate(chain, tmp_path / "a", p0only_doc(), True) is None
    assert gate(chain, tmp_path / "b", p0only_doc("success", "timeout"), False) is None


@pytest.mark.parametrize("mutation,reason", [
    (lambda d: d["steps"][0].update(status="spawn_error"), "probe_step_error"),
    (lambda d: d["steps"][0].update(status="unsupported"), "probe_step_error"),
    (lambda d: d["steps"][0].update(status="observation_unknown"), "probe_step_error"),
    (lambda d: d["steps"][0].update(child_exit_unconfirmed=True), "probe_exit_unconfirmed"),
    (lambda d: d["steps"][1].update(reaped=False), "probe_exit_unconfirmed"),
    (lambda d: d["steps"][1].update(descendants_may_hold_pipe=True), "probe_exit_unconfirmed"),
    (lambda d: d.update(complete=False), "probe_incomplete"),
    (lambda d: d.update(aborted_class="OSError"), "probe_incomplete"),
    (lambda d: d.update(timed_out_wait=True), "probe_incomplete"),
    (lambda d: d.update(conclusion="observation_unknown"), "probe_incomplete"),
    (lambda d: d["steps"][1].update(status="spawn_error", rc=None), "probe_step_error"),
    (lambda d: d["steps"][1].update(status="unsupported"), "probe_step_error"),
    (lambda d: d["steps"][1].update(status="observation_unknown"), "probe_step_error"),
    (lambda d: d["steps"][1].update(status="auth_error", rc=1), "p0_not_tabulable"),
    (lambda d: d["steps"][1].update(status="network_error", rc=1), "p0_not_tabulable"),
    (lambda d: d.update(steps=[d["steps"][0]] + d["steps"][2:]), "result_schema"),
    (lambda d: d.pop("mode"), "result_schema"),
    (lambda d: d.update(extra=1), "result_schema"),
])
def test_g4_stops_on_each_single_change(chain, tmp_path, mutation, reason):
    doc = p0only_doc("success", "success")
    mutation(doc)
    assert gate(chain, tmp_path, doc) == reason


@pytest.mark.parametrize("mutation", [
    lambda d: d["steps"][2].update(status="success", account_type_confirmed=True, child_pid=7, reaped=True),
    lambda d: d["steps"][2].update(status="skipped_prior_unresolved"),
    lambda d: d["steps"][3].update(account_type_confirmed=True),
    lambda d: d["steps"][4].update(child_pid=99),
    lambda d: d["steps"][3].update(status="success", account_type_confirmed=True, child_pid=7, reaped=True),
])
def test_g4_stops_when_a_token_step_ran_in_a_p0only_profile(chain, tmp_path, mutation):
    doc = p0only_doc("success", "success")
    mutation(doc)
    assert chain.probe.validate_result(doc)
    assert gate(chain, tmp_path, doc) == "profile_violation"


@pytest.mark.parametrize("text,reason", [
    (None, "profile_missing"),
    ("{not json", "profile_schema"),
    ("[]", "profile_schema"),
    (json.dumps({**valid_profile_doc(), "extra": 1}), "profile_schema"),
    (json.dumps({k: v for k, v in valid_profile_doc().items() if k != "load_after"}), "profile_schema"),
    (json.dumps(valid_profile_doc(profile="full")), "profile_schema"),
    (json.dumps(valid_profile_doc(profile_version=2)), "profile_schema"),
    (json.dumps(valid_profile_doc(profile_version=True)), "profile_schema"),
    (json.dumps(valid_profile_doc(profile_version="1")), "profile_schema"),
    (json.dumps(valid_profile_doc(process_type_set="true")), "profile_schema"),
    (json.dumps(valid_profile_doc(process_type_set=1)), "profile_schema"),
    (json.dumps(valid_profile_doc(load_before=[1.0, 2.0])), "profile_schema"),
    (json.dumps(valid_profile_doc(load_before=["1", 2.0, 3.0])), "profile_schema"),
    (json.dumps(valid_profile_doc(load_before=[True, 2.0, 3.0])), "profile_schema"),
    (json.dumps(valid_profile_doc(load_before="1.0 2.0 3.0")), "profile_schema"),
    (json.dumps(valid_profile_doc(load_after=[1.0, 2.0, -0.1])), "profile_schema"),
    (json.dumps(valid_profile_doc(load_after=[1.0, 2.0, 10000])), "profile_schema"),
    ('{"profile_version":1,"profile":"p0only","process_type_set":true,"load_before":[NaN,1,1],"load_after":null}',
     "profile_schema"),
    ('{"profile_version":1,"profile":"p0only","process_type_set":true,"load_before":[Infinity,1,1],'
     '"load_after":null}', "profile_schema"),
    ("x" * (1 << 21), "profile_schema"),
])
def test_g4_stops_on_a_missing_or_malformed_profile(chain, tmp_path, text, reason):
    assert gate(chain, tmp_path, p0only_doc(), profile=text) == reason


def test_g4_accepts_null_loads_and_ignores_them(chain, tmp_path):
    text = json.dumps(valid_profile_doc(load_before=None, load_after=None))
    assert gate(chain, tmp_path, p0only_doc(), profile=text) is None


def test_g4_does_not_follow_a_symlinked_profile(chain, tmp_path):
    doc = p0only_doc()
    directory = write_probe_dir(tmp_path, "d", doc, expect_set=True, profile=None)
    real = tmp_path / "real-profile.json"
    real.write_text(json.dumps(valid_profile_doc()))
    (directory / "profile.json").symlink_to(real)
    assert chain.gate_n4(directory, doc, True) == "profile_missing"


@pytest.mark.parametrize("expect_set,profile_set,plist,reason", [
    (True, True, {"ProcessType": "Standard"}, "profile_mismatch"),
    (True, True, {"ProcessType": "Interactive"}, "profile_mismatch"),
    (True, True, {"ProcessType": "Adaptive"}, "profile_mismatch"),
    (True, True, {"ProcessType": ""}, "profile_mismatch"),
    (True, True, {"ProcessType": 1}, "profile_mismatch"),
    (True, True, {"ProcessType": "background"}, "profile_mismatch"),
    (True, True, {}, "profile_mismatch"),
    (True, False, {"ProcessType": "Background"}, "profile_mismatch"),
    (True, False, {}, "profile_mismatch"),
    (False, False, {"ProcessType": "Background"}, "profile_mismatch"),
    (False, False, {"ProcessType": "Standard"}, "profile_mismatch"),
    (False, True, {}, "profile_mismatch"),
    (False, True, {"ProcessType": "Background"}, "profile_mismatch"),
    (True, True, {"ProcessType": "Background"}, None),
    (False, False, {}, None),
    # a nested value or a similar name is not the top-level key (a text search would be fooled)
    (False, False, {"EnvironmentVariables": {"ProcessType": "Background"}}, None),
    (True, True, {"EnvironmentVariables": {"ProcessType": "Background"}}, "profile_mismatch"),
    (False, False, {"Label": "ProcessType", "Comment": "<key>ProcessType</key>"}, None),
])
def test_the_plist_is_read_as_a_structure_and_a_value_is_compared(chain, tmp_path, expect_set, profile_set, plist,
                                                                  reason):
    doc = p0only_doc()
    directory = write_probe_dir(tmp_path, "d", doc, expect_set=profile_set, plist=None)
    (directory / "job.plist").write_bytes(plistlib.dumps({"Label": "x", **plist}))
    assert chain.gate_n4(directory, doc, expect_set) == reason


@pytest.mark.parametrize("plist", [None, b"", b"not a plist at all", b"<plist><dict><key>ProcessType</key>",
                                   b"\xff\xfe\x00broken", b"<?xml version='1.0'?><plist version='1.0'><array/></plist>"])
def test_a_missing_or_broken_plist_stops_without_a_guess(chain, tmp_path, plist):
    doc = p0only_doc()
    directory = write_probe_dir(tmp_path, "d", doc, expect_set=True, plist=None)
    if plist is not None:
        (directory / "job.plist").write_bytes(plist)
    assert chain.gate_n4(directory, doc, True) == "profile_mismatch"


def test_a_symlinked_plist_is_not_followed(chain, tmp_path):
    doc = p0only_doc()
    directory = write_probe_dir(tmp_path, "d", doc, expect_set=True, plist=None)
    real = tmp_path / "real.plist"
    real.write_bytes(plistlib.dumps({"ProcessType": "Background"}))
    (directory / "job.plist").symlink_to(real)
    assert chain.gate_n4(directory, doc, True) == "profile_mismatch"


def test_the_probe_gate_reasons_come_before_the_profile_ones(chain, tmp_path):
    doc = p0only_doc("spawn_error", "timeout")
    assert gate(chain, tmp_path, doc, profile=None, plist=None) == "probe_step_error"


# ---------------------------------------------------------------------------------------------- the reading table
def test_the_table_has_exactly_the_four_rows_of_the_design(chain):
    rows = {
        ("timeout", "success", "timeout"): "association",
        ("timeout", "timeout", "timeout"): "not_removed_by_the_key",
        ("success", "success", "success"): "not_reproduced",
        ("success", "timeout", "success"): "hold", ("success", "timeout", "timeout"): "hold",
        ("timeout", "success", "success"): "hold", ("success", "success", "timeout"): "hold",
        ("timeout", "timeout", "success"): "hold", ("success", "timeout", "success"): "hold",
    }
    for p0s, key in rows.items():
        obs = [("success", p) for p in p0s]
        assert chain.n4_reading(obs)[0] == key, p0s


@pytest.mark.parametrize("p4s", [("network_error", "success", "success"), ("success", "timeout", "success"),
                                 ("success", "success", "network_error"), ("network_error",) * 3])
def test_a_p4_that_is_not_success_in_any_stage_means_the_table_is_not_read(chain, p4s):
    obs = [(p4, p0) for p4, p0 in zip(p4s, ("timeout", "success", "timeout"))]
    key, lines = chain.n4_reading(obs)
    assert key == "hold" and any("해석 보류" in line and "P4" in line for line in lines)
    assert not any("연관" in line for line in lines)


def test_the_reading_texts_keep_to_what_the_design_allows(chain):
    texts = {}
    for p0s in (("timeout", "success", "timeout"), ("timeout", "timeout", "timeout"), ("success",) * 3,
                ("success", "timeout", "success")):
        key, lines = chain.n4_reading([("success", p) for p in p0s])
        texts[key] = " ".join(lines)
    assert "연관" in texts["association"] and "원인 확정 아님" in texts["association"]
    assert "Standard" in texts["association"] and "자원 제한이 없는" in texts["association"]
    assert "제거만 해서는" in texts["not_removed_by_the_key"] and "L1" in texts["not_removed_by_the_key"]
    assert "재현되지 않음" in texts["not_reproduced"] and "해결이 아님" in texts["not_reproduced"]
    assert "해석 보류" in texts["hold"]
    for text in texts.values():
        for forbidden in ("낮은 우선순위", "원인은", "해결됐", "해결되었", "운영 plist 를 바꾸", "재개해도"):
            assert forbidden not in text, forbidden
        assert "A-B-A" in text or "한 번" in text or "순서" in text or "해석 보류" in text


# ===================================================================================== the N4 entry of the chain
class N4Sandbox(ChainSandbox):
    def __init__(self, tmp_path: Path):
        super().__init__(tmp_path)
        self.tools = {name: [sys.executable, str(FAKE_TOOL), name] for name in STAGES}
        for name in STAGES:
            self.stage(name)

    def stage(self, name: str, doc=None, *, profile=None, plist=None, extra=None, **spec) -> None:
        directory = P_NAMES[name]
        expect = EXPECT[name]
        items = [{"name": f"{directory}/result.json", "text": as_text(doc if doc is not None else p0only_doc())}]
        items.append({"name": f"{directory}/profile.json",
                      "text": profile if profile is not None else json.dumps(valid_profile_doc(expect))})
        document = {"Label": "x", "RunAtLoad": True}
        if expect:
            document["ProcessType"] = "Background"
        items.append({"name": f"{directory}/job.plist", "text": plist if plist is not None else
                      plistlib.dumps(document).decode()})
        self.spec(name, write=items + (extra or []), **spec)

    def observe(self, a1: str, b: str, a2: str, p4: str = "success") -> None:
        for name, p0 in zip(STAGES, (a1, b, a2)):
            self.stage(name, p0only_doc(p4, p0))


@pytest.fixture
def n4(tmp_path):
    return N4Sandbox(tmp_path)


# ------------------------------------------------------------------ DA r1 minor 1: the step array is exact
def _extra(doc, index, **kw):
    doc["steps"].insert(index, step(doc["steps"][index]["step"], "success", account_type_confirmed=True, **kw))
    return doc


@pytest.mark.parametrize("mutation", [
    lambda d: d.update(steps=d["steps"][1:]),                                         # P4 missing
    lambda d: d.update(steps=d["steps"][:1] + d["steps"][2:]),                        # P0 missing
    lambda d: d.update(steps=d["steps"][:-1]),                                        # P1b missing
    lambda d: d.update(steps=[]),                                                     # nothing at all
    lambda d: _extra(d, 2),                                                           # a success P2 before the skipped P2
    lambda d: d["steps"].append(step("P2", "success", account_type_confirmed=True)),  # ... or after it
    lambda d: d["steps"].append(dict(d["steps"][0])),                                 # P4 twice
    lambda d: d["steps"].append(dict(d["steps"][1])),                                 # P0 twice
    lambda d: d.update(steps=[dict(d["steps"][2])] + d["steps"][1:]),                 # five entries, P4 replaced by P2
    lambda d: d.update(steps=d["steps"][:1] + [dict(d["steps"][1])] * 2 + d["steps"][3:]),   # P0 twice, P2 missing
])
def test_g4_demands_exactly_one_of_each_of_the_five_steps(chain, tmp_path, mutation):
    doc = p0only_doc()
    mutation(doc)
    assert chain.probe.validate_result(doc)            # the shared closed schema alone does not notice
    assert gate(chain, tmp_path, doc) == "result_schema"


def test_the_extra_account_step_is_not_hidden_behind_the_later_skipped_one(chain, tmp_path):
    doc = _extra(p0only_doc(), 2)
    assert chain.probe.validate_result(doc) and chain.gate_probe(doc) is None   # the old checks let it through
    assert gate(chain, tmp_path, doc) == "result_schema"


def test_a_step_array_that_is_not_exact_stops_the_chain_end_to_end(n4):
    doc = p0only_doc()
    doc["steps"] = doc["steps"][1:]
    n4.stage("N4-A1", doc)
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and n4.calls() == ["N4-A1"] and "result_schema" in proc.stdout


def test_the_shared_validator_and_the_other_gates_keep_their_contract(chain):
    """N4 only: the shared v1 validator and gate_probe (N1..N3) still accept an array without P4 or with a repeat."""
    doc = p0only_doc()
    doc["steps"] = doc["steps"][1:]
    assert chain.probe.validate_result(doc) and chain.gate_probe(doc) is None


def test_the_n4_plan_exists_with_the_same_numbers_as_the_other_plans(chain):
    assert chain.PLANS["n4"] == STAGES and chain.PLANS["full"] == ("N1", "N2", "N3")   # N1..N3 flow untouched
    assert chain.plan_total(len(chain.PLANS["n4"])) == 240.0
    assert chain.STEP_S == 75.0 and chain.START_NEED_S == 83.0 and chain.OVERRUN_S == 77.0 and chain.GRACE_S == 3.0


def test_the_n4_tools_are_the_probe_script_with_the_two_new_arguments_and_nothing_else(chain):
    tools = chain.build_tools(Path("/x/probe-opa"), "/py/python")
    base = ["/bin/bash", "/x/probe-opa/probe.sh", "--python", "/py/python", "--p0-only", "--process-type"]
    assert tools["N4-A1"] == [*base, "background"] and tools["N4-B"] == [*base, "unset"]
    assert tools["N4-A2"] == [*base, "background"]
    assert tools["N1"] == ["/bin/bash", "/x/probe-opa/probe.sh", "--python", "/py/python"]
    assert not any("compare.sh" in part for name in STAGES for part in tools[name])


def test_a_normal_a_b_a_runs_three_stages_in_order_and_reads_the_table(n4):
    n4.observe("timeout", "success", "timeout")
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert n4.calls() == list(STAGES) and proc.stdout.count("통과") == 3
    assert "연관" in proc.stdout and "원인 확정 아님" in proc.stdout and "r10" in proc.stdout
    assert "N4-A1: P4=success P0=timeout" in proc.stdout and "N4-B: P4=success P0=success" in proc.stdout


@pytest.mark.parametrize("observed,word", [(("timeout", "timeout", "timeout"), "제거만 해서는"),
                                           (("success", "success", "success"), "재현되지 않음"),
                                           (("success", "timeout", "success"), "해석 보류")])
def test_the_other_rows_are_read_the_same_way_end_to_end(n4, observed, word):
    n4.observe(*observed)
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 0 and word in proc.stdout and n4.calls() == list(STAGES)
    assert "연관된 관측" not in proc.stdout or observed == ("timeout", "success", "timeout")


def test_a_p4_that_is_not_success_goes_on_but_the_table_is_not_read(n4):
    n4.observe("timeout", "success", "timeout", p4="network_error")
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 0 and n4.calls() == list(STAGES)
    assert "해석 보류" in proc.stdout and "연관된 관측" not in proc.stdout


def test_a_profile_mismatch_in_stage_b_stops_before_the_last_a(n4):
    n4.stage("N4-B", plist=plistlib.dumps({"Label": "x", "ProcessType": "Background"}).decode())
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and n4.calls() == ["N4-A1", "N4-B"]
    assert "profile_mismatch" in proc.stdout and "연관" not in proc.stdout


def test_a_stop_at_the_last_stage_never_reads_the_table(n4):
    """The first two stages look like the association row, but the last one fails its gate: nothing is interpreted."""
    n4.observe("timeout", "success", "timeout")
    n4.stage("N4-A2", p0only_doc("success", "timeout"),
             plist=plistlib.dumps({"Label": "x", "ProcessType": "Interactive"}).decode())
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and n4.calls() == list(STAGES) and "profile_mismatch" in proc.stdout
    assert "연관" not in proc.stdout and "제거만 해서는" not in proc.stdout and "재현되지 않음" not in proc.stdout


def test_the_profile_says_the_opposite_in_stage_b(n4):
    n4.stage("N4-B", profile=json.dumps(valid_profile_doc(True)))
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and "profile_mismatch" in proc.stdout and n4.calls() == ["N4-A1", "N4-B"]


def test_a_stage_a_with_another_process_type_value_stops_at_once(n4):
    n4.stage("N4-A1", plist=plistlib.dumps({"Label": "x", "ProcessType": "Interactive"}).decode())
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and n4.calls() == ["N4-A1"] and "profile_mismatch" in proc.stdout


def test_a_token_step_in_a_p0only_result_stops_with_a_violation(n4):
    doc = p0only_doc()
    doc["steps"][2].update(status="success", account_type_confirmed=True, child_pid=7, reaped=True)
    n4.stage("N4-A1", doc)
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and n4.calls() == ["N4-A1"] and "profile_violation" in proc.stdout


@pytest.mark.parametrize("profile,reason", [("{}", "profile_schema"), ("garbage", "profile_schema"),
                                            (json.dumps(valid_profile_doc(profile_version=2)), "profile_schema")])
def test_an_unusable_profile_stops_the_chain(n4, profile, reason):
    n4.stage("N4-A1", profile=profile)
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and n4.calls() == ["N4-A1"] and reason in proc.stdout


def test_a_stage_without_a_profile_file_stops_the_chain(n4):
    n4.spec("N4-A1", write=[{"name": f"{P_NAMES['N4-A1']}/result.json", "text": as_text(p0only_doc())},
                            {"name": f"{P_NAMES['N4-A1']}/job.plist",
                             "text": plistlib.dumps({"ProcessType": "Background"}).decode()}])
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and n4.calls() == ["N4-A1"] and "profile_missing" in proc.stdout


def test_n4_result_discovery_takes_only_one_new_probe_folder(n4):
    n4.stage("N4-A1", extra=[{"name": "20261016-100001-999-1/result.json", "text": as_text(p0only_doc())}])
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and "result_ambiguous" in proc.stdout and n4.calls() == ["N4-A1"]


@pytest.mark.parametrize("spec,reason", [
    ({"write": []}, "result_missing"),
    ({"write": [{"name": "compare-20261016-100000-1-2.result.json", "text": "{}"}]}, "result_missing"),
    ({"write": [{"name": f"{P_NAMES['N4-A1']}/result.json", "text": '{"v":'}]}, "result_unreadable"),
    ({"write": [{"name": f"{P_NAMES['N4-A1']}/result.json", "text": "x" * ((1 << 20) + 5)}]}, "result_unreadable"),
    ({"write": [{"name": "not-a-probe-name/result.json", "text": "{}"}]}, "result_missing"),
])
def test_n4_result_discovery_failures_stop_the_chain(n4, spec, reason):
    n4.spec("N4-A1", **spec)
    proc = n4.run("--plan", "n4")
    assert proc.returncode == 5 and reason in proc.stdout and n4.calls() == ["N4-A1"]


@pytest.mark.parametrize("code", [1, 2, 3, 4, 130, 143, 129])
def test_a_nonzero_n4_tool_code_is_passed_on(n4, code):
    n4.spec("N4-A1", rc=code)
    proc = n4.run("--plan", "n4")
    assert proc.returncode == code and n4.calls() == ["N4-A1"]


def test_a_signal_during_a_n4_stage_is_forwarded_once_to_that_tool_and_the_code_is_kept(n4):
    n4.spec("N4-B", sleep=30, cleanup_s=0.2)
    process = n4.start("--plan", "n4")
    assert wait_until(lambda: "N4-B" in n4.calls(), 60)
    time.sleep(0.3)
    os.kill(process.pid, signal.SIGINT)
    out, err = process.communicate(timeout=60)
    assert process.returncode == 130, out + err
    assert n4.calls() == ["N4-A1", "N4-B"] and n4.signals("N4-B") == [signal.SIGINT]


def test_a_n4_tool_over_the_limit_gets_term_once_and_the_rest_is_skipped(n4):
    n4.spec("N4-A1", sleep=60, cleanup_s=0.1)
    proc = n4.run("--plan", "n4", PROBE_CH_T_OVERRUN="2", PROBE_CH_T_GRACE="4")
    assert proc.returncode == 6 and n4.calls() == ["N4-A1"] and n4.signals("N4-A1") == [signal.SIGTERM]


def _clock_chain(monkeypatch, tmp_path, *, plan: str, durations):
    """The chain's own clock and tools replaced by fakes (as in test_chain_opa), with the N4 stage tools."""
    sb = N4Sandbox(tmp_path)
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


def test_the_n4_plan_keeps_the_clock_rules(monkeypatch, tmp_path):
    chain, code, started, total = _clock_chain(monkeypatch, tmp_path, plan="n4", durations=[(75.0, False)] * 3)
    assert code == 0 and len(started) == 3 and total == 234.0 <= 240.0
    assert all(remaining >= chain.START_NEED_S for remaining, _ in started)


@pytest.mark.parametrize("lengths", list(itertools.product((0.0, 40.0, 75.0, 77.0), repeat=3)))
def test_no_n4_stage_starts_below_83_seconds_left(monkeypatch, tmp_path, lengths):
    chain, code, started, total = _clock_chain(monkeypatch, tmp_path, plan="n4",
                                               durations=[(d, False) for d in lengths] + [(0.0, False)] * 3)
    assert total <= chain.plan_total(3) and all(remaining >= chain.START_NEED_S for remaining, _ in started)
    if len(started) < 3:
        assert code == 7


def test_the_overrun_path_of_n4_ends_with_six_inside_the_total(monkeypatch, tmp_path):
    chain, code, started, total = _clock_chain(monkeypatch, tmp_path, plan="n4",
                                               durations=[(75.0, False), (75.0, False), (80.0, True)])
    assert code == 6 and len(started) == 3 and total + 2.0 <= 240.0


def test_chain_sh_accepts_the_n4_plan_and_still_refuses_unknown_ones(n4):
    assert n4.run("--plan", "bogus").returncode == 2 and n4.calls() == []
    n4.observe("success", "success", "success")
    assert n4.run("--plan", "n4").returncode == 0


def test_n4_output_never_shows_values_from_the_files_or_the_environment(n4):
    secret = "SYNTH_N4_ENV_6601"
    n4.stage("N4-A1", plist=plistlib.dumps({"Label": secret, "ProcessType": "Background",
                                            "EnvironmentVariables": {"X": secret}}).decode(),
             profile=json.dumps(valid_profile_doc(True, load_before=None, load_after=None)))
    proc = n4.run("--plan", "n4", SYNTH_N4_SECRET=secret)
    assert proc.returncode == 0 and secret not in proc.stdout + proc.stderr


def test_the_n4_code_has_no_token_signal_or_group_path():
    source = (OPS / "chain.py").read_text(encoding="utf-8")
    for forbidden in ("os.kill", "killpg", "pkill", "killall", "read_token", "op-sa-token", "launchctl",
                      "OP_SERVICE_ACCOUNT_TOKEN", "shell=True"):
        assert forbidden not in source, forbidden


# -------------------------------------------------------------------- the real probe script, three times, stubs only
def test_chain_n4_over_the_real_probe_script_with_synthetic_stubs(tmp_path):
    """probe.sh runs with the real N4 arguments on a fake launchctl / log / op: file names, closed schemas, plists and
    both gates must fit what the real tool writes. Three runs: three op --version calls, no token anywhere."""
    stub = Sandbox(tmp_path)
    py = sys.executable
    tools = {"N4-A1": ["/bin/bash", str(OPS / "probe.sh"), "--selftest", "--python", py, "--p0-only",
                       "--process-type", "background"],
             "N4-B": ["/bin/bash", str(OPS / "probe.sh"), "--selftest", "--python", py, "--p0-only",
                      "--process-type", "unset"],
             "N4-A2": ["/bin/bash", str(OPS / "probe.sh"), "--selftest", "--python", py, "--p0-only",
                       "--process-type", "background"]}
    env = stub.env(PATH=f"{stub.bin}:/usr/bin:/bin:/usr/sbin:/sbin", PROBE_CH_TOOLS=json.dumps(tools),
                   PROBE_CH_T_STEP="60", PROBE_CH_T_OVERRUN="60", PROBE_CH_T_SLOT="70", PROBE_CH_T_GRACE="3",
                   PROBE_CH_T_CANCEL="20", PROBE_CH_T_TRANSITION="3")
    done = subprocess.run(["/bin/bash", str(CHAIN_SH), "--selftest", "--python", py, "--plan", "n4"], env=env,
                          capture_output=True, text=True, timeout=240)
    assert done.returncode == 0, done.stdout + done.stderr
    assert done.stdout.count("통과") == 3 and "재현되지 않음" in done.stdout
    calls = stub.opcalls.read_text().splitlines()
    assert len(calls) == 3 and all(c.startswith("--version TOK= ") for c in calls)
    dirs = sorted(p for p in stub.base.iterdir() if p.is_dir())
    assert len(dirs) == 3 and all((d / "profile.json").exists() for d in dirs)
    kinds = ["ProcessType" in plistlib.loads((d / "job.plist").read_bytes()) for d in dirs]
    assert kinds == [True, False, True]
    assert TOKEN not in done.stdout + done.stderr and stub.loaded() == []
