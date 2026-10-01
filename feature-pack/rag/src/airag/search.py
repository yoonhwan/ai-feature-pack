"""BM25 (FTS5) + cosine (vec0) hybrid search with deterministic RRF
fusion and immutable evidence manifests (D-010 requirements 7/8, P-03-B
scope; ownership per ft-airag-arch-astra's 2026-09-10 split: this worker
owns ONLY this file and its test — pipeline.py/profiles.py/embeddings.py/
LLM connection and api.py/CLI wiring are owned elsewhere and are NOT
touched here).

Network-free by design: this module never calls an embedding/LLM
provider. Every caller must have ALREADY computed the query embedding
(`SearchQuery.query_vector` — float32-packed bytes, the exact format
`embeddings.embed_query`/`_check_float32_safe` produce) and resolved any
query translation/provenance BEFORE calling `search()`. This keeps the
search CORE deterministic and testable without a live provider, and keeps
translation/provider concerns out of this module — `SearchQuery` carries
`original_query` (verbatim user input), `search_query_text` (the text
actually embedded and matched — may equal `original_query`, or may be an
English translation when the corpus is English-embedded per D-011), and
`query_provenance` (a caller-supplied dict describing how/whether that
translation happened — this module records it verbatim in the manifest,
never interprets or validates its shape beyond requiring it be a dict).

Read-snapshot discipline (dispatch item 8): `search()` opens one read
transaction, resolves the eligible source/generation set, runs both
retrievers, and closes that transaction BEFORE writing the manifest in a
SEPARATE write transaction — never upgrading a stale read view into a
writer, and never leaving the manifest write racing the read it describes.

Eligibility (dispatch items 5/7): a source is eligible when it belongs to
the requested collection, is not deleted, and its `ready_generation_id`'s
processing profile targets the SAME `space_id` the query was embedded
against (D-001: never compare across embedding spaces, even same-
dimension ones). Both retrievers restrict candidates to the current ready,
non-deleted source generations before ranking limits. Publication and
delete/restore also update FTS/vector visibility atomically.

FTS injection safety (dispatch item 7): the query text is never
concatenated into SQL or handed to FTS5's MATCH mini-language raw. Each
whitespace-separated token is individually quoted (internal `"` doubled)
and OR-joined — this neutralizes every FTS5 operator (AND/OR/NOT/NEAR/
prefix-`*`/column-filter/parentheses) a user's text might otherwise be
parsed as, at the cost of proper Korean tokenization (word-level OR
matching only — real Korean morphological tokenization is explicitly
flagged as future work, not solved here, matching D-010 item 7's own
"choose/document Korean lexical behavior explicitly").
"""

from __future__ import annotations

import json
import hashlib
import math
import sqlite3
import struct
import time
from dataclasses import dataclass, field

from airag import store
from airag.db import vecext

DEFAULT_RRF_K = 60
DEFAULT_TOP_K = 10
MAX_TOP_K = 200


class SearchError(store.ApiError):
    """Same code/message/retryable contract as store.ApiError (root
    2026-09-10: EmbeddingError/LLMError get the same base, so api.py's
    map_exception can handle every module's operational errors through
    ONE existing store.ApiError branch — never a per-module import in the
    default CLI error path, which would reintroduce the exact tokenizer/
    docling import-chain regression already fixed once in store.py)."""


