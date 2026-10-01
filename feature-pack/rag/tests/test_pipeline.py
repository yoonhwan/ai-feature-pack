"""Wiring tests for pipeline.py — mocks the LLM/embedding HTTP layers (no
live GPU needed for these) and verifies against a real encrypted DB that:
the ENGLISH TRANSLATION (not the original text) is what gets embedded and
stored as chunks.text, the original text/group provenance/prompt versions
survive in the anchor untouched, lease renewal fires between embedding
batches, and a mid-pipeline failure fails the generation cleanly (no
partial publish). Real GPU integration is opt-in in test_pipeline_live.py;
these mocked tests do not establish actual model quality."""

from __future__ import annotations

import struct
import uuid
from pathlib import Path
from unittest.mock import patch

import pytest

from airag import embeddings, llm_enrichment, pipeline, profiles, store
from airag.db import connect

PINNED_TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


def _rid() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def con(tmp_path: Path, key_bytes: bytes):
    c = connect.init_db(tmp_path / "pipeline.db", key_bytes)
    yield c
    c.close()


def _embed_cfg(**overrides: object) -> embeddings.EmbeddingSpaceConfig:
    fields: dict[str, object] = {
        "provider": "lmstudio", "endpoint": "http://localhost:1234/v1", "model": "fake-embed",
        "revision": "sha256:aaaa", "dimension": 4, "tokenizer_revision": PINNED_TOKENIZER_REVISION,
    }
    fields.update(overrides)
    return embeddings.EmbeddingSpaceConfig(**fields)  # type: ignore[arg-type]


def _llm_cfg() -> llm_enrichment.ChatCompletionConfig:
    return llm_enrichment.ChatCompletionConfig(
        provider="byz-vllm", endpoint="http://localhost:8002/v1", model="byz-llm", weights_revision=None,
        context_length=24576,
    )


def _fake_vector(dim: int, seed: float) -> bytes:
    return struct.pack(f"{dim}f", *[seed] * dim)


def _stage(con, space_id: int, profile_key: str, content: bytes) -> dict[str, object]:
    return store.add(con, store.AddRequest(_rid(), "docs", "faq.md", content, media_type="text/plain"), profile_key=profile_key)


def test_pipeline_embeds_english_translation_not_original_and_preserves_provenance(con) -> None:
    embed_cfg = _embed_cfg()
    con.execute("BEGIN IMMEDIATE")
    space_id, profile_key = profiles.register_space_and_profile(con, embed_cfg, {"adapter": "plain_text"}, llm=_llm_cfg())
    con.commit()

    content = "한국어 원문입니다.".encode("utf-8")
    r = _stage(con, space_id, profile_key, content)
    cfg = pipeline.PipelineConfig(embedding=embed_cfg, space_id=space_id, llm=_llm_cfg())

    fake_group = llm_enrichment.SemanticGroup(unit_ids=["chunk-0"], group_summary="g-summary", group_tags=["g-tag"])
    fake_enrichment = llm_enrichment.UnitEnrichment(
        unit_id="group-0-0", tags=["tag1"], summary="an english summary", translation_en="This is the English translation."
    )

    with patch("airag.llm_enrichment.plan_semantic_groups", return_value=([fake_group], {"prompt_version": "v1-groups"})), \
         patch("airag.llm_enrichment.enrich_units", return_value=([fake_enrichment], {
             "prompt_version": "v1-enrich", "model_echoed": "byz-llm",
             "system_fingerprint_RUNTIME_NOT_WEIGHTS": "vllm-0.28.0-fake",
             "configured_weights_revision": None,
         })), \
         patch("airag.embeddings.embed_documents") as mock_embed, \
         patch("airag.embeddings.count_tokens", return_value=7):
        mock_embed.return_value = [_fake_vector(4, 1.0)]
        result = pipeline.process_and_publish(
            con, job_id=r["job_id"], generation_id=r["generation_id"], claim_epoch=1,
            content=content, media_type="text/plain", source_key="faq.md", cfg=cfg,
        )

    assert result["status"] == "ready"
    assert result["chunk_count"] == 1

    # embed_documents must have been called with the TRANSLATION, never the original.
    embedded_texts_passed = mock_embed.call_args[0][1]
    assert embedded_texts_passed == ["This is the English translation."]

    row = con.execute(
        "SELECT text, anchor_json FROM chunks WHERE generation_id = ?", (result["generation_id"],)
    ).fetchone()
    text, anchor_json = row
    assert text == "This is the English translation."  # chunks.text IS the translation
    import json
    anchor = json.loads(anchor_json)
    enrichment = anchor["llm_enrichment"]
    assert enrichment["original_text"] == "한국어 원문입니다."  # original preserved verbatim, distinctly
    assert enrichment["translation_en"] == "This is the English translation."
    assert enrichment["tags"] == ["tag1"]
    assert enrichment["group_summary"] == "g-summary"
    assert enrichment["enrich_prompt_version"] == "v1-enrich"
    assert enrichment["group_prompt_version"] == "v1-groups"
    assert enrichment["llm_configured_weights_revision"] is None

    # FTS is built over the embedded (English) text, not the Korean original.
    fts_hit = con.execute("SELECT chunk_id FROM fts_chunks WHERE fts_chunks MATCH 'translation'").fetchall()
    assert len(fts_hit) == 1


