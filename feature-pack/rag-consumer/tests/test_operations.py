from datetime import datetime, timedelta, timezone
import errno
import json
import os
from pathlib import Path

import pytest
import sqlcipher3

from airag_consumer import operations as ops
from airag_consumer.archive import verify_archive, write_archive


KEY = bytes(range(32))
OTHER_KEY = bytes(range(1, 33))
SEOUL = ops._SEOUL


def make_db(path: Path, key: bytes = KEY, *, created_at: datetime | None = None) -> None:
    created_at = created_at or datetime(2026, 9, 1, tzinfo=timezone.utc)
    con = sqlcipher3.connect(path)
    con.execute(f"PRAGMA key = \"x'{key.hex()}'\"")
    con.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, value TEXT, created_at TEXT)")
    con.execute("INSERT INTO records VALUES (1, 'saved', ?)", (created_at.isoformat(),))
    con.commit()
    con.close()


def archive_record(scope):
    return {"id": "event-1", "kind": "event",
            "scope": [scope.tenant_id, scope.project_id, scope.stream_id],
            "payload": {"message_id": "m001", "content": "saved"}}


def test_future_success_is_clock_error_not_permanent_schedule_suppression():
    from airag_consumer.operations import OperationsError, backup_due
    now = datetime(2026, 9, 27, 0, 0, tzinfo=timezone.utc)
    with pytest.raises(OperationsError, match="BACKUP_CLOCK_REGRESSION"):
        backup_due(now, now + timedelta(days=1))


def test_key_gate_and_unrelated_child_environment(tmp_path):
    env = {"AIRAG_CONSUMER_KEY_HEX": KEY.hex(), "AIRAG_PROJECTION_KEY_HEX": OTHER_KEY.hex(),
           "AIRAG_ARCHIVE_KEY_HEX": os.urandom(32).hex(), "PATH": "/bin"}
    assert ops.load_store_keys(ops.KEY_NAMES, env)["consumer_ledger"] == KEY
    assert ops.unrelated_child_environment(env) == {"PATH": "/bin"}
    with pytest.raises(ops.OperationsError):
        ops.load_store_keys(("consumer_ledger", "projection_db"), {**env, "AIRAG_PROJECTION_KEY_HEX": KEY.hex()})
    with pytest.raises(ops.OperationsError):
        ops.load_store_keys(("consumer_ledger",), {"AIRAG_CONSUMER_KEY_HEX": "bad"})
    with pytest.raises(ops.OperationsError):
        ops.load_store_keys(("archive",), {})
    assert list(tmp_path.iterdir()) == []


def test_schedule_slot_catchup_and_success_only():
    day = datetime(2026, 9, 27, 2, 59, tzinfo=SEOUL)
    yesterday = datetime(2026, 9, 26, 3, tzinfo=SEOUL)
    assert ops.backup_due(day, yesterday).due is False
    due = ops.backup_due(day + timedelta(minutes=1), yesterday)
    assert due.due and due.slot == datetime(2026, 9, 27, 3, tzinfo=SEOUL)
    assert due.catchup is False
    assert ops.backup_due(day + timedelta(minutes=2), yesterday).catchup is True
    assert ops.backup_due(day + timedelta(minutes=1), due.slot).due is False
    missed = ops.backup_due(day + timedelta(days=4), yesterday)
    assert missed.due and missed.catchup and missed.slot.date().day == 30
    assert ops.backup_due(day + timedelta(days=4), missed.slot).due is False
    with pytest.raises(ops.OperationsError):
        ops.backup_due(datetime(2026, 9, 27), None)


def test_backup_restore_wrong_key_and_cleanup_boundary(tmp_path, scope):
    root = tmp_path / "backups"
    root.mkdir()
    db = tmp_path / "ledger.db"
    archive_key = os.urandom(32)
    make_db(db)
    archive_receipt = write_archive(tmp_path / "archives", archive_key, scope,
                                    [archive_record(scope)])
    archive = Path(archive_receipt.path)
    seen = []

    def links(paths, current_now):
        assert current_now.tzinfo is not None
        con = ops._connect(paths["ledger"], KEY, True)
        try:
            assert con.execute("SELECT value FROM records").fetchone() == ("saved",)
        finally:
            con.close()
        assert verify_archive(paths["archive"], archive_key, scope).bundle_id == archive_receipt.bundle_id
        assert paths["archive"].read_bytes() == archive.read_bytes()
        seen.append(True)

    old = datetime(2026, 8, 1, 3, tzinfo=SEOUL)
    first = ops.create_backup_set(root, [ops.DatabaseSource("ledger", db, KEY)],
                                  [ops.ArchiveSource("archive", archive)], links, now=old)
    assert seen and first.is_dir()
    now = datetime(2026, 9, 27, 4, tzinfo=SEOUL)
    assert ops.verify_backup_set(first, {"ledger": KEY}, links, now=now)["state"] == "verified"
    with pytest.raises(ops.OperationsError):
        ops.verify_backup_set(first, {"ledger": OTHER_KEY}, links, now=now)
    newest = ops.create_backup_set(root, [ops.DatabaseSource("ledger", db, KEY)],
                                   [ops.ArchiveSource("archive", archive)], links, now=now)
    foreign = root / "airag-set-foreign"
    foreign.mkdir()
    (foreign / "manifest.json").write_text(json.dumps({"owner": "someone-else", "state": "verified"}))
    assert ops.prune_backup_sets(root, now=now, newest_verified=newest, restore_in_use=[first]) == []
    assert ops.prune_backup_sets(root, now=now, newest_verified=newest) == [first]
    assert newest.exists() and foreign.exists() and archive.exists() and db.exists()


