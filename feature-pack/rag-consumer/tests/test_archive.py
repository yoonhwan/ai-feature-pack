import os
from pathlib import Path
import sqlite3

import pytest

from airag_consumer.archive import lookup_archive, verify_archive, write_archive
from airag_consumer.events import AccessScope, EventError


def record(scope, identity="event-1"):
    return {"id": identity, "kind": "event",
            "scope": [scope.tenant_id, scope.project_id, scope.stream_id],
            "payload": {"content": "이전 해결 근거 PUBLIC_MARKER api_key=SECRET_ARCHIVE_MARKER",
                        "message_id": "m001", "source_ordinal": 1}}


def test_encrypted_immutable_archive_replay_and_explicit_lookup(tmp_path, scope):
    key = os.urandom(32)
    first = write_archive(tmp_path, key, scope, [record(scope)])
    again = write_archive(tmp_path, key, scope, [record(scope)])
    assert first == again and len(list(tmp_path.glob("archive-*.db"))) == 1
    assert not list(tmp_path.glob(".partial-*.db"))
    assert b"PUBLIC_MARKER" not in Path(first.path).read_bytes()
    assert b"SECRET_ARCHIVE_MARKER" not in Path(first.path).read_bytes()
    with pytest.raises(EventError, match="EXPLICIT_ARCHIVE_LOOKUP"):
        lookup_archive(first.path, key, scope, explicit_request=False, authorize_record=lambda _: True)
    found = lookup_archive(first.path, key, scope, explicit_request=True,
                           authorize_record=lambda _: True, query="해결")
    assert len(found) == 1
    assert "SECRET_ARCHIVE_MARKER" not in found[0]["payload"]["content"]
    assert "PUBLIC_MARKER" in found[0]["payload"]["content"]
    assert verify_archive(first.path, key, scope).bundle_id == first.bundle_id


def test_current_auth_scope_and_wrong_key(tmp_path, scope):
    key = os.urandom(32)
    receipt = write_archive(tmp_path, key, scope, [record(scope)])
    assert lookup_archive(receipt.path, key, scope, explicit_request=True,
                          authorize_record=lambda _: False) == []
    assert lookup_archive(receipt.path, key, scope, explicit_request=True,
                          authorize_record=lambda _: True, query="message_id") == []
    assert len(lookup_archive(receipt.path, key, scope, explicit_request=True,
                             authorize_record=lambda _: True, query="m001")) == 1
    with pytest.raises(EventError, match="SCOPE"):
        verify_archive(receipt.path, key, AccessScope("other", scope.project_id, scope.stream_id))
    with pytest.raises(EventError, match="ARCHIVE_READ"):
        verify_archive(receipt.path, os.urandom(32), scope)
    con = sqlite3.connect(receipt.path)
    try:
        with pytest.raises(sqlite3.DatabaseError):
            con.execute("SELECT * FROM sqlite_master").fetchall()
    finally:
        con.close()


def test_untrusted_records_and_keys_fail_before_creating_archive(tmp_path, scope):
    key = os.urandom(32)
    bad = record(scope)
    bad["payload"]["content"] = "<environment_context>unfinished"
    with pytest.raises(EventError, match="UNBALANCED"):
        write_archive(tmp_path / "not-created", key, scope, [bad])
    assert not (tmp_path / "not-created").exists()
    with pytest.raises(EventError, match="KEY_MUST"):
        write_archive(tmp_path / "not-created", b"bad", scope, [record(scope)])
    bad = record(scope)
    bad["scope"][0] = "foreign"
    with pytest.raises(EventError, match="SCOPE"):
        write_archive(tmp_path, key, scope, [bad])
    with pytest.raises(EventError, match="DUPLICATE"):
        write_archive(tmp_path, key, scope, [record(scope), record(scope)])


def test_tamper_detected_and_existing_target_never_overwritten(tmp_path, scope):
    key = os.urandom(32)
    receipt = write_archive(tmp_path, key, scope, [record(scope)])
    import sqlcipher3 as sqlite
    con = sqlite.connect(receipt.path)
    con.execute(f"""PRAGMA key = "x'{key.hex()}'" """)
    con.execute("UPDATE entries SET payload=?", (b"{}",))
    con.commit()
    con.close()
    before = Path(receipt.path).read_bytes()
    with pytest.raises(EventError, match="DIGEST"):
        write_archive(tmp_path, key, scope, [record(scope)])
    assert Path(receipt.path).read_bytes() == before


def test_failed_verification_does_not_publish_or_release_source(tmp_path, scope, monkeypatch):
    import airag_consumer.archive as archive
    key = os.urandom(32)
    def fail(*args):
        raise EventError("SYNTHETIC_ARCHIVE_VERIFICATION_FAILURE")
    monkeypatch.setattr(archive, "verify_archive", fail)
    with pytest.raises(EventError, match="SYNTHETIC"):
        write_archive(tmp_path, key, scope, [record(scope)])
    assert not list(tmp_path.glob("archive-*.db"))
    assert list(tmp_path.glob(".partial-*.db"))
