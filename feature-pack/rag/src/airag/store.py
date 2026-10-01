"""Public storage API (design D-009, P-02 scope).

Identity/CAS model — see docs/DECISIONS.md D-009 for the narrative and one
worked example. Summary:

- A source is identified by (collection, source_key), never by a mutable
  path alone.
- `revision_token` is an OPAQUE compare-and-swap token (base64 of
  "v1:<source_id>:<state_version>") returned by every mutation, NOT a
  content hash. Callers pass it back as `expected_revision` on update/
  delete/restore. `state_version` increments on every real state mutation
  (content change, metadata change, delete, restore) — including delete and
  restore, which touch no content bytes — so a token from before a
  delete/restore cycle is stale even if content is unchanged afterward.
- `source_revisions.content_hash` is the *content* identity (sha256 of the
  bytes). It has no uniqueness constraint: content can legitimately revert
  to a hash it held earlier (A->B->A), which must create a fresh revision
  row — see db/schema.py's docstring.
- `force_reprocess=True` with UNCHANGED bytes does NOT create a new
  revision (D-001: same original bytes + a different processing profile is
  a new GENERATION on the same revision, not a new revision) — it queues a
  new processing job against the existing head revision instead.
- request_id (consumer-supplied) + a fingerprint of the actual request
  payload (content bytes included, not just a path) are checked and
  persisted INSIDE the same BEGIN IMMEDIATE transaction as the mutation
  itself (p02-review1.txt item 1) — checking the ledger before acquiring
  the write lock lets two concurrent identical retries both miss the ledger
  and then collide on a UNIQUE constraint instead of one cleanly replaying.
  An identical retry (same request_id, same fingerprint) replays the stored
  result without re-validating expected_revision or redoing work —
  recognized before any CAS check, so a retry succeeds even if the source
  has moved on since. Same request_id with a DIFFERENT fingerprint is a
  conflict.

Searchability model (p02-review1.txt item 4): `ready_generation_id` is not
collapsed into a single "ready" boolean at read time. `processing_status` is
one of not_indexed/pending/ready/stale_ready, and `searchable` is reported
separately — a deleted source is never searchable regardless of any ready
pointer; a source whose head has moved past what was last published is
`stale_ready` (still searchable — the old ready content is real and served
— just not built from the current head).

P-02 never processes content: bare `add`/`update` never create or touch
`generations` — that is P-03's job, via the `stage_generation`/
`publish_generation`/`fail_generation` primitives this module exposes as a
ready boundary. `publish_generation` takes only a `generation_id`: the CAS
state it publishes against is the one captured by `stage_generation` at
staging time, never a value supplied fresh by the caller at publish time
(closes the "stale generation republishes because the caller refreshed its
token" gap — p02-review1.txt item 3).

P-03-B (ft-airag-arch-astra design review 2026-09-09): `add`/`update` accept
an optional keyword-only `profile_key` — when a caller (api.py, having
resolved "explicit request override, else the currently configured
default") passes one, the SAME BEGIN IMMEDIATE transaction that accepts the
storage mutation ALSO inserts a 'staged' generation and links the job to it
(`jobs.profile_key` set, `jobs.generation_id` set, status flips to
'running') — never a second, separately-committed transaction attaching
that intent afterward, which would leave a crash window between "content
durably stored" and "processing intent durably recorded" (this is the exact
gap dispatch item 4 calls out). The returned response's `job_id` is what a
caller uses afterward to drive/resume the actual processing (chunk+embed+
publish, done outside this transaction) and, on a later replay, to look up
`jobs.final_response_json` — the immutable completion snapshot written by
`publish_generation_with_content` — rather than recomputing a live answer
from current source/generation state, which could have moved on since (a
later update/delete/reprocess) and would make an identical retry return a
different answer over time.

`profile_key` here is deliberately NOT part of the idempotency fingerprint:
only `AddRequest.explicit_profile_key`/`UpdateRequest.explicit_profile_key`
(a caller's OWN explicit override, part of what the caller actually asked
for) is fingerprinted. The resolved `profile_key` argument reflects "the
currently configured default" when the caller did not explicitly override
it — that can legitimately change between an original call and a later
retry of the SAME request_id, and a retry must keep using the profile
captured at ORIGINAL processing time (found via the cached response's
`job_id`), never silently reinterpret the retry under today's new default.
A caller who DOES explicitly pass a different profile on retry gets a
different fingerprint and therefore the existing `IDEMPOTENCY_MISMATCH`
path — no separate mechanism needed for that case.
"""

from __future__ import annotations

import base64
import hashlib
import json
import sqlite3
import time
import uuid
from dataclasses import dataclass

# NOTE: airag.embeddings is imported LAZILY inside
# publish_generation_with_content, never at module level — a top-level
# import here drags in chunking.py's docling_core/transformers import
# chain for every caller of this module, including the plain DB-management
# CLI paths (init/manage doctor/verify/etc.) that never touch embeddings at
# all (independently measured: adds ~1.4s just to `import airag.store`,
# which the full test suite pays once per subprocess-based CLI test).

# strict_json_loads: shared with the P-03 normalize conversation adapter,
# see airag._json — kept out of this module to avoid a store<->normalize
# circular import once store calls into normalize for synchronous
# add/update processing.
from airag._json import strict_json_loads

CAS_TOKEN_PREFIX = "v1"
MAX_CONTENT_BYTES = 50 * 1024 * 1024
UTF8_VALIDATED_MEDIA_TYPES = frozenset({"text/plain", "text/markdown", "application/json"})

# A claim's lease must comfortably outlast several embedding HTTP batches
# with retries (each bounded at the provider timeout, see embeddings.py) —
# the pipeline renews it between batches on long documents, this is only
# the ceiling before an on-demand reclaim becomes possible. No background
# daemon expires anything automatically (ft-airag-arch-astra review
# 2026-09-09: "요청시 회수만") — a lease past its deadline just becomes
# eligible for `reclaim_stale_job` the next time someone asks.
DEFAULT_LEASE_MS = 5 * 60 * 1000


class ApiError(Exception):
    """Structured error: stable `code`, human `message`, and whether a
    caller should expect a retry (after re-fetching current state) to
    plausibly succeed."""

    code: str
    message: str
    retryable: bool

    def __init__(self, code: str, message: str, *, retryable: bool) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.retryable = retryable

    def to_dict(self) -> dict[str, object]:
        return {"code": self.code, "message": self.message, "retryable": self.retryable}


# ---------------------------------------------------------------- CAS token


def encode_revision_token(source_id: int, state_version: int) -> str:
    raw = f"{CAS_TOKEN_PREFIX}:{source_id}:{state_version}".encode()
    return base64.urlsafe_b64encode(raw).decode("ascii")


def decode_revision_token(token: str) -> tuple[int, int]:
    try:
        raw = base64.urlsafe_b64decode(token.encode("ascii")).decode("utf-8")
        prefix, source_id_s, state_version_s = raw.split(":")
        if prefix != CAS_TOKEN_PREFIX:
            raise ValueError("unrecognized token prefix")
        return int(source_id_s), int(state_version_s)
    except Exception as exc:
        raise ApiError(
            "INVALID_REVISION_TOKEN", f"malformed revision token: {exc}", retryable=False
        ) from exc


def _require_cas_match(source_id: int, state_version: int, expected_revision: str) -> None:
    expected_source_id, expected_state_version = decode_revision_token(expected_revision)
    if expected_source_id != source_id or expected_state_version != state_version:
        raise ApiError(
            "CONFLICT_STALE_REVISION",
            "expected_revision does not match the source's current state (it moved on "
            "— including possibly a delete/restore cycle with unchanged content; "
            "re-fetch status and retry)",
            retryable=True,
        )


# ---------------------------------------------------------- idempotency
#
# Checked and recorded INSIDE the caller's already-open BEGIN IMMEDIATE
# transaction — never before it (p02-review1.txt item 1).


def _fingerprint(payload: dict[str, object]) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _check_idempotency(
    con: sqlite3.Connection, request_id: str, fingerprint: str
) -> dict[str, object] | None:
    row = con.execute(
        "SELECT fingerprint, response_json FROM request_ledger WHERE request_id = ?",
        (request_id,),
    ).fetchone()
    if row is None:
        return None
    stored_fingerprint, response_json = row
    if stored_fingerprint != fingerprint:
        raise ApiError(
            "IDEMPOTENCY_MISMATCH",
            f"request_id {request_id!r} was already used with a different request payload",
            retryable=False,
        )
    result = json.loads(response_json)
    result["idempotent_replay"] = True
    return result


def _record_request(
    con: sqlite3.Connection,
    request_id: str,
    fingerprint: str,
    command: str,
    response: dict[str, object],
) -> None:
    now_ms = int(time.time() * 1000)
    _ = con.execute(
        "INSERT INTO request_ledger(request_id, fingerprint, command, response_json, created_at_ms) VALUES (?, ?, ?, ?, ?)",
        (request_id, fingerprint, command, json.dumps(response), now_ms),
    )


# --------------------------------------------------------------- requests


@dataclass
class AddRequest:
    request_id: str
    collection: str
    source_key: str
    content: bytes
    media_type: str = "text/plain"
    origin_uri: str | None = None
    # The caller's OWN explicit profile override, if any — part of what the
    # caller asked for, so it IS in the idempotency fingerprint. None means
    # "use whatever the configured default profile is" — see module
    # docstring's P-03-B section for why that resolved default is NOT
    # fingerprinted the same way.
    explicit_profile_key: str | None = None

    def validate(self) -> None:
        _require_nonempty_str("request_id", self.request_id)
        _require_nonempty_str("collection", self.collection)
        _require_nonempty_str("source_key", self.source_key)
        _require_media_type(self.media_type)
        _require_origin_uri(self.origin_uri)
        _require_content(self.content, self.media_type)
        if self.explicit_profile_key is not None and not isinstance(self.explicit_profile_key, str):
            raise ApiError("VALIDATION_ERROR", "explicit_profile_key must be a string or None", retryable=False)


@dataclass
class UpdateRequest:
    request_id: str
    collection: str
    source_key: str
    expected_revision: str
    content: bytes
    media_type: str = "text/plain"
    origin_uri: str | None = None
    force_reprocess: bool = False
    explicit_profile_key: str | None = None

    def validate(self) -> None:
        _require_nonempty_str("request_id", self.request_id)
        _require_nonempty_str("collection", self.collection)
        _require_nonempty_str("source_key", self.source_key)
        _require_nonempty_str("expected_revision", self.expected_revision)
        _require_media_type(self.media_type)
        _require_origin_uri(self.origin_uri)
        if not isinstance(self.force_reprocess, bool):
            raise ApiError(
                "VALIDATION_ERROR", "force_reprocess must be a bool", retryable=False
            )
        _require_content(self.content, self.media_type)
        if self.explicit_profile_key is not None and not isinstance(self.explicit_profile_key, str):
            raise ApiError("VALIDATION_ERROR", "explicit_profile_key must be a string or None", retryable=False)


