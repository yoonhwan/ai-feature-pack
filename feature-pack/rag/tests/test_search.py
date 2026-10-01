"""search.py: real-DB tests for eligibility filtering, BM25+vec0 RRF
fusion, immutable manifest persistence, historical replay, and FTS
injection safety. Network-free by construction — all vectors here are
synthetic, no embedding/LLM provider is ever called."""

from __future__ import annotations

import struct
import uuid
from pathlib import Path

import pytest

from airag import embeddings, profiles, search, store
from airag.db import connect

PINNED_TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


def _rid() -> str:
    return str(uuid.uuid4())


def _vec(*values: float) -> bytes:
    return struct.pack(f"{len(values)}f", *values)


@pytest.fixture
def con(tmp_path: Path, key_bytes: bytes):
    c = connect.init_db(tmp_path / "search.db", key_bytes)
    yield c
    c.close()


def _cfg(**overrides: object) -> embeddings.EmbeddingSpaceConfig:
    fields: dict[str, object] = {
        "provider": "lmstudio", "endpoint": "http://localhost:1234/v1", "model": "fake-embed",
        "revision": "sha256:aaaa", "dimension": 4, "tokenizer_revision": PINNED_TOKENIZER_REVISION,
    }
    fields.update(overrides)
    return embeddings.EmbeddingSpaceConfig(**fields)  # type: ignore[arg-type]


def _register(con, cfg: embeddings.EmbeddingSpaceConfig) -> tuple[int, str]:
    con.execute("BEGIN IMMEDIATE")
    space_id, profile_key = profiles.register_space_and_profile(con, cfg, {"adapter": "plain_text"})
    con.commit()
    embeddings.ensure_vec_space_table(con, space_id, cfg.dimension)
    return space_id, profile_key


def _publish(con, space_id: int, profile_key: str, source_key: str, text: str, vec: bytes, collection: str = "docs") -> dict[str, object]:
    r = store.add(con, store.AddRequest(_rid(), collection, source_key, text.encode("utf-8")), profile_key=profile_key)
    return store.publish_generation_with_content(
        con, r["generation_id"], standard_md=text, structured_json={},
        chunk_rows=[{"text": text, "token_count": 3, "anchor": {"headings": [], "items": []}}],
        space_id=space_id, vectors=[vec],
    )


def _query(**overrides: object) -> search.SearchQuery:
    fields: dict[str, object] = {
        "collection": "docs", "original_query": "cats", "search_query_text": "cats",
        "query_vector": _vec(1.0, 0.0, 0.0, 0.0), "space_id": 1, "profile_key": "p",
    }
    fields.update(overrides)
    return search.SearchQuery(**fields)  # type: ignore[arg-type]


# --------------------------------------------------------------- validation


def test_validate_rejects_empty_query_vector() -> None:
    with pytest.raises(search.SearchError) as excinfo:
        _query(query_vector=b"").validate()
    assert excinfo.value.code == "VALIDATION_ERROR"


def test_validate_rejects_non_positive_top_k() -> None:
    with pytest.raises(search.SearchError):
        _query(top_k=0).validate()


def test_validate_rejects_top_k_over_max() -> None:
    with pytest.raises(search.SearchError):
        _query(top_k=search.MAX_TOP_K + 1).validate()


def test_validate_rejects_non_dict_provenance() -> None:
    with pytest.raises(search.SearchError):
        _query(query_provenance="not-a-dict").validate()  # type: ignore[arg-type]


# ------------------------------------------------------- FTS injection safety


def test_escape_fts_query_neutralizes_operators() -> None:
    escaped = search._escape_fts_query('fox AND "evil" OR * (nested)')
    assert escaped == '"fox" OR "AND" OR """evil""" OR "OR" OR "*" OR "(nested)"'
    # Every token is individually quoted — AND/OR/* have no special meaning
    # once inside a quoted phrase; unbalanced/odd quoting inside a token is
    # escaped by doubling, never left to break out of its own quotes.


def test_escape_fts_query_rejects_whitespace_only() -> None:
    with pytest.raises(search.SearchError):
        search._escape_fts_query("   ")


# --------------------------------------------------------------- end to end


