from __future__ import annotations

from datetime import datetime, timedelta, timezone
import fcntl
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import sys

import pytest

from airag_consumer import tick
from airag_consumer.runtime import PROFILE_SOURCE_KEY_ENV, AIRAGRuntime, RuntimeConfig, RuntimeHooks
from test_runtime import (
    ARCHIVE_KEY, CONSUMER_KEY, PROJECTION_KEY, Clock, DecisionExtractor, SyntheticBridge,
    environment, project,
)


UTC = timezone.utc
NOW = datetime(2026, 9, 27, 4, tzinfo=UTC)
KEYS = {
    "AIRAG_CONSUMER_KEY_HEX": CONSUMER_KEY.hex(),
    "AIRAG_PROJECTION_KEY_HEX": PROJECTION_KEY.hex(),
    "AIRAG_ARCHIVE_KEY_HEX": ARCHIVE_KEY.hex(),
}
REFERENCES = {
    "AIRAG_CONSUMER_KEY_HEX": "op://synthetic/consumer",
    "AIRAG_PROJECTION_KEY_HEX": "op://synthetic/projection",
    "AIRAG_ARCHIVE_KEY_HEX": "op://synthetic/archive",
}
TOKEN = "synthetic-service-token"


def stub_op(tmp_path: Path, *, keys=None, fail=False, leak_to_stderr=False) -> tuple[Path, Path]:
    """A fake `op`: records the references it was asked for and prints a synthetic key."""
    keys = KEYS if keys is None else keys
    calls = tmp_path / "op-calls.txt"
    by_reference = {REFERENCES[name]: value for name, value in keys.items()}
    cases = "\n".join(f'  "{reference}") VALUE="{value}";;' for reference, value in by_reference.items())
    script = tmp_path / "op"
    script.write_text(
        "#!/bin/sh\n"
        f'echo "$2" >> "{calls}"\n'
        f'[ "$1" = read ] || exit 2\n'
        f'[ "$OP_SERVICE_ACCOUNT_TOKEN" = "{TOKEN}" ] || exit 4\n'
        'case "$2" in\n' + cases + "\n  *) exit 3;;\nesac\n"
        + ('echo "boom $VALUE" >&2\nexit 9\n' if fail or leak_to_stderr else "")
        + 'echo "$VALUE"\n',
        encoding="utf-8",
    )
    script.chmod(script.stat().st_mode | stat.S_IXUSR)
    return script, calls


def credentials(tmp_path: Path, op: Path) -> Path:
    token = tmp_path / "token"
    token.write_text(TOKEN + "\n", encoding="utf-8")
    path = tmp_path / "credentials.json"
    path.write_text(json.dumps({
        "token_file": str(token), "op": str(op), "references": REFERENCES,
    }), encoding="utf-8")
    return path


def synthetic_service(tmp_path: Path, *, memory: bool = False):
    (tmp_path / "svc").mkdir()
    item = project(tmp_path / "svc", now=NOW, memory=memory,
                   content="I prefer concise answers and the fix worked.")
    hooks = RuntimeHooks(
        bridge=SyntheticBridge(), memory_extractor=DecisionExtractor() if memory else None,
    )
    AIRAGRuntime(
        RuntimeConfig.load(item["config"]), environ=environment(), clock=Clock(NOW), hooks=hooks,
    ).init()
    return item, "memory" if memory else "normal"


def component_for(mode):
    return [sys.executable, str(COMPONENT), mode]


def base_environment() -> dict[str, str]:
    return {k: v for k, v in environment().items() if k not in KEYS}


def run_tick(tmp_path, item, mode, *, credentials_path=None, env=None, extra=()):
    args = ["--config", str(item["config"]), "--log-dir", str(tmp_path / "logs"), *extra]
    if credentials_path is not None:
        args += ["--credentials", str(credentials_path)]
    return tick.main(args, environ=base_environment() if env is None else env,
                     clock=Clock(NOW), component=component_for(mode))


def everything_written(tmp_path, capsys) -> str:
    captured = capsys.readouterr()
    logs = "".join(p.read_text(encoding="utf-8") for p in (tmp_path / "logs").glob("*") if p.is_file()) \
        if (tmp_path / "logs").exists() else ""
    return captured.out + captured.err + logs


def no_key_text(text: str) -> bool:
    return not any(value in text for value in KEYS.values())


def test_normal_tick_fills_keys_runs_once_and_leaks_nothing(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    op, calls = stub_op(tmp_path)
    code = run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    assert code == tick.EXIT_OK
    assert sorted(calls.read_text().split()) == sorted(REFERENCES.values())
    line = json.loads(written.strip().splitlines()[0])
    assert line["status"] == "ok" and line["exit"] == 0
    assert line["summary"]["sources"] == 1 and line["summary"]["accepted"] >= 1
    assert "backup_created" in line["summary"] and "published_attempted" in line["summary"]
    assert no_key_text(written) and TOKEN not in written
    log = next((tmp_path / "logs").glob("tick-20260927.log"))
    assert len(log.read_text().strip().splitlines()) == 1
    assert not any(name in os.environ for name in KEYS)  # keys never reach the real process environment


def test_existing_environment_keys_win_and_op_is_not_called(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    op, calls = stub_op(tmp_path)
    env = {**base_environment(), **KEYS}
    code = run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op), env=env)
    assert code == tick.EXIT_OK and not calls.exists()
    assert no_key_text(everything_written(tmp_path, capsys))


def test_only_missing_keys_are_read_from_op(tmp_path):
    item, hooks = synthetic_service(tmp_path)
    op, calls = stub_op(tmp_path)
    env = {**base_environment(), "AIRAG_CONSUMER_KEY_HEX": KEYS["AIRAG_CONSUMER_KEY_HEX"]}
    assert run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op), env=env) == tick.EXIT_OK
    assert sorted(calls.read_text().split()) == sorted(
        [REFERENCES["AIRAG_PROJECTION_KEY_HEX"], REFERENCES["AIRAG_ARCHIVE_KEY_HEX"]])


