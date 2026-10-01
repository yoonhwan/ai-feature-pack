"""Consumer-owned event adapter: callers supply events, bytes, and CAS tokens.

This example does not watch, enumerate, poll, read, or delete external files.
A missing entry or failed listing is an observation, never a deletion request.
Persist an event's ID and expected revision before delivery, then resend the
same event unchanged on retry. Obtain a revision token from the previous API
response or an explicit status request; never silently refresh a stale token.
"""

from __future__ import annotations

from dataclasses import dataclass

from airag import api


@dataclass(frozen=True)
class SourceEvent:
    event_id: str
    kind: str
    collection: str
    source_key: str | None = None
    content: bytes | None = None
    expected_revision: str | None = None
    media_type: str = "text/plain"
    origin_uri: str | None = None
    profile_key: str | None = None


def handle_event(con, event: SourceEvent) -> dict[str, object]:
    """Deliver exactly one explicit event, without inferring other mutations."""
    if not isinstance(event, SourceEvent) or not isinstance(event.event_id, str) or not event.event_id.strip():
        return api.envelope("consumer event", ok=False,
                            error={"code": "VALIDATION_ERROR", "message": "event_id must be a nonempty string", "retryable": False})
    if event.kind in ("unavailable", "incomplete_listing", "missing"):
        return api.envelope("consumer observation", ok=True, request_id=event.event_id,
                            data={"ignored": True, "reason": event.kind})
    if event.kind == "add":
        return api.add(con, event.event_id, event.collection, event.source_key, event.content,
                       media_type=event.media_type, origin_uri=event.origin_uri, profile_key=event.profile_key)
    if event.kind == "update":
        return api.update(con, event.event_id, event.collection, event.source_key, event.expected_revision,
                          event.content, media_type=event.media_type, origin_uri=event.origin_uri,
                          profile_key=event.profile_key)
    if event.kind == "delete":
        return api.delete(con, event.event_id, event.collection, event.source_key, event.expected_revision)
    if event.kind == "restore":
        return api.restore(con, event.event_id, event.collection, event.source_key, event.expected_revision)
    return api.envelope("consumer event", ok=False, request_id=event.event_id,
                        error={"code": "VALIDATION_ERROR", "message": "unsupported explicit event kind", "retryable": False})
