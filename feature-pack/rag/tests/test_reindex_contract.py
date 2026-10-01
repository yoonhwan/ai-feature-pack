"""Independent reindex checks: publication, space isolation, and durable replay."""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path
from unittest.mock import patch

import pytest

from airag import api, embeddings, store
from airag.db import connect
from test_cli_processing import provider


def _register(con, revision, dimension=4, endpoint="http://localhost:9999/v1"):
    config = embeddings.EmbeddingSpaceConfig(
        "openai-compatible", endpoint, "fixture-embed", revision, dimension,
        tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3",
    )
    result = api.register_profile(con, {"embedding": asdict(config)})
    assert result["ok"], result
    return result["data"]["profile_key"]


def _vector(config):
    return struct.pack(f"{config.dimension}f", 1, *([0] * (config.dimension - 1)))


def _vectors(config, texts, **_kwargs):
    return [_vector(config) for _ in texts]


def _search(con, profile):
    with patch("airag.embeddings.embed_query", side_effect=lambda config, _text: _vector(config)):
        result = api.search(con, "docs", "original", profile)
    assert result["ok"], result
    return result["data"]


def _row_counts(con):
    return tuple(con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                 for table in ("jobs", "generations", "source_revisions", "request_ledger"))


@pytest.fixture
def reindex_db(tmp_path, key_bytes):
    path = tmp_path / "reindex-contract.db"
    con = connect.init_db(path, key_bytes)
    old_profile = _register(con, "old-revision")
    new_profile = _register(con, "new-revision", 6)
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        added = api.add(con, "original-add", "docs", "source", b"original input",
                        origin_uri="fixture://original", profile_key=old_profile)
    assert added["ok"], added
    yield con, old_profile, new_profile, added, path, key_bytes
    con.close()


def test_profile_switch_keeps_old_search_until_publish_and_preserves_history(reindex_db):
    con, old_profile, new_profile, added, path, key = reindex_db
    original_rows = con.execute("SELECT * FROM source_revisions").fetchall()
    identity = con.execute("SELECT source_key, origin_uri, media_type, head_revision_id FROM sources").fetchall()
    old_manifest = _search(con, old_profile)
    assert old_manifest["results"][0]["generation_id"] == added["data"]["generation_id"]
    observer = connect.open_encrypted(path, key)
    observations = []

    def during_processing(config, texts, **kwargs):
        state = api.status(observer, "docs", "source")["data"]
        observations.append(state)
        assert state["ready_generation_id"] == added["data"]["generation_id"]
        assert state["revision_token"] == added["data"]["revision_token"]
        assert _search(observer, old_profile)["results"] == old_manifest["results"]
        return _vectors(config, texts, **kwargs)

    try:
        with patch("airag.embeddings.embed_documents", side_effect=during_processing):
            result = api.reindex(con, "switch", "docs", "source", added["data"]["revision_token"],
                                 profile_key=new_profile)
    finally:
        observer.close()
    assert result["ok"], result
    assert observations
    assert result["data"]["revision_id"] == added["data"]["revision_id"]
    assert result["data"]["generation_id"] != added["data"]["generation_id"]
    assert con.execute("SELECT * FROM source_revisions").fetchall() == original_rows
    assert con.execute("SELECT source_key, origin_uri, media_type, head_revision_id FROM sources").fetchall() == identity
    assert _search(con, old_profile)["results"] == []
    fresh = _search(con, new_profile)
    assert fresh["results"][0]["generation_id"] == result["data"]["generation_id"]
    replay = api.fetch_manifest(con, old_manifest["manifest_id"])
    assert replay["ok"] and replay["data"]["results"] == old_manifest["results"]
    old_artifact = api.fetch_artifact(con, "docs", "source", generation_id=added["data"]["generation_id"])
    assert old_artifact["ok"] and "original input" in old_artifact["data"]["standard_md"]
    for profile, expected_active in ((old_profile, 0), (new_profile, 1)):
        space = con.execute("SELECT space_id FROM processing_profiles WHERE profile_key = ?", (profile,)).fetchone()[0]
        table = embeddings.vec_space_table_name(space)
        assert con.execute(f"SELECT COUNT(*) FROM {table} WHERE active = 1").fetchone() == (expected_active,)