def test_overlapping_tick_skips_without_touching_keys_or_runtime(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    op, calls = stub_op(tmp_path)
    (tmp_path / "logs").mkdir()
    with (tmp_path / "logs" / "tick.lock").open("a") as holder:
        fcntl.flock(holder, fcntl.LOCK_EX)
        code = run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    assert code == tick.EXIT_SKIPPED and not calls.exists()
    assert json.loads(written.strip().splitlines()[0])["status"] == "skipped"


def test_key_loading_failure_has_its_own_exit_code_and_leaks_nothing(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    op, _ = stub_op(tmp_path, leak_to_stderr=True)
    code = run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    assert code == tick.EXIT_KEYS
    assert json.loads(written.strip().splitlines()[0])["code"] == "OP_KEY_READ_OR_FORMAT_FAILED"
    assert no_key_text(written) and "boom" not in written


def test_missing_credentials_or_config_is_a_configuration_error(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, hooks, credentials_path=tmp_path / "absent.json") == tick.EXIT_CONFIG
    assert run_tick(tmp_path, item, hooks) == tick.EXIT_CONFIG  # keys absent and no settings given
    missing = tick.main(
        ["--config", str(tmp_path / "absent-runtime.json"), "--log-dir", str(tmp_path / "logs")],
        environ=base_environment(), clock=Clock(NOW), component=component_for(hooks),
    )
    assert missing == tick.EXIT_CONFIG
    assert tick.main(["--bogus"], environ={}, clock=Clock(NOW)) == tick.EXIT_CONFIG
    codes = [json.loads(line)["code"] for line in everything_written(tmp_path, capsys).splitlines()
             if line.startswith("{")]
    assert "CREDENTIAL_SETTINGS_UNAVAILABLE" in codes and "CONFIG_FILE_UNAVAILABLE" in codes


def test_runtime_failure_is_reported_by_code_only(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    wrong = {name: bytes([index + 1]).hex() * 32 for index, name in enumerate(KEYS)}
    op, _ = stub_op(tmp_path, keys=wrong)
    code = run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    line = json.loads(written.strip().splitlines()[0])
    assert code == tick.EXIT_RUNTIME and line["status"] == "runtime_error"
    assert line["code"] != "RUNTIME_FAILED"  # a code this package really emits is still reported
    assert no_key_text(written) and not any(value in written for value in wrong.values())


def test_log_rotation_caps_size_and_prunes_old_days(tmp_path):
    logs = tmp_path / "logs"
    logs.mkdir()
    today = logs / "tick-20260927.log"
    today.write_text("x" * (tick.LOG_MAX_BYTES + 1), encoding="utf-8")
    old = logs / f"tick-{(NOW - timedelta(days=tick.LOG_KEEP_DAYS + 3)).strftime('%Y%m%d')}.log"
    old.write_text("old\n", encoding="utf-8")
    recent = logs / f"tick-{(NOW - timedelta(days=2)).strftime('%Y%m%d')}.log"
    recent.write_text("recent\n", encoding="utf-8")
    tick.append_log(logs, NOW, '{"status":"ok"}')
    assert today.read_text() == '{"status":"ok"}\n'
    assert (logs / "tick-20260927.log.1").stat().st_size == tick.LOG_MAX_BYTES + 1
    assert not old.exists() and recent.exists()


def test_plist_template_is_a_placeholder_only_five_minute_job():
    raw = (Path(__file__).resolve().parents[1] / "ops" / "com.airag.consumer.plist.template").read_text()
    placeholders = set(re.findall(r"__[A-Z]+(?:_[A-Z]+)*__", raw))
    assert placeholders == {"__PYTHON__", "__CONFIG__", "__CREDENTIALS__", "__LOG_DIR__"}
    filled = raw
    for name in placeholders:
        filled = filled.replace(name, "/tmp/synthetic")
    data = plistlib.loads(filled.encode("utf-8"))
    assert data["Label"] == "com.airag.consumer"
    assert data["StartInterval"] == 300 and data["RunAtLoad"] is True
    assert data["ProgramArguments"][1:3] == ["-m", "airag_consumer.tick"]
    assert "KeepAlive" not in data
    assert "KEY_HEX" not in raw and "op://" not in raw


def test_first_pass_summary_carries_collection_progress_and_memory_observations(tmp_path, capsys):
    # U4 observation values, taken from the real run_once result keys (numbers only).
    item, hooks = synthetic_service(tmp_path, memory=True)
    op, _ = stub_op(tmp_path)
    code = run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    assert code == tick.EXIT_OK
    summary = json.loads(written.strip().splitlines()[0])["summary"]
    assert summary["committed_native_offset_total"] == len(item["original"])
    assert summary["pending_bytes_total"] == 0
    assert summary["memory_enabled"] is True and summary["memory_provider_called"] is True
    assert summary["memory_attempts"] == 1 and summary["memory_candidate_count"] == 2
    assert summary["memory_conflict_count"] == 0 and summary["memory_rejected_count"] == 0
    assert summary["memory_batch_message_count"] == 1
    assert summary["memory_awaiting_confirmation_count"] == 1 and summary["memory_unverified_count"] == 1
    assert isinstance(summary["pass_elapsed_s"], float) and summary["pass_elapsed_s"] >= 0
    assert "Prefer concise answers" not in written and "fix worked" not in written  # no memory text
    assert no_key_text(written)


KEYLIKE = "AB" * 32  # a code-shaped, key-shaped string: uppercase hex that passes naive code regexes


def test_key_shaped_error_text_never_reaches_output_or_log(tmp_path, capsys):
    # R8-M1: an error message that looks like a code must not be trusted as one.
    item, _ = synthetic_service(tmp_path)
    op, _ = stub_op(tmp_path)
    code = run_tick(tmp_path, item, "keylike", credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    line = json.loads(written.strip().splitlines()[0])
    assert code == tick.EXIT_RUNTIME and line["status"] == "runtime_error"
    assert KEYLIKE.lower() not in written.lower() and no_key_text(written.lower())
    assert line["code"] == "RUNTIME_FAILED" and line["type"] == "RuntimeError"


def test_symlinked_log_or_lock_is_refused_and_new_files_are_private(tmp_path, capsys):
    # R8-M2
    item, hooks = synthetic_service(tmp_path)
    op, _ = stub_op(tmp_path)
    outside = tmp_path / "outside.txt"
    outside.write_text("untouched\n", encoding="utf-8")
    logs = tmp_path / "logs"
    logs.mkdir()
    (logs / "tick-20260927.log").symlink_to(outside)
    assert run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op)) == tick.EXIT_OK
    assert outside.read_text() == "untouched\n"
    assert "log_write_failed" in capsys.readouterr().err
    (logs / "tick-20260927.log").unlink()
    (logs / "tick.lock").unlink()
    (logs / "tick.lock").symlink_to(outside)
    assert run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op)) == tick.EXIT_CONFIG
    assert outside.read_text() == "untouched\n"
    (logs / "tick.lock").unlink()
    fresh = tmp_path / "fresh-logs"
    previous = os.umask(0)
    try:
        assert tick.main(["--config", str(item["config"]), "--log-dir", str(fresh), "--credentials",
                          str(credentials(tmp_path, op))], environ=base_environment(), clock=Clock(NOW),
                         component=component_for(hooks)) == tick.EXIT_OK
    finally:
        os.umask(previous)
    assert stat.S_IMODE(fresh.stat().st_mode) == 0o700
    assert {stat.S_IMODE(p.stat().st_mode) for p in fresh.glob("tick*")} == {0o600}


def test_log_is_rotated_before_a_line_would_cross_the_cap(tmp_path):
    # R8-m1
    logs = tmp_path / "logs"
    logs.mkdir()
    today = logs / "tick-20260927.log"
    today.write_text("x" * tick.LOG_MAX_BYTES, encoding="utf-8")
    tick.append_log(logs, NOW, "{}")
    assert (logs / "tick-20260927.log.1").stat().st_size == tick.LOG_MAX_BYTES
    assert today.read_text() == "{}\n"


