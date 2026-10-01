import json
from pathlib import Path

import pytest

from airag_consumer.conversation import CONVERSATION_MEDIA_TYPE, create_only_conversation, message_anchor_id
from airag_consumer.events import AccessScope, EventError, parse_event
from airag_consumer.jsonl import read_batch


def event(payload, scope):
    return parse_event(json.dumps(payload).encode(), expected_scope=scope)


def test_synthetic_contract_reaches_real_docling_with_scoped_message_anchors(scope):
    from airag import normalize

    fixture = Path(__file__).resolve().parents[2] / "rag/docs/artifacts/p08a01-synthetic-conversation.jsonl"
    batch = read_batch(fixture.read_bytes(), expected_scope=scope)
    raw = create_only_conversation([r.event for r in batch.records])
    turns = json.loads(raw)["turns"]
    doc = normalize.build_document(CONVERSATION_MEDIA_TYPE, raw, name="synthetic-W001")
    assert len(turns) == 2
    assert {a.turn_id for a in doc.anchors.values()} == {t["id"] for t in turns}
    for i, turn in enumerate(turns):
        assert turn["id"] == message_anchor_id(batch.records[i].event)
        assert "synthetic" not in turn["id"] and "airag-contract" not in turn["id"]
        assert any(a.pointer == f"/turns/{i}/text" and a.original_text == turn["text"] for a in doc.anchors.values())


def test_empty_body_has_no_search_turn_but_event_is_preserved(payload, scope):
    payload["content"] = " \n\t"
    source = event(payload, scope)
    assert json.loads(create_only_conversation([source])) == {"turns": []}
    assert source.message_id == "m001" and source.canonical_json


def test_correction_cannot_be_misrepresented_as_new_message(payload, scope):
    payload["event_type"] = "edit"
    with pytest.raises(EventError, match="CORRECTION_REDUCTION_REQUIRED"):
        create_only_conversation([event(payload, scope)])


def test_duplicate_requires_ledger_not_silent_duplicate_turn(payload, scope):
    source = event(payload, scope)
    with pytest.raises(EventError, match="DUPLICATE_EVENT_REQUIRES_LEDGER"):
        create_only_conversation([source, source])
    payload["event_id"] = "another-event"
    with pytest.raises(EventError, match="DUPLICATE_MESSAGE_REQUIRES_LEDGER"):
        create_only_conversation([source, event(payload, scope)])


def test_cross_scope_merge_rejected(payload, scope):
    first = event(payload, scope)
    payload["stream_id"] = "other"
    second = event(payload, AccessScope("synthetic", "airag-contract", "other"))
    with pytest.raises(EventError, match="MIXED_SCOPES"):
        create_only_conversation([first, second])


def test_source_ordinal_makes_out_of_order_snapshot_deterministic(payload, scope):
    first = event(payload, scope)
    payload.update(event_id="e002", message_id="m002", source_ordinal=2, content="second")
    second = event(payload, scope)
    assert create_only_conversation([second, first]) == create_only_conversation([first, second])


def test_duplicate_ordinal_and_mixed_epoch_need_reconciliation(payload, scope):
    first = event(payload, scope)
    payload.update(event_id="e002", message_id="m002")
    with pytest.raises(EventError, match="DUPLICATE_SOURCE_ORDINAL"):
        create_only_conversation([first, event(payload, scope)])
    payload.update(source_ordinal=2, producer_epoch="new")
    with pytest.raises(EventError, match="EPOCH_RECONCILIATION_REQUIRED"):
        create_only_conversation([first, event(payload, scope)])


def test_manually_modified_event_cannot_bypass_public_role_gate(payload, scope):
    from dataclasses import replace
    first = event(payload, scope)
    with pytest.raises(EventError, match="EVENT_REPRESENTATION_MISMATCH"):
        create_only_conversation([replace(first, role="tool")])


def test_literal_placeholder_is_not_silently_removed(payload, scope):
    payload["content"] = "[REDACTED:environment_context]"
    turns = json.loads(create_only_conversation([event(payload, scope)]))["turns"]
    assert turns[0]["text"] == payload["content"]


def test_real_redaction_empty_body_uses_provenance(payload, scope):
    from airag_consumer.conversation import redacted_conversation
    from airag_consumer.redaction import redact_event
    payload["content"] = "<environment_context>private</environment_context>"
    redacted = redact_event(event(payload, scope))
    assert json.loads(redacted_conversation([redacted])) == {"turns": []}