def test_archive_sqlcipher_snapshot_component(tmp_path, scope):
    root = tmp_path / "backups"
    root.mkdir()
    ledger = tmp_path / "ledger.db"
    archive_key = os.urandom(32)
    make_db(ledger)
    receipt = write_archive(tmp_path / "archives", archive_key, scope, [archive_record(scope)])
    now = datetime(2026, 9, 27, 4, tzinfo=SEOUL)

    def links(paths, current_now):
        assert current_now == now
        assert verify_archive(paths["archive_db"], archive_key, scope).bundle_id == receipt.bundle_id

    backup = ops.create_backup_set(
        root,
        [ops.DatabaseSource("ledger", ledger, KEY),
         ops.DatabaseSource("archive_db", Path(receipt.path), archive_key)],
        [], links, now=now,
    )
    manifest = ops.verify_backup_set(
        backup, {"ledger": KEY, "archive_db": archive_key}, links, now=now,
    )
    assert {item["kind"] for item in manifest["components"]} == {"database"}


def test_failed_or_partial_backup_never_published(tmp_path, monkeypatch):
    root = tmp_path / "backups"
    root.mkdir()
    db = tmp_path / "ledger.db"
    make_db(db)
    now = datetime.now(timezone.utc)
    with pytest.raises(ops.OperationsError):
        ops.create_backup_set(root, [ops.DatabaseSource("ledger", db, OTHER_KEY)], [], lambda _paths, _now: None, now=now)
    assert list(root.iterdir()) == []
    assert not list(root.glob("airag-set-*"))

    def no_space(*_args, **_kwargs):
        raise OSError(errno.ENOSPC, "synthetic disk full")

    monkeypatch.setattr(ops, "_write_json", no_space)
    with pytest.raises(OSError) as exc:
        ops.create_backup_set(root, [ops.DatabaseSource("ledger", db, KEY)], [], lambda _paths, _now: None, now=now)
    assert exc.value.errno == errno.ENOSPC
    assert not list(root.glob("airag-set-*"))


def test_symlinks_and_sources_inside_root_rejected(tmp_path):
    root = tmp_path / "backups"
    root.mkdir()
    db = tmp_path / "ledger.db"
    make_db(db)
    alias = tmp_path / "alias"
    alias.symlink_to(root)
    now = datetime.now(timezone.utc)
    with pytest.raises(ops.OperationsError):
        ops.create_backup_set(alias, [ops.DatabaseSource("ledger", db, KEY)], [], lambda _paths, _now: None, now=now)
    inside = root / "source.db"
    inside.write_bytes(db.read_bytes())
    with pytest.raises(ops.OperationsError):
        ops.create_backup_set(root, [ops.DatabaseSource("ledger", inside, KEY)], [], lambda _paths, _now: None, now=now)


def test_link_failure_leaves_only_unverified_staging(tmp_path):
    root = tmp_path / "backups"
    root.mkdir()
    db = tmp_path / "ledger.db"
    make_db(db)
    now = datetime(2026, 9, 27, 4, tzinfo=SEOUL)

    def rejected_reconciliation(_paths, _now):
        raise ops.OperationsError("RESTORE_RECONCILIATION_FAILED")

    with pytest.raises(ops.OperationsError, match="RESTORE_RECONCILIATION_FAILED"):
        ops.create_backup_set(root, [ops.DatabaseSource("ledger", db, KEY)], [],
                              rejected_reconciliation, now=now)
    assert not list(root.glob("airag-set-*"))
    stages = list(root.glob(".airag-stage-*"))
    assert len(stages) == 1
    assert json.loads((stages[0] / "manifest.json").read_text())["state"] == "staging"


def test_restore_hook_receives_current_time_without_opening_read_gate(tmp_path):
    root = tmp_path / "backups"
    root.mkdir()
    db = tmp_path / "ledger.db"
    created_at = datetime(2026, 5, 1, tzinfo=timezone.utc)
    make_db(db, created_at=created_at)
    backup_now = datetime(2026, 5, 2, 3, tzinfo=SEOUL)
    gate = {"open": False}

    def initial_check(_paths, current_now):
        assert current_now == backup_now
        assert gate["open"] is False

    backup = ops.create_backup_set(root, [ops.DatabaseSource("ledger", db, KEY)], [],
                                   initial_check, now=backup_now)
    restore_now = datetime(2026, 9, 27, 4, tzinfo=SEOUL)
    reconciliation = []

    def current_reconciliation(paths, current_now):
        assert current_now == restore_now
        assert gate["open"] is False
        con = ops._connect(paths["ledger"], KEY, True)
        try:
            restored_created_at = datetime.fromisoformat(
                con.execute("SELECT created_at FROM records").fetchone()[0])
        finally:
            con.close()
        reconciliation.append(restored_created_at < current_now - timedelta(days=90))

    ops.verify_backup_set(backup, {"ledger": KEY}, current_reconciliation, now=restore_now)
    assert reconciliation == [True]
    assert gate["open"] is False
