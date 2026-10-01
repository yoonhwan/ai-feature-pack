"""Shared request/result envelope (design D-009, P-02 scope, p02-review1.txt
item 6): both the CLI and any direct Python caller go through THIS module,
not `airag.store` directly. `store.py`'s functions are lower-level
repository helpers that raise `store.ApiError` on validation/CAS/etc
failures; calling those alone is not "the completed standard API" — this
module owns the envelope contract (schema_version, request_id, ok, command,
data, error) AND the mapping from every recognized OPERATIONAL failure —
not just `store.ApiError` — to a structured {code, message, retryable}
error. `map_exception` is the single table both `run()` (for failures
inside a store.* call) and the CLI's top-level handler (for failures
before any store.* call even runs, such as opening the encrypted DB or
resolving the key) go through, so the exact same operational failure gets
the exact same code/retryable everywhere — not one mapping in api.py and a
different one duplicated in main.py (p02-review1.txt item 6 follow-up:
"공통 mapping도 API 경계 소유로").

`map_exception` returns None for anything it does not recognize as an
expected operational condition — that is a programmer bug, and it must
propagate (never silently turned into a clean-looking error envelope that
hides it).
"""

from __future__ import annotations

import sqlite3
import json
import time
import uuid
from collections.abc import Callable

import sqlcipher3

from airag import _fileio, store
from airag.db import connect

ENVELOPE_SCHEMA_VERSION = 1


def envelope(
    command: str,
    *,
    ok: bool,
    data: dict[str, object] | None = None,
    error: dict[str, object] | None = None,
    request_id: str | None = None,
) -> dict[str, object]:
    return {
        "schema_version": ENVELOPE_SCHEMA_VERSION,
        "request_id": request_id or str(uuid.uuid4()),
        "ok": ok,
        "command": command,
        "data": data or {},
        "error": error,
    }


def map_exception(exc: BaseException) -> dict[str, object] | None:
    if isinstance(exc, store.ApiError):
        return exc.to_dict()
    if isinstance(exc, connect.WrongKeyOrForeignDatabase):
        return {"code": "KEY_OR_DB_VERIFICATION_FAILED", "message": str(exc), "retryable": False}
    if isinstance(exc, connect.UnsupportedSchemaVersion):
        return {"code": "UNSUPPORTED_SCHEMA_VERSION", "message": str(exc), "retryable": False}
    if isinstance(exc, connect.DatabaseAlreadyExists):
        return {"code": "DATABASE_ALREADY_EXISTS", "message": str(exc), "retryable": False}
    if isinstance(exc, (sqlite3.OperationalError, sqlcipher3.OperationalError)):
        # sqlcipher3 raises its OWN OperationalError class, distinct from
        # (not a subclass of) stdlib sqlite3.OperationalError — every real
        # connection in this package goes through the sqlcipher3 driver, so
        # missing this class here let real lock-contention escape unmapped
        # (independently reproduced against a real encrypted DB). Not every
        # OperationalError is retryable, though: "database is locked"/"busy"
        # is a transient condition worth retrying; an unknown-table or SQL
        # syntax error under this name is a bug and must not be reported as
        # something a caller should just try again.
        msg = str(exc)
        is_busy = "locked" in msg.lower() or "busy" in msg.lower()
        return {
            "code": "DB_BUSY" if is_busy else "DB_OPERATIONAL_ERROR",
            "message": msg,
            "retryable": is_busy,
        }
    if isinstance(exc, (ValueError, TypeError)):
        # e.g. a truncated/invalid --key-fd value, a bad revision token
        # shape reaching lower code than store.decode_revision_token, or a
        # malformed argument value.
        return {"code": "VALIDATION_ERROR", "message": str(exc), "retryable": False}
    if isinstance(exc, OSError):
        return {"code": "IO_ERROR", "message": str(exc), "retryable": False}
    return None


def run(
    command: str, fn: Callable[[], dict[str, object]], *, request_id: str | None = None
) -> dict[str, object]:
    try:
        data = fn()
        return envelope(command, ok=True, data=data, request_id=request_id)
    except Exception as exc:
        mapped = map_exception(exc)
        if mapped is None:
            raise
        return envelope(command, ok=False, error=mapped, request_id=request_id)


