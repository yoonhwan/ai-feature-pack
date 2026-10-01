"""Schema DDL and migrations (design D-009/D-010, P-02/P-03 scope).

v1 (P-01): db_meta, schema_migrations only.
v2 (P-02): + collections/sources/source_revisions/generations/jobs/request_ledger.
v3 (P-03): + embedding_spaces/processing_profiles/chunks/normalized_documents/
fts_chunks. Per-space `vec_space_{space_id}` vec0 virtual tables are NOT part
of this static DDL — they require the sqlite_vec runtime extension to be
loaded and their dimension is only known once an embedding_spaces row exists,
so they are created lazily (CREATE VIRTUAL TABLE IF NOT EXISTS) the first
time a space is used; see `airag.embeddings.ensure_vec_space_table`.
`fts_chunks` IS part of this static DDL since FTS5 is a built-in SQLite
virtual table module needing no extension load. D-010: fts_chunks rows exist
ONLY for the currently published (ready) generation of each source — publish
inserts the new generation's rows and deletes the old ready generation's rows
in the SAME transaction as the ready-pointer move, never leaving
staged/failed rows sitting in the FTS index behind a WHERE filter (that would
skew BM25's corpus-wide term statistics for already-published content).
vec0's per-row `active` metadata column is fine for vec0 because cosine
distance is a pure per-row computation with no corpus-wide statistic to
pollute (verified empirically in docs/artifacts/p03a-provider-probe.json).
v4 (P-03-B, ft-airag-arch-astra design review 2026-09-09): + `jobs.profile_key`
column (nullable — only set when a job was created with a configured
processing profile) so a job created atomically with its storage-accepting
mutation (store.add/update) durably records WHICH profile it was staged
against, without a second, separately-committed transaction attaching that
intent later (which would leave a crash window between "content stored" and
"processing intent recorded"). + `jobs.final_response_json` (nullable): the
IMMUTABLE post-publication application response, written in the SAME
transaction as the publish that produced it (ready pointer + fts_chunks +
vec0 activation) — never recomputed live from current source/generation
state on replay, because current state can have moved on (a later update/
delete/reprocess) since this job completed; a replay of the SAME request
must keep returning the exact snapshot captured at THIS job's completion,
forever (ft-airag-arch-astra review: recomputing live on replay would make
identical retries return different answers over time). Also +
`search_manifests`: an immutable per-search record of exact query/config/
filter/eligible-version/chosen-chunk/score/anchor state (D-010 requirement
8) — never part of v3 because it did not exist as a concept until search
itself was implemented. + `jobs.lease_owner`/`lease_expires_at_ms`/
`claim_epoch` and `generations.owner_job_id`/`claim_epoch` (ft-airag-arch-
astra review 2026-09-09, crash-recovery/fencing): the pending->running CAS
alone prevents two claims from succeeding at once, but leaves a claimed job
whose worker crashed permanently stuck 'running' forever with no recovery
path. A caller MAY explicitly reclaim a job whose lease has expired
(on-demand only — no background daemon/auto-schedule): reclaiming bumps
`claim_epoch`, marks the previous 'staged' generation 'failed' (its history
is preserved, never overwritten), and starts a genuinely NEW generation
attempt owned by the new epoch. `publish_generation`/`fail_generation`
verify the generation's own `claim_epoch` still equals its owner job's
CURRENT `claim_epoch` before acting — a late write from an old, since-
reclaimed attempt is rejected (STALE_CLAIM_FENCED) even if it finishes its
outside-the-transaction model call after the reclaim already happened. A
generation staged without a job_id (the plain P-02-boundary call some
existing tests use directly) has NULL owner_job_id/claim_epoch and is never
subject to this check — fencing only applies to the P-03-B job-linked path.

`ensure_current_schema` is the only migration entrypoint: it reads the
on-disk version, refuses anything outside KNOWN_SCHEMA_VERSIONS or newer
than CURRENT_SCHEMA_VERSION, and migrates forward one step at a time inside
the caller's transaction. It never recreates or drops a database — an
existing v1 DB gains the new v2 tables in place.

Design invariants (owner review, pre-store-layer):
- `sources.head_revision_id` is the authoritative "current revision"
  pointer — never inferred via MAX(revision_id). source_revisions has NO
  uniqueness constraint on (source_id, content_hash): an A->B->A content
  history must be able to create a fresh revision row when content reverts
  to a hash it held before; a MAX()/UNIQUE-based "current" would break that.
- `sources.ready_generation_id` is likewise an explicit pointer, set only by
  a publish operation (P-03) that has verified the generation's revision
  belongs to this same source (store.py enforces this — SQLite cannot
  express a two-hop "generations.revision_id -> source_revisions.source_id
  == sources.source_id" constraint declaratively).
- `generations` has NO uniqueness constraint on (revision_id, profile_key):
  generations are immutable once created, so a retry/re-index of the same
  (revision, profile) is a NEW row (a new attempt), never an update to an
  old one. "Already ready, don't redo" is an application-level idempotency
  decision (request_ledger / caller query), not a DB constraint that would
  otherwise block legitimate re-processing after a failed attempt.
- `jobs` persists enough to be retried without external context: the input
  it was given (`revision_id`), the output it is producing (`generation_id`,
  set once known), and the CAS state it was staged against
  (`expected_state_version`).
"""

