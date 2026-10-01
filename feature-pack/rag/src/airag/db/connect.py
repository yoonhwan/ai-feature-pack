"""Encrypted SQLCipher connection helpers (design §4.1/§4.2, phase 1 scope only).

Ordering note (review-adjudication.txt item 7, defense in depth): PRAGMA
temp_store=MEMORY is applied immediately after PRAGMA key, before the
verification SELECT — the KakaoBot precedent (src/krb/db/connect.py) applies
it after that SELECT. No cipher_default_temp_store pragma is used since no
official SQLCipher documentation for one was found; this ordering change is
the only defense-in-depth step taken.

Identity note (p01-review.txt item 1, p01 2nd review): a valid key only
proves the file decrypts into *some* readable SQLite structure — it does not
prove the result is an airag database. `open_encrypted` (ordinary
reopen/verify) additionally requires an `engine='airag'` marker and an exact
supported schema version, so a foreign-but-correctly-keyed SQLCipher
database or a differently-versioned airag database is refused.

No-modification note (p01 2nd review): `PRAGMA journal_mode = WAL` rewrites
the database file's header/format on disk — empirically confirmed here, this
pragma alone changes file bytes even when no table data changes. Every other
pragma used (key, temp_store, foreign_keys, busy_timeout) and the identity
verification SELECT are connection-local and do not touch the file. So
`open_encrypted` defers `journal_mode=WAL` until AFTER identity/schema
verification succeeds — a rejected foreign database's bytes are never
touched. It also connects via a `mode=rw` URI, so the SQLite driver itself
refuses to create a missing file (not just an app-level exists() check).
`init_db` uses the lower-level `_open_non_mutating(..., allow_create=True)`
directly, since a brand-new database has no schema yet to validate.
"""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path

import sqlcipher3

from airag.db import schema
from airag.db.schema import ENGINE_TAG, UnsupportedSchemaVersion

KEY_LEN = 32
SCHEMA_VERSION = schema.CURRENT_SCHEMA_VERSION

__all__ = [
    "WrongKeyOrForeignDatabase",
    "UnsupportedSchemaVersion",
    "DatabaseAlreadyExists",
    "SCHEMA_VERSION",
    "cipher_version",
    "open_encrypted",
    "open_readonly",
    "init_db",
    "read_schema_version",
]


class WrongKeyOrForeignDatabase(Exception):
    """Key verification failed: wrong key, no key, foreign DB, or a plaintext file."""


class DatabaseAlreadyExists(Exception):
    """init_db() refuses to overwrite any pre-existing file at the target
    path (including an empty one), and refuses to race a concurrent init of
    the same path — both are the same underlying O_EXCL reservation."""


def _validate_key_length(key_bytes: bytes) -> None:
    if not isinstance(key_bytes, bytes):
        raise TypeError(f"key must be bytes, got {type(key_bytes).__name__}")
    if len(key_bytes) != KEY_LEN:
        raise ValueError(f"key must be {KEY_LEN} bytes, got {len(key_bytes)}")


def _apply_raw_key(con: sqlite3.Connection, key_bytes: bytes) -> None:
    _validate_key_length(key_bytes)
    _ = con.execute(f"PRAGMA key = \"x'{key_bytes.hex()}'\"")


def _verify_readable(con: sqlite3.Connection) -> None:
    try:
        con.execute("SELECT count(*) FROM sqlite_master").fetchone()
    except Exception as exc:  # sqlcipher3 raises DatabaseError("file is not a database")
        raise WrongKeyOrForeignDatabase(str(exc)) from exc


def cipher_version(con: sqlite3.Connection) -> str | None:
    """The active SQLCipher build's cipher_version, or None if this
    connection is not actually running under SQLCipher (e.g. a plaintext
    sqlite3 driver masquerading behind the same API — PRAGMA key would be a
    silent no-op on such a driver)."""
    row = con.execute("PRAGMA cipher_version").fetchone()
    return row[0] if row else None


def _assert_real_encryption(con: sqlite3.Connection) -> None:
    version = cipher_version(con)
    if not version:
        raise WrongKeyOrForeignDatabase(
            "PRAGMA cipher_version is empty — this connection is not running under real SQLCipher; refusing rather than risk a plaintext fallback"
        )


def _open_non_mutating(
    path: str | Path, key_bytes: bytes, *, allow_create: bool
) -> sqlite3.Connection:
    """Apply key + connection-local pragmas only. Never issues
    `PRAGMA journal_mode`, so it never mutates on-disk file bytes — safe to
    call on a database that identity/schema verification might still go on
    to reject (see module docstring's no-modification note).

    `allow_create=False` connects via a `mode=rw` URI, so the SQLite driver
    itself refuses to create a missing file — used by `open_encrypted`.
    `allow_create=True` connects to the path directly — used by `init_db`
    on a path it has just exclusively reserved via O_EXCL.

    Fails closed on every error path: the connection is always closed
    before the exception propagates, whatever the exception type.
    """
    _validate_key_length(key_bytes)
    p = Path(path)
    if allow_create:
        con = sqlcipher3.connect(str(p), check_same_thread=False)
    else:
        # A hand-built f"file:{p}?mode=rw" would let a path containing
        # ?/#/% be misparsed as URI query/fragment/percent-escapes and open
        # a different file than intended. Path.resolve().as_uri() percent-
        # encodes the path correctly (RFC 8089); the "?mode=rw" query is
        # appended after, on the already-escaped string.
        uri = p.resolve().as_uri() + "?mode=rw"
        con = sqlcipher3.connect(uri, uri=True, check_same_thread=False)
    con.isolation_level = None
    try:
        _apply_raw_key(con, key_bytes)
        con.execute("PRAGMA temp_store = MEMORY")
        _verify_readable(con)
        _assert_real_encryption(con)
        con.execute("PRAGMA foreign_keys = ON")
        con.execute("PRAGMA busy_timeout = 5000")
    except Exception:
        con.close()
        raise
    return con


