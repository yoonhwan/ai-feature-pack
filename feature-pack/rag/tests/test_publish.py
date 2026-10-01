"""Real-DB regression tests for store.publish_generation_with_content and
the delete/restore visibility wiring, per ft-airag-arch-astra's
p03-publication-review.txt (space/profile mismatch, cross-space migration,
aggressive final_response_extra, empty document, partial-failure rollback,
delete/restore FTS/vector visibility)."""

from __future__ import annotations

import struct
import uuid
from pathlib import Path

import pytest

from airag import embeddings, profiles, store
from airag.db import connect

PINNED_TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


def _rid() -> str:
    return str(uuid.uuid4())


def _cfg(**overrides: object) -> embeddings.EmbeddingSpaceConfig:
    fields: dict[str, object] = {
        "provider": "lmstudio",
        "endpoint": "http://localhost:1234/v1",
        "model": "fake-model-a",
        "revision": "sha256:aaaa",
        "dimension": 4,
        "tokenizer_revision": PINNED_TOKENIZER_REVISION,
    }
    fields.update(overrides)
    return embeddings.EmbeddingSpaceConfig(**fields)  # type: ignore[arg-type]


def _vec(*values: float) -> bytes:
    return struct.pack(f"{len(values)}f", *values)


@pytest.fixture
def con(tmp_path: Path, key_bytes: bytes):
    c = connect.init_db(tmp_path / "publish.db", key_bytes)
    yield c
    c.close()


def _register(con, cfg: embeddings.EmbeddingSpaceConfig) -> tuple[int, str]:
    con.execute("BEGIN IMMEDIATE")
    space_id, profile_key = profiles.register_space_and_profile(con, cfg, {"adapter": "plain_text"})
    con.commit()
    embeddings.ensure_vec_space_table(con, space_id, cfg.dimension)
    return space_id, profile_key


def _add_and_stage(con, profile_key: str, content: bytes = b"hello world") -> dict[str, object]:
    return store.add(con, store.AddRequest(_rid(), "docs", "faq.md", content), profile_key=profile_key)


def _one_chunk_row(text: str = "hello world") -> dict[str, object]:
    return {"text": text, "token_count": 2, "anchor": {"headings": [], "items": []}}


# ------------------------------------------------------------ space/profile


def test_space_profile_mismatch_is_rejected(con) -> None:
    space_a, profile_a = _register(con, _cfg())
    space_b, _ = _register(con, _cfg(model="fake-model-b"))
    r = _add_and_stage(con, profile_a)

    with pytest.raises(store.ApiError) as excinfo:
        store.publish_generation_with_content(
            con, r["generation_id"], standard_md="md", structured_json={}, chunk_rows=[_one_chunk_row()],
            space_id=space_b, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
        )
    assert excinfo.value.code == "VALIDATION_ERROR"


def test_vector_byte_length_mismatch_is_rejected(con) -> None:
    space_a, profile_a = _register(con, _cfg())
    r = _add_and_stage(con, profile_a)
    with pytest.raises(store.ApiError) as excinfo:
        store.publish_generation_with_content(
            con, r["generation_id"], standard_md="md", structured_json={}, chunk_rows=[_one_chunk_row()],
            space_id=space_a, vectors=[_vec(1.0, 0.0)],  # only 2 floats, space is dim=4
        )
    assert excinfo.value.code == "DIMENSION_MISMATCH"


# ------------------------------------------------------- cross-space migration


def test_migration_to_a_different_space_deactivates_old_space_vectors_only(con) -> None:
    space_a, profile_a = _register(con, _cfg(model="model-a"))
    space_b, profile_b = _register(con, _cfg(model="model-b"))

    r1 = _add_and_stage(con, profile_a, b"v1")
    pub1 = store.publish_generation_with_content(
        con, r1["generation_id"], standard_md="md1", structured_json={}, chunk_rows=[_one_chunk_row("v1 text")],
        space_id=space_a, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
    )
    table_a = embeddings.vec_space_table_name(space_a)
    assert con.execute(f"SELECT active FROM {table_a} WHERE generation_id = ?", (pub1["generation_id"],)).fetchone() == (1,)

    current_token = store.get_status(con, "docs", "faq.md")["revision_token"]
    r2 = store.update(
        con, store.UpdateRequest(_rid(), "docs", "faq.md", current_token, b"v2"), profile_key=profile_b
    )
    pub2 = store.publish_generation_with_content(
        con, r2["generation_id"], standard_md="md2", structured_json={}, chunk_rows=[_one_chunk_row("v2 text")],
        space_id=space_b, vectors=[_vec(0.0, 1.0, 0.0, 0.0)],
    )

    # Old space A's row is deactivated — NOT the same table as B.
    assert con.execute(f"SELECT active FROM {table_a} WHERE generation_id = ?", (pub1["generation_id"],)).fetchone() == (0,)
    table_b = embeddings.vec_space_table_name(space_b)
    assert con.execute(f"SELECT active FROM {table_b} WHERE generation_id = ?", (pub2["generation_id"],)).fetchone() == (1,)
    # FTS reflects only the new generation's content.
    rows = con.execute("SELECT chunk_id FROM fts_chunks WHERE fts_chunks MATCH 'v1'").fetchall()
    assert rows == []
    rows = con.execute("SELECT chunk_id FROM fts_chunks WHERE fts_chunks MATCH 'v2'").fetchall()
    assert len(rows) == 1