def add(
    con: sqlite3.Connection,
    request_id: str,
    collection: str,
    source_key: str,
    content: bytes,
    *,
    media_type: str = "text/plain",
    origin_uri: str | None = None,
    profile_key: str | None = None,
) -> dict[str, object]:
    owner = uuid.uuid4().hex
    def execute():
        _validate_profile(con, profile_key)
        receipt = store.add(
            con, store.AddRequest(request_id, collection, source_key, content, media_type, origin_uri, profile_key),
            profile_key=profile_key, lease_owner=owner,
        )
        return _finish_ingestion(con, receipt, owner)
    return run(
        "add",
        execute,
        request_id=request_id,
    )


def update(
    con: sqlite3.Connection,
    request_id: str,
    collection: str,
    source_key: str,
    expected_revision: str,
    content: bytes,
    *,
    media_type: str = "text/plain",
    origin_uri: str | None = None,
    force_reprocess: bool = False,
    profile_key: str | None = None,
) -> dict[str, object]:
    owner = uuid.uuid4().hex
    def execute():
        _validate_profile(con, profile_key)
        receipt = store.update(
            con, store.UpdateRequest(
                request_id, collection, source_key, expected_revision, content,
                media_type, origin_uri, force_reprocess, profile_key,
            ), profile_key=profile_key, lease_owner=owner,
        )
        return _finish_ingestion(con, receipt, owner)
    return run(
        "update",
        execute,
        request_id=request_id,
    )


def _validate_profile(con, profile_key):
    if profile_key is not None:
        if not isinstance(profile_key, str) or not profile_key:
            raise ValueError("profile_key must be a nonempty string")
        from airag.pipeline import PipelineConfig
        PipelineConfig.from_profile(con, profile_key)


def _finish_ingestion(con, receipt, owner):
    if receipt.get("generation_id") is None:
        return receipt  # An immutable stored-only receipt stays stored-only.
    from airag import pipeline
    job_id = receipt["job_id"]
    row = con.execute(
        "SELECT status, generation_id, profile_key, final_response_json, lease_owner, lease_expires_at_ms, "
        "claim_epoch, error FROM jobs WHERE job_id = ?", (job_id,),
    ).fetchone()
    status, generation_id, profile_key, final_json, lease_owner, expires, epoch, error = row
    if final_json is not None:
        final = json.loads(final_json)
        if final.get("processing_status") == "failed":
            error = final["error"]
            raise store.ApiError(error["code"], error["message"], retryable=error["retryable"])
        return final
    if status == "failed":
        raise store.ApiError("PROCESSING_FAILED", error or "processing failed; submit a new reprocess request", retryable=False)
    if status != "running":
        raise store.ApiError("INVALID_JOB_STATE", "captured processing job is not running", retryable=False)
    if lease_owner != owner:
        if expires is None or expires > int(time.time() * 1000):
            raise store.ApiError("IN_PROGRESS", "this request is already being processed", retryable=True)
        reclaimed = store.reclaim_stale_job(con, job_id, lease_owner=owner)
        generation_id, epoch = reclaimed["generation_id"], reclaimed["claim_epoch"]
    source = con.execute(
        "SELECT r.content_bytes, r.media_type, s.source_key FROM jobs j "
        "JOIN source_revisions r ON r.revision_id = j.revision_id "
        "JOIN sources s ON s.source_id = r.source_id WHERE j.job_id = ?", (job_id,),
    ).fetchone()
    return pipeline.process_and_publish(
        con, job_id=job_id, generation_id=generation_id, claim_epoch=epoch,
        content=source[0], media_type=source[1], source_key=source[2],
        cfg=pipeline.PipelineConfig.from_profile(con, profile_key),
    )


def retry(con, request_id: str, job_id: int, *, profile_key: str | None = None):
    """P06-03: `manage retry` — process an existing pending input (no
    profile was configured at add/update time) or retry a job whose
    processing attempt failed. `request_id` is THIS retry command's own
    idempotency key (distinct from whatever request_id created `job_id`
    originally) — see store.retry's docstring for exactly which branch
    mutates the original job (pending: safe in place) versus creates a
    fresh one (failed: required, so the original request's own replay is
    never altered). The result always carries `target_job_id` (what the
    caller asked to retry), `executed_job_id` (the job actually
    processed/replayed — a NEW job for the 'failed' branch, the SAME job
    otherwise), and `profile_key`, on top of whatever `_finish_ingestion`
    returns (a live/replayed processing result or its immutable final
    response) — a caller with only a job_id can always tell which job
    actually ran."""
    owner = uuid.uuid4().hex
    def execute():
        _validate_profile(con, profile_key)
        receipt = store.retry(con, request_id, job_id, profile_key=profile_key, lease_owner=owner)
        result = _finish_ingestion(con, receipt, owner)
        return {
            **result, "target_job_id": job_id,
            "executed_job_id": receipt["job_id"], "profile_key": receipt["profile_key"],
        }
    return run("manage retry", execute, request_id=request_id)