def test_reindex_failure_keeps_old_index_and_retry_preserves_failed_response(reindex_db):
    con, old_profile, new_profile, added, _, _ = reindex_db
    token = added["data"]["revision_token"]
    before = _search(con, old_profile)
    with patch("airag.embeddings.embed_documents", side_effect=embeddings.EmbeddingError(
        "PROVIDER_UNREACHABLE", "synthetic reindex failure", retryable=True,
    )):
        failed = api.reindex(con, "failed-switch", "docs", "source", token, profile_key=new_profile)
    assert failed["error"]["code"] == "PROVIDER_UNREACHABLE"
    assert api.status(con, "docs", "source")["data"]["ready_generation_id"] == added["data"]["generation_id"]
    assert _search(con, old_profile)["results"] == before["results"]
    job = api.status(con, "docs", "source")["data"]["latest_job"]
    assert job["status"] == "failed" and job["profile_key"] == new_profile
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        recovered = api.retry(con, "retry-failed-switch", job["job_id"])
    assert recovered["ok"], recovered
    with patch("airag.embeddings.embed_documents") as provider_call:
        assert api.reindex(con, "failed-switch", "docs", "source", token, profile_key=new_profile) == failed
        provider_call.assert_not_called()
    assert _search(con, old_profile)["results"] == []
    assert _search(con, new_profile)["results"][0]["generation_id"] == recovered["data"]["generation_id"]


def test_completed_reindex_replays_after_reopen_and_new_source_revision(reindex_db):
    con, old_profile, new_profile, added, path, key = reindex_db
    token = added["data"]["revision_token"]
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        result = api.reindex(con, "reindex", "docs", "source", token, profile_key=new_profile)
        assert result["ok"], result
        changed = api.update(con, "later-update", "docs", "source", result["data"]["revision_token"],
                             b"newer input", profile_key=old_profile)
        assert changed["ok"], changed
    reopened = connect.open_encrypted(path, key)
    try:
        before = _row_counts(reopened)
        with patch("airag.embeddings.embed_documents") as provider_call:
            assert api.reindex(reopened, "reindex", "docs", "source", token, profile_key=new_profile) == result
            assert api.add(reopened, "original-add", "docs", "source", b"original input",
                           origin_uri="fixture://original", profile_key=old_profile) == added
            provider_call.assert_not_called()
        assert _row_counts(reopened) == before
    finally:
        reopened.close()


def test_same_profile_reindex_creates_a_generation_without_copying_original(reindex_db):
    con, old_profile, _, added, _, _ = reindex_db
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        result = api.reindex(con, "same-profile", "docs", "source", added["data"]["revision_token"],
                             profile_key=old_profile)
    assert result["ok"], result
    assert result["data"]["generation_id"] != added["data"]["generation_id"]
    assert result["data"]["revision_id"] == added["data"]["revision_id"]
    assert con.execute("SELECT COUNT(*) FROM source_revisions").fetchone() == (1,)


@pytest.mark.parametrize("changed_field", ["profile", "token", "collection", "source"])
def test_reindex_request_fingerprint_is_checked_before_current_source_state(reindex_db, changed_field):
    con, old_profile, new_profile, added, _, _ = reindex_db
    token = added["data"]["revision_token"]
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        result = api.reindex(con, "fixed-request", "docs", "source", token, profile_key=new_profile)
    assert result["ok"], result
    args = {"collection": "docs", "source_key": "source", "expected_revision": token, "profile_key": new_profile}
    if changed_field == "profile":
        args["profile_key"] = old_profile
    elif changed_field == "token":
        args["expected_revision"] = result["data"]["revision_token"]
    elif changed_field == "collection":
        args["collection"] = "other-collection"
    else:
        args["source_key"] = "other-source"
    before = _row_counts(con)
    conflict = api.reindex(con, "fixed-request", **args)
    assert conflict["error"]["code"] == "IDEMPOTENCY_MISMATCH"
    assert _row_counts(con) == before


