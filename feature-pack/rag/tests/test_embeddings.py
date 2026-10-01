from __future__ import annotations

import struct
import os
from pathlib import Path

import pytest

from airag import embeddings
from airag.db import connect

REAL_MODEL = "text-embedding-qwen3-embedding-0.6b"
REAL_REVISION = "gguf_sha256:06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439"
# Actual pinned commit for https://huggingface.co/Qwen/Qwen3-Embedding-0.6B,
# fetched via the HF API 2026-09-09 (api.huggingface.co/models/... "sha")
# — a real commit sha, never the floating "main" branch name.
PINNED_TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


def _cfg(**overrides: object) -> embeddings.EmbeddingSpaceConfig:
    fields: dict[str, object] = {
        "provider": "lmstudio",
        "endpoint": "http://localhost:1234/v1",
        "model": REAL_MODEL,
        "revision": REAL_REVISION,
        "dimension": 1024,
        "tokenizer_revision": PINNED_TOKENIZER_REVISION,
    }
    fields.update(overrides)
    return embeddings.EmbeddingSpaceConfig(**fields)  # type: ignore[arg-type]


# ---------------------------------------------------------- config validation


def test_validate_config_accepts_a_well_formed_config() -> None:
    embeddings.validate_config(_cfg())  # must not raise


def test_validate_config_rejects_unpinned_tokenizer_revision() -> None:
    for bad in ("main", "MAIN", "latest", "HEAD", ""):
        with pytest.raises(ValueError, match="pinned"):
            embeddings.validate_config(_cfg(tokenizer_revision=bad))


def test_validate_config_rejects_unsupported_provider() -> None:
    with pytest.raises(ValueError, match="provider"):
        embeddings.validate_config(_cfg(provider="totally-unknown"))


def test_validate_config_rejects_unsupported_document_preprocessing() -> None:
    with pytest.raises(ValueError, match="document_preprocessing"):
        embeddings.validate_config(_cfg(document_preprocessing="wrapped"))


def test_validate_config_rejects_non_http_endpoint() -> None:
    with pytest.raises(ValueError, match="http"):
        embeddings.validate_config(_cfg(endpoint="ftp://localhost/v1"))


@pytest.mark.parametrize("field,bad", [("dimension", 0), ("dimension", -1), ("dimension", True),
                                        ("max_tokens", 0), ("max_batch", 0), ("max_batch", True)])
def test_validate_config_rejects_non_positive_or_bool_int_fields(field: str, bad: object) -> None:
    with pytest.raises(ValueError):
        embeddings.validate_config(_cfg(**{field: bad}))


def test_validate_config_rejects_non_positive_timeout() -> None:
    with pytest.raises(ValueError, match="timeout_s"):
        embeddings.validate_config(_cfg(timeout_s=0.0))
    with pytest.raises(ValueError, match="timeout_s"):
        embeddings.validate_config(_cfg(timeout_s=float("nan")))


def test_validate_config_rejects_template_without_query_placeholder() -> None:
    with pytest.raises(ValueError, match="query"):
        embeddings.validate_config(_cfg(query_preprocessing_template="Instruct: {task}\nNo query here"))


def test_validate_config_rejects_unsupported_template_placeholder() -> None:
    with pytest.raises(ValueError, match="placeholder"):
        embeddings.validate_config(_cfg(query_preprocessing_template="{query} {mystery}"))


def test_validate_config_rejects_empty_task_description() -> None:
    with pytest.raises(ValueError, match="query_task_description"):
        embeddings.validate_config(_cfg(query_task_description="   "))


# ------------------------------------------------------------- fingerprint


def test_fingerprint_stable_for_identical_identity() -> None:
    assert embeddings.fingerprint_space(_cfg()) == embeddings.fingerprint_space(_cfg())


@pytest.mark.parametrize(
    "overrides",
    [
        {"model": "different-model"},
        {"revision": "gguf_sha256:different"},
        {"dimension": 768},
        {"document_preprocessing": "raw"},  # placeholder — overwritten below for query fields
        {"query_task_description": "a different task entirely"},
        {"provider": "openai-compatible"},
    ],
)
def test_fingerprint_changes_with_any_identity_field(overrides: dict[str, object]) -> None:
    if overrides == {"document_preprocessing": "raw"}:
        pytest.skip("placeholder case superseded by explicit modality/provider/task cases")
    assert embeddings.fingerprint_space(_cfg()) != embeddings.fingerprint_space(_cfg(**overrides))


def test_fingerprint_changes_with_query_task_description() -> None:
    a = _cfg(query_task_description="task A")
    b = _cfg(query_task_description="task B")
    assert embeddings.fingerprint_space(a) != embeddings.fingerprint_space(b)


