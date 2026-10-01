from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest
import sqlcipher3

from airag.db import connect, schema


def test_fresh_database_has_v3_tables_empty(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con) == schema.CURRENT_SCHEMA_VERSION
        for table in (
            "embedding_spaces",
            "processing_profiles",
            "normalized_documents",
            "chunks",
        ):
            assert con.execute(f"SELECT COUNT(*) FROM {table}").fetchone() == (0,)
        assert con.execute("SELECT COUNT(*) FROM fts_chunks").fetchone() == (0,)
    finally:
        con.close()


def _create_legacy_v2_db(path: Path, key_bytes: bytes) -> None:
    """A DB exactly as P-02 code would have left it: v1+v2 tables, no v3."""
    con = sqlcipher3.connect(str(path))
    con.isolation_level = None
    _ = con.execute(f"PRAGMA key = \"x'{key_bytes.hex()}'\"")
    _ = con.execute("PRAGMA journal_mode = WAL")
    _ = con.execute("BEGIN")
    schema.create_base_tables(con)
    schema.create_v2_tables(con)
    _ = con.execute("INSERT INTO schema_migrations(version, applied_at_ms) VALUES (2, 0)")
    _ = con.execute("INSERT INTO db_meta(key, value) VALUES ('engine', 'airag')")
    _ = con.execute(
        "INSERT INTO collections(collection_id, name) VALUES (1, 'docs')"
    )
    con.commit()
    con.close()


def test_open_migrates_v2_to_v3_and_preserves_v2_data(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "legacy_v2.db"
    _create_legacy_v2_db(db_path, key_bytes)

    con = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con) == schema.CURRENT_SCHEMA_VERSION
        row = con.execute("SELECT name FROM collections WHERE collection_id = 1").fetchone()
        assert row == ("docs",)
        assert con.execute("SELECT COUNT(*) FROM chunks").fetchone() == (0,)
        assert con.execute("SELECT COUNT(*) FROM fts_chunks").fetchone() == (0,)
    finally:
        con.close()


def test_v1_to_v3_migration_in_one_open(tmp_path: Path, key_bytes: bytes) -> None:
    """A DB stuck at v1 must reach v3 (both v2 and v3 DDL) in a single open,
    not require two separate reopens."""
    db_path = tmp_path / "legacy_v1.db"
    con = sqlcipher3.connect(str(db_path))
    con.isolation_level = None
    _ = con.execute(f"PRAGMA key = \"x'{key_bytes.hex()}'\"")
    _ = con.execute("PRAGMA journal_mode = WAL")
    _ = con.execute("BEGIN")
    schema.create_base_tables(con)
    _ = con.execute("INSERT INTO schema_migrations(version, applied_at_ms) VALUES (1, 0)")
    _ = con.execute("INSERT INTO db_meta(key, value) VALUES ('engine', 'airag')")
    con.commit()
    con.close()

    con2 = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con2) == schema.CURRENT_SCHEMA_VERSION
        assert con2.execute("SELECT COUNT(*) FROM collections").fetchone() == (0,)
        assert con2.execute("SELECT COUNT(*) FROM chunks").fetchone() == (0,)
    finally:
        con2.close()


def _create_legacy_v3_db(path: Path, key_bytes: bytes) -> None:
    """A DB exactly as P-03(-A) code would have left it: v1+v2+v3 tables,
    no v4 — used to verify the v4 migration adds jobs.profile_key/
    final_response_json and search_manifests without touching existing
    rows."""
    con = sqlcipher3.connect(str(path))
    con.isolation_level = None
    _ = con.execute(f"PRAGMA key = \"x'{key_bytes.hex()}'\"")
    _ = con.execute("PRAGMA journal_mode = WAL")
    _ = con.execute("BEGIN")
    schema.create_base_tables(con)
    schema.create_v2_tables(con)
    schema.create_v3_tables(con)
    _ = con.execute("INSERT INTO schema_migrations(version, applied_at_ms) VALUES (3, 0)")
    _ = con.execute("INSERT INTO db_meta(key, value) VALUES ('engine', 'airag')")
    _ = con.execute("INSERT INTO collections(collection_id, name) VALUES (1, 'docs')")
    _ = con.execute(
        "INSERT INTO sources(source_id, collection_id, source_key, media_type, created_at_ms) "
        "VALUES (1, 1, 'a.md', 'text/markdown', 0)"
    )
    _ = con.execute(
        "INSERT INTO jobs(job_id, source_id, kind, status, created_at_ms, updated_at_ms) "
        "VALUES (1, 1, 'add', 'pending', 0, 0)"
    )
    con.commit()
    con.close()