def test_search_fuses_bm25_and_vector_hits_deterministically(con) -> None:
    space_id, profile_key = _register(con, _cfg())
    pub_cat = _publish(con, space_id, profile_key, "cat.md", "cats sleep all day long", _vec(1.0, 0.0, 0.0, 0.0))
    pub_dog = _publish(con, space_id, profile_key, "dog.md", "dogs bark at strangers", _vec(0.0, 1.0, 0.0, 0.0))

    q = _query(
        original_query="고양이", search_query_text="cats sleep", query_vector=_vec(1.0, 0.0, 0.0, 0.0),
        space_id=space_id, profile_key=profile_key, query_provenance={"translated": True, "original_language": "ko"},
    )
    result = search.search(con, q)

    assert result["historical"] is False
    assert len(result["results"]) == 2
    top = result["results"][0]
    assert top["generation_id"] == pub_cat["generation_id"]
    assert top["bm25_rank"] == 1
    assert top["vec_rank"] == 1
    assert top["embedded_text"] == "cats sleep all day long"
    assert top["original_text"] == "cats sleep all day long"  # no LLM enrichment -> same as embedded
    assert top["is_translated"] is False
    second = result["results"][1]
    assert second["generation_id"] == pub_dog["generation_id"]
    assert second["vec_rank"] is None or second["vec_rank"] > top["vec_rank"]

    manifest_id = result["manifest_id"]
    row = con.execute("SELECT query_text, space_id, profile_key FROM search_manifests WHERE manifest_id = ?", (manifest_id,)).fetchone()
    assert row == ("고양이", space_id, profile_key)


def test_search_vector_only_hit_surfaces_without_bm25_match(con) -> None:
    """Text has NO overlapping keywords with the query, but the vector is
    an exact match — must still surface via the vector retriever alone."""
    space_id, profile_key = _register(con, _cfg())
    _publish(con, space_id, profile_key, "a.md", "completely unrelated wording here", _vec(1.0, 0.0, 0.0, 0.0))

    q = _query(search_query_text="nonmatching keyword", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key)
    result = search.search(con, q)
    assert len(result["results"]) == 1
    assert result["results"][0]["bm25_rank"] is None
    assert result["results"][0]["vec_rank"] == 1


def test_search_excludes_deleted_source(con) -> None:
    space_id, profile_key = _register(con, _cfg())
    pub = _publish(con, space_id, profile_key, "a.md", "cats sleeping soundly", _vec(1.0, 0.0, 0.0, 0.0))
    status = store.get_status(con, "docs", "a.md")
    store.delete(con, store.DeleteRequest(_rid(), "docs", "a.md", status["revision_token"]))

    q = _query(search_query_text="cats", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key)
    result = search.search(con, q)
    assert result["results"] == []
    assert result["eligible"]["count"] == 0


def test_search_excludes_content_from_a_different_space(con) -> None:
    space_a, profile_a = _register(con, _cfg(model="model-a"))
    space_b, profile_b = _register(con, _cfg(model="model-b"))
    _publish(con, space_a, profile_a, "a.md", "cats sleeping", _vec(1.0, 0.0, 0.0, 0.0))

    q = _query(search_query_text="cats", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_b, profile_key=profile_b)
    result = search.search(con, q)
    assert result["results"] == []
    assert result["eligible"]["count"] == 0


def test_search_excludes_content_from_a_different_collection(con) -> None:
    space_id, profile_key = _register(con, _cfg())
    other_pub = _publish(con, space_id, profile_key, "a.md", "cats sleeping", _vec(1.0, 0.0, 0.0, 0.0), collection="other-collection")
    # "docs" must actually exist (search on a never-created collection is a
    # separate NOT_FOUND case, covered by test_search_on_unknown_collection_raises_not_found).
    # Vector KNN always returns its k-nearest candidates regardless of
    # absolute distance (no similarity threshold) — with exactly one
    # candidate in "docs", that unrelated doc legitimately appears; the
    # property under test is that the OTHER collection's "cats" match
    # (which would otherwise rank #1 on both BM25 and vector) is absent.
    _publish(con, space_id, profile_key, "unrelated.md", "totally unrelated dog content", _vec(0.0, 1.0, 0.0, 0.0), collection="docs")

    q = _query(collection="docs", search_query_text="cats", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key)
    result = search.search(con, q)
    result_generation_ids = {r["generation_id"] for r in result["results"]}
    assert other_pub["generation_id"] not in result_generation_ids
    assert all(r["collection"] == "docs" for r in result["results"])