@pytest.mark.parametrize("change", ["delete", "restore", "update"])
def test_reindex_stale_token_never_claims_or_calls_provider(reindex_db, change):
    con, old_profile, new_profile, added, _, _ = reindex_db
    token = added["data"]["revision_token"]
    if change == "update":
        changed = api.update(con, "changed", "docs", "source", token, b"newer input")
        assert changed["ok"], changed
    else:
        deleted = store.delete(con, store.DeleteRequest("delete", "docs", "source", token))
        if change == "restore":
            store.restore(con, store.RestoreRequest("restore", "docs", "source", deleted["revision_token"]))
    before = _row_counts(con)
    with patch("airag.embeddings.embed_documents") as provider_call:
        result = api.reindex(con, "stale", "docs", "source", token, profile_key=new_profile)
        assert not result["ok"], result
        assert result["error"]["code"] in {"ALREADY_DELETED", "CONFLICT_STALE_REVISION"}
        provider_call.assert_not_called()
    assert _row_counts(con) == before


@pytest.mark.parametrize("profile", [None, "", True, "missing-profile"])
def test_reindex_invalid_profile_never_leaves_a_running_job(reindex_db, profile):
    con, _, _, added, _, _ = reindex_db
    before = _row_counts(con)
    with patch("airag.embeddings.embed_documents") as provider_call:
        result = api.reindex(con, "invalid-profile", "docs", "source", added["data"]["revision_token"],
                             profile_key=profile)
        assert not result["ok"], result
        provider_call.assert_not_called()
    assert _row_counts(con) == before


def test_same_request_from_another_connection_has_one_processing_claim(reindex_db):
    con, _, new_profile, added, path, key = reindex_db
    observer = connect.open_encrypted(path, key)
    token = added["data"]["revision_token"]

    def during_processing(config, texts, **kwargs):
        with patch("airag.embeddings.embed_documents", side_effect=_vectors) as duplicate:
            competing = api.reindex(observer, "one-request", "docs", "source", token, profile_key=new_profile)
        assert competing["error"]["code"] == "IN_PROGRESS"
        duplicate.assert_not_called()
        return _vectors(config, texts, **kwargs)

    try:
        with patch("airag.embeddings.embed_documents", side_effect=during_processing) as processing:
            result = api.reindex(con, "one-request", "docs", "source", token, profile_key=new_profile)
        assert result["ok"], result
        processing.assert_called_once()
        assert con.execute("SELECT COUNT(*) FROM jobs").fetchone() == (2,)
    finally:
        observer.close()


def test_reindex_resumes_captured_attempt_after_restart(reindex_db):
    con, _, new_profile, added, path, key = reindex_db
    token = added["data"]["revision_token"]
    claimed = store.reindex(con, "crashed-reindex", "docs", "source", token,
                            profile_key=new_profile, lease_owner="crashed-worker")
    con.execute("UPDATE jobs SET lease_expires_at_ms = 0 WHERE job_id = ?", (claimed["job_id"],))
    con.commit()
    reopened = connect.open_encrypted(path, key)
    try:
        with patch("airag.embeddings.embed_documents", side_effect=_vectors) as processing:
            result = api.reindex(reopened, "crashed-reindex", "docs", "source", token, profile_key=new_profile)
        assert result["ok"], result
        processing.assert_called_once()
        assert result["data"]["generation_id"] != claimed["generation_id"]
        with pytest.raises(store.ApiError) as exc:
            store.fail_generation(con, claimed["generation_id"], "late obsolete worker")
        assert exc.value.code == "STALE_CLAIM_FENCED"
        assert con.execute("SELECT COUNT(*) FROM jobs").fetchone() == (2,)
        assert con.execute("SELECT COUNT(*) FROM source_revisions").fetchone() == (1,)
    finally:
        reopened.close()


