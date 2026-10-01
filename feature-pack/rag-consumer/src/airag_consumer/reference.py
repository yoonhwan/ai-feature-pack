"""Readonly existing-tour reference search through encrypted snapshots."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
from dataclasses import replace
from pathlib import Path

from airag import backups, embeddings, llm_enrichment, profiles
from airag import search as core_search
from airag.db import connect

from .lifecycle import AuthenticatedScope


ALLOWED_TOUR_SOURCES = (
    ("tour-text", "library-ko.txt"),
    ("tour-text", "library-en.txt"),
    ("tour-text", "refund-policy.md"),
    ("tour-text", "refund-evidence.md"),
    ("tour-text", "refund-support.md"),
    ("tour-text", "conversation.json"),
    ("tour-text", "empty.txt"),
    ("tour-pdf", "sample-pdf"),
    ("tour-docx", "sample-docx"),
    ("tour-xlsx", "sample-xlsx"),
    ("tour-hwp", "sample-hwp"),
    ("tour-hwpx", "sample-hwpx"),
    ("tour-hwpx_text", "sample-hwpx_text"),
    ("tour-mixed_pdf", "sample-mixed_pdf"),
    ("tour-ocr", "sample-ocr"),
    ("tour-vision", "sample-vision"),
    ("tour-text", "long.txt"),
)
_PROFILE_KEY = re.compile(r"[0-9a-f]{64}\Z")


class ReferenceSearchError(ValueError):
    """A fail-closed reference snapshot, routing, or consistency error."""


def _require_text(name: str, value: object) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        raise ReferenceSearchError(f"INVALID_{name.upper()}")
    return value


def _validate_key(name: str, value: object) -> bytes:
    if not isinstance(value, bytes) or len(value) != 32:
        raise ReferenceSearchError(f"INVALID_{name.upper()}")
    return value


def _digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def _safe_paths(source_path: str | Path, snapshot_path: str | Path) -> tuple[Path, Path]:
    source = Path(source_path).absolute()
    snapshot = Path(snapshot_path).absolute()
    if source == snapshot or source.is_symlink() or snapshot.is_symlink():
        raise ReferenceSearchError("INVALID_REFERENCE_PATH")
    if not source.is_file() or not snapshot.parent.is_dir():
        raise ReferenceSearchError("INVALID_REFERENCE_PATH")
    for path in (source, snapshot.parent):
        for part in (path, *path.parents):
            if part.is_symlink():
                raise ReferenceSearchError("SYMLINK_REFERENCE_PATH_REJECTED")
    if os.path.lexists(snapshot):
        raise ReferenceSearchError("SNAPSHOT_PATH_EXISTS")
    return source, snapshot


def _capture_state(con: sqlite3.Connection) -> dict[tuple[str, str], dict[str, object] | None]:
    state = {}
    for collection, source_key in ALLOWED_TOUR_SOURCES:
        row = con.execute(
            """SELECT s.source_id,s.state_version,s.head_revision_id,
                      s.ready_generation_id,s.deleted_at_ms,r.content_hash,r.media_type,
                      g.revision_id,g.profile_key,g.status,p.space_id
               FROM collections c JOIN sources s ON s.collection_id=c.collection_id
               LEFT JOIN source_revisions r ON r.revision_id=s.head_revision_id
               LEFT JOIN generations g ON g.generation_id=s.ready_generation_id
               LEFT JOIN processing_profiles p ON p.profile_key=g.profile_key
               WHERE c.name=? AND s.source_key=?""",
            (collection, source_key),
        ).fetchone()
        state[(collection, source_key)] = None if row is None else {
            "source_id": row[0], "state_version": row[1],
            "head_revision_id": row[2], "ready_generation_id": row[3],
            "deleted": row[4] is not None, "content_hash": row[5],
            "media_type": row[6], "ready_revision_id": row[7],
            "profile_key": row[8], "generation_status": row[9],
            "space_id": row[10],
        }
    return state


def _readonly_state(path: Path, key: bytes) -> dict[tuple[str, str], dict[str, object] | None]:
    con = connect.open_readonly(path, key)
    try:
        con.execute("BEGIN")
        return _capture_state(con)
    finally:
        con.close()


def _searchable_groups(
    state: dict[tuple[str, str], dict[str, object] | None],
) -> list[dict[str, object]]:
    grouped: dict[tuple[str, int], list[tuple[str, dict[str, object]]]] = {}
    for (collection, source_key), item in state.items():
        if (
            item is None or item["deleted"] is True
            or item["head_revision_id"] is None
            or item["head_revision_id"] != item["ready_revision_id"]
            or item["generation_status"] != "ready"
            or not isinstance(item["space_id"], int)
            or not isinstance(item["profile_key"], str)
            or _PROFILE_KEY.fullmatch(item["profile_key"]) is None
        ):
            continue
        grouped.setdefault((collection, item["space_id"]), []).append((source_key, item))
    result = []
    for (collection, space_id), members in sorted(grouped.items()):
        profiles_for_space = sorted({item["profile_key"] for _, item in members})
        result.append({
            "collection": collection, "space_id": space_id,
            "source_keys": sorted(source_key for source_key, _ in members),
            "profile_key": profiles_for_space[0],
            "compatible_profile_keys": profiles_for_space,
            "source_receipts": [
                {
                    "source_key": source_key, "source_id": item["source_id"],
                    "revision_id": item["ready_revision_id"],
                    "generation_id": item["ready_generation_id"],
                    "profile_key": item["profile_key"],
                    "content_hash": item["content_hash"],
                }
                for source_key, item in sorted(members)
            ],
        })
    return result


def _llm_identity(descriptor: dict[str, object]) -> dict[str, object]:
    value = json.loads(json.dumps(descriptor))
    config = value.get("config")
    if isinstance(config, dict):
        config.pop("endpoint", None)
    return value


def _route_profile(
    con: sqlite3.Connection,
    profile_key: str,
    space_id: int,
    *,
    embedding_endpoint_override: str | None,
    llm_endpoint_override: str | None,
) -> tuple[embeddings.EmbeddingSpaceConfig, llm_enrichment.ChatCompletionConfig | None, dict[str, object]]:
    captured_embedding, _normalizer = profiles.config_from_profile(con, profile_key)
    row = con.execute(
        "SELECT space_id FROM processing_profiles WHERE profile_key=?", (profile_key,),
    ).fetchone()
    if row != (space_id,):
        raise ReferenceSearchError("REFERENCE_PROFILE_SPACE_MISMATCH")
    routed_embedding = captured_embedding
    if embedding_endpoint_override is not None:
        _require_text("embedding_endpoint_override", embedding_endpoint_override)
        routed_embedding, _ = profiles.config_from_profile(
            con, profile_key, endpoint=embedding_endpoint_override,
        )
    if embeddings.fingerprint_space(routed_embedding) != embeddings.fingerprint_space(captured_embedding):
        raise ReferenceSearchError("EMBEDDING_ROUTE_IDENTITY_MISMATCH")

    captured_llm = profiles.llm_from_profile(con, profile_key)
    routed_llm = captured_llm
    if llm_endpoint_override is not None:
        _require_text("llm_endpoint_override", llm_endpoint_override)
        if captured_llm is None:
            raise ReferenceSearchError("LLM_ROUTE_WITHOUT_CAPTURED_LLM")
        routed_llm = replace(captured_llm, endpoint=llm_endpoint_override)
        if _llm_identity(profiles.enrichment_descriptor(routed_llm)) != _llm_identity(
            profiles.enrichment_descriptor(captured_llm)
        ):
            raise ReferenceSearchError("LLM_ROUTE_IDENTITY_MISMATCH")

    return routed_embedding, routed_llm, {
        "embedding": {
            "overridden": embedding_endpoint_override is not None,
            "captured_endpoint": captured_embedding.endpoint,
            "routed_endpoint": routed_embedding.endpoint,
            "space_fingerprint": embeddings.fingerprint_space(captured_embedding),
        },
        "llm": None if captured_llm is None else {
            "overridden": llm_endpoint_override is not None,
            "captured_endpoint": captured_llm.endpoint,
            "routed_endpoint": routed_llm.endpoint,
            "model": captured_llm.model,
            "weights_revision": captured_llm.weights_revision,
        },
    }


def _search_group(
    con: sqlite3.Connection,
    group: dict[str, object],
    query: str,
    top_k: int,
    *,
    embedding_endpoint_override: str | None,
    llm_endpoint_override: str | None,
) -> dict[str, object]:
    profile_key = group["profile_key"]
    embedding, llm, routing = _route_profile(
        con, profile_key, group["space_id"],
        embedding_endpoint_override=embedding_endpoint_override,
        llm_endpoint_override=llm_endpoint_override,
    )
    search_text = query
    query_provenance: dict[str, object] = {
        "original_query": query, "translated": False, "reference_routing": routing,
    }
    if llm is not None:
        enriched, metadata = llm_enrichment.enrich_units(llm, {"query": query})
        if len(enriched) != 1 or enriched[0].unit_id != "query":
            raise ReferenceSearchError("LLM_QUERY_COVERAGE_MISMATCH")
        search_text = enriched[0].translation_en
        query_provenance.update({
            "translated": True, "translated_query": search_text,
            "metadata": metadata,
        })
    vector = embeddings.embed_query(embedding, search_text)
    result = core_search.search(
        con,
        core_search.SearchQuery(
            collection=group["collection"], original_query=query,
            search_query_text=search_text, query_vector=vector,
            space_id=group["space_id"], profile_key=profile_key,
            top_k=top_k, query_provenance=query_provenance,
            source_keys=tuple(group["source_keys"]),
        ),
    )
    if result["eligible"]["count"] != len(group["source_keys"]):
        raise ReferenceSearchError("REFERENCE_ELIGIBILITY_MISMATCH")
    return {
        "label": "existing_tour_reference",
        "collection": group["collection"], "space_id": group["space_id"],
        "profile_key": profile_key,
        "compatible_profile_keys": group["compatible_profile_keys"],
        "source_keys": group["source_keys"],
        "source_receipts": group["source_receipts"],
        "routing": routing,
        "query_provenance": result["query_provenance"],
        "ranking": result["ranking"],
        "eligible": result["eligible"],
        "score_scope": "within_this_collection_and_embedding_space_only",
        "transient_manifest": {
            "snapshot_only": True, "original_database_manifest": False,
            "manifest_id": result["manifest_id"],
        },
        "results": result["results"],
    }


def search_tour_reference(
    source_path: str | Path,
    source_key: bytes,
    snapshot_path: str | Path,
    snapshot_key: bytes,
    scope: AuthenticatedScope,
    *,
    query: str,
    top_k: int = 5,
    embedding_endpoint_override: str | None = None,
    llm_endpoint_override: str | None = None,
) -> dict[str, object]:
    """Search frozen tour sources in a writable encrypted snapshot.

    The verified snapshot is retained at the caller-owned path. This function
    never deletes a database and never writes a manifest to the original.
    """
    source_key = _validate_key("source_key", source_key)
    snapshot_key = _validate_key("snapshot_key", snapshot_key)
    if not isinstance(scope, AuthenticatedScope):
        raise ReferenceSearchError("AUTHENTICATED_SCOPE_REQUIRED")
    query = _require_text("query", query)
    if (
        isinstance(top_k, bool) or not isinstance(top_k, int)
        or not 1 <= top_k <= core_search.MAX_TOP_K
    ):
        raise ReferenceSearchError("INVALID_TOP_K")
    source, snapshot = _safe_paths(source_path, snapshot_path)
    source_digest_before = _digest(source)
    try:
        backup = backups.copy_database(
            source, snapshot, source_key,
            destination_key_bytes=snapshot_key,
        )
    except Exception as exc:
        code = getattr(exc, "code", "UNKNOWN")
        raise ReferenceSearchError(f"REFERENCE_SNAPSHOT_FAILED:{code}") from None

    original_state = _readonly_state(source, source_key)
    snapshot_con = connect.open_encrypted(snapshot, snapshot_key)
    try:
        snapshot_state = _capture_state(snapshot_con)
        if snapshot_state != original_state:
            raise ReferenceSearchError("REFERENCE_SNAPSHOT_STATE_MISMATCH")
        groups = [
            _search_group(
                snapshot_con, group, query, top_k,
                embedding_endpoint_override=embedding_endpoint_override,
                llm_endpoint_override=llm_endpoint_override,
            )
            for group in _searchable_groups(snapshot_state)
        ]
    finally:
        snapshot_con.close()

    current_state = _readonly_state(source, source_key)
    source_digest_after = _digest(source)
    if current_state != original_state:
        raise ReferenceSearchError("REFERENCE_SOURCE_CHANGED_DURING_QUERY")
    if source_digest_after != source_digest_before:
        raise ReferenceSearchError("REFERENCE_SOURCE_BYTES_CHANGED")
    return {
        "label": "existing_tour_reference",
        "scope": scope.to_dict(), "query": query,
        "allowed_source_pairs": [list(item) for item in ALLOWED_TOUR_SOURCES],
        "groups": groups,
        "ranking": {
            "global_merge": False,
            "reason": "collections and embedding spaces remain separately labelled",
        },
        "snapshot": {
            "path": str(snapshot), "encrypted": backup["encrypted"],
            "verified": backup["verified"], "retained": True,
            "cleanup_owner": "caller_with_database_deletion_approval",
        },
        "original": {
            "path": str(source), "readonly": True,
            "sha256_before": source_digest_before,
            "sha256_after": source_digest_after,
            "unchanged": True,
        },
    }