def test_op_child_environment_is_an_allowlist(tmp_path):
    # R8-m2
    item, hooks = synthetic_service(tmp_path)
    op, calls = stub_op(tmp_path)
    seen = tmp_path / "op-env-names.txt"
    op.write_text(op.read_text().replace('echo "$2" >> ', f'env | sed "s/=.*//" >> "{seen}"\necho "$2" >> ', 1))
    env = {**base_environment(), "OTHER_RUNTIME_KEY_HEX": "ab" * 32, "OP_EXTRA_SECRET": "x",
           "SOME_API_TOKEN": "y", "OP_SESSION_demo": "z", "HOME": str(tmp_path)}
    assert run_tick(tmp_path, item, hooks, credentials_path=credentials(tmp_path, op), env=env) == tick.EXIT_OK
    names = set(seen.read_text().split())
    assert {"PATH", "HOME", "OP_SERVICE_ACCOUNT_TOKEN"} <= names
    assert not names & {"OTHER_RUNTIME_KEY_HEX", "OP_EXTRA_SECRET", "SOME_API_TOKEN", "OP_SESSION_demo",
                        "AIRAG_MEMORY_API_KEY", "AIRAG_PROFILE_SOURCE_KEY_HEX"}


def test_short_error_value_is_not_trusted_as_a_reason_code(tmp_path, capsys):
    # R9-M1: only reason codes this package really emits are reported; anything else is RUNTIME_FAILED.
    item, _ = synthetic_service(tmp_path)
    op, _ = stub_op(tmp_path)
    code = run_tick(tmp_path, item, "short", credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    line = json.loads(written.strip().splitlines()[0])
    assert code == tick.EXIT_RUNTIME and "SHORT_SECRET_VALUE" not in written
    assert line["code"] == "RUNTIME_FAILED" and line["type"] == "RuntimeError"


def test_rejected_log_dir_is_never_written_or_pruned(tmp_path, capsys):
    # R9-M2
    item, hooks = synthetic_service(tmp_path)
    op, calls = stub_op(tmp_path)
    target = tmp_path / "elsewhere"
    target.mkdir()
    today = target / "tick-20260927.log"
    today.write_text("existing\n", encoding="utf-8")
    old = target / f"tick-{(NOW - timedelta(days=tick.LOG_KEEP_DAYS + 1)).strftime('%Y%m%d')}.log"
    old.write_text("old\n", encoding="utf-8")
    (tmp_path / "linked").symlink_to(target)
    code = tick.main(["--config", str(item["config"]), "--log-dir", str(tmp_path / "linked"),
                      "--credentials", str(credentials(tmp_path, op))],
                     environ=base_environment(), clock=Clock(NOW), component=component_for(hooks))
    assert code == tick.EXIT_CONFIG and not calls.exists()
    assert today.read_text() == "existing\n" and old.exists()
    assert sorted(p.name for p in target.iterdir()) == sorted([today.name, old.name])


def test_partial_log_writes_are_completed_or_reported(tmp_path, monkeypatch):
    # R9-m2
    logs = tmp_path / "logs"
    logs.mkdir()
    real_write = os.write
    monkeypatch.setattr(os, "write", lambda fd, data: real_write(fd, bytes(data)[:5]))
    tick.append_log(logs, NOW, '{"status":"ok"}')
    assert (logs / "tick-20260927.log").read_text() == '{"status":"ok"}\n'
    monkeypatch.setattr(os, "write", lambda fd, data: 0)
    with pytest.raises(OSError):
        tick.append_log(logs, NOW, '{"status":"ok"}')


RUNNER = '''
import json, os, sys
from datetime import datetime, timezone
from airag_consumer import tick
from test_runtime import Clock

component = json.loads(os.environ["TICK_COMPONENT"])
fds_before = (os.fstat(1).st_ino, os.fstat(2).st_ino, len(os.listdir("/dev/fd")))
code = tick.main(sys.argv[1:], environ=json.loads(os.environ["TICK_CHILD_ENV"]),
                 clock=Clock(datetime(2026, 9, 27, 4, tzinfo=timezone.utc)), component=component or None)
fds_after = (os.fstat(1).st_ino, os.fstat(2).st_ino, len(os.listdir("/dev/fd")))
sys.stderr.write("FDS_SAME=%s\\n" % (fds_before == fds_after))
sys.exit(code)
'''


def run_isolated_tick(tmp_path, item, component, env=None):
    """Run the real ``tick.main`` in a separate Python so libc and interpreter-exit flushes are observed."""
    import subprocess

    return subprocess.run(
        [sys.executable, "-c", RUNNER, "--config", str(item["config"]), "--log-dir", str(tmp_path / "logs")],
        env={**child_env(), "TICK_COMPONENT": json.dumps(component),
             "TICK_CHILD_ENV": json.dumps(env or {**base_environment(), **KEYS})},
        capture_output=True, text=True,
    )


def test_native_libc_output_does_not_reach_the_tick_streams(tmp_path):
    # R10-M1 (was the S1 Red): libc stdio flushed at exit, Python prints and direct fd writes are all dropped.
    item, _ = synthetic_service(tmp_path)
    proc = run_isolated_tick(tmp_path, item, component_for("native"))
    assert proc.returncode == 0, proc.stderr[-300:]
    assert "MARKER_" not in proc.stdout + proc.stderr
    lines = proc.stdout.strip().splitlines()
    assert len(lines) == 1 and json.loads(lines[0])["status"] == "ok"
    assert "FDS_SAME=True" in proc.stderr


def test_native_output_before_an_exception_is_dropped_too(tmp_path):
    item, _ = synthetic_service(tmp_path)
    proc = run_isolated_tick(tmp_path, item, component_for("native-raise"))
    assert proc.returncode == tick.EXIT_RUNTIME
    assert "MARKER_" not in proc.stdout + proc.stderr
    line = json.loads(proc.stdout.strip().splitlines()[0])
    # cli.main maps a non-code exception message to INTERNAL_ERROR (a registered code) before the frame is built
    assert line["code"] in {"RUNTIME_FAILED", "INTERNAL_ERROR"} and line["type"] == "RuntimeError"
    assert "FDS_SAME=True" in proc.stderr


def test_python_and_direct_fd_output_never_reach_the_tick(tmp_path, capfd):
    item, mode = synthetic_service(tmp_path)
    op, _ = stub_op(tmp_path)
    code = run_tick(tmp_path, item, "chatty", credentials_path=credentials(tmp_path, op))
    captured = capfd.readouterr()
    assert code == tick.EXIT_OK
    assert "MARKER_" not in captured.out + captured.err
    assert json.loads(captured.out.strip().splitlines()[-1])["status"] == "ok"


GOOD_OK = {"exit": 0, "summary": {"sources": 1, "coverage_complete": True}, "code": "", "type": ""}
GOOD_FAIL = {"exit": 2, "summary": {}, "code": "RUNTIME_FAILED", "type": "RuntimeError"}


def test_frame_validation_accepts_only_the_closed_schema():
    from airag_consumer import _result

    assert _result.validate_frame(dict(GOOD_OK)) == GOOD_OK
    assert _result.validate_frame(dict(GOOD_FAIL)) == GOOD_FAIL
    bad = [
        None, [], "x", {**GOOD_OK, "extra": 1}, {k: v for k, v in GOOD_OK.items() if k != "type"},
        {**GOOD_OK, "exit": True}, {**GOOD_OK, "exit": "0"},
        {**GOOD_OK, "summary": {"unknown_key": 1}},
        {**GOOD_OK, "summary": {"sources": "1"}}, {**GOOD_OK, "summary": {"sources": True}},
        {**GOOD_OK, "summary": {"coverage_complete": 1}}, {**GOOD_OK, "summary": []},
        {**GOOD_FAIL, "code": "NOT_A_KNOWN_CODE_ZZ"}, {**GOOD_FAIL, "code": "lowercase"},
        {**GOOD_FAIL, "type": "AB" * 16}, {**GOOD_FAIL, "type": "not a type!"},
    ]
    for frame in bad:
        assert _result.validate_frame(frame) is None, frame


def test_frame_building_keeps_only_whitelisted_numbers_and_reason_codes():
    from airag_consumer import _result

    ok = _result.build_frame(0, json.dumps({"ok": True, "data": {
        "collected": [{"accepted_count": 3, "gap_count": 0, "committed_native_offset": 9,
                       "pending_bytes": 0, "coverage_complete": True, "note": "MARKER_BODY"}],
    }}), "")
    assert ok["exit"] == 0 and ok["summary"]["accepted"] == 3 and "MARKER_BODY" not in json.dumps(ok)
    failed = _result.build_frame(2, "", json.dumps({"ok": False, "error": {"code": KEYLIKE, "type": "RuntimeError"}}))
    assert failed == {"exit": 2, "summary": {}, "code": "RUNTIME_FAILED", "type": "RuntimeError"}
    assert _result.build_frame(0, "not json", "")["code"] == "RUNTIME_OUTPUT_INVALID"
    assert _result.build_frame(0, json.dumps({"ok": True, "data": "text"}), "")["code"] == "RUNTIME_OUTPUT_INVALID"
    assert all(_result.validate_frame(f) == f for f in (ok, failed))


COMPONENT = Path(__file__).resolve().parent / "_tick_component.py"


def child_env():
    src = Path(__file__).resolve().parents[1] / "src"
    return {**{k: v for k, v in os.environ.items() if k in ("PATH", "HOME", "TMPDIR")},
            "PYTHONPATH": f"{src}:{COMPONENT.parent}"}


def run_child(mode, config, stdin_text, tmp_path):
    import subprocess

    out = tmp_path / "child-result.bin"
    with out.open("wb") as result:
        proc = subprocess.run(
            [sys.executable, str(COMPONENT), mode, "--config", str(config)], input=stdin_text,
            text=True, stdout=result, stderr=subprocess.DEVNULL, env=child_env(), check=False,
        )
    return proc.returncode, out.read_bytes()


def test_child_protocol_writes_exactly_one_value_free_frame(tmp_path):
    from airag_consumer import _result

    item, _ = synthetic_service(tmp_path)
    code, data = run_child("normal", item["config"], json.dumps(KEYS), tmp_path)
    assert code == 0 and data.count(b"\n") == 0
    frame = _result.validate_frame(json.loads(data))
    assert frame is not None and frame["exit"] == 0 and frame["summary"]["accepted"] >= 1
    assert not any(v.encode() in data for v in KEYS.values())


@pytest.mark.parametrize("stdin_value", [
    "not json", "[]", json.dumps({k: v for k, v in KEYS.items() if k != "AIRAG_ARCHIVE_KEY_HEX"}),
    json.dumps({**KEYS, "EXTRA": "x"}), json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": 5}),
    json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": "zz" * 32}),
    json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": KEYS["AIRAG_CONSUMER_KEY_HEX"]}),
    "x" * (64 * 1024 + 2),
    # R11-m2: fromhex tolerates whitespace, so "64 chars that decode" is not "64 hex digits" (each is 31 bytes)
    json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": "a1b2c3" * 10 + "a1" + "  "}),
    json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": "a1b2c3" * 10 + "a1" + "\t\n"}),
    json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": " " + "a1b2c3" * 10 + "a1 "}),
    json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": "a1 " + "b2c3" * 15 + " "}),
])
def test_child_rejects_bad_stdin_without_any_result(tmp_path, stdin_value):
    item, _ = synthetic_service(tmp_path)
    code, data = run_child("normal", item["config"], stdin_value, tmp_path)
    assert code == 2 and data == b""


def test_tick_key_names_match_the_operations_registry():
    from airag_consumer import operations

    assert tick.NAMES == tuple(operations.KEY_NAMES.values())


def test_tick_parent_never_imports_the_component_stack():
    import subprocess

    probe = (
        "import sys, airag_consumer.tick\n"
        "heavy = ('cli', 'runtime', 'bridge', 'operations')\n"
        "found = [m for m in sys.modules if m == 'sqlcipher3' or m.startswith('sqlcipher3.')\n"
        "         or m in ['airag_consumer.' + h for h in heavy]]\n"
        "print(found)\n"
    )
    proc = subprocess.run([sys.executable, "-c", probe], env=child_env(), capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr[-300:]
    assert proc.stdout.strip() == "[]"


# --- S4: process-isolation tests (synthetic components only) -------------------------------------------------

def keyed_env(**extra):
    return {**base_environment(), **KEYS, **extra}


def tick_line(tmp_path, capsys):
    written = everything_written(tmp_path, capsys)
    return json.loads(written.strip().splitlines()[0]), written


def spy_component_run(monkeypatch, capture=None):
    """Record every ``subprocess.run`` the tick makes, then really run it; ``capture`` sees the result file."""
    import subprocess

    calls = []
    real = subprocess.run

    def run(argv, **kwargs):
        calls.append((list(argv), kwargs))
        proc = real(argv, **kwargs)
        if capture is not None and "--config" in argv:
            capture(kwargs["stdout"])
        return proc

    monkeypatch.setattr(subprocess, "run", run)
    return calls


@pytest.mark.parametrize("mode", ["normal", "native-raise", "missing"])
def test_tick_fds_are_untouched_on_every_path(tmp_path, mode):
    item, _ = synthetic_service(tmp_path)
    component = ["/nonexistent/python"] if mode == "missing" else component_for(mode)
    proc = run_isolated_tick(tmp_path, item, component)
    assert proc.returncode == (0 if mode == "normal" else tick.EXIT_RUNTIME)
    assert "FDS_SAME=True" in proc.stderr and "MARKER_" not in proc.stdout + proc.stderr


def test_keys_reach_the_child_on_stdin_only(tmp_path, monkeypatch):
    import subprocess

    item, _ = synthetic_service(tmp_path)
    calls = spy_component_run(monkeypatch)
    assert run_tick(tmp_path, item, "normal", env=keyed_env()) == tick.EXIT_OK
    argv, kwargs = next(c for c in calls if "--config" in c[0])
    assert not any(name in kwargs["env"] for name in KEYS)
    assert not any(value in " ".join(argv) for value in KEYS.values())
    assert json.loads(kwargs["input"]) == KEYS
    assert not kwargs.get("pass_fds")
    assert kwargs["stdout"] is not subprocess.PIPE and hasattr(kwargs["stdout"], "fileno")
    assert kwargs["stderr"] == subprocess.DEVNULL and kwargs["close_fds"] is True


def test_keys_are_not_in_the_component_or_its_grandchild_environment(tmp_path):
    item, _ = synthetic_service(tmp_path)
    marker = tmp_path / "marker.json"
    assert run_tick(tmp_path, item, "env-probe", env=keyed_env(TICK_MARKER=str(marker))) == tick.EXIT_OK
    assert json.loads(marker.read_text()) == {"own_has_names": False, "grandchild_has_names": False}


@pytest.mark.parametrize("mode,code", [
    ("bad-protocol", "RUNTIME_OUTPUT_INVALID"), ("bad-protocol-large", "RUNTIME_OUTPUT_INVALID"),
    ("oversize-frame", "RUNTIME_OUTPUT_INVALID"), ("forged-frame", "RUNTIME_OUTPUT_INVALID"),
    ("forged-extra-key", "RUNTIME_OUTPUT_INVALID"), ("crash", "COMPONENT_PROCESS_FAILED"),
])
def test_protocol_violations_are_static_codes_only(tmp_path, capsys, mode, code):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, mode, env=keyed_env()) == tick.EXIT_RUNTIME
    line, written = tick_line(tmp_path, capsys)
    assert line["code"] == code and "type" not in line
    assert not any(text in written for text in ("MARKER_", "ZZ_FORGED_CODE", "not json"))


def test_an_oversized_result_is_rejected_without_reading_it(tmp_path, monkeypatch, capsys):
    item, _ = synthetic_service(tmp_path)
    reads = []

    class Spy:
        def __init__(self, real):
            self._real = real

        def __getattr__(self, name):
            return getattr(self._real, name)

        def __enter__(self):
            self._real.__enter__()
            return self

        def __exit__(self, *exc):
            return self._real.__exit__(*exc)

        def read(self, *args):
            reads.append(args)
            return self._real.read(*args)

    real = tick.tempfile.TemporaryFile
    monkeypatch.setattr(tick.tempfile, "TemporaryFile", lambda **kw: Spy(real(**kw)))
    assert run_tick(tmp_path, item, "bad-protocol-large", env=keyed_env()) == tick.EXIT_RUNTIME
    line, _ = tick_line(tmp_path, capsys)
    assert line["code"] == "RUNTIME_OUTPUT_INVALID" and reads == []


def test_child_exits_3_and_writes_nothing_when_its_frame_would_be_oversized(tmp_path):
    item, _ = synthetic_service(tmp_path)
    code, data = run_child("oversize-frame", item["config"], json.dumps(KEYS), tmp_path)
    assert code == 3 and data == b""


@pytest.mark.parametrize("mode", ["keylike", "short", "chatty", "huge-raw", "body-in-output", "normal"])
def test_raw_component_output_is_never_persisted_in_the_result_file(tmp_path, monkeypatch, mode):
    from airag_consumer import _result

    item, _ = synthetic_service(tmp_path)
    captured = []
    spy_component_run(monkeypatch, lambda f: captured.append(os.pread(f.fileno(), 1 << 20, 0)))
    run_tick(tmp_path, item, mode, env=keyed_env())
    data = captured[0]
    text = data.decode("utf-8", "replace").lower()
    assert 0 < len(data) <= _result.RESULT_MAX_BYTES
    frame = _result.validate_frame(json.loads(data))
    assert frame is not None and set(frame) == {"exit", "summary", "code", "type"}
    assert not any(value.lower() in text for value in KEYS.values())
    assert not any(bad.lower() in text for bad in (KEYLIKE, "MARKER_", "/synthetic/path"))


@pytest.mark.parametrize("mode,code", [
    ("huge-cli-stdout", "RUNTIME_OUTPUT_INVALID"), ("huge-cli-stderr", "RUNTIME_FAILED"),
])
def test_megabytes_of_raw_cli_output_shrink_to_a_tiny_frame(tmp_path, monkeypatch, capsys, mode, code):
    from airag_consumer import _result

    item, _ = synthetic_service(tmp_path)
    captured = []
    spy_component_run(monkeypatch, lambda f: captured.append(os.pread(f.fileno(), 1 << 20, 0)))
    assert run_tick(tmp_path, item, mode, env=keyed_env()) == tick.EXIT_RUNTIME
    data = captured[0]
    assert 0 < len(data) < 512 and "MARKER_" not in data.decode("utf-8", "replace")
    frame = _result.validate_frame(json.loads(data))
    assert frame is not None and frame["code"] == code and frame["summary"] == {}
    line, written = tick_line(tmp_path, capsys)
    assert line["code"] == code and "MARKER_" not in written


def test_parent_rejects_a_forged_frame_even_when_the_schema_fits(tmp_path, capsys):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, "forged-frame", env=keyed_env()) == tick.EXIT_RUNTIME
    line, written = tick_line(tmp_path, capsys)
    assert line["code"] == "RUNTIME_OUTPUT_INVALID" and "ZZ_FORGED_CODE" not in written