def _enable_wal(con: sqlite3.Connection) -> None:
    """Converts the database file to WAL journal mode. This mutates on-disk
    file bytes — only call after identity/schema verification has already
    succeeded, or on a brand-new database this very call is initializing."""
    con.execute("PRAGMA journal_mode = WAL")


def _verify_engine_and_schema(con: sqlite3.Connection) -> None:
    try:
        row = con.execute(
            "SELECT value FROM db_meta WHERE key = 'engine'"
        ).fetchone()
    except Exception as exc:
        raise WrongKeyOrForeignDatabase(
            f"not an {ENGINE_TAG} database: {exc}"
        ) from exc
    if row is None or row[0] != ENGINE_TAG:
        raise WrongKeyOrForeignDatabase(
            f"not an {ENGINE_TAG} database: db_meta.engine missing or mismatched"
        )
    # Raises UnsupportedSchemaVersion for anything unrecognized/future, and
    # migrates forward in place for an older known version (e.g. a P-01 v1
    # database gains the P-02 v2 tables here).
    schema.ensure_current_schema(con)


def open_encrypted(path: str | Path, key_bytes: bytes) -> sqlite3.Connection:
    """Open an EXISTING, already-initialized airag database at `path`.

    Fails closed and never creates or modifies anything on disk for: a
    missing path, a wrong key, a plaintext SQLite file, a foreign (correctly
    keyed but non-airag) encrypted database, and a database whose schema
    version is not exactly what this build supports.
    """
    try:
        con = _open_non_mutating(path, key_bytes, allow_create=False)
    except sqlcipher3.OperationalError as exc:
        raise WrongKeyOrForeignDatabase(
            f"{path} does not exist or is not openable: {exc}"
        ) from exc
    try:
        _verify_engine_and_schema(con)
        _enable_wal(con)
    except Exception:
        con.close()
        raise
    return con


def open_readonly(path: str | Path, key_bytes: bytes) -> sqlite3.Connection:
    """Open for diagnostics without migration, WAL conversion, or file creation."""
    _validate_key_length(key_bytes)
    con = sqlcipher3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True)
    con.isolation_level = None
    try:
        _apply_raw_key(con, key_bytes)
        con.execute("PRAGMA temp_store = MEMORY")
        con.execute("PRAGMA query_only = ON")
        con.execute("PRAGMA busy_timeout = 5000")
        _verify_readable(con)
        _assert_real_encryption(con)
        row = con.execute("SELECT value FROM db_meta WHERE key='engine'").fetchone()
        if row != (ENGINE_TAG,):
            raise WrongKeyOrForeignDatabase("database engine identity does not match")
        if read_schema_version(con) != SCHEMA_VERSION:
            raise UnsupportedSchemaVersion("diagnostics require the current schema; migration was not attempted")
        return con
    except Exception:
        con.close()
        raise


def init_db(path: str | Path, key_bytes: bytes) -> sqlite3.Connection:
    """Create a brand-new encrypted DB at `path`.

    Key length is validated before anything touches the filesystem. The
    path is then atomically reserved with O_CREAT|O_EXCL before any SQLite
    connection is made: this refuses ANY pre-existing file at that path
    (including an empty one) and eliminates the check-then-act race
    entirely — of any number of callers racing the same brand-new path,
    exactly one wins and the rest raise `DatabaseAlreadyExists` immediately,
    without contending for a separate lock file. Schema creation is a
    single explicit transaction, so a mid-init crash cannot leave a
    partially initialized database that reads as valid. A failed init's
    artifact (the reserved file, and its `-wal`/`-shm` siblings if the
    driver created them) is never auto-deleted — deleting it is a decision
    for a human, not this function.
    """
    _validate_key_length(key_bytes)
    p = Path(path)
    try:
        fd = os.open(str(p), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise DatabaseAlreadyExists(f"{p} already exists") from exc
    os.close(fd)

    con = _open_non_mutating(p, key_bytes, allow_create=True)
    try:
        _enable_wal(con)
        con.execute("BEGIN")
        schema.create_fresh_database(con)
        con.commit()
    except Exception:
        con.close()
        raise
    return con


def read_schema_version(con: sqlite3.Connection) -> int | None:
    row = con.execute("SELECT MAX(version) FROM schema_migrations").fetchone()
    return row[0] if row else None
