"""Validate normalized events without storing them or acknowledging delivery."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import hashlib
import json


class EventError(ValueError):
    """A safe error code that does not echo source content."""


def _text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise EventError(f"INVALID_{field.upper()}")
    try:
        value.encode("utf-8")
    except UnicodeError:
        raise EventError(f"INVALID_{field.upper()}") from None
    return value


def _identifier(value: object, field: str) -> str:
    value = _text(value, field)
    if value != value.strip() or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise EventError(f"INVALID_{field.upper()}")
    return value


@dataclass(frozen=True)
class AccessScope:
    tenant_id: str
    project_id: str
    stream_id: str

    def __post_init__(self) -> None:
        for name in ("tenant_id", "project_id", "stream_id"):
            value = _identifier(getattr(self, name), name)
            if value.startswith("pending_"):
                raise EventError("UNRESOLVED_SCOPE")


@dataclass(frozen=True)
class Event:
    event_id: str
    message_id: str
    producer_epoch: str
    source_version: int
    source_ordinal: int
    event_type: str
    scope: AccessScope
    role: str | None
    content: str | None
    canonical_json: bytes

    def replay_fingerprint(self, *, redaction_version: str) -> str:
        """Fingerprint input identity; this is not an authorization or dedup ledger."""
        policy = _text(redaction_version, "redaction_version")
        payload = json.loads(self.canonical_json)
        payload.pop("ingested_at")
        encoded = json.dumps(
            [policy, payload], ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), allow_nan=False,
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


def _pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise EventError("DUPLICATE_JSON_KEY")
        result[key] = value
    return result


def _nonfinite(_: str) -> None:
    raise EventError("NONFINITE_JSON_VALUE")


def parse_event(raw: bytes, *, expected_scope: AccessScope) -> Event:
    """Parse the normalized event format, not a native agent rollout.

    expected_scope must come from trusted caller configuration. No inference,
    correction application, redaction, persistence, or provider calls occur here.
    """
    if not isinstance(raw, bytes):
        raise EventError("BYTES_REQUIRED")
    if not isinstance(expected_scope, AccessScope):
        raise EventError("TRUSTED_SCOPE_REQUIRED")
    try:
        payload = json.loads(
            raw.decode("utf-8"), object_pairs_hook=_pairs, parse_constant=_nonfinite,
        )
    except EventError:
        raise
    except (UnicodeError, ValueError, RecursionError):
        raise EventError("INVALID_JSON") from None
    if not isinstance(payload, dict):
        raise EventError("EVENT_OBJECT_REQUIRED")
    required = {
        "schema_version", "event_id", "stream_id", "message_id", "producer_epoch",
        "source_version", "source_ordinal", "event_type", "occurred_at", "ingested_at", "access_scope",
    }
    optional = {"role", "content", "reply_to", "tool_call_id", "attachment_ref"}
    if not required <= payload.keys():
        raise EventError("MISSING_EVENT_FIELDS")
    if payload.keys() - required - optional:
        raise EventError("UNKNOWN_EVENT_FIELDS")
    if type(payload["schema_version"]) is not int or payload["schema_version"] != 1:
        raise EventError("UNSUPPORTED_SCHEMA_VERSION")
    if type(payload["source_version"]) is not int or payload["source_version"] < 0:
        raise EventError("INVALID_SOURCE_VERSION")
    if type(payload["source_ordinal"]) is not int or not 0 <= payload["source_ordinal"] <= 2**63 - 1:
        raise EventError("INVALID_SOURCE_ORDINAL")
    for name in ("event_id", "stream_id", "message_id", "producer_epoch", "event_type"):
        _identifier(payload[name], name)
    for name in ("occurred_at", "ingested_at"):
        value = _text(payload[name], name)
        try:
            stamp = datetime.fromisoformat(value)
            if stamp.tzinfo is None or stamp.utcoffset() is None:
                raise ValueError
        except ValueError:
            raise EventError("TIMEZONE_REQUIRED") from None
    supplied = payload["access_scope"]
    if not isinstance(supplied, dict) or set(supplied) != {"tenant_id", "project_id"}:
        raise EventError("INVALID_ACCESS_SCOPE")
    scope = AccessScope(supplied["tenant_id"], supplied["project_id"], payload["stream_id"])
    if scope != expected_scope:
        raise EventError("SCOPE_MISMATCH")
    event_type = payload["event_type"]
    if event_type in {"grant", "revoke"}:
        raise EventError("UNIMPLEMENTED_AUTHORITY_EVENT")
    if event_type not in {"create", "edit", "delete", "restore"}:
        raise EventError("UNSUPPORTED_EVENT_TYPE")
    role, content = payload.get("role"), payload.get("content")
    if event_type in {"create", "edit"}:
        _text(role, "role")
        if role not in {"user", "assistant"}:
            raise EventError("UNSUPPORTED_ROLE")
        if not isinstance(content, str):
            raise EventError("INVALID_CONTENT")
    elif role is not None or content is not None:
        raise EventError("CONTROL_EVENT_BODY_NOT_ALLOWED")
    for name in ("reply_to", "tool_call_id", "attachment_ref"):
        if name in payload:
            _text(payload[name], name)
    try:
        canonical = json.dumps(
            payload, ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), allow_nan=False,
        ).encode("utf-8")
    except (UnicodeError, ValueError):
        raise EventError("INVALID_EVENT_ENCODING") from None
    return Event(
        payload["event_id"], payload["message_id"], payload["producer_epoch"],
        payload["source_version"], payload["source_ordinal"], event_type, scope, role, content, canonical,
    )