@dataclass
class DeleteRequest:
    request_id: str
    collection: str
    source_key: str
    expected_revision: str

    def validate(self) -> None:
        _require_nonempty_str("request_id", self.request_id)
        _require_nonempty_str("collection", self.collection)
        _require_nonempty_str("source_key", self.source_key)
        _require_nonempty_str("expected_revision", self.expected_revision)


@dataclass
class RestoreRequest:
    request_id: str
    collection: str
    source_key: str
    expected_revision: str

    def validate(self) -> None:
        _require_nonempty_str("request_id", self.request_id)
        _require_nonempty_str("collection", self.collection)
        _require_nonempty_str("source_key", self.source_key)
        _require_nonempty_str("expected_revision", self.expected_revision)


def _require_nonempty_str(field_name: str, value: object) -> None:
    if not isinstance(value, str) or not value:
        raise ApiError(
            "VALIDATION_ERROR", f"{field_name} must be a non-empty string", retryable=False
        )


def _require_media_type(media_type: object) -> None:
    if not isinstance(media_type, str) or not media_type:
        raise ApiError(
            "VALIDATION_ERROR", "media_type must be a non-empty string", retryable=False
        )


def _require_origin_uri(origin_uri: object) -> None:
    if origin_uri is not None and not isinstance(origin_uri, str):
        raise ApiError(
            "VALIDATION_ERROR", "origin_uri must be a string or None", retryable=False
        )


def _require_content(content: object, media_type: str) -> None:
    # Deliberately bytes-only, not bytearray: a mutable buffer could change
    # between the hash computed here and the bytes actually stored later,
    # silently diverging content_hash from content_bytes. Accepting only an
    # immutable type removes that whole class of bug (p02-review1.txt item 2).
    if not isinstance(content, bytes):
        raise ApiError(
            "VALIDATION_ERROR",
            f"content must be bytes (immutable) — got {type(content).__name__}",
            retryable=False,
        )
    if len(content) > MAX_CONTENT_BYTES:
        raise ApiError(
            "PAYLOAD_TOO_LARGE",
            f"content is {len(content)} bytes, exceeds the {MAX_CONTENT_BYTES}-byte guard",
            retryable=False,
        )
    if media_type in UTF8_VALIDATED_MEDIA_TYPES:
        try:
            _ = content.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ApiError(
                "VALIDATION_ERROR",
                f"content is not valid UTF-8 for media_type={media_type!r}: {exc}",
                retryable=False,
            ) from exc
    if media_type == "application/json":
        try:
            _ = strict_json_loads(content)
        except (json.JSONDecodeError, ValueError) as exc:
            raise ApiError(
                "VALIDATION_ERROR", f"content is not valid JSON: {exc}", retryable=False
            ) from exc


# ------------------------------------------------------------------ helpers


def _get_or_create_collection(con: sqlite3.Connection, name: str) -> int:
    row = con.execute(
        "SELECT collection_id FROM collections WHERE name = ?", (name,)
    ).fetchone()
    if row is not None:
        return row[0]
    cur = con.execute("INSERT INTO collections(name) VALUES (?)", (name,))
    assert cur.lastrowid is not None
    return cur.lastrowid


@dataclass
class _SourceRow:
    source_id: int
    state_version: int
    head_revision_id: int | None
    ready_generation_id: int | None
    deleted_at_ms: int | None
    media_type: str
    origin_uri: str | None


def _find_source(con: sqlite3.Connection, collection: str, source_key: str) -> _SourceRow | None:
    row = con.execute(
        "SELECT s.source_id, s.state_version, s.head_revision_id, s.ready_generation_id, "
        "s.deleted_at_ms, s.media_type, s.origin_uri "
        "FROM sources s JOIN collections c ON s.collection_id = c.collection_id "
        "WHERE c.name = ? AND s.source_key = ?",
        (collection, source_key),
    ).fetchone()
    if row is None:
        return None
    return _SourceRow(*row)


def _require_source(con: sqlite3.Connection, collection: str, source_key: str) -> _SourceRow:
    row = _find_source(con, collection, source_key)
    if row is None:
        raise ApiError(
            "NOT_FOUND",
            f"no source {source_key!r} in collection {collection!r}",
            retryable=False,
        )
    return row


def _resolve_processing_fields(
    con: sqlite3.Connection, s: _SourceRow
) -> dict[str, object]:
    """Never collapses "any ready pointer exists" into a bare "ready"
    boolean (p02-review1.txt item 4): a deleted source is never searchable
    regardless of a ready pointer; a source whose head has moved past what
    was last published is `stale_ready` — still searchable, just not built
    from the current head."""
    ready_revision_id: int | None = None
    if s.ready_generation_id is not None:
        row = con.execute(
            "SELECT revision_id FROM generations WHERE generation_id = ?",
            (s.ready_generation_id,),
        ).fetchone()
        ready_revision_id = row[0] if row is not None else None

    deleted = s.deleted_at_ms is not None
    searchable = (not deleted) and s.ready_generation_id is not None

    if deleted:
        processing_status = "not_indexed"
    elif s.ready_generation_id is None:
        processing_status = "not_indexed" if s.head_revision_id is None else "pending"
    elif ready_revision_id == s.head_revision_id:
        processing_status = "ready"
    else:
        processing_status = "stale_ready"

    return {
        "head_revision_id": s.head_revision_id,
        "ready_generation_id": s.ready_generation_id,
        "ready_revision_id": ready_revision_id,
        "searchable": searchable,
        "processing_status": processing_status,
    }


# ---------------------------------------------------------------- mutations


