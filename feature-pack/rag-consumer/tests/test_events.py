import json

import pytest

from airag_consumer.events import AccessScope, EventError, parse_event


def encoded(payload):
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def test_replay_ignores_arrival_time_but_detects_source_and_policy_changes(payload, scope):
    first = parse_event(encoded(payload), expected_scope=scope)
    payload["ingested_at"] = "2026-09-28T01:00:00Z"
    replay = parse_event(encoded(payload), expected_scope=scope)
    assert first.replay_fingerprint(redaction_version="r1") == replay.replay_fingerprint(redaction_version="r1")
    payload["content"] = "다른 내용"
    changed = parse_event(encoded(payload), expected_scope=scope)
    assert first.replay_fingerprint(redaction_version="r1") != changed.replay_fingerprint(redaction_version="r1")
    assert first.replay_fingerprint(redaction_version="r1") != first.replay_fingerprint(redaction_version="r2")


@pytest.mark.parametrize("field,value,code", [
    ("schema_version", True, "UNSUPPORTED_SCHEMA_VERSION"),
    ("source_version", True, "INVALID_SOURCE_VERSION"),
    ("source_version", -1, "INVALID_SOURCE_VERSION"),
    ("content", {"text": "x"}, "INVALID_CONTENT"),
    ("role", "developer", "UNSUPPORTED_ROLE"),
    ("role", "system", "UNSUPPORTED_ROLE"),
    ("occurred_at", "2026-09-27T00:00:00", "TIMEZONE_REQUIRED"),
    ("event_type", "grant", "UNIMPLEMENTED_AUTHORITY_EVENT"),
    ("event_type", "revoke", "UNIMPLEMENTED_AUTHORITY_EVENT"),
    ("role", "tool", "UNSUPPORTED_ROLE"),
    ("role", "customer", "UNSUPPORTED_ROLE"),
    ("source_ordinal", True, "INVALID_SOURCE_ORDINAL"),
    ("source_ordinal", -1, "INVALID_SOURCE_ORDINAL"),
    ("source_ordinal", 2**63, "INVALID_SOURCE_ORDINAL"),
    ("event_id", " e001", "INVALID_EVENT_ID"),
    ("message_id", "m001\nother", "INVALID_MESSAGE_ID"),
    ("event_id", "", "INVALID_EVENT_ID"),
])
def test_invalid_fields_fail_explicitly(payload, scope, field, value, code):
    payload[field] = value
    with pytest.raises(EventError, match=code):
        parse_event(encoded(payload), expected_scope=scope)


@pytest.mark.parametrize("field,value", [("tenant_id", "other"), ("project_id", "other")])
def test_event_cannot_choose_its_own_scope(payload, scope, field, value):
    payload["access_scope"][field] = value
    with pytest.raises(EventError, match="SCOPE_MISMATCH"):
        parse_event(encoded(payload), expected_scope=scope)


def test_stream_scope_mismatch(payload, scope):
    payload["stream_id"] = "another-stream"
    with pytest.raises(EventError, match="SCOPE_MISMATCH"):
        parse_event(encoded(payload), expected_scope=scope)


def test_pending_tenant_is_not_an_authorized_scope():
    with pytest.raises(EventError, match="UNRESOLVED_SCOPE"):
        AccessScope("pending_user_value", "project", "stream")


@pytest.mark.parametrize("raw,code", [
    (b'{"x":1,"x":2}', "DUPLICATE_JSON_KEY"),
    (b'{"nested":{"x":1,"x":2}}', "DUPLICATE_JSON_KEY"),
    (b'{"x":NaN}', "NONFINITE_JSON_VALUE"),
    (b'{"x":Infinity}', "NONFINITE_JSON_VALUE"),
    (b'[]', "EVENT_OBJECT_REQUIRED"),
    (b'\xff', "INVALID_JSON"),
])
def test_ambiguous_json_rejected(raw, code, scope):
    with pytest.raises(EventError, match=code):
        parse_event(raw, expected_scope=scope)


def test_errors_do_not_echo_sensitive_payload(scope):
    with pytest.raises(EventError) as caught:
        parse_event(b'{"secret":"DO-NOT-ECHO"', expected_scope=scope)
    assert "DO-NOT-ECHO" not in str(caught.value)


def test_direct_parser_requires_bytes_and_trusted_scope(payload, scope):
    with pytest.raises(EventError, match="BYTES_REQUIRED"):
        parse_event("{}", expected_scope=scope)
    with pytest.raises(EventError, match="TRUSTED_SCOPE_REQUIRED"):
        parse_event(encoded(payload), expected_scope=None)


def test_delete_is_an_event_not_a_body_update(payload, scope):
    payload["event_type"] = "delete"
    with pytest.raises(EventError, match="CONTROL_EVENT_BODY_NOT_ALLOWED"):
        parse_event(encoded(payload), expected_scope=scope)
    del payload["role"], payload["content"]
    event = parse_event(encoded(payload), expected_scope=scope)
    assert event.event_type == "delete" and event.content is None


def test_restore_is_control_only_and_missing_ordinal_is_rejected(payload, scope):
    payload["event_type"] = "restore"
    with pytest.raises(EventError, match="CONTROL_EVENT_BODY_NOT_ALLOWED"):
        parse_event(encoded(payload), expected_scope=scope)
    del payload["role"], payload["content"]
    assert parse_event(encoded(payload), expected_scope=scope).content is None
    del payload["source_ordinal"]
    with pytest.raises(EventError, match="MISSING_EVENT_FIELDS"):
        parse_event(encoded(payload), expected_scope=scope)


def test_unknown_fields_and_missing_identity_are_not_silently_dropped(payload, scope):
    payload["hidden_payload"] = "not part of the contract"
    with pytest.raises(EventError, match="UNKNOWN_EVENT_FIELDS"):
        parse_event(encoded(payload), expected_scope=scope)
    del payload["hidden_payload"], payload["message_id"]
    with pytest.raises(EventError, match="MISSING_EVENT_FIELDS"):
        parse_event(encoded(payload), expected_scope=scope)


def test_escaped_invalid_unicode_is_rejected(payload, scope):
    payload["content"] = "\ud800"
    with pytest.raises(EventError, match="INVALID_EVENT_ENCODING"):
        parse_event(json.dumps(payload).encode(), expected_scope=scope)
