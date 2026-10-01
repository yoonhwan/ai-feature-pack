from __future__ import annotations

import json
import os
import sqlite3
import struct
from dataclasses import asdict
from pathlib import Path
from unittest.mock import patch

import pytest

from airag import api, embeddings, llm_enrichment, store
from airag.db import connect
from airag_consumer.lifecycle import AuthenticatedScope
from airag_consumer import reference


TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


def scope() -> AuthenticatedScope:
    return AuthenticatedScope(
        "owner", "tenant", "project", ("tour:synthetic-reference",),
    )


def embedding_config(model: str = "fixture-embed") -> embeddings.EmbeddingSpaceConfig:
    return embeddings.EmbeddingSpaceConfig(
        "openai-compatible", "http://127.0.0.1:9/v1", model,
        model + "-revision", 4, tokenizer_revision=TOKENIZER_REVISION,
    )


def vectors(_config, texts, **_kwargs):
    return [struct.pack("4f", 1, 0, 0, 0) for _ in texts]


def register(con, model: str = "fixture-embed", *, llm=None) -> str:
    value = {"embedding": asdict(embedding_config(model))}
    if llm is not None:
        value["llm"] = asdict(llm)
    response = api.register_profile(con, value)
    assert response["ok"], response
    return response["data"]["profile_key"]


def add_source(con, profile, collection, source_key, text, request_id):
    result = api.add(
        con, request_id, collection, source_key, text.encode(),
        profile_key=profile,
    )
    assert result["ok"], result
    return result


def build_tour(tmp_path: Path):
    path = tmp_path / "tour.db"
    key = os.urandom(32)
    con = connect.init_db(path, key)
    text_profile = register(con, "fixture-text")
    pdf_profile = register(con, "fixture-pdf")
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        add_source(
            con, text_profile, "tour-text", "library-en.txt",
            "library reference marker", "add-library",
        )
        add_source(
            con, text_profile, "tour-text", "refund-policy.md",
            "refund policy marker", "add-refund",
        )
        add_source(
            con, pdf_profile, "tour-pdf", "sample-pdf",
            "pdf reference marker", "add-pdf",
        )
        add_source(
            con, text_profile, "tour-text", "not-approved.txt",
            "foreign unapproved marker", "add-foreign",
        )
        deleted = add_source(
            con, text_profile, "tour-text", "empty.txt",
            "deleted allowed marker", "add-deleted",
        )
    store.delete(
        con, store.DeleteRequest(
            "delete-empty", "tour-text", "empty.txt",
            deleted["data"]["revision_token"],
        ),
    )
    con.close()
    return path, key


def test_encrypted_snapshot_search_groups_allowed_sources_without_original_write(tmp_path):
    source_path, source_key = build_tour(tmp_path)
    before = source_path.read_bytes()
    snapshot = tmp_path / "reference-snapshot.db"
    snapshot_key = os.urandom(32)
    with patch(
        "airag.embeddings.embed_query",
        return_value=struct.pack("4f", 1, 0, 0, 0),
    ):
        result = reference.search_tour_reference(
            source_path, source_key, snapshot, snapshot_key, scope(),
            query="reference marker", top_k=5,
        )
    assert result["label"] == "existing_tour_reference"
    assert result["ranking"]["global_merge"] is False
    assert source_path.read_bytes() == before
    assert result["original"]["sha256_before"] == result["original"]["sha256_after"]
    assert result["snapshot"]["retained"] is True and snapshot.exists()
    assert len(result["allowed_source_pairs"]) == 17

    groups = {(item["collection"], item["space_id"]): item for item in result["groups"]}
    assert {key[0] for key in groups} == {"tour-text", "tour-pdf"}
    returned_sources = {
        source_key for item in result["groups"] for source_key in item["source_keys"]
    }
    assert returned_sources == {"library-en.txt", "refund-policy.md", "sample-pdf"}
    assert "not-approved.txt" not in returned_sources
    assert "empty.txt" not in returned_sources
    assert all(item["transient_manifest"]["snapshot_only"] for item in result["groups"])
    assert all(
        item["score_scope"] == "within_this_collection_and_embedding_space_only"
        for item in result["groups"]
    )

    original = connect.open_readonly(source_path, source_key)
    copied = connect.open_readonly(snapshot, snapshot_key)
    try:
        assert original.execute("SELECT COUNT(*) FROM search_manifests").fetchone() == (0,)
        assert copied.execute("SELECT COUNT(*) FROM search_manifests").fetchone() == (2,)
    finally:
        original.close()
        copied.close()
    plaintext = sqlite3.connect(snapshot)
    try:
        with pytest.raises(sqlite3.DatabaseError):
            plaintext.execute("SELECT * FROM sqlite_master").fetchall()
    finally:
        plaintext.close()


