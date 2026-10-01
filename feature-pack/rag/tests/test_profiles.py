from __future__ import annotations

from pathlib import Path

from airag import embeddings, profiles
from airag.db import connect

PINNED_TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


def _cfg(**overrides: object) -> embeddings.EmbeddingSpaceConfig:
    fields: dict[str, object] = {
        "provider": "lmstudio",
        "endpoint": "http://localhost:1234/v1",
        "model": "text-embedding-qwen3-embedding-0.6b",
        "revision": "gguf_sha256:06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439",
        "dimension": 1024,
        "tokenizer_revision": PINNED_TOKENIZER_REVISION,
    }
    fields.update(overrides)
    return embeddings.EmbeddingSpaceConfig(**fields)  # type: ignore[arg-type]


def test_register_space_and_profile_is_idempotent(tmp_path: Path, key_bytes: bytes) -> None:
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        cfg = _cfg()
        normalizer_config = {"adapter": "markdown", "version": 1}
        con.execute("BEGIN IMMEDIATE")
        space_id1, key1 = profiles.register_space_and_profile(con, cfg, normalizer_config)
        space_id2, key2 = profiles.register_space_and_profile(con, cfg, normalizer_config)
        con.commit()
        assert space_id1 == space_id2
        assert key1 == key2
        assert con.execute("SELECT COUNT(*) FROM processing_profiles").fetchone() == (1,)
    finally:
        con.close()


def test_different_normalizer_config_yields_different_profile_same_space(
    tmp_path: Path, key_bytes: bytes
) -> None:
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        cfg = _cfg()
        con.execute("BEGIN IMMEDIATE")
        space_id1, key1 = profiles.register_space_and_profile(con, cfg, {"adapter": "markdown"})
        space_id2, key2 = profiles.register_space_and_profile(con, cfg, {"adapter": "plain_text"})
        con.commit()
        assert space_id1 == space_id2  # same embedding space
        assert key1 != key2  # different profile
    finally:
        con.close()


def test_config_from_profile_reconstructs_full_config(tmp_path: Path, key_bytes: bytes) -> None:
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        original = _cfg(timeout_s=12.5, max_batch=16)
        normalizer_config = {"adapter": "markdown", "version": 1}
        con.execute("BEGIN IMMEDIATE")
        _, profile_key = profiles.register_space_and_profile(con, original, normalizer_config)
        con.commit()

        reloaded_cfg, reloaded_norm_config = profiles.config_from_profile(con, profile_key)
        assert reloaded_cfg == original
        assert reloaded_norm_config == normalizer_config
    finally:
        con.close()


def test_config_from_profile_allows_endpoint_override(tmp_path: Path, key_bytes: bytes) -> None:
    """endpoint is operational, not identity — overriding it on reload
    (e.g. a tunnel's local port changed) must not change the profile_key
    or the reconstructed identity fields."""
    con = connect.init_db(tmp_path / "t.db", key_bytes)
    try:
        original = _cfg(endpoint="http://localhost:1234/v1")
        con.execute("BEGIN IMMEDIATE")
        _, profile_key = profiles.register_space_and_profile(con, original, {})
        con.commit()

        reloaded_cfg, _ = profiles.config_from_profile(con, profile_key, endpoint="http://localhost:9999/v1")
        assert reloaded_cfg.endpoint == "http://localhost:9999/v1"
        assert reloaded_cfg.identity_fields() == original.identity_fields()
        assert embeddings.fingerprint_space(reloaded_cfg) == embeddings.fingerprint_space(original)
    finally:
        con.close()


def test_enrichment_identity_and_config_survive_reload(tmp_path: Path, key_bytes: bytes) -> None:
    from dataclasses import replace
    from airag import llm_enrichment, pipeline

    con = connect.init_db(tmp_path / "enriched.db", key_bytes)
    llm = llm_enrichment.ChatCompletionConfig("byz-vllm", "http://localhost:8002/v1", "byz-llm", "revision-a", 24576)
    try:
        con.execute("BEGIN IMMEDIATE")
        raw_space, raw_profile = profiles.register_space_and_profile(con, _cfg(), {})
        space, profile = profiles.register_space_and_profile(con, _cfg(), {}, llm=llm)
        other_space, other_profile = profiles.register_space_and_profile(con, _cfg(), {}, llm=replace(llm, weights_revision="revision-b"))
        moved_space, moved_profile = profiles.register_space_and_profile(con, _cfg(), {}, llm=replace(llm, endpoint="http://localhost:9999/v1"))
        con.commit()
        assert len({raw_space, space, other_space}) == 3
        assert len({raw_profile, profile, other_profile, moved_profile}) == 4
        assert moved_space == space
        restored = pipeline.PipelineConfig.from_profile(con, profile)
        assert restored.llm == llm
        assert restored.embedding == profiles.embedding_for_llm(_cfg(), llm)
        assert pipeline.PipelineConfig.from_profile(con, raw_profile).llm is None
    finally:
        con.close()