@dataclass(frozen=True)
class SearchQuery:
    collection: str
    original_query: str
    search_query_text: str
    query_vector: bytes
    space_id: int
    profile_key: str
    top_k: int = DEFAULT_TOP_K
    rrf_k: int = DEFAULT_RRF_K
    query_provenance: dict[str, object] = field(default_factory=dict)
    source_keys: tuple[str, ...] | None = None
    media_types: tuple[str, ...] | None = None

    def validate(self) -> None:
        for name in ("collection", "original_query", "search_query_text", "profile_key"):
            value = getattr(self, name)
            if not isinstance(value, str) or not value.strip():
                raise SearchError("VALIDATION_ERROR", f"{name} must be a non-empty string", retryable=False)
        if not isinstance(self.query_vector, bytes) or not self.query_vector:
            raise SearchError("VALIDATION_ERROR", "query_vector must be non-empty bytes", retryable=False)
        if isinstance(self.space_id, bool) or not isinstance(self.space_id, int) or self.space_id <= 0:
            raise SearchError("VALIDATION_ERROR", "space_id must be a positive int", retryable=False)
        if isinstance(self.top_k, bool) or not isinstance(self.top_k, int) or not (0 < self.top_k <= MAX_TOP_K):
            raise SearchError("VALIDATION_ERROR", f"top_k must be a positive int <= {MAX_TOP_K}", retryable=False)
        if isinstance(self.rrf_k, bool) or not isinstance(self.rrf_k, int) or self.rrf_k <= 0:
            raise SearchError("VALIDATION_ERROR", "rrf_k must be a positive int", retryable=False)
        if not isinstance(self.query_provenance, dict):
            raise SearchError("VALIDATION_ERROR", "query_provenance must be a dict", retryable=False)
        validate_scope(self.source_keys, self.media_types)


def validate_scope(source_keys=None, media_types=None):
    for value in (source_keys, media_types):
        if value is not None and (not isinstance(value,(list,tuple)) or not 1<=len(value)<=100 or any(not isinstance(x,str) or not x.strip() for x in value)):
            raise SearchError("VALIDATION_ERROR", "scope filters must be nonempty lists of at most 100 strings", retryable=False)
    return {'source_keys':sorted(set(source_keys)) if source_keys is not None else None,
            'media_types':sorted(set(media_types)) if media_types is not None else None}


def _escape_fts_query(text: str) -> str:
    """Quotes each whitespace-separated token individually (doubling any
    internal `"`) and OR-joins them — every FTS5 mini-language operator a
    user's raw text might otherwise be parsed as loses its special meaning
    inside a quoted phrase. Never interpolates `text` into SQL directly."""
    tokens = text.split()
    if not tokens:
        raise SearchError("VALIDATION_ERROR", "search_query_text has no non-whitespace tokens", retryable=False)
    return " OR ".join('"' + tok.replace('"', '""') + '"' for tok in tokens)


def _vec_space_table_name(space_id: int) -> str:
    # Duplicated (not imported) from embeddings.py deliberately — importing
    # airag.embeddings here would drag in chunking.py's docling_core/
    # transformers import chain into this network-free, otherwise-light
    # module, the exact regression already fixed once in store.py. This is
    # a one-line pure function; keeping it local costs nothing and avoids
    # re-introducing that cost for every caller of search().
    return f"vec_space_{int(space_id)}"


def _validate_profile_matches_space(con: sqlite3.Connection, profile_key: str, space_id: int) -> None:
    """Owner review 2026-09-10: profile_key/space_id must be cross-
    validated INSIDE the read snapshot, not merely recorded — a caller
    passing a profile_key that does not actually target the declared
    space_id would otherwise silently attribute a search to the wrong
    profile in the manifest."""
    row = con.execute(
        "SELECT space_id FROM processing_profiles WHERE profile_key = ?", (profile_key,)
    ).fetchone()
    if row is None:
        raise SearchError("NOT_FOUND", f"processing profile {profile_key!r} not found", retryable=False)
    if row[0] != space_id:
        raise SearchError(
            "VALIDATION_ERROR",
            f"profile_key {profile_key!r} targets space {row[0]}, not the declared space_id {space_id}",
            retryable=False,
        )


def _validate_query_vector(con: sqlite3.Connection, space_id: int, query_vector: bytes) -> None:
    """Owner review 2026-09-10: validate the query vector's byte length
    against the space's declared dimension, and that it unpacks to finite,
    non-all-zero float32 values — the same class of check embeddings.py
    applies to a provider's response, applied here to a caller-supplied
    query vector (this module never computes one itself)."""
    row = con.execute("SELECT dimension FROM embedding_spaces WHERE space_id = ?", (space_id,)).fetchone()
    if row is None:
        raise SearchError("NOT_FOUND", f"embedding space {space_id} not found", retryable=False)
    dimension = row[0]
    expected_len = dimension * 4
    if len(query_vector) != expected_len:
        raise SearchError(
            "DIMENSION_MISMATCH",
            f"query_vector is {len(query_vector)} bytes, expected {expected_len} for a {dimension}-dim float32 space",
            retryable=False,
        )
    values = struct.unpack(f"{dimension}f", query_vector)
    if not all(math.isfinite(v) for v in values):
        raise SearchError("NON_FINITE_VECTOR", "query_vector contains a non-finite value", retryable=False)
    if all(v == 0.0 for v in values):
        raise SearchError("ZERO_VECTOR", "query_vector is an all-zero vector", retryable=False)


