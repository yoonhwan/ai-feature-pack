"""R-H: the `op` child gets HOME=<real home>/.config/airag/op-home (an own, 0700, non-symlink directory) and nothing
else about the tick changes. A bad directory is one explicit value-free failure (OP_HOME_INVALID) that never calls
`op` and never falls back to the real HOME (the real HOME is what makes `op` open another app's data)."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from airag_consumer import tick
from test_tick import (
    KEYS, REFERENCES, TOKEN, everything_written, no_key_text, run_tick, stub_op, synthetic_service,
)

KINDS = {"unreadable", "symlink", "not_dir", "owner", "mode", "setting"}


def home_of(tmp_path: Path) -> Path:
    home = tmp_path / "realhome"
    home.mkdir(exist_ok=True)
    return home


def op_home_of(home: Path) -> Path:
    return home / ".config" / "airag" / "op-home"


def recording_op(tmp_path: Path):
    """A fake `op` that also records its HOME and the names of its whole environment."""
    op, calls = stub_op(tmp_path)
    seen_home, seen_env = tmp_path / "op-home-seen.txt", tmp_path / "op-env-seen.txt"
    op.write_text(op.read_text().replace(
        'echo "$2" >> ', f'echo "$HOME" >> "{seen_home}"\nenv >> "{seen_env}"\necho "$2" >> ', 1))
    return op, calls, seen_home, seen_env


def creds(tmp_path: Path, op: Path, *, token_ref: str | None = None) -> Path:
    token = tmp_path / "tok"
    token.write_text(TOKEN + "\n", encoding="utf-8")
    path = tmp_path / "credentials.json"
    path.write_text(json.dumps({"token_file": token_ref or str(token), "op": str(op), "references": REFERENCES}),
                    encoding="utf-8")
    return path


def test_child_home_is_the_isolated_directory_and_the_real_home_is_untouched(tmp_path, monkeypatch):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    op, calls, seen_home, _ = recording_op(tmp_path)
    env = {"HOME": str(home), "PATH": os.environ["PATH"]}
    tick.load_keys(env, creds(tmp_path, op))
    assert set(seen_home.read_text().split()) == {str(op_home_of(home))}  # every one of the 3 children
    assert len(seen_home.read_text().split()) == 3
    assert env["HOME"] == str(home) and os.environ["HOME"] == str(home)  # tick process / caller env: HOME unchanged
    assert {name: env[name] for name in KEYS} == KEYS


def test_the_rest_of_the_child_environment_is_the_allowlist_unchanged(tmp_path, monkeypatch):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    op, _, _, seen_env = recording_op(tmp_path)
    env = {"HOME": str(home), "PATH": os.environ["PATH"], "LANG": "C.UTF-8", "USER": "u", "OP_EXTRA_SECRET": "x",
           "OTHER_RUNTIME_KEY_HEX": "ab" * 32}
    tick.load_keys(env, creds(tmp_path, op))
    names = {line.split("=", 1)[0] for line in seen_env.read_text().splitlines() if "=" in line}
    assert {"PATH", "HOME", "LANG", "USER", "OP_SERVICE_ACCOUNT_TOKEN"} <= names
    assert not names & {"OP_EXTRA_SECRET", "OTHER_RUNTIME_KEY_HEX", "OP_CACHE", "OP_CONFIG_DIR"}
    assert "LANG=C.UTF-8" in seen_env.read_text()


def test_token_file_is_still_read_through_the_real_home(tmp_path, monkeypatch):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    (home / "tok").write_text(TOKEN + "\n", encoding="utf-8")
    op, calls, _, _ = recording_op(tmp_path)
    env = {"HOME": str(home), "PATH": os.environ["PATH"]}
    tick.load_keys(env, creds(tmp_path, op, token_ref="~/tok"))  # `~` expands against the real HOME, not op-home
    assert {name: env[name] for name in KEYS} == KEYS and calls.exists()


def test_a_missing_directory_is_created_with_mode_0700_and_an_existing_good_one_is_reused(tmp_path, monkeypatch):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    op, _, _, _ = recording_op(tmp_path)
    target = op_home_of(home)
    assert not target.exists()
    tick.load_keys({"HOME": str(home), "PATH": os.environ["PATH"]}, creds(tmp_path, op))
    info = target.lstat()
    assert target.is_dir() and not target.is_symlink() and info.st_uid == os.getuid() and (info.st_mode & 0o777) == 0o700
    (target / "kept").write_text("x", encoding="utf-8")
    tick.load_keys({"HOME": str(home), "PATH": os.environ["PATH"]}, creds(tmp_path, op))
    assert (target / "kept").read_text() == "x"  # reused, not recreated or cleaned


def test_without_a_home_in_the_environment_the_real_home_is_used_to_place_it(tmp_path, monkeypatch):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    op, _, seen_home, _ = recording_op(tmp_path)
    tick.load_keys({"PATH": os.environ["PATH"]}, creds(tmp_path, op))
    assert set(seen_home.read_text().split()) == {str(op_home_of(home))}


def _make_bad(case: str, home: Path, monkeypatch) -> None:
    target = op_home_of(home)
    target.parent.mkdir(parents=True, exist_ok=True)
    if case.startswith("mode_"):
        target.mkdir()
        target.chmod(int(case[-4:], 8))
    elif case == "symlink":
        real = home / "elsewhere"
        real.mkdir(mode=0o700)
        target.symlink_to(real)
    elif case == "file":
        target.write_text("x", encoding="utf-8")
        target.chmod(0o700)
    elif case == "foreign_owner":
        target.mkdir(mode=0o700)
        monkeypatch.setattr(tick.os, "getuid", lambda: target.lstat().st_uid + 1)
    elif case == "parent_is_a_file":
        target.parent.rmdir()
        target.parent.write_text("x", encoding="utf-8")


BAD = ["mode_0755", "mode_0750", "mode_0770", "mode_0500", "mode_0777", "symlink", "file", "foreign_owner", "parent_is_a_file"]


@pytest.mark.parametrize("case", BAD)
def test_a_bad_directory_fails_once_without_calling_op_or_using_the_real_home(tmp_path, monkeypatch, case):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    _make_bad(case, home, monkeypatch)
    op, calls, seen_home, _ = recording_op(tmp_path)
    env = {"HOME": str(home), "PATH": os.environ["PATH"]}
    with pytest.raises(tick.TickError) as raised:
        tick.load_keys(env, creds(tmp_path, op))
    error = raised.value
    assert (error.exit_code, error.code) == (tick.EXIT_KEYS, "OP_HOME_INVALID") and error.kind in KINDS
    assert not calls.exists() and not seen_home.exists()  # op never ran: no fallback to the real HOME
    assert not any(name in env for name in KEYS)
    assert no_key_text(str(error) + repr(error) + error.kind) and error.__cause__ is None and error.__suppress_context__


def test_a_relative_home_is_refused(tmp_path):
    op, calls, _, _ = recording_op(tmp_path)
    with pytest.raises(tick.TickError) as raised:
        tick.load_keys({"HOME": "relative/home", "PATH": os.environ["PATH"]}, creds(tmp_path, op))
    assert (raised.value.code, raised.value.kind) == ("OP_HOME_INVALID", "setting") and not calls.exists()


def test_the_directory_is_not_touched_when_op_is_not_used(tmp_path, monkeypatch):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    tick.load_keys({"HOME": str(home), **KEYS}, None)  # every key already in the environment
    store = tmp_path / "store-keys"
    store.write_text(json.dumps(KEYS), encoding="utf-8")
    store.chmod(0o600)
    credentials_path = tmp_path / "c.json"
    credentials_path.write_text(json.dumps({"store_keys_file": str(store)}), encoding="utf-8")
    tick.load_keys({"HOME": str(home)}, credentials_path)  # key-file source (R-F)
    assert not (home / ".config").exists()


def test_full_tick_with_a_bad_directory_ends_with_the_one_code_and_leaks_nothing(tmp_path, capsys, monkeypatch):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    _make_bad("mode_0755", home, monkeypatch)
    item, hooks = synthetic_service(tmp_path)
    op, calls, _, _ = recording_op(tmp_path)
    env = {"HOME": str(home), "PATH": os.environ["PATH"]}
    code = run_tick(tmp_path, item, hooks, credentials_path=creds(tmp_path, op), env=env)
    written = everything_written(tmp_path, capsys)
    assert code == tick.EXIT_KEYS and not calls.exists()
    line = json.loads(written.strip().splitlines()[0])
    assert (line["status"], line["exit"], line["code"]) == ("key_error", 30, "OP_HOME_INVALID") and line["type"] in KINDS
    assert no_key_text(written) and TOKEN not in written


def test_full_tick_with_a_good_directory_runs_normally(tmp_path, capsys, monkeypatch):
    home = home_of(tmp_path)
    monkeypatch.setenv("HOME", str(home))
    item, hooks = synthetic_service(tmp_path)
    op, calls, seen_home, _ = recording_op(tmp_path)
    env = {"HOME": str(home), "PATH": os.environ["PATH"]}
    code = run_tick(tmp_path, item, hooks, credentials_path=creds(tmp_path, op), env=env)
    written = everything_written(tmp_path, capsys)
    assert code == tick.EXIT_OK and set(seen_home.read_text().split()) == {str(op_home_of(home))}
    line = json.loads(written.strip().splitlines()[-1])
    assert line["status"] == "ok" and len(line["probe"]["keys"]) == 3
    assert no_key_text(written) and TOKEN not in written
