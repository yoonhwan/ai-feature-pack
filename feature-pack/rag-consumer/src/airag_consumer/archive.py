"""Immutable encrypted archive bundles, separate from normal RAG retrieval."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import uuid

import sqlcipher3 as sqlite

from .events import AccessScope, EventError
from .redaction import redact_text


ENGINE = "airag-archive-v1"


@dataclass(frozen=True)
class ArchiveReceipt:
    bundle_id: str
    path: str
    records: int
    ciphertext_sha256: str


def _json(value: object) -> bytes:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True,
                          separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (ValueError, TypeError, UnicodeError):
        raise EventError("INVALID_ARCHIVE_PAYLOAD") from None


def _key(key: bytes) -> None:
    if not isinstance(key, bytes) or len(key) != 32:
        raise EventError("KEY_MUST_BE_32_BYTES")


def _connect(path: Path, key: bytes, mode: str):
    _key(key)
    if path.is_symlink():
        raise EventError("SYMLINK_ARCHIVE_REJECTED")
    con = sqlite.connect(path.absolute().as_uri() + "?mode=" + mode, uri=True, isolation_level=None)
    try:
        con.execute(f"""PRAGMA key = "x'{key.hex()}'" """)
        if not con.execute("PRAGMA cipher_version").fetchone():
            raise EventError("SQLCIPHER_REQUIRED")
        con.execute("PRAGMA temp_store=MEMORY")
        if mode == "ro":
            con.execute("PRAGMA query_only=ON")
        else:
            con.execute("PRAGMA synchronous=FULL")
        con.execute("SELECT count(*) FROM sqlite_master").fetchone()
        return con
    except BaseException:
        con.close()
        raise


def _clean(value: object) -> object:
    if isinstance(value, str):
        return redact_text(value)[0]
    if isinstance(value, dict):
        if any(not isinstance(key, str) for key in value):
            raise EventError("INVALID_ARCHIVE_PAYLOAD")
        for key in value:
            if redact_text(key)[0] != key:
                raise EventError("SENSITIVE_ARCHIVE_FIELD_NAME")
        return {key: _clean(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_clean(item) for item in value]
    if value is None or type(value) in {int, float, bool}:
        return value
    raise EventError("INVALID_ARCHIVE_PAYLOAD")


def _scope(scope: AccessScope) -> list[str]:
    if not isinstance(scope, AccessScope):
        raise EventError("TRUSTED_SCOPE_REQUIRED")
    return [scope.tenant_id, scope.project_id, scope.stream_id]


def _verified_read(path: Path, key: bytes, scope: AccessScope) -> tuple[str, list[dict]]:
    con = None
    try:
        con = _connect(path, key, "ro")
        row = con.execute("SELECT engine,bundle_id,scope_json FROM archive_meta").fetchone()
        if not row or row[0] != ENGINE or json.loads(row[2]) != _scope(scope):
            raise EventError("ARCHIVE_SCOPE_OR_ENGINE_MISMATCH")
        if con.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            raise EventError("ARCHIVE_INTEGRITY_FAILED")
        records = []
        for entry_id, payload, digest in con.execute("SELECT entry_id,payload,sha256 FROM entries ORDER BY entry_id"):
            if hashlib.sha256(payload).hexdigest() != digest:
                raise EventError("ARCHIVE_RECORD_DIGEST_MISMATCH")
            record = json.loads(payload)
            if record.get("id") != entry_id or _json(record) != payload:
                raise EventError("ARCHIVE_RECORD_ID_MISMATCH")
            records.append(record)
        expected = hashlib.sha256(_json({"scope": _scope(scope), "records": records})).hexdigest()
        if expected != row[1]:
            raise EventError("ARCHIVE_BUNDLE_DIGEST_MISMATCH")
        return row[1], records
    except (sqlite.Error, ValueError, TypeError, KeyError) as exc:
        if isinstance(exc, EventError):
            raise
        raise EventError("ARCHIVE_READ_FAILED") from None
    finally:
        if con is not None:
            con.close()


def verify_archive(path: str | Path, key: bytes, scope: AccessScope) -> ArchiveReceipt:
    """Verify ciphertext's decrypted contents without returning archived text."""
    target = Path(path)
    bundle_id, records = _verified_read(target, key, scope)
    return ArchiveReceipt(bundle_id, str(target), len(records),
                          hashlib.sha256(target.read_bytes()).hexdigest())


