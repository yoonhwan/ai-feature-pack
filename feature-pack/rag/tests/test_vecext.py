from __future__ import annotations

import sqlite3

import pytest

from airag.db import vecext


def test_try_load_vec0_real_extension() -> None:
    con = sqlite3.connect(":memory:")
    try:
        assert vecext.try_load_vec0(con) is True
        row = con.execute("SELECT vec_version()").fetchone()
        assert row is not None and row[0]
    finally:
        con.close()


def test_extension_loading_disabled_after_success() -> None:
    con = sqlite3.connect(":memory:")
    try:
        assert vecext.try_load_vec0(con) is True
        # enable_load_extension(False) was called in the `finally` clause —
        # a second, un-enabled load_extension() call must fail closed.
        with pytest.raises(sqlite3.OperationalError):
            con.load_extension("sqlite_vec")
    finally:
        con.close()


def test_extension_loading_disabled_even_on_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Exercises the real try_load_vec0() on a genuine failure path, not a
    hand-rolled reimplementation of its enable/disable logic."""
    import sqlite_vec

    def _raise(_con: sqlite3.Connection) -> None:
        raise RuntimeError("synthetic load failure")

    monkeypatch.setattr(sqlite_vec, "load", _raise)

    con = sqlite3.connect(":memory:")
    try:
        assert vecext.try_load_vec0(con) is False
        # enable_load_extension(False) ran in try_load_vec0's `finally`
        # clause even though sqlite_vec.load() raised — the same live
        # connection must still fail closed on a subsequent, un-enabled
        # load_extension() call.
        with pytest.raises(sqlite3.OperationalError):
            con.load_extension("sqlite_vec")
    finally:
        con.close()


def test_vec_version_returns_string() -> None:
    con = sqlite3.connect(":memory:")
    try:
        version = vecext.vec_version(con)
        assert isinstance(version, str) and version.startswith("v")
    finally:
        con.close()


def test_loaded_extension_is_reused_with_active_statements(monkeypatch: pytest.MonkeyPatch) -> None:
    import sqlite_vec

    con = sqlite3.connect(":memory:")
    try:
        assert vecext.try_load_vec0(con)
        cursor = con.execute("SELECT 1 UNION ALL SELECT 2")
        assert cursor.fetchone() == (1,)
        def unexpected_reload(_con):
            pytest.fail("an existing vec0 registration must not be reloaded")
        monkeypatch.setattr(sqlite_vec, "load", unexpected_reload)
        assert vecext.try_load_vec0(con)
        assert cursor.fetchone() == (2,)
        cursor.close()
        with pytest.raises(sqlite3.OperationalError):
            con.load_extension("sqlite_vec")
    finally:
        con.close()
