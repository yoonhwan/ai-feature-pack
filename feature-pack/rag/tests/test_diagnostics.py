from __future__ import annotations

import json
import struct
from dataclasses import asdict
from unittest.mock import patch

import pytest

from airag import api, embeddings
from airag.db import connect


@pytest.fixture
def diagnostic_db(tmp_path, key_bytes):
    path = tmp_path / "diagnostics.db"
    con = connect.init_db(path, key_bytes)
    cfg = embeddings.EmbeddingSpaceConfig(
        "openai-compatible", "http://localhost:9999/private?token=ENDPOINT_SECRET", "fixture", "revision-1", 4,
        tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3",
    )
    profile = api.register_profile(con, {"embedding": asdict(cfg)})["data"]["profile_key"]
    with patch("airag.embeddings.embed_documents", side_effect=lambda cfg, texts, **kw: [struct.pack("4f", 1, 0, 0, 0) for _ in texts]):
        added = api.add(con, "add", "docs", "source", b"SOURCE_SECRET original input", profile_key=profile)
    assert added["ok"], added
    yield con, path, key_bytes, profile, added
    con.close()


def _codes(result):
    return {issue["code"] for issue in result["data"]["issues"]}


def test_valid_database_read_only_diagnostics_do_not_call_provider(diagnostic_db):
    con, path, key, profile, added = diagnostic_db
    readonly = connect.open_readonly(path, key)
    statements = []
    readonly.set_trace_callback(statements.append)
    try:
        with patch("airag.embeddings.embed_documents", side_effect=AssertionError("network forbidden")):
            result = api.verify(readonly, request_id="verify")
        assert result["ok"], result
        assert result["request_id"] == "verify"
        assert result["data"]["profiles"][0]["valid"]
        assert result["data"]["provider_connectivity"] == "not_checked"
        assert readonly.total_changes == 0
        assert readonly.execute("PRAGMA query_only").fetchone() == (1,)
        assert not readonly.in_transaction
        assert not any(s.upper().startswith(("INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER")) for s in statements)
        serialized = json.dumps(result)
        assert "SOURCE_SECRET" not in serialized and "ENDPOINT_SECRET" not in serialized
    finally:
        readonly.close()


def test_stale_ready_after_pending_update_is_valid_and_exposes_job(diagnostic_db):
    con, path, key, profile, added = diagnostic_db
    updated = api.update(con, "update", "docs", "source", added["data"]["revision_token"], b"new text")
    assert updated["ok"]
    result = api.operational_status(con)
    assert result["data"]["healthy"], result
    assert result["data"]["jobs"]["pending"] == 1
    assert result["data"]["jobs"]["items"][0]["status"] == "pending"


def test_failed_job_exposes_presence_without_provider_error(diagnostic_db):
    con, path, key, profile, added = diagnostic_db
    con.execute("UPDATE jobs SET status='failed',error='PROVIDER_SECRET raw source body'")
    result = api.operational_status(con)
    assert result["data"]["jobs"]["failed"] == 1
    assert result["data"]["jobs"]["items"][0]["error_present"]
    assert "PROVIDER_SECRET" not in json.dumps(result)


def test_fts_missing_and_duplicate_rows_are_diagnosed_without_repair(diagnostic_db):
    con, path, key, profile, added = diagnostic_db
    con.execute("DELETE FROM fts_chunks")
    result = api.verify(con)
    assert not result["ok"] and "FTS_MISSING_ROWS" in _codes(result)
    assert con.execute("SELECT COUNT(*) FROM fts_chunks").fetchone() == (0,)
    con.execute("INSERT INTO fts_chunks(text,chunk_id,source_id,collection_id) VALUES('PRIVATE_SOURCE',999,999,999)")
    result = api.verify(con)
    assert "FTS_UNEXPECTED_ROWS" in _codes(result)
    assert "PRIVATE_SOURCE" not in json.dumps(result)


def test_vector_deactivation_is_diagnosed_without_repair(diagnostic_db):
    con, path, key, profile, added = diagnostic_db
    con.execute("UPDATE vec_space_1 SET active=0")
    result = api.verify(con)
    assert not result["ok"] and "VEC_MISSING_ROWS" in _codes(result)
    assert con.execute("SELECT active FROM vec_space_1").fetchone() == (0,)


def test_profile_corruption_is_redacted(diagnostic_db):
    con, path, key, profile, added = diagnostic_db
    con.execute("UPDATE processing_profiles SET chunker_config='PRIVATE_CONFIG'")
    result = api.verify(con)
    assert "PROFILE_CONFIGURATION_INVALID" in _codes(result)
    assert "PRIVATE_CONFIG" not in json.dumps(result)


def test_caller_transaction_is_not_committed_or_rolled_back(diagnostic_db):
    con, path, key, profile, added = diagnostic_db
    con.execute("BEGIN")
    con.execute("UPDATE jobs SET error='uncommitted'")
    result = api.verify(con)
    assert result["ok"], result
    assert con.in_transaction
    assert con.execute("SELECT error FROM jobs").fetchone() == ("uncommitted",)
    con.rollback()
    assert con.execute("SELECT error FROM jobs").fetchone() == (None,)


def test_unused_profile_needs_no_vector_table(tmp_path, key_bytes):
    con = connect.init_db(tmp_path / "empty.db", key_bytes)
    try:
        cfg = embeddings.EmbeddingSpaceConfig("openai-compatible", "http://localhost:1/v1", "fixture", "rev", 4,
                                               tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3")
        assert api.register_profile(con, {"embedding": asdict(cfg)})["ok"]
        assert api.verify(con)["ok"]
        assert con.execute("SELECT name FROM sqlite_master WHERE name='vec_space_1'").fetchone() is None
    finally:
        con.close()