from __future__ import annotations

import sqlite3
import time

CURRENT_SCHEMA_VERSION = 5
KNOWN_SCHEMA_VERSIONS = frozenset({1, 2, 3, 4, 5})
ENGINE_TAG = "airag"


class UnsupportedSchemaVersion(Exception):
    """On-disk schema version is not one this build recognizes, or is newer
    than this build supports."""


def create_base_tables(con: sqlite3.Connection) -> None:
    """v1 tables (db_meta, schema_migrations) — used both by a fresh init
    and, implicitly, already present on any v1 DB being migrated."""
    _ = con.execute("CREATE TABLE db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    _ = con.execute(
        "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at_ms INTEGER NOT NULL)"
    )


def create_v2_tables(con: sqlite3.Connection) -> None:
    """The P-02 storage foundation: durable source/revision/generation/job/
    request-ledger ledger. See docs/DECISIONS.md D-009 and this module's
    docstring for the identity, CAS-token, and ownership invariants."""
    _ = con.execute(
        "CREATE TABLE collections (collection_id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)"
    )
    _ = con.execute(
        "CREATE TABLE sources ("
        "source_id INTEGER PRIMARY KEY, "
        "collection_id INTEGER NOT NULL REFERENCES collections(collection_id), "
        "source_key TEXT NOT NULL, "
        "origin_uri TEXT, "
        "media_type TEXT NOT NULL, "
        "state_version INTEGER NOT NULL DEFAULT 1, "
        "head_revision_id INTEGER, "
        "ready_generation_id INTEGER, "
        "deleted_at_ms INTEGER, "
        "created_at_ms INTEGER NOT NULL, "
        "UNIQUE(collection_id, source_key))"
    )
    # No UNIQUE(source_id, content_hash): an A->B->A content history must be
    # able to create a fresh revision row when content reverts to a hash it
    # held before — see module docstring.
    _ = con.execute(
        "CREATE TABLE source_revisions ("
        "revision_id INTEGER PRIMARY KEY, "
        "source_id INTEGER NOT NULL REFERENCES sources(source_id), "
        "content_hash TEXT NOT NULL, "
        "byte_length INTEGER NOT NULL, "
        "content_bytes BLOB NOT NULL, "
        "media_type TEXT NOT NULL, "
        "origin_uri TEXT, "
        "created_at_ms INTEGER NOT NULL)"
    )
    # No UNIQUE(revision_id, profile_key): generations are immutable once
    # created, so a retry/re-index is a new row, not an update — see module
    # docstring. expected_state_version is the source CAS state captured at
    # STAGING time — publish_generation checks against this stored value,
    # never a value supplied fresh by the caller at publish time (review
    # p02-review1.txt item 3: a caller-supplied publish-time token would let
    # a stale generation publish if the caller simply refreshed its token).
    _ = con.execute(
        "CREATE TABLE generations ("
        "generation_id INTEGER PRIMARY KEY, "
        "revision_id INTEGER NOT NULL REFERENCES source_revisions(revision_id), "
        "profile_key TEXT NOT NULL, "
        "status TEXT NOT NULL CHECK(status IN ('staged','ready','failed')), "
        "expected_state_version INTEGER NOT NULL, "
        "created_at_ms INTEGER NOT NULL, "
        "published_at_ms INTEGER, "
        "failed_at_ms INTEGER, "
        "error TEXT)"
    )
    _ = con.execute(
        "CREATE TABLE jobs ("
        "job_id INTEGER PRIMARY KEY, "
        "source_id INTEGER NOT NULL REFERENCES sources(source_id), "
        "revision_id INTEGER REFERENCES source_revisions(revision_id), "
        "generation_id INTEGER REFERENCES generations(generation_id), "
        "kind TEXT NOT NULL CHECK(kind IN ('add','update','delete','restore')), "
        "status TEXT NOT NULL CHECK(status IN ('pending','running','done','failed')), "
        "expected_state_version INTEGER, "
        "created_at_ms INTEGER NOT NULL, "
        "updated_at_ms INTEGER NOT NULL, "
        "error TEXT)"
    )
    _ = con.execute(
        "CREATE TABLE request_ledger ("
        "request_id TEXT PRIMARY KEY, "
        "fingerprint TEXT NOT NULL, "
        "command TEXT NOT NULL, "
        "response_json TEXT NOT NULL, "
        "created_at_ms INTEGER NOT NULL)"
    )
    _ = con.execute("CREATE INDEX idx_sources_collection ON sources(collection_id)")
    _ = con.execute("CREATE INDEX idx_revisions_source ON source_revisions(source_id)")
    _ = con.execute(
        "CREATE INDEX idx_revisions_source_hash ON source_revisions(source_id, content_hash)"
    )
    _ = con.execute(
        "CREATE INDEX idx_generations_revision_profile ON generations(revision_id, profile_key)"
    )
    _ = con.execute("CREATE INDEX idx_jobs_source ON jobs(source_id)")