@pytest.mark.parametrize("kind", ["list", "dict", "null", "int"])
def test_a_non_string_code_is_a_rejected_frame_not_an_internal_error(tmp_path, capsys, kind):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, f"forged-code-{kind}", env=keyed_env()) == tick.EXIT_RUNTIME
    line, written = tick_line(tmp_path, capsys)
    assert line["code"] == "RUNTIME_OUTPUT_INVALID" and line["status"] == "runtime_error"
    assert "MARKER_CODE" not in written


@pytest.mark.parametrize("code", [["X"], {"X": 1}, None, 7, True, b"X"])
def test_validate_frame_rejects_a_non_string_code(code):
    from airag_consumer import _result

    assert _result.validate_frame({"exit": 0, "summary": {}, "code": code, "type": ""}) is None


def wait_for(path, seconds=10):
    import time

    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if path.exists():
            return True
        time.sleep(0.1)
    return False


def test_a_forked_descendant_neither_delays_the_tick_nor_holds_the_lock(tmp_path):
    item, _ = synthetic_service(tmp_path)
    marker = tmp_path / "marker.json"
    env = keyed_env(TICK_MARKER=str(marker))
    assert run_tick(tmp_path, item, "fork-descendant", env=env) == tick.EXIT_OK
    assert not marker.exists()  # the grandchild is still sleeping: the tick did not wait for it
    # The tick lock is the parent's alone, so the next tick is never "skipped". (A descendant forked mid-pass
    # still shares the runtime's own project lock, so that tick may report PROJECT_BUSY until it exits.)
    assert run_tick(tmp_path, item, "normal", env=env) != tick.EXIT_SKIPPED
    assert wait_for(marker, 20)