def test_fingerprint_unaffected_by_operational_fields() -> None:
    """endpoint/timeout_s/max_batch/tokenizer_* are NOT part of D-001
    identity — two configs pointed at different endpoints for the same
    underlying model+revision are the same space."""
    a = _cfg(endpoint="http://localhost:1234/v1", timeout_s=10.0, max_batch=8)
    b = _cfg(endpoint="http://otherhost:9999/v1", timeout_s=99.0, max_batch=200)
    assert embeddings.fingerprint_space(a) == embeddings.fingerprint_space(b)


# --------------------------------------------------------------- register


def test_register_space_is_get_or_create(tmp_path: Path, key_bytes: bytes) -> None:
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        con.execute("BEGIN IMMEDIATE")
        sid1 = embeddings.register_space(con, _cfg())
        sid2 = embeddings.register_space(con, _cfg())
        con.commit()
        assert sid1 == sid2
        assert con.execute("SELECT COUNT(*) FROM embedding_spaces").fetchone() == (1,)
    finally:
        con.close()


def test_register_space_different_identity_creates_new_row(tmp_path: Path, key_bytes: bytes) -> None:
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        con.execute("BEGIN IMMEDIATE")
        sid1 = embeddings.register_space(con, _cfg())
        sid2 = embeddings.register_space(con, _cfg(dimension=768))
        con.commit()
        assert sid1 != sid2
    finally:
        con.close()


def test_register_space_rejects_invalid_config(tmp_path: Path, key_bytes: bytes) -> None:
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        con.execute("BEGIN IMMEDIATE")
        with pytest.raises(ValueError):
            embeddings.register_space(con, _cfg(tokenizer_revision="main"))
        con.rollback()
    finally:
        con.close()


def test_config_from_space_row_reconstructs_full_identity(tmp_path: Path, key_bytes: bytes) -> None:
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        original = _cfg(query_task_description="a specific pinned task description")
        con.execute("BEGIN IMMEDIATE")
        space_id = embeddings.register_space(con, original)
        con.commit()

        reloaded = embeddings.config_from_space_row(
            con, space_id,
            endpoint="http://localhost:1234/v1",
            tokenizer_model=original.tokenizer_model,
            tokenizer_revision=original.tokenizer_revision,
            max_tokens=original.max_tokens,
        )
        assert reloaded.identity_fields() == original.identity_fields()
        assert embeddings.fingerprint_space(reloaded) == embeddings.fingerprint_space(original)
    finally:
        con.close()


# ------------------------------------------------------------- pack_vector


def test_pack_vector_round_trips() -> None:
    values = [1.0, -2.5, 0.0, 3.25]
    packed = embeddings._check_float32_safe(0, values)
    assert struct.unpack(f"{len(values)}f", packed) == tuple(values)


# ------------------------------------------------------ response validation


def _resp(data: list[dict[str, object]], *, model: str | None = REAL_MODEL) -> dict[str, object]:
    out: dict[str, object] = {"data": data, "usage": {"prompt_tokens": 0, "total_tokens": 0}}
    if model is not None:
        out["model"] = model
    return out


def _unpack_all(packed_list: list[bytes], dim: int) -> list[tuple[float, ...]]:
    return [struct.unpack(f"{dim}f", p) for p in packed_list]


def test_validate_orders_by_index_not_response_order() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp(
        [
            {"index": 1, "embedding": [0.0, 1.0]},
            {"index": 0, "embedding": [1.0, 0.0]},
        ]
    )
    vectors = _unpack_all(embeddings._validate_and_pack(cfg, payload, 2), 2)
    assert vectors == [(1.0, 0.0), (0.0, 1.0)]


def test_validate_requires_model_echo() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [1.0, 0.0]}], model=None)
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "MODEL_MISMATCH"


def test_validate_rejects_model_mismatch() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [1.0, 0.0]}], model="a-different-model")
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "MODEL_MISMATCH"


