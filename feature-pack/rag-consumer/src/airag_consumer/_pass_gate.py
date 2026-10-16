"""Gate in front of a consumer pass: a read-only quick_check of the two stores, and the pass-state file.

Runs in the pass child (which already holds the keys) after its streams point at /dev/null and before the pass.
A pass that was not shown to end cleanly is checked first: no state file, ``running``, or any invalid, unsafe or
foreign file all count as "not clean". A refused check never starts the pass, and neither does a state file that
cannot be written: there is no pass without a safe ``running`` mark. After a pass ends (normally or by an
exception) the mark becomes ``clean``. ``clean`` means "the process ended on its own", not "the database is
sound", and a power loss is not covered: only a forced kill of a live system leaves ``running`` behind.
Design: r17 section 6, errata 1 sections 1, 4 and 5, errata 2 sections 3 and 5, errata 3.

Nothing here prints or stores a value: results are enums and millisecond counts, and a database error's text is
never read. This module must stay import-light (stdlib and ``_result`` only); SQLCipher, the runtime and the core
are imported inside the functions that run after the child's streams were redirected.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import stat
import threading
import time
from typing import Callable, Sequence

from ._result import INTEGRITY_VERSION

STATE_VERSION = 1
STATE_MAX_BYTES = 256
CHECK_BUSY_TIMEOUT_MS = 1000
# Planned budget per database: 7 s per started 16 MiB (file plus WAL), at most 70 s. A planning value, not a guarantee:
# what is guaranteed is only the moment the main thread decides (see check_databases).
BUDGET_UNIT_S = 7.0
BUDGET_UNIT_BYTES = 16 * 1024 * 1024
BUDGET_CEILING_S = 70.0
_MS_MAX = 120_000.0
_PROGRESS_STEPS = 10_000


# ---- the pass-state file --------------------------------------------------------------------------------------


def project_id(consumer_db: str, projection_db: str) -> str:
    """16 hex digits that tell which pair of stores a state file belongs to (the paths themselves are not stored)."""
    joined = f"{os.fspath(consumer_db)}\n{os.fspath(projection_db)}".encode("utf-8")
    return hashlib.sha256(joined).hexdigest()[:16]


def state_is_clean(path: str, project: str) -> bool:
    """True only for a valid, private, regular ``clean`` file of this project; every other state means "check"."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return False
    try:
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1
            or info.st_mode & 0o077 or info.st_size > STATE_MAX_BYTES
        ):
            return False
        data = os.read(fd, STATE_MAX_BYTES + 1)
    except OSError:
        return False
    finally:
        os.close(fd)
    if len(data) > STATE_MAX_BYTES:
        return False
    try:
        record = json.loads(data)
    except ValueError:
        return False
    return (
        type(record) is dict and set(record) == {"v", "proj", "state"} and type(record["v"]) is int
        and record["v"] == STATE_VERSION and record["proj"] == project and record["state"] == "clean"
    )


