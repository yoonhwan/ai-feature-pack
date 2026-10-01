"""Encrypted SQLite snapshots published only after verification, without overwrite."""

from __future__ import annotations

import hashlib
import os
import stat
import tempfile
import time
from pathlib import Path

import sqlcipher3

from airag import diagnostics, store
from airag.db import connect


_TABLES = ("sources", "source_revisions", "generations", "jobs", "processing_profiles",
           "embedding_spaces", "chunks", "normalized_documents", "request_ledger",
           "search_manifests", "expansion_manifests")


def _verified_counts(con):
    report = diagnostics.inspect_database(con)
    if not report["healthy"]:
        raise store.ApiError("BACKUP_VERIFICATION_FAILED", "snapshot has inconsistent database state", retryable=False)
    for content, byte_length, content_hash in con.execute(
        "SELECT content_bytes,byte_length,content_hash FROM source_revisions"
    ):
        if len(content) != byte_length or hashlib.sha256(content).hexdigest() != content_hash:
            raise store.ApiError("BACKUP_VERIFICATION_FAILED", "snapshot original content verification failed", retryable=False)
    return {table: con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] for table in _TABLES}


def copy_database(source_path, destination_path, key_bytes: bytes, *, destination_key_bytes: bytes | None = None):
    """Create a fresh encrypted snapshot; neither source nor existing targets change.

    A failed new staging file is retained as evidence. The final pathname is
    installed atomically by a hard link only after closing and reopening the
    verified encrypted snapshot. No plaintext database is ever written.
    """
    connect._validate_key_length(key_bytes)
    target_key = key_bytes if destination_key_bytes is None else destination_key_bytes
    connect._validate_key_length(target_key)
    source = Path(source_path).absolute()
    target = Path(destination_path).absolute()
    if source.is_symlink() or target.is_symlink():
        raise store.ApiError("INVALID_BACKUP_PATH", "source and destination must not be symbolic links", retryable=False)
    if source.resolve() == target.resolve():
        raise store.ApiError("INVALID_BACKUP_PATH", "source and destination must differ", retryable=False)
    if os.path.lexists(target):
        raise store.ApiError("DESTINATION_EXISTS", "destination already exists; overwrite is not permitted", retryable=False)
    if not source.is_file():
        raise store.ApiError("INVALID_BACKUP_PATH", "source must be an existing regular file", retryable=False)

    source_con = None
    destination_con = None
    partial = None
    try:
        source_con = connect.open_readonly(source, key_bytes)
        source_con.execute("BEGIN")
        counts = _verified_counts(source_con)
        fd, partial_name = tempfile.mkstemp(prefix=".airag-snapshot-", suffix=".partial", dir=target.parent)
        partial = Path(partial_name)
        original_stat = os.fstat(fd)
        os.close(fd)
        destination_con = sqlcipher3.connect(partial.as_uri() + "?mode=rw", uri=True)
        destination_con.isolation_level = None
        connect._apply_raw_key(destination_con, target_key)
        destination_con.execute("PRAGMA temp_store = MEMORY")
        connect._assert_real_encryption(destination_con)
        destination_con.execute("PRAGMA busy_timeout = 5000")
        started = time.monotonic()

        def progress(_status, _remaining, _total):
            if time.monotonic() - started > 60:
                raise TimeoutError("snapshot copy timed out")

        source_con.backup(destination_con, pages=256, progress=progress, sleep=0.05)
        # Only the new snapshot changes journal mode. It must be a standalone
        # encrypted file, independent of any source WAL or staging sidecars.
        destination_con.execute("PRAGMA journal_mode = DELETE")
        destination_con.close()
        destination_con = None
        verification = connect.open_readonly(partial, target_key)
        try:
            verification.execute("BEGIN")
            if _verified_counts(verification) != counts:
                raise store.ApiError("BACKUP_VERIFICATION_FAILED", "snapshot row counts do not match", retryable=False)
        finally:
            verification.close()
        current_stat = partial.lstat()
        if (current_stat.st_dev, current_stat.st_ino) != (original_stat.st_dev, original_stat.st_ino) or not stat.S_ISREG(current_stat.st_mode):
            raise store.ApiError("INVALID_BACKUP_PATH", "staging file identity changed", retryable=False)
        with partial.open("rb") as handle:
            os.fsync(handle.fileno())
        try:
            os.link(partial, target, follow_symlinks=False)
        except FileExistsError as exc:
            raise store.ApiError("DESTINATION_EXISTS", "destination already exists; overwrite is not permitted", retryable=False) from exc
        # This removes only this invocation's temporary second name after the
        # verified database has been published. The final database remains.
        published_stat = target.lstat()
        if (published_stat.st_dev, published_stat.st_ino) != (original_stat.st_dev, original_stat.st_ino):
            raise store.ApiError("INVALID_BACKUP_PATH", "published file identity changed", retryable=False)
        os.unlink(partial)
        partial = None
        directory_fd = os.open(target.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        return {"path": str(target), "source_path": str(source), "verified": True, "encrypted": True,
                "schema_version": connect.SCHEMA_VERSION, "counts": counts,
                "diagnostics": {"healthy": True, "issues": []}}
    except Exception as exc:
        retained = f"; incomplete staging artifact retained at {partial}" if partial is not None else ""
        if isinstance(exc, store.ApiError):
            raise store.ApiError(exc.code, exc.message + retained, retryable=False) from exc
        raise store.ApiError("BACKUP_FAILED", "encrypted snapshot could not be completed" + retained, retryable=False) from exc
    finally:
        if destination_con is not None:
            destination_con.close()
        if source_con is not None:
            source_con.close()