def test_validate_rejects_wrong_count() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [1.0, 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 2)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_validate_rejects_duplicate_index() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [1.0, 0.0]}, {"index": 0, "embedding": [0.0, 1.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 2)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_validate_rejects_out_of_range_index() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 5, "embedding": [1.0, 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_validate_rejects_bool_index() -> None:
    """bool is a subclass of int in Python — True/False must never be
    accepted as a valid 0/1 index."""
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": True, "embedding": [1.0, 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_validate_rejects_bool_vector_component() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [True, 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_validate_rejects_numeric_string_vector_component() -> None:
    """No float()-coercion of a JSON string — a numeric string is not the
    same contract as an actual JSON number."""
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": ["1.0", 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_validate_rejects_wrong_dimension() -> None:
    cfg = _cfg(dimension=4)
    payload = _resp([{"index": 0, "embedding": [1.0, 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "DIMENSION_MISMATCH"


def test_validate_rejects_non_finite_values() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [float("nan"), 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "NON_FINITE_VECTOR"


def test_validate_rejects_all_zero_vector() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [0.0, 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "ZERO_VECTOR"


def test_validate_rejects_float32_overflow() -> None:
    """A finite float64 value (1e39) that overflows float32 range packs to
    +-inf silently (struct.pack does not raise) — must be caught anyway."""
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [1e39, 0.0]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "NON_FINITE_VECTOR"


def test_validate_rejects_float32_underflow_to_all_zero() -> None:
    cfg = _cfg(dimension=2)
    payload = _resp([{"index": 0, "embedding": [1e-300, 1e-300]}])
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings._validate_and_pack(cfg, payload, 1)
    assert excinfo.value.code == "ZERO_VECTOR"


# ---------------------------------------------------------- vec space table


def test_ensure_vec_space_table_creates_table_with_declared_dimension(
    tmp_path: Path, key_bytes: bytes
) -> None:
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        table = embeddings.ensure_vec_space_table(con, 7, 4)
        assert table == "vec_space_7"
        con.execute(
            f"INSERT INTO {table}(chunk_id, embedding, source_id, collection_id, generation_id, active) "
            "VALUES (1, ?, 10, 1, 100, 1)",
            (embeddings._check_float32_safe(0, [1.0, 0.0, 0.0, 0.0]),),
        )
        con.commit()
        row = con.execute(f"SELECT chunk_id FROM {table} WHERE chunk_id = 1").fetchone()
        assert row == (1,)
    finally:
        con.close()


# ------------------------------------------------------- live integration
#
# Requires a reachable LM Studio server serving text-embedding-qwen3-
# embedding-0.6b at localhost:1234 (per docs/artifacts/p03a-provider-probe.
# json). Skipped by default (pytest.ini addopts = "-m 'not integration'").


@pytest.mark.integration
def test_embed_query_and_documents_against_real_lmstudio() -> None:
    cfg = _cfg()
    if os.environ.get("AIRAG_EMBED_ENDPOINT"):
        from dataclasses import replace
        cfg = replace(cfg, provider="openai-compatible", endpoint=os.environ["AIRAG_EMBED_ENDPOINT"],
                      model=os.environ.get("AIRAG_EMBED_MODEL", "byz-embed"), revision=os.environ["AIRAG_EMBED_REVISION"])
    q_vec = struct.unpack("1024f", embeddings.embed_query(cfg, "고양이 수면 습관"))
    assert len(q_vec) == 1024
    doc_packed = embeddings.embed_documents(
        cfg,
        [
            "고양이는 하루의 대부분을 잠으로 보내는 동물이다.",
            "오늘 서울의 날씨는 맑고 기온은 25도이다.",
        ],
    )
    assert len(doc_packed) == 2
    doc_vecs = _unpack_all(doc_packed, 1024)
    assert all(len(v) == 1024 for v in doc_vecs)

    def cosine(a: tuple[float, ...], b: tuple[float, ...]) -> float:
        dot = sum(x * y for x, y in zip(a, b))
        na = sum(x * x for x in a) ** 0.5
        nb = sum(y * y for y in b) ** 0.5
        return dot / (na * nb)

    assert cosine(q_vec, doc_vecs[0]) > cosine(q_vec, doc_vecs[1])


@pytest.mark.integration
def test_embed_documents_on_batch_hook_fires_per_batch() -> None:
    cfg = _cfg(max_batch=1)
    if os.environ.get("AIRAG_EMBED_ENDPOINT"):
        from dataclasses import replace
        cfg = replace(cfg, provider="openai-compatible", endpoint=os.environ["AIRAG_EMBED_ENDPOINT"],
                      model=os.environ.get("AIRAG_EMBED_MODEL", "byz-embed"), revision=os.environ["AIRAG_EMBED_REVISION"])
    calls: list[tuple[int, int]] = []
    embeddings.embed_documents(
        cfg, ["첫번째 문서", "두번째 문서", "세번째 문서"],
        on_batch=lambda done, total: calls.append((done, total)),
    )
    assert calls == [(1, 3), (2, 3), (3, 3)]


@pytest.mark.integration
def test_embed_query_too_long_is_rejected_not_truncated() -> None:
    cfg = _cfg(max_tokens=16)
    with pytest.raises(embeddings.EmbeddingError) as excinfo:
        embeddings.embed_query(cfg, "고양이 " * 200)
    assert excinfo.value.code == "QUERY_TOO_LONG"