def test_concurrent_update_wins_without_reindex_overwriting_its_publication(reindex_db):
    con, old_profile, new_profile, added, path, key = reindex_db
    writer = connect.open_encrypted(path, key)
    token = added["data"]["revision_token"]
    changed = []

    def during_processing(config, texts, **kwargs):
        with patch("airag.embeddings.embed_documents", side_effect=_vectors):
            update = api.update(writer, "concurrent-update", "docs", "source", token,
                                b"concurrent new input", profile_key=old_profile)
        assert update["ok"], update
        changed.append(update)
        return _vectors(config, texts, **kwargs)

    try:
        with patch("airag.embeddings.embed_documents", side_effect=during_processing):
            result = api.reindex(con, "losing-reindex", "docs", "source", token, profile_key=new_profile)
        assert not result["ok"], result
        assert result["error"]["code"] in {"STALE_REVISION", "CONFLICT_STALE_REVISION"}
        assert api.status(con, "docs", "source")["data"]["ready_generation_id"] == changed[0]["data"]["generation_id"]
        assert _search(con, new_profile)["results"] == []
    finally:
        writer.close()


def test_installed_cli_switches_profile_and_replays_after_later_update(tmp_path, key_bytes, provider):
    cli = str(Path(sys.executable).with_name("ai-rag"))
    db_path = tmp_path / "cli-reindex.db"

    def call(*args):
        read_fd, write_fd = os.pipe()
        os.write(write_fd, key_bytes)
        os.close(write_fd)
        try:
            result = subprocess.run(
                [cli, *args, "--key-fd", str(read_fd)], pass_fds=(read_fd,),
                cwd=tmp_path, capture_output=True, text=True, timeout=30,
            )
        finally:
            os.close(read_fd)
        assert result.stdout, result.stderr
        response = json.loads(result.stdout)
        assert result.returncode == 0 and response["ok"], response
        return response

    call("init", str(db_path))
    con = connect.open_encrypted(db_path, key_bytes)
    try:
        old_profile = _register(con, "cli-old-revision", endpoint=provider)
        new_profile = _register(con, "cli-new-revision", endpoint=provider)
        original_args = ("add", "--db", str(db_path), "--collection", "docs", "--source-key", "source",
                         "--text", "original input", "--profile-key", old_profile, "--request-id", "cli-add")
        added = call(*original_args)
        search_args = ("search", "--db", str(db_path), "--collection", "docs", "--query", "original")
        old_search = call(*search_args, "--profile-key", old_profile)["data"]
        reindex_args = ("manage", "reindex", "--db", str(db_path), "--collection", "docs", "--source-key", "source",
                        "--expected-revision", added["data"]["revision_token"], "--profile-key", new_profile,
                        "--request-id", "cli-reindex")
        reindexed = call(*reindex_args)
        assert reindexed["data"]["generation_id"] != added["data"]["generation_id"]
        assert reindexed["data"]["revision_id"] == added["data"]["revision_id"]
        assert call(*reindex_args) == reindexed
        status = call("manage", "status", "--db", str(db_path), "--collection", "docs", "--source-key", "source")
        assert status["data"]["latest_job"]["profile_key"] == new_profile
        assert call(*search_args, "--profile-key", old_profile)["data"]["results"] == []
        assert call(*search_args, "--profile-key", new_profile)["data"]["results"][0]["generation_id"] == reindexed["data"]["generation_id"]
        historical = call("fetch", "manifest", "--db", str(db_path), "--manifest-id", str(old_search["manifest_id"]))
        assert historical["data"]["results"] == old_search["results"]
        call("update", "--db", str(db_path), "--collection", "docs", "--source-key", "source",
             "--expected-revision", reindexed["data"]["revision_token"], "--text", "newer input",
             "--profile-key", old_profile, "--request-id", "cli-later-update")
        assert call(*reindex_args) == reindexed
        assert call(*original_args) == added
        assert con.execute("SELECT COUNT(*) FROM source_revisions").fetchone() == (2,)
    finally:
        con.close()