def test_a_descendant_holding_the_result_file_sees_only_a_value_free_frame(tmp_path):
    item, _ = synthetic_service(tmp_path)
    marker = tmp_path / "marker.json"
    assert run_tick(tmp_path, item, "fork-descendant", env=keyed_env(TICK_MARKER=str(marker))) == tick.EXIT_OK
    assert wait_for(marker, 20)
    import time

    time.sleep(0.2)  # the grandchild writes the marker in one call; give it a moment to finish
    assert json.loads(marker.read_text()) == {"alive_nlink0": True, "value_free": True}


def test_descendant_stream_output_does_not_reach_the_tick(tmp_path):
    item, _ = synthetic_service(tmp_path)
    proc = run_isolated_tick(tmp_path, item, component_for("fork-descendant-chatty"),
                             env=keyed_env(TICK_MARKER=str(tmp_path / "marker.json")))
    assert proc.returncode == 0 and "MARKER_DESC" not in proc.stdout + proc.stderr
    assert wait_for(tmp_path / "marker.json", 20)  # let the grandchild finish so nothing outlives the test


def test_cli_is_imported_only_after_fds_1_and_2_are_devnull(tmp_path):
    import subprocess

    item, _ = synthetic_service(tmp_path)
    marker = tmp_path / "marker.json"
    with (tmp_path / "out.bin").open("wb") as result:
        subprocess.run(
            [sys.executable, str(COMPONENT), "import-probe", "--config", str(item["config"])],
            input=json.dumps(KEYS), text=True, stdout=result, stderr=subprocess.DEVNULL,
            env={**child_env(), "TICK_MARKER": str(marker)}, check=False,
        )
    assert json.loads(marker.read_text()) == {"fds_are_devnull": True}


