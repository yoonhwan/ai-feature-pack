from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from airag.db import connect

MARKER = "SYNTHETIC-PLAINTEXT-MARKER-p01-8f3c2a91"


def test_marker_absent_from_db_and_wal_bytes(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    _ = con.execute("CREATE TABLE notes (body TEXT)")
    _ = con.execute("INSERT INTO notes(body) VALUES (?)", (MARKER,))
    con.commit()

    wal_path = db_path.with_suffix(db_path.suffix + "-wal")
    if wal_path.exists():
        assert MARKER.encode() not in wal_path.read_bytes()

    _ = con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    con.close()

    marker_bytes = MARKER.encode()
    assert marker_bytes not in db_path.read_bytes()
    if wal_path.exists():
        assert marker_bytes not in wal_path.read_bytes()

    # Sanity: the marker really is retrievable once opened with the right key
    # (i.e. this isn't absent because the insert silently failed).
    con2 = connect.open_encrypted(db_path, key_bytes)
    try:
        row = con2.execute("SELECT body FROM notes").fetchone()
        assert row == (MARKER,)
    finally:
        con2.close()


def test_ordinary_sqlite3_cannot_read_encrypted_db(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    _ = con.execute("CREATE TABLE notes (body TEXT)")
    con.commit()
    _ = con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    con.close()

    plain = sqlite3.connect(str(db_path))
    try:
        with pytest.raises(sqlite3.DatabaseError):
            _ = plain.execute("SELECT name FROM sqlite_master").fetchall()
    finally:
        plain.close()