def test_pipeline_without_llm_config_embeds_original_text_unchanged(con) -> None:
    embed_cfg = _embed_cfg()
    con.execute("BEGIN IMMEDIATE")
    space_id, profile_key = profiles.register_space_and_profile(con, embed_cfg, {"adapter": "plain_text"})
    con.commit()

    content = b"plain english content"
    r = _stage(con, space_id, profile_key, content)
    cfg = pipeline.PipelineConfig(embedding=embed_cfg, space_id=space_id, llm=None)

    with patch("airag.llm_enrichment.plan_semantic_groups") as mock_groups, \
         patch("airag.llm_enrichment.enrich_units") as mock_enrich, \
         patch("airag.embeddings.embed_documents") as mock_embed:
        mock_embed.return_value = [_fake_vector(4, 1.0)]
        result = pipeline.process_and_publish(
            con, job_id=r["job_id"], generation_id=r["generation_id"], claim_epoch=1,
            content=content, media_type="text/plain", source_key="faq.md", cfg=cfg,
        )

    mock_groups.assert_not_called()
    mock_enrich.assert_not_called()
    embedded_texts_passed = mock_embed.call_args[0][1]
    assert embedded_texts_passed == ["plain english content"]
    row = con.execute("SELECT text FROM chunks WHERE generation_id = ?", (result["generation_id"],)).fetchone()
    assert row[0] == "plain english content"


def test_pipeline_renews_lease_between_embedding_batches(con) -> None:
    embed_cfg = _embed_cfg()
    con.execute("BEGIN IMMEDIATE")
    space_id, profile_key = profiles.register_space_and_profile(con, embed_cfg, {"adapter": "plain_text"})
    con.commit()

    content = b"english content for lease renewal check"
    r = _stage(con, space_id, profile_key, content)
    cfg = pipeline.PipelineConfig(embedding=embed_cfg, space_id=space_id, llm=None)

    def _fake_embed_documents(_cfg, texts, *, on_batch=None):
        if on_batch is not None:
            on_batch(len(texts), len(texts))
        return [_fake_vector(4, 1.0) for _ in texts]

    with patch("airag.embeddings.embed_documents", side_effect=_fake_embed_documents), \
         patch("airag.store.renew_lease") as mock_renew:
        pipeline.process_and_publish(
            con, job_id=r["job_id"], generation_id=r["generation_id"], claim_epoch=1,
            content=content, media_type="text/plain", source_key="faq.md", cfg=cfg,
        )
    assert mock_renew.call_count >= 4
    for call in mock_renew.call_args_list:
        assert call.args == (con, r["job_id"], 1)
        assert call.kwargs["lease_ms"] >= store.DEFAULT_LEASE_MS


def test_pipeline_failure_fails_generation_not_partial_publish(con) -> None:
    embed_cfg = _embed_cfg()
    con.execute("BEGIN IMMEDIATE")
    space_id, profile_key = profiles.register_space_and_profile(con, embed_cfg, {"adapter": "plain_text"})
    con.commit()

    content = b"content that will fail during embedding"
    r = _stage(con, space_id, profile_key, content)
    cfg = pipeline.PipelineConfig(embedding=embed_cfg, space_id=space_id, llm=None)

    with patch("airag.embeddings.embed_documents", side_effect=embeddings.EmbeddingError("PROVIDER_UNREACHABLE", "boom", retryable=True)):
        with pytest.raises(embeddings.EmbeddingError):
            pipeline.process_and_publish(
                con, job_id=r["job_id"], generation_id=r["generation_id"], claim_epoch=1,
                content=content, media_type="text/plain", source_key="faq.md", cfg=cfg,
            )

    assert con.execute("SELECT status FROM generations WHERE generation_id = ?", (r["generation_id"],)).fetchone() == ("failed",)
    assert con.execute("SELECT status FROM jobs WHERE job_id = ?", (r["job_id"],)).fetchone() == ("failed",)
    assert con.execute("SELECT COUNT(*) FROM chunks WHERE generation_id = ?", (r["generation_id"],)).fetchone() == (0,)


