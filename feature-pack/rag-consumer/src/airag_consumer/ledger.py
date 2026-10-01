"""SQLCipher event receipts and byte checkpoints committed in one transaction.

This accepts normalized JSONL bytes, not file paths or native agent rollouts.
File-incarnation and prefix verification remain the source adapter's job.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
import re
from pathlib import Path

import sqlcipher3 as sqlite

from .events import AccessScope, EventError
from .jsonl import read_batch
from .redaction import POLICY_VERSION, redact_event, redact_text


ENGINE = "airag-consumer-ledger-v1"
_SCHEMA = (
    "CREATE TABLE meta (engine TEXT NOT NULL)",
    """CREATE TABLE sources (
        source_id TEXT PRIMARY KEY, incarnation TEXT NOT NULL,
        tenant_id TEXT NOT NULL, project_id TEXT NOT NULL, stream_id TEXT NOT NULL,
        policy_version TEXT NOT NULL, next_offset INTEGER NOT NULL CHECK(next_offset >= 0),
        chain_digest TEXT NOT NULL)""",
    """CREATE TABLE events (
        event_key TEXT PRIMARY KEY, fingerprint TEXT NOT NULL,
        policy_version TEXT NOT NULL, redacted_json BLOB NOT NULL,
        audit_rules TEXT NOT NULL, ordering_key TEXT NOT NULL UNIQUE,
        has_public_text INTEGER NOT NULL CHECK(has_public_text IN (0,1)))""",
    """CREATE TABLE deliveries (
        source_id TEXT NOT NULL REFERENCES sources(source_id),
        start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL,
        span_digest TEXT NOT NULL, record_count INTEGER NOT NULL,
        PRIMARY KEY(source_id, start_offset, end_offset))""",
    """CREATE TABLE records (
        source_id TEXT NOT NULL REFERENCES sources(source_id),
        start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL,
        event_key TEXT NOT NULL REFERENCES events(event_key),
        PRIMARY KEY(source_id, start_offset))""",
    """CREATE TABLE rejections (
        source_id TEXT NOT NULL REFERENCES sources(source_id),
        start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL,
        span_digest TEXT NOT NULL, reason_code TEXT NOT NULL, policy_version TEXT NOT NULL,
        validation_code TEXT NOT NULL,
        PRIMARY KEY(source_id, start_offset, end_offset))""",
)


@dataclass(frozen=True)
class Receipt:
    committed_offset: int
    inserted_events: int
    replayed_events: int
    pending_bytes: int


@dataclass(frozen=True)
class SkipReceipt:
    committed_offset: int
    reason_code: str
    replayed: bool
    accepted_events: int = 0
    coverage_gap: bool = True


def _identity(value: object) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > 1024:
        raise EventError("INVALID_SOURCE_IDENTITY")
    if value != value.strip() or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise EventError("INVALID_SOURCE_IDENTITY")
    clean, hits = redact_text(value)
    if clean != value or hits:
        raise EventError("SENSITIVE_SOURCE_IDENTITY")
    return value


def _hash(value: object) -> str:
    return hashlib.sha256(json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), allow_nan=False,
    ).encode("utf-8")).hexdigest()


class Ledger:
    def __init__(self, connection: sqlite.Connection) -> None:
        self._con = connection

    def close(self) -> None:
        self._con.close()

    def __enter__(self) -> Ledger:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def checkpoint(self, source_id: str) -> int | None:
        row = self._con.execute(
            "SELECT next_offset FROM sources WHERE source_id=?", (_identity(source_id),),
        ).fetchone()
        return None if row is None else row[0]

    def rejection_count(self, source_id: str) -> int:
        return self._con.execute(
            "SELECT count(*) FROM rejections WHERE source_id=?", (_identity(source_id),),
        ).fetchone()[0]

    def _bind_source(
        self, source_id: str, incarnation: str, scope: AccessScope, start_offset: int,
    ) -> tuple:
        bound = (incarnation, scope.tenant_id, scope.project_id, scope.stream_id, POLICY_VERSION)
        row = self._con.execute(
            """SELECT incarnation,tenant_id,project_id,stream_id,policy_version,
                      next_offset,chain_digest FROM sources WHERE source_id=?""",
            (source_id,),
        ).fetchone()
        if row is None:
            if start_offset != 0:
                raise EventError("CHECKPOINT_GAP")
            self._con.execute("INSERT INTO sources VALUES (?,?,?,?,?,?,?,?)",
                              (source_id, *bound, 0, ""))
            row = (*bound, 0, "")
        if row[:5] != bound:
            raise EventError("SOURCE_BINDING_MISMATCH")
        return row

    def skip_rejected_record(
        self, data: bytes, *, source_id: str, incarnation: str, expected_scope: AccessScope,
        start_offset: int, expected_sha256: str, acknowledge_gap: bool = False,
        source_reason_code: str | None = None,
    ) -> SkipReceipt:
        """Deliberately record a verified rejection, never an accepted event.

        Store only reason/digest/range; caller must surface the coverage gap.
        Valid, incomplete, changed, or multi-record input cannot be skipped here.
        Source-integrity verification and human/policy authorization belong to
        the caller; this is not an automatic catch-and-ignore ingestion loop.
        """
        _identity(source_id)
        _identity(incarnation)
        if source_reason_code is not None and (
            not isinstance(source_reason_code, str)
            or re.fullmatch(r"[A-Z][A-Z0-9_]{0,127}", source_reason_code) is None
        ):
            raise EventError("INVALID_SOURCE_REASON_CODE")
        if acknowledge_gap is not True:
            raise EventError("EXPLICIT_GAP_ACKNOWLEDGEMENT_REQUIRED")
        if not isinstance(expected_scope, AccessScope):
            raise EventError("TRUSTED_SCOPE_REQUIRED")
        if type(start_offset) is not int or start_offset < 0:
            raise EventError("INVALID_OFFSET")
        if not isinstance(data, bytes) or not data.endswith(b"\n") or data.count(b"\n") != 1:
            raise EventError("ONE_COMPLETE_RECORD_REQUIRED")
        if len(data) > 1_048_577 or start_offset + len(data) > 2**63 - 1:
            raise EventError("RECORD_TOO_LARGE")
        digest = hashlib.sha256(data).hexdigest()
        if expected_sha256 != digest:
            raise EventError("REJECTED_RECORD_DIGEST_MISMATCH")
        try:
            parsed = read_batch(data, expected_scope=expected_scope, start_offset=start_offset)
            redact_event(parsed.records[0].event)
        except EventError as exc:
            validation_code = getattr(exc, "code", str(exc))
            reason = source_reason_code or validation_code
        else:
            raise EventError("VALID_RECORD_CANNOT_SKIP")
        end = start_offset + len(data)
        con = self._con
        try:
            con.execute("BEGIN IMMEDIATE")
            row = self._bind_source(source_id, incarnation, expected_scope, start_offset)
            previous = con.execute(
                """SELECT span_digest,reason_code,validation_code FROM rejections
                   WHERE source_id=? AND start_offset=? AND end_offset=?""",
                (source_id, start_offset, end),
            ).fetchone()
            if previous is not None:
                if previous != (digest, reason, validation_code):
                    raise EventError("REJECTION_CONFLICT")
                con.execute("COMMIT")
                return SkipReceipt(row[5], reason, True)
            if row[5] != start_offset:
                raise EventError("CHECKPOINT_CONFLICT")
            con.execute("INSERT INTO rejections VALUES (?,?,?,?,?,?,?)",
                        (source_id, start_offset, end, digest, reason, POLICY_VERSION, validation_code))
            chain = _hash([row[6], start_offset, end, digest, "rejected", reason])
            con.execute("UPDATE sources SET next_offset=?,chain_digest=? WHERE source_id=?",
                        (end, chain, source_id))
            con.execute("COMMIT")
            return SkipReceipt(end, reason, False)
        except BaseException as exc:
            if con.in_transaction:
                con.execute("ROLLBACK")
            if isinstance(exc, sqlite.Error):
                raise EventError("LEDGER_TRANSACTION_FAILED") from None
            raise

    def ingest(
        self, data: bytes, *, source_id: str, incarnation: str,
        expected_scope: AccessScope, start_offset: int,
    ) -> Receipt:
        """Return a receipt only after durable commit; never store pending tail."""
        _identity(source_id)
        _identity(incarnation)
        batch = read_batch(data, expected_scope=expected_scope, start_offset=start_offset)
        end_offset = batch.parsed_end_offset
        if end_offset > 2**63 - 1:
            raise EventError("OFFSET_OUT_OF_RANGE")
        prepared = []
        for record in batch.records:
            source = record.event
            redacted = redact_event(source)
            event_key = _hash([
                source.scope.tenant_id, source.scope.project_id, source.scope.stream_id,
                source.producer_epoch, source.event_id,
            ])
            fingerprint = source.replay_fingerprint(redaction_version=POLICY_VERSION)
            ordering_key = _hash([
                source.scope.tenant_id, source.scope.project_id, source.scope.stream_id,
                source.producer_epoch, source.source_ordinal,
            ])
            prepared.append((record, event_key, fingerprint, redacted, ordering_key))
        consumed = end_offset - start_offset
        span_digest = hashlib.sha256(data[:consumed]).hexdigest()
        con = self._con
        try:
            con.execute("BEGIN IMMEDIATE")
            row = self._bind_source(source_id, incarnation, expected_scope, start_offset)
            old_receipt = con.execute(
                """SELECT span_digest,record_count FROM deliveries
                   WHERE source_id=? AND start_offset=? AND end_offset=?""",
                (source_id, start_offset, end_offset),
            ).fetchone()
            if old_receipt is not None:
                if old_receipt[0] != span_digest:
                    raise EventError("DELIVERY_CONFLICT")
                con.execute("COMMIT")
                return Receipt(row[5], 0, old_receipt[1], len(batch.pending_tail))
            if row[5] != start_offset:
                raise EventError("CHECKPOINT_CONFLICT")
            inserted = replayed = 0
            for record, event_key, fingerprint, redacted, ordering_key in prepared:
                previous = con.execute(
                    "SELECT fingerprint FROM events WHERE event_key=?", (event_key,),
                ).fetchone()
                if previous is not None:
                    if previous[0] != fingerprint:
                        raise EventError("EVENT_ID_CONFLICT")
                    replayed += 1
                else:
                    if con.execute("SELECT 1 FROM events WHERE ordering_key=?", (ordering_key,)).fetchone():
                        raise EventError("SOURCE_ORDINAL_CONFLICT")
                    con.execute("INSERT INTO events VALUES (?,?,?,?,?,?,?)", (
                        event_key, fingerprint, POLICY_VERSION,
                        redacted.event.canonical_json, json.dumps(redacted.audit_rules), ordering_key,
                        int(redacted.has_public_text),
                    ))
                    inserted += 1
                con.execute("INSERT INTO records VALUES (?,?,?,?)",
                            (source_id, record.start_offset, record.end_offset, event_key))
            if consumed:
                con.execute("INSERT INTO deliveries VALUES (?,?,?,?,?)",
                            (source_id, start_offset, end_offset, span_digest, len(prepared)))
                chain = _hash([row[6], start_offset, end_offset, span_digest])
                con.execute("UPDATE sources SET next_offset=?,chain_digest=? WHERE source_id=?",
                            (end_offset, chain, source_id))
            con.execute("COMMIT")
            return Receipt(end_offset, inserted, replayed, len(batch.pending_tail))
        except BaseException as exc:
            if con.in_transaction:
                con.execute("ROLLBACK")
            if isinstance(exc, sqlite.Error):
                raise EventError("LEDGER_TRANSACTION_FAILED") from None
            raise


def open_ledger(path: str | Path, key: bytes) -> Ledger:
    """Create a private encrypted ledger or open an existing matching ledger.

    Never adopt plaintext/foreign/empty files. Keys arrive as bytes, not argv or
    configuration literals. Failed new-file initialization leaves a file for
    diagnosis; this function never removes or overwrites an existing database.
    """
    if not isinstance(key, bytes) or len(key) != 32:
        raise EventError("KEY_MUST_BE_32_BYTES")
    target = Path(path).absolute()
    if target.is_symlink():
        raise EventError("SYMLINK_DATABASE_REJECTED")
    created = False
    try:
        fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        pass
    else:
        os.close(fd)
        created = True
    if target.stat().st_mode & 0o077:
        raise EventError("PRIVATE_DATABASE_PERMISSIONS_REQUIRED")
    con = None
    try:
        con = sqlite.connect(target.as_uri() + "?mode=rw", uri=True, isolation_level=None)
        con.execute(f"""PRAGMA key = "x'{key.hex()}'" """)
        if not con.execute("PRAGMA cipher_version").fetchone():
            raise EventError("SQLCIPHER_REQUIRED")
        con.execute("PRAGMA temp_store=MEMORY")
        con.execute("PRAGMA busy_timeout=5000")
        con.execute("SELECT count(*) FROM sqlite_master").fetchone()
        if not created:
            if con.execute("SELECT engine FROM meta").fetchall() != [(ENGINE,)]:
                raise EventError("FOREIGN_LEDGER")
            if con.execute("PRAGMA user_version").fetchone() != (4,):
                raise EventError("UNSUPPORTED_LEDGER_SCHEMA")
        con.execute("PRAGMA foreign_keys=ON")
        con.execute("PRAGMA journal_mode=DELETE")
        con.execute("PRAGMA synchronous=FULL")
        if created:
            con.execute("BEGIN IMMEDIATE")
            for statement in _SCHEMA:
                con.execute(statement)
            con.execute("INSERT INTO meta VALUES (?)", (ENGINE,))
            con.execute("PRAGMA user_version=4")
            con.execute("COMMIT")
        return Ledger(con)
    except BaseException as exc:
        if con is not None:
            con.close()
        if isinstance(exc, sqlite.Error):
            raise EventError("LEDGER_OPEN_FAILED") from None
        raise
