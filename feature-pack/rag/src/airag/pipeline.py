"""Captured-profile ingestion with anchored semantic groups and atomic publication.

LLM groups determine the translated segments that are embedded. Token splits
of a translation retain group-level source provenance; translation offsets
are never presented as offsets in the original. All provider calls happen
outside write transactions, with claim checks between bounded operations.
"""

from __future__ import annotations

import math
import json
import sqlite3
import os
import time
from dataclasses import asdict, dataclass

from airag import chunking, embeddings, llm_enrichment, normalize, profiles, store, processing

_ENRICHMENT_KEY = "llm_enrichment"


@dataclass(frozen=True)
class PipelineConfig:
    embedding: embeddings.EmbeddingSpaceConfig
    space_id: int
    llm: llm_enrichment.ChatCompletionConfig | None = None
    normalizer: dict[str, object] | None = None

    @classmethod
    def from_profile(cls, con: sqlite3.Connection, profile_key: str) -> PipelineConfig:
        embedding, normalizer = profiles.config_from_profile(con, profile_key)
        row = con.execute("SELECT space_id FROM processing_profiles WHERE profile_key = ?", (profile_key,)).fetchone()
        return cls(embedding=embedding, space_id=row[0], llm=profiles.llm_from_profile(con, profile_key), normalizer=normalizer)


def _validate_attempt(con, job_id, generation_id, claim_epoch, content, media_type, source_key, cfg):
    if any(isinstance(value, bool) or not isinstance(value, int) or value <= 0 for value in (job_id, generation_id, claim_epoch)):
        raise ValueError("job_id, generation_id and claim_epoch must be positive integers")
    row = con.execute(
        "SELECT g.profile_key, g.owner_job_id, g.claim_epoch, g.status, j.claim_epoch, j.status, "
        "j.generation_id, r.content_bytes, r.media_type, s.source_key "
        "FROM generations g JOIN jobs j ON j.job_id = g.owner_job_id "
        "JOIN source_revisions r ON r.revision_id = g.revision_id "
        "JOIN sources s ON s.source_id = r.source_id WHERE g.generation_id = ?", (generation_id,),
    ).fetchone()
    if row is None:
        raise store.ApiError("NOT_FOUND", "no claimed generation found", retryable=False)
    profile_key, owner, epoch, gen_status, job_epoch, job_status, job_generation, original, media, name = row
    if (owner, epoch, job_epoch, job_generation) != (job_id, claim_epoch, claim_epoch, generation_id):
        raise store.ApiError("STALE_CLAIM_FENCED", "job/generation claim does not match this attempt", retryable=False)
    if gen_status != "staged" or job_status != "running":
        raise store.ApiError("INVALID_JOB_STATE", "attempt is no longer running", retryable=False)
    if (content, media_type, source_key) != (original, media, name):
        raise store.ApiError("VALIDATION_ERROR", "input differs from the job's immutable source revision", retryable=False)
    captured = PipelineConfig.from_profile(con, profile_key)
    actual_embedding = profiles.embedding_for_llm(cfg.embedding, cfg.llm)
    if (actual_embedding, cfg.space_id, cfg.llm) != (captured.embedding, captured.space_id, captured.llm):
        raise store.ApiError("VALIDATION_ERROR", "pipeline configuration differs from the captured profile", retryable=False)
    if cfg.normalizer is not None and cfg.normalizer != captured.normalizer:
        raise store.ApiError("VALIDATION_ERROR", "normalizer differs from the captured profile", retryable=False)
    return captured