def create_v3_tables(con: sqlite3.Connection) -> None:
    """The P-03 embedding/search foundation (design D-010). `embedding_spaces`
    rows are immutable once created — a fingerprint (provider+model+revision+
    dimension+modality+document/query preprocessing) identifies a space, and
    two spaces with the same declared dimension are never treated as
    comparable (D-001 model-space-isolation) because the fingerprint, not
    the dimension alone, is the identity. `processing_profiles` likewise
    fingerprints normalization/chunker/tokenizer config together with the
    embedding space it targets — `generations.profile_key` (P-02) is that
    fingerprint. `chunks` is the permanent historical record of exact
    embedded text per generation (never rewritten once a generation exists).
    `normalized_documents` holds the one standard-MD + structured
    DoclingDocument export per generation. `fts_chunks` starts empty — see
    module docstring for why rows are only ever inserted/deleted at publish
    time, never pre-staged behind a WHERE filter."""
    _ = con.execute(
        "CREATE TABLE embedding_spaces ("
        "space_id INTEGER PRIMARY KEY, "
        "fingerprint TEXT NOT NULL UNIQUE, "
        "provider TEXT NOT NULL, "
        "model TEXT NOT NULL, "
        "revision TEXT NOT NULL, "
        "dimension INTEGER NOT NULL, "
        "modality TEXT NOT NULL, "
        "document_preprocessing TEXT NOT NULL, "
        "query_preprocessing TEXT NOT NULL, "
        "created_at_ms INTEGER NOT NULL)"
    )
    _ = con.execute(
        "CREATE TABLE processing_profiles ("
        "profile_key TEXT PRIMARY KEY, "
        "space_id INTEGER NOT NULL REFERENCES embedding_spaces(space_id), "
        "normalizer_config TEXT NOT NULL, "
        "chunker_config TEXT NOT NULL, "
        "created_at_ms INTEGER NOT NULL)"
    )
    _ = con.execute(
        "CREATE TABLE normalized_documents ("
        "generation_id INTEGER PRIMARY KEY REFERENCES generations(generation_id), "
        "standard_md TEXT NOT NULL, "
        "structured_json TEXT NOT NULL, "
        "created_at_ms INTEGER NOT NULL)"
    )
    # No UNIQUE(generation_id, chunk_index) violation risk from retries:
    # chunks are written once per (immutable) generation, same as
    # generations themselves — a retried processing attempt is a NEW
    # generation row (P-02 module docstring), never a second write to an
    # existing generation's chunks.
    _ = con.execute(
        "CREATE TABLE chunks ("
        "chunk_id INTEGER PRIMARY KEY, "
        "generation_id INTEGER NOT NULL REFERENCES generations(generation_id), "
        "chunk_index INTEGER NOT NULL, "
        "text TEXT NOT NULL, "
        "token_count INTEGER NOT NULL, "
        "anchor_json TEXT, "
        "created_at_ms INTEGER NOT NULL, "
        "UNIQUE(generation_id, chunk_index))"
    )
    _ = con.execute(
        "CREATE VIRTUAL TABLE fts_chunks USING fts5("
        "text, "
        "chunk_id UNINDEXED, "
        "source_id UNINDEXED, "
        "collection_id UNINDEXED)"
    )
    _ = con.execute("CREATE INDEX idx_chunks_generation ON chunks(generation_id)")
    _ = con.execute(
        "CREATE INDEX idx_profiles_space ON processing_profiles(space_id)"
    )