def test_query_time_embedding_and_llm_routes_preserve_captured_identity(tmp_path):
    source_path = tmp_path / "tour-llm.db"
    source_key = os.urandom(32)
    con = connect.init_db(source_path, source_key)
    llm = llm_enrichment.ChatCompletionConfig(
        "openai-compatible", "http://127.0.0.1:8/v1", "fixture-llm",
        "weights-sha", 4096,
    )
    profile = register(con, "fixture-llm-embed", llm=llm)

    def group(_cfg, units):
        return [
            llm_enrichment.SemanticGroup(list(units), "summary", ["tag"])
        ], {}

    def enrich(_cfg, units, *, on_progress=None):
        if on_progress is not None:
            on_progress()
        return [
            llm_enrichment.UnitEnrichment(key, ["tag"], "summary", value)
            for key, value in units.items()
        ], {}

    with patch("airag.llm_enrichment.plan_semantic_groups", side_effect=group), patch(
        "airag.llm_enrichment.enrich_units", side_effect=enrich,
    ), patch("airag.embeddings.embed_documents", side_effect=vectors):
        add_source(
            con, profile, "tour-text", "library-ko.txt",
            "라우팅 기준 문서", "add-routed",
        )
    captured_row = con.execute(
        "SELECT chunker_config FROM processing_profiles WHERE profile_key=?",
        (profile,),
    ).fetchone()
    con.close()
    snapshot = tmp_path / "routed-snapshot.db"
    snapshot_key = os.urandom(32)
    seen = {}

    def query_enrich(config, units):
        seen["llm_endpoint"] = config.endpoint
        return [
            llm_enrichment.UnitEnrichment("query", ["tag"], "summary", "routed query")
        ], {"synthetic_provider": True}

    def query_vector(config, text):
        seen["embedding_endpoint"] = config.endpoint
        seen["query_text"] = text
        return struct.pack("4f", 1, 0, 0, 0)

    with patch("airag.llm_enrichment.enrich_units", side_effect=query_enrich), patch(
        "airag.embeddings.embed_query", side_effect=query_vector,
    ):
        result = reference.search_tour_reference(
            source_path, source_key, snapshot, snapshot_key, scope(),
            query="질문", embedding_endpoint_override="http://127.0.0.1:18712/v1",
            llm_endpoint_override="http://127.0.0.1:18703/v1",
        )
    assert seen == {
        "llm_endpoint": "http://127.0.0.1:18703/v1",
        "embedding_endpoint": "http://127.0.0.1:18712/v1",
        "query_text": "routed query",
    }
    routed = result["groups"][0]["routing"]
    assert routed["embedding"]["overridden"] is True
    assert routed["llm"]["overridden"] is True
    assert result["groups"][0]["profile_key"] == profile
    copied = connect.open_readonly(snapshot, snapshot_key)
    original = connect.open_readonly(source_path, source_key)
    try:
        assert copied.execute(
            "SELECT chunker_config FROM processing_profiles WHERE profile_key=?",
            (profile,),
        ).fetchone() == captured_row
        assert original.execute(
            "SELECT chunker_config FROM processing_profiles WHERE profile_key=?",
            (profile,),
        ).fetchone() == captured_row
    finally:
        copied.close()
        original.close()


def test_original_revision_change_during_query_is_rejected(tmp_path):
    source_path, source_key = build_tour(tmp_path)
    snapshot = tmp_path / "changed-snapshot.db"
    snapshot_key = os.urandom(32)
    real_search = reference.core_search.search
    changed = []

    def search_then_delete(*args, **kwargs):
        result = real_search(*args, **kwargs)
        if not changed:
            writer = connect.open_encrypted(source_path, source_key)
            try:
                current = api.status(writer, "tour-text", "library-en.txt")
                store.delete(
                    writer, store.DeleteRequest(
                        "delete-during-reference", "tour-text", "library-en.txt",
                        current["data"]["revision_token"],
                    ),
                )
            finally:
                writer.close()
            changed.append(True)
        return result

    with patch.object(
        reference.core_search, "search", side_effect=search_then_delete,
    ), patch(
        "airag.embeddings.embed_query",
        return_value=struct.pack("4f", 1, 0, 0, 0),
    ):
        with pytest.raises(
            reference.ReferenceSearchError,
            match="REFERENCE_SOURCE_CHANGED_DURING_QUERY",
        ):
            reference.search_tour_reference(
                source_path, source_key, snapshot, snapshot_key, scope(),
                query="reference", top_k=3,
            )
    assert changed == [True]
    assert snapshot.exists()


def test_wrong_source_key_and_snapshot_collision_fail_without_fallback(tmp_path):
    source_path, source_key = build_tour(tmp_path)
    snapshot = tmp_path / "wrong-key-snapshot.db"
    with pytest.raises(reference.ReferenceSearchError, match="REFERENCE_SNAPSHOT_FAILED"):
        reference.search_tour_reference(
            source_path, os.urandom(32), snapshot, os.urandom(32), scope(),
            query="reference",
        )
    assert not snapshot.exists()
    existing = tmp_path / "existing.db"
    existing.write_bytes(b"user-owned")
    with pytest.raises(reference.ReferenceSearchError, match="SNAPSHOT_PATH_EXISTS"):
        reference.search_tour_reference(
            source_path, source_key, existing, os.urandom(32), scope(),
            query="reference",
        )
    assert existing.read_bytes() == b"user-owned"