def _translated_rows(records, cfg, renew, *, concurrency=1, cache=None):
    rows = []
    artifacts = []
    output_chunker = chunking.build_hf_chunker(
        cfg.embedding.tokenizer_model, cfg.embedding.tokenizer_revision, cfg.embedding.max_tokens,
    )
    windows = [(start, {f"chunk-{r.index}": r.text for r in records[start:start + profiles.SEMANTIC_WINDOW_UNITS]})
               for start in range(0, len(records), profiles.SEMANTIC_WINDOW_UNITS)]
    computed = processing.run_windows(windows, cfg, renew, concurrency=concurrency, cache=cache)
    for start, (groups, enriched, group_meta, enrich_meta, metrics) in computed:
        window = records[start:start + profiles.SEMANTIC_WINDOW_UNITS]
        by_id = {f"chunk-{r.index}": r for r in window}
        enrich_by_id = {e.unit_id: e for e in enriched}
        for i, group in enumerate(groups):
            group_id = f"group-{start}-{i}"
            result = enrich_by_id[group_id]
            source_records = [by_id[uid] for uid in group.unit_ids]
            source_units = [
                {"unit_id": uid, "original_text": by_id[uid].raw_text,
                 "contextualized_text": by_id[uid].text, "anchor": by_id[uid].anchor}
                for uid in group.unit_ids
            ]
            artifact = {
                "group_id": group_id, "source_unit_ids": group.unit_ids, "source_units": source_units,
                "original_text": "\n\n".join(r.raw_text for r in source_records),
                "original_text_is_contiguous": (
                    len(source_records) == 1 and len(source_records[0].anchor["items"]) == 1
                    and source_records[0].anchor["items"][0].get("granularity") == "exact"
                    and source_records[0].anchor["items"][0].get("matched_text") == source_records[0].raw_text
                ),
                "tags": result.tags, "summary": result.summary, "translation_en": result.translation_en,
                "group_summary": group.group_summary, "group_tags": group.group_tags,
                "enrich_prompt_version": enrich_meta.get("prompt_version"),
                "group_prompt_version": group_meta.get("prompt_version"),
                "llm_configured_weights_revision": cfg.llm.weights_revision,
                "enrichment_metadata": enrich_meta, "grouping_metadata": group_meta,
                "execution_metrics": metrics,
            }
            artifacts.append(artifact)
            translated = normalize.build_document("text/plain", result.translation_en.encode("utf-8"), name=group_id)
            parts = chunking.chunk_document(translated, output_chunker)
            if not parts:
                raise ValueError("nonempty translation produced no embedding chunks")
            for part in parts:
                if len(source_records) == 1:
                    anchor = dict(source_records[0].anchor)
                else:
                    anchor = {
                        "headings": list(dict.fromkeys(h for r in source_records for h in r.anchor["headings"])),
                        "items": [item for r in source_records for item in r.anchor["items"]],
                    }
                anchor[_ENRICHMENT_KEY] = {
                    **artifact, "provenance_granularity": "semantic_group", "translation_part": part.index,
                    "translation_part_count": len(parts), "embedding_text": part.text,
                }
                rows.append({"text": part.text, "token_count": part.token_count, "anchor": anchor})
        renew()
    return rows, artifacts


