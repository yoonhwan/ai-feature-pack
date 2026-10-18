"""R-F: the tick's key-file source. A credentials file that names ``store_keys_file`` makes the tick read the three
store keys from that owner-only file and never call `op` (no permission window, no fallback). Any problem with the
file is one explicit, value-free failure: OP_STORE_KEYS_INVALID."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from airag_consumer import tick
from test_tick import (
    KEYS, TOKEN, everything_written, no_key_text, run_tick, stub_op, synthetic_service,
)

MARKER = "f" * 62 + "zz"  # a recognizable, deliberately malformed "key" that must never be echoed anywhere
KINDS = {"unreadable", "not_regular", "owner", "mode", "content", "setting"}
HINT = "tick store_keys_invalid: rewrite the store-keys file from a terminal"


def write_store(tmp_path: Path, content=None, *, mode=0o600, name="store-keys") -> Path:
    path = tmp_path / name
    path.write_text(json.dumps(KEYS if content is None else content), encoding="utf-8")
    path.chmod(mode)
    return path


def store_credentials(tmp_path: Path, store, *, op: Path | None = None) -> Path:
    settings: dict[str, object] = {"store_keys_file": str(store)}
    if op is not None:  # a working `op` that must NOT be reached
        token = tmp_path / "token"
        token.write_text("synthetic-token\n", encoding="utf-8")
        settings.update({"token_file": str(token), "op": str(op), "references": {
            name: f"op://synthetic/{name}" for name in KEYS}})
    path = tmp_path / "credentials.json"
    path.write_text(json.dumps(settings), encoding="utf-8")
    return path


def test_valid_store_file_fills_keys_and_never_starts_a_process(tmp_path, monkeypatch):
    def boom(*args, **kwargs):
        raise AssertionError("a subprocess was started")

    monkeypatch.setattr(tick.subprocess, "run", boom)
    env: dict[str, str] = {}
    tick.load_keys(env, store_credentials(tmp_path, write_store(tmp_path)))
    assert {name: env[name] for name in KEYS} == KEYS


def test_existing_environment_key_wins_over_the_file(tmp_path):
    own = "1" * 64
    env = {"AIRAG_CONSUMER_KEY_HEX": own}
    tick.load_keys(env, store_credentials(tmp_path, write_store(tmp_path)))
    assert env["AIRAG_CONSUMER_KEY_HEX"] == own
    assert env["AIRAG_PROJECTION_KEY_HEX"] == KEYS["AIRAG_PROJECTION_KEY_HEX"]
    assert env["AIRAG_ARCHIVE_KEY_HEX"] == KEYS["AIRAG_ARCHIVE_KEY_HEX"]


def test_file_is_not_read_when_the_environment_has_every_key(tmp_path):
    env = dict(KEYS)
    tick.load_keys(env, store_credentials(tmp_path, tmp_path / "does-not-exist"))
    assert env == KEYS


def _bad_store(tmp_path, case, monkeypatch) -> Path:
    path = tmp_path / "store-keys"
    if case == "missing":
        return path
    if case == "directory":
        path.mkdir()
        path.chmod(0o600)
        return path
    if case == "symlink":
        target = write_store(tmp_path, name="real-keys")
        path.symlink_to(target)
        return path
    if case == "fifo":
        os.mkfifo(path, 0o600)
        return path
    if case == "foreign_owner":
        write_store(tmp_path)
        monkeypatch.setattr(tick.os, "getuid", lambda: os.stat(path).st_uid + 1)
        return path
    if case in ("mode_0644", "mode_0640", "mode_0400", "mode_0700", "mode_0660"):
        return write_store(tmp_path, mode=int(case[-4:], 8))
    content = {
        "not_json": "not json at all {",
        "not_dict": json.dumps([MARKER]),
        "key_missing": json.dumps({k: v for k, v in list(KEYS.items())[:2]}),
        "extra_key": json.dumps({**KEYS, "EXTRA": KEYS["AIRAG_ARCHIVE_KEY_HEX"]}),
        "short_value": json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": MARKER[:-1]}),
        "non_hex_value": json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": MARKER}),
        "non_string_value": json.dumps({**KEYS, "AIRAG_ARCHIVE_KEY_HEX": 12345}),
        "empty_file": "",
        "oversized": json.dumps({**KEYS, "pad": MARKER * 200}),
        "not_utf8": None,
    }[case]
    if content is None:
        path.write_bytes(b"\xff\xfe" + MARKER.encode())
    else:
        path.write_text(content, encoding="utf-8")
    path.chmod(0o600)
    return path


BAD_CASES = [
    "missing", "directory", "symlink", "fifo", "foreign_owner",
    "mode_0644", "mode_0640", "mode_0400", "mode_0700", "mode_0660",
    "not_json", "not_dict", "key_missing", "extra_key", "short_value", "non_hex_value", "non_string_value",
    "empty_file", "oversized", "not_utf8",
]


@pytest.mark.parametrize("case", BAD_CASES)
def test_any_problem_is_one_value_free_failure_without_op_fallback(tmp_path, monkeypatch, case):
    store = _bad_store(tmp_path, case, monkeypatch)
    op, calls = stub_op(tmp_path)  # a fully working op: reaching it would be the fallback this test forbids
    env: dict[str, str] = {}
    with pytest.raises(tick.TickError) as raised:
        tick.load_keys(env, store_credentials(tmp_path, store, op=op))
    error = raised.value
    assert (error.exit_code, error.code) == (tick.EXIT_KEYS, "OP_STORE_KEYS_INVALID")
    assert error.kind in KINDS
    assert not calls.exists() and env == {}
    for text in (str(error), repr(error), error.code, error.kind, repr(error.args)):
        assert MARKER not in text and no_key_text(text)
    assert error.__cause__ is None and error.__suppress_context__  # no chained exception that could carry a value


@pytest.mark.parametrize("setting", [5, "", "relative/store-keys", ["x"]])
def test_a_present_but_unusable_setting_is_the_same_failure(tmp_path, setting):
    path = tmp_path / "credentials.json"
    path.write_text(json.dumps({"store_keys_file": setting}), encoding="utf-8")
    with pytest.raises(tick.TickError) as raised:
        tick.load_keys({}, path)
    assert (raised.value.exit_code, raised.value.code, raised.value.kind) == (tick.EXIT_KEYS, "OP_STORE_KEYS_INVALID", "setting")


def test_without_the_setting_the_op_path_is_unchanged(tmp_path):
    op, calls = stub_op(tmp_path)
    token = tmp_path / "token"
    token.write_text(TOKEN + "\n", encoding="utf-8")
    credentials_path = tmp_path / "credentials.json"
    credentials_path.write_text(json.dumps({"token_file": str(token), "op": str(op), "references": {
        "AIRAG_CONSUMER_KEY_HEX": "op://synthetic/consumer", "AIRAG_PROJECTION_KEY_HEX": "op://synthetic/projection",
        "AIRAG_ARCHIVE_KEY_HEX": "op://synthetic/archive"}}), encoding="utf-8")
    env: dict[str, str] = {}
    tick.load_keys(env, credentials_path)
    assert calls.exists() and {name: env[name] for name in KEYS} == KEYS


def test_full_tick_with_a_valid_file_runs_without_op_and_leaks_nothing(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    op, calls = stub_op(tmp_path)
    credentials_path = store_credentials(tmp_path, write_store(tmp_path), op=op)
    code = run_tick(tmp_path, item, hooks, credentials_path=credentials_path)
    written = everything_written(tmp_path, capsys)
    assert code == tick.EXIT_OK and not calls.exists()
    line = json.loads(written.strip().splitlines()[-1])
    assert line["status"] == "ok" and line["probe"]["keys"] == []  # no `op read` attempt was recorded
    assert no_key_text(written)
    assert not any(name in os.environ for name in KEYS)


def test_full_tick_with_a_bad_file_fails_once_with_the_hint_and_no_value(tmp_path, capsys, monkeypatch):
    item, hooks = synthetic_service(tmp_path)
    op, calls = stub_op(tmp_path)
    store = write_store(tmp_path, {**KEYS, "AIRAG_ARCHIVE_KEY_HEX": MARKER})
    credentials_path = store_credentials(tmp_path, store, op=op)
    code = run_tick(tmp_path, item, hooks, credentials_path=credentials_path)
    written = everything_written(tmp_path, capsys)
    assert code == tick.EXIT_KEYS and not calls.exists()
    line = json.loads(written.strip().splitlines()[0])
    assert (line["status"], line["exit"], line["code"]) == ("key_error", 30, "OP_STORE_KEYS_INVALID")
    assert line["type"] in KINDS
    assert MARKER not in written and no_key_text(written)


def test_the_hint_is_one_fixed_stderr_line_only_for_this_failure(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    run_tick(tmp_path, item, hooks, credentials_path=store_credentials(tmp_path, tmp_path / "absent"))
    assert capsys.readouterr().err.splitlines().count(HINT) == 1
    other = tmp_path / "other"
    other.mkdir()
    item2, hooks2 = synthetic_service(other)
    run_tick(other, item2, hooks2, credentials_path=store_credentials(other, other / "absent2"))
    assert capsys.readouterr().err.splitlines().count(HINT) == 1  # one per failing tick, not accumulated
    third = tmp_path / "third"
    third.mkdir()
    item3, hooks3 = synthetic_service(third)
    op, _ = stub_op(third)
    assert run_tick(third, item3, hooks3, credentials_path=store_credentials(third, write_store(third), op=op)) == tick.EXIT_OK
    assert HINT not in capsys.readouterr().err


def test_a_store_file_whose_keys_are_not_distinct_is_refused(tmp_path):
    same = {name: KEYS["AIRAG_ARCHIVE_KEY_HEX"] for name in KEYS}
    with pytest.raises(tick.TickError) as raised:
        tick.load_keys({}, store_credentials(tmp_path, write_store(tmp_path, same)))
    assert raised.value.code == "STORE_KEYS_MUST_BE_DISTINCT"