@dataclass(frozen=True)
class _EligibleSource:
    source_id: int
    generation_id: int
    revision_id: int
    state_version: int
    graph_version: int | None


def _resolve_eligible_sources(con: sqlite3.Connection, collection: str, space_id: int, *, source_keys=None, media_types=None) -> list[_EligibleSource]:
    scope=validate_scope(source_keys,media_types)
    extra='';params=[collection,space_id]
    for column,values in (('s.source_key',scope['source_keys']),('r.media_type',scope['media_types'])):
        if values is not None:
            extra+=' AND '+column+' IN ('+','.join('?' for _ in values)+')';params.extend(values)
    rows = con.execute(
        "SELECT s.source_id, s.ready_generation_id, g.revision_id, s.state_version, gg.version "
        "FROM sources s "
        "JOIN collections c ON s.collection_id = c.collection_id "
        "JOIN generations g ON s.ready_generation_id = g.generation_id "
        "JOIN processing_profiles pp ON g.profile_key = pp.profile_key "
        "JOIN source_revisions r ON g.revision_id = r.revision_id "
        "LEFT JOIN generation_graphs gg ON gg.generation_id=g.generation_id "
        "WHERE c.name = ? AND pp.space_id=? AND s.deleted_at_ms IS NULL AND s.ready_generation_id IS NOT NULL AND g.status = 'ready'"+extra,
        params,
    ).fetchall()
    return [
        _EligibleSource(source_id=r[0], generation_id=r[1], revision_id=r[2], state_version=r[3], graph_version=r[4])
        for r in rows
    ]


def snapshot_state(eligible, collection, space_id, scope):
    sources=sorted(({'source_id':e.source_id,'revision_id':e.revision_id,'generation_id':e.generation_id,
                     'state_version':e.state_version,'graph_version':e.graph_version} for e in eligible),key=lambda x:x['source_id'])
    value={'version':1,'collection':collection,'space_id':space_id,'scope':scope,'sources':sources}
    value['fingerprint']=hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    return value


def _bm25_candidates(
    con: sqlite3.Connection, collection: str, query: SearchQuery, limit: int, eligible_generation_ids: list[int]
) -> list[tuple[int, float]]:
    """`collection_id` alone is NOT sufficient scoping — FTS5 has no
    concept of embedding space, so a collection holding content indexed
    under multiple spaces (e.g. mid-migration) would otherwise leak a
    different-space document into BM25 results even though the query's
    vector could never legitimately be compared against it (D-001).
    Explicitly restrict to the SAME eligible (space-matching, non-deleted)
    generation set `_resolve_eligible_sources` already computed."""
    if not eligible_generation_ids:
        return []
    row = con.execute("SELECT collection_id FROM collections WHERE name = ?", (collection,)).fetchone()
    if row is None:
        return []
    collection_id = row[0]
    fts_query = _escape_fts_query(query.search_query_text)
    placeholders = ",".join("?" for _ in eligible_generation_ids)
    rows = con.execute(
        "SELECT fc.chunk_id, bm25(fts_chunks) FROM fts_chunks fc JOIN chunks c ON fc.chunk_id = c.chunk_id "
        f"WHERE fts_chunks MATCH ? AND fc.collection_id = ? AND c.generation_id IN ({placeholders}) "
        # Deterministic secondary key BEFORE the LIMIT cut — SQLite gives no
        # stable order for exact bm25() ties otherwise, which could make
        # even which chunks ENTER the candidate pool nondeterministic
        # across runs, not just their final rank (owner review 2026-09-10).
        "ORDER BY bm25(fts_chunks), fc.chunk_id LIMIT ?",
        (fts_query, collection_id, *eligible_generation_ids, limit),
    ).fetchall()
    # FTS5's bm25() is more-negative-is-better; sort ascending (already is,
    # via ORDER BY) and keep the raw score for the manifest — rank order,
    # not the raw score's sign, is what RRF actually consumes.
    return [(r[0], r[1]) for r in rows]


