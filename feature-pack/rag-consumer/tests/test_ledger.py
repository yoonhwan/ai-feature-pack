from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
import sqlite3
import threading

import pytest

from airag_consumer.events import AccessScope, EventError
from airag_consumer.ledger import open_ledger


@pytest.fixture
def key():
    return os.urandom(32)


def line(payload):
    return json.dumps(payload, ensure_ascii=False).encode() + b"\n"


def ingest(ledger, data, scope, offset=0, incarnation="file-1"):
    return ledger.ingest(data, source_id="selected-jsonl", incarnation=incarnation,
                         expected_scope=scope, start_offset=offset)


def event_count(ledger):
    return ledger._con.execute("SELECT count(*) FROM events").fetchone()[0]


def test_commit_reopen_and_retry_after_lost_ack(tmp_path, key, payload, scope):
    path = tmp_path / "ledger.db"
    data = line(payload)
    with open_ledger(path, key) as ledger:
        receipt = ingest(ledger, data, scope)
        assert receipt.inserted_events == 1 and receipt.committed_offset == len(data)
    with open_ledger(path, key) as ledger:
        retry = ingest(ledger, data, scope)
        assert retry.inserted_events == 0 and retry.replayed_events == 1
        assert ledger.checkpoint("selected-jsonl") == len(data)
        assert event_count(ledger) == 1
    assert path.stat().st_mode & 0o077 == 0


def test_duplicate_at_new_offset_preserves_first_acceptance(tmp_path, key, payload, scope):
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        first = line(payload)
        ingest(ledger, first, scope)
        payload["ingested_at"] = "2026-09-28T00:00:00Z"
        second = line(payload)
        receipt = ingest(ledger, second, scope, offset=len(first))
        assert receipt.inserted_events == 0 and receipt.replayed_events == 1
        assert receipt.committed_offset == len(first) + len(second)
        stored = json.loads(ledger._con.execute("SELECT redacted_json FROM events").fetchone()[0])
        assert stored["ingested_at"] == "2026-09-27T00:00:01Z"


def test_pending_tail_not_stored_or_acked(tmp_path, key, payload, scope):
    complete = line(payload)
    payload["event_id"], payload["message_id"] = "e002", "m002"
    payload["source_ordinal"] = 2
    later = line(payload)
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        receipt = ingest(ledger, complete + later[:10], scope)
        assert receipt.pending_bytes == 10 and receipt.committed_offset == len(complete)
        assert event_count(ledger) == 1
        receipt = ingest(ledger, later, scope, offset=len(complete))
        assert receipt.committed_offset == len(complete) + len(later)
        assert event_count(ledger) == 2


def test_event_conflict_rolls_back_other_new_events_and_checkpoint(tmp_path, key, payload, scope):
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        first = line(payload)
        ingest(ledger, first, scope)
        second = dict(payload, event_id="e002", message_id="m002", source_ordinal=2)
        changed = dict(payload, content="changed source payload")
        with pytest.raises(EventError, match="EVENT_ID_CONFLICT"):
            ingest(ledger, line(second) + line(changed), scope, offset=len(first))
        assert event_count(ledger) == 1
        assert ledger.checkpoint("selected-jsonl") == len(first)


def test_same_span_with_changed_bytes_is_conflict(tmp_path, key, payload, scope):
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        first = line(payload)
        ingest(ledger, first, scope)
        payload["event_id"] = "e999"
        assert len(line(payload)) == len(first)
        with pytest.raises(EventError, match="DELIVERY_CONFLICT"):
            ingest(ledger, line(payload), scope)
        assert event_count(ledger) == 1


def test_same_ordinal_different_event_rolls_back(tmp_path, key, payload, scope):
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        first = line(payload)
        ingest(ledger, first, scope)
        payload.update(event_id="e002", message_id="m002")
        with pytest.raises(EventError, match="SOURCE_ORDINAL_CONFLICT"):
            ingest(ledger, line(payload), scope, offset=len(first))
        assert event_count(ledger) == 1 and ledger.checkpoint("selected-jsonl") == len(first)


def test_transaction_fault_after_event_insert_leaves_no_commit(tmp_path, key, payload, scope):
    path = tmp_path / "ledger.db"
    with open_ledger(path, key) as ledger:
        ledger._con.execute("""CREATE TRIGGER fail_record BEFORE INSERT ON records
            BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END""")
        with pytest.raises(EventError, match="LEDGER_TRANSACTION_FAILED"):
            ingest(ledger, line(payload), scope)
        assert ledger.checkpoint("selected-jsonl") is None and event_count(ledger) == 0
    with open_ledger(path, key) as ledger:
        assert ledger.checkpoint("selected-jsonl") is None and event_count(ledger) == 0


def test_failure_before_commit_does_not_advance_existing_source(tmp_path, key, payload, scope):
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        first = line(payload)
        ingest(ledger, first, scope)
        ledger._con.execute("""CREATE TRIGGER fail_checkpoint BEFORE UPDATE ON sources
            BEGIN SELECT RAISE(ABORT, 'synthetic checkpoint failure'); END""")
        payload["event_id"], payload["message_id"] = "e002", "m002"
        payload["source_ordinal"] = 2
        with pytest.raises(EventError, match="LEDGER_TRANSACTION_FAILED"):
            ingest(ledger, line(payload), scope, offset=len(first))
        assert ledger.checkpoint("selected-jsonl") == len(first) and event_count(ledger) == 1


