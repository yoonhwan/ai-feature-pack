"""Pure conversation serialization for validated, create-only snapshots."""

from __future__ import annotations

import json
import hashlib
from collections.abc import Sequence

from .events import Event, EventError, parse_event
from .redaction import RedactedEvent


CONVERSATION_MEDIA_TYPE = "application/x-airag-conversation+json"


def message_anchor_id(event: Event) -> str:
    namespace = json.dumps(
        [event.scope.tenant_id, event.scope.project_id, event.scope.stream_id,
         event.producer_epoch, event.message_id],
        ensure_ascii=False, separators=(",", ":"),
    ).encode("utf-8")
    return "msg:" + hashlib.sha256(namespace).hexdigest()


def create_only_conversation(events: Sequence[Event]) -> bytes:
    """Bridge normalized events to core without calling or publishing to core.

    Production use still requires redaction, durable storage, correction
    reduction, and authorization gates. This function does none of those jobs.
    Timestamps and scope stay in the caller's event ledger, not in core turns.
    """
    for event in events:
        if not isinstance(event, Event):
            raise EventError("VALIDATED_EVENT_REQUIRED")
        if parse_event(event.canonical_json, expected_scope=event.scope) != event:
            raise EventError("EVENT_REPRESENTATION_MISMATCH")
    seen_events: set[str] = set()
    seen_messages: set[str] = set()
    scope = events[0].scope if events else None
    epoch = events[0].producer_epoch if events else None
    seen_ordinals: set[int] = set()
    turns = []
    for event in sorted(events, key=lambda item: item.source_ordinal):
        if event.scope != scope:
            raise EventError("MIXED_SCOPES")
        if event.producer_epoch != epoch:
            raise EventError("EPOCH_RECONCILIATION_REQUIRED")
        if event.event_type != "create":
            raise EventError("CORRECTION_REDUCTION_REQUIRED")
        if event.event_id in seen_events:
            raise EventError("DUPLICATE_EVENT_REQUIRES_LEDGER")
        seen_events.add(event.event_id)
        turn_id = message_anchor_id(event)
        if turn_id in seen_messages:
            raise EventError("DUPLICATE_MESSAGE_REQUIRES_LEDGER")
        seen_messages.add(turn_id)
        if event.source_ordinal in seen_ordinals:
            raise EventError("DUPLICATE_SOURCE_ORDINAL")
        seen_ordinals.add(event.source_ordinal)
        if event.content is None or event.role is None:
            raise EventError("INVALID_CREATE_EVENT")
        if not event.content.strip():
            continue
        turns.append({"id": turn_id, "role": event.role, "text": event.content})
    return json.dumps(
        {"turns": turns}, ensure_ascii=False, separators=(",", ":"), allow_nan=False,
    ).encode("utf-8")


def redacted_conversation(events: Sequence[RedactedEvent]) -> bytes:
    """Use trusted redaction provenance, not user-supplied placeholder spelling."""
    # Validate ordering/identity of every event before omitting empty projections.
    create_only_conversation([item.event for item in events])
    return create_only_conversation([item.event for item in events if item.has_public_text])