def create_v4_tables(con: sqlite3.Connection) -> None:
    """P-03-B: `jobs.profile_key` lets store.add/update record, atomically
    with the job row itself (same BEGIN IMMEDIATE as the storage-accepting
    mutation), which processing profile a synchronous processing attempt was
    staged against — never attached in a second, separately-committed
    transaction (that would leave a crash gap between "content stored" and
    "processing intent recorded"). `search_manifests` is the immutable
    record of one completed search: exact query text, the profile/space it
    ran against, the filters applied, the eligible source/revision/
    generation versions considered, and the final chosen chunks with their
    per-retriever ranks/scores/anchors — written once, after the read
    snapshot that produced it, never updated in place."""
    _ = con.execute("ALTER TABLE jobs ADD COLUMN profile_key TEXT")
    _ = con.execute("ALTER TABLE jobs ADD COLUMN final_response_json TEXT")
    _ = con.execute("ALTER TABLE jobs ADD COLUMN lease_owner TEXT")
    _ = con.execute("ALTER TABLE jobs ADD COLUMN lease_expires_at_ms INTEGER")
    _ = con.execute("ALTER TABLE jobs ADD COLUMN claim_epoch INTEGER NOT NULL DEFAULT 0")
    _ = con.execute("ALTER TABLE generations ADD COLUMN owner_job_id INTEGER REFERENCES jobs(job_id)")
    _ = con.execute("ALTER TABLE generations ADD COLUMN claim_epoch INTEGER")
    _ = con.execute(
        "CREATE TABLE search_manifests ("
        "manifest_id INTEGER PRIMARY KEY, "
        "collection_id INTEGER NOT NULL REFERENCES collections(collection_id), "
        "query_text TEXT NOT NULL, "
        "profile_key TEXT NOT NULL REFERENCES processing_profiles(profile_key), "
        "space_id INTEGER NOT NULL REFERENCES embedding_spaces(space_id), "
        "filters_json TEXT NOT NULL, "
        "eligible_json TEXT NOT NULL, "
        "results_json TEXT NOT NULL, "
        "created_at_ms INTEGER NOT NULL)"
    )
    _ = con.execute(
        "CREATE INDEX idx_search_manifests_collection ON search_manifests(collection_id)"
    )


def create_v5_tables(con: sqlite3.Connection) -> None:
    """Generation-owned structure/reference intent and immutable expansion results."""
    con.execute("CREATE TABLE generation_graphs (generation_id INTEGER PRIMARY KEY REFERENCES generations(generation_id), version INTEGER NOT NULL, created_at_ms INTEGER NOT NULL, error TEXT)")
    con.execute("CREATE TABLE chunk_edges (generation_id INTEGER NOT NULL REFERENCES generation_graphs(generation_id), from_chunk_id INTEGER NOT NULL REFERENCES chunks(chunk_id), to_chunk_id INTEGER NOT NULL REFERENCES chunks(chunk_id), relation TEXT NOT NULL, provenance_json TEXT NOT NULL, PRIMARY KEY(from_chunk_id,to_chunk_id,relation))")
    con.execute("CREATE INDEX idx_chunk_edges_from ON chunk_edges(from_chunk_id,relation,to_chunk_id)")
    con.execute("CREATE TABLE chunk_references (reference_id INTEGER PRIMARY KEY, generation_id INTEGER NOT NULL REFERENCES generation_graphs(generation_id), from_chunk_id INTEGER NOT NULL REFERENCES chunks(chunk_id), relation TEXT NOT NULL, target_json TEXT NOT NULL, provenance_json TEXT NOT NULL)")
    con.execute("CREATE INDEX idx_chunk_references_from ON chunk_references(from_chunk_id,reference_id)")
    con.execute("CREATE TABLE chunk_locators (generation_id INTEGER NOT NULL REFERENCES generation_graphs(generation_id), chunk_id INTEGER NOT NULL REFERENCES chunks(chunk_id), kind TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(chunk_id,kind,value))")
    con.execute("CREATE INDEX idx_chunk_locators_target ON chunk_locators(generation_id,kind,value,chunk_id)")
    con.execute("CREATE TABLE expansion_manifests (expansion_id INTEGER PRIMARY KEY, search_manifest_id INTEGER NOT NULL REFERENCES search_manifests(manifest_id), inline INTEGER NOT NULL DEFAULT 0, response_json TEXT NOT NULL, created_at_ms INTEGER NOT NULL)")
    con.execute("CREATE UNIQUE INDEX idx_expansion_inline ON expansion_manifests(search_manifest_id) WHERE inline=1")
    from airag import relations
    for (generation_id,) in con.execute("SELECT DISTINCT generation_id FROM chunks ORDER BY generation_id").fetchall():
        try:
            relations.persist_generation(con, generation_id)
        except relations.GraphLimitError as exc:
            # A new graph limit must not make previously valid v4 content
            # inaccessible. Search/replay remain available; expansion of
            # this generation fails explicitly instead of using a partial graph.
            con.execute('INSERT INTO generation_graphs(generation_id,version,created_at_ms,error) VALUES (?,?,?,?)',
                        (generation_id,0,int(time.time()*1000),str(exc)))


