"""Authorized conversation-window, memory, and expiry lifecycle.

The encrypted ledger remains append-only.  This module owns only namespaced
projection state and receives the already-open ledger connection explicitly.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Callable, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta
import hashlib
import json
import math
from typing import Any, NoReturn

from .archive import ArchiveReceipt
from .conversation import CONVERSATION_MEDIA_TYPE, message_anchor_id
from .events import AccessScope, Event, EventError, parse_event
from .redaction import RedactedEvent, redact_text


class LifecycleError(EventError):
    """A safe lifecycle error code that never contains message content."""


def _error(code: str) -> NoReturn:
    raise LifecycleError(code)


def _identifier(value: object, code: str) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        _error(code)
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        _error(code)
    return value


def _canonical(value: object) -> str:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False,
    )


def _digest(value: object) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _archive_clean(value: object) -> Any:
    """Mirror archive normalization so a receipt's bundle ID can be verified."""
    if isinstance(value, str):
        return redact_text(value)[0]
    if isinstance(value, dict):
        if any(not isinstance(key, str) for key in value):
            _error("INVALID_ARCHIVE_PAYLOAD")
        return {key: _archive_clean(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_archive_clean(item) for item in value]
    if value is None or type(value) in {int, float, bool}:
        return value
    _error("INVALID_ARCHIVE_PAYLOAD")


def _time(value: str) -> datetime:
    try:
        stamp = datetime.fromisoformat(value)
    except (TypeError, ValueError):
        _error("INVALID_LIFECYCLE_TIMESTAMP")
    if stamp.tzinfo is None or stamp.utcoffset() is None:
        _error("LIFECYCLE_TIMEZONE_REQUIRED")
    return stamp


def _safe_now(clock: Callable[[], datetime]) -> datetime:
    value = clock()
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        _error("INJECTED_CLOCK_TIMEZONE_REQUIRED")
    return value


@dataclass(frozen=True)
class AuthenticatedScope:
    """Trusted caller identity plus explicitly enrolled streams."""

    owner_id: str
    tenant_id: str
    project_id: str
    enrolled_streams: tuple[str, ...]

    def __post_init__(self) -> None:
        _identifier(self.owner_id, "INVALID_OWNER_ID")
        _identifier(self.tenant_id, "INVALID_TENANT_ID")
        _identifier(self.project_id, "INVALID_PROJECT_ID")
        if isinstance(self.enrolled_streams, (str, bytes)):
            _error("EXPLICIT_UNIQUE_STREAM_ENROLLMENT_REQUIRED")
        streams = tuple(self.enrolled_streams)
        if not streams or len(streams) != len(set(streams)):
            _error("EXPLICIT_UNIQUE_STREAM_ENROLLMENT_REQUIRED")
        for stream in streams:
            _identifier(stream, "INVALID_STREAM_ID")
            AccessScope(self.tenant_id, self.project_id, stream)
        object.__setattr__(self, "enrolled_streams", streams)

    def permits(self, event: Event) -> bool:
        return (
            event.scope.tenant_id == self.tenant_id
            and event.scope.project_id == self.project_id
            and event.scope.stream_id in self.enrolled_streams
        )

    def to_dict(self) -> dict[str, object]:
        return {
            "owner_id": self.owner_id,
            "tenant_id": self.tenant_id,
            "project_id": self.project_id,
            "enrolled_streams": list(self.enrolled_streams),
        }


@dataclass(frozen=True)
class AcceptedEvent:
    """A ledger-accepted event carrying trusted redaction provenance."""

    event: Event
    audit_rules: tuple[str, ...]
    has_public_text: bool

    def __post_init__(self) -> None:
        if not isinstance(self.event, Event):
            _error("VALIDATED_EVENT_REQUIRED")
        if type(self.has_public_text) is not bool:
            _error("INVALID_PUBLIC_TEXT_PROVENANCE")
        if any(not isinstance(rule, str) or not rule for rule in self.audit_rules):
            _error("INVALID_REDACTION_AUDIT")


@dataclass(frozen=True)
class MessageState:
    message_key: str
    message_id: str
    stream_id: str
    producer_epoch: str
    role: str
    content: str
    created_at: str
    creation_ordinal: int
    current_version: int
    current_event_id: str
    version_signature: str
    visible: bool
    expired: bool
    has_public_text: bool
    tool_excluded: bool
    audit_rules: tuple[str, ...]
    reply_to: str | None
    history: tuple[dict[str, object], ...]

    @property
    def eligible(self) -> bool:
        return self.visible and not self.expired and self.has_public_text and not self.tool_excluded

    def to_dict(self) -> dict[str, object]:
        return {
            "message_key": self.message_key,
            "message_id": self.message_id,
            "stream_id": self.stream_id,
            "producer_epoch": self.producer_epoch,
            "role": self.role,
            "content": self.content,
            "created_at": self.created_at,
            "creation_ordinal": self.creation_ordinal,
            "current_version": self.current_version,
            "current_event_id": self.current_event_id,
            "version_signature": self.version_signature,
            "visible": self.visible,
            "expired": self.expired,
            "has_public_text": self.has_public_text,
            "tool_excluded": self.tool_excluded,
            "audit_rules": list(self.audit_rules),
            "reply_to": self.reply_to,
            "history": [dict(item) for item in self.history],
        }


@dataclass(frozen=True)
class ReductionResult:
    messages: tuple[MessageState, ...]

    @property
    def eligible(self) -> tuple[MessageState, ...]:
        return tuple(message for message in self.messages if message.eligible)

    @property
    def expired(self) -> tuple[MessageState, ...]:
        return tuple(message for message in self.messages if message.expired)

    def to_dict(self) -> dict[str, object]:
        return {
            "messages": [message.to_dict() for message in self.messages],
            "eligible_message_keys": [message.message_key for message in self.eligible],
            "expired_message_keys": [message.message_key for message in self.expired],
        }


def _as_accepted(item: AcceptedEvent | RedactedEvent) -> AcceptedEvent:
    if isinstance(item, AcceptedEvent):
        return item
    if isinstance(item, RedactedEvent):
        return AcceptedEvent(item.event, item.audit_rules, item.has_public_text)
    _error("ACCEPTED_REDACTED_EVENT_REQUIRED")


def reduce_events(
    events: Sequence[AcceptedEvent | RedactedEvent], *, scope: AuthenticatedScope,
    now: datetime, retention_days: int = 90,
) -> ReductionResult:
    """Deterministically reduce append-only corrections into current messages."""
    if not isinstance(scope, AuthenticatedScope):
        _error("AUTHENTICATED_SCOPE_REQUIRED")
    if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() is None:
        _error("LIFECYCLE_TIMEZONE_REQUIRED")
    if type(retention_days) is not int or retention_days <= 0:
        _error("INVALID_RETENTION_DAYS")

    accepted: list[AcceptedEvent] = []
    event_ids: dict[tuple[str, str, str], bytes] = {}
    ordinals: dict[tuple[str, str, int], bytes] = {}
    for item in events:
        record = _as_accepted(item)
        event = record.event
        if parse_event(event.canonical_json, expected_scope=event.scope) != event:
            _error("EVENT_REPRESENTATION_MISMATCH")
        if not scope.permits(event):
            _error("AUTHENTICATED_SCOPE_MISMATCH")
        event_key = (event.scope.stream_id, event.producer_epoch, event.event_id)
        previous = event_ids.get(event_key)
        if previous is not None:
            if previous != event.canonical_json:
                _error("EVENT_ID_CONFLICT")
            continue
        event_ids[event_key] = event.canonical_json
        ordinal_key = (event.scope.stream_id, event.producer_epoch, event.source_ordinal)
        if ordinal_key in ordinals:
            _error("SOURCE_ORDINAL_CONFLICT")
        ordinals[ordinal_key] = event.canonical_json
        accepted.append(record)

    grouped: dict[tuple[str, str, str], list[AcceptedEvent]] = defaultdict(list)
    for record in accepted:
        event = record.event
        grouped[(event.scope.stream_id, event.producer_epoch, event.message_id)].append(record)

    messages: list[MessageState] = []
    for records in grouped.values():
        versions: dict[int, AcceptedEvent] = {}
        for record in records:
            version = record.event.source_version
            if version in versions:
                _error("AMBIGUOUS_MESSAGE_VERSION")
            versions[version] = record
        ordered = sorted(
            records,
            key=lambda record: (
                record.event.source_version, record.event.source_ordinal, record.event.event_id,
            ),
        )
        first = ordered[0]
        if first.event.event_type != "create":
            _error("MESSAGE_CREATE_REQUIRED")
        payload = json.loads(first.event.canonical_json)
        role = first.event.role
        content = first.event.content
        if role is None or content is None:
            _error("INVALID_CREATE_EVENT")
        created_at = payload["occurred_at"]
        visible = True
        public = first.has_public_text
        audit_rules = first.audit_rules
        tool_excluded = "tool_call_id" in payload
        reply_to = payload.get("reply_to")
        history: list[dict[str, object]] = []
        for index, record in enumerate(ordered):
            event = record.event
            body = json.loads(event.canonical_json)
            history.append({
                "event_id": event.event_id,
                "event_type": event.event_type,
                "source_version": event.source_version,
                "source_ordinal": event.source_ordinal,
                "occurred_at": body["occurred_at"],
                "canonical_sha256": hashlib.sha256(event.canonical_json).hexdigest(),
            })
            if index == 0:
                continue
            if event.event_type == "create":
                _error("DUPLICATE_MESSAGE_CREATE")
            if event.event_type == "edit":
                if event.role is None or event.content is None:
                    _error("INVALID_EDIT_EVENT")
                role = event.role
                content = event.content
                public = record.has_public_text
                audit_rules = record.audit_rules
                tool_excluded = "tool_call_id" in body
                reply_to = body.get("reply_to")
            elif event.event_type == "delete":
                if not visible:
                    _error("INVALID_DELETE_TRANSITION")
                visible = False
            elif event.event_type == "restore":
                if visible:
                    _error("INVALID_RESTORE_TRANSITION")
                visible = True
            else:
                _error("UNSUPPORTED_LIFECYCLE_EVENT")
        latest = ordered[-1].event
        creation = first.event
        if role is None or content is None:
            _error("INVALID_REDUCED_MESSAGE")
        messages.append(MessageState(
            message_key=message_anchor_id(creation),
            message_id=creation.message_id,
            stream_id=creation.scope.stream_id,
            producer_epoch=creation.producer_epoch,
            role=role,
            content=content,
            created_at=created_at,
            creation_ordinal=creation.source_ordinal,
            current_version=latest.source_version,
            current_event_id=latest.event_id,
            version_signature=_digest(history),
            visible=visible,
            expired=now >= _time(created_at) + timedelta(days=retention_days),
            has_public_text=public,
            tool_excluded=tool_excluded,
            audit_rules=tuple(audit_rules),
            reply_to=reply_to,
            history=tuple(history),
        ))
    messages.sort(key=lambda item: (
        item.stream_id, item.producer_epoch, item.creation_ordinal, item.message_key,
    ))
    return ReductionResult(tuple(messages))


def load_accepted_events(connection: Any, *, scope: AuthenticatedScope) -> tuple[AcceptedEvent, ...]:
    """Load only enrolled, accepted, redacted ledger rows for the trusted scope."""
    if not isinstance(scope, AuthenticatedScope):
        _error("AUTHENTICATED_SCOPE_REQUIRED")
    try:
        rows = connection.execute(
            "SELECT redacted_json,audit_rules,has_public_text FROM events",
        ).fetchall()
    except Exception:
        _error("LEDGER_READ_FAILED")
    result: list[AcceptedEvent] = []
    for redacted_json, audit_json, has_public_text in rows:
        if not isinstance(redacted_json, (bytes, bytearray)):
            _error("INVALID_LEDGER_EVENT")
        try:
            payload = json.loads(bytes(redacted_json))
        except (UnicodeError, ValueError, TypeError):
            _error("INVALID_LEDGER_EVENT")
        supplied = payload.get("access_scope") if isinstance(payload, dict) else None
        stream_id = payload.get("stream_id") if isinstance(payload, dict) else None
        if not isinstance(supplied, dict):
            _error("INVALID_LEDGER_EVENT")
        if (
            supplied.get("tenant_id") != scope.tenant_id
            or supplied.get("project_id") != scope.project_id
            or stream_id not in scope.enrolled_streams
        ):
            continue
        event_scope = AccessScope(scope.tenant_id, scope.project_id, stream_id)
        event = parse_event(bytes(redacted_json), expected_scope=event_scope)
        try:
            rules = json.loads(audit_json)
        except (TypeError, ValueError):
            _error("INVALID_REDACTION_AUDIT")
        if not isinstance(rules, list) or any(not isinstance(rule, str) for rule in rules):
            _error("INVALID_REDACTION_AUDIT")
        if has_public_text not in (0, 1):
            _error("INVALID_PUBLIC_TEXT_PROVENANCE")
        result.append(AcceptedEvent(event, tuple(rules), bool(has_public_text)))
    return tuple(result)


_SCHEMA = (
    """CREATE TABLE IF NOT EXISTS airag_lifecycle_windows (
        window_id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, tenant_id TEXT NOT NULL,
        project_id TEXT NOT NULL, stream_id TEXT NOT NULL, producer_epoch TEXT NOT NULL,
        created_at TEXT NOT NULL, closed_at TEXT NOT NULL, close_reason TEXT NOT NULL,
        checkpoint_json TEXT NOT NULL, document_json TEXT, document_sha256 TEXT NOT NULL,
        processing_state TEXT NOT NULL, publication_state TEXT NOT NULL,
        publish_attempts INTEGER NOT NULL DEFAULT 0, published_at TEXT,
        last_error TEXT, invalidated_reason TEXT)""",
    """CREATE TABLE IF NOT EXISTS airag_lifecycle_window_members (
        window_id TEXT NOT NULL REFERENCES airag_lifecycle_windows(window_id),
        message_key TEXT NOT NULL, version_signature TEXT NOT NULL,
        PRIMARY KEY(window_id,message_key))""",
    """CREATE TABLE IF NOT EXISTS airag_lifecycle_memories (
        memory_id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, tenant_id TEXT NOT NULL,
        project_id TEXT NOT NULL, kind TEXT NOT NULL, text TEXT,
        approval_state TEXT NOT NULL, pinned INTEGER NOT NULL CHECK(pinned IN (0,1)),
        created_at TEXT NOT NULL, invalidated_reason TEXT)""",
    """CREATE TABLE IF NOT EXISTS airag_lifecycle_memory_dependencies (
        memory_id TEXT NOT NULL REFERENCES airag_lifecycle_memories(memory_id),
        message_key TEXT NOT NULL, version_signature TEXT NOT NULL,
        dependency_kind TEXT NOT NULL, PRIMARY KEY(memory_id,message_key,dependency_kind))""",
    """CREATE TABLE IF NOT EXISTS airag_lifecycle_archive_queue (
        entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
        owner_id TEXT NOT NULL, tenant_id TEXT NOT NULL, project_id TEXT NOT NULL,
        payload_json TEXT NOT NULL, payload_sha256 TEXT NOT NULL,
        state TEXT NOT NULL, created_at TEXT NOT NULL, confirmed_at TEXT,
        archive_receipt_json TEXT,
        PRIMARY KEY(entity_type,entity_id))""",
    """CREATE TABLE IF NOT EXISTS airag_lifecycle_scope_gates (
        scope_key TEXT PRIMARY KEY, owner_id TEXT NOT NULL, tenant_id TEXT NOT NULL,
        project_id TEXT NOT NULL, streams_json TEXT NOT NULL,
        checkpoint_sha256 TEXT NOT NULL, reconciled_at TEXT NOT NULL,
        expiry_valid_until TEXT)""",
)


@contextmanager
def _transaction(connection: Any):
    nested = bool(getattr(connection, "in_transaction", False))
    try:
        if nested:
            connection.execute("SAVEPOINT airag_lifecycle_tx")
        else:
            connection.execute("BEGIN IMMEDIATE")
        yield
        if nested:
            connection.execute("RELEASE SAVEPOINT airag_lifecycle_tx")
        else:
            connection.execute("COMMIT")
    except BaseException:
        try:
            if nested:
                connection.execute("ROLLBACK TO SAVEPOINT airag_lifecycle_tx")
                connection.execute("RELEASE SAVEPOINT airag_lifecycle_tx")
            elif getattr(connection, "in_transaction", False):
                connection.execute("ROLLBACK")
        except Exception:
            pass
        raise


def initialize_lifecycle(connection: Any) -> None:
    """Initialize only lifecycle-owned tables on an already-open connection."""
    try:
        with _transaction(connection):
            for statement in _SCHEMA:
                connection.execute(statement)
    except LifecycleError:
        raise
    except Exception:
        _error("LIFECYCLE_SCHEMA_FAILED")


class Lifecycle:
    """Durable projection runtime with injected clock and tokenizer."""

    def __init__(
        self, connection: Any, *, clock: Callable[[], datetime],
        tokenizer: Callable[[str], int] | None = None,
        token_mode: str = "estimated", event_limit: int = 40,
        token_limit: int = 2000, open_tail_seconds: int = 300,
        retention_days: int = 90, active_window_count: int = 4,
        initialize: bool = True,
    ) -> None:
        if not callable(clock):
            _error("INJECTED_CLOCK_REQUIRED")
        if token_mode not in {"estimated", "exact"}:
            _error("INVALID_TOKEN_MODE")
        if token_mode == "exact" and not callable(tokenizer):
            _error("EXACT_TOKENIZER_REQUIRED")
        for value, code in (
            (event_limit, "INVALID_EVENT_LIMIT"),
            (token_limit, "INVALID_TOKEN_LIMIT"),
            (open_tail_seconds, "INVALID_OPEN_TAIL_SECONDS"),
            (retention_days, "INVALID_RETENTION_DAYS"),
            (active_window_count, "INVALID_ACTIVE_WINDOW_COUNT"),
        ):
            if type(value) is not int or value <= 0:
                _error(code)
        self._con = connection
        self._clock = clock
        self._tokenizer = tokenizer
        self._token_mode = token_mode
        self._event_limit = event_limit
        self._token_limit = token_limit
        self._open_tail_seconds = open_tail_seconds
        self._retention_days = retention_days
        self._active_window_count = active_window_count
        if initialize:
            initialize_lifecycle(connection)

    def _now(self) -> datetime:
        return _safe_now(self._clock)

    def _tokens(self, text: str) -> int:
        if self._token_mode == "exact":
            value = self._tokenizer(text)  # type: ignore[misc]
        else:
            value = max(1, math.ceil(len(text.encode("utf-8")) / 4))
        if type(value) is not int or value < 0:
            _error("INVALID_TOKENIZER_RESULT")
        return value

    def _checkpoint(self, scope: AuthenticatedScope) -> list[dict[str, object]]:
        placeholders = ",".join("?" for _ in scope.enrolled_streams)
        try:
            rows = self._con.execute(
                f"""SELECT source_id,incarnation,stream_id,next_offset,chain_digest
                    FROM sources WHERE tenant_id=? AND project_id=?
                    AND stream_id IN ({placeholders}) ORDER BY source_id""",
                (scope.tenant_id, scope.project_id, *scope.enrolled_streams),
            ).fetchall()
        except Exception:
            _error("LEDGER_CHECKPOINT_READ_FAILED")
        return [
            {
                "source_id": row[0], "incarnation": row[1], "stream_id": row[2],
                "next_offset": row[3], "chain_digest": row[4],
            }
            for row in rows
        ]

    def _load(self, scope: AuthenticatedScope, now: datetime) -> ReductionResult:
        return reduce_events(
            load_accepted_events(self._con, scope=scope), scope=scope, now=now,
            retention_days=self._retention_days,
        )

    def _scope_key(self, scope: AuthenticatedScope) -> str:
        return _digest(scope.to_dict())

    def _write_read_gate(
        self, scope: AuthenticatedScope, reduction: ReductionResult,
        checkpoint: list[dict[str, object]], now: datetime,
    ) -> None:
        future_expiries = [
            _time(message.created_at) + timedelta(days=self._retention_days)
            for message in reduction.messages if not message.expired
        ]
        valid_until = min(future_expiries).isoformat() if future_expiries else None
        self._con.execute(
            """INSERT INTO airag_lifecycle_scope_gates VALUES (?,?,?,?,?,?,?,?)
               ON CONFLICT(scope_key) DO UPDATE SET
                 owner_id=excluded.owner_id,tenant_id=excluded.tenant_id,
                 project_id=excluded.project_id,streams_json=excluded.streams_json,
                 checkpoint_sha256=excluded.checkpoint_sha256,
                 reconciled_at=excluded.reconciled_at,
                 expiry_valid_until=excluded.expiry_valid_until""",
            (
                self._scope_key(scope), scope.owner_id, scope.tenant_id, scope.project_id,
                _canonical(list(scope.enrolled_streams)), _digest(checkpoint),
                now.isoformat(), valid_until,
            ),
        )

    def _read_gate(self, scope: AuthenticatedScope) -> dict[str, object]:
        now = self._now()
        checkpoint = self._checkpoint(scope)
        row = self._con.execute(
            """SELECT checkpoint_sha256,reconciled_at,expiry_valid_until
               FROM airag_lifecycle_scope_gates WHERE scope_key=? AND owner_id=?
               AND tenant_id=? AND project_id=? AND streams_json=?""",
            (
                self._scope_key(scope), scope.owner_id, scope.tenant_id, scope.project_id,
                _canonical(list(scope.enrolled_streams)),
            ),
        ).fetchone()
        reason = None
        if row is None:
            reason = "current_time_expiry_pass_required"
        elif row[0] != _digest(checkpoint):
            reason = "ledger_checkpoint_changed"
        elif row[2] is not None and now >= _time(row[2]):
            reason = "retention_boundary_reached"
        return {
            "open": reason is None,
            "closed_reason": reason,
            "reconciled_at": None if row is None else row[1],
            "expiry_valid_until": None if row is None else row[2],
        }

    def _require_read_gate(self, scope: AuthenticatedScope) -> None:
        if not self._read_gate(scope)["open"]:
            _error("CURRENT_TIME_EXPIRY_PASS_REQUIRED")

    def _queue_archive(
        self, scope: AuthenticatedScope, entity_type: str, entity_id: str,
        record: dict[str, object], now: datetime,
    ) -> None:
        payload_json = _canonical(record)
        digest = hashlib.sha256(payload_json.encode("utf-8")).hexdigest()
        row = self._con.execute(
            """SELECT payload_sha256 FROM airag_lifecycle_archive_queue
               WHERE entity_type=? AND entity_id=?""", (entity_type, entity_id),
        ).fetchone()
        if row is not None:
            if row[0] != digest:
                _error("ARCHIVE_CANDIDATE_CONFLICT")
            return
        self._con.execute(
            """INSERT INTO airag_lifecycle_archive_queue
               VALUES (?,?,?,?,?,?,?,?,?,NULL,NULL)""",
            (
                entity_type, entity_id, scope.owner_id, scope.tenant_id, scope.project_id,
                payload_json, digest, "pending", now.isoformat(),
            ),
        )

    def _queue_expired_messages(
        self, scope: AuthenticatedScope, reduction: ReductionResult, now: datetime,
    ) -> None:
        for message in reduction.expired:
            entity_id = "event:" + _digest({
                "owner_id": scope.owner_id,
                "message_key": message.message_key,
                "version_signature": message.version_signature,
            })
            self._queue_archive(
                scope, "message", entity_id,
                {
                    "kind": "event",
                    "id": entity_id,
                    "scope": [scope.tenant_id, scope.project_id, message.stream_id],
                    "payload": {
                        "archive_reason": "retention_expired",
                        "lookup_mode": "explicit_archive_only",
                        "owner_id": scope.owner_id,
                        "message": message.to_dict(),
                    },
                }, now,
            )

    def _invalidate_windows(
        self, scope: AuthenticatedScope, reduction: ReductionResult,
    ) -> set[tuple[str, str]]:
        current = {message.message_key: message for message in reduction.messages}
        rows = self._con.execute(
            """SELECT w.window_id,w.stream_id,w.producer_epoch,m.message_key,m.version_signature
               FROM airag_lifecycle_windows w
               JOIN airag_lifecycle_window_members m ON m.window_id=w.window_id
               WHERE w.owner_id=? AND w.tenant_id=? AND w.project_id=?
               AND w.publication_state!='invalidated'""",
            (scope.owner_id, scope.tenant_id, scope.project_id),
        ).fetchall()
        by_window: dict[tuple[str, str, str], list[tuple[str, str]]] = defaultdict(list)
        for window_id, stream_id, epoch, key, signature in rows:
            by_window[(window_id, stream_id, epoch)].append((key, signature))
        force: set[tuple[str, str]] = set()
        for (window_id, stream_id, epoch), members in by_window.items():
            reason = None
            for key, signature in members:
                message = current.get(key)
                if message is None:
                    reason = "source_missing"
                    break
                if message.expired:
                    reason = "source_expired"
                    break
                if not message.visible or not message.has_public_text or message.tool_excluded:
                    reason = "source_ineligible"
                    break
                if message.version_signature != signature:
                    reason = "source_changed"
                    break
            if reason is not None:
                self._con.execute(
                    """UPDATE airag_lifecycle_windows
                       SET processing_state='complete',publication_state='invalidated',
                           invalidated_reason=? WHERE window_id=?""",
                    (reason, window_id),
                )
                force.add((stream_id, epoch))
        return force

    def _invalidate_memories(
        self, scope: AuthenticatedScope, reduction: ReductionResult, now: datetime,
    ) -> None:
        current = {message.message_key: message for message in reduction.messages}
        rows = self._con.execute(
            """SELECT m.memory_id,d.message_key,d.version_signature
               FROM airag_lifecycle_memories m
               JOIN airag_lifecycle_memory_dependencies d ON d.memory_id=m.memory_id
               WHERE m.owner_id=? AND m.tenant_id=? AND m.project_id=?
               AND m.invalidated_reason IS NULL""",
            (scope.owner_id, scope.tenant_id, scope.project_id),
        ).fetchall()
        grouped: dict[str, list[tuple[str, str]]] = defaultdict(list)
        for memory_id, key, signature in rows:
            grouped[memory_id].append((key, signature))
        for memory_id, dependencies in grouped.items():
            reason = None
            for key, signature in dependencies:
                message = current.get(key)
                if message is None:
                    reason = "source_missing"
                    break
                if message.expired:
                    reason = "source_expired"
                    break
                if not message.eligible:
                    reason = "source_ineligible"
                    break
                if message.version_signature != signature:
                    reason = "source_changed"
                    break
            if reason is None:
                continue
            self._con.execute(
                "UPDATE airag_lifecycle_memories SET invalidated_reason=? WHERE memory_id=?",
                (reason, memory_id),
            )
            if reason == "source_expired":
                row = self._con.execute(
                    """SELECT kind,text,approval_state,pinned,created_at
                       FROM airag_lifecycle_memories WHERE memory_id=?""", (memory_id,),
                ).fetchone()
                streams = sorted({
                    current[key].stream_id for key, _ in dependencies if key in current
                })
                for stream_id in streams:
                    candidate_id = f"{memory_id}:{_digest(stream_id)[:16]}"
                    self._queue_archive(scope, "memory", candidate_id, {
                        "kind": "memory",
                        "id": memory_id,
                        "scope": [scope.tenant_id, scope.project_id, stream_id],
                        "payload": {
                            "archive_reason": "source_retention_expired",
                            "lookup_mode": "explicit_archive_only",
                            "owner_id": scope.owner_id,
                            "memory_kind": row[0], "text": row[1],
                            "approval_state": row[2], "pinned": bool(row[3]),
                            "created_at": row[4], "invalidated_reason": reason,
                            "anchors": [key for key, _ in dependencies],
                        },
                    }, now)

    def _valid_member_keys(self, scope: AuthenticatedScope) -> set[str]:
        rows = self._con.execute(
            """SELECT m.message_key FROM airag_lifecycle_window_members m
               JOIN airag_lifecycle_windows w ON w.window_id=m.window_id
               WHERE w.owner_id=? AND w.tenant_id=? AND w.project_id=?
               AND w.publication_state!='invalidated'""",
            (scope.owner_id, scope.tenant_id, scope.project_id),
        ).fetchall()
        return {row[0] for row in rows}

    def _store_window(
        self, scope: AuthenticatedScope, messages: Sequence[MessageState],
        checkpoint: list[dict[str, object]], close_reason: str, now: datetime,
    ) -> str:
        basis = {
            "owner_id": scope.owner_id, "tenant_id": scope.tenant_id,
            "project_id": scope.project_id, "stream_id": messages[0].stream_id,
            "producer_epoch": messages[0].producer_epoch,
            "members": [[item.message_key, item.version_signature] for item in messages],
        }
        window_id = "win:" + _digest(basis)
        document = {
            "schema_version": 1,
            "window_id": window_id,
            "media_type": CONVERSATION_MEDIA_TYPE,
            "name": window_id,
            "content": {
                "turns": [
                    {"id": item.message_key, "role": item.role, "text": item.content}
                    for item in messages
                ],
            },
            "provenance": {
                "scope": scope.to_dict(),
                "stream_id": messages[0].stream_id,
                "producer_epoch": messages[0].producer_epoch,
                "messages": [item.to_dict() for item in messages],
                "ledger_checkpoint": checkpoint,
            },
            "closed_at": now.isoformat(),
            "close_reason": close_reason,
        }
        encoded = _canonical(document)
        doc_hash = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
        self._con.execute(
            """INSERT OR IGNORE INTO airag_lifecycle_windows
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,NULL,NULL,NULL)""",
            (
                window_id, scope.owner_id, scope.tenant_id, scope.project_id,
                messages[0].stream_id, messages[0].producer_epoch,
                messages[0].created_at, now.isoformat(), close_reason,
                _canonical(checkpoint), encoded, doc_hash, "ready", "index_pending",
            ),
        )
        row = self._con.execute(
            "SELECT document_sha256 FROM airag_lifecycle_windows WHERE window_id=?",
            (window_id,),
        ).fetchone()
        if row is None:
            _error("WINDOW_STORE_FAILED")
        if row[0] != doc_hash:
            # A concurrent/retried close with the same immutable membership wins.
            return window_id
        for item in messages:
            self._con.execute(
                """INSERT OR IGNORE INTO airag_lifecycle_window_members
                   VALUES (?,?,?)""", (window_id, item.message_key, item.version_signature),
            )
        return window_id

    def _build_windows(
        self, scope: AuthenticatedScope, reduction: ReductionResult,
        checkpoint: list[dict[str, object]], force: set[tuple[str, str]],
        task_completed: bool, explicit_save: bool, now: datetime,
    ) -> list[str]:
        indexed = self._valid_member_keys(scope)
        grouped: dict[tuple[str, str], list[MessageState]] = defaultdict(list)
        for message in reduction.eligible:
            if message.message_key not in indexed:
                grouped[(message.stream_id, message.producer_epoch)].append(message)
        created: list[str] = []
        for group_key in sorted(grouped):
            messages = sorted(grouped[group_key], key=lambda item: (
                item.creation_ordinal, item.message_key,
            ))
            tail: list[MessageState] = []
            tail_tokens = 0
            for message in messages:
                count = self._tokens(message.content)
                if tail and (
                    len(tail) >= self._event_limit or tail_tokens + count > self._token_limit
                ):
                    created.append(self._store_window(
                        scope, tail, checkpoint, "limit", now,
                    ))
                    tail, tail_tokens = [], 0
                tail.append(message)
                tail_tokens += count
                if len(tail) >= self._event_limit or tail_tokens >= self._token_limit:
                    created.append(self._store_window(
                        scope, tail, checkpoint, "limit", now,
                    ))
                    tail, tail_tokens = [], 0
            if not tail:
                continue
            if task_completed:
                reason = "task_completion"
            elif explicit_save:
                reason = "explicit_save"
            elif group_key in force:
                reason = "correction"
            else:
                oldest = min(_time(item.created_at) for item in tail)
                reason = "open_tail_age" if now >= oldest + timedelta(
                    seconds=self._open_tail_seconds,
                ) else None
            if reason is not None:
                created.append(self._store_window(scope, tail, checkpoint, reason, now))
        return created

    def refresh(
        self, scope: AuthenticatedScope, *, task_completed: bool = False,
        explicit_save: bool = False,
    ) -> dict[str, object]:
        """Reconcile ledger state, close eligible windows, and return serializable state."""
        if not isinstance(scope, AuthenticatedScope):
            _error("AUTHENTICATED_SCOPE_REQUIRED")
        if type(task_completed) is not bool or type(explicit_save) is not bool:
            _error("INVALID_CLOSE_TRIGGER")
        now = self._now()
        reduction = self._load(scope, now)
        checkpoint = self._checkpoint(scope)
        try:
            with _transaction(self._con):
                self._queue_expired_messages(scope, reduction, now)
                force = self._invalidate_windows(scope, reduction)
                self._invalidate_memories(scope, reduction, now)
                created = self._build_windows(
                    scope, reduction, checkpoint, force, task_completed, explicit_save, now,
                )
                self._write_read_gate(scope, reduction, checkpoint, now)
        except LifecycleError:
            raise
        except Exception:
            _error("LIFECYCLE_RECONCILE_FAILED")
        state = self.state(scope)
        state["created_window_ids"] = created
        state["reduction"] = reduction.to_dict()
        state["ledger_checkpoint"] = checkpoint
        return state

    def _scope_window(self, scope: AuthenticatedScope, window_id: str) -> tuple[Any, ...]:
        row = self._con.execute(
            """SELECT document_json,document_sha256,processing_state,publication_state,
                      publish_attempts,invalidated_reason
               FROM airag_lifecycle_windows
               WHERE window_id=? AND owner_id=? AND tenant_id=? AND project_id=?""",
            (window_id, scope.owner_id, scope.tenant_id, scope.project_id),
        ).fetchone()
        if row is None:
            _error("WINDOW_NOT_FOUND_OR_SCOPE_DENIED")
        return row

    def claim_publication(self, scope: AuthenticatedScope, window_id: str) -> dict[str, object]:
        """Claim an idempotent publication; processing claims are retryable after crashes."""
        _identifier(window_id, "INVALID_WINDOW_ID")
        self._require_read_gate(scope)
        now = self._now()
        with _transaction(self._con):
            row = self._scope_window(scope, window_id)
            if row[3] == "invalidated":
                _error("WINDOW_INVALIDATED")
            if row[3] == "searchable":
                return {
                    "window_id": window_id, "idempotency_key": window_id,
                    "publication_state": "searchable", "already_published": True,
                    "document": None,
                }
            if row[0] is None:
                _error("WINDOW_DOCUMENT_EVICTED")
            self._con.execute(
                """UPDATE airag_lifecycle_windows
                   SET processing_state='processing',publication_state='index_pending',
                       publish_attempts=publish_attempts+1,last_error=NULL
                   WHERE window_id=?""", (window_id,),
            )
            attempts = row[4] + 1
        return {
            "window_id": window_id, "idempotency_key": window_id,
            "publication_state": "index_pending", "already_published": False,
            "attempt": attempts, "claimed_at": now.isoformat(),
            "document_sha256": row[1], "document": json.loads(row[0]),
        }

    def finish_publication(
        self, scope: AuthenticatedScope, window_id: str, *, success: bool,
        error_code: str | None = None,
    ) -> dict[str, object]:
        if type(success) is not bool:
            _error("INVALID_PUBLICATION_RESULT")
        if error_code is not None:
            _identifier(error_code, "INVALID_PUBLICATION_ERROR_CODE")
        self._require_read_gate(scope)
        now = self._now()
        with _transaction(self._con):
            row = self._scope_window(scope, window_id)
            if row[3] == "invalidated":
                _error("WINDOW_INVALIDATED")
            if success:
                self._con.execute(
                    """UPDATE airag_lifecycle_windows SET processing_state='complete',
                       publication_state='searchable',published_at=?,last_error=NULL
                       WHERE window_id=?""", (now.isoformat(), window_id),
                )
                state = "searchable"
            else:
                if error_code is None:
                    _error("PUBLICATION_ERROR_CODE_REQUIRED")
                self._con.execute(
                    """UPDATE airag_lifecycle_windows SET processing_state='ready',
                       publication_state='failed',last_error=? WHERE window_id=?""",
                    (error_code, window_id),
                )
                state = "failed"
        return {"window_id": window_id, "publication_state": state}

    def create_memory(
        self, scope: AuthenticatedScope, *, kind: str, text: str,
        anchor_ids: Sequence[str], proof_anchor_ids: Sequence[str] = (),
        explicit_confirmation: bool = False, conflict: bool = False,
        pinned: bool = False,
    ) -> dict[str, object]:
        """Create a rule-checked or explicitly confirmed memory with live anchors."""
        automatic = {"decision", "progress", "verified_solution"}
        confirmed = {"preference", "instruction"}
        if kind not in automatic | confirmed:
            _error("UNSUPPORTED_MEMORY_KIND")
        self._require_read_gate(scope)
        if type(explicit_confirmation) is not bool or type(conflict) is not bool or type(pinned) is not bool:
            _error("INVALID_MEMORY_FLAGS")
        if conflict:
            _error("UNRESOLVED_MEMORY_CONFLICT")
        if kind in automatic and explicit_confirmation:
            _error("AUTOMATIC_MEMORY_CANNOT_CLAIM_HUMAN_VALIDATION")
        if kind in confirmed and not explicit_confirmation:
            _error("EXPLICIT_MEMORY_CONFIRMATION_REQUIRED")
        if not isinstance(text, str):
            _error("INVALID_MEMORY_TEXT")
        clean, _ = redact_text(text)
        if not clean.strip():
            _error("INVALID_MEMORY_TEXT")
        anchors = tuple(dict.fromkeys(anchor_ids))
        proof = tuple(dict.fromkeys(proof_anchor_ids))
        if not anchors or any(not isinstance(item, str) for item in anchors + proof):
            _error("CURRENT_MEMORY_ANCHORS_REQUIRED")
        if kind == "verified_solution" and not proof:
            _error("VERIFIED_SOLUTION_PROOF_REQUIRED")
        if kind != "verified_solution" and proof:
            _error("UNEXPECTED_SOLUTION_PROOF")
        now = self._now()
        reduction = self._load(scope, now)
        current = {message.message_key: message for message in reduction.eligible}
        for anchor in anchors + proof:
            if anchor not in current:
                _error("MEMORY_ANCHOR_NOT_CURRENT_OR_AUTHORIZED")
        dependencies = {
            key: current[key].version_signature for key in tuple(dict.fromkeys(anchors + proof))
        }
        approval = "rule_checked" if kind in automatic else "human_validated"
        memory_id = "mem:" + _digest({
            "scope": scope.to_dict(), "kind": kind, "text": clean,
            "anchors": [[key, dependencies[key]] for key in anchors],
            "proof": [[key, dependencies[key]] for key in proof],
        })
        with _transaction(self._con):
            self._con.execute(
                """INSERT OR IGNORE INTO airag_lifecycle_memories
                   VALUES (?,?,?,?,?,?,?,?,?,NULL)""",
                (
                    memory_id, scope.owner_id, scope.tenant_id, scope.project_id,
                    kind, clean, approval, int(pinned), now.isoformat(),
                ),
            )
            for key in anchors:
                self._con.execute(
                    """INSERT OR IGNORE INTO airag_lifecycle_memory_dependencies
                       VALUES (?,?,?,'anchor')""", (memory_id, key, dependencies[key]),
                )
            for key in proof:
                self._con.execute(
                    """INSERT OR IGNORE INTO airag_lifecycle_memory_dependencies
                       VALUES (?,?,?,'proof')""", (memory_id, key, dependencies[key]),
                )
        return {
            "memory_id": memory_id, "kind": kind, "text": clean,
            "approval_state": approval, "pinned": pinned,
            "anchors": list(anchors), "proof_anchors": list(proof),
            "created_at": now.isoformat(),
        }

    def reopen_solution(self, scope: AuthenticatedScope, memory_id: str) -> dict[str, object]:
        """Fail closed when a previously verified solution is reopened."""
        with _transaction(self._con):
            row = self._con.execute(
                """SELECT kind,invalidated_reason FROM airag_lifecycle_memories
                   WHERE memory_id=? AND owner_id=? AND tenant_id=? AND project_id=?""",
                (memory_id, scope.owner_id, scope.tenant_id, scope.project_id),
            ).fetchone()
            if row is None:
                _error("MEMORY_NOT_FOUND_OR_SCOPE_DENIED")
            if row[0] != "verified_solution":
                _error("ONLY_VERIFIED_SOLUTION_CAN_REOPEN")
            if row[1] is None:
                self._con.execute(
                    "UPDATE airag_lifecycle_memories SET invalidated_reason='solution_reopened' WHERE memory_id=?",
                    (memory_id,),
                )
        return {"memory_id": memory_id, "invalidated_reason": row[1] or "solution_reopened"}

    def archive_candidates(self, scope: AuthenticatedScope) -> list[dict[str, object]]:
        if not isinstance(scope, AuthenticatedScope):
            _error("AUTHENTICATED_SCOPE_REQUIRED")
        rows = self._con.execute(
            """SELECT entity_type,entity_id,payload_json,payload_sha256,created_at
               FROM airag_lifecycle_archive_queue
               WHERE owner_id=? AND tenant_id=? AND project_id=? AND state='pending'
               ORDER BY created_at,entity_type,entity_id""",
            (scope.owner_id, scope.tenant_id, scope.project_id),
        ).fetchall()
        return [
            {
                "entity_type": row[0], "candidate_id": row[1],
                "record": json.loads(row[2]), "record_sha256": row[3],
                "archive_scope": json.loads(row[2])["scope"],
                "lookup_mode": "explicit_archive_only", "created_at": row[4],
            }
            for row in rows
        ]

    def confirm_archive(
        self, scope: AuthenticatedScope, *, candidate_ids: Sequence[str],
        receipt: ArchiveReceipt,
    ) -> dict[str, object]:
        """Verify an archive receipt for an exact candidate batch, then evict."""
        if not isinstance(scope, AuthenticatedScope):
            _error("AUTHENTICATED_SCOPE_REQUIRED")
        if isinstance(candidate_ids, (str, bytes)):
            _error("UNIQUE_ARCHIVE_CANDIDATES_REQUIRED")
        raw_candidates = tuple(candidate_ids)
        candidates = tuple(dict.fromkeys(raw_candidates))
        if not candidates or len(candidates) != len(raw_candidates):
            _error("UNIQUE_ARCHIVE_CANDIDATES_REQUIRED")
        if not isinstance(receipt, ArchiveReceipt):
            _error("ARCHIVE_RECEIPT_REQUIRED")
        hex_digits = set("0123456789abcdef")
        if (
            not isinstance(receipt.path, str) or not receipt.path
            or type(receipt.records) is not int or receipt.records <= 0
            or len(receipt.bundle_id) != 64 or len(receipt.ciphertext_sha256) != 64
            or set(receipt.bundle_id) - hex_digits
            or set(receipt.ciphertext_sha256) - hex_digits
        ):
            _error("INVALID_ARCHIVE_RECEIPT")
        now = self._now()
        with _transaction(self._con):
            queued: list[tuple[str, str, dict[str, Any], str]] = []
            for candidate_id in candidates:
                row = self._con.execute(
                    """SELECT entity_type,payload_json,state FROM airag_lifecycle_archive_queue
                       WHERE entity_id=? AND owner_id=? AND tenant_id=? AND project_id=?""",
                    (
                        candidate_id, scope.owner_id, scope.tenant_id, scope.project_id,
                    ),
                ).fetchone()
                if row is None:
                    _error("ARCHIVE_CANDIDATE_NOT_FOUND_OR_SCOPE_DENIED")
                queued.append((candidate_id, row[0], json.loads(row[1]), row[2]))
            archive_scopes = {_canonical(item[2].get("scope")) for item in queued}
            if len(archive_scopes) != 1:
                _error("ONE_ARCHIVE_SCOPE_PER_RECEIPT_REQUIRED")
            archive_scope = queued[0][2].get("scope")
            if (
                not isinstance(archive_scope, list) or len(archive_scope) != 3
                or archive_scope[0] != scope.tenant_id
                or archive_scope[1] != scope.project_id
                or archive_scope[2] not in scope.enrolled_streams
            ):
                _error("ARCHIVE_RECORD_SCOPE_MISMATCH")
            records = sorted(
                (_archive_clean(item[2]) for item in queued),
                key=lambda record: record["id"],
            )
            expected_bundle = _digest({"scope": archive_scope, "records": records})
            if receipt.bundle_id != expected_bundle or receipt.records != len(records):
                _error("ARCHIVE_RECEIPT_CONTENT_MISMATCH")
            receipt_json = _canonical({
                "bundle_id": receipt.bundle_id, "path": receipt.path,
                "records": receipt.records,
                "ciphertext_sha256": receipt.ciphertext_sha256,
            })
            for candidate_id, entity_type, record, _ in queued:
                self._con.execute(
                    """UPDATE airag_lifecycle_archive_queue SET state='confirmed',
                       confirmed_at=?,archive_receipt_json=? WHERE entity_id=?""",
                    (now.isoformat(), receipt_json, candidate_id),
                )
                if entity_type == "message":
                    key = record["payload"]["message"]["message_key"]
                    self._con.execute(
                        """DELETE FROM airag_lifecycle_window_members WHERE message_key=?
                           AND window_id IN (SELECT window_id FROM airag_lifecycle_windows
                           WHERE publication_state='invalidated')""", (key,),
                    )
                    self._con.execute(
                        """DELETE FROM airag_lifecycle_memory_dependencies WHERE message_key=?
                           AND memory_id IN (SELECT memory_id FROM airag_lifecycle_memories
                           WHERE invalidated_reason IS NOT NULL)""", (key,),
                    )
                elif entity_type == "memory":
                    memory_id = record["id"]
                    pending = self._con.execute(
                        """SELECT count(*) FROM airag_lifecycle_archive_queue
                           WHERE entity_type='memory' AND entity_id LIKE ? AND state!='confirmed'""",
                        (memory_id + ":%",),
                    ).fetchone()[0]
                    if pending == 0:
                        self._con.execute(
                            "DELETE FROM airag_lifecycle_memory_dependencies WHERE memory_id=?",
                            (memory_id,),
                        )
                        self._con.execute(
                            "UPDATE airag_lifecycle_memories SET text=NULL WHERE memory_id=?",
                            (memory_id,),
                        )
                else:
                    _error("UNSUPPORTED_ARCHIVE_ENTITY")
            self._con.execute(
                """UPDATE airag_lifecycle_windows SET document_json=NULL
                   WHERE publication_state='invalidated' AND NOT EXISTS
                   (SELECT 1 FROM airag_lifecycle_window_members m
                    WHERE m.window_id=airag_lifecycle_windows.window_id)""",
            )
        return {
            "candidate_ids": list(candidates), "confirmed": True,
            "bundle_id": receipt.bundle_id, "records": receipt.records,
        }

    def state(self, scope: AuthenticatedScope) -> dict[str, object]:
        if not isinstance(scope, AuthenticatedScope):
            _error("AUTHENTICATED_SCOPE_REQUIRED")
        gate = self._read_gate(scope)
        windows = self._con.execute(
            """SELECT window_id,stream_id,producer_epoch,close_reason,processing_state,
                      publication_state,publish_attempts,document_sha256,invalidated_reason,
                      closed_at
               FROM airag_lifecycle_windows
               WHERE owner_id=? AND tenant_id=? AND project_id=?
               ORDER BY rowid""",
            (scope.owner_id, scope.tenant_id, scope.project_id),
        ).fetchall()
        window_items = [
            {
                "window_id": row[0], "stream_id": row[1], "producer_epoch": row[2],
                "close_reason": row[3], "processing_state": row[4],
                "publication_state": row[5], "publish_attempts": row[6],
                "document_sha256": row[7], "invalidated_reason": row[8],
                "closed_at": row[9],
            }
            for row in windows
        ]
        searchable = [
            item["window_id"] for item in window_items
            if item["publication_state"] == "searchable"
        ]
        pending = [
            item["window_id"] for item in window_items
            if item["publication_state"] in {"index_pending", "failed"}
        ]
        memories = self._con.execute(
            """SELECT memory_id,kind,text,approval_state,pinned,created_at,invalidated_reason
               FROM airag_lifecycle_memories
               WHERE owner_id=? AND tenant_id=? AND project_id=?
               ORDER BY created_at,memory_id""",
            (scope.owner_id, scope.tenant_id, scope.project_id),
        ).fetchall()
        memory_items = [
            {
                "memory_id": row[0], "kind": row[1], "text": row[2],
                "approval_state": row[3], "pinned": bool(row[4]),
                "created_at": row[5], "invalidated_reason": row[6],
                "visible": row[6] is None,
            }
            for row in memories
        ]
        if gate["open"]:
            visible_searchable = searchable
            visible_pending = pending
            visible_memories = [
                item["memory_id"] for item in memory_items if item["visible"]
            ]
        else:
            # Restored/stale caches remain introspectable but cannot feed retrieval.
            visible_searchable = []
            visible_pending = []
            visible_memories = []
            for item in memory_items:
                item["text"] = None
                item["visible"] = False
        active = visible_searchable[-self._active_window_count:]
        older = visible_searchable[:-self._active_window_count]
        archive = self.archive_candidates(scope)
        return {
            "scope": scope.to_dict(),
            "read_gate": gate,
            "windows": window_items,
            "searchable_window_ids": visible_searchable,
            "active_window_ids": active,
            "older_searchable_window_ids": older,
            "pending_publication_ids": visible_pending,
            "memories": memory_items,
            "visible_memory_ids": visible_memories,
            "archive_candidates": archive,
            "archive_only_expiry_candidates": [
                {**item, "lookup_mode": "explicit_archive_only"} for item in archive
            ],
        }