def test_scope_incarnation_and_policy_are_bound(tmp_path, key, payload, scope):
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        data = line(payload)
        ingest(ledger, data, scope)
        with pytest.raises(EventError, match="SOURCE_BINDING_MISMATCH"):
            ingest(ledger, data, scope, incarnation="replaced-file")
        payload["access_scope"]["project_id"] = "other"
        with pytest.raises(EventError, match="SOURCE_BINDING_MISMATCH"):
            ingest(ledger, line(payload), AccessScope("synthetic", "other", scope.stream_id))
        ledger._con.execute("UPDATE sources SET policy_version='other-policy'")
        with pytest.raises(EventError, match="SOURCE_BINDING_MISMATCH"):
            ingest(ledger, data, scope)


def test_gap_and_bad_line_do_not_create_source(tmp_path, key, payload, scope):
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        with pytest.raises(EventError, match="CHECKPOINT_GAP"):
            ingest(ledger, line(payload), scope, offset=5)
        with pytest.raises(EventError, match="INVALID_JSON"):
            ingest(ledger, line(payload) + b"bad-json\n", scope)
        assert ledger.checkpoint("selected-jsonl") is None


def test_redaction_precedes_storage_and_audit_has_no_secret(tmp_path, key, payload, scope):
    secret = "SYNTHETIC-NOT-FOR-STORAGE"
    marker = "PUBLIC-ENCRYPTION-MARKER"
    payload["content"] = marker + " api_key=" + secret
    path = tmp_path / "ledger.db"
    with open_ledger(path, key) as ledger:
        ingest(ledger, line(payload), scope)
        body, audit = ledger._con.execute("SELECT redacted_json,audit_rules FROM events").fetchone()
        assert secret not in body.decode() and marker in body.decode()
        assert secret not in audit and "named_secret" in audit
    for file in tmp_path.iterdir():
        assert secret.encode() not in file.read_bytes()
        assert marker.encode() not in file.read_bytes()


def test_redaction_failure_cannot_ack_or_store(tmp_path, key, payload, scope):
    payload["content"] = "<environment_context>no closing block"
    with open_ledger(tmp_path / "ledger.db", key) as ledger:
        with pytest.raises(EventError, match="UNBALANCED"):
            ingest(ledger, line(payload), scope)
        assert event_count(ledger) == 0 and ledger.checkpoint("selected-jsonl") is None


def test_wrong_key_and_plain_sqlite_fail_without_modifying_db(tmp_path, key, payload, scope):
    path = tmp_path / "ledger.db"
    with open_ledger(path, key) as ledger:
        ingest(ledger, line(payload), scope)
    before = hashlib.sha256(path.read_bytes()).digest()
    with pytest.raises(EventError, match="LEDGER_OPEN_FAILED"):
        open_ledger(path, os.urandom(32))
    con = sqlite3.connect(path)
    try:
        with pytest.raises(sqlite3.DatabaseError):
            con.execute("SELECT * FROM sqlite_master").fetchall()
    finally:
        con.close()
    assert hashlib.sha256(path.read_bytes()).digest() == before


def test_plaintext_and_preexisting_empty_files_never_adopted(tmp_path, key):
    plain = tmp_path / "plain.db"
    con = sqlite3.connect(plain)
    con.execute("CREATE TABLE private_data(body TEXT)")
    con.close()
    plain.chmod(0o600)
    before = plain.read_bytes()
    with pytest.raises(EventError):
        open_ledger(plain, key)
    assert plain.read_bytes() == before
    empty = tmp_path / "empty.db"
    empty.touch(mode=0o600)
    with pytest.raises(EventError):
        open_ledger(empty, key)
    assert empty.read_bytes() == b""


def test_invalid_key_and_symlink_do_not_create_or_touch_target(tmp_path, key):
    path = tmp_path / "new.db"
    with pytest.raises(EventError, match="KEY_MUST_BE"):
        open_ledger(path, b"short")
    assert not path.exists()
    target = tmp_path / "target.db"
    target.write_text("preserved")
    path.symlink_to(target)
    with pytest.raises(EventError, match="SYMLINK"):
        open_ledger(path, key)
    assert target.read_text() == "preserved"


def test_concurrent_identical_delivery_commits_once(tmp_path, key, payload, scope):
    path = tmp_path / "ledger.db"
    with open_ledger(path, key):
        pass
    barrier = threading.Barrier(2)
    def run():
        with open_ledger(path, key) as ledger:
            barrier.wait(timeout=10)
            return ingest(ledger, line(payload), scope)
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = [pool.submit(run) for _ in range(2)]
        receipts = [job.result(timeout=15) for job in jobs]
    assert sorted(r.inserted_events for r in receipts) == [0, 1]
    with open_ledger(path, key) as ledger:
        assert event_count(ledger) == 1 and ledger.checkpoint("selected-jsonl") == len(line(payload))