def test_search_distinguishes_original_from_translated_text(con) -> None:
    space_id, profile_key = _register(con, _cfg())
    r = store.add(con, store.AddRequest(_rid(), "docs", "a.md", "한국어 원문".encode("utf-8")), profile_key=profile_key)
    anchor = {"headings": [], "items": [], "llm_enrichment": {"original_text": "한국어 원문", "translation_en": "Korean original text"}}
    store.publish_generation_with_content(
        con, r["generation_id"], standard_md="", structured_json={},
        chunk_rows=[{"text": "Korean original text", "token_count": 3, "anchor": anchor}],
        space_id=space_id, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
    )
    result = search.search(con, _query(search_query_text="Korean", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key))
    hit = result["results"][0]
    assert hit["embedded_text"] == "Korean original text"
    assert hit["original_text"] == "한국어 원문"
    assert hit["is_translated"] is True


# ------------------------------------------------------------ replay/history


def test_replay_manifest_is_immutable_across_later_deletion(con) -> None:
    space_id, profile_key = _register(con, _cfg())
    _publish(con, space_id, profile_key, "a.md", "cats sleeping soundly", _vec(1.0, 0.0, 0.0, 0.0))

    q = _query(search_query_text="cats", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key)
    original = search.search(con, q)
    manifest_id = original["manifest_id"]
    assert len(original["results"]) == 1

    status = store.get_status(con, "docs", "a.md")
    store.delete(con, store.DeleteRequest(_rid(), "docs", "a.md", status["revision_token"]))

    replayed = search.replay_manifest(con, manifest_id)
    assert replayed["historical"] is True
    assert len(replayed["results"]) == 1  # STILL shows the original evidence
    assert replayed["results"][0]["embedded_text"] == "cats sleeping soundly"

    fresh = search.search(con, q)
    assert fresh["results"] == []  # a FRESH search correctly reflects the deletion


def test_replay_unknown_manifest_raises_not_found(con) -> None:
    with pytest.raises(search.SearchError) as excinfo:
        search.replay_manifest(con, 999999)
    assert excinfo.value.code == "NOT_FOUND"


def test_replay_rejects_non_positive_or_bool_manifest_id(con) -> None:
    for bad in (0, -1, True):
        with pytest.raises(search.SearchError) as excinfo:
            search.replay_manifest(con, bad)  # type: ignore[arg-type]
        assert excinfo.value.code == "VALIDATION_ERROR"


def test_search_and_replay_expose_provenance_and_ranking_settings(con) -> None:
    space_id, profile_key = _register(con, _cfg())
    pub = _publish(con, space_id, profile_key, "a.md", "cats sleeping soundly", _vec(1.0, 0.0, 0.0, 0.0))
    provenance = {"translated": True, "original_language": "ko", "translation_model": "byz-llm"}

    q = _query(
        original_query="고양이", search_query_text="cats", query_vector=_vec(1.0, 0.0, 0.0, 0.0),
        space_id=space_id, profile_key=profile_key, rrf_k=42, query_provenance=provenance,
    )
    fresh = search.search(con, q)
    for result in (fresh, search.replay_manifest(con, fresh["manifest_id"])):
        assert result["space_id"] == space_id
        assert result["profile_key"] == profile_key
        assert result["query_provenance"] == provenance
        assert result["ranking"]["rrf_k"] == 42
        assert result["ranking"]["exact_cosine"] is True
        assert result["ranking"]["candidate_limit"] > 0

    eligible = fresh["eligible"]
    assert eligible["count"] == 1
    assert eligible["sources"] == [{
        "source_id": pub["source_id"], "revision_id": pub["revision_id"], "generation_id": pub["generation_id"],
    }]


def test_original_text_not_claimed_contiguous_without_matching_anchor(con) -> None:
    """No llm_enrichment blob, and the anchor's own matched_text does NOT
    equal the stored (contextualized) text — must not claim contiguity."""
    space_id, profile_key = _register(con, _cfg())
    r = store.add(con, store.AddRequest(_rid(), "docs", "a.md", b"heading context body"), profile_key=profile_key)
    anchor = {"headings": ["Some Heading"], "items": [
        {"self_ref": "#/x", "granularity": "exact", "matched_text": "body only, not the full contextualized text"}
    ]}
    store.publish_generation_with_content(
        con, r["generation_id"], standard_md="", structured_json={},
        chunk_rows=[{"text": "Some Heading\nbody", "token_count": 3, "anchor": anchor}],
        space_id=space_id, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
    )
    result = search.search(con, _query(search_query_text="heading", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key))
    hit = result["results"][0]
    assert hit["original_text_is_contiguous"] is False
    assert hit["provenance_granularity"] == "exact"


