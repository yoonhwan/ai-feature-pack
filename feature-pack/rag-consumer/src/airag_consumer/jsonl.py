"""Bounded, byte-addressed JSONL parsing; offsets are not durable checkpoints."""

from __future__ import annotations

from dataclasses import dataclass

from .events import AccessScope, Event, EventError, parse_event


class JsonlError(EventError):
    def __init__(self, code: str, start_offset: int, end_offset: int) -> None:
        self.code = code
        self.start_offset = start_offset
        self.end_offset = end_offset
        super().__init__(f"{code} AT_BYTE_{start_offset}")


@dataclass(frozen=True)
class EventRecord:
    start_offset: int
    end_offset: int
    event: Event


@dataclass(frozen=True)
class EventBatch:
    records: tuple[EventRecord, ...]
    parsed_end_offset: int
    pending_tail: bytes


def read_batch(
    data: bytes,
    *,
    expected_scope: AccessScope,
    start_offset: int = 0,
    max_record_bytes: int = 1_048_576,
    max_batch_bytes: int = 8_388_608,
) -> EventBatch:
    """Read a snapshot starting at a verified record boundary.

    Incomplete final bytes remain pending, including split UTF-8 characters.
    An invalid complete line fails the whole batch. The caller must preserve
    the previous checkpoint until all accepted records are durably committed.
    """
    if not isinstance(data, bytes):
        raise EventError("BYTES_REQUIRED")
    if not isinstance(expected_scope, AccessScope):
        raise EventError("TRUSTED_SCOPE_REQUIRED")
    if type(start_offset) is not int or start_offset < 0:
        raise EventError("INVALID_OFFSET")
    for limit in (max_record_bytes, max_batch_bytes):
        if type(limit) is not int or limit <= 0:
            raise EventError("INVALID_LIMIT")
    if len(data) > max_batch_bytes:
        raise EventError("BATCH_TOO_LARGE")
    cursor = 0
    records = []
    while True:
        end = data.find(b"\n", cursor)
        if end == -1:
            if len(data) - cursor > max_record_bytes:
                raise EventError("RECORD_TOO_LARGE")
            break
        if end - cursor > max_record_bytes:
            raise EventError("RECORD_TOO_LARGE")
        raw = data[cursor:end]
        if not raw.strip():
            raise EventError("EMPTY_JSONL_RECORD")
        try:
            event = parse_event(raw, expected_scope=expected_scope)
        except EventError as exc:
            raise JsonlError(str(exc), start_offset + cursor, start_offset + end + 1) from None
        records.append(EventRecord(start_offset + cursor, start_offset + end + 1, event))
        cursor = end + 1
    return EventBatch(tuple(records), start_offset + cursor, data[cursor:])