def _insert_staged_generation(
    con: sqlite3.Connection,
    revision_id: int,
    profile_key: str,
    expected_state_version: int,
    now_ms: int,
    *,
    job_id: int | None,
    lease_owner: str | None = None,
    lease_ms: int = DEFAULT_LEASE_MS,
) -> int:
    """Inserts a 'staged' generation row and, if job_id is given, links the
    job to it: generation_id set, status -> 'running', profile_key
    captured, AND a fresh claim (`claim_epoch` bumped from whatever it was
    — 0 on a job's very first claim — to a new value, `lease_owner`/
    `lease_expires_at_ms` set). The generation itself records the epoch it
    was staged under (`owner_job_id`, `claim_epoch`) so `publish_generation`/
    `fail_generation` can later verify that epoch is still current before
    acting (fencing — see schema.py's v4 docstring). The shared core of the
    standalone `stage_generation` P-02 boundary call and the inline staging
    `add`/`update` perform atomically with their own storage-accepting
    mutation (P-03-B). Caller must already hold the BEGIN IMMEDIATE write
    lock and have validated CAS/head-revision/job-claimability."""
    new_epoch: int | None = None
    if job_id is not None:
        row = con.execute("SELECT claim_epoch FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
        assert row is not None
        new_epoch = row[0] + 1

    cur = con.execute(
        "INSERT INTO generations(revision_id, profile_key, status, expected_state_version, created_at_ms, "
        "owner_job_id, claim_epoch) VALUES (?, ?, 'staged', ?, ?, ?, ?)",
        (revision_id, profile_key, expected_state_version, now_ms, job_id, new_epoch),
    )
    assert cur.lastrowid is not None
    generation_id = cur.lastrowid
    if job_id is not None:
        owner = lease_owner if lease_owner is not None else uuid.uuid4().hex
        _ = con.execute(
            "UPDATE jobs SET generation_id = ?, status = 'running', profile_key = ?, updated_at_ms = ?, "
            "lease_owner = ?, lease_expires_at_ms = ?, claim_epoch = ? WHERE job_id = ?",
            (generation_id, profile_key, now_ms, owner, now_ms + lease_ms, new_epoch, job_id),
        )
    return generation_id


def _check_claim_fencing(con: sqlite3.Connection, generation_id: int) -> None:
    """Raises STALE_CLAIM_FENCED if this generation was staged under a job
    epoch that is no longer current — i.e. the job has since been
    reclaimed (its lease expired and someone else took over) and this
    generation is a late write from the abandoned attempt. A generation
    staged without a job_id (owner_job_id/claim_epoch both NULL — the plain
    P-02-boundary call some tests use directly) is never subject to this
    check."""
    row = con.execute(
        "SELECT owner_job_id, claim_epoch FROM generations WHERE generation_id = ?", (generation_id,)
    ).fetchone()
    assert row is not None
    owner_job_id, gen_epoch = row
    if owner_job_id is None:
        return
    job_row = con.execute("SELECT claim_epoch FROM jobs WHERE job_id = ?", (owner_job_id,)).fetchone()
    if job_row is None or job_row[0] != gen_epoch:
        raise ApiError(
            "STALE_CLAIM_FENCED",
            f"generation {generation_id} was staged under an epoch that is no longer current "
            "(its job has since been reclaimed — this is a late write from an abandoned attempt)",
            retryable=False,
        )


def renew_lease(con: sqlite3.Connection, job_id: int, claim_epoch: int, *, lease_ms: int = DEFAULT_LEASE_MS) -> None:
    """Extends a still-live claim's lease deadline — the pipeline calls
    this between embedding provider batches on a long document (p03-
    embedding-review.txt item 5) so a slow-but-alive worker's own job never
    becomes eligible for `reclaim_stale_job` out from under it. `claim_epoch`
    must match the job's CURRENT epoch (the value the caller received when
    it originally claimed or reclaimed this job) — a caller whose claim has
    already been superseded by a reclaim gets STALE_CLAIM_FENCED here too,
    the same fencing `publish_generation`/`fail_generation` apply, so a
    fenced-out worker cannot keep an abandoned lease alive by renewing it."""
    _ = con.execute("BEGIN IMMEDIATE")
    try:
        row = con.execute("SELECT status, claim_epoch FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
        if row is None:
            raise ApiError("NOT_FOUND", f"job {job_id} not found", retryable=False)
        status, current_epoch = row
        if current_epoch != claim_epoch:
            raise ApiError(
                "STALE_CLAIM_FENCED",
                f"job {job_id}'s claim epoch has moved on (now {current_epoch}, caller has {claim_epoch}) "
                "— this claim was already reclaimed",
                retryable=False,
            )
        if status != "running":
            raise ApiError(
                "INVALID_JOB_STATE", f"job {job_id} is {status!r}, not 'running' — nothing to renew", retryable=False
            )
        now_ms = int(time.time() * 1000)
        _ = con.execute(
            "UPDATE jobs SET lease_expires_at_ms = ?, updated_at_ms = ? WHERE job_id = ?",
            (now_ms + lease_ms, now_ms, job_id),
        )
        con.commit()
    except Exception:
        con.rollback()
        raise


def reclaim_stale_job(
    con: sqlite3.Connection,
    job_id: int,
    *,
    lease_owner: str | None = None,
    lease_ms: int = DEFAULT_LEASE_MS,
) -> dict[str, object]:
    """On-demand recovery for a job whose claim (lease) has expired — no
    background daemon calls this; a caller retrying a request that finds
    its job stuck 'running' past its lease deadline calls this explicitly.
    Atomically: marks the abandoned generation 'failed' (history preserved,
    never silently overwritten), bumps the job's claim_epoch, and starts a
    genuinely NEW staged generation owned by the new epoch — never reusing
    the old generation_id. Refuses a job that is not 'running', whose lease
    has NOT actually expired yet (still-live attempts are not reclaimable
    just because someone asks), whose revision is no longer the source's
    head, or whose source has moved (delete/restore/metadata edit) since
    this job's own `expected_state_version` was captured at creation time —
    that CAS check is what prevents reclaiming into an unnecessary model
    call against a source that has since changed underneath it.

    `profile_key` is deliberately NOT a parameter here — this reclaims the
    SAME job's ALREADY-captured `jobs.profile_key` from its original claim
    (ft-airag-arch-astra review 2026-09-09: accepting a fresh profile_key
    argument here would let a reclaim silently reinterpret the request
    under a different profile than the one it was originally captured
    against, breaking the "retry uses the originally captured profile"
    invariant just as surely as re-resolving today's default would)."""
    _ = con.execute("BEGIN IMMEDIATE")
    try:
        row = con.execute(
            "SELECT source_id, revision_id, status, generation_id, lease_expires_at_ms, "
            "profile_key, expected_state_version FROM jobs WHERE job_id = ?",
            (job_id,),
        ).fetchone()
        if row is None:
            raise ApiError("NOT_FOUND", f"job {job_id} not found", retryable=False)
        source_id, revision_id, status, old_generation_id, lease_expires_at_ms, profile_key, job_expected_state_version = row
        if status != "running":
            raise ApiError(
                "INVALID_JOB_STATE", f"job {job_id} is {status!r}, not 'running' — nothing to reclaim", retryable=False
            )
        if profile_key is None:
            # Cannot happen for a job that ever reached 'running' via
            # _insert_staged_generation (which always sets it alongside the
            # status flip) — defensive only, never a silently-guessed value.
            raise ApiError(
                "INVALID_JOB_STATE", f"job {job_id} has no captured profile_key — cannot reclaim", retryable=False
            )
        now_ms = int(time.time() * 1000)
        if lease_expires_at_ms is None or now_ms < lease_expires_at_ms:
            raise ApiError(
                "LEASE_NOT_EXPIRED",
                f"job {job_id}'s lease has not expired yet — the current attempt may still be live",
                retryable=True,
            )

        src_row = con.execute(
            "SELECT state_version, head_revision_id, deleted_at_ms FROM sources WHERE source_id = ?",
            (source_id,),
        ).fetchone()
        assert src_row is not None
        state_version, head_revision_id, deleted_at_ms = src_row
        if deleted_at_ms is not None:
            raise ApiError("ALREADY_DELETED", f"source {source_id} is deleted — cannot reclaim", retryable=False)
        if revision_id != head_revision_id:
            raise ApiError(
                "STALE_REVISION",
                f"revision {revision_id} is no longer the source's head — refusing to reclaim onto a superseded revision",
                retryable=False,
            )
        if state_version != job_expected_state_version:
            raise ApiError(
                "CONFLICT_STALE_REVISION",
                f"source state has changed (delete/restore/metadata edit) since job {job_id} was created "
                "— refusing to reclaim onto a source that has moved on",
                retryable=True,
            )

        if old_generation_id is not None:
            _ = con.execute(
                "UPDATE generations SET status = 'failed', failed_at_ms = ?, error = ? WHERE generation_id = ? AND status = 'staged'",
                (now_ms, "lease_expired_reclaimed_by_new_attempt", old_generation_id),
            )

        new_generation_id = _insert_staged_generation(
            con, revision_id, profile_key, state_version, now_ms,
            job_id=job_id, lease_owner=lease_owner, lease_ms=lease_ms,
        )
        job_row = con.execute("SELECT claim_epoch FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
        assert job_row is not None
        con.commit()
        return {
            "job_id": job_id,
            "generation_id": new_generation_id,
            "previous_generation_id": old_generation_id,
            "claim_epoch": job_row[0],
        }
    except Exception:
        con.rollback()
        raise


def retry(
    con: sqlite3.Connection,
    request_id: str,
    job_id: int,
    *,
    profile_key: str | None = None,
    lease_owner: str | None = None,
    lease_ms: int = DEFAULT_LEASE_MS,
) -> dict[str, object]:
    """P06-03: explicit operator-facing retry / process-existing-pending
    command, identified by `job_id` (which pins the exact source/revision/
    profile). Idempotent via `request_ledger` exactly like `add`/`update`:
    checked and recorded INSIDE this same BEGIN IMMEDIATE transaction — a
    replay (same request_id + same fingerprint of job_id+profile_key)
    returns the cached response; a different job_id/profile_key under the
    SAME request_id is `IDEMPOTENCY_MISMATCH`, never silently reinterpreted.

    Branches on the TARGET job's current status:
    - 'pending' with no generation_id (a `stored_pending` receipt from an
      add/update that had no profile configured — D-011: no automatic
      model selection): requires an EXPLICIT `profile_key` (nothing
      captured to reuse); stages a generation on THIS SAME job. This is
      safe to mutate in place — ft-airag-arch-astra 2026-09-10: the
      ORIGINAL add/update's own stored receipt has `generation_id: None`
      and short-circuits before ever re-reading live job state, so later
      staging this job does not change what that original request replays.
    - 'failed': creates a GENUINELY NEW job row (same source_id/
      revision_id, `kind='update'`) and stages a generation on THAT new
      job — the ORIGINAL failed job's status/generation_id/claim_epoch/
      error/final_response_json are NEVER touched. This is REQUIRED,
      not merely safe: unlike the pending case, a job that was actually
      staged has a non-None generation_id in its OWN add/update receipt,
      so `api._finish_ingestion` re-reads THAT SAME job_id's live state on
      every replay of the ORIGINAL request — mutating it here would change
      what that original request replays to (ft-airag-arch-astra review
      2026-09-10, correcting an earlier draft that mutated the same job).
      Reuses the failed job's own already-captured `profile_key` (a
      caller-supplied value that does not match it is rejected, never
      silently overridden).
    - 'running' or 'done': no staging action — the caller (api.retry) is
      expected to drive the SAME job_id through the existing lease/replay
      resolution (`reclaim_stale_job` if the lease expired, or the
      immutable `final_response_json` if done) exactly as add/update's own
      synchronous path already does; this function just validates the
      target and returns it unchanged.
    - anything else: `INVALID_JOB_STATE`.

    CAS (pending/failed branches only): the source's CURRENT state_version
    must still equal the TARGET job's own `expected_state_version` —
    exactly the same check `reclaim_stale_job` applies — so a delete/
    restore/metadata edit, or a later successful publish on the same
    revision, since this job was created cannot be silently retried onto a
    source that has moved on; a mismatch is `CONFLICT_STALE_REVISION`.

    An explicit `profile_key` (the 'pending' branch) is validated as an
    ACTUALLY REGISTERED profile BEFORE claiming — never leaving a job
    'running' against a nonexistent/malformed profile.

    Active-job duplicate guard (the 'failed' branch): before creating a
    new job, checks for an existing NON-TERMINAL job (status 'pending' or
    'running') already covering the SAME (source_id, revision_id) — a
    concurrent retry (different request_id, same target job_id) that
    raced in and committed first, or any other still-live job for this
    exact revision (e.g. an independent force_reprocess under a different
    profile). If found, raises `IN_PROGRESS` and records NOTHING in the
    ledger for this attempt — it never adopts/executes that OTHER job
    (which could target a different profile entirely, or be a pending-
    with-no-profile job that would falsely report success with
    generation_id=None). A genuine restart of THIS SAME retry request_id
    is already served by the idempotency cache-hit above, before this
    check is ever reached.

    Returns `{"job_id": <the job a caller should now resolve/process>,
    "generation_id": ..., "original_job_id": job_id, "profile_key": ...}`
    — for the 'pending'/'running'/'done' branches `job_id ==
    original_job_id`; only the 'failed' branch (absent a duplicate) returns
    a different (new) job_id."""
    if isinstance(job_id, bool) or not isinstance(job_id, int) or job_id <= 0:
        raise ApiError("VALIDATION_ERROR", f"job_id must be a positive int, got {job_id!r}", retryable=False)
    _require_nonempty_str("request_id", request_id)
    if profile_key is not None and (not isinstance(profile_key, str) or not profile_key):
        raise ApiError("VALIDATION_ERROR", "profile_key must be a non-empty string or None", retryable=False)
    fingerprint = _fingerprint({"command": "retry", "job_id": job_id, "profile_key": profile_key})

    _ = con.execute("BEGIN IMMEDIATE")
    try:
        cached = _check_idempotency(con, request_id, fingerprint)
        if cached is not None:
            con.rollback()
            return cached

        row = con.execute(
            "SELECT source_id, revision_id, status, generation_id, profile_key, expected_state_version "
            "FROM jobs WHERE job_id = ?",
            (job_id,),
        ).fetchone()
        if row is None:
            raise ApiError("NOT_FOUND", f"job {job_id} not found", retryable=False)
        source_id, revision_id, status, generation_id, captured_profile_key, job_expected_state_version = row
        if revision_id is None:
            # delete/restore jobs carry no revision/profile/generation at
            # all (store.delete/restore insert kind='delete'|'restore',
            # status='done', every other column NULL) — they are not
            # content-processing jobs and retry does not apply to them.
            # Without this check status='done' fell through to the no-op
            # "already done" branch below and returned a fake ok=True
            # success (ft-airag-arch-astra review 2026-09-10).
            raise ApiError(
                "INVALID_JOB_STATE", f"job {job_id} is not a content-processing job (no revision) — retry does not apply",
                retryable=False,
            )

        if captured_profile_key is not None and profile_key is not None and profile_key != captured_profile_key:
            raise ApiError(
                "VALIDATION_ERROR",
                "profile_key does not match this job's already-captured profile — retry cannot reinterpret "
                "under a different profile",
                retryable=False,
            )

        now_ms = int(time.time() * 1000)
        active_job_id = job_id
        active_generation_id = generation_id
        active_profile_key = captured_profile_key

        if status == "pending" and generation_id is None:
            if captured_profile_key is not None:
                raise ApiError(
                    "INVALID_JOB_STATE", f"job {job_id} already has a captured profile — this is not a "
                    "never-staged pending job", retryable=False,
                )
            if profile_key is None:
                raise ApiError(
                    "VALIDATION_ERROR", "profile_key is required to process a never-staged pending job",
                    retryable=False,
                )
            if con.execute(
                "SELECT 1 FROM processing_profiles WHERE profile_key = ?", (profile_key,)
            ).fetchone() is None:
                raise ApiError("NOT_FOUND", f"processing profile {profile_key!r} not found", retryable=False)
            src_row = con.execute(
                "SELECT state_version, head_revision_id, deleted_at_ms FROM sources WHERE source_id = ?",
                (source_id,),
            ).fetchone()
            assert src_row is not None
            state_version, head_revision_id, deleted_at_ms = src_row
            if deleted_at_ms is not None:
                raise ApiError("ALREADY_DELETED", f"source {source_id} is deleted — cannot stage", retryable=False)
            if revision_id != head_revision_id:
                raise ApiError(
                    "STALE_REVISION",
                    f"revision {revision_id} is no longer the source's head — refusing to stage a superseded revision",
                    retryable=False,
                )
            if state_version != job_expected_state_version:
                raise ApiError(
                    "CONFLICT_STALE_REVISION",
                    f"source state has changed since job {job_id} was created — refusing to stage a source that has moved on",
                    retryable=True,
                )
            active_generation_id = _insert_staged_generation(
                con, revision_id, profile_key, state_version, now_ms,
                job_id=job_id, lease_owner=lease_owner, lease_ms=lease_ms,
            )
            active_profile_key = profile_key
        elif status == "failed":
            if captured_profile_key is None:
                raise ApiError(
                    "INVALID_JOB_STATE", f"job {job_id} has no captured profile_key — was never staged; "
                    "retry does not apply", retryable=False,
                )
            # CAS FIRST, always — before even looking for a duplicate
            # (ft-airag-arch-astra review 2026-09-10: checking duplicate-
            # existence before CAS let a stale source slip through when no
            # duplicate happened to exist).
            src_row = con.execute(
                "SELECT state_version, head_revision_id, deleted_at_ms FROM sources WHERE source_id = ?",
                (source_id,),
            ).fetchone()
            assert src_row is not None
            state_version, head_revision_id, deleted_at_ms = src_row
            if deleted_at_ms is not None:
                raise ApiError("ALREADY_DELETED", f"source {source_id} is deleted — cannot retry", retryable=False)
            if revision_id != head_revision_id:
                raise ApiError(
                    "STALE_REVISION",
                    f"revision {revision_id} is no longer the source's head — refusing to retry onto a superseded revision",
                    retryable=False,
                )
            if state_version != job_expected_state_version:
                raise ApiError(
                    "CONFLICT_STALE_REVISION",
                    f"source state has changed since job {job_id} was created — refusing to retry a source that has moved on",
                    retryable=True,
                )

            # NEVER silently adopt/execute some OTHER job for this
            # (source_id, revision_id) — it may target a completely
            # different profile (e.g. an independent force_reprocess) or
            # be a not-yet-processed pending-with-no-profile job that
            # would falsely report success with generation_id=None
            # (ft-airag-arch-astra review 2026-09-10, caught by
            # test_retry_never_adopts_an_unrelated_job_for_the_same_
            # revision). If ANY other non-terminal job already covers this
            # revision, refuse with IN_PROGRESS and record NOTHING in the
            # ledger for this attempt — a genuine restart of THIS SAME
            # retry request_id is already served by the idempotency cache-
            # hit above, before this branch is ever reached.
            # Scoped to jobs created against THIS SAME (CAS-validated)
            # expected_state_version — not merely this revision_id: a
            # metadata-only edit bumps state_version without creating a new
            # revision_id, so an OLDER pending/running job on this same
            # revision_id can carry a now-stale expected_state_version —
            # that job can never itself publish (its own CAS is already
            # doomed) and must never permanently block a fresh, valid retry
            # just because it shares revision_id (ft-airag-arch-astra
            # review 2026-09-11, same class of bug found in reindex's
            # guard: test_reindex_contract.py::
            # test_failed_fresh_reindex_can_be_retried_despite_an_obsolete_
            # pending_job). Neither that other job nor this job is touched.
            existing = con.execute(
                "SELECT job_id FROM jobs WHERE source_id = ? AND revision_id = ? AND expected_state_version = ? "
                "AND status IN ('pending', 'running') AND job_id != ? LIMIT 1",
                (source_id, revision_id, state_version, job_id),
            ).fetchone()
            if existing is not None:
                raise ApiError(
                    "IN_PROGRESS",
                    f"another job ({existing[0]}) is already active for this source's current revision — refusing "
                    "to start a second concurrent attempt",
                    retryable=True,
                )

            # A GENUINELY NEW job — the original failed job (status/
            # generation_id/claim_epoch/error) is never mutated, so a
            # replay of whatever original add/update request created it
            # is completely unaffected by this retry (see docstring).
            cur = con.execute(
                "INSERT INTO jobs(source_id, revision_id, kind, status, expected_state_version, created_at_ms, updated_at_ms) "
                "VALUES (?, ?, 'update', 'pending', ?, ?, ?)",
                (source_id, revision_id, state_version, now_ms, now_ms),
            )
            assert cur.lastrowid is not None
            active_job_id = cur.lastrowid
            active_generation_id = _insert_staged_generation(
                con, revision_id, captured_profile_key, state_version, now_ms,
                job_id=active_job_id, lease_owner=lease_owner, lease_ms=lease_ms,
            )
            active_profile_key = captured_profile_key
        elif status not in ("running", "done"):
            raise ApiError("INVALID_JOB_STATE", f"job {job_id} is {status!r} — retry does not apply", retryable=False)

        response: dict[str, object] = {
            "job_id": active_job_id, "generation_id": active_generation_id,
            "original_job_id": job_id, "profile_key": active_profile_key,
        }
        _record_request(con, request_id, fingerprint, "retry", response)
        con.commit()
        return response
    except Exception:
        con.rollback()
        raise


def reindex(
    con: sqlite3.Connection,
    request_id: str,
    collection: str,
    source_key: str,
    expected_revision: str,
    *,
    profile_key: str,
    lease_owner: str | None = None,
    lease_ms: int = DEFAULT_LEASE_MS,
) -> dict[str, object]:
    """P06-04: explicit reindex / profile-transition command. Reprocesses
    the CURRENT head revision's already-stored bytes under `profile_key`
    (same profile: a plain reprocess; a different profile/space: a model
    migration) — never touches `source_revisions`/`sources.media_type`/
    `origin_uri` (no content or metadata mutation). Identified by
    (collection, source_key, expected_revision), not a job_id — `manage
    retry` targets an existing job; this targets a revision.

    Idempotent via its OWN `request_ledger` fingerprint over
    (collection, source_key, expected_revision, profile_key) — deliberately
    NOT derived from freshly re-read content bytes at call time. A
    dedicated fingerprint over these stable, caller-supplied identifiers
    means a replay of the SAME request_id always returns the SAME cached
    response regardless of what happens to the source afterwards
    (including a later real update() moving the head to a different
    revision) — the same replay guarantee add/update/retry already give
    (ft-airag-arch-astra 2026-09-11: do not implement this by internally
    reading the head's current content and delegating into
    `update(force_reprocess=True)` — that would fingerprint on live-read
    bytes and could produce a different recorded fingerprint on a later
    re-entry, breaking replay).

    CAS-checked exactly like update()/delete(): `expected_revision` must
    match the source's CURRENT (source_id, state_version) — a delete/
    restore/metadata edit/prior publish since the caller last observed
    status is CONFLICT_STALE_REVISION, never silently reindexed onto a
    source that moved on.

    `profile_key` is REQUIRED (unlike retry's pending branch, there is no
    "originally captured" profile to fall back to reusing — D-011: no
    automatic model selection) and validated as an actually-registered
    profile BEFORE claiming. It may be the SAME profile (a plain
    reprocess) or a DIFFERENT one (a model/space migration) —
    `publish_generation_with_content` already derives the vec0 space from
    the NEW generation's own profile and deactivates the OLD ready
    generation's vectors in ITS OWN (possibly different) space, so a
    profile transition Just Works through the existing publish path with
    no special-casing here.

    Refuses to start a second concurrent attempt: if another non-terminal
    job (status 'pending'/'running') already covers this exact
    (source_id, head_revision_id), raises IN_PROGRESS and records nothing
    — a genuine restart of THIS SAME request_id is already served by the
    idempotency cache-hit above. This is what keeps concurrent/duplicate
    reindex calls (or a reindex racing another reindex/retry already in
    flight for the same revision) from double-publishing.

    On failure, the pipeline's existing `fail_generation` path marks only
    the NEW generation/job failed — `sources.ready_generation_id` is
    untouched, so the previous ready index keeps serving search
    unchanged, exactly like any other reprocess-in-place failure. A
    failed reindex job is a completely ordinary content-processing job
    (revision_id set, profile_key captured) — `manage retry --job-id`
    already handles retrying it with no reindex-specific code.

    Returns `{"job_id", "generation_id", "revision_id", "profile_key"}` —
    the new job/generation created to carry out this reindex."""
    _require_nonempty_str("request_id", request_id)
    _require_nonempty_str("collection", collection)
    _require_nonempty_str("source_key", source_key)
    _require_nonempty_str("expected_revision", expected_revision)
    if not isinstance(profile_key, str) or not profile_key:
        raise ApiError("VALIDATION_ERROR", "profile_key must be a non-empty string", retryable=False)
    fingerprint = _fingerprint(
        {
            "command": "reindex",
            "collection": collection,
            "source_key": source_key,
            "expected_revision": expected_revision,
            "profile_key": profile_key,
        }
    )

    _ = con.execute("BEGIN IMMEDIATE")
    try:
        cached = _check_idempotency(con, request_id, fingerprint)
        if cached is not None:
            con.rollback()
            return cached

        s = _require_source(con, collection, source_key)
        if s.deleted_at_ms is not None:
            raise ApiError(
                "ALREADY_DELETED", f"source {source_key!r} is deleted — restore before reindexing", retryable=False
            )
        _require_cas_match(s.source_id, s.state_version, expected_revision)
        assert s.head_revision_id is not None

        if con.execute(
            "SELECT 1 FROM processing_profiles WHERE profile_key = ?", (profile_key,)
        ).fetchone() is None:
            raise ApiError("NOT_FOUND", f"processing profile {profile_key!r} not found", retryable=False)

        # Scoped to jobs created against THIS SAME expected_state_version
        # (the one `expected_revision` was just CAS-validated against), not
        # merely this revision_id: a metadata-only edit bumps state_version
        # without creating a new revision_id, so an OLDER pending/running
        # job on this same revision_id can carry a now-stale
        # expected_state_version — that job can never itself publish (its
        # own CAS is already doomed) and must never permanently block a
        # fresh, valid reindex request just because it shares revision_id
        # (ft-airag-arch-astra review 2026-09-11, test_reindex_contract.py
        # obsolete_job cases). The old job itself is left untouched.
        existing = con.execute(
            "SELECT job_id FROM jobs WHERE source_id = ? AND revision_id = ? AND expected_state_version = ? "
            "AND status IN ('pending', 'running') LIMIT 1",
            (s.source_id, s.head_revision_id, s.state_version),
        ).fetchone()
        if existing is not None:
            raise ApiError(
                "IN_PROGRESS",
                f"another job ({existing[0]}) is already active for this source's current revision — refusing "
                "to start a second concurrent reindex",
                retryable=True,
            )

        now_ms = int(time.time() * 1000)
        cur = con.execute(
            "INSERT INTO jobs(source_id, revision_id, kind, status, expected_state_version, created_at_ms, updated_at_ms) "
            "VALUES (?, ?, 'update', 'pending', ?, ?, ?)",
            (s.source_id, s.head_revision_id, s.state_version, now_ms, now_ms),
        )
        assert cur.lastrowid is not None
        job_id = cur.lastrowid
        generation_id = _insert_staged_generation(
            con, s.head_revision_id, profile_key, s.state_version, now_ms,
            job_id=job_id, lease_owner=lease_owner, lease_ms=lease_ms,
        )

        response: dict[str, object] = {
            "job_id": job_id, "generation_id": generation_id,
            "revision_id": s.head_revision_id, "profile_key": profile_key,
        }
        _record_request(con, request_id, fingerprint, "reindex", response)
        con.commit()
        return response
    except Exception:
        con.rollback()
        raise


def add(con: sqlite3.Connection, req: AddRequest, *, profile_key: str | None = None, lease_owner: str | None = None) -> dict[str, object]:
    req.validate()
    content_hash = hashlib.sha256(req.content).hexdigest()
    fingerprint = _fingerprint(
        {
            "command": "add",
            "collection": req.collection,
            "source_key": req.source_key,
            "media_type": req.media_type,
            "origin_uri": req.origin_uri,
            "content_hash": content_hash,
            "explicit_profile_key": req.explicit_profile_key,
        }
    )

    _ = con.execute("BEGIN IMMEDIATE")
    try:
        cached = _check_idempotency(con, req.request_id, fingerprint)
        if cached is not None:
            con.rollback()
            return cached

        collection_id = _get_or_create_collection(con, req.collection)
        existing = con.execute(
            "SELECT deleted_at_ms FROM sources WHERE collection_id = ? AND source_key = ?",
            (collection_id, req.source_key),
        ).fetchone()
        if existing is not None:
            if existing[0] is None:
                raise ApiError(
                    "ALREADY_EXISTS",
                    f"source {req.source_key!r} already exists in collection {req.collection!r} — use update",
                    retryable=False,
                )
            raise ApiError(
                "ALREADY_EXISTS_DELETED",
                f"source {req.source_key!r} exists but is deleted in collection {req.collection!r} — use restore, not add",
                retryable=False,
            )

        now_ms = int(time.time() * 1000)
        cur = con.execute(
            "INSERT INTO sources(collection_id, source_key, origin_uri, media_type, state_version, created_at_ms) "
            "VALUES (?, ?, ?, ?, 1, ?)",
            (collection_id, req.source_key, req.origin_uri, req.media_type, now_ms),
        )
        assert cur.lastrowid is not None
        source_id = cur.lastrowid
        cur = con.execute(
            "INSERT INTO source_revisions(source_id, content_hash, byte_length, content_bytes, media_type, origin_uri, created_at_ms) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (source_id, content_hash, len(req.content), req.content, req.media_type, req.origin_uri, now_ms),
        )
        assert cur.lastrowid is not None
        revision_id = cur.lastrowid
        _ = con.execute(
            "UPDATE sources SET head_revision_id = ? WHERE source_id = ?",
            (revision_id, source_id),
        )
        cur = con.execute(
            "INSERT INTO jobs(source_id, revision_id, kind, status, expected_state_version, created_at_ms, updated_at_ms) "
            "VALUES (?, ?, 'add', 'pending', 1, ?, ?)",
            (source_id, revision_id, now_ms, now_ms),
        )
        assert cur.lastrowid is not None
        job_id = cur.lastrowid
        generation_id: int | None = None
        if profile_key is not None:
            generation_id = _insert_staged_generation(
                con, revision_id, profile_key, 1, now_ms, job_id=job_id, lease_owner=lease_owner
            )
        response: dict[str, object] = {
            "source_id": source_id,
            "revision_id": revision_id,
            "revision_token": encode_revision_token(source_id, 1),
            "state_version": 1,
            "content_hash": content_hash,
            "no_op": False,
            "content_changed": True,
            "head_revision_id": revision_id,
            "ready_generation_id": None,
            "ready_revision_id": None,
            "searchable": False,
            "processing_status": "pending",
            "job_id": job_id,
            "generation_id": generation_id,
        }
        _record_request(con, req.request_id, fingerprint, "add", response)
        con.commit()
        return response
    except Exception:
        con.rollback()
        raise


def update(con: sqlite3.Connection, req: UpdateRequest, *, profile_key: str | None = None, lease_owner: str | None = None) -> dict[str, object]:
    req.validate()
    content_hash = hashlib.sha256(req.content).hexdigest()
    fingerprint = _fingerprint(
        {
            "command": "update",
            "collection": req.collection,
            "source_key": req.source_key,
            "expected_revision": req.expected_revision,
            "media_type": req.media_type,
            "origin_uri": req.origin_uri,
            "content_hash": content_hash,
            "force_reprocess": req.force_reprocess,
            "explicit_profile_key": req.explicit_profile_key,
        }
    )

    _ = con.execute("BEGIN IMMEDIATE")
    try:
        cached = _check_idempotency(con, req.request_id, fingerprint)
        if cached is not None:
            con.rollback()
            return cached

        s = _require_source(con, req.collection, req.source_key)
        if s.deleted_at_ms is not None:
            raise ApiError(
                "ALREADY_DELETED",
                f"source {req.source_key!r} is deleted — restore before updating",
                retryable=False,
            )
        _require_cas_match(s.source_id, s.state_version, req.expected_revision)

        assert s.head_revision_id is not None
        head_row = con.execute(
            "SELECT content_hash FROM source_revisions WHERE revision_id = ?",
            (s.head_revision_id,),
        ).fetchone()
        assert head_row is not None
        head_hash = head_row[0]

        content_changed = content_hash != head_hash
        metadata_changed = req.media_type != s.media_type or (
            req.origin_uri is not None and req.origin_uri != s.origin_uri
        )
        reprocess_queued = req.force_reprocess and not content_changed

        now_ms = int(time.time() * 1000)

        if not content_changed and not metadata_changed and not req.force_reprocess:
            response: dict[str, object] = {
                "source_id": s.source_id,
                "revision_id": s.head_revision_id,
                "revision_token": encode_revision_token(s.source_id, s.state_version),
                "state_version": s.state_version,
                "content_hash": content_hash,
                "no_op": True,
                "content_changed": False,
                "metadata_changed": False,
                "reprocess_queued": False,
                **_resolve_processing_fields(con, s),
            }
        elif content_changed:
            # req.origin_uri of None means "leave the source's existing
            # origin_uri untouched" — that effective value (not the raw,
            # possibly-None request field) is what the NEW revision row
            # must record too, or a fetch of this revision would show
            # origin_uri=None even though the source's own origin_uri was
            # correctly preserved (independently found by owner probe).
            effective_origin_uri = req.origin_uri if req.origin_uri is not None else s.origin_uri
            cur = con.execute(
                "INSERT INTO source_revisions(source_id, content_hash, byte_length, content_bytes, media_type, origin_uri, created_at_ms) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (s.source_id, content_hash, len(req.content), req.content, req.media_type, effective_origin_uri, now_ms),
            )
            assert cur.lastrowid is not None
            new_revision_id = cur.lastrowid
            new_state_version = s.state_version + 1
            _ = con.execute(
                "UPDATE sources SET head_revision_id = ?, state_version = ?, media_type = ?, "
                "origin_uri = ? WHERE source_id = ?",
                (new_revision_id, new_state_version, req.media_type, effective_origin_uri, s.source_id),
            )
            cur = con.execute(
                "INSERT INTO jobs(source_id, revision_id, kind, status, expected_state_version, created_at_ms, updated_at_ms) "
                "VALUES (?, ?, 'update', 'pending', ?, ?, ?)",
                (s.source_id, new_revision_id, new_state_version, now_ms, now_ms),
            )
            assert cur.lastrowid is not None
            job_id = cur.lastrowid
            generation_id: int | None = None
            if profile_key is not None:
                generation_id = _insert_staged_generation(
                    con, new_revision_id, profile_key, new_state_version, now_ms, job_id=job_id, lease_owner=lease_owner
                )
            # ready_generation_id is untouched by update() — only
            # publish_generation ever changes it. Reusing s's actual value
            # here (not hardcoding None) keeps this response's searchable/
            # processing_status consistent with what get_status() would
            # independently compute right after this commits (independently
            # found by owner probe: a hardcoded None here made update()'s
            # own response claim searchable=False even when an existing
            # ready pointer was untouched and still valid).
            new_s = _SourceRow(
                s.source_id, new_state_version, new_revision_id, s.ready_generation_id, None,
                req.media_type, effective_origin_uri,
            )
            response = {
                "source_id": s.source_id,
                "revision_id": new_revision_id,
                "revision_token": encode_revision_token(s.source_id, new_state_version),
                "state_version": new_state_version,
                "content_hash": content_hash,
                "no_op": False,
                "content_changed": True,
                "metadata_changed": metadata_changed,
                "reprocess_queued": False,
                "job_id": job_id,
                "generation_id": generation_id,
                **_resolve_processing_fields(con, new_s),
            }
        else:
            # Content unchanged: metadata_changed and/or force_reprocess.
            # D-001: unchanged bytes never create a new revision — a
            # metadata edit updates `sources` in place, and force_reprocess
            # queues a new processing job against the SAME head revision.
            new_state_version = s.state_version
            if metadata_changed:
                new_state_version = s.state_version + 1
                _ = con.execute(
                    "UPDATE sources SET media_type = ?, origin_uri = COALESCE(?, origin_uri), "
                    "state_version = ? WHERE source_id = ?",
                    (req.media_type, req.origin_uri, new_state_version, s.source_id),
                )
            reprocess_job_id: int | None = None
            reprocess_generation_id: int | None = None
            if reprocess_queued:
                cur = con.execute(
                    "INSERT INTO jobs(source_id, revision_id, kind, status, expected_state_version, created_at_ms, updated_at_ms) "
                    "VALUES (?, ?, 'update', 'pending', ?, ?, ?)",
                    (s.source_id, s.head_revision_id, new_state_version, now_ms, now_ms),
                )
                assert cur.lastrowid is not None
                reprocess_job_id = cur.lastrowid
                if profile_key is not None:
                    assert s.head_revision_id is not None
                    reprocess_generation_id = _insert_staged_generation(
                        con, s.head_revision_id, profile_key, new_state_version, now_ms, job_id=reprocess_job_id, lease_owner=lease_owner
                    )
            new_s = _SourceRow(
                s.source_id,
                new_state_version,
                s.head_revision_id,
                s.ready_generation_id,
                None,
                req.media_type if metadata_changed else s.media_type,
                (req.origin_uri or s.origin_uri) if metadata_changed else s.origin_uri,
            )
            response = {
                "source_id": s.source_id,
                "revision_id": s.head_revision_id,
                "revision_token": encode_revision_token(s.source_id, new_state_version),
                "state_version": new_state_version,
                "content_hash": content_hash,
                "no_op": False,
                "content_changed": False,
                "metadata_changed": metadata_changed,
                "reprocess_queued": reprocess_queued,
                "job_id": reprocess_job_id,
                "generation_id": reprocess_generation_id,
                **_resolve_processing_fields(con, new_s),
            }

        _record_request(con, req.request_id, fingerprint, "update", response)
        con.commit()
        return response
    except Exception:
        con.rollback()
        raise


def _find_vec_table_for_generation(con: sqlite3.Connection, generation_id: int) -> str | None:
    """Returns the vec0 table name backing this generation's embedding
    space, or None if the generation has no profile/space (never went
    through the real-content publish path) or that table was never
    actually created (e.g. a generation staged then failed before
    publish)."""
    row = con.execute(
        "SELECT pp.space_id FROM generations g JOIN processing_profiles pp ON g.profile_key = pp.profile_key "
        "WHERE g.generation_id = ?",
        (generation_id,),
    ).fetchone()
    if row is None:
        return None
    from airag import embeddings  # lazy — see module docstring's import note

    table = embeddings.vec_space_table_name(row[0])
    exists = con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)).fetchone()
    return table if exists is not None else None


def _set_generation_visibility(con: sqlite3.Connection, generation_id: int, source_id: int, *, visible: bool) -> None:
    """Atomically flips FTS/vector search visibility for one generation's
    chunks — used by `delete`/`restore` (p03-publication-review.txt item 2:
    "current store.delete/restore only flips source state and does not yet
    update FTS/vector visibility") so a deleted source's content is
    actually removed from the searchable index, not merely flagged at the
    API-response layer while still fully present underneath. `visible=
    False` DELETEs the fts_chunks rows (FTS5 has no per-row disable —
    matches this package's existing convention of never leaving non-
    current rows in the FTS index) and sets vec0 `active=0`; `visible=True`
    re-inserts fts_chunks rows from the PERMANENTLY-RETAINED `chunks.text`
    (never re-derived/re-embedded) and sets vec0 `active=1`. Caller must
    already hold the write lock (BEGIN IMMEDIATE)."""
    collection_row = con.execute("SELECT collection_id FROM sources WHERE source_id = ?", (source_id,)).fetchone()
    assert collection_row is not None
    collection_id = collection_row[0]

    if not visible:
        _ = con.execute(
            "DELETE FROM fts_chunks WHERE chunk_id IN (SELECT chunk_id FROM chunks WHERE generation_id = ?)",
            (generation_id,),
        )
    else:
        rows = con.execute(
            "SELECT chunk_id, text FROM chunks WHERE generation_id = ? ORDER BY chunk_index", (generation_id,)
        ).fetchall()
        for chunk_id, text in rows:
            _ = con.execute(
                "INSERT INTO fts_chunks(rowid, text, chunk_id, source_id, collection_id) VALUES (?, ?, ?, ?, ?)",
                (chunk_id, text, chunk_id, source_id, collection_id),
            )

    vec_table = _find_vec_table_for_generation(con, generation_id)
    if vec_table is not None:
        from airag.db import vecext
        if not vecext.try_load_vec0(con):
            raise ApiError("VEC0_UNAVAILABLE", "sqlite_vec extension could not be loaded", retryable=False)
        _ = con.execute(
            f"UPDATE {vec_table} SET active = ? WHERE generation_id = ?", (1 if visible else 0, generation_id)
        )


def delete(con: sqlite3.Connection, req: DeleteRequest) -> dict[str, object]:
    req.validate()
    fingerprint = _fingerprint(
        {
            "command": "delete",
            "collection": req.collection,
            "source_key": req.source_key,
            "expected_revision": req.expected_revision,
        }
    )

    _ = con.execute("BEGIN IMMEDIATE")
    try:
        cached = _check_idempotency(con, req.request_id, fingerprint)
        if cached is not None:
            con.rollback()
            return cached

        s = _require_source(con, req.collection, req.source_key)
        if s.deleted_at_ms is not None:
            raise ApiError(
                "ALREADY_DELETED", f"source {req.source_key!r} is already deleted", retryable=False
            )
        _require_cas_match(s.source_id, s.state_version, req.expected_revision)

        now_ms = int(time.time() * 1000)
        new_state_version = s.state_version + 1
        _ = con.execute(
            "UPDATE sources SET deleted_at_ms = ?, state_version = ? WHERE source_id = ?",
            (now_ms, new_state_version, s.source_id),
        )
        if s.ready_generation_id is not None:
            _set_generation_visibility(con, s.ready_generation_id, s.source_id, visible=False)
        _ = con.execute(
            "INSERT INTO jobs(source_id, kind, status, created_at_ms, updated_at_ms) "
            "VALUES (?, 'delete', 'done', ?, ?)",
            (s.source_id, now_ms, now_ms),
        )
        response: dict[str, object] = {
            "source_id": s.source_id,
            "revision_token": encode_revision_token(s.source_id, new_state_version),
            "state_version": new_state_version,
            "deleted": True,
            "searchable": False,
            "processing_status": "not_indexed",
        }
        _record_request(con, req.request_id, fingerprint, "delete", response)
        con.commit()
        return response
    except Exception:
        con.rollback()
        raise


def restore(con: sqlite3.Connection, req: RestoreRequest) -> dict[str, object]:
    req.validate()
    fingerprint = _fingerprint(
        {
            "command": "restore",
            "collection": req.collection,
            "source_key": req.source_key,
            "expected_revision": req.expected_revision,
        }
    )

    _ = con.execute("BEGIN IMMEDIATE")
    try:
        cached = _check_idempotency(con, req.request_id, fingerprint)
        if cached is not None:
            con.rollback()
            return cached

        s = _require_source(con, req.collection, req.source_key)
        if s.deleted_at_ms is None:
            raise ApiError(
                "NOT_DELETED", f"source {req.source_key!r} is not deleted", retryable=False
            )
        _require_cas_match(s.source_id, s.state_version, req.expected_revision)

        now_ms = int(time.time() * 1000)
        new_state_version = s.state_version + 1
        _ = con.execute(
            "UPDATE sources SET deleted_at_ms = NULL, state_version = ? WHERE source_id = ?",
            (new_state_version, s.source_id),
        )
        if s.ready_generation_id is not None:
            _set_generation_visibility(con, s.ready_generation_id, s.source_id, visible=True)
        _ = con.execute(
            "INSERT INTO jobs(source_id, kind, status, created_at_ms, updated_at_ms) "
            "VALUES (?, 'restore', 'done', ?, ?)",
            (s.source_id, now_ms, now_ms),
        )
        new_s = _SourceRow(
            s.source_id, new_state_version, s.head_revision_id, s.ready_generation_id, None, s.media_type, s.origin_uri
        )
        response: dict[str, object] = {
            "source_id": s.source_id,
            "revision_token": encode_revision_token(s.source_id, new_state_version),
            "state_version": new_state_version,
            "deleted": False,
            **_resolve_processing_fields(con, new_s),
        }
        _record_request(con, req.request_id, fingerprint, "restore", response)
        con.commit()
        return response
    except Exception:
        con.rollback()
        raise


# ---------------------------------------------------------- staging/publish
#
# P-02 boundary for P-03: nothing here does real chunking/embedding — these
# are the durable primitives P-03 will drive with real processing output.


def stage_generation(
    con: sqlite3.Connection,
    revision_id: int,
    profile_key: str,
    expected_revision: str,
    *,
    job_id: int | None = None,
) -> dict[str, object]:
    """Records a new (immutable) generation attempt as 'staged', capturing
    the source's CAS state_version *now* — publish_generation will check
    against this captured value later, never a value the caller supplies
    fresh at publish time. Requires the source to be active (not deleted)
    and the revision being staged to be the CURRENT head — staging a
    superseded revision is refused, not silently accepted.
    """
    _ = con.execute("BEGIN IMMEDIATE")
    try:
        rev_row = con.execute(
            "SELECT source_id FROM source_revisions WHERE revision_id = ?", (revision_id,)
        ).fetchone()
        if rev_row is None:
            raise ApiError("NOT_FOUND", f"revision {revision_id} not found", retryable=False)
        source_id = rev_row[0]

        src_row = con.execute(
            "SELECT state_version, head_revision_id, deleted_at_ms FROM sources WHERE source_id = ?",
            (source_id,),
        ).fetchone()
        assert src_row is not None
        state_version, head_revision_id, deleted_at_ms = src_row
        if deleted_at_ms is not None:
            raise ApiError(
                "ALREADY_DELETED", f"source {source_id} is deleted — cannot stage", retryable=False
            )
        expected_source_id, expected_state_version = decode_revision_token(expected_revision)
        if expected_source_id != source_id or expected_state_version != state_version:
            raise ApiError(
                "CONFLICT_STALE_REVISION",
                "expected_revision does not match the source's current state",
                retryable=True,
            )
        if revision_id != head_revision_id:
            raise ApiError(
                "STALE_REVISION",
                f"revision {revision_id} is not the current head revision ({head_revision_id}) — refusing to stage a superseded revision",
                retryable=False,
            )

        if job_id is not None:
            # A job may be claimed (linked to a generation) exactly once.
            # Re-checked fresh here inside this BEGIN IMMEDIATE transaction,
            # so two concurrent stage_generation calls racing to claim the
            # SAME job_id serialize on the write lock and the second one
            # sees generation_id already set — rejected, not silently
            # overwritten (independently reproduced: staging a second time
            # against an already-'done' job rewrote it back to 'running',
            # destroying its completion history).
            job_row = con.execute(
                "SELECT source_id, revision_id, status, generation_id FROM jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            if job_row is None:
                raise ApiError("NOT_FOUND", f"job {job_id} not found", retryable=False)
            j_source_id, j_revision_id, j_status, j_generation_id = job_row
            if j_source_id != source_id or j_revision_id != revision_id:
                raise ApiError(
                    "VALIDATION_ERROR",
                    f"job {job_id} does not match the source/revision being staged",
                    retryable=False,
                )
            if j_status != "pending" or j_generation_id is not None:
                raise ApiError(
                    "INVALID_JOB_STATE",
                    f"job {job_id} is {j_status!r} (generation_id={j_generation_id!r}) — not claimable; "
                    "a completed/running/failed job cannot be silently reassigned to a new attempt",
                    retryable=False,
                )

        now_ms = int(time.time() * 1000)
        generation_id = _insert_staged_generation(
            con, revision_id, profile_key, state_version, now_ms, job_id=job_id
        )

        con.commit()
        return {
            "generation_id": generation_id,
            "revision_id": revision_id,
            "status": "staged",
            "expected_state_version": state_version,
        }
    except Exception:
        con.rollback()
        raise


def publish_generation(con: sqlite3.Connection, generation_id: int) -> dict[str, object]:
    """Atomically moves `sources.ready_generation_id` to `generation_id`,
    only if ALL of: the generation is still 'staged' (never republishes an
    already-ready/failed generation); the source is not deleted; the
    generation's revision is still the source's current head; and the
    source's CURRENT state_version still equals the `expected_state_version`
    captured by `stage_generation` — never a caller-supplied value, closing
    the gap where a stale generation could publish if the caller simply
    refreshed its token. Any linked job's status flips to 'done' in the
    same transaction as the ready pointer.
    """
    _ = con.execute("BEGIN IMMEDIATE")
    try:
        gen_row = con.execute(
            "SELECT g.revision_id, g.status, g.expected_state_version, r.source_id "
            "FROM generations g JOIN source_revisions r ON g.revision_id = r.revision_id "
            "WHERE g.generation_id = ?",
            (generation_id,),
        ).fetchone()
        if gen_row is None:
            raise ApiError("NOT_FOUND", f"generation {generation_id} not found", retryable=False)
        _check_claim_fencing(con, generation_id)
        revision_id, status, expected_state_version, source_id = gen_row
        if status != "staged":
            raise ApiError(
                "INVALID_GENERATION_STATE",
                f"generation {generation_id} is {status!r}, not 'staged' — cannot publish",
                retryable=False,
            )

        src_row = con.execute(
            "SELECT state_version, head_revision_id, deleted_at_ms FROM sources WHERE source_id = ?",
            (source_id,),
        ).fetchone()
        assert src_row is not None
        state_version, head_revision_id, deleted_at_ms = src_row
        if deleted_at_ms is not None:
            raise ApiError(
                "ALREADY_DELETED", f"source {source_id} is deleted — cannot publish", retryable=False
            )
        if state_version != expected_state_version:
            raise ApiError(
                "CONFLICT_STALE_REVISION",
                "source state has changed since this generation was staged — publish refused",
                retryable=True,
            )
        if revision_id != head_revision_id:
            raise ApiError(
                "STALE_REVISION",
                f"generation {generation_id}'s revision is no longer the source's head — publish refused",
                retryable=False,
            )

        now_ms = int(time.time() * 1000)
        # Publication itself advances state_version. Without this, two
        # generations staged against the SAME expected_state_version (e.g.
        # a first attempt and a retry, staged back-to-back before either
        # published) both keep passing the CAS check after the first one
        # publishes — nothing about "source state" changed from either
        # generation's point of view, so a second, unrelated publish could
        # silently overwrite the first with an older/worse result out of
        # order. Bumping state_version here means the second publish now
        # sees state_version != its own captured expected_state_version and
        # is correctly refused (independently found by owner probe: g1/g2
        # staged against one token both published successfully, g1
        # clobbering g2's ready pointer).
        new_state_version = state_version + 1
        _ = con.execute(
            "UPDATE generations SET status = 'ready', published_at_ms = ? WHERE generation_id = ?",
            (now_ms, generation_id),
        )
        _ = con.execute(
            "UPDATE sources SET ready_generation_id = ?, state_version = ? WHERE source_id = ?",
            (generation_id, new_state_version, source_id),
        )
        _ = con.execute(
            "UPDATE jobs SET status = 'done', updated_at_ms = ? WHERE generation_id = ?",
            (now_ms, generation_id),
        )
        con.commit()
        return {
            "source_id": source_id,
            "generation_id": generation_id,
            "status": "ready",
            "state_version": new_state_version,
            "revision_token": encode_revision_token(source_id, new_state_version),
        }
    except Exception:
        con.rollback()
        raise


def publish_generation_with_content(
    con: sqlite3.Connection,
    generation_id: int,
    *,
    standard_md: str,
    structured_json: dict[str, object],
    chunk_rows: list[dict[str, object]],
    space_id: int,
    vectors: list[bytes],
    final_response_extra: dict[str, object] | None = None,
) -> dict[str, object]:
    """The P-03-B real-content publish path: everything `publish_generation`
    does (ready-pointer CAS move, fencing, job completion) PLUS, in the SAME
    transaction: writes `normalized_documents` + `chunks` for this
    generation, replaces `fts_chunks` (deletes the OLD ready generation's
    rows, inserts this generation's — D-010: never leaves stale rows
    behind a WHERE filter, which would skew BM25's corpus-wide term
    statistics), and activates this generation's vectors in the space's
    vec0 table while deactivating the old ready generation's (D-010:
    publish/deactivate must change atomically with the ready pointer and
    FTS visibility — never a source with content 'ready' but its vectors
    still pointing at stale/deleted data).

    Writes the caller-supplied `final_response_extra` (merged over a base
    shape this function derives) into `jobs.final_response_json` as an
    IMMUTABLE completion snapshot — the exact response an api.py-level
    replay of the same request must return, forever, never recomputed live
    from current state (see module docstring's P-03-B section and
    schema.py's v4 docstring).

    `chunk_rows` are plain dicts (`{"text", "token_count", "anchor"}`), NOT
    `chunking.ChunkRecord` — store.py does not import chunking.py, to keep
    the storage layer independent of the normalization/chunking library
    choice. `vectors` are already float32-packed bytes (embeddings.py's
    `_validate_and_pack` output) in the SAME order as `chunk_rows`.

    Caller must already have ensured the vec0 table exists for `space_id`
    (`embeddings.ensure_vec_space_table`) BEFORE calling this — that CREATE
    VIRTUAL TABLE IF NOT EXISTS is DDL best issued as its own autocommitted
    statement outside this write transaction, matching this package's
    existing FTS5/vec0 table-creation convention (see tests/
    test_fts5_vec0_data.py)."""
    from airag import embeddings  # lazy — see module docstring's import note

    if len(chunk_rows) != len(vectors):
        raise ValueError(f"chunk_rows ({len(chunk_rows)}) and vectors ({len(vectors)}) length mismatch")

    _ = con.execute("BEGIN IMMEDIATE")
    try:
        gen_row = con.execute(
            "SELECT g.revision_id, g.status, g.expected_state_version, r.source_id, g.profile_key "
            "FROM generations g JOIN source_revisions r ON g.revision_id = r.revision_id "
            "WHERE g.generation_id = ?",
            (generation_id,),
        ).fetchone()
        if gen_row is None:
            raise ApiError("NOT_FOUND", f"generation {generation_id} not found", retryable=False)
        _check_claim_fencing(con, generation_id)
        revision_id, status, expected_state_version, source_id, gen_profile_key = gen_row
        if status != "staged":
            raise ApiError(
                "INVALID_GENERATION_STATE",
                f"generation {generation_id} is {status!r}, not 'staged' — cannot publish",
                retryable=False,
            )

        # p03-publication-review.txt item 1: a caller could otherwise pass
        # an unrelated same-dimension space_id and publish vectors into a
        # model space that does not match this generation's own immutable
        # processing profile. Derive the AUTHORITATIVE space from the
        # profile and require it to match what the caller passed.
        profile_row = con.execute(
            "SELECT space_id FROM processing_profiles WHERE profile_key = ?", (gen_profile_key,)
        ).fetchone()
        if profile_row is None:
            raise ApiError(
                "NOT_FOUND", f"processing profile {gen_profile_key!r} not found for generation {generation_id}",
                retryable=False,
            )
        if profile_row[0] != space_id:
            raise ApiError(
                "VALIDATION_ERROR",
                f"space_id {space_id} does not match generation {generation_id}'s own profile space "
                f"{profile_row[0]} — refusing to publish vectors into an unrelated embedding space",
                retryable=False,
            )
        space_dim_row = con.execute("SELECT dimension FROM embedding_spaces WHERE space_id = ?", (space_id,)).fetchone()
        assert space_dim_row is not None
        expected_byte_len = space_dim_row[0] * 4  # float32
        for i, vec in enumerate(vectors):
            if len(vec) != expected_byte_len:
                raise ApiError(
                    "DIMENSION_MISMATCH",
                    f"vector {i} is {len(vec)} bytes, expected {expected_byte_len} for a "
                    f"{space_dim_row[0]}-dim float32 space — refusing to publish a malformed vector",
                    retryable=False,
                )

        src_row = con.execute(
            "SELECT state_version, head_revision_id, deleted_at_ms, ready_generation_id, collection_id "
            "FROM sources WHERE source_id = ?",
            (source_id,),
        ).fetchone()
        assert src_row is not None
        state_version, head_revision_id, deleted_at_ms, old_ready_generation_id, collection_id = src_row
        if deleted_at_ms is not None:
            raise ApiError(
                "ALREADY_DELETED", f"source {source_id} is deleted — cannot publish", retryable=False
            )
        if state_version != expected_state_version:
            raise ApiError(
                "CONFLICT_STALE_REVISION",
                "source state has changed since this generation was staged — publish refused",
                retryable=True,
            )
        if revision_id != head_revision_id:
            raise ApiError(
                "STALE_REVISION",
                f"generation {generation_id}'s revision is no longer the source's head — publish refused",
                retryable=False,
            )

        now_ms = int(time.time() * 1000)

        _ = con.execute(
            "INSERT INTO normalized_documents(generation_id, standard_md, structured_json, created_at_ms) "
            "VALUES (?, ?, ?, ?)",
            (generation_id, standard_md, json.dumps(structured_json, ensure_ascii=False), now_ms),
        )

        chunk_ids: list[int] = []
        for idx, row in enumerate(chunk_rows):
            cur = con.execute(
                "INSERT INTO chunks(generation_id, chunk_index, text, token_count, anchor_json, created_at_ms) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (generation_id, idx, row["text"], row["token_count"], json.dumps(row["anchor"], ensure_ascii=False), now_ms),
            )
            assert cur.lastrowid is not None
            chunk_ids.append(cur.lastrowid)

        from airag import relations
        relations.persist_generation(con, generation_id)

        if old_ready_generation_id is not None:
            _ = con.execute(
                "DELETE FROM fts_chunks WHERE chunk_id IN (SELECT chunk_id FROM chunks WHERE generation_id = ?)",
                (old_ready_generation_id,),
            )
        for chunk_id, row in zip(chunk_ids, chunk_rows):
            _ = con.execute(
                "INSERT INTO fts_chunks(rowid, text, chunk_id, source_id, collection_id) VALUES (?, ?, ?, ?, ?)",
                (chunk_id, row["text"], chunk_id, source_id, collection_id),
            )

        vec_table = embeddings.vec_space_table_name(space_id)
        if old_ready_generation_id is not None:
            # p03-publication-review.txt item 2: the OLD ready generation's
            # vectors live in ITS OWN profile's space table, which can
            # differ from the NEW generation's space (a model/space
            # migration) — deactivating only `vec_table` would leave the
            # old space's rows silently active forever after a migration.
            old_space_row = con.execute(
                "SELECT pp.space_id FROM generations g JOIN processing_profiles pp ON g.profile_key = pp.profile_key "
                "WHERE g.generation_id = ?",
                (old_ready_generation_id,),
            ).fetchone()
            if old_space_row is not None:
                old_vec_table = embeddings.vec_space_table_name(old_space_row[0])
                _ = con.execute(
                    f"UPDATE {old_vec_table} SET active = 0 WHERE generation_id = ?", (old_ready_generation_id,)
                )
        for chunk_id, vec in zip(chunk_ids, vectors):
            _ = con.execute(
                f"INSERT INTO {vec_table}(chunk_id, embedding, source_id, collection_id, generation_id, active) "
                "VALUES (?, ?, ?, ?, ?, 1)",
                (chunk_id, vec, source_id, collection_id, generation_id),
            )

        new_state_version = state_version + 1
        _ = con.execute(
            "UPDATE generations SET status = 'ready', published_at_ms = ? WHERE generation_id = ?",
            (now_ms, generation_id),
        )
        _ = con.execute(
            "UPDATE sources SET ready_generation_id = ?, state_version = ? WHERE source_id = ?",
            (generation_id, new_state_version, source_id),
        )

        # p03-publication-review.txt item 3: an empty document (zero
        # chunks) must report an honest non-searchable status, not a
        # fabricated "ready and searchable" — there is nothing to find.
        # item 4: final_response_extra is caller METADATA ONLY — it must
        # never be able to overwrite the AUTHORITATIVE fields this
        # function itself just confirmed (source_id/generation_id/
        # revision_id/state_version/revision_token/searchable/
        # processing_status/chunk_count). Passing a stale storage receipt
        # as extra must not silently replay ITS old token instead of the
        # real post-publication one — that is exactly the replay bug this
        # layer exists to prevent.
        AUTHORITATIVE_KEYS = frozenset({
            "source_id", "generation_id", "revision_id", "status", "state_version",
            "revision_token", "chunk_count", "searchable", "processing_status",
        })
        if final_response_extra:
            collision = AUTHORITATIVE_KEYS & final_response_extra.keys()
            if collision:
                raise ValueError(
                    f"final_response_extra must not set authoritative field(s) {sorted(collision)} — "
                    "those are computed by publish_generation_with_content itself"
                )
        final_response: dict[str, object] = dict(final_response_extra) if final_response_extra else {}
        final_response.update({
            "source_id": source_id,
            "generation_id": generation_id,
            "revision_id": revision_id,
            "status": "ready",
            "state_version": new_state_version,
            "revision_token": encode_revision_token(source_id, new_state_version),
            "chunk_count": len(chunk_rows),
            "searchable": len(chunk_rows) > 0,
            "processing_status": "ready" if chunk_rows else "ready_empty",
        })

        _ = con.execute(
            "UPDATE jobs SET status = 'done', final_response_json = ?, updated_at_ms = ? WHERE generation_id = ?",
            (json.dumps(final_response, ensure_ascii=False), now_ms, generation_id),
        )
        con.commit()
        return final_response
    except Exception:
        con.rollback()
        raise


def fail_generation(
    con: sqlite3.Connection, generation_id: int, error_message: str, *, final_error: dict[str, object] | None = None,
) -> dict[str, object]:
    """Marks a staged generation as failed. Never touches
    `sources.ready_generation_id` — any previously-published, still-ready
    generation's content remains searchable exactly as before."""
    _ = con.execute("BEGIN IMMEDIATE")
    try:
        row = con.execute(
            "SELECT status FROM generations WHERE generation_id = ?", (generation_id,)
        ).fetchone()
        if row is None:
            raise ApiError("NOT_FOUND", f"generation {generation_id} not found", retryable=False)
        _check_claim_fencing(con, generation_id)
        if row[0] != "staged":
            raise ApiError(
                "INVALID_GENERATION_STATE",
                f"generation {generation_id} is {row[0]!r}, not 'staged' — cannot fail it",
                retryable=False,
            )
        now_ms = int(time.time() * 1000)
        _ = con.execute(
            "UPDATE generations SET status = 'failed', failed_at_ms = ?, error = ? WHERE generation_id = ?",
            (now_ms, error_message, generation_id),
        )
        _ = con.execute(
            "UPDATE jobs SET status = 'failed', error = ?, updated_at_ms = ? WHERE generation_id = ?",
            (error_message, now_ms, generation_id),
        )
        if final_error is not None:
            _ = con.execute(
                "UPDATE jobs SET final_response_json = ? WHERE generation_id = ?",
                (json.dumps({"processing_status": "failed", "error": final_error}), generation_id),
            )
        con.commit()
        return {"generation_id": generation_id, "status": "failed"}
    except Exception:
        con.rollback()
        raise


# --------------------------------------------------------------------- reads


def get_status(con: sqlite3.Connection, collection: str, source_key: str) -> dict[str, object]:
    _require_nonempty_str("collection", collection)
    _require_nonempty_str("source_key", source_key)
    s = _require_source(con, collection, source_key)
    # Minimal job identification (P06-03 CLI usability, ft-airag-arch-astra
    # 2026-09-10) — the most recent CONTENT-PROCESSING job (revision_id NOT
    # NULL, i.e. never a delete/restore bookkeeping job), so an operator
    # can find a job_id to pass to `manage retry` without touching SQL.
    # Deliberately just identification, not a diagnostic (full operational
    # diagnosis is P06-05, out of scope here).
    job_row = con.execute(
        "SELECT job_id, revision_id, profile_key, status FROM jobs "
        "WHERE source_id = ? AND revision_id IS NOT NULL ORDER BY job_id DESC LIMIT 1",
        (s.source_id,),
    ).fetchone()
    latest_job = (
        {"job_id": job_row[0], "revision_id": job_row[1], "profile_key": job_row[2], "status": job_row[3]}
        if job_row is not None else None
    )
    return {
        "source_id": s.source_id,
        "collection": collection,
        "source_key": source_key,
        "state_version": s.state_version,
        "revision_token": encode_revision_token(s.source_id, s.state_version),
        "deleted": s.deleted_at_ms is not None,
        "media_type": s.media_type,
        "origin_uri": s.origin_uri,
        "latest_job": latest_job,
        **_resolve_processing_fields(con, s),
    }


def list_sources(
    con: sqlite3.Connection, collection: str, *, include_deleted: bool = False
) -> dict[str, object]:
    _require_nonempty_str("collection", collection)
    if not isinstance(include_deleted, bool):
        raise ApiError("VALIDATION_ERROR", "include_deleted must be a bool", retryable=False)
    row = con.execute("SELECT collection_id FROM collections WHERE name = ?", (collection,)).fetchone()
    if row is None:
        return {"collection": collection, "sources": []}
    collection_id = row[0]
    query = (
        "SELECT source_id, source_key, state_version, head_revision_id, ready_generation_id, deleted_at_ms, media_type, origin_uri "
        "FROM sources WHERE collection_id = ?"
    )
    params: tuple[object, ...] = (collection_id,)
    if not include_deleted:
        query += " AND deleted_at_ms IS NULL"
    rows = con.execute(query + " ORDER BY source_key", params).fetchall()
    sources = []
    for r in rows:
        s = _SourceRow(r[0], r[2], r[3], r[4], r[5], r[6], r[7])
        sources.append(
            {
                "source_id": s.source_id,
                "source_key": r[1],
                "state_version": s.state_version,
                "revision_token": encode_revision_token(s.source_id, s.state_version),
                "deleted": s.deleted_at_ms is not None,
                **_resolve_processing_fields(con, s),
            }
        )
    return {"collection": collection, "sources": sources}


def fetch_original(
    con: sqlite3.Connection,
    collection: str,
    source_key: str,
    *,
    revision_id: int | None = None,
    include_bytes: bool = False,
) -> dict[str, object]:
    """`include_bytes` is explicit opt-in — the default response never
    SELECTs the content BLOB into memory at all. `revision_id` selects a
    specific (possibly historical, no longer head) revision belonging to
    this source; a revision_id belonging to a DIFFERENT source is refused,
    not silently served."""
    _require_nonempty_str("collection", collection)
    _require_nonempty_str("source_key", source_key)
    if revision_id is not None and not isinstance(revision_id, int):
        raise ApiError("VALIDATION_ERROR", "revision_id must be an int or None", retryable=False)
    if not isinstance(include_bytes, bool):
        raise ApiError("VALIDATION_ERROR", "include_bytes must be a bool", retryable=False)
    s = _require_source(con, collection, source_key)
    target_revision_id = revision_id if revision_id is not None else s.head_revision_id
    if target_revision_id is None:
        raise ApiError(
            "NOT_FOUND", f"source {source_key!r} has no stored revision", retryable=False
        )

    row = con.execute(
        "SELECT source_id, content_hash, byte_length, media_type, origin_uri, created_at_ms "
        "FROM source_revisions WHERE revision_id = ?",
        (target_revision_id,),
    ).fetchone()
    if row is None or row[0] != s.source_id:
        raise ApiError(
            "NOT_FOUND",
            f"revision {target_revision_id} does not belong to source {source_key!r} in collection {collection!r}",
            retryable=False,
        )
    _, content_hash, byte_length, rev_media_type, rev_origin_uri, created_at_ms = row

    result: dict[str, object] = {
        "source_id": s.source_id,
        "revision_id": target_revision_id,
        "is_head": target_revision_id == s.head_revision_id,
        "revision_token": encode_revision_token(s.source_id, s.state_version),
        "content_hash": content_hash,
        "byte_length": byte_length,
        "media_type": rev_media_type,
        "origin_uri": rev_origin_uri,
        "created_at_ms": created_at_ms,
        "deleted": s.deleted_at_ms is not None,
        **_resolve_processing_fields(con, s),
    }
    if include_bytes:
        blob_row = con.execute(
            "SELECT content_bytes FROM source_revisions WHERE revision_id = ?",
            (target_revision_id,),
        ).fetchone()
        assert blob_row is not None
        result["content_base64"] = base64.b64encode(blob_row[0]).decode("ascii")
    return result
