import hashlib
import json
import os

import pytest

from airag_consumer.events import EventError
from airag_consumer.ledger import open_ledger


def line(payload):
    return json.dumps(payload, ensure_ascii=False).encode() + b"\n"


def ingest(ledger, data, scope, offset):
    return ledger.ingest(data, source_id="selected", incarnation="file-1",
                         expected_scope=scope, start_offset=offset)


def skip(ledger, data, scope, offset, **kwargs):
    return ledger.skip_rejected_record(
        data, source_id="selected", incarnation="file-1", expected_scope=scope,
        start_offset=offset, expected_sha256=hashlib.sha256(data).hexdigest(), **kwargs,
    )


@pytest.mark.parametrize("bad_kind", ["invalid_json", "ambiguous_redaction"])
def test_poison_record_can_be_audited_and_later_record_committed(tmp_path, payload, scope, bad_kind):
    key = os.urandom(32)
    path = tmp_path / "ledger.db"
    good = line(payload)
    payload.update(event_id="e002", message_id="m002", source_ordinal=2,
                   content="<environment_context><environment_context>NO-STORE-PRIVATE")
    bad = line(payload) if bad_kind == "ambiguous_redaction" else b'{"bad":"NO-STORE-PRIVATE"\n'
    payload.update(event_id="e003", message_id="m003", source_ordinal=3, content="public")
    later = line(payload)
    with open_ledger(path, key) as ledger:
        ingest(ledger, good, scope, 0)
        with pytest.raises(EventError):
            ingest(ledger, bad + later, scope, len(good))
        assert ledger.checkpoint("selected") == len(good)
        receipt = skip(ledger, bad, scope, len(good), acknowledge_gap=True)
        assert receipt.coverage_gap and receipt.accepted_events == 0
        assert receipt.committed_offset == len(good) + len(bad)
        result = ingest(ledger, later, scope, receipt.committed_offset)
        assert result.inserted_events == 1
        rows = ledger._con.execute("SELECT * FROM rejections").fetchall()
        assert "NO-STORE-PRIVATE" not in repr(rows)
        assert ledger.rejection_count("selected") == 1
    with open_ledger(path, key) as ledger:
        replay = skip(ledger, bad, scope, len(good), acknowledge_gap=True)
        assert replay.replayed and replay.committed_offset == len(good + bad + later)
        assert ledger.rejection_count("selected") == 1


def test_skip_requires_explicit_gap_decision_and_rejected_single_record(tmp_path, payload, scope):
    with open_ledger(tmp_path / "ledger.db", os.urandom(32)) as ledger:
        with pytest.raises(EventError, match="EXPLICIT_GAP"):
            skip(ledger, b"bad\n", scope, 0)
        with pytest.raises(EventError, match="VALID_RECORD_CANNOT_SKIP"):
            skip(ledger, line(payload), scope, 0, acknowledge_gap=True)
        for data in [b"partial", b"bad\nsecond\n"]:
            with pytest.raises(EventError, match="ONE_COMPLETE_RECORD"):
                skip(ledger, data, scope, 0, acknowledge_gap=True)
        assert ledger.checkpoint("selected") is None


def test_skip_digest_and_contiguous_offset_are_checked(tmp_path, scope):
    with open_ledger(tmp_path / "ledger.db", os.urandom(32)) as ledger:
        with pytest.raises(EventError, match="DIGEST_MISMATCH"):
            ledger.skip_rejected_record(
                b"bad\n", source_id="selected", incarnation="file-1", expected_scope=scope,
                start_offset=0, expected_sha256="wrong", acknowledge_gap=True,
            )
        with pytest.raises(EventError, match="CHECKPOINT_GAP"):
            skip(ledger, b"bad\n", scope, 5, acknowledge_gap=True)
        assert ledger.checkpoint("selected") is None


def test_failed_skip_transaction_does_not_advance_or_leave_partial_audit(tmp_path, scope):
    key = os.urandom(32)
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        ledger._con.execute("""CREATE TRIGGER fail_gap BEFORE UPDATE ON sources
            BEGIN SELECT RAISE(ABORT, 'synthetic disk failure'); END""")
        with pytest.raises(EventError, match="LEDGER_TRANSACTION_FAILED"):
            skip(ledger, b"bad\n", scope, 0, acknowledge_gap=True)
        assert ledger.checkpoint("selected") is None and ledger.rejection_count("selected") == 0


def test_changed_rejected_bytes_at_same_range_are_not_replayed(tmp_path, scope):
    with open_ledger(tmp_path / "ledger.db", os.urandom(32)) as ledger:
        skip(ledger, b"bad\n", scope, 0, acknowledge_gap=True)
        with pytest.raises(EventError, match="REJECTION_CONFLICT"):
            skip(ledger, b"???\n", scope, 0, acknowledge_gap=True)
        assert ledger.checkpoint("selected") == 4


def test_source_reason_is_audited_separately_from_validation(tmp_path, scope):
    with open_ledger(tmp_path / "ledger.db", os.urandom(32)) as ledger:
        data = b"{}\n"
        receipt = ledger.skip_rejected_record(
            data, source_id="native", incarnation="file", expected_scope=scope,
            start_offset=0, expected_sha256=hashlib.sha256(data).hexdigest(),
            acknowledge_gap=True, source_reason_code="UNKNOWN_NATIVE_PART",
        )
        assert receipt.reason_code == "UNKNOWN_NATIVE_PART"
        assert ledger._con.execute("SELECT reason_code,validation_code FROM rejections").fetchone() == (
            "UNKNOWN_NATIVE_PART", "MISSING_EVENT_FIELDS",
        )