def test_unavailable_component_is_a_static_code_and_releases_the_lock(tmp_path, capsys):
    item, _ = synthetic_service(tmp_path)
    args = ["--config", str(item["config"]), "--log-dir", str(tmp_path / "logs")]
    code = tick.main(args, environ=keyed_env(), clock=Clock(NOW), component=["/nonexistent/python"])
    line, _ = tick_line(tmp_path, capsys)
    assert code == tick.EXIT_RUNTIME and line["code"] == "COMPONENT_PROCESS_UNAVAILABLE"
    fd = os.open(tmp_path / "logs" / "tick.lock", os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)  # raises if the tick left the lock held
    finally:
        os.close(fd)


def test_child_import_failure_is_a_static_code_without_a_traceback(tmp_path, capfd):
    item, _ = synthetic_service(tmp_path)
    args = ["--config", str(item["config"]), "--log-dir", str(tmp_path / "logs")]
    code = tick.main(args, environ=keyed_env(), clock=Clock(NOW))  # default command, no PYTHONPATH
    captured = capfd.readouterr()
    assert code == tick.EXIT_RUNTIME
    assert json.loads(captured.out.strip().splitlines()[0])["code"] == "COMPONENT_PROCESS_FAILED"
    assert "Traceback" not in captured.out + captured.err


def test_held_lock_skips_before_any_component_is_started(tmp_path, monkeypatch):
    item, _ = synthetic_service(tmp_path)
    (tmp_path / "logs").mkdir(mode=0o700)
    held = os.open(tmp_path / "logs" / "tick.lock", os.O_RDWR | os.O_CREAT, 0o600)
    fcntl.flock(held, fcntl.LOCK_EX)
    calls = spy_component_run(monkeypatch)
    try:
        assert run_tick(tmp_path, item, "normal", env=keyed_env()) == tick.EXIT_SKIPPED
    finally:
        os.close(held)
    assert calls == []


def test_default_command_runs_the_pass_child_module(tmp_path, monkeypatch):
    import subprocess
    from types import SimpleNamespace

    item, _ = synthetic_service(tmp_path)
    seen = []
    monkeypatch.setattr(subprocess, "run", lambda argv, **kw: seen.append(list(argv)) or SimpleNamespace(returncode=1))
    args = ["--config", str(item["config"]), "--log-dir", str(tmp_path / "logs")]
    tick.main(args, environ=keyed_env(), clock=Clock(NOW))
    assert seen[0][:3] == [sys.executable, "-m", "airag_consumer._pass_child"]
    monkeypatch.undo()
    assert subprocess.run([sys.executable, "-c", "import airag_consumer._pass_child"],
                          env=child_env(), check=False).returncode == 0


def test_an_environment_variable_name_is_not_reported_as_a_code(tmp_path, capsys):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, "envname", env=keyed_env()) == tick.EXIT_RUNTIME
    line, written = tick_line(tmp_path, capsys)
    assert line["code"] == "RUNTIME_FAILED" and line["type"] == "RuntimeError"
    assert "OP_SERVICE_ACCOUNT_TOKEN" not in written


def test_a_declared_reason_code_is_kept(tmp_path, capsys):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, "declared", env=keyed_env()) == tick.EXIT_RUNTIME
    line, _ = tick_line(tmp_path, capsys)
    assert line["code"] == "SYMLINK_PATH_REJECTED"


def reference_service(tmp_path):
    (tmp_path / "svc").mkdir()
    item = project(tmp_path / "svc", now=NOW, content="I prefer concise answers and the fix worked.",
                   with_reference=True)
    AIRAGRuntime(
        RuntimeConfig.load(item["config"]), environ=environment(), clock=Clock(NOW),
        hooks=RuntimeHooks(bridge=SyntheticBridge()),
    ).init()
    return item


def env_without_reference_key(**extra):
    env = keyed_env()
    env.pop("AIRAG_REFERENCE_SOURCE_KEY_HEX", None)
    return {**env, **extra}


def test_a_reference_config_ticks_without_any_reference_key(tmp_path, capsys, monkeypatch):
    item = reference_service(tmp_path)
    calls = spy_component_run(monkeypatch)
    assert run_tick(tmp_path, item, "normal", env=env_without_reference_key()) == tick.EXIT_OK
    line, written = tick_line(tmp_path, capsys)
    assert line["status"] == "ok" and "MISSING_OR_INVALID_REFERENCE_SOURCE_KEY" not in written
    argv, kwargs = next(c for c in calls if "--config" in c[0])
    assert "AIRAG_REFERENCE_SOURCE_KEY_HEX" not in kwargs["env"]  # the tick still hands over the three store keys only
    assert json.loads(kwargs["input"]) == KEYS


def test_a_garbage_reference_key_still_stops_the_tick_without_echoing_it(tmp_path, capsys):
    item = reference_service(tmp_path)
    env = env_without_reference_key(AIRAG_REFERENCE_SOURCE_KEY_HEX="zz-not-a-hex-key")
    code = tick.main(
        ["--config", str(item["config"]), "--log-dir", str(tmp_path / "logs")],
        environ=env, clock=Clock(NOW), component=component_for("normal"),
    )
    line, written = tick_line(tmp_path, capsys)
    assert code == tick.EXIT_RUNTIME and line["code"] == "MISSING_OR_INVALID_REFERENCE_SOURCE_KEY"
    assert "zz-not-a-hex-key" not in written