def _vec_candidates(con: sqlite3.Connection, collection: str, query: SearchQuery, limit: int) -> list[tuple[int, float]]:
    """Exact scalar-cosine fallback (D-010/P-03-B dispatch item 5,
    explicitly authorized: "exact scalar-cosine fallback over eligible
    rows is acceptable if a filter cannot be safely pushed down; never
    silent partial postfiltering"). vec0's own KNN `MATCH ... k = ?` path
    cannot combine same-space + current-ready-generation + non-deleted +
    collection filtering with a fully deterministic tie-break: vec0
    rejects any KNN query with more than its single mandatory `ORDER BY
    distance` clause (verified — "Only a single 'ORDER BY distance'
    clause is allowed on vec0 KNN queries"), so an exact-distance tie at
    the k-boundary is not resolvable via an outer ORDER BY there.

    This instead computes `vec_distance_cosine` as a plain SCALAR function
    over every row already relationally scoped — same embedding space
    (the table itself + `pp.space_id` belt-and-suspenders), source not
    deleted, source's CURRENT ready generation (never a superseded or
    stale-but-not-yet-republished one), and the target collection — all
    filtered BEFORE the ORDER BY/LIMIT, with `chunk_id` as an unrestricted
    secondary sort key for full determinism on an exact distance tie. This
    is an O(N) scan over the eligible rows in this space/collection, NOT
    an ANN index scan — acceptable per dispatch as the exact fallback;
    reintroducing an indexed KNN fast path later would not change this
    module's public contract."""
    table = _vec_space_table_name(query.space_id)
    exists = con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)).fetchone()
    if exists is None:
        return []
    scope=validate_scope(query.source_keys,query.media_types)
    extra='';params=[query.query_vector,collection,query.space_id]
    for column,values in (('s.source_key',scope['source_keys']),('rev.media_type',scope['media_types'])):
        if values is not None:
            extra+=' AND '+column+' IN ('+','.join('?' for _ in values)+')';params.extend(values)
    params.append(limit)
    rows = con.execute(
        f"SELECT v.chunk_id, vec_distance_cosine(v.embedding, ?) AS distance FROM {table} v "
        "JOIN chunks c ON v.chunk_id = c.chunk_id "
        "JOIN generations g ON c.generation_id = g.generation_id "
        "JOIN processing_profiles pp ON g.profile_key = pp.profile_key "
        "JOIN source_revisions rev ON g.revision_id = rev.revision_id "
        "JOIN sources s ON rev.source_id = s.source_id "
        "JOIN collections col ON s.collection_id = col.collection_id "
        "WHERE col.name = ? AND s.deleted_at_ms IS NULL AND s.ready_generation_id = g.generation_id "
        "AND g.status = 'ready' AND v.active = 1 AND pp.space_id = ?"+extra+" ORDER BY distance, v.chunk_id LIMIT ?",
        params,
    ).fetchall()
    return [(r[0], r[1]) for r in rows]


@dataclass(frozen=True)
class _FusedResult:
    chunk_id: int
    rrf_score: float
    bm25_rank: int | None
    bm25_score: float | None
    vec_rank: int | None
    vec_distance: float | None


def _rrf_fuse(bm25: list[tuple[int, float]], vec: list[tuple[int, float]], *, rrf_k: int) -> list[_FusedResult]:
    bm25_rank = {cid: i + 1 for i, (cid, _) in enumerate(bm25)}
    bm25_score = dict(bm25)
    vec_rank = {cid: i + 1 for i, (cid, _) in enumerate(vec)}
    vec_dist = dict(vec)
    all_ids = set(bm25_rank) | set(vec_rank)

    fused: list[_FusedResult] = []
    for cid in all_ids:
        score = 0.0
        if cid in bm25_rank:
            score += 1.0 / (rrf_k + bm25_rank[cid])
        if cid in vec_rank:
            score += 1.0 / (rrf_k + vec_rank[cid])
        fused.append(_FusedResult(
            chunk_id=cid, rrf_score=score,
            bm25_rank=bm25_rank.get(cid), bm25_score=bm25_score.get(cid),
            vec_rank=vec_rank.get(cid), vec_distance=vec_dist.get(cid),
        ))
    # Deterministic: score descending, chunk_id ascending on ties — a
    # stable, reproducible tie-breaker (dispatch item 7's "stable tie-
    # breakers"), never insertion order (a Python set has none anyway).
    fused.sort(key=lambda f: (-f.rrf_score, f.chunk_id))
    return fused