def reindex(con, request_id: str, collection: str, source_key: str, expected_revision: str, *, profile_key: str):
    """P06-04: `manage reindex` — reprocess the source's current head
    revision under `profile_key` (same profile: a plain reprocess;
    different profile/space: a migration) without touching stored
    original bytes or metadata. See store.reindex's docstring for the
    CAS/idempotency/duplicate-guard contract. `profile_key` is required
    (D-011: no automatic model selection — unlike retry's failed-job
    branch, there is no "originally captured" profile to fall back to)."""
    owner = uuid.uuid4().hex
    def execute():
        if not isinstance(profile_key, str) or not profile_key:
            raise ValueError("profile_key is required for reindex")
        _validate_profile(con, profile_key)
        receipt = store.reindex(
            con, request_id, collection, source_key, expected_revision,
            profile_key=profile_key, lease_owner=owner,
        )
        result = _finish_ingestion(con, receipt, owner)
        return {**result, "profile_key": receipt["profile_key"]}
    return run("manage reindex", execute, request_id=request_id)


def register_profile(con, config: dict[str, object], *, request_id=None):
    def execute():
        from airag import embeddings, llm_enrichment, profiles
        if not isinstance(config, dict) or set(config) - {"embedding", "llm", "normalizer"} or not isinstance(config.get("embedding"), dict):
            raise ValueError("profile config supports embedding, llm, and normalizer fields")
        embedding = embeddings.EmbeddingSpaceConfig(**config["embedding"])
        llm = llm_enrichment.ChatCompletionConfig(**config["llm"]) if config.get("llm") is not None else None
        normalizer = config.get("normalizer", {})
        if not isinstance(normalizer, dict):
            raise ValueError("normalizer must be an object")
        con.execute("BEGIN IMMEDIATE")
        try:
            space, key = profiles.register_space_and_profile(con, embedding, normalizer, llm=llm)
            con.commit()
        except Exception:
            con.rollback()
            raise
        return {"profile_key": key, "space_id": space, "llm_enrichment": llm is not None}
    return run("manage profile", execute, request_id=request_id)


def search(con, collection: str, query: str, profile_key: str, *, top_k=10, request_id=None, source_keys=None, media_types=None, expansion_options=None):
    def execute():
        from airag import embeddings, llm_enrichment, pipeline, search as retrieval
        if not isinstance(query, str) or not query.strip():
            raise ValueError("query must be a nonempty string")
        if not isinstance(collection, str) or not collection.strip():
            raise ValueError("collection must be a nonempty string")
        if isinstance(top_k, bool) or not isinstance(top_k, int) or not 0 < top_k <= retrieval.MAX_TOP_K:
            raise ValueError(f"top_k must be a positive integer <= {retrieval.MAX_TOP_K}")
        retrieval.validate_scope(source_keys,media_types)
        options=_expansion_options(expansion_options) if expansion_options is not None else None
        _validate_profile(con, profile_key)
        cfg = pipeline.PipelineConfig.from_profile(con, profile_key)
        search_text = query
        provenance = {"original_query": query, "translated": False}
        if cfg.llm is not None:
            result, meta = llm_enrichment.enrich_units(cfg.llm, {"query": query})
            search_text = result[0].translation_en
            provenance = {"original_query": query, "translated_query": search_text, "translated": True, "metadata": meta}
        vector = embeddings.embed_query(cfg.embedding, search_text)
        return retrieval.search(con, retrieval.SearchQuery(
            collection=collection, original_query=query, search_query_text=search_text, query_vector=vector,
            space_id=cfg.space_id, profile_key=profile_key, top_k=top_k, query_provenance=provenance,
            source_keys=source_keys,media_types=media_types,
        ),expansion_options=options)
    return run("search", execute, request_id=request_id)


def _expansion_options(value):
    from airag.expansion import ExpansionOptions
    if value is None:value={}
    if isinstance(value,dict):value=ExpansionOptions(**value)
    if not isinstance(value,ExpansionOptions):raise ValueError('expansion options must be an object')
    value.validate()
    return value