def create_fresh_database(con: sqlite3.Connection) -> None:
    """Used by init_db: a brand-new database goes straight to
    CURRENT_SCHEMA_VERSION in one transaction — no need to create v1 then
    migrate a database that never existed at v1."""
    create_base_tables(con)
    create_v2_tables(con)
    create_v3_tables(con)
    create_v4_tables(con)
    create_v5_tables(con)
    now_ms = int(time.time() * 1000)
    _ = con.execute(
        "INSERT INTO schema_migrations(version, applied_at_ms) VALUES (?, ?)",
        (CURRENT_SCHEMA_VERSION, now_ms),
    )
    _ = con.execute(
        "INSERT INTO db_meta(key, value) VALUES ('engine', ?)", (ENGINE_TAG,)
    )


def _read_schema_version(con: sqlite3.Connection) -> int | None:
    row = con.execute("SELECT MAX(version) FROM schema_migrations").fetchone()
    return row[0] if row else None


def _check_known_and_not_future(version: int | None) -> None:
    if version not in KNOWN_SCHEMA_VERSIONS:
        raise UnsupportedSchemaVersion(
            f"unsupported schema version {version!r} (known: {sorted(KNOWN_SCHEMA_VERSIONS)}, current: {CURRENT_SCHEMA_VERSION})"
        )
    if version > CURRENT_SCHEMA_VERSION:
        raise UnsupportedSchemaVersion(
            f"schema version {version} is newer than this build supports ({CURRENT_SCHEMA_VERSION})"
        )


def ensure_current_schema(con: sqlite3.Connection) -> None:
    """Reads the on-disk schema version and migrates forward to
    CURRENT_SCHEMA_VERSION if it is an older KNOWN version. Raises
    UnsupportedSchemaVersion for anything unrecognized or newer than this
    build supports — never guesses at an unknown schema's shape.

    Migration itself (DDL + the version-bump row) is one atomic
    BEGIN IMMEDIATE .. COMMIT transaction, not autocommitted statement by
    statement: `con.isolation_level = None` means every bare `execute()` is
    its own implicit transaction, so a mid-migration failure without an
    explicit BEGIN could leave some v2 tables created and others missing,
    with schema_migrations still reporting the old version — neither fully
    migrated nor cleanly v1. BEGIN IMMEDIATE also acquires the write lock
    up front and the version is re-read *after* acquiring it: a second
    connection racing to open the same v1 database concurrently will block
    on the lock, then see the migration already applied by the winner and
    take the no-op fast path below instead of re-running (and failing on)
    the DDL a second time.
    """
    version = _read_schema_version(con)
    _check_known_and_not_future(version)
    if version == CURRENT_SCHEMA_VERSION:
        return

    _ = con.execute("BEGIN IMMEDIATE")
    try:
        version = _read_schema_version(con)
        _check_known_and_not_future(version)
        assert version is not None
        if version < 2:
            create_v2_tables(con)
        if version < 3:
            create_v3_tables(con)
        if version < 4:
            create_v4_tables(con)
        if version < 5:
            create_v5_tables(con)
        if version < CURRENT_SCHEMA_VERSION:
            now_ms = int(time.time() * 1000)
            _ = con.execute(
                "INSERT INTO schema_migrations(version, applied_at_ms) VALUES (?, ?)",
                (CURRENT_SCHEMA_VERSION, now_ms),
            )
        con.commit()
    except Exception:
        con.rollback()
        raise
