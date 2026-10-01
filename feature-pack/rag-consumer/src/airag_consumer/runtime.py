"""Executable AIRAG consumer runtime composed from bounded local components.

Configuration names every source and output explicitly.  The runtime never
discovers sessions, generates keys, installs a daemon, or accepts archive paths
from lookup callers.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Callable, Mapping, Sequence
from contextlib import contextmanager
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import fcntl
import hashlib
import importlib
import json
import os
from pathlib import Path
import re
import stat
from typing import Any, NoReturn
import uuid

from airag import profiles
from airag.db.connect import init_db, open_encrypted, open_readonly

from .archive import lookup_archive, verify_archive, write_archive
from .collector import CollectorResult, collect_codex_rollout
from .events import AccessScope
from .ledger import Ledger, open_ledger
from .lifecycle import AuthenticatedScope, Lifecycle
from .operations import (
    ArchiveSource,
    DatabaseSource,
    KEY_NAMES,
    backup_due,
    create_backup_set,
    load_store_keys,
    prune_backup_sets,
    verify_backup_set,
)


class RuntimeError(ValueError):
    """Safe runtime error code without keys or conversation text."""


def _error(code: str) -> NoReturn:
    raise RuntimeError(code)


_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}\Z")
_PROFILE = re.compile(r"[0-9a-f]{64}\Z")
PROFILE_SOURCE_KEY_ENV = "AIRAG_PROFILE_SOURCE_KEY_HEX"
MEMORY_BATCH_INPUT_BYTES = 4096
MEMORY_MAX_MESSAGES_PER_BATCH = 4


def _id(value: object, code: str) -> str:
    if not isinstance(value, str) or _ID.fullmatch(value) is None:
        _error(code)
    return value


def _opaque(value: object, code: str) -> str:
    if (
        not isinstance(value, str) or not value or len(value) > 256
        or value != value.strip()
        or any(ord(char) < 32 or ord(char) == 127 for char in value)
    ):
        _error(code)
    return value


def _aware(clock: Callable[[], datetime]) -> datetime:
    value = clock()
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        _error("AWARE_CLOCK_REQUIRED")
    return value


def _json(value: object) -> str:
    try:
        return json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False,
        )
    except (TypeError, ValueError, UnicodeError):
        _error("INVALID_RUNTIME_STATE")


def _regular(path: Path, code: str) -> None:
    try:
        info = path.lstat()
    except OSError:
        _error(code)
    if path.is_symlink() or not stat.S_ISREG(info.st_mode):
        _error(code)


def _directory(path: Path, code: str) -> None:
    try:
        info = path.lstat()
    except OSError:
        _error(code)
    if path.is_symlink() or not stat.S_ISDIR(info.st_mode):
        _error(code)


def _no_symlink_ancestors(path: Path) -> None:
    current = path if path.exists() else path.parent
    while True:
        if current.is_symlink():
            _error("SYMLINK_PATH_REJECTED")
        if current.parent == current:
            break
        current = current.parent


def _absolute(value: object, code: str) -> Path:
    if not isinstance(value, str) or not value:
        _error(code)
    path = Path(value)
    if not path.is_absolute() or Path(os.path.normpath(value)) != path:
        _error(code)
    _no_symlink_ancestors(path)
    return path


def _inside(path: Path, root: Path) -> bool:
    return path != root and root in path.parents


def runtime_child_environment(environ: Mapping[str, str]) -> dict[str, str]:
    """Remove store/bootstrap/provider secrets from any unrelated child."""
    return {
        key: value for key, value in environ.items()
        if not (key.startswith("AIRAG_") and key.endswith("_KEY_HEX"))
        and key != "AIRAG_MEMORY_API_KEY"
    }


def managed_backup_root(project_id: str) -> Path:
    """Return the one contract-owned backup path allowed outside project_root."""
    project = _id(project_id, "INVALID_PROJECT_ID")
    return Path.home() / ".local" / "share" / "airag" / "backups" / project


@dataclass(frozen=True)
class SourceEnrollment:
    path: Path
    session_id: str
    source_id: str

    def to_dict(self) -> dict[str, str]:
        return {
            "path": str(self.path), "session_id": self.session_id,
            "source_id": self.source_id,
        }


@dataclass(frozen=True)
class ReferenceGroupConfig:
    source_db: Path
    source_key_env: str
    source_allowlist: tuple[tuple[str, str], ...]
    snapshot_root: Path
    embedding_endpoint_override: str | None = None
    llm_endpoint_override: str | None = None

    def public_dict(self) -> dict[str, object]:
        return {
            "source_db": str(self.source_db),
            "source_key_env": self.source_key_env,
            "source_allowlist": [list(item) for item in self.source_allowlist],
            "snapshot_root": str(self.snapshot_root),
            "embedding_endpoint_override": self.embedding_endpoint_override,
            "llm_endpoint_override": self.llm_endpoint_override,
        }


@dataclass(frozen=True)
class RuntimeConfig:
    project_root: Path
    owner_id: str
    tenant_id: str
    project_id: str
    consumer_db: Path
    projection_db: Path
    archive_root: Path
    backup_root: Path
    profile_source_db: Path
    profile_key: str
    collection: str
    sources: tuple[SourceEnrollment, ...]
    reference: ReferenceGroupConfig | None = None
    token_mode: str = "estimated"
    allow_gaps: bool = False
    memory_enabled: bool = False
    memory_endpoint: str | None = None
    memory_model: str | None = None
    poll_seconds: int = 30

    @classmethod
    def load(cls, path_value: str | Path) -> RuntimeConfig:
        path = _absolute(os.fspath(path_value), "ABSOLUTE_CONFIG_PATH_REQUIRED")
        _regular(path, "REGULAR_CONFIG_FILE_REQUIRED")
        try:
            with path.open(encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, UnicodeError, json.JSONDecodeError):
            _error("INVALID_RUNTIME_CONFIG")
        if not isinstance(payload, dict):
            _error("INVALID_RUNTIME_CONFIG")
        required = {
            "schema_version", "project_root", "owner_id", "tenant_id", "project_id",
            "consumer_db", "projection_db", "archive_root", "backup_root",
            "profile_source_db", "profile_key", "collection", "sources",
        }
        optional = {
            "token_mode", "allow_gaps", "memory_enabled", "memory_endpoint",
            "memory_model", "poll_seconds", "reference",
        }
        if set(payload) - required - optional or not required <= set(payload):
            _error("INVALID_RUNTIME_CONFIG_FIELDS")
        if payload["schema_version"] != 1:
            _error("UNSUPPORTED_RUNTIME_CONFIG")
        root = _absolute(payload["project_root"], "INVALID_PROJECT_ROOT")
        _directory(root, "INVALID_PROJECT_ROOT")
        owner_id = _id(payload["owner_id"], "INVALID_OWNER_ID")
        tenant_id = _id(payload["tenant_id"], "INVALID_TENANT_ID")
        project_id = _id(payload["project_id"], "INVALID_PROJECT_ID")
        outputs = {
            name: _absolute(payload[name], f"INVALID_{name.upper()}")
            for name in ("consumer_db", "projection_db", "archive_root", "backup_root")
        }
        for name, item in outputs.items():
            if _inside(item, root):
                continue
            if name == "backup_root" and item == managed_backup_root(project_id):
                continue
            _error("OUTPUT_PATH_OUTSIDE_PROJECT")
        values = tuple(outputs.values())
        if len(set(values)) != len(values):
            _error("OUTPUT_PATH_COLLISION")
        if any(left in right.parents or right in left.parents for index, left in enumerate(values)
               for right in values[index + 1:]):
            _error("OUTPUT_PATH_COLLISION")
        profile_source = _absolute(payload["profile_source_db"], "INVALID_PROFILE_SOURCE")
        if profile_source.exists():
            _regular(profile_source, "REGULAR_PROFILE_SOURCE_REQUIRED")
        elif not outputs["projection_db"].exists():
            _error("REGULAR_PROFILE_SOURCE_REQUIRED")
        if profile_source in values:
            _error("PROFILE_SOURCE_OUTPUT_COLLISION")
        profile_key = payload["profile_key"]
        if not isinstance(profile_key, str) or _PROFILE.fullmatch(profile_key) is None:
            _error("INVALID_PROFILE_KEY")
        collection = _id(payload["collection"], "INVALID_COLLECTION")
        source_values = payload["sources"]
        if not isinstance(source_values, list) or not source_values:
            _error("EXPLICIT_SOURCE_ENROLLMENT_REQUIRED")
        sources = []
        for item in source_values:
            if not isinstance(item, dict) or set(item) != {"path", "session_id", "source_id"}:
                _error("INVALID_SOURCE_ENROLLMENT")
            source_path = _absolute(item["path"], "INVALID_SOURCE_PATH")
            _regular(source_path, "REGULAR_SOURCE_REQUIRED")
            sources.append(SourceEnrollment(
                source_path,
                _id(item["session_id"], "INVALID_SESSION_ID"),
                _id(item["source_id"], "INVALID_SOURCE_ID"),
            ))
        if len({item.path for item in sources}) != len(sources):
            _error("DUPLICATE_SOURCE_PATH")
        if len({item.session_id for item in sources}) != len(sources):
            _error("DUPLICATE_SESSION_ID")
        if len({item.source_id for item in sources}) != len(sources):
            _error("DUPLICATE_SOURCE_ID")
        reference = None
        reference_value = payload.get("reference")
        if reference_value is not None:
            if not isinstance(reference_value, dict):
                _error("INVALID_REFERENCE_CONFIG")
            required_reference = {"source_db", "source_key_env", "source_allowlist"}
            optional_reference = {
                "snapshot_root", "embedding_endpoint_override", "llm_endpoint_override",
            }
            if (
                not required_reference <= set(reference_value)
                or set(reference_value) - required_reference - optional_reference
            ):
                _error("INVALID_REFERENCE_CONFIG")
            reference_source = _absolute(
                reference_value["source_db"], "INVALID_REFERENCE_SOURCE",
            )
            _regular(reference_source, "REGULAR_REFERENCE_SOURCE_REQUIRED")
            if reference_source in values:
                _error("REFERENCE_SOURCE_OUTPUT_COLLISION")
            source_key_env = reference_value["source_key_env"]
            if (
                not isinstance(source_key_env, str)
                or re.fullmatch(r"AIRAG_[A-Z0-9_]+_KEY_HEX", source_key_env) is None
                or source_key_env in {*KEY_NAMES.values(), PROFILE_SOURCE_KEY_ENV}
            ):
                _error("INVALID_REFERENCE_SOURCE_KEY_ENV")
            raw_allowlist = reference_value["source_allowlist"]
            if not isinstance(raw_allowlist, list):
                _error("INVALID_REFERENCE_SOURCE_ALLOWLIST")
            try:
                allowlist = tuple(
                    (item[0], item[1])
                    for item in raw_allowlist
                    if isinstance(item, list) and len(item) == 2
                    and all(isinstance(value, str) for value in item)
                )
            except (TypeError, IndexError):
                _error("INVALID_REFERENCE_SOURCE_ALLOWLIST")
            from .reference import ALLOWED_TOUR_SOURCES
            if len(allowlist) != len(raw_allowlist) or allowlist != ALLOWED_TOUR_SOURCES:
                _error("REFERENCE_SOURCE_ALLOWLIST_MISMATCH")
            snapshot_value = reference_value.get(
                "snapshot_root", str(root / "reference-snapshots"),
            )
            snapshot_root = _absolute(snapshot_value, "INVALID_REFERENCE_SNAPSHOT_ROOT")
            if not _inside(snapshot_root, root):
                _error("REFERENCE_SNAPSHOT_OUTSIDE_PROJECT")
            if snapshot_root in values or any(
                snapshot_root in item.parents or item in snapshot_root.parents
                for item in values
            ):
                _error("OUTPUT_PATH_COLLISION")
            endpoints = []
            for field in ("embedding_endpoint_override", "llm_endpoint_override"):
                endpoint = reference_value.get(field)
                if endpoint is not None and (
                    not isinstance(endpoint, str)
                    or not endpoint.startswith(("http://", "https://"))
                ):
                    _error("INVALID_REFERENCE_ENDPOINT_OVERRIDE")
                endpoints.append(endpoint)
            reference = ReferenceGroupConfig(
                reference_source, source_key_env, allowlist, snapshot_root,
                endpoints[0], endpoints[1],
            )
        token_mode = payload.get("token_mode", "estimated")
        if token_mode not in {"estimated", "exact"}:
            _error("INVALID_TOKEN_MODE")
        allow_gaps = payload.get("allow_gaps", False)
        memory_enabled = payload.get("memory_enabled", False)
        memory_endpoint = payload.get("memory_endpoint")
        memory_model = payload.get("memory_model")
        poll_seconds = payload.get("poll_seconds", 30)
        if type(allow_gaps) is not bool or type(memory_enabled) is not bool:
            _error("INVALID_RUNTIME_FLAGS")
        if memory_enabled and (
            not isinstance(memory_endpoint, str) or not memory_endpoint
            or not isinstance(memory_model, str) or not memory_model
        ):
            _error("MEMORY_PROVIDER_CONFIG_REQUIRED")
        if not memory_enabled and (memory_endpoint is not None or memory_model is not None):
            _error("MEMORY_PROVIDER_WITHOUT_ENABLEMENT")
        if type(poll_seconds) is not int or not 1 <= poll_seconds <= 3600:
            _error("INVALID_POLL_SECONDS")
        return cls(
            root, owner_id, tenant_id, project_id,
            outputs["consumer_db"], outputs["projection_db"], outputs["archive_root"],
            outputs["backup_root"], profile_source, profile_key, collection,
            tuple(sources), reference, token_mode, allow_gaps, memory_enabled,
            memory_endpoint, memory_model, poll_seconds,
        )

    @property
    def scope(self) -> AuthenticatedScope:
        return AuthenticatedScope(
            self.owner_id, self.tenant_id, self.project_id,
            tuple(source.session_id for source in self.sources),
        )

    def public_dict(self) -> dict[str, object]:
        return {
            "project_root": str(self.project_root), "owner_id": self.owner_id,
            "tenant_id": self.tenant_id, "project_id": self.project_id,
            "consumer_db": str(self.consumer_db), "projection_db": str(self.projection_db),
            "archive_root": str(self.archive_root), "backup_root": str(self.backup_root),
            "profile_source_db": str(self.profile_source_db), "profile_key": self.profile_key,
            "collection": self.collection,
            "sources": [source.to_dict() for source in self.sources],
            "reference": None if self.reference is None else self.reference.public_dict(),
            "token_mode": self.token_mode, "allow_gaps": self.allow_gaps,
            "memory_enabled": self.memory_enabled,
            "memory_endpoint": self.memory_endpoint, "memory_model": self.memory_model,
            "poll_seconds": self.poll_seconds,
        }


@dataclass(frozen=True)
class RuntimeHooks:
    """Explicit test seams; production defaults use bridge and memory modules."""

    bridge: object | None = None
    memory: object | None = None
    memory_extractor: Callable[[object], object] | None = None
    memory_verifier: Callable[..., object] | None = None


_RUNTIME_SCHEMA = (
    """CREATE TABLE IF NOT EXISTS airag_runtime_binding (
        singleton INTEGER PRIMARY KEY CHECK(singleton=1), owner_id TEXT NOT NULL,
        tenant_id TEXT NOT NULL, project_id TEXT NOT NULL,
        profile_key TEXT NOT NULL, collection_name TEXT NOT NULL,
        token_mode TEXT NOT NULL, sources_json TEXT NOT NULL)""",
    """CREATE TABLE IF NOT EXISTS airag_runtime_state (
        state_key TEXT PRIMARY KEY, state_value TEXT NOT NULL)""",
)


class AIRAGRuntime:
    def __init__(
        self, config: RuntimeConfig, *, environ: Mapping[str, str],
        clock: Callable[[], datetime], tokenizer: Callable[[str], int] | None = None,
        hooks: RuntimeHooks | None = None,
    ) -> None:
        if not isinstance(config, RuntimeConfig):
            _error("RUNTIME_CONFIG_REQUIRED")
        if not callable(clock):
            _error("AWARE_CLOCK_REQUIRED")
        if config.token_mode == "exact" and not callable(tokenizer):
            _error("EXACT_TOKENIZER_REQUIRED")
        # This must remain before locks, directories, or databases are created.
        self.keys = load_store_keys(
            ("consumer_ledger", "projection_db", "archive"), environ,
        )
        raw_source_key = environ.get(PROFILE_SOURCE_KEY_ENV)
        if raw_source_key is None or raw_source_key == "":
            self.profile_source_key = None
        elif not isinstance(raw_source_key, str) or re.fullmatch(
            r"[0-9a-fA-F]{64}", raw_source_key,
        ) is None:
            _error("MISSING_OR_INVALID_PROFILE_SOURCE_KEY")
        else:
            self.profile_source_key = bytes.fromhex(raw_source_key)
            if self.profile_source_key in self.keys.values():
                _error("PROFILE_SOURCE_KEY_MUST_BE_DISTINCT")
        if (
            (not config.projection_db.exists() or not config.consumer_db.exists())
            and self.profile_source_key is None
        ):
            _error("MISSING_OR_INVALID_PROFILE_SOURCE_KEY")
        self.reference_source_key = None
        if config.reference is not None:
            raw_reference_key = environ.get(config.reference.source_key_env)
            if not isinstance(raw_reference_key, str) or re.fullmatch(
                r"[0-9a-fA-F]{64}", raw_reference_key,
            ) is None:
                _error("MISSING_OR_INVALID_REFERENCE_SOURCE_KEY")
            self.reference_source_key = bytes.fromhex(raw_reference_key)
            distinct = {*self.keys.values()}
            if self.profile_source_key is not None:
                distinct.add(self.profile_source_key)
            if self.reference_source_key in distinct:
                _error("REFERENCE_SOURCE_KEY_MUST_BE_DISTINCT")
        self.config = config
        self.clock = clock
        self.tokenizer = tokenizer
        self.hooks = hooks or RuntimeHooks()
        self._environ = environ

    @contextmanager
    def _lock(self):
        path = self.config.project_root / ".airag-runtime.lock"
        try:
            fd = os.open(path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
        except OSError:
            _error("PROJECT_LOCK_FAILED")
        lock = os.fdopen(fd, "r+b")
        try:
            if not stat.S_ISREG(os.fstat(lock.fileno()).st_mode):
                _error("PROJECT_LOCK_FAILED")
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                _error("PROJECT_BUSY")
            yield
        finally:
            lock.close()

    def _bridge(self) -> object:
        return self.hooks.bridge or importlib.import_module("airag_consumer.bridge")

    def _memory(self) -> object:
        return self.hooks.memory or importlib.import_module("airag_consumer.memory")

    def _open_ledger(self, *, create: bool = False) -> Ledger:
        if not create and not self.config.consumer_db.exists():
            _error("RUNTIME_NOT_INITIALIZED")
        return open_ledger(self.config.consumer_db, self.keys["consumer_ledger"])

    def _open_projection(self, *, create: bool = False):
        if self.config.projection_db.exists():
            return open_encrypted(self.config.projection_db, self.keys["projection_db"])
        if not create:
            _error("RUNTIME_NOT_INITIALIZED")
        return init_db(self.config.projection_db, self.keys["projection_db"])

    def _lifecycle(self, ledger: Ledger, *, clock: Callable[[], datetime] | None = None) -> Lifecycle:
        return Lifecycle(
            ledger._con, clock=clock or self.clock, tokenizer=self.tokenizer,
            token_mode=self.config.token_mode,
        )

    def _initialize_runtime_tables(self, ledger: Ledger) -> None:
        con = ledger._con
        try:
            con.execute("BEGIN IMMEDIATE")
            for statement in _RUNTIME_SCHEMA:
                con.execute(statement)
            binding = (
                self.config.owner_id, self.config.tenant_id, self.config.project_id,
                self.config.profile_key, self.config.collection, self.config.token_mode,
                _json([source.to_dict() for source in self.config.sources]),
            )
            row = con.execute(
                """SELECT owner_id,tenant_id,project_id,profile_key,collection_name,
                          token_mode,sources_json FROM airag_runtime_binding WHERE singleton=1""",
            ).fetchone()
            if row is None:
                con.execute(
                    "INSERT INTO airag_runtime_binding VALUES (1,?,?,?,?,?,?,?)", binding,
                )
            elif row != binding:
                _error("RUNTIME_BINDING_MISMATCH")
            con.execute("COMMIT")
        except BaseException:
            if con.in_transaction:
                con.execute("ROLLBACK")
            raise

    def _profile_descriptor(self, projection: Any) -> dict[str, object] | None:
        try:
            embedding, normalizer = profiles.config_from_profile(
                projection, self.config.profile_key,
            )
            llm = profiles.llm_from_profile(projection, self.config.profile_key)
            row = projection.execute(
                """SELECT space_id,chunker_config FROM processing_profiles
                   WHERE profile_key=?""",
                (self.config.profile_key,),
            ).fetchone()
        except Exception:
            return None
        if row is None:
            return None
        value = {
            "profile_key": self.config.profile_key,
            "space_id": row[0],
            "embedding": asdict(embedding),
            "normalizer": normalizer,
            "chunker": json.loads(row[1]),
            "llm": None if llm is None else asdict(llm),
        }
        value["descriptor_sha256"] = hashlib.sha256(
            _json(value).encode("utf-8"),
        ).hexdigest()
        return value

    def _stored_profile_receipt(self, ledger: Ledger) -> dict[str, object] | None:
        row = ledger._con.execute(
            "SELECT state_value FROM airag_runtime_state WHERE state_key='profile_install_receipt'",
        ).fetchone()
        if row is None:
            return None
        try:
            value = json.loads(row[0])
        except (TypeError, json.JSONDecodeError):
            _error("INVALID_PROFILE_INSTALL_RECEIPT")
        if not isinstance(value, dict):
            _error("INVALID_PROFILE_INSTALL_RECEIPT")
        return value

    def _record_profile_receipt(self, ledger: Ledger, descriptor: dict[str, object]) -> None:
        ledger._con.execute(
            """INSERT INTO airag_runtime_state VALUES ('profile_install_receipt',?)
               ON CONFLICT(state_key) DO UPDATE SET state_value=excluded.state_value""",
            (_json(descriptor),),
        )

    def _install_profile(self, ledger: Ledger, projection: Any) -> dict[str, object]:
        descriptor = self._profile_descriptor(projection)
        stored = self._stored_profile_receipt(ledger)
        if descriptor is not None and stored == descriptor:
            return {
                "profile_key": self.config.profile_key,
                "space_id": descriptor["space_id"],
                "llm_enrichment": descriptor["llm"] is not None,
                "reused_verified_target": True,
            }
        if self.profile_source_key is None:
            _error("MISSING_OR_INVALID_PROFILE_SOURCE_KEY")
        _regular(self.config.profile_source_db, "REGULAR_PROFILE_SOURCE_REQUIRED")
        bridge = self._bridge()
        install = getattr(bridge, "install_captured_profile", None)
        if not callable(install):
            _error("BRIDGE_INSTALL_PROFILE_API_UNAVAILABLE")
        source = open_readonly(self.config.profile_source_db, self.profile_source_key)
        try:
            result = install(source, projection, self.config.profile_key)
        finally:
            source.close()
        if not isinstance(result, dict) or result.get("profile_key") != self.config.profile_key:
            _error("PROFILE_INSTALLATION_MISMATCH")
        descriptor = self._profile_descriptor(projection)
        if descriptor is None:
            _error("PROFILE_INSTALLATION_MISMATCH")
        self._record_profile_receipt(ledger, descriptor)
        return result

    def init(self) -> dict[str, object]:
        with self._lock():
            for directory in (self.config.archive_root, self.config.backup_root):
                if directory.exists():
                    _directory(directory, "INVALID_OUTPUT_DIRECTORY")
                else:
                    if directory == managed_backup_root(self.config.project_id):
                        directory.mkdir(mode=0o700, parents=True)
                        _no_symlink_ancestors(directory)
                    else:
                        directory.mkdir(mode=0o700)
            if self.config.reference is not None:
                snapshot_root = self.config.reference.snapshot_root
                if snapshot_root.exists():
                    _directory(snapshot_root, "INVALID_REFERENCE_SNAPSHOT_ROOT")
                else:
                    snapshot_root.mkdir(mode=0o700)
            ledger = self._open_ledger(create=True)
            projection = None
            try:
                self._initialize_runtime_tables(ledger)
                lifecycle = self._lifecycle(ledger)
                lifecycle.refresh(self.config.scope)
                projection = self._open_projection(create=True)
                profile = self._install_profile(ledger, projection)
                return {
                    "initialized": True, "scope": self.config.scope.to_dict(),
                    "profile": profile, "token_mode": self.config.token_mode,
                }
            finally:
                if projection is not None:
                    projection.close()
                ledger.close()

    def _collection_pass(self, ledger: Ledger) -> list[dict[str, object]]:
        results = []
        for source in self.config.sources:
            result = collect_codex_rollout(
                ledger,
                source_path=source.path,
                allowed_real_paths=(source.path,),
                source_id=source.source_id,
                expected_session_id=source.session_id,
                expected_scope=AccessScope(
                    self.config.tenant_id, self.config.project_id, source.session_id,
                ),
                allow_gaps=self.config.allow_gaps,
                clock=self.clock,
            )
            results.append(_collector_dict(result))
        return results

    def _publish(self, lifecycle: Lifecycle, projection: Any) -> dict[str, object]:
        bridge = self._bridge()
        publish = getattr(bridge, "publish_pending_windows", None)
        if not callable(publish):
            _error("BRIDGE_PUBLISH_API_UNAVAILABLE")
        result = publish(
            lifecycle, self.config.scope, projection,
            collection=self.config.collection, profile_key=self.config.profile_key,
        )
        if not isinstance(result, list):
            _error("INVALID_BRIDGE_RESULT")
        return {
            "attempted": len(result),
            "succeeded": sum(item.get("ok") is True for item in result if isinstance(item, dict)),
            "items": result,
        }

    def _extract_memory(self, lifecycle: Lifecycle, *, concurrency: int = 1) -> dict[str, object]:
        if type(concurrency) is not int or concurrency not in (1, 2):
            _error("INVALID_MEMORY_CONCURRENCY")
        limits = {
            "batch_input_limit_bytes": MEMORY_BATCH_INPUT_BYTES,
            "max_messages_per_batch": MEMORY_MAX_MESSAGES_PER_BATCH,
        }
        if not self.config.memory_enabled:
            return {
                "enabled": False, "created": 0, "pending": 0, "failed": 0,
                **limits,
            }
        memory = self._memory()
        extract = getattr(memory, "extract_memories" if concurrency == 1 else "extract_memory_batches", None)
        if not callable(extract):
            _error("MEMORY_EXTRACTION_API_UNAVAILABLE")
        extractor = self.hooks.memory_extractor
        if extractor is None:
            config_type = getattr(memory, "OpenAICompatibleMemoryConfig", None)
            extractor_type = getattr(memory, "OpenAICompatibleMemoryExtractor", None)
            if not callable(config_type) or not callable(extractor_type):
                _error("MEMORY_PROVIDER_API_UNAVAILABLE")

            api_key = self._environ.get("AIRAG_MEMORY_API_KEY")
            if api_key is not None and (not isinstance(api_key, str) or not api_key):
                _error("INVALID_MEMORY_API_KEY")
            api_key_provider = None
            if api_key is not None:
                def api_key_provider() -> str:
                    return api_key

            extractor = extractor_type(config_type(
                endpoint=self.config.memory_endpoint,
                model=self.config.memory_model,
                api_key_provider=api_key_provider,
            ))
        result = extract(
            lifecycle, self.config.scope, extractor=extractor,
            model_id=self.config.memory_model,
            verifier=self.hooks.memory_verifier, clock=self.clock,
            batch_input_bytes=MEMORY_BATCH_INPUT_BYTES,
            max_messages_per_batch=MEMORY_MAX_MESSAGES_PER_BATCH,
            **({"concurrency": concurrency} if concurrency > 1 else {}),
        )
        if concurrency > 1:
            if not isinstance(result, dict):
                _error("INVALID_MEMORY_RESULT")
            return {"enabled": True, **limits, **result}
        to_dict = getattr(result, "to_dict", None)
        if not callable(to_dict):
            _error("INVALID_MEMORY_RESULT")
        payload = to_dict()
        if not isinstance(payload, dict):
            _error("INVALID_MEMORY_RESULT")
        return {"enabled": True, **limits, **payload}

    def _archive_pending(self, lifecycle: Lifecycle) -> list[dict[str, object]]:
        candidates = lifecycle.archive_candidates(self.config.scope)
        groups: dict[tuple[str, str, str], list[dict[str, object]]] = defaultdict(list)
        for candidate in candidates:
            archive_scope = candidate.get("archive_scope")
            if (
                not isinstance(archive_scope, list) or len(archive_scope) != 3
                or any(not isinstance(item, str) for item in archive_scope)
                or not isinstance(candidate.get("record"), dict)
                or not isinstance(candidate.get("candidate_id"), str)
            ):
                _error("INVALID_ARCHIVE_CANDIDATE")
            groups[tuple(archive_scope)].append(candidate)
        receipts = []
        for scope_values, items in sorted(groups.items()):
            access = AccessScope(*scope_values)
            records = [item["record"] for item in items]
            receipt = write_archive(
                self.config.archive_root, self.keys["archive"], access, records,
            )
            verified = verify_archive(receipt.path, self.keys["archive"], access)
            if verified != receipt:
                _error("ARCHIVE_VERIFICATION_MISMATCH")
            lifecycle.confirm_archive(
                self.config.scope,
                candidate_ids=[item["candidate_id"] for item in items], receipt=receipt,
            )
            receipts.append({
                "bundle_id": receipt.bundle_id, "path": receipt.path,
                "records": receipt.records, "ciphertext_sha256": receipt.ciphertext_sha256,
                "scope": list(scope_values),
            })
        return receipts

    def _last_verified_backup(self, ledger: Ledger) -> datetime | None:
        row = ledger._con.execute(
            "SELECT state_value FROM airag_runtime_state WHERE state_key='last_verified_backup'",
        ).fetchone()
        if row is None:
            return None
        try:
            value = datetime.fromisoformat(row[0])
        except ValueError:
            _error("INVALID_RUNTIME_STATE")
        if value.tzinfo is None or value.utcoffset() is None:
            _error("INVALID_RUNTIME_STATE")
        return value

    def _record_verified_backup(self, ledger: Ledger, value: datetime, path: Path) -> None:
        data = _json({"completed_at": value.isoformat(), "path": str(path)})
        ledger._con.execute(
            """INSERT INTO airag_runtime_state VALUES ('last_verified_backup',?)
               ON CONFLICT(state_key) DO UPDATE SET state_value=excluded.state_value""",
            (value.isoformat(),),
        )
        ledger._con.execute(
            """INSERT INTO airag_runtime_state VALUES ('last_verified_backup_receipt',?)
               ON CONFLICT(state_key) DO UPDATE SET state_value=excluded.state_value""",
            (data,),
        )

    def _verified_backup_ids(self) -> list[str]:
        result = []
        for path in self.config.backup_root.iterdir():
            if path.is_symlink() or not path.is_dir() or not path.name.startswith("airag-set-"):
                continue
            manifest = path / "manifest.json"
            if manifest.is_symlink() or not manifest.is_file():
                continue
            try:
                data = json.loads(manifest.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError):
                continue
            if data.get("owner") == "airag-operations-v1" and data.get("state") == "verified":
                result.append(path.name)
        return sorted(result)

    def _confirmed_archives(self, ledger: Ledger) -> list[dict[str, object]]:
        rows = ledger._con.execute(
            """SELECT DISTINCT archive_receipt_json,payload_json
               FROM airag_lifecycle_archive_queue
               WHERE state='confirmed' AND archive_receipt_json IS NOT NULL""",
        ).fetchall()
        grouped: dict[str, dict[str, object]] = {}
        for receipt_json, payload_json in rows:
            receipt = json.loads(receipt_json)
            record = json.loads(payload_json)
            bundle = receipt.get("bundle_id")
            if not isinstance(bundle, str) or len(bundle) != 64:
                _error("INVALID_ARCHIVE_RECEIPT_STATE")
            item = grouped.setdefault(bundle, {"receipt": receipt, "scopes": set()})
            item["scopes"].add(tuple(record["scope"]))
        result = []
        for bundle, item in grouped.items():
            if len(item["scopes"]) != 1:
                _error("ARCHIVE_RECEIPT_SCOPE_CONFLICT")
            receipt = item["receipt"]
            path = Path(receipt["path"])
            if (
                not path.is_absolute() or path.parent != self.config.archive_root
                or path.is_symlink() or not path.is_file()
            ):
                _error("UNTRUSTED_ARCHIVE_RECEIPT_PATH")
            result.append({
                "bundle_id": bundle, "path": path,
                "scope": next(iter(item["scopes"])),
                "ciphertext_sha256": receipt["ciphertext_sha256"],
                "records": receipt["records"],
            })
        return sorted(result, key=lambda item: item["bundle_id"])

    def _archive_components(
        self, archives: Sequence[dict[str, object]],
    ) -> dict[str, dict[str, object]]:
        result = {
            f"archive_{item['bundle_id'][:16]}": item for item in archives
        }
        if len(result) != len(archives):
            _error("ARCHIVE_COMPONENT_NAME_COLLISION")
        return result

    def _verify_ledger_links(self, ledger: Ledger) -> None:
        for source_id, next_offset in ledger._con.execute(
            "SELECT source_id,next_offset FROM sources ORDER BY source_id",
        ):
            intervals = ledger._con.execute(
                """SELECT start_offset,end_offset FROM deliveries WHERE source_id=?
                   UNION ALL SELECT start_offset,end_offset FROM rejections WHERE source_id=?
                   ORDER BY start_offset""", (source_id, source_id),
            ).fetchall()
            cursor = 0
            for start, end in intervals:
                if start != cursor or end <= start:
                    _error("RESTORED_LEDGER_CHECKPOINT_MISMATCH")
                cursor = end
            if cursor != next_offset:
                _error("RESTORED_LEDGER_CHECKPOINT_MISMATCH")
            for start, end, record_count in ledger._con.execute(
                """SELECT start_offset,end_offset,record_count FROM deliveries
                   WHERE source_id=? ORDER BY start_offset""", (source_id,),
            ).fetchall():
                stored = ledger._con.execute(
                    """SELECT count(*) FROM records WHERE source_id=?
                       AND start_offset>=? AND end_offset<=?""",
                    (source_id, start, end),
                ).fetchone()[0]
                if stored != record_count:
                    _error("RESTORED_LEDGER_RECEIPT_MISMATCH")
        collector_table = ledger._con.execute(
            """SELECT 1 FROM sqlite_master WHERE type='table'
               AND name='airag_rollout_collector_sources'""",
        ).fetchone()
        if collector_table is not None:
            for normalized_source, normalized_offset in ledger._con.execute(
                """SELECT normalized_source_id,next_normalized_offset
                   FROM airag_rollout_collector_sources""",
            ).fetchall():
                if ledger.checkpoint(normalized_source) != normalized_offset:
                    _error("RESTORED_COLLECTOR_CHECKPOINT_MISMATCH")

    def _restore_link_check(self) -> Callable[[Mapping[str, Path], datetime], None]:
        def check(restored: Mapping[str, Path], current_now: datetime) -> None:
            restored_ledger = open_ledger(restored["consumer"], self.keys["consumer_ledger"])
            try:
                self._verify_ledger_links(restored_ledger)
                stored_profile = self._stored_profile_receipt(restored_ledger)
                if stored_profile is None:
                    _error("RESTORED_PROFILE_RECEIPT_MISSING")
                restored_lifecycle = self._lifecycle(
                    restored_ledger, clock=lambda: current_now,
                )
                restored_state = restored_lifecycle.refresh(self.config.scope)
                if not restored_state["read_gate"]["open"]:
                    _error("RESTORED_EXPIRY_RECONCILIATION_FAILED")
                archive_components = self._archive_components(
                    self._confirmed_archives(restored_ledger),
                )
                if set(restored) != {"consumer", "projection", *archive_components}:
                    _error("RESTORED_COMPONENT_SET_MISMATCH")
            finally:
                restored_ledger.close()
            projection = open_encrypted(restored["projection"], self.keys["projection_db"])
            try:
                if self._profile_descriptor(projection) != stored_profile:
                    _error("RESTORED_PROFILE_RECEIPT_MISMATCH")
                bridge = self._bridge()
                verify_links = getattr(bridge, "verify_projection_links", None)
                if not callable(verify_links):
                    _error("BRIDGE_VERIFY_API_UNAVAILABLE")
                result = verify_links(
                    restored_state, projection, collection=self.config.collection,
                    profile_key=self.config.profile_key,
                )
                if not isinstance(result, dict):
                    _error("INVALID_BRIDGE_RESULT")
            finally:
                projection.close()
            for name, archive in archive_components.items():
                scope = AccessScope(*archive["scope"])
                receipt = verify_archive(restored[name], self.keys["archive"], scope)
                if (
                    receipt.bundle_id != archive["bundle_id"]
                    or receipt.records != archive["records"]
                ):
                    _error("RESTORED_ARCHIVE_RECEIPT_MISMATCH")
        return check

    def _backup(self, ledger: Ledger, *, force: bool = False) -> dict[str, object]:
        now = _aware(self.clock)
        previous = self._last_verified_backup(ledger)
        decision = backup_due(now, previous)
        if not force and not decision.due:
            return {
                "due": False, "created": False, "slot": decision.slot.isoformat(),
                "last_verified_success": None if previous is None else previous.isoformat(),
            }
        archives = self._confirmed_archives(ledger)
        archive_components = self._archive_components(archives)
        databases = [
            DatabaseSource("consumer", self.config.consumer_db, self.keys["consumer_ledger"]),
            DatabaseSource("projection", self.config.projection_db, self.keys["projection_db"]),
        ]
        archive_sources = [
            ArchiveSource(name, item["path"]) for name, item in archive_components.items()
        ]
        backup = create_backup_set(
            self.config.backup_root, databases, archive_sources,
            self._restore_link_check(), now=now,
        )
        self._record_verified_backup(ledger, now, backup)
        removed = prune_backup_sets(
            self.config.backup_root, now=now, newest_verified=backup,
        )
        return {
            "due": decision.due, "created": True, "catchup": decision.catchup,
            "slot": decision.slot.isoformat(), "path": str(backup),
            "pruned": [str(path) for path in removed],
            "last_verified_success": now.isoformat(),
        }

    def run_once(
        self, *, task_completed: bool = False, explicit_save: bool = False,
    ) -> dict[str, object]:
        with self._lock():
            ledger = self._open_ledger()
            projection = None
            try:
                self._initialize_runtime_tables(ledger)
                projection = self._open_projection()
                lifecycle = self._lifecycle(ledger)
                collected = self._collection_pass(ledger)
                lifecycle_state = lifecycle.refresh(
                    self.config.scope,
                    task_completed=task_completed, explicit_save=explicit_save,
                )
                published = self._publish(lifecycle, projection)
                memories = self._extract_memory(lifecycle)
                # Provider work may have crossed an expiry/checkpoint boundary.
                lifecycle_state = lifecycle.refresh(self.config.scope)
                archived = self._archive_pending(lifecycle)
                backup = self._backup(ledger)
                return {
                    "collected": collected, "lifecycle": _safe_lifecycle(lifecycle_state),
                    "published": published, "memory": memories,
                    "archives": archived, "backup": backup,
                }
            finally:
                if projection is not None:
                    projection.close()
                ledger.close()

    def status(self) -> dict[str, object]:
        with self._lock():
            ledger = self._open_ledger()
            try:
                self._initialize_runtime_tables(ledger)
                lifecycle = self._lifecycle(ledger)
                state = lifecycle.refresh(self.config.scope)
                last_backup = self._last_verified_backup(ledger)
                gaps = ledger._con.execute(
                    """SELECT count(*) FROM airag_rollout_collector_plans
                       WHERE disposition='gap' AND state='finalized'""",
                ).fetchone()[0] if ledger._con.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='airag_rollout_collector_plans'",
                ).fetchone() else 0
                collector_sources = []
                collector_table = ledger._con.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='airag_rollout_collector_sources'",
                ).fetchone()
                if collector_table is not None:
                    enrollment = {item.source_id: item for item in self.config.sources}
                    for source_id, next_offset in ledger._con.execute(
                        """SELECT source_id,next_native_offset
                           FROM airag_rollout_collector_sources ORDER BY source_id""",
                    ).fetchall():
                        source = enrollment.get(source_id)
                        if source is None:
                            _error("COLLECTOR_SOURCE_BINDING_MISMATCH")
                        _regular(source.path, "REGULAR_SOURCE_REQUIRED")
                        current_size = source.path.stat().st_size
                        source_gaps = ledger._con.execute(
                            """SELECT count(*) FROM airag_rollout_collector_plans
                               WHERE source_id=? AND disposition='gap' AND state='finalized'""",
                            (source_id,),
                        ).fetchone()[0]
                        complete = next_offset == current_size
                        collector_sources.append({
                            "source_id": source_id,
                            "committed_native_offset": next_offset,
                            "current_snapshot_bytes": current_size,
                            "complete_through_current_snapshot": complete,
                            "gap_count": source_gaps,
                            "coverage_complete": complete and source_gaps == 0,
                        })
                windows = state["windows"]
                memory_table = ledger._con.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='airag_memory_candidates'",
                ).fetchone()
                awaiting_memory_ids = [] if memory_table is None else [
                    row[0] for row in ledger._con.execute(
                        """SELECT c.candidate_id FROM airag_memory_candidates c
                           JOIN airag_memory_extractions e ON e.extraction_id=c.extraction_id
                           WHERE e.owner_id=? AND e.tenant_id=? AND e.project_id=?
                           AND c.disposition='awaiting_confirmation'
                           ORDER BY c.candidate_id""",
                        (
                            self.config.owner_id, self.config.tenant_id,
                            self.config.project_id,
                        ),
                    ).fetchall()
                ]
                backup_ids = self._verified_backup_ids()
                reference_snapshots = []
                if self.config.reference is not None:
                    reference_snapshots = sorted(
                        path.name for path in self.config.reference.snapshot_root.iterdir()
                        if path.is_file() and not path.is_symlink()
                        and path.name.startswith("reference-") and path.suffix == ".db"
                    )
                return {
                    "scope": self.config.scope.to_dict(),
                    "read_gate": state["read_gate"],
                    "pending": sum(item["publication_state"] == "index_pending" for item in windows),
                    "failed": sum(item["publication_state"] == "failed" for item in windows),
                    "indexed": len(state["searchable_window_ids"]),
                    "active": len(state["active_window_ids"]),
                    "older_searchable": len(state["older_searchable_window_ids"]),
                    "expired": len(state["reduction"]["expired_message_keys"]),
                    "archive_pending": len(state["archive_only_expiry_candidates"]),
                    "visible_memories": len(state["visible_memory_ids"]),
                    "memory_awaiting_confirmation_ids": awaiting_memory_ids,
                    "gaps": gaps, "token_mode": self.config.token_mode,
                    "collector_sources": collector_sources,
                    "coverage_complete": bool(collector_sources) and {
                        item["source_id"] for item in collector_sources
                    } == {item.source_id for item in self.config.sources} and all(
                        item["coverage_complete"] for item in collector_sources
                    ),
                    "token_estimate_label": "estimated_utf8_bytes_div_4" if self.config.token_mode == "estimated" else None,
                    "last_verified_backup": None if last_backup is None else last_backup.isoformat(),
                    "verified_backup_ids": backup_ids,
                    "backup_count": len(backup_ids),
                    "reference_enabled": self.config.reference is not None,
                    "reference_source_count": 0 if self.config.reference is None else len(
                        self.config.reference.source_allowlist
                    ),
                    "reference_snapshot_count": len(reference_snapshots),
                }
            finally:
                ledger.close()

    def search(self, query: str, *, limit: int = 5) -> dict[str, object]:
        if not isinstance(query, str) or not query.strip() or type(limit) is not int or not 1 <= limit <= 100:
            _error("INVALID_SEARCH_REQUEST")
        with self._lock():
            ledger = self._open_ledger()
            projection = None
            try:
                lifecycle = self._lifecycle(ledger)
                before = lifecycle.refresh(self.config.scope)
                if not before["read_gate"]["open"]:
                    _error("CURRENT_TIME_EXPIRY_PASS_REQUIRED")
                projection = self._open_projection()
                bridge = self._bridge()
                search = getattr(bridge, "search_history", None)
                if not callable(search):
                    _error("BRIDGE_SEARCH_API_UNAVAILABLE")
                result = search(
                    lifecycle, self.config.scope, projection,
                    collection=self.config.collection, profile_key=self.config.profile_key,
                    query=query, top_k=limit,
                )
                if not isinstance(result, dict):
                    _error("INVALID_BRIDGE_RESULT")
                reference_result = None
                if self.config.reference is not None:
                    if self.reference_source_key is None:
                        _error("MISSING_OR_INVALID_REFERENCE_SOURCE_KEY")
                    from .reference import search_tour_reference
                    timestamp = _aware(self.clock).astimezone(timezone.utc).strftime(
                        "%Y%m%dT%H%M%S%fZ",
                    )
                    snapshot = self.config.reference.snapshot_root / (
                        f"reference-{timestamp}-{uuid.uuid4().hex}.db"
                    )
                    reference_result = search_tour_reference(
                        self.config.reference.source_db, self.reference_source_key,
                        snapshot, self.keys["projection_db"], self.config.scope,
                        query=query, top_k=limit,
                        embedding_endpoint_override=(
                            self.config.reference.embedding_endpoint_override
                        ),
                        llm_endpoint_override=self.config.reference.llm_endpoint_override,
                    )
                after = lifecycle.refresh(self.config.scope)
                if (
                    not after["read_gate"]["open"]
                    or before["searchable_window_ids"] != after["searchable_window_ids"]
                ):
                    _error("SEARCH_ELIGIBILITY_CHANGED")
                if reference_result is None:
                    return result
                return {
                    "label": "combined_query",
                    "scope": self.config.scope.to_dict(),
                    "query": query,
                    "groups": [
                        {"label": "conversation_memory", "result": result},
                        {"label": "existing_tour_reference", "result": reference_result},
                    ],
                    "conversation": result,
                    "reference": reference_result,
                    "ranking": {
                        "global_merge": False,
                        "reason": "conversation and existing-tour reference scores remain group-local",
                    },
                }
            finally:
                if projection is not None:
                    projection.close()
                ledger.close()

    def archive_search(self, query: str, *, limit: int = 20) -> dict[str, object]:
        if not isinstance(query, str) or type(limit) is not int or not 1 <= limit <= 100:
            _error("INVALID_ARCHIVE_SEARCH_REQUEST")
        with self._lock():
            ledger = self._open_ledger()
            try:
                lifecycle = self._lifecycle(ledger)
                lifecycle.refresh(self.config.scope)
                archives = self._confirmed_archives(ledger)
                results = []
                for item in archives:
                    path = Path(item["path"])
                    if path.parent != self.config.archive_root or path.is_symlink():
                        _error("UNTRUSTED_ARCHIVE_RECEIPT_PATH")
                    scope = AccessScope(*item["scope"])

                    def authorize(record: dict, expected=scope) -> bool:
                        return (
                            record.get("scope") == [
                                expected.tenant_id, expected.project_id, expected.stream_id,
                            ]
                            and expected.stream_id in self.config.scope.enrolled_streams
                            and isinstance(record.get("payload"), dict)
                            and record["payload"].get("owner_id") == self.config.owner_id
                        )

                    found = lookup_archive(
                        path, self.keys["archive"], scope,
                        explicit_request=True, authorize_record=authorize,
                        query=query, limit=max(1, limit - len(results)),
                    )
                    results.extend(found)
                    if len(results) >= limit:
                        break
                return {
                    "label": "historical_archive_audit_only",
                    "explicit_request": True, "results": results[:limit],
                }
            finally:
                ledger.close()

    def memory_confirm(self, candidate_id: str) -> dict[str, object]:
        _opaque(candidate_id, "INVALID_MEMORY_CANDIDATE_ID")
        with self._lock():
            ledger = self._open_ledger()
            try:
                lifecycle = self._lifecycle(ledger)
                lifecycle.refresh(self.config.scope)
                memory = self._memory()
                confirm = getattr(memory, "confirm_candidate", None)
                if not callable(confirm):
                    _error("MEMORY_CONFIRM_API_UNAVAILABLE")
                result = confirm(
                    lifecycle, self.config.scope, candidate_id, clock=self.clock,
                )
                if not isinstance(result, dict):
                    _error("INVALID_MEMORY_RESULT")
                return result
            finally:
                ledger.close()

    def backup(self, *, force: bool = True) -> dict[str, object]:
        with self._lock():
            ledger = self._open_ledger()
            try:
                self._initialize_runtime_tables(ledger)
                return self._backup(ledger, force=force)
            finally:
                ledger.close()

    def verify_backup(self, backup_id: str) -> dict[str, object]:
        _id(backup_id, "INVALID_BACKUP_ID")
        path = self.config.backup_root / backup_id
        if path.parent != self.config.backup_root or not path.name.startswith("airag-set-"):
            _error("INVALID_BACKUP_ID")
        with self._lock():
            ledger = self._open_ledger()
            try:
                data = verify_backup_set(
                    path,
                    {
                        "consumer": self.keys["consumer_ledger"],
                        "projection": self.keys["projection_db"],
                    },
                    self._restore_link_check(), now=_aware(self.clock),
                )
                return {
                    "backup_id": backup_id, "verified": True,
                    "completed_at": data["completed_at"],
                    "components": [item["name"] for item in data["components"]],
                }
            finally:
                ledger.close()


def _collector_dict(result: CollectorResult) -> dict[str, object]:
    value = asdict(result)
    value["coverage_gaps"] = [asdict(item) for item in result.coverage_gaps]
    return value


def _safe_lifecycle(state: Mapping[str, object]) -> dict[str, object]:
    """Return operational counters/IDs without conversation or memory text."""
    windows = state["windows"]
    return {
        "read_gate": state["read_gate"],
        "created_window_ids": state.get("created_window_ids", []),
        "searchable_window_ids": state["searchable_window_ids"],
        "active_window_ids": state["active_window_ids"],
        "older_searchable_window_ids": state["older_searchable_window_ids"],
        "pending_publication_ids": state["pending_publication_ids"],
        "window_states": [
            {
                "window_id": item["window_id"],
                "publication_state": item["publication_state"],
                "processing_state": item["processing_state"],
                "invalidated_reason": item["invalidated_reason"],
            }
            for item in windows
        ],
        "expired_count": len(state["reduction"]["expired_message_keys"]),
        "archive_pending_count": len(state["archive_only_expiry_candidates"]),
        "visible_memory_count": len(state["visible_memory_ids"]),
    }
