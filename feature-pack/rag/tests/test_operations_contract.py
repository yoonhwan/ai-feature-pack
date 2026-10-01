"""Independent read-only operational diagnostics with actual SQLCipher/vec0."""
from __future__ import annotations

import hashlib
import json
import os
import struct
import subprocess
import sys
from pathlib import Path

import pytest

from airag import api, embeddings, profiles, store
from airag.db import connect


@pytest.fixture
def operational_db(tmp_path, key_bytes):
    path = tmp_path / "operations.db"
    con = connect.init_db(path, key_bytes)
    cfg = embeddings.EmbeddingSpaceConfig(
        "openai-compatible", "http://localhost:1/v1", "fixture", "fixture-v1", 4,
        tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3",
    )
    con.execute("BEGIN IMMEDIATE")
    space, profile = profiles.register_space_and_profile(con, cfg, {"adapter": "plain_text"})
    con.commit()
    embeddings.ensure_vec_space_table(con, space, 4)
    receipt = store.add(con, store.AddRequest("original", "docs", "private-source", b"PRIVATE_ORIGINAL_9382"), profile_key=profile)
    ready = store.publish_generation_with_content(
        con, receipt["generation_id"], standard_md="PRIVATE_ORIGINAL_9382", structured_json={},
        chunk_rows=[{"text": "PRIVATE_ORIGINAL_9382", "token_count": 4, "anchor": {"headings": [], "items": []}}],
        space_id=space, vectors=[struct.pack("4f", 1, 0, 0, 0)],
    )
    yield con, path, key_bytes, space, profile, ready
    con.close()


def _issues(result):
    return {x["code"] for x in result["data"]["issues"]}


def test_clean_diagnostics_do_not_modify_database_or_expose_original(operational_db):
    con, path, key, _, _, _ = operational_db
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    reader = connect.open_readonly(path, key)
    try:
        result = api.verify(reader)
        assert result["ok"], result
        assert result["data"]["read_only"] and result["data"]["healthy"]
        assert result["data"]["provider_connectivity"] == "not_checked"
        assert "PRIVATE_ORIGINAL_9382" not in json.dumps(result)
        with pytest.raises(Exception):
            reader.execute("UPDATE sources SET state_version = state_version + 1")
    finally:
        reader.close()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == before


@pytest.mark.parametrize("corruption,code", [
    ("fts", "FTS_MISSING_ROWS"), ("fts_text", "FTS_UNEXPECTED_ROWS"),
    ("vector", "VEC_MISSING_ROWS"), ("pointer", "READY_POINTER_MISMATCH"),
    ("profile", "PROFILE_CONFIGURATION_INVALID"),
])
def test_verifier_reports_corruption_without_repair(operational_db, corruption, code):
    con, _, _, space, profile, ready = operational_db
    if corruption == "fts":
        con.execute("DELETE FROM fts_chunks")
    elif corruption == "fts_text":
        con.execute("UPDATE fts_chunks SET text = 'WRONG_TEXT_SECRET_472'")
    elif corruption == "vector":
        con.execute(f"UPDATE {embeddings.vec_space_table_name(space)} SET active = 0")
    elif corruption == "pointer":
        con.execute("UPDATE generations SET status='failed' WHERE generation_id=?", (ready["generation_id"],))
    else:
        con.execute("UPDATE processing_profiles SET chunker_config=? WHERE profile_key=?",
                    ('{"provider_endpoint":"http://SECRET:PASS@localhost/?token=SECRET"}', profile))
    con.commit()
    changes = con.total_changes
    result = api.verify(con)
    assert not result["ok"] and result["error"]["code"] == "DIAGNOSTICS_FAILED", result
    assert code in _issues(result), result
    assert con.total_changes == changes
    serialized = json.dumps(result)
    assert "PRIVATE_ORIGINAL_9382" not in serialized
    assert "WRONG_TEXT_SECRET_472" not in serialized
    assert "SECRET:PASS" not in serialized


def test_pending_and_failed_update_leave_previous_ready_diagnostics_healthy(operational_db):
    con, _, _, _, profile, ready = operational_db
    updated = store.update(con, store.UpdateRequest("pending-update", "docs", "private-source",
                                                  ready["revision_token"], b"PRIVATE_NEWER_882"), profile_key=profile)
    store.fail_generation(con, updated["generation_id"], "API_TOKEN_PRIVATE_FAILURE_947")
    result = api.operational_status(con)
    assert result["ok"] and result["data"]["healthy"], result
    assert result["data"]["jobs"]["failed"] == 1
    assert result["data"]["jobs"]["items"][0]["error_present"]
    assert "API_TOKEN_PRIVATE_FAILURE_947" not in json.dumps(result)
    assert "PRIVATE_NEWER_882" not in json.dumps(result)


def test_diagnostics_preserve_the_callers_transaction(operational_db):
    con, _, _, _, _, _ = operational_db
    con.execute("BEGIN")
    try:
        assert api.verify(con)["ok"]
        assert con.in_transaction
    finally:
        con.rollback()


def test_deleted_source_has_no_active_index_but_is_consistent(operational_db):
    con, _, _, _, _, ready = operational_db
    store.delete(con, store.DeleteRequest("delete", "docs", "private-source", ready["revision_token"]))
    assert api.verify(con)["ok"]


def test_cli_verify_and_status_are_read_only_and_redacted(operational_db, tmp_path):
    con, path, key, _, _, _ = operational_db
    cli = str(Path(sys.executable).with_name("ai-rag"))
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    for command in ("verify", "doctor", "status"):
        read_fd, write_fd = os.pipe()
        os.write(write_fd, key)
        os.close(write_fd)
        try:
            p = subprocess.run([cli, "manage", command, "--db", str(path), "--key-fd", str(read_fd)],
                               pass_fds=(read_fd,), cwd=tmp_path, capture_output=True, text=True, timeout=30)
        finally:
            os.close(read_fd)
        response = json.loads(p.stdout)
        assert p.returncode == 0 and response["ok"], response
        assert "PRIVATE_ORIGINAL_9382" not in p.stdout + p.stderr
        assert key.hex() not in p.stdout + p.stderr
    assert hashlib.sha256(path.read_bytes()).hexdigest() == before
