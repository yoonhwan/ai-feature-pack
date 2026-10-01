from __future__ import annotations

import struct
from pathlib import Path

from airag.db import connect, vecext


def _pack_vec(values: list[float]) -> bytes:
    return struct.pack(f"{len(values)}f", *values)


def test_fts5_insert_and_search_in_encrypted_connection(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        _ = con.execute("CREATE VIRTUAL TABLE docs USING fts5(body)")
        _ = con.execute("INSERT INTO docs(rowid, body) VALUES (1, 'the quick brown fox')")
        _ = con.execute("INSERT INTO docs(rowid, body) VALUES (2, 'a lazy sleeping dog')")
        con.commit()

        rows = con.execute(
            "SELECT rowid FROM docs WHERE docs MATCH 'fox'"
        ).fetchall()
        assert rows == [(1,)]

        rows = con.execute(
            "SELECT rowid FROM docs WHERE docs MATCH 'dog'"
        ).fetchall()
        assert rows == [(2,)]
    finally:
        con.close()


def test_fts5_persists_across_reopen(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    _ = con.execute("CREATE VIRTUAL TABLE docs USING fts5(body)")
    _ = con.execute("INSERT INTO docs(rowid, body) VALUES (1, 'persisted content')")
    con.commit()
    _ = con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    con.close()

    con2 = connect.open_encrypted(db_path, key_bytes)
    try:
        rows = con2.execute(
            "SELECT rowid FROM docs WHERE docs MATCH 'persisted'"
        ).fetchall()
        assert rows == [(1,)]
    finally:
        con2.close()


def test_fts5_rollback_discards_uncommitted_insert(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        _ = con.execute("CREATE VIRTUAL TABLE docs USING fts5(body)")
        con.commit()

        _ = con.execute("BEGIN")
        _ = con.execute("INSERT INTO docs(rowid, body) VALUES (1, 'transient row')")
        con.rollback()

        rows = con.execute(
            "SELECT rowid FROM docs WHERE docs MATCH 'transient'"
        ).fetchall()
        assert rows == []
    finally:
        con.close()


def test_fts5_and_vec0_rollback_together_in_one_transaction(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        assert vecext.try_load_vec0(con) is True
        _ = con.execute("CREATE VIRTUAL TABLE docs USING fts5(body)")
        _ = con.execute("CREATE VIRTUAL TABLE vitems USING vec0(embedding float[4])")
        con.commit()

        _ = con.execute("BEGIN")
        _ = con.execute("INSERT INTO docs(rowid, body) VALUES (1, 'transient row')")
        _ = con.execute(
            "INSERT INTO vitems(rowid, embedding) VALUES (?, ?)",
            (1, _pack_vec([1.0, 0.0, 0.0, 0.0])),
        )
        con.rollback()

        fts_rows = con.execute(
            "SELECT rowid FROM docs WHERE docs MATCH 'transient'"
        ).fetchall()
        vec_rows = con.execute("SELECT rowid FROM vitems").fetchall()
        assert fts_rows == []
        assert vec_rows == []
    finally:
        con.close()


def test_vec0_insert_and_query_in_encrypted_connection(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        assert vecext.try_load_vec0(con) is True
        _ = con.execute("CREATE VIRTUAL TABLE vitems USING vec0(embedding float[4])")

        _ = con.execute(
            "INSERT INTO vitems(rowid, embedding) VALUES (?, ?)",
            (1, _pack_vec([1.0, 0.0, 0.0, 0.0])),
        )
        _ = con.execute(
            "INSERT INTO vitems(rowid, embedding) VALUES (?, ?)",
            (2, _pack_vec([0.0, 1.0, 0.0, 0.0])),
        )
        con.commit()

        query = _pack_vec([1.0, 0.0, 0.0, 0.0])
        rows = con.execute(
            "SELECT rowid, distance FROM vitems WHERE embedding MATCH ? ORDER BY distance LIMIT 1",
            (query,),
        ).fetchall()
        assert rows[0][0] == 1
        assert rows[0][1] == 0.0
    finally:
        con.close()


def test_vec0_persists_across_reopen(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    assert vecext.try_load_vec0(con) is True
    _ = con.execute("CREATE VIRTUAL TABLE vitems USING vec0(embedding float[4])")
    _ = con.execute(
        "INSERT INTO vitems(rowid, embedding) VALUES (?, ?)",
        (1, _pack_vec([0.0, 0.0, 1.0, 0.0])),
    )
    con.commit()
    _ = con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    con.close()

    con2 = connect.open_encrypted(db_path, key_bytes)
    try:
        assert vecext.try_load_vec0(con2) is True
        query = _pack_vec([0.0, 0.0, 1.0, 0.0])
        rows = con2.execute(
            "SELECT rowid, distance FROM vitems WHERE embedding MATCH ? ORDER BY distance LIMIT 1",
            (query,),
        ).fetchall()
        assert rows[0][0] == 1
        assert rows[0][1] == 0.0
    finally:
        con2.close()