def expand(con,manifest_id,*,options=None,seed_chunk_ids=None,request_id=None):
    def execute():
        from airag import expansion
        return expansion.expand(con,manifest_id,_expansion_options(options),seed_chunk_ids=seed_chunk_ids)
    return run('expand',execute,request_id=request_id)


def fetch_expansion(con,expansion_id,*,request_id=None):
    def execute():
        from airag import expansion
        return expansion.replay(con,expansion_id)
    return run('fetch expansion',execute,request_id=request_id)


def fetch_manifest(con, manifest_id: int, *, request_id=None):
    def execute():
        from airag.search import replay_manifest
        return replay_manifest(con, manifest_id)
    return run("fetch manifest", execute, request_id=request_id)


def fetch_artifact(con, collection: str, source_key: str, *, chunk_id=None, generation_id=None, request_id=None):
    command = "fetch chunk" if chunk_id is not None else "fetch source"
    def execute():
        if (chunk_id is None) == (generation_id is None):
            raise ValueError("select exactly one chunk_id or generation_id")
        selected = chunk_id if chunk_id is not None else generation_id
        if isinstance(selected, bool) or not isinstance(selected, int) or selected <= 0:
            raise ValueError("artifact identifier must be a positive integer")
        if chunk_id is not None:
            row = con.execute("SELECT generation_id FROM chunks WHERE chunk_id = ?", (chunk_id,)).fetchone()
            gen = row[0] if row else None
        else:
            gen = generation_id
        row = con.execute(
            "SELECT r.revision_id, r.content_hash, r.origin_uri, s.source_id FROM generations g "
            "JOIN source_revisions r ON r.revision_id = g.revision_id JOIN sources s ON s.source_id = r.source_id "
            "JOIN collections c ON c.collection_id = s.collection_id "
            "WHERE g.generation_id = ? AND s.source_key = ? AND c.name = ?", (gen, source_key, collection),
        ).fetchone()
        if row is None:
            raise store.ApiError("NOT_FOUND", "artifact does not belong to this source/collection", retryable=False)
        data = {"generation_id": gen, "revision_id": row[0], "content_hash": row[1], "origin_uri": row[2],
                "source_id": row[3], "source_key": source_key, "collection": collection, "historical": True}
        if chunk_id is not None:
            text, anchor = con.execute("SELECT text, anchor_json FROM chunks WHERE chunk_id = ?", (chunk_id,)).fetchone()
            data.update(chunk_id=chunk_id, embedded_text=text, anchor=json.loads(anchor))
        else:
            artifact = con.execute("SELECT standard_md, structured_json FROM normalized_documents WHERE generation_id = ?", (gen,)).fetchone()
            if artifact is None:
                raise store.ApiError("NOT_FOUND", "generation has no normalized artifact", retryable=False)
            data.update(standard_md=artifact[0], structured=json.loads(artifact[1]))
        return data
    return run(command, execute, request_id=request_id)


def delete(
    con: sqlite3.Connection,
    request_id: str,
    collection: str,
    source_key: str,
    expected_revision: str,
) -> dict[str, object]:
    return run(
        "delete",
        lambda: store.delete(con, store.DeleteRequest(request_id, collection, source_key, expected_revision)),
        request_id=request_id,
    )


def restore(
    con: sqlite3.Connection,
    request_id: str,
    collection: str,
    source_key: str,
    expected_revision: str,
) -> dict[str, object]:
    return run(
        "manage restore",
        lambda: store.restore(con, store.RestoreRequest(request_id, collection, source_key, expected_revision)),
        request_id=request_id,
    )


def status(
    con: sqlite3.Connection, collection: str | None = None, source_key: str | None = None, *, request_id: str | None = None
) -> dict[str, object]:
    if collection is None and source_key is None:
        return operational_status(con, request_id=request_id)
    return run(
        "manage status", lambda: store.get_status(con, collection, source_key), request_id=request_id
    )


def _diagnose(con, command: str, *, request_id: str | None = None, require_healthy: bool = True):
    from airag import diagnostics
    try:
        data = diagnostics.inspect_database(con)
    except Exception:
        return envelope(command, ok=False, request_id=request_id,
                        error={"code": "DIAGNOSTICS_FAILED", "message": "database diagnostics could not complete", "retryable": False})
    ok = not require_healthy or data["healthy"]
    return envelope(command, ok=ok, data=data, request_id=request_id,
                    error=None if ok else {"code": "DIAGNOSTICS_FAILED", "message": "database diagnostics found inconsistencies", "retryable": False})