def test_original_text_claimed_contiguous_when_anchor_matches_exactly(con) -> None:
    space_id, profile_key = _register(con, _cfg())
    r = store.add(con, store.AddRequest(_rid(), "docs", "a.md", b"plain body text"), profile_key=profile_key)
    anchor = {"headings": [], "items": [{"self_ref": "#/x", "granularity": "exact", "matched_text": "plain body text"}]}
    store.publish_generation_with_content(
        con, r["generation_id"], standard_md="", structured_json={},
        chunk_rows=[{"text": "plain body text", "token_count": 3, "anchor": anchor}],
        space_id=space_id, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
    )
    result = search.search(con, _query(search_query_text="plain", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key))
    hit = result["results"][0]
    assert hit["original_text_is_contiguous"] is True
    assert hit["provenance_granularity"] == "exact"


def test_search_on_unknown_collection_raises_not_found(con) -> None:
    with pytest.raises(search.SearchError) as excinfo:
        search.search(con, _query(collection="never-registered", space_id=1, profile_key="p"))
    assert excinfo.value.code == "NOT_FOUND"


# ---------------------------------------------------- reopened-connection


def test_search_works_on_a_freshly_reopened_connection(tmp_path: Path, key_bytes: bytes) -> None:
    """The real CLI/API path: a fresh process opens the DB via
    connect.open_encrypted() — a DIFFERENT connection object than whichever
    one created the vec0 tables — which does NOT have sqlite_vec loaded by
    default (owner review 2026-09-10, reproduced via a real separate-
    process CLI E2E: 'no such module: vec0'). search() must load it
    itself, without creating any table (no DDL)."""
    db_path = tmp_path / "reopen.db"
    con1 = connect.init_db(db_path, key_bytes)
    space_id, profile_key = _register(con1, _cfg())
    _publish(con1, space_id, profile_key, "a.md", "cats sleeping soundly", _vec(1.0, 0.0, 0.0, 0.0))
    con1.close()

    con2 = connect.open_encrypted(db_path, key_bytes)  # fresh connection — vec0 NOT loaded on it
    try:
        result = search.search(con2, _query(
            search_query_text="cats", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key,
        ))
        assert len(result["results"]) == 1
    finally:
        con2.close()


# ------------------------------------------------- exact scalar-cosine path


def test_search_breaks_exact_vector_distance_ties_deterministically(con) -> None:
    space_id, profile_key = _register(con, _cfg())
    _publish(con, space_id, profile_key, "a.md", "first document text", _vec(1.0, 0.0, 0.0, 0.0))
    _publish(con, space_id, profile_key, "b.md", "second document text", _vec(1.0, 0.0, 0.0, 0.0))  # exact tie

    q = _query(search_query_text="unrelated wording", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key)
    result1 = search.search(con, q)
    result2 = search.search(con, q)
    ids1 = [r["chunk_id"] for r in result1["results"]]
    ids2 = [r["chunk_id"] for r in result2["results"]]
    assert ids1 == ids2 == sorted(ids1)  # stable across repeated runs, ascending chunk_id tie-break


def test_search_excludes_stale_superseded_generation_vectors(con) -> None:
    """After a content update+republish, the OLD generation's vector row
    still physically exists (retained history) but must never leak into
    fresh search results — even sharing an identical vector with the
    current one."""
    space_id, profile_key = _register(con, _cfg())
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "a.md", b"v1"), profile_key=profile_key)
    old_pub = store.publish_generation_with_content(
        con, r1["generation_id"], standard_md="v1", structured_json={},
        chunk_rows=[{"text": "v1 unrelated wording", "token_count": 1, "anchor": {"headings": [], "items": []}}],
        space_id=space_id, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
    )
    current_token = store.get_status(con, "docs", "a.md")["revision_token"]
    r2 = store.update(con, store.UpdateRequest(_rid(), "docs", "a.md", current_token, b"v2"), profile_key=profile_key)
    new_pub = store.publish_generation_with_content(
        con, r2["generation_id"], standard_md="v2", structured_json={},
        chunk_rows=[{"text": "v2 unrelated wording", "token_count": 1, "anchor": {"headings": [], "items": []}}],
        space_id=space_id, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],  # SAME vector as the now-superseded generation
    )

    result = search.search(con, _query(
        search_query_text="unrelated wording", query_vector=_vec(1.0, 0.0, 0.0, 0.0), space_id=space_id, profile_key=profile_key,
    ))
    result_gen_ids = {r["generation_id"] for r in result["results"]}
    assert new_pub["generation_id"] in result_gen_ids
    assert old_pub["generation_id"] not in result_gen_ids
