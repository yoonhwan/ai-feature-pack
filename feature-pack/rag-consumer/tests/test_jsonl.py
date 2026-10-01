import json

import pytest

from airag_consumer.events import EventError
from airag_consumer.jsonl import JsonlError, read_batch


def line(payload):
    return json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n"


def test_offsets_are_bytes_and_partial_utf8_is_not_committed(payload, scope):
    first = line(payload)
    payload["event_id"], payload["message_id"] = "e002", "m002"
    second = line(payload)
    split = second.index("설".encode()) + 1
    batch = read_batch(first + second[:split], expected_scope=scope, start_offset=100)
    assert len(batch.records) == 1
    assert batch.records[0].start_offset == 100
    assert batch.parsed_end_offset == 100 + len(first)
    assert batch.pending_tail == second[:split]
    resumed = read_batch(
        batch.pending_tail + second[split:], expected_scope=scope,
        start_offset=batch.parsed_end_offset,
    )
    assert len(resumed.records) == 1
    assert resumed.records[0].event.message_id == "m002"
    assert resumed.parsed_end_offset == 100 + len(first) + len(second)
    assert resumed.pending_tail == b""


def test_complete_json_without_newline_stays_pending(payload, scope):
    raw = line(payload)[:-1]
    batch = read_batch(raw, expected_scope=scope)
    assert not batch.records and batch.parsed_end_offset == 0
    assert batch.pending_tail == raw


def test_bad_later_line_cannot_return_an_advanced_checkpoint(payload, scope):
    with pytest.raises(JsonlError, match="INVALID_JSON") as caught:
        read_batch(line(payload) + b'{"broken"}\n', expected_scope=scope)
    assert caught.value.start_offset == len(line(payload))
    assert caught.value.end_offset > caught.value.start_offset


@pytest.mark.parametrize("raw", [b"\n", b" \t\n"])
def test_blank_lines_are_not_accepted_events(raw, scope):
    with pytest.raises(EventError, match="EMPTY_JSONL_RECORD"):
        read_batch(raw, expected_scope=scope)


def test_crlf_offsets_include_both_bytes(payload, scope):
    raw = line(payload)[:-1] + b"\r\n"
    batch = read_batch(raw, expected_scope=scope)
    assert len(batch.records) == 1 and batch.parsed_end_offset == len(raw)


@pytest.mark.parametrize("raw", [b"x" * 6, b"x" * 6 + b"\n"])
def test_bounded_record_including_unterminated_tail(raw, scope):
    with pytest.raises(EventError, match="RECORD_TOO_LARGE"):
        read_batch(raw, expected_scope=scope, max_record_bytes=5)


def test_bounded_batch(scope):
    with pytest.raises(EventError, match="BATCH_TOO_LARGE"):
        read_batch(b"x" * 6, expected_scope=scope, max_batch_bytes=5)


def test_empty_snapshot_still_requires_trusted_scope():
    with pytest.raises(EventError, match="TRUSTED_SCOPE_REQUIRED"):
        read_batch(b"", expected_scope=None)


@pytest.mark.parametrize("offset", [-1, True, 1.5])
def test_offsets_must_be_nonnegative_integers(scope, offset):
    with pytest.raises(EventError, match="INVALID_OFFSET"):
        read_batch(b"", expected_scope=scope, start_offset=offset)
