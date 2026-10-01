from __future__ import annotations

from datetime import datetime, timedelta, timezone
import errno
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
from airag_consumer.runtime import AIRAGRuntime, RuntimeConfig, RuntimeHooks
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
    return item, hooks


def base_environment() -> dict[str, str]:
    return {k: v for k, v in environment().items() if k not in KEYS}


def run_tick(tmp_path, item, hooks, *, credentials_path=None, env=None, extra=()):
    args = ["--config", str(item["config"]), "--log-dir", str(tmp_path / "logs"), *extra]
    if credentials_path is not None:
        args += ["--credentials", str(credentials_path)]
    return tick.main(args, environ=base_environment() if env is None else env,
                     clock=Clock(NOW), hooks=hooks)


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
        environ=base_environment(), clock=Clock(NOW), hooks=hooks,
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


class RaisingBridge(SyntheticBridge):
    @staticmethod
    def publish_pending_windows(lifecycle, scope, core, **_kwargs):
        raise RuntimeError(KEYLIKE)


class ChattyBridge(SyntheticBridge):
    @staticmethod
    def publish_pending_windows(lifecycle, scope, core, **kwargs):
        print("MARKER_BODY_PRINT")
        sys.stderr.write("MARKER_QUOTE_STDERR\n")
        os.write(1, b"MARKER_FD_STDOUT\n")
        os.write(2, b"MARKER_FD_STDERR\n")
        return SyntheticBridge.publish_pending_windows(lifecycle, scope, core, **kwargs)


def test_key_shaped_error_text_never_reaches_output_or_log(tmp_path, capsys):
    # R8-M1: an error message that looks like a code must not be trusted as one.
    item, _ = synthetic_service(tmp_path)
    op, _ = stub_op(tmp_path)
    code = run_tick(tmp_path, item, RuntimeHooks(bridge=RaisingBridge()), credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    line = json.loads(written.strip().splitlines()[0])
    assert code == tick.EXIT_RUNTIME and line["status"] == "runtime_error"
    assert KEYLIKE.lower() not in written.lower() and no_key_text(written.lower())
    assert line["code"] == "RUNTIME_FAILED" and line["type"] == "RuntimeError"


def test_component_output_is_discarded_at_process_level(tmp_path, capfd):
    # R8-M1: whatever a component prints during the pass must not reach launchd's stdout/stderr.
    item, _ = synthetic_service(tmp_path)
    op, _ = stub_op(tmp_path)
    code = run_tick(tmp_path, item, RuntimeHooks(bridge=ChattyBridge()), credentials_path=credentials(tmp_path, op))
    captured = capfd.readouterr()
    assert code == tick.EXIT_OK
    assert "MARKER_" not in captured.out + captured.err
    assert json.loads(captured.out.strip().splitlines()[-1])["status"] == "ok"


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
                         hooks=hooks) == tick.EXIT_OK
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


class ShortValueBridge(SyntheticBridge):
    @staticmethod
    def publish_pending_windows(lifecycle, scope, core, **_kwargs):
        raise RuntimeError("SHORT_SECRET_VALUE")


def test_short_error_value_is_not_trusted_as_a_reason_code(tmp_path, capsys):
    # R9-M1: only reason codes this package really emits are reported; anything else is RUNTIME_FAILED.
    item, _ = synthetic_service(tmp_path)
    op, _ = stub_op(tmp_path)
    code = run_tick(tmp_path, item, RuntimeHooks(bridge=ShortValueBridge()), credentials_path=credentials(tmp_path, op))
    written = everything_written(tmp_path, capsys)
    line = json.loads(written.strip().splitlines()[0])
    assert code == tick.EXIT_RUNTIME and "SHORT_SECRET_VALUE" not in written
    assert line["code"] == "RUNTIME_FAILED" and line["type"] == "RuntimeError"


@pytest.mark.parametrize("raising", [False, True])
def test_buffered_component_output_is_flushed_into_the_discard_window(monkeypatch, capfd, raising):
    # R9-M1: a stream object cached before the pass must not flush its marker after fds are restored.
    cached_out = os.fdopen(1, "w", buffering=8192, closefd=False)
    cached_err = os.fdopen(2, "w", buffering=8192, closefd=False)
    monkeypatch.setattr(sys, "stdout", cached_out)
    monkeypatch.setattr(sys, "stderr", cached_err)
    try:
        with tick._discard_component_output():
            cached_out.write("MARKER_CACHED_OUT\n")
            cached_err.write("MARKER_CACHED_ERR\n")
            if raising:
                raise RuntimeError("inside")
    except RuntimeError:
        assert raising
    cached_out.flush()
    cached_err.flush()
    captured = capfd.readouterr()
    assert "MARKER_" not in captured.out + captured.err


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
                     environ=base_environment(), clock=Clock(NOW), hooks=hooks)
    assert code == tick.EXIT_CONFIG and not calls.exists()
    assert today.read_text() == "existing\n" and old.exists()
    assert sorted(p.name for p in target.iterdir()) == sorted([today.name, old.name])


def test_discard_setup_failure_does_not_leak_duplicated_fds(monkeypatch):
    # R9-m1
    real_dup, real_open, made = os.dup, os.open, []

    def dup(fd):
        made.append(real_dup(fd))
        return made[-1]

    def failing_open(path, *args, **kwargs):
        if path == os.devnull:
            raise OSError(errno.EMFILE, "synthetic")
        return real_open(path, *args, **kwargs)

    monkeypatch.setattr(os, "dup", dup)
    monkeypatch.setattr(os, "open", failing_open)
    with pytest.raises(OSError):
        with tick._discard_component_output():
            pass
    monkeypatch.undo()
    try:
        for fd in made:
            with pytest.raises(OSError):
                os.fstat(fd)
    finally:
        for fd in made:
            try:
                os.close(fd)
            except OSError:
                pass


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