def test_pipeline_empty_content_publishes_zero_chunks_honestly(con) -> None:
    embed_cfg = _embed_cfg()
    con.execute("BEGIN IMMEDIATE")
    space_id, profile_key = profiles.register_space_and_profile(con, embed_cfg, {"adapter": "plain_text"})
    con.commit()

    r = _stage(con, space_id, profile_key, b"")
    cfg = pipeline.PipelineConfig(embedding=embed_cfg, space_id=space_id, llm=None)

    with patch("airag.embeddings.embed_documents") as mock_embed:
        result = pipeline.process_and_publish(
            con, job_id=r["job_id"], generation_id=r["generation_id"], claim_epoch=1,
            content=b"", media_type="text/plain", source_key="faq.md", cfg=cfg,
        )
    mock_embed.assert_not_called()
    assert result["chunk_count"] == 0
    assert result["searchable"] is False


@pytest.mark.parametrize("mismatch", ["input", "model", "llm", "job", "epoch"])
def test_pipeline_rejects_uncaptured_inputs_before_model_calls_without_failing_owner(con, mismatch) -> None:
    from dataclasses import replace

    content = b"the authoritative input"
    con.execute("BEGIN IMMEDIATE")
    space, profile = profiles.register_space_and_profile(con, _embed_cfg(), {})
    con.commit()
    staged = _stage(con, space, profile, content)
    cfg = pipeline.PipelineConfig.from_profile(con, profile)
    if mismatch == "model":
        cfg = replace(cfg, embedding=replace(cfg.embedding, model="other-model"))
    if mismatch == "llm":
        cfg = replace(cfg, llm=_llm_cfg())
    with patch("airag.embeddings.embed_documents") as embed, patch("airag.llm_enrichment.enrich_units") as enrich:
        with pytest.raises((store.ApiError, ValueError)):
            pipeline.process_and_publish(
                con, job_id=staged["job_id"] + (1 if mismatch == "job" else 0),
                generation_id=staged["generation_id"], claim_epoch=2 if mismatch == "epoch" else 1,
                content=b"different bytes" if mismatch == "input" else content,
                media_type="text/plain", source_key="faq.md", cfg=cfg,
            )
    embed.assert_not_called()
    enrich.assert_not_called()
    assert con.execute("SELECT status FROM jobs WHERE job_id = ?", (staged["job_id"],)).fetchone() == ("running",)
    assert con.execute("SELECT COUNT(*) FROM chunks").fetchone() == (0,)


@pytest.mark.parametrize("long_translation", [False, True])
def test_semantic_groups_control_chunks_and_translation_splits_keep_original_anchors(con, long_translation) -> None:
    import json

    embed_cfg = _embed_cfg(max_tokens=16)
    con.execute("BEGIN IMMEDIATE")
    space, profile = profiles.register_space_and_profile(con, embed_cfg, {}, llm=_llm_cfg())
    con.commit()
    content = b"Alpha beta gamma delta epsilon zeta eta theta.\n\nOne two three four five six seven eight nine ten."
    staged = _stage(con, space, profile, content)
    seen_units = {}
    translation = "A unified semantic segment." * (20 if long_translation else 1)

    def group(_cfg, units):
        seen_units.update(units)
        return [llm_enrichment.SemanticGroup(list(units), "combined summary", ["combined"])], {"prompt_version": "group-v1"}

    def enrich(_cfg, groups, *, on_progress=None):
        assert callable(on_progress)
        on_progress()
        assert len(groups) == 1
        assert list(groups.values()) == ["\n\n".join(seen_units.values())]
        return [llm_enrichment.UnitEnrichment(next(iter(groups)), ["combined"], "summary", translation)], {"prompt_version": "enrich-v1"}

    with patch("airag.llm_enrichment.plan_semantic_groups", side_effect=group), \
         patch("airag.llm_enrichment.enrich_units", side_effect=enrich), \
         patch("airag.embeddings.embed_documents", side_effect=lambda _cfg, texts, **kw: [_fake_vector(4, 1) for _ in texts]):
        result = pipeline.process_and_publish(
            con, job_id=staged["job_id"], generation_id=staged["generation_id"], claim_epoch=1,
            content=content, media_type="text/plain", source_key="faq.md", cfg=pipeline.PipelineConfig.from_profile(con, profile),
        )
    assert len(seen_units) > 1
    assert result["chunk_count"] > 1 if long_translation else result["chunk_count"] == 1
    rows = con.execute("SELECT text, token_count, anchor_json FROM chunks ORDER BY chunk_index").fetchall()
    for text, count, anchor_json in rows:
        assert count <= 16
        artifact = json.loads(anchor_json)["llm_enrichment"]
        assert artifact["embedding_text"] == text
        assert artifact["translation_en"] == translation
        assert artifact["source_unit_ids"] == list(seen_units)
        assert artifact["provenance_granularity"] == "semantic_group"
        for unit in artifact["source_units"]:
            for item in unit["anchor"]["items"]:
                if item["granularity"] == "exact":
                    assert content.decode()[item["start"]:item["end"]] == item["matched_text"]