def operational_status(con: sqlite3.Connection, *, request_id: str | None = None) -> dict[str, object]:
    return _diagnose(con, "manage status", request_id=request_id, require_healthy=False)


def verify(con: sqlite3.Connection, *, request_id: str | None = None) -> dict[str, object]:
    return _diagnose(con, "manage verify", request_id=request_id)


def doctor(con: sqlite3.Connection | None = None, *, request_id: str | None = None) -> dict[str, object]:
    from airag import diagnostics
    if con is not None:
        return _diagnose(con, "manage doctor", request_id=request_id)
    data = diagnostics.inspect_runtime()
    return envelope("manage doctor", ok=data["healthy"], data=data, request_id=request_id)


def backup_database(source_path, backup_path, key_bytes: bytes, *, destination_key_bytes: bytes | None = None,
                    request_id: str | None = None) -> dict[str, object]:
    from airag import backups
    return run("manage backup", lambda: backups.copy_database(
        source_path, backup_path, key_bytes, destination_key_bytes=destination_key_bytes), request_id=request_id)


def restore_backup(backup_path, destination_path, key_bytes: bytes, *, destination_key_bytes: bytes | None = None,
                   request_id: str | None = None) -> dict[str, object]:
    from airag import backups
    return run("manage restore-backup", lambda: backups.copy_database(
        backup_path, destination_path, key_bytes, destination_key_bytes=destination_key_bytes), request_id=request_id)


def list_(
    con: sqlite3.Connection,
    collection: str,
    *,
    include_deleted: bool = False,
    request_id: str | None = None,
) -> dict[str, object]:
    return run(
        "manage list",
        lambda: store.list_sources(con, collection, include_deleted=include_deleted),
        request_id=request_id,
    )


def show(
    con: sqlite3.Connection,
    collection: str,
    source_key: str,
    *,
    revision_id: int | None = None,
    request_id: str | None = None,
) -> dict[str, object]:
    return run(
        "manage show",
        lambda: store.fetch_original(con, collection, source_key, revision_id=revision_id, include_bytes=False),
        request_id=request_id,
    )


def fetch_original(
    con: sqlite3.Connection,
    collection: str,
    source_key: str,
    *,
    revision_id: int | None = None,
    include_bytes: bool = False,
    request_id: str | None = None,
) -> dict[str, object]:
    return run(
        "fetch original",
        lambda: store.fetch_original(
            con, collection, source_key, revision_id=revision_id, include_bytes=include_bytes
        ),
        request_id=request_id,
    )


# ------------------------------------------------------------------- batch
#
# A real, importable Python API — not a CLI-only code path
# (p02-cli-review.txt item 1: "Keep same public API batch behavior
# accessible to Python consumers rather than CLI-only implementation").
# Items are plain dicts, already parsed by the caller (the CLI reads
# --batch's file and json.loads's it; a direct Python caller can build the
# list itself) — this function owns per-item validation/typing/mutation,
# never the file I/O.

MAX_BATCH_ITEMS = 1000


