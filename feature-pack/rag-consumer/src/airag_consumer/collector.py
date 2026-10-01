"""Restart-safe Codex rollout adapter for explicitly enrolled JSONL files.

The adapter stores only source identities, byte ranges, checksums, and safe
classification codes in its SQLCipher tables. Native message bodies are never
buffered durably. A record plan is committed before calling :class:`Ledger`, so
a crash after the ledger commit replays the same normalized bytes and receipt.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import stat
from typing import Callable, Iterable

from .events import AccessScope, EventError, parse_event
from .ledger import Ledger
from .redaction import redact_event


CONTENT_PART_SEPARATOR = "\n\n"
_EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()
_TABLE_PREFIX = "airag_rollout_collector_"
_EXCLUDED_TOP_LEVEL = {
    "session_meta": "EXCLUDED_SESSION_META",
    "metadata": "EXCLUDED_METADATA",
    "event_msg": "EXCLUDED_EVENT_MSG_DUPLICATE",
    "compacted": "EXCLUDED_COMPACTED_HISTORY",
    "world_state": "EXCLUDED_WORLD_STATE",
    "turn_context": "EXCLUDED_TURN_CONTEXT",
    "token_usage_record": "EXCLUDED_TOKEN_USAGE",
    "inter_agent_communication_metadata": "EXCLUDED_INTER_AGENT_METADATA",
}
_EXCLUDED_ROLES = {
    "system": "EXCLUDED_SYSTEM_ROLE",
    "developer": "EXCLUDED_DEVELOPER_ROLE",
}
_ALLOWED_ASSISTANT_PHASES = {"final_answer", "commentary"}


@dataclass(frozen=True)
class CoverageGap:
    start_offset: int
    end_offset: int
    native_sha256: str
    reason_code: str


@dataclass(frozen=True)
class CollectorResult:
    source_id: str
    captured_byte_limit: int
    committed_native_offset: int
    committed_normalized_offset: int
    accepted_count: int
    skipped_count: int
    gap_count: int
    pending_bytes: int
    coverage_gaps: tuple[CoverageGap, ...]
    complete_through_snapshot: bool
    coverage_complete: bool


@dataclass(frozen=True)
class _Source:
    source_id: str
    normalized_source_id: str
    incarnation: str
    next_native_offset: int
    prefix_sha256: str
    next_normalized_offset: int
    last_ordinal: int | None


@dataclass(frozen=True)
class _Classification:
    disposition: str
    reason_code: str
    ordinal: int | None
    normalized: bytes
    event_id: str | None
    message_id: str | None


@dataclass(frozen=True)
class _Plan:
    source_id: str
    native_start: int
    native_end: int
    native_sha256: str
    ordinal: int | None
    disposition: str
    reason_code: str
    normalized_start: int
    normalized_end: int
    normalized_sha256: str
    event_id: str | None
    message_id: str | None
    first_seen_at: str
    state: str


_SCHEMA = (
    f"""CREATE TABLE IF NOT EXISTS {_TABLE_PREFIX}sources (
        source_id TEXT PRIMARY KEY,
        normalized_source_id TEXT NOT NULL UNIQUE,
        source_path TEXT NOT NULL,
        real_path TEXT NOT NULL,
        device TEXT NOT NULL,
        inode TEXT NOT NULL,
        expected_session_id TEXT NOT NULL,
        tenant_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        incarnation TEXT NOT NULL,
        next_native_offset INTEGER NOT NULL CHECK(next_native_offset >= 0),
        prefix_sha256 TEXT NOT NULL,
        next_normalized_offset INTEGER NOT NULL CHECK(next_normalized_offset >= 0),
        last_ordinal INTEGER)""",
    f"""CREATE TABLE IF NOT EXISTS {_TABLE_PREFIX}plans (
        source_id TEXT NOT NULL REFERENCES {_TABLE_PREFIX}sources(source_id),
        native_start INTEGER NOT NULL,
        native_end INTEGER NOT NULL,
        native_sha256 TEXT NOT NULL,
        ordinal INTEGER,
        disposition TEXT NOT NULL CHECK(disposition IN ('accepted','skipped','gap')),
        reason_code TEXT NOT NULL,
        normalized_start INTEGER NOT NULL,
        normalized_end INTEGER NOT NULL,
        normalized_sha256 TEXT NOT NULL,
        event_id TEXT,
        message_id TEXT,
        first_seen_at TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('planned','finalized')),
        PRIMARY KEY(source_id, native_start))""",
)


def _safe_identity(value: object) -> str:
    if not isinstance(value, str) or not value or len(value) > 1024:
        raise EventError("INVALID_COLLECTOR_IDENTITY")
    if value != value.strip() or any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise EventError("INVALID_COLLECTOR_IDENTITY")
    return value


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonical(value: object) -> bytes:
    try:
        return json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeError):
        raise EventError("INVALID_NATIVE_RECORD") from None


def _pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise EventError("DUPLICATE_NATIVE_JSON_KEY")
        result[key] = value
    return result


def _nonfinite(_: str) -> None:
    raise EventError("NONFINITE_NATIVE_JSON_VALUE")


def _native_object(raw: bytes) -> dict[str, object]:
    try:
        value = json.loads(
            raw.decode("utf-8"), object_pairs_hook=_pairs, parse_constant=_nonfinite,
        )
    except EventError:
        raise
    except (UnicodeError, ValueError, RecursionError):
        raise EventError("INVALID_NATIVE_JSON") from None
    if not isinstance(value, dict):
        raise EventError("NATIVE_OBJECT_REQUIRED")
    return value


def _utc_timestamp(clock: Callable[[], datetime]) -> str:
    value = clock()
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        raise EventError("TIMEZONE_AWARE_CLOCK_REQUIRED")
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _ensure_schema(ledger: Ledger) -> None:
    con = ledger._con
    try:
        con.execute("BEGIN IMMEDIATE")
        for statement in _SCHEMA:
            con.execute(statement)
        con.execute("COMMIT")
    except BaseException:
        if con.in_transaction:
            con.execute("ROLLBACK")
        raise


def _open_enrolled(path_value: str | Path, allowed_real_paths: Iterable[str | Path]) -> tuple[int, str, os.stat_result]:
    supplied = os.fspath(path_value)
    if not os.path.isabs(supplied) or os.path.normpath(supplied) != supplied:
        raise EventError("EXACT_ABSOLUTE_SOURCE_PATH_REQUIRED")
    allowed = {os.fspath(item) for item in allowed_real_paths}
    if supplied not in allowed:
        raise EventError("UNENROLLED_SOURCE_PATH")
    try:
        link_stat = os.lstat(supplied)
    except OSError:
        raise EventError("SOURCE_OPEN_FAILED") from None
    if stat.S_ISLNK(link_stat.st_mode):
        raise EventError("SYMLINK_SOURCE_REJECTED")
    if not stat.S_ISREG(link_stat.st_mode):
        raise EventError("REGULAR_SOURCE_FILE_REQUIRED")
    real_path = os.path.realpath(supplied)
    if real_path != supplied:
        raise EventError("SOURCE_PATH_ESCAPE")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(supplied, flags)
        opened = os.fstat(fd)
    except OSError:
        raise EventError("SOURCE_OPEN_FAILED") from None
    if (opened.st_dev, opened.st_ino) != (link_stat.st_dev, link_stat.st_ino):
        os.close(fd)
        raise EventError("SOURCE_CHANGED_DURING_OPEN")
    return fd, real_path, opened


def _read_exact(fd: int, start: int, length: int) -> bytes:
    chunks: list[bytes] = []
    cursor = start
    remaining = length
    while remaining:
        chunk = os.pread(fd, min(remaining, 1_048_576), cursor)
        if not chunk:
            raise EventError("SOURCE_TRUNCATED")
        chunks.append(chunk)
        cursor += len(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _prefix_sha256(fd: int, end: int) -> str:
    digest = hashlib.sha256()
    cursor = 0
    while cursor < end:
        chunk = os.pread(fd, min(1_048_576, end - cursor), cursor)
        if not chunk:
            raise EventError("SOURCE_TRUNCATED")
        digest.update(chunk)
        cursor += len(chunk)
    return digest.hexdigest()


def _verify_session_meta(fd: int, expected_session_id: str, max_record_bytes: int) -> None:
    head = os.pread(fd, max_record_bytes + 2, 0)
    newline = head.find(b"\n")
    if newline < 0:
        if len(head) > max_record_bytes:
            raise EventError("RECORD_TOO_LARGE")
        raise EventError("SESSION_META_INCOMPLETE")
    if newline > max_record_bytes:
        raise EventError("RECORD_TOO_LARGE")
    record = _native_object(head[:newline])
    payload = record.get("payload")
    if record.get("type") != "session_meta" or not isinstance(payload, dict):
        raise EventError("SESSION_META_REQUIRED")
    if payload.get("id") != expected_session_id:
        raise EventError("SESSION_SCOPE_MISMATCH")


def _source_row(row: tuple) -> _Source:
    return _Source(row[0], row[1], row[2], row[3], row[4], row[5], row[6])


def _reload_source(ledger: Ledger, source_id: str) -> _Source:
    row = ledger._con.execute(
        f"""SELECT source_id,normalized_source_id,incarnation,next_native_offset,
                   prefix_sha256,next_normalized_offset,last_ordinal
            FROM {_TABLE_PREFIX}sources WHERE source_id=?""", (source_id,),
    ).fetchone()
    if row is None:
        raise EventError("COLLECTOR_SOURCE_MISSING")
    return _source_row(row)


def _load_or_create_source(
    ledger: Ledger, *, source_id: str, source_path: str, real_path: str,
    opened: os.stat_result, expected_session_id: str, expected_scope: AccessScope,
) -> _Source:
    con = ledger._con
    normalized_source_id = f"{source_id}:codex-rollout-normalized"
    seed = _canonical([
        "codex-rollout-incarnation-v1", real_path, expected_session_id,
        str(opened.st_dev), str(opened.st_ino),
    ])
    incarnation = f"codex-rollout:{_sha256(seed)}"
    try:
        con.execute("BEGIN IMMEDIATE")
        row = con.execute(
            f"""SELECT source_id,normalized_source_id,incarnation,next_native_offset,
                       prefix_sha256,next_normalized_offset,last_ordinal,
                       source_path,real_path,device,inode,expected_session_id,tenant_id,project_id
                FROM {_TABLE_PREFIX}sources WHERE source_id=?""", (source_id,),
        ).fetchone()
        if row is None:
            con.execute(
                f"INSERT INTO {_TABLE_PREFIX}sources VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    source_id, normalized_source_id, source_path, real_path,
                    str(opened.st_dev), str(opened.st_ino), expected_session_id,
                    expected_scope.tenant_id, expected_scope.project_id, incarnation,
                    0, _EMPTY_SHA256, 0, None,
                ),
            )
            result = _Source(source_id, normalized_source_id, incarnation, 0, _EMPTY_SHA256, 0, None)
        else:
            binding = (
                source_path, real_path, str(opened.st_dev), str(opened.st_ino),
                expected_session_id, expected_scope.tenant_id, expected_scope.project_id,
            )
            if row[7:] != binding or row[1] != normalized_source_id or row[2] != incarnation:
                raise EventError("COLLECTOR_SOURCE_BINDING_MISMATCH")
            result = _source_row(row[:7])
        con.execute("COMMIT")
        return result
    except BaseException:
        if con.in_transaction:
            con.execute("ROLLBACK")
        raise


def _ordinal(record: dict[str, object]) -> int:
    value = record.get("ordinal")
    if type(value) is not int or not 0 <= value <= 2**63 - 1:
        raise EventError("INVALID_NATIVE_ORDINAL")
    return value


def _gap_line(start: int, end: int, native_sha256: str) -> bytes:
    return _canonical({
        "collector_gap": {
            "native_start": start, "native_end": end, "native_sha256": native_sha256,
        },
    }) + b"\n"


def _event_id(stream_id: str, producer_epoch: str, message_id: str) -> str:
    return _sha256(_canonical([stream_id, producer_epoch, message_id, "create", 1]))


def _normalize_message(
    record: dict[str, object], *, expected_scope: AccessScope,
    producer_epoch: str, first_seen_at: str,
) -> tuple[bytes, str, str, int]:
    ordinal = _ordinal(record)
    payload = record.get("payload")
    if not isinstance(payload, dict):
        raise EventError("INVALID_MESSAGE_PAYLOAD")
    role = payload.get("role")
    if role not in {"user", "assistant"}:
        raise EventError("UNSUPPORTED_NATIVE_ROLE")
    if role == "assistant" and payload.get("phase") not in _ALLOWED_ASSISTANT_PHASES:
        raise EventError("UNVERIFIED_ASSISTANT_PHASE")
    message_id = payload.get("id")
    if not isinstance(message_id, str) or not message_id or message_id != message_id.strip():
        raise EventError("INVALID_NATIVE_MESSAGE_ID")
    content = payload.get("content")
    if not isinstance(content, list) or not content:
        raise EventError("MESSAGE_CONTENT_REQUIRED")
    texts: list[str] = []
    for part in content:
        if not isinstance(part, dict) or part.get("type") not in {"input_text", "output_text"}:
            raise EventError("UNKNOWN_MESSAGE_CONTENT_PART")
        text = part.get("text")
        if not isinstance(text, str):
            raise EventError("INVALID_MESSAGE_CONTENT_PART")
        try:
            text.encode("utf-8")
        except UnicodeError:
            raise EventError("INVALID_MESSAGE_CONTENT_PART") from None
        texts.append(text)
    occurred_at = record.get("timestamp")
    if not isinstance(occurred_at, str):
        raise EventError("NATIVE_TIMESTAMP_REQUIRED")
    event_id = _event_id(expected_scope.stream_id, producer_epoch, message_id)
    normalized = _canonical({
        "schema_version": 1,
        "event_id": event_id,
        "stream_id": expected_scope.stream_id,
        "message_id": message_id,
        "producer_epoch": producer_epoch,
        "source_version": 1,
        "source_ordinal": ordinal,
        "event_type": "create",
        "occurred_at": occurred_at,
        "ingested_at": first_seen_at,
        "access_scope": {
            "tenant_id": expected_scope.tenant_id,
            "project_id": expected_scope.project_id,
        },
        "role": role,
        "content": CONTENT_PART_SEPARATOR.join(texts),
    }) + b"\n"
    event = parse_event(normalized[:-1], expected_scope=expected_scope)
    redact_event(event)
    return normalized, event_id, message_id, ordinal


def _classify(
    raw_line: bytes, *, start: int, end: int, expected_scope: AccessScope,
    producer_epoch: str, first_seen_at: str, last_ordinal: int | None,
    allow_gaps: bool,
) -> _Classification:
    native_sha256 = _sha256(raw_line + b"\n")
    ordinal: int | None = None
    try:
        record = _native_object(raw_line)
        ordinal = _ordinal(record)
        if last_ordinal is not None and ordinal <= last_ordinal:
            raise EventError("NON_MONOTONIC_NATIVE_ORDINAL")
        record_type = record.get("type")
        if record_type in _EXCLUDED_TOP_LEVEL:
            return _Classification("skipped", _EXCLUDED_TOP_LEVEL[record_type], ordinal, b"", None, None)
        if record_type != "response_item":
            raise EventError("UNKNOWN_NATIVE_RECORD_TYPE")
        payload = record.get("payload")
        if not isinstance(payload, dict):
            raise EventError("INVALID_RESPONSE_ITEM_PAYLOAD")
        payload_type = payload.get("type")
        if payload_type != "message":
            reason = "EXCLUDED_REASONING" if payload_type == "reasoning" else "EXCLUDED_NON_MESSAGE_RESPONSE"
            return _Classification("skipped", reason, ordinal, b"", None, None)
        role = payload.get("role")
        if role in _EXCLUDED_ROLES:
            return _Classification("skipped", _EXCLUDED_ROLES[role], ordinal, b"", None, None)
        normalized, event_id, message_id, ordinal = _normalize_message(
            record, expected_scope=expected_scope, producer_epoch=producer_epoch,
            first_seen_at=first_seen_at,
        )
        return _Classification("accepted", "ACCEPTED_MESSAGE", ordinal, normalized, event_id, message_id)
    except EventError as exc:
        if not allow_gaps:
            raise
        gap_ordinal = ordinal if ordinal is not None and (
            last_ordinal is None or ordinal > last_ordinal
        ) else None
        return _Classification(
            "gap", str(exc), gap_ordinal, _gap_line(start, end, native_sha256), None, None,
        )


def _plan_from_row(row: tuple) -> _Plan:
    return _Plan(*row)


def _pending_plan(ledger: Ledger, source_id: str, native_start: int) -> _Plan | None:
    row = ledger._con.execute(
        f"""SELECT source_id,native_start,native_end,native_sha256,ordinal,disposition,
                   reason_code,normalized_start,normalized_end,normalized_sha256,event_id,
                   message_id,first_seen_at,state
            FROM {_TABLE_PREFIX}plans
            WHERE source_id=? AND native_start=? AND state='planned'""",
        (source_id, native_start),
    ).fetchone()
    return None if row is None else _plan_from_row(row)


def _plan_at(ledger: Ledger, source_id: str, native_start: int) -> _Plan | None:
    row = ledger._con.execute(
        f"""SELECT source_id,native_start,native_end,native_sha256,ordinal,disposition,
                   reason_code,normalized_start,normalized_end,normalized_sha256,event_id,
                   message_id,first_seen_at,state
            FROM {_TABLE_PREFIX}plans WHERE source_id=? AND native_start=?""",
        (source_id, native_start),
    ).fetchone()
    return None if row is None else _plan_from_row(row)


def _create_plan(
    ledger: Ledger, source: _Source, *, start: int, end: int,
    native_sha256: str, classified: _Classification, first_seen_at: str,
) -> _Plan:
    normalized_start = source.next_normalized_offset
    normalized_end = normalized_start + len(classified.normalized)
    plan = _Plan(
        source.source_id, start, end, native_sha256, classified.ordinal,
        classified.disposition, classified.reason_code, normalized_start, normalized_end,
        _sha256(classified.normalized), classified.event_id, classified.message_id,
        first_seen_at, "planned",
    )
    con = ledger._con
    try:
        con.execute("BEGIN IMMEDIATE")
        cursor = con.execute(
            f"SELECT next_native_offset,next_normalized_offset FROM {_TABLE_PREFIX}sources WHERE source_id=?",
            (source.source_id,),
        ).fetchone()
        if cursor != (start, normalized_start):
            raise EventError("STALE_COLLECTOR_CURSOR")
        con.execute(
            f"INSERT INTO {_TABLE_PREFIX}plans VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                plan.source_id, plan.native_start, plan.native_end, plan.native_sha256,
                plan.ordinal, plan.disposition, plan.reason_code, plan.normalized_start,
                plan.normalized_end, plan.normalized_sha256, plan.event_id,
                plan.message_id, plan.first_seen_at, plan.state,
            ),
        )
        con.execute("COMMIT")
        return plan
    except BaseException as exc:
        if con.in_transaction:
            con.execute("ROLLBACK")
        concurrent = _plan_at(ledger, source.source_id, start)
        if concurrent is not None and (
            concurrent.native_end, concurrent.native_sha256, concurrent.normalized_start
        ) == (end, native_sha256, normalized_start):
            return concurrent
        raise exc


def _reconstruct_plan(
    plan: _Plan, raw_line: bytes, *, expected_scope: AccessScope,
    producer_epoch: str, last_ordinal: int | None,
) -> _Classification:
    classified = _classify(
        raw_line, start=plan.native_start, end=plan.native_end,
        expected_scope=expected_scope, producer_epoch=producer_epoch,
        first_seen_at=plan.first_seen_at, last_ordinal=last_ordinal, allow_gaps=True,
    )
    values = (
        classified.disposition, classified.reason_code, classified.ordinal,
        plan.normalized_start + len(classified.normalized), _sha256(classified.normalized),
        classified.event_id, classified.message_id,
    )
    expected = (
        plan.disposition, plan.reason_code, plan.ordinal, plan.normalized_end,
        plan.normalized_sha256, plan.event_id, plan.message_id,
    )
    if values != expected:
        raise EventError("PENDING_PLAN_RECONSTRUCTION_MISMATCH")
    return classified


def _deliver_plan(
    ledger: Ledger, source: _Source, plan: _Plan, classified: _Classification,
    expected_scope: AccessScope,
) -> None:
    if plan.disposition == "accepted":
        ledger.ingest(
            classified.normalized, source_id=source.normalized_source_id,
            incarnation=source.incarnation, expected_scope=expected_scope,
            start_offset=plan.normalized_start,
        )
    elif plan.disposition == "gap":
        ledger.skip_rejected_record(
            classified.normalized, source_id=source.normalized_source_id,
            incarnation=source.incarnation, expected_scope=expected_scope,
            start_offset=plan.normalized_start, expected_sha256=plan.normalized_sha256,
            acknowledge_gap=True, source_reason_code=plan.reason_code,
        )


def _finalize_plan(
    ledger: Ledger, fd: int, source: _Source, plan: _Plan,
    expected_scope: AccessScope, opened: os.stat_result,
) -> _Source:
    current = os.fstat(fd)
    if (current.st_dev, current.st_ino) != (opened.st_dev, opened.st_ino):
        raise EventError("FILE_IDENTITY_CHANGED")
    raw = _read_exact(fd, plan.native_start, plan.native_end - plan.native_start)
    if _sha256(raw) != plan.native_sha256:
        raise EventError("SOURCE_CHANGED_DURING_COLLECTION")
    new_prefix = _prefix_sha256(fd, plan.native_end)
    con = ledger._con
    try:
        con.execute("BEGIN IMMEDIATE")
        state = con.execute(
            f"SELECT state FROM {_TABLE_PREFIX}plans WHERE source_id=? AND native_start=?",
            (source.source_id, plan.native_start),
        ).fetchone()
        if state == ("finalized",):
            con.execute("COMMIT")
        else:
            if plan.disposition != "skipped":
                checkpoint = ledger.checkpoint(source.normalized_source_id)
                if checkpoint != plan.normalized_end:
                    raise EventError("NORMALIZED_RECEIPT_MISSING")
            cursor = con.execute(
                f"SELECT next_native_offset,next_normalized_offset FROM {_TABLE_PREFIX}sources WHERE source_id=?",
                (source.source_id,),
            ).fetchone()
            if cursor != (plan.native_start, plan.normalized_start):
                raise EventError("STALE_COLLECTOR_CURSOR")
            con.execute(
                f"""UPDATE {_TABLE_PREFIX}sources
                    SET next_native_offset=?,prefix_sha256=?,next_normalized_offset=?,
                        last_ordinal=COALESCE(?,last_ordinal) WHERE source_id=?""",
                (plan.native_end, new_prefix, plan.normalized_end, plan.ordinal, source.source_id),
            )
            con.execute(
                f"UPDATE {_TABLE_PREFIX}plans SET state='finalized' WHERE source_id=? AND native_start=?",
                (source.source_id, plan.native_start),
            )
            con.execute("COMMIT")
    except BaseException:
        if con.in_transaction:
            con.execute("ROLLBACK")
        raise
    return _reload_source(ledger, source.source_id)


def _result(
    ledger: Ledger, source: _Source, *, captured: int, pending_bytes: int,
) -> CollectorResult:
    counts = dict(ledger._con.execute(
        f"""SELECT disposition,count(*) FROM {_TABLE_PREFIX}plans
            WHERE source_id=? AND state='finalized' GROUP BY disposition""",
        (source.source_id,),
    ).fetchall())
    gaps = tuple(
        CoverageGap(*row) for row in ledger._con.execute(
            f"""SELECT native_start,native_end,native_sha256,reason_code
                FROM {_TABLE_PREFIX}plans
                WHERE source_id=? AND state='finalized' AND disposition='gap'
                ORDER BY native_start""", (source.source_id,),
        ).fetchall()
    )
    complete = source.next_native_offset == captured and pending_bytes == 0
    return CollectorResult(
        source.source_id, captured, source.next_native_offset, source.next_normalized_offset,
        counts.get("accepted", 0), counts.get("skipped", 0), counts.get("gap", 0),
        pending_bytes, gaps, complete, complete and not gaps,
    )


def collect_codex_rollout(
    ledger: Ledger, *, source_path: str | Path, allowed_real_paths: Iterable[str | Path],
    source_id: str, expected_session_id: str, expected_scope: AccessScope,
    captured_byte_limit: int | None = None, expected_native_offset: int | None = None,
    allow_gaps: bool = False, max_record_bytes: int = 1_048_576,
    max_batch_bytes: int = 8_388_608,
    clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
) -> CollectorResult:
    """Collect a bounded, immutable snapshot prefix from one enrolled rollout.

    ``allow_gaps`` is an explicit authorization to persist safe gap metadata and
    continue. It never turns a rejected native record into an accepted event.
    """
    if not isinstance(ledger, Ledger):
        raise EventError("LEDGER_REQUIRED")
    source_id = _safe_identity(source_id)
    expected_session_id = _safe_identity(expected_session_id)
    if not isinstance(expected_scope, AccessScope) or expected_scope.stream_id != expected_session_id:
        raise EventError("SESSION_SCOPE_MISMATCH")
    if type(allow_gaps) is not bool:
        raise EventError("INVALID_GAP_POLICY")
    for limit in (max_record_bytes, max_batch_bytes):
        if type(limit) is not int or limit <= 0:
            raise EventError("INVALID_LIMIT")
    if expected_native_offset is not None and (
        type(expected_native_offset) is not int or expected_native_offset < 0
    ):
        raise EventError("INVALID_OFFSET")
    _ensure_schema(ledger)
    fd = -1
    try:
        fd, real_path, opened = _open_enrolled(source_path, allowed_real_paths)
        supplied = os.fspath(source_path)
        _verify_session_meta(fd, expected_session_id, max_record_bytes)
        source = _load_or_create_source(
            ledger, source_id=source_id, source_path=supplied, real_path=real_path,
            opened=opened, expected_session_id=expected_session_id,
            expected_scope=expected_scope,
        )
        if expected_native_offset is not None and source.next_native_offset != expected_native_offset:
            raise EventError("STALE_COLLECTOR_CURSOR")
        if opened.st_size < source.next_native_offset:
            raise EventError("SOURCE_TRUNCATED")
        if _prefix_sha256(fd, source.next_native_offset) != source.prefix_sha256:
            raise EventError("SOURCE_PREFIX_REWRITTEN")
        if captured_byte_limit is None:
            requested = opened.st_size
        elif type(captured_byte_limit) is not int or captured_byte_limit < 0:
            raise EventError("INVALID_CAPTURE_LIMIT")
        else:
            requested = captured_byte_limit
        if requested > opened.st_size:
            raise EventError("CAPTURE_LIMIT_BEYOND_FILE")
        if requested < source.next_native_offset:
            raise EventError("CAPTURE_LIMIT_BEFORE_CHECKPOINT")
        captured = min(requested, source.next_native_offset + max_batch_bytes)
        pending_bytes = 0
        while source.next_native_offset < captured:
            latest = _reload_source(ledger, source.source_id)
            if latest.next_native_offset != source.next_native_offset:
                if _prefix_sha256(fd, latest.next_native_offset) != latest.prefix_sha256:
                    raise EventError("SOURCE_PREFIX_REWRITTEN")
                source = latest
                continue
            start = source.next_native_offset
            plan = _pending_plan(ledger, source.source_id, start)
            if plan is not None:
                if plan.native_end > captured:
                    pending_bytes = captured - start
                    break
                raw_with_newline = _read_exact(fd, start, plan.native_end - start)
                if _sha256(raw_with_newline) != plan.native_sha256:
                    raise EventError("PENDING_NATIVE_RECORD_CHANGED")
                classified = _reconstruct_plan(
                    plan, raw_with_newline[:-1], expected_scope=expected_scope,
                    producer_epoch=source.incarnation, last_ordinal=source.last_ordinal,
                )
            else:
                available = captured - start
                probe = os.pread(fd, min(available, max_record_bytes + 2), start)
                newline = probe.find(b"\n")
                if newline < 0:
                    if available > max_record_bytes:
                        raise EventError("RECORD_TOO_LARGE")
                    pending_bytes = available
                    break
                if newline > max_record_bytes:
                    raise EventError("RECORD_TOO_LARGE")
                end = start + newline + 1
                raw_with_newline = probe[:newline + 1]
                native_sha256 = _sha256(raw_with_newline)
                first_seen_at = _utc_timestamp(clock)
                classified = _classify(
                    raw_with_newline[:-1], start=start, end=end,
                    expected_scope=expected_scope, producer_epoch=source.incarnation,
                    first_seen_at=first_seen_at, last_ordinal=source.last_ordinal,
                    allow_gaps=allow_gaps,
                )
                try:
                    plan = _create_plan(
                        ledger, source, start=start, end=end, native_sha256=native_sha256,
                        classified=classified, first_seen_at=first_seen_at,
                    )
                except EventError as exc:
                    if str(exc) != "STALE_COLLECTOR_CURSOR":
                        raise
                    source = _reload_source(ledger, source.source_id)
                    continue
                if plan.first_seen_at != first_seen_at or plan.state != "planned":
                    classified = _reconstruct_plan(
                        plan, raw_with_newline[:-1], expected_scope=expected_scope,
                        producer_epoch=source.incarnation, last_ordinal=source.last_ordinal,
                    )
            _deliver_plan(ledger, source, plan, classified, expected_scope)
            source = _finalize_plan(ledger, fd, source, plan, expected_scope, opened)
        if source.next_native_offset == captured:
            pending_bytes = 0
        return _result(ledger, source, captured=captured, pending_bytes=pending_bytes)
    finally:
        if fd >= 0:
            os.close(fd)