@pytest.mark.parametrize("job_status", ["pending", "running"])
def test_obsolete_job_does_not_block_reindex_with_a_fresh_source_token(reindex_db, job_status):
    con, old_profile, new_profile, added, _, _ = reindex_db
    token = added["data"]["revision_token"]
    if job_status == "running":
        old_job = store.reindex(con, "abandoned-reindex", "docs", "source", token,
                                profile_key=old_profile, lease_owner="abandoned-worker")
    else:
        old_job = store.update(con, store.UpdateRequest(
            "abandoned-pending", "docs", "source", token, b"original input", force_reprocess=True,
        ))
    old_snapshot = con.execute("SELECT * FROM jobs WHERE job_id = ?", (old_job["job_id"],)).fetchone()
    changed = api.update(con, "metadata-only", "docs", "source", token, b"original input",
                         origin_uri="fixture://changed-metadata")
    assert changed["ok"], changed
    fresh_token = changed["data"]["revision_token"]
    assert fresh_token != token
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        reindexed = api.reindex(con, "fresh-reindex", "docs", "source", fresh_token, profile_key=new_profile)
    assert reindexed["ok"], reindexed
    assert con.execute("SELECT * FROM jobs WHERE job_id = ?", (old_job["job_id"],)).fetchone() == old_snapshot
    assert con.execute("SELECT COUNT(*) FROM source_revisions").fetchone() == (1,)
    assert _search(con, new_profile)["results"][0]["generation_id"] == reindexed["data"]["generation_id"]


def test_distinct_request_cannot_duplicate_an_attempt_for_the_current_source_state(reindex_db):
    con, old_profile, new_profile, added, _, _ = reindex_db
    token = added["data"]["revision_token"]
    store.reindex(con, "active-reindex", "docs", "source", token,
                  profile_key=old_profile, lease_owner="active-worker")
    before = _row_counts(con)
    with patch("airag.embeddings.embed_documents") as provider_call:
        result = api.reindex(con, "competing-reindex", "docs", "source", token, profile_key=new_profile)
        assert result["error"]["code"] == "IN_PROGRESS"
        provider_call.assert_not_called()
    assert _row_counts(con) == before


def test_failed_fresh_reindex_can_be_retried_despite_an_obsolete_pending_job(reindex_db):
    con, old_profile, new_profile, added, _, _ = reindex_db
    token = added["data"]["revision_token"]
    obsolete = store.update(con, store.UpdateRequest(
        "obsolete-pending", "docs", "source", token, b"original input", force_reprocess=True,
    ))
    old_snapshot = con.execute("SELECT * FROM jobs WHERE job_id = ?", (obsolete["job_id"],)).fetchone()
    changed = api.update(con, "metadata-change", "docs", "source", token, b"original input",
                         origin_uri="fixture://changed-metadata")
    assert changed["ok"], changed
    fresh_token = changed["data"]["revision_token"]
    with patch("airag.embeddings.embed_documents", side_effect=embeddings.EmbeddingError(
        "PROVIDER_UNREACHABLE", "synthetic failure after source changed", retryable=True,
    )):
        failed = api.reindex(con, "fresh-reindex", "docs", "source", fresh_token, profile_key=new_profile)
    assert failed["error"]["code"] == "PROVIDER_UNREACHABLE"
    current_job = api.status(con, "docs", "source")["data"]["latest_job"]
    assert current_job["status"] == "failed"
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        retried = api.retry(con, "retry-fresh-reindex", current_job["job_id"])
    assert retried["ok"], retried
    assert con.execute("SELECT * FROM jobs WHERE job_id = ?", (obsolete["job_id"],)).fetchone() == old_snapshot
    assert _search(con, old_profile)["results"] == []
    assert _search(con, new_profile)["results"][0]["generation_id"] == retried["data"]["generation_id"]
