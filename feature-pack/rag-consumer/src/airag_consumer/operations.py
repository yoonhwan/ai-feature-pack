"""AIRAG key, schedule, and encrypted recovery backup operations.

This module does not start a daemon or select production paths. Callers supply
the enabled stores, their already-openable keys, and the project backup root.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time, timedelta
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
from typing import Callable, Iterable, Mapping
from zoneinfo import ZoneInfo

import sqlcipher3


KEY_NAMES = {
    "consumer_ledger": "AIRAG_CONSUMER_KEY_HEX",
    "projection_db": "AIRAG_PROJECTION_KEY_HEX",
    "archive": "AIRAG_ARCHIVE_KEY_HEX",
}
_SEOUL = ZoneInfo("Asia/Seoul")
_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}\Z")
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_OWNER = "airag-operations-v1"
_RestoreLinkCheck = Callable[[Mapping[str, Path], datetime], None]


class OperationsError(ValueError):
    """An operational precondition or verification failed; no key is included."""


def load_store_keys(enabled: Iterable[str], environ: Mapping[str, str]) -> dict[str, bytes]:
    """Validate 64-hex runtime keys before callers create any enabled store."""
    names = tuple(enabled)
    if len(set(names)) != len(names) or any(name not in KEY_NAMES for name in names):
        raise OperationsError("INVALID_ENABLED_STORE")
    result = {}
    for name in names:
        value = environ.get(KEY_NAMES[name], "")
        if not isinstance(value, str) or re.fullmatch(r"[0-9a-fA-F]{64}", value) is None:
            raise OperationsError("MISSING_OR_INVALID_STORE_KEY")
        result[name] = bytes.fromhex(value)
    if len(set(result.values())) != len(result):
        raise OperationsError("STORE_KEYS_MUST_BE_DISTINCT")
    return result


def unrelated_child_environment(environ: Mapping[str, str]) -> dict[str, str]:
    """Return a child environment without AIRAG store secrets."""
    return {key: value for key, value in environ.items() if key not in KEY_NAMES.values()}


@dataclass(frozen=True)
class BackupDecision:
    """Whether one current Seoul schedule slot requires a backup."""

    due: bool
    slot: datetime
    catchup: bool


def backup_due(now: datetime, last_verified_success: datetime | None) -> BackupDecision:
    """Decide the latest daily Seoul 03:00 slot from aware timestamps.

    A caller runs this once at startup and records success only after
    ``create_backup_set`` returns. Missed days collapse to one current slot.
    """
    if now.tzinfo is None or now.utcoffset() is None:
        raise OperationsError("AWARE_TIME_REQUIRED")
    if last_verified_success is not None and (last_verified_success.tzinfo is None or last_verified_success.utcoffset() is None):
        raise OperationsError("AWARE_TIME_REQUIRED")
    if last_verified_success is not None and last_verified_success > now:
        raise OperationsError("BACKUP_CLOCK_REGRESSION")
    local = now.astimezone(_SEOUL)
    slot = datetime.combine(local.date(), time(3), _SEOUL)
    if local < slot:
        slot -= timedelta(days=1)
    previous = None if last_verified_success is None else last_verified_success.astimezone(_SEOUL)
    due = previous is None or previous < slot
    catchup = due and (local > slot or (previous is not None and previous < slot - timedelta(days=1)))
    return BackupDecision(due, slot, catchup)


@dataclass(frozen=True)
class DatabaseSource:
    """One SQLite/SQLCipher source and its in-memory 32-byte key."""

    name: str
    path: Path
    key: bytes


@dataclass(frozen=True)
class ArchiveSource:
    """One caller-owned encrypted file, including a raw immutable archive DB."""

    name: str
    path: Path


def _regular(path: Path) -> None:
    if path.is_symlink() or not path.is_file() or not stat.S_ISREG(path.lstat().st_mode):
        raise OperationsError("REGULAR_FILE_REQUIRED")


def _aware(value: datetime) -> None:
    if value.tzinfo is None or value.utcoffset() is None:
        raise OperationsError("AWARE_TIME_REQUIRED")


def _root(root: Path) -> Path:
    root = Path(root).absolute()
    if not root.is_dir() or root.is_symlink():
        raise OperationsError("INVALID_BACKUP_ROOT")
    for parent in (root, *root.parents):
        if parent.is_symlink():
            raise OperationsError("SYMLINK_PATH_REJECTED")
    return root


def _validate_sources(root: Path, databases: tuple[DatabaseSource, ...], archives: tuple[ArchiveSource, ...]) -> None:
    names = [source.name for source in (*databases, *archives)]
    if not names or len(names) != len(set(names)) or any(_ID.fullmatch(name) is None for name in names):
        raise OperationsError("INVALID_COMPONENT_NAMES")
    for source in (*databases, *archives):
        path = Path(source.path).absolute()
        _regular(path)
        if path == root or root in path.parents:
            raise OperationsError("SOURCE_INSIDE_BACKUP_ROOT")
        for parent in path.parents:
            if parent.is_symlink():
                raise OperationsError("SYMLINK_PATH_REJECTED")
    for source in databases:
        if not isinstance(source.key, bytes) or len(source.key) != 32:
            raise OperationsError("INVALID_DATABASE_KEY")
    if len({source.key for source in databases}) != len(databases):
        raise OperationsError("STORE_KEYS_MUST_BE_DISTINCT")


def _preflight_databases(databases: tuple[DatabaseSource, ...]) -> None:
    for source in databases:
        connection = _connect(Path(source.path).absolute(), source.key, True)
        connection.close()


def _connect(path: Path, key: bytes, readonly: bool) -> sqlcipher3.Connection:
    mode = "ro" if readonly else "rw"
    con = sqlcipher3.connect(path.as_uri() + f"?mode={mode}", uri=True, isolation_level=None)
    try:
        con.execute(f"PRAGMA key = \"x'{key.hex()}'\"")
        con.execute("PRAGMA temp_store=MEMORY")
        if not con.execute("PRAGMA cipher_version").fetchone()[0]:
            raise OperationsError("SQLCIPHER_REQUIRED")
        con.execute("SELECT count(*) FROM sqlite_master").fetchone()
        return con
    except Exception:
        con.close()
        raise OperationsError("DATABASE_OPEN_OR_KEY_FAILED") from None


def _integrity(path: Path, key: bytes) -> None:
    con = _connect(path, key, True)
    try:
        if con.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise OperationsError("DATABASE_INTEGRITY_FAILED")
    finally:
        con.close()


def _digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _copy_database(source: DatabaseSource, target: Path) -> None:
    source_path = Path(source.path).absolute()
    _regular(source_path)
    source_con = _connect(source_path, source.key, True)
    target_con = None
    try:
        source_con.execute("BEGIN")
        target.touch(mode=0o600, exist_ok=False)
        target_con = _connect(target, source.key, False)
        source_con.backup(target_con, pages=256, sleep=0.05)
        target_con.execute("PRAGMA journal_mode=DELETE")
        target_con.close()
        target_con = None
        _integrity(target, source.key)
        _fsync_file(target)
    finally:
        if target_con is not None:
            target_con.close()
        source_con.close()


def _copy_archive(source: Path, target: Path) -> None:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        source_fd = os.open(source, flags)
    except OSError:
        raise OperationsError("ARCHIVE_OPEN_FAILED") from None
    try:
        if not stat.S_ISREG(os.fstat(source_fd).st_mode):
            raise OperationsError("REGULAR_FILE_REQUIRED")
        target_fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(source_fd, "rb") as source_handle, os.fdopen(target_fd, "wb") as target_handle:
            source_fd = -1
            shutil.copyfileobj(source_handle, target_handle, length=1024 * 1024)
            target_handle.flush()
            os.fsync(target_handle.fileno())
    finally:
        if source_fd >= 0:
            os.close(source_fd)


def _write_json(path: Path, value: dict) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(value, handle, sort_keys=True, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())


def _replace_json(path: Path, value: dict) -> None:
    fd, temporary = tempfile.mkstemp(prefix=".manifest-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, sort_keys=True, separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _fsync_file(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _validate_manifest(data: object, state: str) -> dict:
    if not isinstance(data, dict) or data.get("owner") != _OWNER or data.get("state") != state:
        raise OperationsError("UNOWNED_OR_INCOMPLETE_SET")
    timestamp_name = "completed_at" if state == "verified" else "created_at"
    try:
        timestamp = datetime.fromisoformat(data[timestamp_name])
    except (KeyError, TypeError, ValueError):
        raise OperationsError("INVALID_MANIFEST") from None
    _aware(timestamp)
    components = data.get("components")
    checkpoints = data.get("checkpoints")
    if not isinstance(components, list) or not components or not isinstance(checkpoints, dict):
        raise OperationsError("INVALID_MANIFEST")
    names = []
    for item in components:
        if not isinstance(item, dict):
            raise OperationsError("INVALID_MANIFEST_COMPONENT")
        name, kind, digest = item.get("name"), item.get("kind"), item.get("sha256")
        if (not isinstance(name, str) or _ID.fullmatch(name) is None or
                kind not in ("database", "archive") or
                not isinstance(digest, str) or _SHA256.fullmatch(digest) is None):
            raise OperationsError("INVALID_MANIFEST_COMPONENT")
        names.append(name)
    if len(names) != len(set(names)) or checkpoints != {
            item["name"]: item["sha256"] for item in components}:
        raise OperationsError("INCOHERENT_MANIFEST_CHECKPOINTS")
    return data


def _manifest(set_path: Path, *, state: str = "verified") -> dict:
    if set_path.is_symlink() or not set_path.is_dir():
        raise OperationsError("INVALID_BACKUP_SET")
    for parent in (set_path, *set_path.parents):
        if parent.is_symlink():
            raise OperationsError("SYMLINK_PATH_REJECTED")
    manifest_path = set_path / "manifest.json"
    _regular(manifest_path)
    try:
        with manifest_path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        raise OperationsError("INVALID_MANIFEST") from None
    return _validate_manifest(data, state)


def read_backup_manifest(set_path: Path) -> dict:
    """Return the validated manifest of a verified, owned backup set."""
    return _manifest(Path(set_path).absolute())


def _verify_contents(set_path: Path, data: dict, database_keys: Mapping[str, bytes],
                     link_check: _RestoreLinkCheck, now: datetime) -> None:
    expected = _expected_set_entries(data)
    if {item.name for item in set_path.iterdir()} != expected:
        raise OperationsError("INVALID_BACKUP_SET_CONTENTS")
    with tempfile.TemporaryDirectory(prefix="airag-restore-") as directory:
        restored = {}
        for item in data["components"]:
            name, kind = item["name"], item["kind"]
            source = set_path / f"{name}.bin"
            _regular(source)
            target = Path(directory) / f"{name}.bin"
            _copy_archive(source, target)
            if _digest(target) != item["sha256"]:
                raise OperationsError("BACKUP_DIGEST_MISMATCH")
            if kind == "database":
                key = database_keys.get(name)
                if not isinstance(key, bytes) or len(key) != 32:
                    raise OperationsError("MISSING_DATABASE_KEY")
                _integrity(target, key)
            restored[name] = target
        link_check(restored, now)


def _expected_set_entries(data: dict) -> set[str]:
    return {"manifest.json", *(f"{item['name']}.bin" for item in data["components"])}


def verify_backup_set(set_path: Path, database_keys: Mapping[str, bytes],
                      link_check: _RestoreLinkCheck, *, now: datetime) -> dict:
    """Restore into an isolated temporary directory, check contents and links.

    The hook receives restored component paths plus the caller's current aware
    time. It must raise until current-clock 90-day expiry, current scope, and
    latest tombstones reconcile. This function never opens an operational read
    gate and never receives or writes a production restore destination.
    """
    _aware(now)
    set_path = Path(set_path).absolute()
    data = _manifest(set_path)
    _verify_contents(set_path, data, database_keys, link_check, now)
    return data


def create_backup_set(root: Path, databases: Iterable[DatabaseSource], archives: Iterable[ArchiveSource],
                      link_check: _RestoreLinkCheck, *, now: datetime) -> Path:
    """Publish a consistent, verified encrypted set under an existing root.

    Archives must already be encrypted by their owner. An exclusive project
    lock serializes creators. An incomplete staging directory is retained for
    diagnosis; only a fully restored and checked set gets a completed name.
    """
    _aware(now)
    databases, archives = tuple(databases), tuple(archives)
    root = _root(root)
    _validate_sources(root, databases, archives)
    _preflight_databases(databases)
    lock_path = root / ".operations.lock"
    try:
        lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    except OSError:
        raise OperationsError("BACKUP_LOCK_FAILED") from None
    if not stat.S_ISREG(os.fstat(lock_fd).st_mode):
        os.close(lock_fd)
        raise OperationsError("BACKUP_LOCK_FAILED")
    with os.fdopen(lock_fd, "r+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stage = Path(tempfile.mkdtemp(prefix=".airag-stage-", dir=root))
        items = []
        for source in databases:
            target = stage / f"{source.name}.bin"
            _copy_database(source, target)
            items.append({"name": source.name, "kind": "database", "sha256": _digest(target)})
        for source in archives:
            target = stage / f"{source.name}.bin"
            _copy_archive(Path(source.path).absolute(), target)
            items.append({"name": source.name, "kind": "archive", "sha256": _digest(target)})
        data = {"owner": _OWNER, "state": "staging", "created_at": now.isoformat(),
                "components": items, "checkpoints": {item["name"]: item["sha256"] for item in items}}
        _write_json(stage / "manifest.json", data)
        _validate_manifest(data, "staging")
        _verify_contents(stage, data, {source.name: source.key for source in databases}, link_check, now)
        verified = {**data, "state": "verified", "completed_at": now.isoformat()}
        _validate_manifest(verified, "verified")
        _replace_json(stage / "manifest.json", verified)
        _fsync_directory(stage)
        final = root / ("airag-set-" + now.astimezone(_SEOUL).strftime("%Y%m%dT%H%M%S") + "-" + stage.name[-8:])
        if os.path.lexists(final):
            raise OperationsError("BACKUP_DESTINATION_EXISTS")
        stage.rename(final)
        _fsync_directory(root)
        return final


def prune_backup_sets(root: Path, *, now: datetime, newest_verified: Path,
                      restore_in_use: Iterable[Path] = ()) -> list[Path]:
    """Remove owned completed sets older than 30 days after a new verified set.

    The caller supplies the just-verified set. Only immediate project-root
    children with a valid owned manifest are candidates.
    """
    if now.tzinfo is None or now.utcoffset() is None:
        raise OperationsError("AWARE_TIME_REQUIRED")
    root = _root(root)
    newest = Path(newest_verified).absolute()
    if newest.parent != root or not newest.name.startswith("airag-set-"):
        raise OperationsError("INVALID_NEWEST_SET")
    newest_data = _manifest(newest)
    newest_children = tuple(newest.iterdir())
    if ({child.name for child in newest_children} != _expected_set_entries(newest_data) or
            any(child.is_symlink() or not child.is_file() for child in newest_children)):
        raise OperationsError("INVALID_NEWEST_SET")
    preserved = {newest, *(Path(p).absolute() for p in restore_in_use)}
    removed = []
    for path in root.iterdir():
        if path in preserved or not path.name.startswith("airag-set-") or path.is_symlink() or not path.is_dir():
            continue
        try:
            data = _manifest(path)
            completed = datetime.fromisoformat(data["completed_at"])
            if completed.tzinfo is None or completed.utcoffset() is None:
                continue
            if completed >= now - timedelta(days=30):
                continue
            children = tuple(path.iterdir())
            if ({child.name for child in children} != _expected_set_entries(data) or
                    any(child.is_symlink() or not child.is_file() for child in children)):
                continue
            shutil.rmtree(path)
            removed.append(path)
        except (OperationsError, OSError, ValueError, KeyError, json.JSONDecodeError):
            continue
    return removed
