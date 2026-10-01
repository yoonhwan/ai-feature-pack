from __future__ import annotations

import json
import os
import sqlite3
import struct
from dataclasses import asdict
from unittest.mock import patch

import pytest

from airag import api, backups, embeddings, keys
from airag.db import connect


@pytest.fixture
def backup_source(tmp_path, key_bytes):
    path = tmp_path / "source.db"
    con = connect.init_db(path, key_bytes)
    cfg = embeddings.EmbeddingSpaceConfig("openai-compatible", "http://localhost:9999/v1", "fixture", "rev", 4,
                                           tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3")
    profile = api.register_profile(con, {"embedding": asdict(cfg)})["data"]["profile_key"]
    with patch("airag.embeddings.embed_documents", side_effect=lambda cfg, texts, **kw: [struct.pack("4f", 1, 0, 0, 0) for _ in texts]):
        added = api.add(con, "original", "docs", "source", b"SECRET original input", profile_key=profile)
    assert added["ok"], added
    with patch("airag.embeddings.embed_query", return_value=struct.pack("4f", 1, 0, 0, 0)):
        manifest = api.search(con, "docs", "input", profile)
    assert manifest["ok"], manifest
    pending = api.add(con, "pending", "docs", "pending", b"pending original")
    assert pending["ok"], pending
    yield con, path, key_bytes, profile, added, manifest
    con.close()


def test_rekey_backup_restore_keeps_original_search_manifest_and_jobs(backup_source, tmp_path):
    con, path, key, profile, added, manifest = backup_source
    backup_key, restored_key = keys.generate_key(), keys.generate_key()
    backup_path = tmp_path / "backup ?#%.db"
    restored_path = tmp_path / "restored ?#%.db"
    backed = api.backup_database(path, backup_path, key, destination_key_bytes=backup_key, request_id="backup")
    assert backed["ok"], backed
    assert backed["request_id"] == "backup"
    result = api.restore_backup(backup_path, restored_path, backup_key, destination_key_bytes=restored_key)
    assert result["ok"], result
    restored = connect.open_encrypted(restored_path, restored_key)
    try:
        assert api.fetch_original(restored, "docs", "source", include_bytes=True)["data"] == api.fetch_original(con, "docs", "source", include_bytes=True)["data"]
        assert api.fetch_manifest(restored, manifest["data"]["manifest_id"])["data"] == api.fetch_manifest(con, manifest["data"]["manifest_id"])["data"]
        assert restored.execute("SELECT * FROM jobs").fetchall() == con.execute("SELECT * FROM jobs").fetchall()
        with patch("airag.embeddings.embed_query", return_value=struct.pack("4f", 1, 0, 0, 0)):
            searched = api.search(restored, "docs", "input", profile)
        assert searched["ok"] and searched["data"]["results"] == manifest["data"]["results"]
    finally:
        restored.close()
    assert backup_path.stat().st_mode & 0o777 == 0o600
    assert not list(tmp_path.glob(".airag-snapshot-*"))
    for artifact in (backup_path, restored_path):
        assert b"SECRET original input" not in artifact.read_bytes()
        plaintext = sqlite3.connect(artifact)
        try:
            with pytest.raises(sqlite3.DatabaseError):
                plaintext.execute("SELECT * FROM sqlite_master").fetchall()
        finally:
            plaintext.close()
    assert key.hex() not in json.dumps(backed) and backup_key.hex() not in json.dumps(backed)


@pytest.mark.parametrize("kind", ["existing", "same", "source_symlink", "target_symlink"])
def test_snapshot_refuses_existing_or_aliased_paths_without_modifying_them(backup_source, tmp_path, kind):
    con, path, key, profile, added, manifest = backup_source
    target = tmp_path / "target.db"
    source = path
    if kind == "existing":
        target.write_text("existing user file", encoding="utf-8")
    elif kind == "same":
        target = path
    elif kind == "source_symlink":
        source = tmp_path / "source-link"
        source.symlink_to(path)
    else:
        target.symlink_to(path)
    original = path.read_bytes()
    result = api.backup_database(source, target, key)
    assert not result["ok"]
    assert path.read_bytes() == original
    if kind == "existing":
        assert target.read_text() == "existing user file"
    assert not list(tmp_path.glob(".airag-snapshot-*"))


def test_wrong_key_and_logical_corruption_never_publish_destination(backup_source, tmp_path):
    con, path, key, profile, added, manifest = backup_source
    target = tmp_path / "wrong-key.db"
    result = api.restore_backup(path, target, keys.generate_key())
    assert not result["ok"] and not target.exists()
    con.execute("UPDATE source_revisions SET content_hash='invalid'")
    result = api.backup_database(path, target, key)
    assert not result["ok"] and not target.exists()


def test_verification_failure_retains_only_partial_and_redacts_error(backup_source, tmp_path):
    con, path, key, profile, added, manifest = backup_source
    target = tmp_path / "failed.db"
    real_verify = backups._verified_counts
    calls = 0

    def fail_destination(connection):
        nonlocal calls
        calls += 1
        if calls == 2:
            raise RuntimeError("PROVIDER_KEY_OR_SOURCE_SECRET")
        return real_verify(connection)

    with patch("airag.backups._verified_counts", side_effect=fail_destination):
        result = api.backup_database(path, target, key)
    assert not result["ok"] and not target.exists()
    assert "PROVIDER_KEY_OR_SOURCE_SECRET" not in json.dumps(result)
    assert len(list(tmp_path.glob(".airag-snapshot-*"))) == 1
    assert "retained" in result["error"]["message"]


def test_atomic_publish_does_not_replace_concurrent_destination(backup_source, tmp_path):
    con, path, key, profile, added, manifest = backup_source
    target = tmp_path / "raced.db"
    real_link = os.link

    def raced_link(source, destination, **kwargs):
        target.write_text("concurrent user file", encoding="utf-8")
        return real_link(source, destination, **kwargs)

    with patch("airag.backups.os.link", side_effect=raced_link):
        result = api.backup_database(path, target, key)
    assert not result["ok"]
    assert target.read_text() == "concurrent user file"
    assert result["error"]["code"] == "DESTINATION_EXISTS"


def test_snapshot_stays_consistent_when_writer_changes_source(backup_source, tmp_path):
    con, path, key, profile, added, manifest = backup_source
    target = tmp_path / "snapshot.db"
    real_verify = backups._verified_counts
    calls = 0

    def concurrent_change(connection):
        nonlocal calls
        calls += 1
        counts = real_verify(connection)
        if calls == 1:
            assert api.add(con, "concurrent", "docs", "new", b"new after snapshot")["ok"]
        return counts

    with patch("airag.backups._verified_counts", side_effect=concurrent_change):
        result = api.backup_database(path, target, key)
    assert result["ok"], result
    restored = connect.open_readonly(target, key)
    try:
        assert restored.execute("SELECT COUNT(*) FROM sources").fetchone() == (2,)
        assert con.execute("SELECT COUNT(*) FROM sources").fetchone() == (3,)
    finally:
        restored.close()