def _fetch_evidence(con: sqlite3.Connection, fused: list[_FusedResult]) -> list[dict[str, object]]:
    """Owner review 2026-09-10: evidence must carry enough to target the
    EXACT historic source (origin_uri/content_hash/source_key/collection),
    and must never claim `original_text` is a verbatim CONTIGUOUS excerpt
    when the pipeline's own `llm_enrichment` blob says otherwise — the
    pipeline may join several source units into one semantic-group
    translation, recording that honestly via `original_text_is_contiguous`
    and `provenance_granularity`. This function passes those flags through
    unchanged. Without enrichment, contextualized chunk text is only
    marked contiguous when it matches the recorded original anchor."""
    results: list[dict[str, object]] = []
    for f in fused:
        row = con.execute(
            "SELECT c.text, c.anchor_json, c.generation_id, g.revision_id, r.source_id, "
            "r.origin_uri, r.content_hash, s.source_key, col.name "
            "FROM chunks c JOIN generations g ON c.generation_id = g.generation_id "
            "JOIN source_revisions r ON g.revision_id = r.revision_id "
            "JOIN sources s ON r.source_id = s.source_id "
            "JOIN collections col ON s.collection_id = col.collection_id "
            "WHERE c.chunk_id = ?",
            (f.chunk_id,),
        ).fetchone()
        if row is None:
            continue  # defensive only — a chunk_id surfaced by a live index query must exist in chunks
        text, anchor_json, generation_id, revision_id, source_id, origin_uri, content_hash, source_key, collection_name = row
        anchor = json.loads(anchor_json) if anchor_json else {}
        enrichment = anchor.get("llm_enrichment") if isinstance(anchor, dict) else None
        has_enrichment = isinstance(enrichment, dict) and "original_text" in enrichment
        if has_enrichment:
            original_text = enrichment["original_text"]
            # Pipeline-declared honesty flags — passed through unchanged,
            # never re-derived or assumed here.
            is_contiguous = bool(enrichment.get("original_text_is_contiguous", False))
            granularity = enrichment.get("provenance_granularity", "unknown")
        else:
            # No llm_enrichment blob: `text` (chunks.text) is chunking.py's
            # own CONTEXTUALIZED text (heading context folded in per its
            # docstring) — NOT necessarily a verbatim contiguous original
            # span. Only claim contiguity when the anchor's OWN recorded
            # `matched_text` (the actual verbatim source substring
            # chunking.py located at anchor-construction time) equals
            # `text` exactly; otherwise report the anchor's own granularity
            # honestly rather than assuming "chunk"/contiguous (owner
            # review 2026-09-10).
            original_text = text
            items = anchor.get("items") if isinstance(anchor, dict) else None
            if isinstance(items, list) and len(items) == 1 and isinstance(items[0], dict) and items[0].get("matched_text") == text:
                is_contiguous = True
                granularity = items[0].get("granularity", "exact")
            elif isinstance(items, list) and len(items) == 1 and isinstance(items[0], dict):
                is_contiguous = False
                granularity = items[0].get("granularity", "unknown")
            else:
                is_contiguous = False
                granularity = "multi_item" if isinstance(items, list) and len(items) > 1 else "unknown"
        source_items = anchor.get("items", []) if isinstance(anchor, dict) else []
        source_origins = sorted({str(item.get("text_origin", "original")) for item in source_items if isinstance(item, dict)})
        results.append({
            "chunk_id": f.chunk_id,
            "source_id": source_id,
            "source_key": source_key,
            "collection": collection_name,
            "generation_id": generation_id,
            "revision_id": revision_id,
            "origin_uri": origin_uri,
            "content_hash": content_hash,
            "embedded_text": text,
            "original_text": original_text,
            "is_translated": has_enrichment and original_text != text,
            "original_text_is_contiguous": is_contiguous,
            "text_origins": source_origins,
            "contains_inference": "inferred" in source_origins,
            "provenance_granularity": granularity,
            "anchor": anchor,
            "rrf_score": f.rrf_score,
            "bm25_rank": f.bm25_rank,
            "bm25_score": f.bm25_score,
            "vec_rank": f.vec_rank,
            "vec_distance": f.vec_distance,
        })
    return results


