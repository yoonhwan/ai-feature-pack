from __future__ import annotations

import threading
from pathlib import Path

import pytest
import sqlcipher3

from airag.db import connect, schema


def _create_legacy_v1_db(path: Path, key_bytes: bytes) -> None:
    """Builds a database exactly as pre-migration P-01 code would have:
    v1 tables only, WAL already enabled (P-01's init_db always enabled
    WAL), plus one synthetic db_meta row that must survive migration
    untouched."""
    con = sqlcipher3.connect(str(path))
    con.isolation_level = None
    _ = con.execute(f"PRAGMA key = \"x'{key_bytes.hex()}'\"")
    _ = con.execute("PRAGMA journal_mode = WAL")
    _ = con.execute("BEGIN")
    schema.create_base_tables(con)
    _ = con.execute(
        "INSERT INTO schema_migrations(version, applied_at_ms) VALUES (1, 0)"
    )
    _ = con.execute("INSERT INTO db_meta(key, value) VALUES ('engine', 'airag')")
    _ = con.execute(
        "INSERT INTO db_meta(key, value) VALUES ('legacy_marker', 'keepme')"
    )
    con.commit()
    con.close()


def test_open_migrates_v1_to_v2_and_preserves_v1_data(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "legacy.db"
    _create_legacy_v1_db(db_path, key_bytes)

    con = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con) == schema.CURRENT_SCHEMA_VERSION
        marker = con.execute(
            "SELECT value FROM db_meta WHERE key = 'legacy_marker'"
        ).fetchone()
        assert marker == ("keepme",)
        # v2 tables exist and are queryable (empty, but present).
        assert con.execute("SELECT COUNT(*) FROM sources").fetchone() == (0,)
        assert con.execute("SELECT COUNT(*) FROM collections").fetchone() == (0,)
    finally:
        con.close()


def test_migration_reopen_is_idempotent(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "legacy.db"
    _create_legacy_v1_db(db_path, key_bytes)

    con1 = connect.open_encrypted(db_path, key_bytes)
    con1.close()
    # Second reopen: version is already 2, ensure_current_schema takes the
    # no-lock-needed fast path and must not try to CREATE TABLE again.
    con2 = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con2) == schema.CURRENT_SCHEMA_VERSION
    finally:
        con2.close()


def test_migration_failure_leaves_v1_intact(
    tmp_path: Path, key_bytes: bytes, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Injects a failure partway through the v2 DDL (after 'collections' is
    created, before the rest) and confirms the whole migration transaction
    rolled back: version stays 1, the partially-created 'collections' table
    is gone, and the pre-existing v1 marker row is untouched. Then confirms
    a subsequent, unpatched open successfully migrates from that same
    still-v1 state."""
    db_path = tmp_path / "legacy.db"
    _create_legacy_v1_db(db_path, key_bytes)

    real_create_v2_tables = schema.create_v2_tables

    def _partial_then_fail(con: object) -> None:
        _ = con.execute(  # type: ignore[attr-defined]
            "CREATE TABLE collections (collection_id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)"
        )
        raise RuntimeError("synthetic mid-migration failure")

    monkeypatch.setattr(schema, "create_v2_tables", _partial_then_fail)

    with pytest.raises(RuntimeError, match="synthetic mid-migration failure"):
        _ = connect.open_encrypted(db_path, key_bytes)

    monkeypatch.setattr(schema, "create_v2_tables", real_create_v2_tables)

    # Inspect the still-v1 database with a fresh connection, unpatched.
    con = sqlcipher3.connect(str(db_path))
    con.isolation_level = None
    try:
        _ = con.execute(f"PRAGMA key = \"x'{key_bytes.hex()}'\"")
        version = con.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0]
        assert version == 1
        marker = con.execute(
            "SELECT value FROM db_meta WHERE key = 'legacy_marker'"
        ).fetchone()
        assert marker == ("keepme",)
        with pytest.raises(sqlcipher3.OperationalError, match="no such table"):
            _ = con.execute("SELECT * FROM collections")
    finally:
        con.close()

    # A clean (unpatched) open now migrates successfully from that intact
    # v1 state.
    con2 = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con2) == schema.CURRENT_SCHEMA_VERSION
        marker = con2.execute(
            "SELECT value FROM db_meta WHERE key = 'legacy_marker'"
        ).fetchone()
        assert marker == ("keepme",)
    finally:
        con2.close()


def test_concurrent_reopen_of_v1_db_migrates_exactly_once(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """Two connections racing to open the same still-v1 database: BEGIN
    IMMEDIATE serializes them, and the loser must re-read the version under
    its own lock and see the migration already applied (take the no-op
    path) rather than re-running (and failing on) the DDL a second time.
    Both opens must succeed."""
    db_path = tmp_path / "legacy.db"
    _create_legacy_v1_db(db_path, key_bytes)

    results: list[tuple[str, object]] = []
    lock = threading.Lock()

    def _attempt() -> None:
        try:
            con = connect.open_encrypted(db_path, key_bytes)
            version = connect.read_schema_version(con)
            con.close()
            with lock:
                results.append(("ok", version))
        except Exception as exc:  # pragma: no cover - failure path asserted below
            with lock:
                results.append(("error", exc))

    threads = [threading.Thread(target=_attempt) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    errors = [r for r in results if r[0] == "error"]
    assert errors == [], f"unexpected errors: {errors}"
    assert len(results) == 4
    assert all(version == schema.CURRENT_SCHEMA_VERSION for _, version in results)

    con = connect.open_encrypted(db_path, key_bytes)
    try:
        assert con.execute("SELECT COUNT(*) FROM collections").fetchone() == (0,)
        marker = con.execute(
            "SELECT value FROM db_meta WHERE key = 'legacy_marker'"
        ).fetchone()
        assert marker == ("keepme",)
    finally:
        con.close()