def write_archive(
    root: str | Path, key: bytes, scope: AccessScope, records: Sequence[dict],
) -> ArchiveReceipt:
    """Seal one immutable bundle; input contains explicit IDs and provenance.

    No source database is changed. Callers may release active references only
    after this returns and after recording its receipt durably in their ledger.
    """
    _key(key)
    _scope(scope)
    normalized = []
    seen = set()
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("id"), str) or not record["id"]:
            raise EventError("ARCHIVE_RECORD_ID_REQUIRED")
        if record["id"] in seen:
            raise EventError("DUPLICATE_ARCHIVE_RECORD_ID")
        seen.add(record["id"])
        if record.get("kind") not in {"event", "memory", "provenance", "correction_state"}:
            raise EventError("UNSUPPORTED_ARCHIVE_RECORD_KIND")
        if record.get("scope") != _scope(scope):
            raise EventError("ARCHIVE_RECORD_SCOPE_MISMATCH")
        clean = _clean(record)
        if clean["id"] != record["id"] or clean["scope"] != record["scope"]:
            raise EventError("SENSITIVE_ARCHIVE_IDENTITY")
        _json(clean)
        normalized.append(clean)
    if not normalized:
        raise EventError("EMPTY_ARCHIVE")
    normalized.sort(key=lambda record: record["id"])
    bundle_id = hashlib.sha256(_json({"scope": _scope(scope), "records": normalized})).hexdigest()
    directory = Path(root).absolute()
    if directory.is_symlink():
        raise EventError("SYMLINK_ARCHIVE_ROOT_REJECTED")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = directory / ("archive-" + bundle_id + ".db")
    if target.exists() or target.is_symlink():
        receipt = verify_archive(target, key, scope)
        if receipt.bundle_id != bundle_id:
            raise EventError("ARCHIVE_ID_CONFLICT")
        return receipt
    staging = directory / (".partial-" + uuid.uuid4().hex + ".db")
    fd = os.open(staging, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(fd)
    con = None
    try:
        con = _connect(staging, key, "rw")
        con.execute("BEGIN IMMEDIATE")
        con.execute("CREATE TABLE archive_meta(engine TEXT,bundle_id TEXT,scope_json TEXT,created_at TEXT)")
        con.execute("CREATE TABLE entries(entry_id TEXT PRIMARY KEY,payload BLOB NOT NULL,sha256 TEXT NOT NULL)")
        con.execute("INSERT INTO archive_meta VALUES(?,?,?,?)",
                    (ENGINE, bundle_id, _json(_scope(scope)).decode(), datetime.now(timezone.utc).isoformat()))
        for record in normalized:
            payload = _json(record)
            con.execute("INSERT INTO entries VALUES(?,?,?)",
                        (record["id"], payload, hashlib.sha256(payload).hexdigest()))
        con.execute("COMMIT")
        con.close()
        con = None
        verify_archive(staging, key, scope)
        # Atomic no-overwrite publication. Removing the staging hardlink below
        # cannot delete the DB: its verified final link remains.
        try:
            os.link(staging, target)
        except FileExistsError:
            receipt = verify_archive(target, key, scope)
            if receipt.bundle_id != bundle_id:
                raise EventError("ARCHIVE_ID_CONFLICT")
        else:
            receipt = verify_archive(target, key, scope)
        directory_fd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        staging.unlink()
        return receipt
    except sqlite.Error:
        raise EventError("ARCHIVE_WRITE_FAILED") from None
    finally:
        if con is not None:
            con.close()
        # Failed staging files are retained for diagnosis, not published.


def lookup_archive(
    path: str | Path, key: bytes, scope: AccessScope, *,
    explicit_request: bool, authorize_record: Callable[[dict], bool],
    query: str = "", limit: int = 20,
) -> list[dict]:
    """Explicit lookup of payload string values, not field names or envelope IDs.

    Caller rechecks current source permissions. This bounded substring lookup
    is an archive inspection tool, not the normal RAG hybrid search path.
    """
    if explicit_request is not True:
        raise EventError("EXPLICIT_ARCHIVE_LOOKUP_REQUIRED")
    if not callable(authorize_record):
        raise EventError("CURRENT_AUTHORIZATION_REQUIRED")
    if not isinstance(query, str) or type(limit) is not int or not 1 <= limit <= 100:
        raise EventError("INVALID_ARCHIVE_QUERY")
    _, records = _verified_read(Path(path), key, scope)
    def text_values(value: object) -> str:
        if isinstance(value, str):
            return value
        if isinstance(value, dict):
            return "\n".join(text_values(item) for item in value.values())
        if isinstance(value, list):
            return "\n".join(text_values(item) for item in value)
        return ""
    result = []
    for record in records:
        if not authorize_record(record):
            continue
        if query.casefold() not in text_values(record.get("payload", {})).casefold():
            continue
        result.append(record)
        if len(result) == limit:
            break
    return result