# --------------------------------------------------------- aggressive extras


def test_final_response_extra_cannot_clobber_authoritative_fields(con) -> None:
    space_a, profile_a = _register(con, _cfg())
    r = _add_and_stage(con, profile_a)
    with pytest.raises(ValueError, match="authoritative"):
        store.publish_generation_with_content(
            con, r["generation_id"], standard_md="md", structured_json={}, chunk_rows=[_one_chunk_row()],
            space_id=space_a, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
            final_response_extra={"revision_token": "evil-forged-token", "state_version": 999},
        )
    # Nothing was published — generation is still staged, not partially ready.
    assert con.execute("SELECT status FROM generations WHERE generation_id = ?", (r["generation_id"],)).fetchone() == ("staged",)


# --------------------------------------------------------------- empty doc


def test_empty_document_reports_honest_non_searchable_status(con) -> None:
    space_a, profile_a = _register(con, _cfg())
    r = _add_and_stage(con, profile_a, b"")
    pub = store.publish_generation_with_content(
        con, r["generation_id"], standard_md="", structured_json={}, chunk_rows=[], space_id=space_a, vectors=[],
    )
    assert pub["searchable"] is False
    assert pub["processing_status"] == "ready_empty"
    assert pub["chunk_count"] == 0
    status = store.get_status(con, "docs", "faq.md")
    assert status["ready_generation_id"] == r["generation_id"]


# ------------------------------------------------------- partial failure


def test_partial_failure_mid_publish_rolls_back_completely(con) -> None:
    space_a, profile_a = _register(con, _cfg())
    r1 = _add_and_stage(con, profile_a, b"v1")
    pub1 = store.publish_generation_with_content(
        con, r1["generation_id"], standard_md="md1", structured_json={}, chunk_rows=[_one_chunk_row("v1 text")],
        space_id=space_a, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
    )

    current_token = store.get_status(con, "docs", "faq.md")["revision_token"]
    r2 = store.update(
        con, store.UpdateRequest(_rid(), "docs", "faq.md", current_token, b"v2"), profile_key=profile_a
    )
    # A malformed chunk row (missing "anchor") raises a KeyError partway
    # through the INSERT loop, inside the still-open BEGIN IMMEDIATE.
    bad_row: dict[str, object] = {"text": "v2 text", "token_count": 2}
    with pytest.raises(KeyError):
        store.publish_generation_with_content(
            con, r2["generation_id"], standard_md="md2", structured_json={}, chunk_rows=[bad_row],
            space_id=space_a, vectors=[_vec(0.0, 1.0, 0.0, 0.0)],
        )

    # Everything from generation 1's publish must be untouched.
    assert con.execute("SELECT status FROM generations WHERE generation_id = ?", (pub1["generation_id"],)).fetchone() == ("ready",)
    table_a = embeddings.vec_space_table_name(space_a)
    assert con.execute(f"SELECT active FROM {table_a} WHERE generation_id = ?", (pub1["generation_id"],)).fetchone() == (1,)
    rows = con.execute("SELECT chunk_id FROM fts_chunks WHERE fts_chunks MATCH 'v1'").fetchall()
    assert len(rows) == 1
    status = store.get_status(con, "docs", "faq.md")
    assert status["ready_generation_id"] == pub1["generation_id"]
    # The failed attempt never reached 'ready' and its job never completed.
    assert con.execute("SELECT status FROM generations WHERE generation_id = ?", (r2["generation_id"],)).fetchone() == ("staged",)
    assert con.execute("SELECT status FROM jobs WHERE job_id = ?", (r2["job_id"],)).fetchone() == ("running",)


# --------------------------------------------------------- delete/restore


def test_delete_hides_content_from_fts_and_vec_restore_brings_it_back(con) -> None:
    space_a, profile_a = _register(con, _cfg())
    r1 = _add_and_stage(con, profile_a, b"searchable content")
    pub1 = store.publish_generation_with_content(
        con, r1["generation_id"], standard_md="md", structured_json={}, chunk_rows=[_one_chunk_row("searchable content")],
        space_id=space_a, vectors=[_vec(1.0, 0.0, 0.0, 0.0)],
    )
    table_a = embeddings.vec_space_table_name(space_a)
    assert con.execute("SELECT chunk_id FROM fts_chunks WHERE fts_chunks MATCH 'searchable'").fetchall() != []
    assert con.execute(f"SELECT active FROM {table_a} WHERE generation_id = ?", (pub1["generation_id"],)).fetchone() == (1,)

    status = store.get_status(con, "docs", "faq.md")
    store.delete(con, store.DeleteRequest(_rid(), "docs", "faq.md", status["revision_token"]))
    assert con.execute("SELECT chunk_id FROM fts_chunks WHERE fts_chunks MATCH 'searchable'").fetchall() == []
    assert con.execute(f"SELECT active FROM {table_a} WHERE generation_id = ?", (pub1["generation_id"],)).fetchone() == (0,)

    status2 = store.get_status(con, "docs", "faq.md")
    store.restore(con, store.RestoreRequest(_rid(), "docs", "faq.md", status2["revision_token"]))
    rows = con.execute("SELECT chunk_id FROM fts_chunks WHERE fts_chunks MATCH 'searchable'").fetchall()
    assert len(rows) == 1
    assert con.execute(f"SELECT active FROM {table_a} WHERE generation_id = ?", (pub1["generation_id"],)).fetchone() == (1,)
