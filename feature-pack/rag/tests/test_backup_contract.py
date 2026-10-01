"""Independent encrypted snapshot/restore checks; all databases are test-owned."""
from __future__ import annotations

import hashlib
import json
import os
import struct
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

from airag import api, embeddings, keys, search, store
from airag.db import connect
from test_operations_contract import operational_db


def _digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _search(con, space, profile):
    return search.search(con, search.SearchQuery("docs", "PRIVATE", "PRIVATE",
                         struct.pack("4f", 1, 0, 0, 0), space, profile))


def test_backup_restore_rotated_key_retains_original_manifest_and_jobs(operational_db, tmp_path):
    con, path, key, space, profile, ready = operational_db
    found = _search(con, space, profile)
    pending = api.add(con, "pending", "docs", "pending", b"PENDING_PRIVATE_227")
    assert pending["ok"]
    snapshot_counts = {table: con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                       for table in ("sources", "source_revisions", "generations", "jobs", "search_manifests")}
    backup = tmp_path / "backup?#%.db"
    backup_key = keys.generate_key()
    result = api.backup_database(path, backup, key, destination_key_bytes=backup_key)
    assert result["ok"], result
    assert backup.read_bytes()[:16] != b"SQLite format 3\x00"
    assert b"PRIVATE_ORIGINAL_9382" not in backup.read_bytes()
    assert backup.stat().st_mode & 0o777 == 0o600
    with pytest.raises(connect.WrongKeyOrForeignDatabase):
        connect.open_readonly(backup, key)
    later = api.add(con, "later", "docs", "later", b"NOT_IN_BACKUP_668")
    assert later["ok"]
    restored = tmp_path / "restored.db"
    restored_key = keys.generate_key()
    response = api.restore_backup(backup, restored, backup_key, destination_key_bytes=restored_key)
    assert response["ok"], response
    recovered = connect.open_encrypted(restored, restored_key)
    try:
        for table, count in snapshot_counts.items():
            assert recovered.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] == count
        assert api.fetch_manifest(recovered, found["manifest_id"])["data"]["results"] == found["results"]
        assert _search(recovered, space, profile)["results"][0]["generation_id"] == ready["generation_id"]
        original = store.fetch_original(recovered, "docs", "private-source", include_bytes=True)
        assert original["content_hash"] == hashlib.sha256(b"PRIVATE_ORIGINAL_9382").hexdigest()
        with patch("airag.embeddings.embed_documents", return_value=[struct.pack("4f", 1, 0, 0, 0)]):
            processed = api.retry(recovered, "resume-pending", pending["data"]["job_id"], profile_key=profile)
        assert processed["ok"], processed
        assert api.verify(recovered)["ok"]
    finally:
        recovered.close()


@pytest.mark.parametrize("mode", ["backup", "restore"])
def test_existing_destination_is_never_overwritten(operational_db, tmp_path, mode):
    _, path, key, _, _, _ = operational_db
    target = tmp_path / "already-exists.db"
    target.write_bytes(b"USER_OWNED_EXISTING_DATA")
    before = _digest(target)
    method = api.backup_database if mode == "backup" else api.restore_backup
    result = method(path, target, key)
    assert not result["ok"], result
    assert _digest(target) == before


@pytest.mark.parametrize("mode", ["backup", "restore"])
def test_same_path_and_symlink_do_not_modify_source(operational_db, tmp_path, mode):
    con, path, key, _, _, _ = operational_db
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    before = _digest(path)
    method = api.backup_database if mode == "backup" else api.restore_backup
    assert not method(path, path, key)["ok"]
    alias = tmp_path / "alias.db"
    alias.symlink_to(path)
    assert not method(path, alias, key)["ok"]
    assert alias.is_symlink() and _digest(path) == before


def test_wrong_key_and_corrupt_snapshot_do_not_publish_destination(operational_db, tmp_path):
    _, path, key, _, _, _ = operational_db
    target = tmp_path / "wrong-key-result.db"
    result = api.restore_backup(path, target, keys.generate_key())
    assert not result["ok"] and not target.exists(), result
    bad = tmp_path / "corrupt.db"
    bad.write_bytes(b"CORRUPT_SYNTHETIC_TEST_INPUT")
    target = tmp_path / "corrupt-result.db"
    result = api.restore_backup(bad, target, key)
    assert not result["ok"] and not target.exists(), result


def test_corrupt_index_backup_does_not_publish_an_apparently_valid_snapshot(operational_db, tmp_path):
    con, path, key, _, _, _ = operational_db
    con.execute("DELETE FROM fts_chunks")
    con.commit()
    target = tmp_path / "inconsistent-snapshot.db"
    result = api.backup_database(path, target, key)
    assert not result["ok"], result
    assert not target.exists()


def test_installed_cli_backup_restore_with_key_fds(operational_db, tmp_path):
    _, path, key, _, _, _ = operational_db
    cli = str(Path(sys.executable).with_name("ai-rag"))
    backup, restored = tmp_path / "cli-backup.db", tmp_path / "cli-restored.db"
    for args in (("backup", "--db", str(path), "--output", str(backup)),
                 ("restore-backup", "--backup", str(backup), "--db", str(restored))):
        r, w = os.pipe()
        os.write(w, key)
        os.close(w)
        try:
            p = subprocess.run([cli, "manage", *args, "--key-fd", str(r)], pass_fds=(r,),
                               cwd=tmp_path, capture_output=True, text=True, timeout=30)
        finally:
            os.close(r)
        result = json.loads(p.stdout)
        assert p.returncode == 0 and result["ok"], result
        assert key.hex() not in p.stdout + p.stderr
        assert "PRIVATE_ORIGINAL_9382" not in p.stdout + p.stderr
    recovered = connect.open_readonly(restored, key)
    try:
        assert api.verify(recovered)["ok"]
    finally:
        recovered.close()