def test_reclaimed_attempt_cannot_fail_or_publish_its_replacement(con) -> None:
    con.execute("BEGIN IMMEDIATE")
    space, profile = profiles.register_space_and_profile(con, _embed_cfg(), {})
    con.commit()
    content = b"retained input"
    old = _stage(con, space, profile, content)
    con.execute("UPDATE jobs SET lease_expires_at_ms = 0 WHERE job_id = ?", (old["job_id"],))
    con.commit()
    replacement = store.reclaim_stale_job(con, old["job_id"])
    with patch("airag.embeddings.embed_documents") as embed:
        with pytest.raises(store.ApiError) as error:
            pipeline.process_and_publish(
                con, job_id=old["job_id"], generation_id=old["generation_id"], claim_epoch=1,
                content=content, media_type="text/plain", source_key="faq.md", cfg=pipeline.PipelineConfig.from_profile(con, profile),
            )
    assert error.value.code == "STALE_CLAIM_FENCED"
    embed.assert_not_called()
    assert con.execute("SELECT status FROM generations WHERE generation_id = ?", (replacement["generation_id"],)).fetchone() == ("staged",)
    assert con.execute("SELECT status FROM jobs WHERE job_id = ?", (old["job_id"],)).fetchone() == ("running",)


def test_long_source_respects_completion_budget_without_losing_original(con):
    from dataclasses import replace
    import json
    from airag import chunking

    embed_cfg = _embed_cfg()
    llm_cfg = replace(_llm_cfg(), max_tokens=1024, enrich_prompt_version="airag.llm_enrichment.enrich_units.v1")
    con.execute("BEGIN IMMEDIATE")
    space_id, profile_key = profiles.register_space_and_profile(con, embed_cfg, {"adapter": "plain_text"}, llm=llm_cfg)
    con.commit()
    source = "Start evidence. " + "A detailed source sentence remains available for retrieval. " * 180 + "Final evidence."
    content = source.encode()
    staged = _stage(con, space_id, profile_key, content)
    cfg = pipeline.PipelineConfig(embedding=embed_cfg, space_id=space_id, llm=llm_cfg)
    tokenizer = chunking.get_tokenizer(embed_cfg.tokenizer_model, embed_cfg.tokenizer_revision, embed_cfg.max_tokens)
    calls = []

    def groups(_cfg, units):
        return [llm_enrichment.SemanticGroup(list(units), "source", ["source"])], {}

    def enrich(_cfg, units, **kwargs):
        # Simulate translation expansion plus JSON/tags overhead at the provider.
        required = 256 + 2 * sum(tokenizer.count_tokens(text) for text in units.values())
        if required > _cfg.max_tokens:
            raise llm_enrichment.LLMError("INCOMPLETE_COMPLETION", "fixture output overflow", retryable=False)
        calls.append(required)
        return [llm_enrichment.UnitEnrichment(uid, ["source"], "source", text) for uid, text in units.items()], {}

    def embed(_cfg, texts, **kwargs):
        return [_fake_vector(4, 1.0) for _ in texts]

    with patch("airag.llm_enrichment.plan_semantic_groups", side_effect=groups), patch(
        "airag.llm_enrichment.enrich_units", side_effect=enrich
    ), patch("airag.embeddings.embed_documents", side_effect=embed):
        result = pipeline.process_and_publish(con, job_id=staged["job_id"], generation_id=staged["generation_id"],
            claim_epoch=1, content=content, media_type="text/plain", source_key="faq.md", cfg=cfg)
    assert result["status"] == "ready" and len(calls) > 1
    assert con.execute("SELECT content_bytes FROM source_revisions").fetchone()[0] == content
    anchors = [json.loads(row[0])["llm_enrichment"] for row in con.execute(
        "SELECT anchor_json FROM chunks WHERE generation_id=? ORDER BY chunk_id", (result["generation_id"],))]
    originals = " ".join(anchor["original_text"] for anchor in anchors)
    assert "Start evidence." in originals and "Final evidence." in originals
