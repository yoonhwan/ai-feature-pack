"""Public ingestion/replay/claim tests with real SQLCipher and mocked vectors."""
from __future__ import annotations

import struct
from dataclasses import asdict
from unittest.mock import patch

import pytest

from airag import api, embeddings, store
from airag.db import connect

TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


def config():
    return embeddings.EmbeddingSpaceConfig(
        "openai-compatible", "http://localhost:9999/v1", "fixture-embed", "fixture-revision", 4,
        tokenizer_revision=TOKENIZER_REVISION,
    )


@pytest.fixture
def db(tmp_path, key_bytes):
    path = tmp_path / "processing.db"
    con = connect.init_db(path, key_bytes)
    result = api.register_profile(con, {"embedding": asdict(config())})
    assert result["ok"], result
    yield con, result["data"]["profile_key"], path, key_bytes
    con.close()


def vectors(_cfg, texts, **kwargs):
    return [struct.pack("4f", 1, 0, 0, 0) for _ in texts]


def test_completed_request_replays_after_reopen_and_later_update(db):
    con, profile, path, key = db
    with patch("airag.embeddings.embed_documents", side_effect=vectors) as embed:
        added = api.add(con, "request-a", "docs", "source", b"first version", profile_key=profile)
        assert added["ok"], added
        assert added["data"]["searchable"] is True
        status = api.status(con, "docs", "source")
        assert added["data"]["revision_token"] == status["data"]["revision_token"]
        changed = api.update(con, "request-b", "docs", "source", added["data"]["revision_token"], b"second version", profile_key=profile)
        assert changed["ok"], changed
        reopened = connect.open_encrypted(path, key)
        try:
            replayed = api.add(reopened, "request-a", "docs", "source", b"first version", profile_key=profile)
        finally:
            reopened.close()
        assert replayed == added
        assert embed.call_count == 2
    generation = added["data"]["generation_id"]
    historical = api.fetch_artifact(con, "docs", "source", generation_id=generation)
    assert historical["ok"] and "first version" in historical["data"]["standard_md"]
    assert not api.fetch_artifact(con, "other", "source", generation_id=generation)["ok"]


def test_same_request_during_model_call_has_only_one_claim(db):
    con, profile, _, _ = db
    def embed(cfg, texts, **kwargs):
        concurrent = api.add(con, "same-request", "docs", "source", b"input", profile_key=profile)
        assert concurrent["error"]["code"] == "IN_PROGRESS"
        assert not con.in_transaction
        return vectors(cfg, texts)
    with patch("airag.embeddings.embed_documents", side_effect=embed) as provider:
        result = api.add(con, "same-request", "docs", "source", b"input", profile_key=profile)
    assert result["ok"], result
    provider.assert_called_once()
    assert con.execute("SELECT COUNT(*) FROM generations").fetchone() == (1,)


def test_retry_recovers_expired_claim_with_captured_profile(db):
    con, profile, _, _ = db
    req = store.AddRequest("crashed", "docs", "source", b"durable input", explicit_profile_key=profile)
    original = store.add(con, req, profile_key=profile, lease_owner="old-process")
    con.execute("UPDATE jobs SET lease_expires_at_ms = 0 WHERE job_id = ?", (original["job_id"],))
    con.commit()
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        result = api.add(con, "crashed", "docs", "source", b"durable input", profile_key=profile)
    assert result["ok"], result
    assert result["data"]["generation_id"] != original["generation_id"]
    assert con.execute("SELECT status FROM generations WHERE generation_id = ?", (original["generation_id"],)).fetchone() == ("failed",)
    assert con.execute("SELECT COUNT(*) FROM source_revisions").fetchone() == (1,)


def test_model_failure_is_structured_and_previous_ready_survives(db):
    con, profile, _, _ = db
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        old = api.add(con, "first", "docs", "source", b"good input", profile_key=profile)
    with patch("airag.embeddings.embed_documents", side_effect=embeddings.EmbeddingError("PROVIDER_UNREACHABLE", "unreachable", retryable=True)):
        failed = api.update(con, "second", "docs", "source", old["data"]["revision_token"], b"new input", profile_key=profile)
    assert failed["error"]["code"] == "PROVIDER_UNREACHABLE"
    assert api.status(con, "docs", "source")["data"]["ready_generation_id"] == old["data"]["generation_id"]
    with patch("airag.embeddings.embed_documents") as embed:
        replay = api.update(con, "second", "docs", "source", old["data"]["revision_token"], b"new input", profile_key=profile)
    assert replay == failed
    embed.assert_not_called()


def test_profiled_batch_processes_each_item(db):
    con, profile, _, _ = db
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        result = api.add_batch(con, [{"request_id": "batch-a", "collection": "docs", "source_key": "a", "text": "body", "profile_key": profile}])
    assert result["data"]["items"][0]["data"]["searchable"] is True


def test_search_snapshot_survives_concurrent_publication_before_manifest_write(db):
    from airag import search as retrieval

    con, profile, path, key = db
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        old = api.add(con, "old-snapshot", "docs", "source", b"original snapshot", profile_key=profile)
    writer = connect.open_encrypted(path, key)
    original_bm25 = retrieval._bm25_candidates
    changed = []

    def lexical_then_publish(*args, **kwargs):
        candidates = original_bm25(*args, **kwargs)
        assert con.in_transaction
        with patch("airag.embeddings.embed_documents", side_effect=vectors):
            result = api.update(writer, "new-snapshot", "docs", "source", old["data"]["revision_token"], b"replacement snapshot", profile_key=profile)
        assert result["ok"], result
        changed.append(result)
        return candidates

    try:
        with patch.object(retrieval, "_bm25_candidates", side_effect=lexical_then_publish), \
             patch("airag.embeddings.embed_query", return_value=struct.pack("4f", 1, 0, 0, 0)):
            result = api.search(con, "docs", "snapshot", profile)
    finally:
        writer.close()
    assert result["ok"], result
    assert changed[0]["data"]["generation_id"] != old["data"]["generation_id"]
    evidence = result["data"]["results"][0]
    assert evidence["generation_id"] == old["data"]["generation_id"]
    assert evidence["embedded_text"] == "original snapshot"
    assert result["data"]["eligible"]["sources"] == [{
        "source_id": old["data"]["source_id"], "revision_id": old["data"]["revision_id"],
        "generation_id": old["data"]["generation_id"],
    }]
    assert api.fetch_manifest(con, result["data"]["manifest_id"])["data"]["results"] == result["data"]["results"]
    assert not con.in_transaction


def test_search_operational_error_uses_shared_envelope(db):
    con, profile, _, _ = db
    with patch("airag.embeddings.embed_query", return_value=struct.pack("4f", 1, 0, 0, 0)):
        result = api.search(con, "missing-collection", "query", profile)
    assert result["ok"] is False
    assert result["error"]["code"] == "NOT_FOUND"
    assert not con.in_transaction
    invalid = api.fetch_manifest(con, True)
    assert invalid["error"]["code"] == "VALIDATION_ERROR"