def _validate_batch_item_shape(index: int, item: object) -> dict[str, object]:
    if not isinstance(item, dict):
        raise store.ApiError("VALIDATION_ERROR", f"item {index} is not an object", retryable=False)
    request_id = item.get("request_id")
    if not isinstance(request_id, str) or not request_id:
        raise store.ApiError("VALIDATION_ERROR", f"item {index}: request_id is required", retryable=False)
    collection = item.get("collection")
    if not isinstance(collection, str) or not collection:
        raise store.ApiError("VALIDATION_ERROR", f"item {index}: collection is required", retryable=False)
    source_key = item.get("source_key")
    if not isinstance(source_key, str) or not source_key:
        raise store.ApiError("VALIDATION_ERROR", f"item {index}: source_key is required", retryable=False)
    content_file = item.get("content_file")
    text = item.get("text")
    if content_file is not None and not isinstance(content_file, str):
        raise store.ApiError("VALIDATION_ERROR", f"item {index}: content_file must be a string path", retryable=False)
    if text is not None and not isinstance(text, str):
        # Strictly typed — a nested JSON object/number/bool here would
        # otherwise get silently stringified via Python's str() (repr
        # syntax, not JSON) rather than rejected (p02-cli-review.txt item 3).
        raise store.ApiError("VALIDATION_ERROR", f"item {index}: text must be a string", retryable=False)
    if (content_file is None) == (text is None):
        raise store.ApiError(
            "VALIDATION_ERROR", f"item {index}: exactly one of content_file/text is required", retryable=False
        )
    # media_type/origin_uri: left as given (possibly absent/None) here —
    # NOT defaulted to "text/plain" unconditionally. A batch item with
    # content_file must infer these the same way the single-item CLI path
    # does (guess from extension / the file's own URI), not silently force
    # text/plain onto a binary file and then fail UTF-8 validation
    # (independently reproduced: a .bin item with 0x00/0xff bytes and no
    # media_type failed here while an equivalent single --content-file call
    # correctly inferred application/octet-stream). Resolved in
    # _resolve_batch_item_content, which is the same inference the CLI's
    # single-item path uses.
    media_type = item.get("media_type")
    if media_type is not None and (not isinstance(media_type, str) or not media_type):
        raise store.ApiError("VALIDATION_ERROR", f"item {index}: media_type must be a non-empty string", retryable=False)
    origin_uri = item.get("origin_uri")
    if origin_uri is not None and not isinstance(origin_uri, str):
        raise store.ApiError("VALIDATION_ERROR", f"item {index}: origin_uri must be a string or None", retryable=False)
    profile_key = item.get("profile_key")
    if profile_key is not None and (not isinstance(profile_key, str) or not profile_key):
        raise store.ApiError("VALIDATION_ERROR", f"item {index}: profile_key must be a nonempty string", retryable=False)
    return {
        "request_id": request_id,
        "collection": collection,
        "source_key": source_key,
        "content_file": content_file,
        "text": text,
        "media_type": media_type,
        "origin_uri": origin_uri,
        "profile_key": profile_key,
    }


def _resolve_batch_item_content(index: int, fields: dict[str, object]) -> tuple[bytes, str, str | None]:
    """Returns (content, effective_media_type, effective_origin_uri) —
    identical inference rule to the CLI's single-item
    `_resolve_single_item_content`: explicit values win; otherwise a
    content_file infers media_type from its extension (never defaulting to
    text/plain) and origin_uri from its own file:// URI; text falls back to
    text/plain with no origin_uri."""
    explicit_media_type = fields["media_type"]
    explicit_origin_uri = fields["origin_uri"]
    if fields["text"] is not None:
        text_val = fields["text"]
        assert isinstance(text_val, str)
        media_type = explicit_media_type if isinstance(explicit_media_type, str) else "text/plain"
        origin_uri = explicit_origin_uri if isinstance(explicit_origin_uri, str) else None
        return text_val.encode("utf-8"), media_type, origin_uri

    content_file = fields["content_file"]
    assert isinstance(content_file, str)
    try:
        content = _fileio.read_bounded_regular_file(content_file, store.MAX_CONTENT_BYTES)
    except OSError as exc:
        raise store.ApiError(
            "IO_ERROR", f"item {index}: could not read content_file: {exc}", retryable=False
        ) from exc
    media_type = explicit_media_type if isinstance(explicit_media_type, str) else _fileio.guess_media_type(content_file)
    origin_uri = explicit_origin_uri if isinstance(explicit_origin_uri, str) else _fileio.default_origin_uri(content_file)
    return content, media_type, origin_uri


def _batch_item_error_with_id(
    index: int, request_id: str | None, code: str, message: str, *, retryable: bool = False
) -> dict[str, object]:
    # A FULL envelope per item (schema_version/request_id/ok/command/data/
    # error), not a stripped-down subset — request_id is preserved even for
    # items that failed before store execution (p02-cli-review.txt item 4),
    # so a caller can correlate a batch result item back to what it sent.
    env = envelope("item", ok=False, error={"code": code, "message": message, "retryable": retryable}, request_id=request_id)
    env["index"] = index
    return env