def search(con: sqlite3.Connection, query: SearchQuery, *, expansion_options=None) -> dict[str, object]:
    """Executes one search inside a single read snapshot, then persists an
    IMMUTABLE evidence manifest in a separate write transaction after that
    snapshot closes. Returns the manifest's own data (including
    `manifest_id` for later `replay_manifest`)."""
    query.validate()
    scope=validate_scope(query.source_keys,query.media_types)
    counter=None
    if expansion_options is not None:
        from airag import expansion
        expansion_options.validate()
        counter=expansion.prepare_counter(con,query.profile_key)

    # A connection opened via connect.open_encrypted() (the normal CLI/API
    # path — a fresh process, not the same connection that created the
    # vec0 tables) does NOT have the sqlite_vec extension loaded by
    # default; loading it is a connection-local, best-effort operation
    # with no DDL side effect (owner review 2026-09-10, reproduced via a
    # real separate-process CLI E2E: "no such module: vec0"). Loading
    # happens BEFORE the read snapshot opens — it is not itself a write.
    if not vecext.try_load_vec0(con):
        raise SearchError(
            "VEC0_UNAVAILABLE", "sqlite_vec extension could not be loaded on this connection", retryable=False
        )

    con.execute("BEGIN")
    try:
        _validate_profile_matches_space(con, query.profile_key, query.space_id)
        _validate_query_vector(con, query.space_id, query.query_vector)
        eligible = _resolve_eligible_sources(con, query.collection, query.space_id, **scope)
        snapshot=snapshot_state(eligible,query.collection,query.space_id,scope)
        eligible_generation_ids = [e.generation_id for e in eligible]
        limit = min(query.top_k * 4, MAX_TOP_K * 4) or query.top_k  # widen the candidate pool before RRF/top_k cut
        bm25 = _bm25_candidates(con, query.collection, query, limit, eligible_generation_ids)
        vec = _vec_candidates(con, query.collection, query, limit)
        fused = _rrf_fuse(bm25, vec, rrf_k=query.rrf_k)[: query.top_k]
        results = _fetch_evidence(con, fused)
        collection_row=con.execute('SELECT collection_id FROM collections WHERE name=?',(query.collection,)).fetchone()
        if collection_row is None:
            raise SearchError('NOT_FOUND',f'collection {query.collection!r} not found',retryable=False)
        expansion_result=None
        if expansion_options is not None:
            expansion_result=expansion.expand_snapshot(con,results,snapshot,expansion_options,counter)
        con.rollback()  # read-only — nothing to commit
    except Exception:
        con.rollback()
        raise

    collection_id = collection_row[0]

    filters = {
        "space_id": query.space_id, "profile_key": query.profile_key,
        "search_query_text": query.search_query_text, "query_provenance": query.query_provenance,
        "top_k": query.top_k, "rrf_k": query.rrf_k, "candidate_limit": limit,
        # exact_cosine=True documents that _vec_candidates used the exact
        # scalar-cosine O(N) fallback (D-010 dispatch item 5), never vec0's
        # KNN path — a future indexed fast path would flip this.
        "exact_cosine": True,
        "scope": scope,
        "snapshot": snapshot,
        "expansion_requested": expansion_options is not None,
    }
    # Owner review 2026-09-10: preserve the (source_id, revision_id,
    # generation_id) TRIPLE per eligible source — three separately-sorted
    # ID lists lose that pairing, which P-05's snapshot-relationship work
    # needs (which generation belonged to which source/revision at search
    # time, not just three independent sets).
    eligible_sources = sorted(
        ({"source_id": e.source_id, "revision_id": e.revision_id, "generation_id": e.generation_id} for e in eligible),
        key=lambda d: d["source_id"],
    )
    eligible_summary = {"sources": eligible_sources, "count": len(eligible)}
    now_ms = int(time.time() * 1000)

    con.execute("BEGIN IMMEDIATE")
    try:
        cur = con.execute(
            "INSERT INTO search_manifests(collection_id, query_text, profile_key, space_id, filters_json, "
            "eligible_json, results_json, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                collection_id, query.original_query, query.profile_key, query.space_id,
                json.dumps(filters, ensure_ascii=False), json.dumps(eligible_summary, ensure_ascii=False),
                json.dumps(results, ensure_ascii=False), now_ms,
            ),
        )
        assert cur.lastrowid is not None
        manifest_id = cur.lastrowid
        if expansion_result is not None:
            expansion_result=expansion.persist(con,manifest_id,expansion_result,inline=True)
        con.commit()
    except Exception:
        con.rollback()
        raise

    response = {
        "manifest_id": manifest_id,
        "collection": query.collection,
        "original_query": query.original_query,
        "search_query_text": query.search_query_text,
        "space_id": query.space_id,
        "profile_key": query.profile_key,
        "query_provenance": query.query_provenance,
        "ranking": {"rrf_k": query.rrf_k, "candidate_limit": limit, "exact_cosine": True},
        "eligible": eligible_summary,
        "results": results,
        "historical": False,
        "scope": scope,
        "snapshot": {k:v for k,v in snapshot.items() if k!='sources'},
    }
    if expansion_result is not None:response['expansion']=expansion_result
    return response


