from __future__ import annotations

import sqlite3
import threading
from pathlib import Path

import pytest
import sqlcipher3

from airag import keys
from airag.db import connect


def test_init_db_creates_encrypted_file(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        assert db_path.exists()
        assert connect.read_schema_version(con) == connect.SCHEMA_VERSION
    finally:
        con.close()


def test_init_db_refuses_existing_nonempty_file(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    con.close()
    with pytest.raises(connect.DatabaseAlreadyExists):
        _ = connect.init_db(db_path, key_bytes)


def test_init_db_refuses_existing_empty_file_too(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """O_CREAT|O_EXCL reservation refuses ANY pre-existing file at the
    path, including a 0-byte placeholder — not just a non-empty one."""
    db_path = tmp_path / "placeholder.db"
    db_path.touch()
    assert db_path.stat().st_size == 0

    with pytest.raises(connect.DatabaseAlreadyExists):
        _ = connect.init_db(db_path, key_bytes)
    assert db_path.stat().st_size == 0


def test_reopen_with_correct_key_succeeds(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    con.close()

    con2 = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con2) == connect.SCHEMA_VERSION
    finally:
        con2.close()


def test_reopen_with_wrong_key_rejected(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    con.close()

    wrong_key = keys.generate_key()
    assert wrong_key != key_bytes
    with pytest.raises(connect.WrongKeyOrForeignDatabase):
        _ = connect.open_encrypted(db_path, wrong_key)


def test_open_rejects_plaintext_sqlite_db_without_modifying_it(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "plain.db"
    plain = sqlite3.connect(str(db_path))
    _ = plain.execute("CREATE TABLE t (x INTEGER)")
    _ = plain.execute("INSERT INTO t VALUES (1)")
    plain.commit()
    plain.close()

    before = db_path.read_bytes()
    with pytest.raises(connect.WrongKeyOrForeignDatabase):
        _ = connect.open_encrypted(db_path, key_bytes)
    after = db_path.read_bytes()
    assert before == after

    # The foreign DB is untouched and still readable as plain sqlite3.
    plain2 = sqlite3.connect(str(db_path))
    assert plain2.execute("SELECT x FROM t").fetchone() == (1,)
    plain2.close()


def test_apply_raw_key_rejects_wrong_length() -> None:
    con = sqlite3.connect(":memory:")
    try:
        with pytest.raises(ValueError, match="must be 32 bytes"):
            connect._apply_raw_key(con, b"short")  # pyright: ignore[reportPrivateUsage]
    finally:
        con.close()


def test_pragmas_applied_on_open(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        assert con.execute("PRAGMA temp_store").fetchone()[0] == 2  # MEMORY
        assert con.execute("PRAGMA foreign_keys").fetchone()[0] == 1
        assert con.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
        assert con.execute("PRAGMA busy_timeout").fetchone()[0] == 5000
    finally:
        con.close()


def test_reopen_roundtrip_with_special_characters_in_path(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """open_encrypted connects via a `mode=rw` URI built from
    Path.resolve().as_uri() — a hand-built f"file:{p}?mode=rw" would let a
    path containing ?, #, or % be misparsed as a URI query/fragment/percent
    escape and open the wrong file (or fail outright)."""
    db_path = tmp_path / "weird name #1 100% done?.db"
    con = connect.init_db(db_path, key_bytes)
    con.close()

    con2 = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con2) == connect.SCHEMA_VERSION
    finally:
        con2.close()


def test_cipher_version_is_real_and_nonempty(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        version = connect.cipher_version(con)
        assert isinstance(version, str) and version
    finally:
        con.close()


def test_open_rejects_foreign_encrypted_db_with_correct_key_without_modifying_it(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """A database encrypted with a key we do have, but never created by
    init_db (no db_meta.engine marker), must still be refused — a valid key
    alone is not proof this is an airag database. It must also be refused
    WITHOUT modifying it: identity/schema verification must happen before
    any mutating pragma (journal_mode=WAL rewrites the file header even
    when no row data changes — confirmed empirically during review)."""
    db_path = tmp_path / "foreign.db"
    con = sqlcipher3.connect(str(db_path))
    _ = con.execute(f"PRAGMA key = \"x'{key_bytes.hex()}'\"")
    _ = con.execute("CREATE TABLE unrelated (x INTEGER)")
    con.commit()
    con.close()

    before = db_path.read_bytes()
    with pytest.raises(connect.WrongKeyOrForeignDatabase):
        _ = connect.open_encrypted(db_path, key_bytes)
    assert db_path.read_bytes() == before
    for suffix in ("-wal", "-shm"):
        assert not Path(str(db_path) + suffix).exists()


def test_open_rejects_future_schema_version(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "future.db"
    con = connect.init_db(db_path, key_bytes)
    _ = con.execute("DELETE FROM schema_migrations")
    _ = con.execute(
        "INSERT INTO schema_migrations(version, applied_at_ms) VALUES (999, 0)"
    )
    con.commit()
    con.close()

    with pytest.raises(connect.UnsupportedSchemaVersion, match="999"):
        _ = connect.open_encrypted(db_path, key_bytes)


def test_open_rejects_stale_schema_version_zero(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """Not just "newer than supported" — any non-matching version (including
    a lower/stale one) must be refused. A ">" check would have let this one
    silently through."""
    db_path = tmp_path / "stale.db"
    con = connect.init_db(db_path, key_bytes)
    _ = con.execute("DELETE FROM schema_migrations")
    _ = con.execute(
        "INSERT INTO schema_migrations(version, applied_at_ms) VALUES (0, 0)"
    )
    con.commit()
    con.close()

    with pytest.raises(connect.UnsupportedSchemaVersion, match="0"):
        _ = connect.open_encrypted(db_path, key_bytes)


def test_open_rejects_missing_schema_migrations_row(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """An airag-tagged DB whose schema_migrations table is empty
    (read_schema_version() returns None) must be refused, not silently
    treated as "no opinion, allow it"."""
    db_path = tmp_path / "empty_schema.db"
    con = connect.init_db(db_path, key_bytes)
    _ = con.execute("DELETE FROM schema_migrations")
    con.commit()
    con.close()

    with pytest.raises(connect.UnsupportedSchemaVersion, match="None"):
        _ = connect.open_encrypted(db_path, key_bytes)


def test_open_encrypted_does_not_create_missing_path(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "missing.db"
    with pytest.raises(connect.WrongKeyOrForeignDatabase, match="does not exist"):
        _ = connect.open_encrypted(db_path, key_bytes)
    assert not db_path.exists()


def test_open_encrypted_rejects_non_bytes_key(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    con.close()

    with pytest.raises(TypeError, match="must be bytes"):
        _ = connect.open_encrypted(db_path, "x" * 32)  # pyright: ignore[reportArgumentType]


def test_wrong_length_key_does_not_leak_connection_or_block_subsequent_open(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    con.close()

    with pytest.raises(ValueError, match="must be 32 bytes"):
        _ = connect.open_encrypted(db_path, b"too-short")

    # If the failed attempt leaked an open connection/lock, this reopen
    # would hang or fail under WAL's locking semantics.
    con2 = connect.open_encrypted(db_path, key_bytes)
    con2.close()


def test_init_db_rejects_wrong_length_key_before_touching_disk(
    tmp_path: Path,
) -> None:
    db_path = tmp_path / "test.db"
    with pytest.raises(ValueError, match="must be 32 bytes"):
        _ = connect.init_db(db_path, b"too-short")
    assert not db_path.exists()


def test_init_db_rejects_non_bytes_key_before_touching_disk(
    tmp_path: Path,
) -> None:
    """A 32-character str passes a length-only check but has no .hex()
    method — _apply_raw_key would raise AttributeError *after* init_db had
    already reserved/created the file via O_EXCL. The type must be
    validated up front, before any file is touched."""
    db_path = tmp_path / "test.db"
    with pytest.raises(TypeError, match="must be bytes"):
        _ = connect.init_db(db_path, "x" * 32)  # pyright: ignore[reportArgumentType]
    assert not db_path.exists()


def test_concurrent_init_same_key_is_exclusive_and_atomic(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "race.db"
    results: list[str] = []
    lock = threading.Lock()

    def _attempt() -> None:
        try:
            con = connect.init_db(db_path, key_bytes)
            con.close()
            with lock:
                results.append("ok")
        except connect.DatabaseAlreadyExists:
            with lock:
                results.append("already_exists")

    threads = [threading.Thread(target=_attempt) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert results.count("ok") == 1
    assert results.count("already_exists") == 3

    con = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con) == connect.SCHEMA_VERSION
    finally:
        con.close()


def test_concurrent_init_different_keys_one_wins_and_stays_intact(
    tmp_path: Path,
) -> None:
    db_path = tmp_path / "race.db"
    key_a = keys.generate_key()
    key_b = keys.generate_key()
    results: list[tuple[str, bytes]] = []
    lock = threading.Lock()

    def _attempt(key: bytes) -> None:
        try:
            con = connect.init_db(db_path, key)
            con.close()
            with lock:
                results.append(("ok", key))
        except connect.DatabaseAlreadyExists:
            with lock:
                results.append(("already_exists", key))

    threads = [
        threading.Thread(target=_attempt, args=(key_a,)),
        threading.Thread(target=_attempt, args=(key_b,)),
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    winners = [key for status, key in results if status == "ok"]
    assert len(winners) == 1
    winning_key = winners[0]
    losing_key = key_b if winning_key == key_a else key_a

    # The winning key opens a fully valid, intact database...
    con = connect.open_encrypted(db_path, winning_key)
    try:
        assert connect.read_schema_version(con) == connect.SCHEMA_VERSION
    finally:
        con.close()

    # ...and the losing key correctly fails against it (no mixed/corrupt state).
    with pytest.raises(connect.WrongKeyOrForeignDatabase):
        _ = connect.open_encrypted(db_path, losing_key)


def test_init_refusal_does_not_delete_preexisting_nonempty_file(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    con.close()
    before = db_path.read_bytes()

    with pytest.raises(connect.DatabaseAlreadyExists):
        _ = connect.init_db(db_path, keys.generate_key())

    assert db_path.read_bytes() == before