def _add_batch_item(con: sqlite3.Connection, index: int, item: object) -> dict[str, object]:
    request_id_for_errors = item.get("request_id") if isinstance(item, dict) else None
    request_id_for_errors = request_id_for_errors if isinstance(request_id_for_errors, str) else None
    try:
        fields = _validate_batch_item_shape(index, item)
        request_id = fields["request_id"]
        assert isinstance(request_id, str)
        content, media_type, origin_uri = _resolve_batch_item_content(index, fields)
        collection = fields["collection"]
        source_key = fields["source_key"]
        assert isinstance(collection, str) and isinstance(source_key, str)
        env = add(con, request_id, collection, source_key, content, media_type=media_type, origin_uri=origin_uri, profile_key=fields["profile_key"])
        env["index"] = index
        return env
    except store.ApiError as exc:
        return _batch_item_error_with_id(index, request_id_for_errors, exc.code, exc.message, retryable=exc.retryable)
    except Exception as exc:  # noqa: BLE001 - one bad item must not abort the batch
        mapped = map_exception(exc)
        if mapped is None:
            raise
        return _batch_item_error_with_id(
            index, request_id_for_errors, str(mapped.get("code", "INTERNAL_ERROR")),
            str(mapped.get("message", "")), retryable=bool(mapped.get("retryable", False)),
        )


def _update_batch_item(con: sqlite3.Connection, index: int, item: object) -> dict[str, object]:
    request_id_for_errors = item.get("request_id") if isinstance(item, dict) else None
    request_id_for_errors = request_id_for_errors if isinstance(request_id_for_errors, str) else None
    try:
        fields = _validate_batch_item_shape(index, item)
        assert isinstance(item, dict)
        expected_revision = item.get("expected_revision")
        if not isinstance(expected_revision, str) or not expected_revision:
            raise store.ApiError("VALIDATION_ERROR", f"item {index}: expected_revision is required", retryable=False)
        force_reprocess = item.get("force_reprocess", False)
        if not isinstance(force_reprocess, bool):
            raise store.ApiError("VALIDATION_ERROR", f"item {index}: force_reprocess must be a bool", retryable=False)
        request_id = fields["request_id"]
        assert isinstance(request_id, str)
        content, media_type, origin_uri = _resolve_batch_item_content(index, fields)
        collection = fields["collection"]
        source_key = fields["source_key"]
        assert isinstance(collection, str) and isinstance(source_key, str)
        env = update(
            con, request_id, collection, source_key, expected_revision, content,
            media_type=media_type, origin_uri=origin_uri, force_reprocess=force_reprocess, profile_key=fields["profile_key"],
        )
        env["index"] = index
        return env
    except store.ApiError as exc:
        return _batch_item_error_with_id(index, request_id_for_errors, exc.code, exc.message, retryable=exc.retryable)
    except Exception as exc:  # noqa: BLE001 - one bad item must not abort the batch
        mapped = map_exception(exc)
        if mapped is None:
            raise
        return _batch_item_error_with_id(
            index, request_id_for_errors, str(mapped.get("code", "INTERNAL_ERROR")),
            str(mapped.get("message", "")), retryable=bool(mapped.get("retryable", False)),
        )


def _run_batch(
    con: sqlite3.Connection,
    command: str,
    items: object,
    item_fn: Callable[[sqlite3.Connection, int, object], dict[str, object]],
    *,
    request_id: str | None = None,
) -> dict[str, object]:
    """The outer envelope's `ok` reflects only whether the batch itself was
    structurally valid and fully processed — each item's own ok/error is
    independent and nested (p02-cli-review.txt item 1/2: earlier items'
    results must never disappear because a later item, or the outer
    request, was malformed). `request_id` here is the caller's identifier
    for the BATCH CALL as a whole (distinct from each item's own
    request_id) and survives into the outer envelope."""
    if not isinstance(items, list):
        return envelope(
            command, ok=False, request_id=request_id,
            error={"code": "VALIDATION_ERROR", "message": "batch must be a JSON array", "retryable": False},
        )
    if len(items) > MAX_BATCH_ITEMS:
        return envelope(
            command, ok=False, request_id=request_id,
            error={"code": "PAYLOAD_TOO_LARGE", "message": f"batch has {len(items)} items, exceeds {MAX_BATCH_ITEMS}", "retryable": False},
        )
    results = [item_fn(con, idx, item) for idx, item in enumerate(items)]
    return envelope(command, ok=True, data={"items": results}, request_id=request_id)


def add_batch(con: sqlite3.Connection, items: object, *, request_id: str | None = None) -> dict[str, object]:
    return _run_batch(con, "add batch", items, _add_batch_item, request_id=request_id)


def update_batch(con: sqlite3.Connection, items: object, *, request_id: str | None = None) -> dict[str, object]:
    return _run_batch(con, "update batch", items, _update_batch_item, request_id=request_id)