def process_and_publish(
    con: sqlite3.Connection,
    *,
    job_id: int,
    generation_id: int,
    claim_epoch: int,
    content: bytes,
    media_type: str,
    source_key: str,
    cfg: PipelineConfig,
) -> dict[str, object]:
    # Reject an unrelated caller before the failure handler can mutate a job.
    cfg = _validate_attempt(con, job_id, generation_id, claim_epoch, content, media_type, source_key, cfg)
    timeout = max(cfg.embedding.timeout_s, 2 * cfg.llm.timeout_s if cfg.llm else 0, (cfg.normalizer or {}).get("timeout_s", 0))
    lease_ms = max(store.DEFAULT_LEASE_MS, math.ceil(timeout * 1000) + 30000)

    def renew():
        store.renew_lease(con, job_id, claim_epoch, lease_ms=lease_ms)

    try:
        renew()
        normalize_started = time.monotonic()
        nd = normalize.build_document(media_type, content, name=source_key, config=cfg.normalizer, vision=cfg.llm, heartbeat=renew)
        normalize_elapsed = time.monotonic() - normalize_started
        chunk_started = time.monotonic()
        unit_limit = cfg.embedding.max_tokens
        if cfg.llm is not None:
            # Reserve JSON/annotation overhead and translation expansion across
            # the whole semantic window, not just one source unit.
            available = cfg.llm.max_tokens - 256
            if available < 2 * profiles.SEMANTIC_WINDOW_UNITS:
                raise llm_enrichment.LLMError(
                    "OUTPUT_BUDGET_TOO_SMALL", "output budget cannot hold a semantic window", retryable=False,
                )
            output_safe_unit_limit = available // (2 * profiles.SEMANTIC_WINDOW_UNITS)
            unit_limit = min(unit_limit, profiles.SOURCE_UNIT_MAX_TOKENS, output_safe_unit_limit)
        chunker = chunking.build_hf_chunker(cfg.embedding.tokenizer_model, cfg.embedding.tokenizer_revision, unit_limit)
        records = chunking.chunk_document(nd, chunker)
        chunk_elapsed = time.monotonic() - chunk_started
        structured = normalize.export_structured(nd.doc)
        if nd.artifacts:
            structured["normalization"] = {"artifacts": nd.artifacts, "anchors": {ref: asdict(anchor) for ref, anchor in nd.anchors.items()}}
            if len(json.dumps(structured, ensure_ascii=False).encode("utf-8")) > cfg.normalizer["max_expanded_bytes"]:
                raise ValueError("normalized document exceeds the captured expansion bound")
        if cfg.llm is not None:
            concurrency = int(os.environ.get("AIRAG_LLM_CONCURRENCY", "1"))
            cache = processing.ResultCache(con, cfg) if os.environ.get("AIRAG_PROCESSING_CACHE", "1") == "1" else None
            compute_started = time.monotonic()
            chunk_rows, artifacts = _translated_rows(records, cfg, renew, concurrency=concurrency, cache=cache)
            compute_elapsed = time.monotonic() - compute_started
            structured[_ENRICHMENT_KEY] = {"profile": profiles.enrichment_descriptor(cfg.llm), "groups": artifacts,
                                         "execution": {"concurrency": concurrency, "elapsed_seconds": round(compute_elapsed, 6),
                                                       "persistent_cache_enabled": cache is not None and cache.enabled,
                                                       "normalize_seconds": round(normalize_elapsed, 6),
                                                       "source_chunk_seconds": round(chunk_elapsed, 6)}}
        else:
            chunk_rows = [{"text": r.text, "token_count": r.token_count, "anchor": r.anchor} for r in records]
        renew()
        embedding_started = time.monotonic()
        vectors = embeddings.embed_documents(
            cfg.embedding, [r["text"] for r in chunk_rows], on_batch=lambda _done, _total: renew(),
        ) if chunk_rows else []
        renew()
        if cfg.llm is not None:
            structured[_ENRICHMENT_KEY]["execution"]["embedding_seconds"] = round(time.monotonic()-embedding_started, 6)
        embeddings.ensure_vec_space_table(con, cfg.space_id, cfg.embedding.dimension)
        return store.publish_generation_with_content(
            con, generation_id, standard_md=normalize.export_standard_md(nd.doc), structured_json=structured,
            chunk_rows=chunk_rows, space_id=cfg.space_id, vectors=vectors,
            final_response_extra={"normalization": {
                "adapter": nd.artifacts.get("adapter"), "warnings": nd.artifacts.get("warnings", []),
                "resource_count": len(nd.artifacts.get("resources", [])),
                "text_origins": sorted({a.text_origin for a in nd.anchors.values()}),
            }} if nd.artifacts else None,
        )
    except Exception as exc:
        from airag.api import map_exception
        final_error = map_exception(exc)
        try:
            store.fail_generation(con, generation_id, str(exc)[:2000], final_error=final_error)
        except store.ApiError:
            pass  # Fenced or terminal attempts cannot change the replacement job.
        raise
