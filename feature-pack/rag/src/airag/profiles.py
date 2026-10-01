"""Processing profile identity/registration (design D-010, P-03-B scope).

A processing profile fingerprints normalization/chunker/tokenizer
configuration together with the embedding space it targets —
`generations.profile_key` (P-02) IS this fingerprint. Immutable once
created: the same config always resolves to the same profile_key
(get-or-create), never mutated in place.

`chunker_config` deliberately carries MORE than docling-core's own chunker
knobs: it also captures the tokenizer_model/tokenizer_revision/max_tokens
that govern chunk sizing (the SAME tokenizer embeddings.py reuses for
token-budget checks — chunking.py's own docstring: "a profile_key that
only records model_name would silently start producing different chunks
the moment the upstream tokenizer files change") AND the provider-facing
operational fields (endpoint/timeout_s/max_batch) that are NOT part of the
embedding space's D-001 identity but which a caller reloading this profile
still needs — p03-embedding-review.txt item 2: "profile reload must retain
the actual configured endpoint/bounds", never re-derived from whatever this
module's or embeddings.py's current code defaults happen to be today.
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import time
from dataclasses import asdict, replace

from airag import embeddings
from airag import llm_enrichment

ENRICHMENT_PIPELINE_VERSION = "semantic-groups-english-v1"
SOURCE_UNIT_MAX_TOKENS = 512
SEMANTIC_WINDOW_UNITS = 4


def enrichment_descriptor(cfg: llm_enrichment.ChatCompletionConfig) -> dict[str, object]:
    llm_enrichment.validate_config(cfg)
    config = asdict(cfg)
    group_prompt_version = config.pop("group_prompt_version")
    enrich_prompt_version = config.pop("enrich_prompt_version")
    return {
        "config": config,
        "pipeline_version": ENRICHMENT_PIPELINE_VERSION,
        "enrich_prompt_version": enrich_prompt_version,
        "group_prompt_version": group_prompt_version,
        "source_unit_max_tokens": SOURCE_UNIT_MAX_TOKENS,
        "semantic_window_units": SEMANTIC_WINDOW_UNITS,
    }


def embedding_for_llm(
    cfg: embeddings.EmbeddingSpaceConfig, llm: llm_enrichment.ChatCompletionConfig | None,
) -> embeddings.EmbeddingSpaceConfig:
    if llm is None:
        if cfg.enrichment_fingerprint is not None:
            raise ValueError("an enriched embedding space requires its captured LLM configuration")
        return cfg
    descriptor = enrichment_descriptor(llm)
    identity = dict(descriptor["config"])
    for field in ("endpoint", "timeout_s"):
        identity.pop(field)
    descriptor["config"] = identity
    fingerprint = hashlib.sha256(json.dumps(descriptor, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if cfg.enrichment_fingerprint not in (None, fingerprint):
        raise ValueError("LLM configuration does not match the embedding space preprocessing")
    return replace(cfg, enrichment_fingerprint=fingerprint)


def chunker_config_dict(cfg: embeddings.EmbeddingSpaceConfig, *, chunker: str = "hybrid") -> dict[str, object]:
    """The canonical chunker_config shape stored on a processing_profiles
    row — built from an EmbeddingSpaceConfig so the tokenizer/operational
    fields it captures are guaranteed consistent with the space the
    profile targets, never hand-typed separately and allowed to drift."""
    return {
        "chunker": chunker,
        "tokenizer_model": cfg.tokenizer_model,
        "tokenizer_revision": cfg.tokenizer_revision,
        "max_tokens": cfg.max_tokens,
        "provider_endpoint": cfg.endpoint,
        "provider_timeout_s": cfg.timeout_s,
        "provider_max_batch": cfg.max_batch,
    }


def fingerprint_profile(space_id: int, normalizer_config: dict[str, object], chunker_config: dict[str, object]) -> str:
    canonical = json.dumps(
        {"space_id": space_id, "normalizer_config": normalizer_config, "chunker_config": chunker_config},
        sort_keys=True, separators=(",", ":"), ensure_ascii=True,
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def register_profile(
    con: sqlite3.Connection, space_id: int, normalizer_config: dict[str, object], chunker_config: dict[str, object]
) -> str:
    """Get-or-create by fingerprint. Caller must already hold the write
    lock (BEGIN IMMEDIATE) — profile_key is the table's PRIMARY KEY, so a
    genuine race would otherwise surface as an IntegrityError rather than
    a clean idempotent return, same convention as embeddings.register_space."""
    profile_key = fingerprint_profile(space_id, normalizer_config, chunker_config)
    row = con.execute(
        "SELECT profile_key FROM processing_profiles WHERE profile_key = ?", (profile_key,)
    ).fetchone()
    if row is not None:
        return profile_key
    now_ms = int(time.time() * 1000)
    con.execute(
        "INSERT INTO processing_profiles(profile_key, space_id, normalizer_config, chunker_config, created_at_ms) "
        "VALUES (?, ?, ?, ?, ?)",
        (
            profile_key, space_id,
            json.dumps(normalizer_config, sort_keys=True, ensure_ascii=True),
            json.dumps(chunker_config, sort_keys=True, ensure_ascii=True),
            now_ms,
        ),
    )
    return profile_key


def register_space_and_profile(
    con: sqlite3.Connection, cfg: embeddings.EmbeddingSpaceConfig, normalizer_config: dict[str, object],
    *, chunker: str = "hybrid", llm: llm_enrichment.ChatCompletionConfig | None = None,
) -> tuple[int, str]:
    """Convenience: register the embedding space and its owning profile
    together (the common case — a caller configuring a provider almost
    always wants both at once). Returns (space_id, profile_key). Caller
    must already hold the write lock."""
    if normalizer_config.get("adapter") == "documents_v1":
        from airag.document_adapters import canonical_config
        normalizer_config = canonical_config(normalizer_config)
    cfg = embedding_for_llm(cfg, llm)
    space_id = embeddings.register_space(con, cfg)
    chunker_config = chunker_config_dict(cfg, chunker=chunker)
    if llm is not None:
        chunker_config["llm_enrichment"] = enrichment_descriptor(llm)
    profile_key = register_profile(con, space_id, normalizer_config, chunker_config)
    return space_id, profile_key


def config_from_profile(
    con: sqlite3.Connection, profile_key: str, *, endpoint: str | None = None,
) -> tuple[embeddings.EmbeddingSpaceConfig, dict[str, object]]:
    """Reconstructs the EmbeddingSpaceConfig a profile was originally
    registered with, plus its normalizer_config, purely from durable
    storage — never from this module's or embeddings.py's current code
    defaults. `endpoint` may be overridden by the caller (e.g. a tunnel
    local port changed since registration) — operational, not identity,
    so this does not change the profile_key or the space's fingerprint."""
    row = con.execute(
        "SELECT space_id, normalizer_config, chunker_config FROM processing_profiles WHERE profile_key = ?",
        (profile_key,),
    ).fetchone()
    if row is None:
        raise ValueError(f"processing profile {profile_key!r} not found")
    space_id, normalizer_config_json, chunker_config_json = row
    chunker_config = json.loads(chunker_config_json)
    cfg = embeddings.config_from_space_row(
        con, space_id,
        endpoint=endpoint if endpoint is not None else chunker_config["provider_endpoint"],
        tokenizer_model=chunker_config["tokenizer_model"],
        tokenizer_revision=chunker_config["tokenizer_revision"],
        max_tokens=chunker_config["max_tokens"],
        timeout_s=chunker_config["provider_timeout_s"],
        max_batch=chunker_config["provider_max_batch"],
    )
    return cfg, json.loads(normalizer_config_json)


def llm_from_profile(con: sqlite3.Connection, profile_key: str) -> llm_enrichment.ChatCompletionConfig | None:
    row = con.execute("SELECT chunker_config FROM processing_profiles WHERE profile_key = ?", (profile_key,)).fetchone()
    if row is None:
        raise ValueError(f"processing profile {profile_key!r} not found")
    descriptor = json.loads(row[0]).get("llm_enrichment")
    if descriptor is None:
        return None
    cfg = llm_enrichment.ChatCompletionConfig(
        **descriptor["config"], group_prompt_version=descriptor["group_prompt_version"],
        enrich_prompt_version=descriptor["enrich_prompt_version"],
    )
    if descriptor != enrichment_descriptor(cfg):
        raise ValueError("captured enrichment pipeline/prompt version is not supported by this build")
    return cfg