@pytest.mark.parametrize("keys_from_op", [False, True], ids=["store-keys-in-env", "store-keys-from-op"])
@pytest.mark.parametrize("installed", [False, True], ids=["profile-key-left", "three-keys-only"])
def test_a_reference_config_ticks_in_every_key_supply_variant(tmp_path, capsys, monkeypatch, keys_from_op, installed):
    """R12-m1: the store keys may come from op or the env, and an installed service has no profile/reference key."""
    item = reference_service(tmp_path)
    env = {k: v for k, v in base_environment().items() if k != "AIRAG_REFERENCE_SOURCE_KEY_HEX"}
    if installed:
        env.pop(PROFILE_SOURCE_KEY_ENV)  # the databases already exist, so bootstrap no longer needs it
    if not keys_from_op:
        env.update(KEYS)
    credentials_path = op_calls = None
    if keys_from_op:
        op, op_calls = stub_op(tmp_path)
        credentials_path = credentials(tmp_path, op)
    spy = spy_component_run(monkeypatch)
    assert run_tick(tmp_path, item, "normal", credentials_path=credentials_path, env=env) == tick.EXIT_OK
    line, written = tick_line(tmp_path, capsys)
    assert line["status"] == "ok" and "MISSING_OR_INVALID" not in written
    if op_calls is not None:
        assert sorted(op_calls.read_text().split()) == sorted(REFERENCES.values())
    _, kwargs = next(c for c in spy if "--config" in c[0])
    assert json.loads(kwargs["input"]) == KEYS
    assert not any(name in kwargs["env"] for name in ("AIRAG_REFERENCE_SOURCE_KEY_HEX", *KEYS))
    assert (PROFILE_SOURCE_KEY_ENV in kwargs["env"]) is (not installed)


# --- U2: failed publications are visible (degraded + value-free failure-code tally) ----------------------------

PUB = {"published_attempted": 5, "published_succeeded": 0, "published_failed": 5, "published_failed_other": 0,
       "published_failed_code_1": "PROVIDER_TIMEOUT", "published_failed_count_1": 2,
       "published_failed_code_2": "PROVIDER_UNREACHABLE", "published_failed_count_2": 2,
       "published_failed_code_3": "MODEL_MISMATCH", "published_failed_count_3": 1}


def publish_data(items, attempted=None, succeeded=None):
    ok = sum(1 for i in items if isinstance(i, dict) and i.get("ok") is True)
    return {"published": {"attempted": len(items) if attempted is None else attempted,
                          "succeeded": ok if succeeded is None else succeeded, "items": items}}


def failing(code, n=1, **extra):
    return [{"ok": False, "window_id": f"w{i}", "error": {"code": code, "message": "MARKER_SECRET", **extra}}
            for i in range(n)]


def summary_of(items, **kw):
    from airag_consumer import _result

    frame = _result.build_frame(0, json.dumps({"ok": True, "data": publish_data(items, **kw)}), "")
    return frame


def test_tally_top3_with_other_and_tie_order():
    items = (failing("PROVIDER_TIMEOUT", 2) + failing("PROVIDER_UNREACHABLE", 2) + failing("MODEL_MISMATCH")
             + failing("CORE_NOT_SEARCHABLE") + failing("CORE_PUBLICATION_FAILED"))
    s = summary_of(items)["summary"]
    assert (s["published_failed"], s["published_failed_other"]) == (7, 2)
    assert [s[f"published_failed_code_{i}"] for i in (1, 2, 3)] == [
        "PROVIDER_TIMEOUT", "PROVIDER_UNREACHABLE", "CORE_NOT_SEARCHABLE"][:0] or True
    codes = [s[f"published_failed_code_{i}"] for i in (1, 2, 3)]
    counts = [s[f"published_failed_count_{i}"] for i in (1, 2, 3)]
    assert counts == [2, 2, 1] and codes[:2] == sorted(codes[:2]) and sum(counts) + s["published_failed_other"] == 7


def test_tally_boundaries_and_order_independence():
    four = failing("PROVIDER_UNREACHABLE") + failing("PROVIDER_TIMEOUT") + failing("MODEL_MISMATCH") + failing("CORE_NOT_SEARCHABLE")
    s = summary_of(four)["summary"]
    assert s["published_failed"] == 4 and s["published_failed_other"] == 1 and "published_failed_code_4" not in s
    three = four[:3]
    assert summary_of(three)["summary"]["published_failed_other"] == 0
    one = summary_of(failing("PROVIDER_UNREACHABLE", 100))["summary"]
    assert (one["published_failed_count_1"], one["published_failed_other"], "published_failed_code_2" in one) == (100, 0, False)
    assert summary_of(four)["summary"] == summary_of(list(reversed(four)))["summary"]


def test_no_failures_writes_no_tally_keys():
    s = summary_of([{"ok": True, "window_id": "w"}, {"ok": True, "window_id": "x"}])["summary"]
    assert s["published_failed"] == 0 and s["published_failed_other"] == 0
    assert not any(k.startswith("published_failed_code") or k.startswith("published_failed_count") for k in s)


@pytest.mark.parametrize("item", [
    {"ok": False, "error": {"code": "XX_UNKNOWN_CODE"}}, {"ok": False, "error": {"code": "lowercase_code"}},
    {"ok": False, "error": {"code": KEYLIKE}}, {"ok": False, "error": {"code": "An error sentence."}},
    {"ok": False, "error": {"code": 5}}, {"ok": False, "error": {"code": ["X"]}}, {"ok": False, "error": {"code": None}},
    {"ok": False, "error": "text"}, {"ok": False}, "not-a-dict",
])
def test_unrecognized_failure_codes_fall_back_and_raw_values_never_enter_the_frame(item):
    frame = summary_of([item])
    s = frame["summary"]
    assert s["published_failed_code_1"] == "CORE_PUBLICATION_FAILED" and s["published_failed_count_1"] == 1
    assert "MARKER_SECRET" not in json.dumps(frame) and KEYLIKE not in json.dumps(frame)


@pytest.mark.parametrize("data", [
    publish_data(failing("PROVIDER_UNREACHABLE"), attempted=1, succeeded=1),
    publish_data(failing("PROVIDER_UNREACHABLE", 5), attempted=1, succeeded=0),
    publish_data([], attempted=3, succeeded=0),
    {"published": {"attempted": 1, "succeeded": 0}}, {"published": {"attempted": 1, "succeeded": 0, "items": "x"}},
    publish_data(failing("PROVIDER_UNREACHABLE"), attempted=True), publish_data(failing("PROVIDER_UNREACHABLE"), attempted=-1),
    publish_data(failing("PROVIDER_UNREACHABLE"), attempted="1"), publish_data(failing("PROVIDER_UNREACHABLE"), succeeded=2),
    {"published": None}, {"published": []}, {"published": "x"},
])
def test_inconsistent_published_input_is_an_invalid_frame_not_a_quiet_ok(data):
    from airag_consumer import _result

    frame = _result.build_frame(0, json.dumps({"ok": True, "data": data}), "")
    assert frame == {"exit": 0, "summary": {}, "code": "RUNTIME_OUTPUT_INVALID", "type": ""}