def _validate_manifest_id(manifest_id: object) -> int:
    if isinstance(manifest_id, bool) or not isinstance(manifest_id, int) or manifest_id <= 0:
        raise SearchError("VALIDATION_ERROR", f"manifest_id must be a positive int, got {manifest_id!r}", retryable=False)
    return manifest_id


def replay_manifest(con: sqlite3.Connection, manifest_id: int) -> dict[str, object]:
    """Returns a PREVIOUSLY-SAVED manifest's exact, frozen results — never
    re-derived from current live state, which may have changed (update/
    delete/reindex) since the original search ran. `historical=True`
    always, distinguishing a replay from a fresh `search()` call even when
    the underlying data happens to be unchanged. Surfaces the SAME fields
    a fresh `search()` return does (query_provenance, profile_key/
    space_id, ranking settings) — all of it was already durably stored in
    `filters_json`, just not previously exposed here (owner review
    2026-09-10)."""
    manifest_id = _validate_manifest_id(manifest_id)
    row = con.execute(
        "SELECT sm.collection_id, c.name, sm.query_text, sm.space_id, sm.profile_key, sm.filters_json, "
        "sm.eligible_json, sm.results_json, sm.created_at_ms "
        "FROM search_manifests sm JOIN collections c ON sm.collection_id = c.collection_id "
        "WHERE sm.manifest_id = ?",
        (manifest_id,),
    ).fetchone()
    if row is None:
        raise SearchError("NOT_FOUND", f"search manifest {manifest_id} not found", retryable=False)
    _, collection_name, query_text, space_id, profile_key, filters_json, eligible_json, results_json, created_at_ms = row
    filters = json.loads(filters_json)
    response = {
        "manifest_id": manifest_id,
        "collection": collection_name,
        "original_query": query_text,
        "search_query_text": filters.get("search_query_text"),
        "space_id": space_id,
        "profile_key": profile_key,
        "query_provenance": filters.get("query_provenance", {}),
        "ranking": {
            "rrf_k": filters.get("rrf_k"), "candidate_limit": filters.get("candidate_limit"),
            "exact_cosine": filters.get("exact_cosine"),
        },
        "eligible": json.loads(eligible_json),
        "results": json.loads(results_json),
        "created_at_ms": created_at_ms,
        "historical": True,
        "scope": filters.get('scope', {'source_keys':None,'media_types':None}),
        "snapshot": {k:v for k,v in filters.get('snapshot',{}).items() if k!='sources'},
    }
    if filters.get('expansion_requested'):
        from airag import expansion
        row=con.execute('SELECT expansion_id FROM expansion_manifests WHERE search_manifest_id=? AND inline=1',(manifest_id,)).fetchone()
        if row is not None:response['expansion']=expansion.replay(con,row[0])
    return response