def test_open_migrates_v3_to_v4_and_preserves_v3_data(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "legacy_v3.db"
    _create_legacy_v3_db(db_path, key_bytes)

    con = connect.open_encrypted(db_path, key_bytes)
    try:
        assert connect.read_schema_version(con) == schema.CURRENT_SCHEMA_VERSION
        row = con.execute(
            "SELECT source_id, status, profile_key, final_response_json FROM jobs WHERE job_id = 1"
        ).fetchone()
        assert row == (1, "pending", None, None)
        assert con.execute("SELECT COUNT(*) FROM search_manifests").fetchone() == (0,)
        row = con.execute("SELECT name FROM collections WHERE collection_id = 1").fetchone()
        assert row == ("docs",)
    finally:
        con.close()


def test_chunks_unique_generation_and_index_enforced(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        _ = con.execute(
            "INSERT INTO collections(collection_id, name) VALUES (1, 'docs')"
        )
        _ = con.execute(
            "INSERT INTO sources(source_id, collection_id, source_key, media_type, created_at_ms) "
            "VALUES (1, 1, 'a.md', 'text/markdown', 0)"
        )
        _ = con.execute(
            "INSERT INTO source_revisions(revision_id, source_id, content_hash, byte_length, "
            "content_bytes, media_type, created_at_ms) VALUES (1, 1, 'h', 1, X'41', 'text/markdown', 0)"
        )
        _ = con.execute(
            "INSERT INTO generations(generation_id, revision_id, profile_key, status, "
            "expected_state_version, created_at_ms) VALUES (1, 1, 'p1', 'staged', 1, 0)"
        )
        _ = con.execute(
            "INSERT INTO chunks(chunk_id, generation_id, chunk_index, text, token_count, created_at_ms) "
            "VALUES (1, 1, 0, 'first chunk', 3, 0)"
        )
        con.commit()

        with pytest.raises((sqlite3.IntegrityError, sqlcipher3.IntegrityError)):
            _ = con.execute(
                "INSERT INTO chunks(chunk_id, generation_id, chunk_index, text, token_count, created_at_ms) "
                "VALUES (2, 1, 0, 'duplicate index', 3, 0)"
            )
    finally:
        con.close()


def test_fts_chunks_insert_and_search_scoped_by_collection(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """fts_chunks rows carry collection_id/source_id as UNINDEXED metadata —
    they can scope a query without those columns contributing to BM25 term
    statistics (only `text` is an indexed column)."""
    db_path = tmp_path / "test.db"
    con = connect.init_db(db_path, key_bytes)
    try:
        _ = con.execute(
            "INSERT INTO fts_chunks(rowid, text, chunk_id, source_id, collection_id) "
            "VALUES (1, 'the quick brown fox', 1, 10, 1)"
        )
        _ = con.execute(
            "INSERT INTO fts_chunks(rowid, text, chunk_id, source_id, collection_id) "
            "VALUES (2, 'a lazy sleeping fox', 2, 20, 2)"
        )
        con.commit()

        rows = con.execute(
            "SELECT chunk_id FROM fts_chunks WHERE fts_chunks MATCH 'fox' AND collection_id = 1"
        ).fetchall()
        assert rows == [(1,)]
    finally:
        con.close()