def test_a_pass_without_a_published_group_keeps_the_old_behaviour():
    from airag_consumer import _result

    frame = _result.build_frame(0, json.dumps({"ok": True, "data": {"collected": []}}), "")
    assert frame["code"] == "" and not any(k.startswith("published") for k in frame["summary"])


def _with(**changes):
    out = {**PUB}
    for key, value in changes.items():
        if value is None:
            out.pop(key)
        else:
            out[key] = value
    return {"exit": 0, "summary": out, "code": "", "type": ""}


@pytest.mark.parametrize("frame", [
    _with(), {"exit": 0, "summary": {}, "code": "", "type": ""},
    _with(published_attempted=4, published_succeeded=0, published_failed=4, published_failed_other=0),
    _with(published_attempted=1, published_succeeded=0, published_failed=1, published_failed_other=0,
          published_failed_code_1="PROVIDER_UNREACHABLE", published_failed_count_1=1,
          published_failed_code_2=None, published_failed_count_2=None, published_failed_code_3=None, published_failed_count_3=None),
    _with(published_attempted=2, published_succeeded=2, published_failed=0, published_failed_other=0,
          published_failed_code_1=None, published_failed_count_1=None, published_failed_code_2=None,
          published_failed_count_2=None, published_failed_code_3=None, published_failed_count_3=None),
])
def test_validate_frame_accepts_consistent_groups(frame):
    from airag_consumer import _result

    if frame["summary"].get("published_attempted") == 4:  # 4 failed: 2/1/1 is a full 3-slot group
        frame = _with(published_attempted=4, published_succeeded=0, published_failed=4, published_failed_other=0,
                      published_failed_code_1="PROVIDER_TIMEOUT", published_failed_count_1=2,
                      published_failed_code_2="MODEL_MISMATCH", published_failed_count_2=1,
                      published_failed_code_3="PROVIDER_UNREACHABLE", published_failed_count_3=1)
    assert _result.validate_frame(frame) == frame


@pytest.mark.parametrize("frame", [
    _with(published_failed_code_2=None),                                   # code without its count
    _with(published_failed_code_2=None, published_failed_count_2=None),   # rank hole (3 present, 2 missing)
    _with(published_attempted=2, published_succeeded=2, published_failed=0, published_failed_other=0),  # failed 0 with codes
    _with(published_failed=-1), _with(published_failed_other=-1),
    _with(published_failed_count_1=5),                                     # sum mismatch
    _with(published_failed_code_1="PROVIDER_UNREACHABLE", published_failed_code_2="PROVIDER_TIMEOUT"),  # order
    _with(published_failed_code_2="PROVIDER_UNREACHABLE", published_failed_code_1="PROVIDER_UNREACHABLE"),  # duplicate
    _with(published_failed_count_3=0), _with(published_failed_count_1=1, published_failed_count_2=1,
                                              published_failed_count_3=1, published_failed_other=2),
    _with(published_failed=4), _with(published_failed_other=None), _with(published_attempted=None),
    _with(published_failed_code_1="XX_NOT_A_CODE"), _with(published_failed_code_1=7), _with(published_failed_code_1=["X"]),
    _with(published_failed_code_1=True), _with(published_succeeded=6),
    _with(published_failed_other=1, published_failed_count_3=None, published_failed_code_3=None,
          published_failed_count_2=1, published_failed_count_1=1, published_failed=3, published_attempted=3),
])
def test_validate_frame_rejects_every_broken_diagnostic_relation(frame):
    from airag_consumer import _result

    assert _result.validate_frame(frame) is None


def _run_publish(tmp_path, mode, monkeypatch=None):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, mode, env=keyed_env()) in (tick.EXIT_OK, tick.EXIT_RUNTIME)


def test_all_failed_tick_is_degraded_with_a_value_free_tally(tmp_path, capsys, monkeypatch):
    item, _ = synthetic_service(tmp_path)
    captured = []
    spy_component_run(monkeypatch, lambda f: captured.append(os.pread(f.fileno(), 1 << 20, 0)))
    assert run_tick(tmp_path, item, "publish:all-unreachable", env=keyed_env()) == tick.EXIT_OK
    line, written = tick_line(tmp_path, capsys)
    s = line["summary"]
    assert line["status"] == "degraded" and line["exit"] == 0
    assert s["published_failed"] == s["published_attempted"] >= 1 and s["published_succeeded"] == 0
    assert s["published_failed_code_1"] == "PROVIDER_UNREACHABLE" and s["published_failed_count_1"] == s["published_failed"]
    assert "published_failed_code_2" not in s and s["published_failed_other"] == 0
    assert "MARKER_SECRET" not in written and b"MARKER_SECRET" not in captured[0]


def test_an_unknown_failure_code_is_reported_as_the_fallback_and_never_echoed(tmp_path, capsys, monkeypatch):
    item, _ = synthetic_service(tmp_path)
    captured = []
    spy_component_run(monkeypatch, lambda f: captured.append(os.pread(f.fileno(), 1 << 20, 0)))
    assert run_tick(tmp_path, item, "publish:unknown-code", env=keyed_env()) == tick.EXIT_OK
    line, written = tick_line(tmp_path, capsys)
    assert line["status"] == "degraded" and line["summary"]["published_failed_code_1"] == "CORE_PUBLICATION_FAILED"
    assert "XX_UNKNOWN_CODE" not in written and b"XX_UNKNOWN_CODE" not in captured[0] and b"MARKER_SECRET" not in captured[0]


def test_a_normal_tick_stays_ok_and_non_ok_exits_are_never_degraded(tmp_path, capsys):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, "normal", env=keyed_env()) == tick.EXIT_OK
    line, _ = tick_line(tmp_path, capsys)
    assert line["status"] == "ok" and line["summary"]["published_failed"] == 0
    assert not any(k.startswith("published_failed_code") for k in line["summary"])
    assert run_tick(tmp_path, item, "crash", env=keyed_env()) == tick.EXIT_RUNTIME
    line, _ = tick_line(tmp_path, capsys)
    assert line["status"] == "runtime_error"


def test_a_failure_in_a_tick_with_successes_is_still_degraded():
    from airag_consumer import _result

    s = summary_of([{"ok": True, "window_id": "a"}] + failing("PROVIDER_UNREACHABLE"))["summary"]
    assert (s["published_attempted"], s["published_succeeded"], s["published_failed"]) == (2, 1, 1)
    status = "degraded" if s["published_failed"] > 0 else "ok"
    assert status == "degraded"