def write_state(path: str, project: str, state: str) -> bool:
    """Replace the state file atomically (same-directory temporary file, mode 0600); False on any failure."""
    data = json.dumps(
        {"v": STATE_VERSION, "proj": project, "state": state}, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")
    temporary = f"{path}.{os.getpid()}.{time.time_ns()}.tmp"
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except OSError:
        return False
    try:
        try:
            view = memoryview(data)
            while view:
                written = os.write(fd, view)
                if written <= 0:
                    raise OSError("state write incomplete")
                view = view[written:]
        finally:
            os.close(fd)
        os.replace(temporary, path)
        return True
    except OSError:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        return False


# ---- the read-only check ------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Target:
    """One store to check: its label (an integrity enum name), path, raw key and identity test."""

    name: str
    path: str
    key: bytes
    identity: Callable[[object], bool]


def consumer_identity(con: object) -> bool:
    """The consumer ledger's own identity: ``meta.engine`` and ``user_version`` (never the core's ``db_meta``)."""
    from .ledger import ENGINE

    return (
        con.execute("SELECT engine FROM meta").fetchall() == [(ENGINE,)]  # type: ignore[attr-defined]
        and con.execute("PRAGMA user_version").fetchone() == (4,)  # type: ignore[attr-defined]
    )


def projection_identity(con: object) -> bool:
    """The core store's identity: ``db_meta`` engine tag and the current schema version."""
    from airag.db import connect

    row = con.execute("SELECT value FROM db_meta WHERE key='engine'").fetchone()  # type: ignore[attr-defined]
    return row == (connect.ENGINE_TAG,) and connect.read_schema_version(con) == connect.SCHEMA_VERSION  # type: ignore[arg-type]


def database_budget(path: str) -> float:
    """Planned seconds for one database: 7 per started 16 MiB of file plus WAL (one unit at least), at most 70."""
    size = 0
    for candidate in (path, path + "-wal"):
        try:
            size += os.stat(candidate).st_size
        except OSError:
            pass
    return min(BUDGET_CEILING_S, BUDGET_UNIT_S * max(1, math.ceil(size / BUDGET_UNIT_BYTES)))


def _limit(con: object, deadline_at: float, clock: Callable[[], float]) -> None:
    """Best effort: have SQLite abort a running statement once the planned time is over."""
    try:
        con.set_progress_handler(lambda: 1 if clock() > deadline_at else 0, _PROGRESS_STEPS)  # type: ignore[attr-defined]
    except Exception:
        pass


def _check_one(
    sqlcipher3: object, target: Target, deadline_at: float, clock: Callable[[], float], handle: dict[str, object],
) -> str:
    """One store, three stages: A open (read-only, same order as the core opener), B identity, C quick_check.

    The result names the stage that failed; no exception class or message is looked at or kept.
    """
    result = "open_error"
    con = None
    try:
        uri = Path(target.path).absolute().as_uri() + "?mode=ro"
        con = sqlcipher3.connect(uri, uri=True, isolation_level=None)  # type: ignore[attr-defined]
        handle["con"] = con
        _limit(con, deadline_at, clock)
        con.execute(f"PRAGMA key = \"x'{target.key.hex()}'\"")
        con.execute("PRAGMA temp_store=MEMORY")
        con.execute("PRAGMA query_only=ON")
        con.execute(f"PRAGMA busy_timeout={CHECK_BUSY_TIMEOUT_MS}")
        con.execute("SELECT count(*) FROM sqlite_master").fetchone()
        version = con.execute("PRAGMA cipher_version").fetchone()
        if not version or not version[0]:
            return "open_error"
        result = "identity_error"
        if not target.identity(con):
            return "identity_error"
        result = "not_ok"
        return "ok" if con.execute("PRAGMA quick_check").fetchall() == [("ok",)] else "not_ok"
    except Exception:
        return result
    finally:
        handle["con"] = None
        if con is not None:
            try:
                con.close()
            except Exception:
                pass


def check_databases(
    targets: Sequence[Target], *, sqlcipher3: object | None = None, clock: Callable[[], float] = time.monotonic,
) -> list[dict[str, object]]:
    """Check the stores one after the other in a daemon thread; the main thread decides by ``join(timeout)``.

    What is guaranteed is the moment of the decision: when the summed planned budgets are over, every store without
    a result is ``deadline`` (and the running connection is interrupted, best effort). A thread stuck in C code may
    outlive the decision; being a daemon it never keeps the process alive.
    """
    if sqlcipher3 is None:
        try:
            import sqlcipher3  # noqa: F811
        except Exception:
            return [{"db": target.name, "out": "open_error", "ms": 0.0} for target in targets]
    budgets = [database_budget(target.path) for target in targets]
    results: dict[str, str] = {}
    elapsed: dict[str, float] = {}
    begun_at: dict[str, float] = {}
    handle: dict[str, object] = {"con": None}

    def work() -> None:
        for target, budget in zip(targets, budgets):
            begun = clock()
            begun_at[target.name] = begun
            outcome = _check_one(sqlcipher3, target, begun + budget, clock, handle)
            elapsed[target.name] = clock() - begun
            results.setdefault(target.name, outcome)

    thread = threading.Thread(target=work, daemon=True)
    thread.start()
    thread.join(timeout=sum(budgets))
    if thread.is_alive():
        running = handle["con"]
        if running is not None:
            try:
                running.interrupt()  # type: ignore[attr-defined]
            except Exception:
                pass
    now = clock()
    rows: list[dict[str, object]] = []
    for target in targets:
        outcome = results.setdefault(target.name, "deadline")  # a result the thread already stored always wins
        seconds = elapsed.get(target.name)
        if seconds is None:
            begun = begun_at.get(target.name)
            seconds = 0.0 if begun is None else now - begun
        rows.append({"db": target.name, "out": outcome, "ms": min(max(round(seconds * 1000.0, 3), 0.0), _MS_MAX)})
    return rows


def refusal_for(rows: Sequence[dict[str, object]]) -> dict[str, str] | None:
    """Why the pass must not start (a reason code and a type token), or None when every store is ok.

    Proven damage outranks an unavailable check; otherwise the first store that is not ok names the refusal.
    """
    failed = [row for row in rows if row["out"] != "ok"]
    if not failed:
        return None
    for row in failed:
        if row["out"] == "not_ok":
            return {"code": "DATABASE_INTEGRITY_FAILED", "type": str(row["db"])}
    return {"code": "DATABASE_INTEGRITY_UNAVAILABLE", "type": str(failed[0]["db"])}


# ---- before and after a pass --------------------------------------------------------------------------------


@dataclass(frozen=True)
class Gate:
    """The gate's verdict: ``refusal`` set means the pass must not start; ``project`` None means "not applicable"."""

    project: str | None = None
    integrity: dict[str, object] | None = None
    refusal: dict[str, str] | None = None


def before_pass(config_path: str, state_file: str, consumer_key: bytes, projection_key: bytes) -> Gate:
    try:
        from .runtime import RuntimeConfig

        config = RuntimeConfig.load(config_path)
    except Exception:
        return Gate()  # an unusable config: the pass reports it itself, and nothing is checked or written here
    project = project_id(os.fspath(config.consumer_db), os.fspath(config.projection_db))
    integrity = None
    if not state_is_clean(state_file, project):
        rows = check_databases([
            Target("consumer", os.fspath(config.consumer_db), consumer_key, consumer_identity),
            Target("projection", os.fspath(config.projection_db), projection_key, projection_identity),
        ])
        integrity = {"v": INTEGRITY_VERSION, "dbs": rows}
        refusal = refusal_for(rows)
        if refusal is not None:
            return Gate(project, integrity, refusal)
    if not write_state(state_file, project, "running"):
        return Gate(project, integrity, {"code": "PASS_STATE_UNAVAILABLE", "type": "pass_state"})
    return Gate(project, integrity, None)


def after_pass(gate: Gate, state_file: str) -> None:
    """Mark the pass as ended on its own. A failed write leaves ``running``: the next tick checks again."""
    if gate.project is not None and gate.refusal is None:
        write_state(state_file, gate.project, "clean")
