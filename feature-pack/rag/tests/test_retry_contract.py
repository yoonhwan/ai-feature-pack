"""Independent retry contract checks using SQLCipher and synthetic vectors."""
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


@pytest.fixture
def retry_db(tmp_path, key_bytes):
    path = tmp_path / "retry-contract.db"
    con = connect.init_db(path, key_bytes)
    config = embeddings.EmbeddingSpaceConfig(
        "openai-compatible", "http://localhost:9999/v1", "fixture-embed",
        "fixture-revision", 4,
        tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3",
    )
    registered = api.register_profile(con, {"embedding": asdict(config)})
    assert registered["ok"], registered
    yield con, registered["data"]["profile_key"], path, key_bytes
    con.close()


def _vectors(_config, texts, **_kwargs):
    return [struct.pack("4f", 1, 0, 0, 0) for _ in texts]


def _failed_add(con, profile):
    with patch("airag.embeddings.embed_documents", side_effect=embeddings.EmbeddingError(
        "PROVIDER_UNREACHABLE", "synthetic failure", retryable=True,
    )):
        failed = api.add(con, "original-add", "docs", "source", b"original input", profile_key=profile)
    assert failed["error"]["code"] == "PROVIDER_UNREACHABLE"
    job = con.execute("SELECT job_id FROM jobs WHERE status = 'failed'").fetchone()[0]
    return failed, job


def _job_snapshot(con, job_id):
    return con.execute("SELECT * FROM jobs WHERE job_id = ?", (job_id,)).fetchone()


def test_failed_original_and_retry_response_survive_reopen_and_later_update(retry_db):
    con, profile, path, key = retry_db
    original, job = _failed_add(con, profile)
    snapshot = _job_snapshot(con, job)
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        retried = api.retry(con, "retry-a", job)
        assert retried["ok"], retried
        changed = api.update(con, "later-update", "docs", "source",
                             retried["data"]["revision_token"], b"later input", profile_key=profile)
        assert changed["ok"], changed
    assert _job_snapshot(con, job) == snapshot
    reopened = connect.open_encrypted(path, key)
    try:
        with patch("airag.embeddings.embed_documents") as provider:
            assert api.add(reopened, "original-add", "docs", "source", b"original input",
                           profile_key=profile) == original
            assert api.retry(reopened, "retry-a", job) == retried
            provider.assert_not_called()
        assert _job_snapshot(reopened, job) == snapshot
    finally:
        reopened.close()


def test_pending_receipt_stays_stored_only_after_retry(retry_db):
    con, profile, path, key = retry_db
    original = api.add(con, "stored", "docs", "source", b"stored input")
    original_replay = api.add(con, "stored", "docs", "source", b"stored input")
    job = original["data"]["job_id"]
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        result = api.retry(con, "process-stored", job, profile_key=profile)
    assert result["ok"], result
    reopened = connect.open_encrypted(path, key)
    try:
        with patch("airag.embeddings.embed_documents") as provider:
            assert api.add(reopened, "stored", "docs", "source", b"stored input") == original_replay
            assert api.retry(reopened, "process-stored", job, profile_key=profile) == result
            provider.assert_not_called()
    finally:
        reopened.close()


@pytest.mark.parametrize("failed", [False, True])
def test_retry_refuses_source_changed_by_delete_restore(retry_db, failed):
    con, profile, _, _ = retry_db
    if failed:
        _, job = _failed_add(con, profile)
    else:
        job = api.add(con, "stored", "docs", "source", b"stored input")["data"]["job_id"]
    before = _job_snapshot(con, job)
    token = api.status(con, "docs", "source")["data"]["revision_token"]
    deleted = store.delete(con, store.DeleteRequest("delete", "docs", "source", token))
    store.restore(con, store.RestoreRequest("restore", "docs", "source", deleted["revision_token"]))
    with patch("airag.embeddings.embed_documents") as provider:
        result = api.retry(con, "stale-retry", job, profile_key=profile)
        assert not result["ok"], result
        assert result["error"]["code"] == "CONFLICT_STALE_REVISION"
        provider.assert_not_called()
    assert _job_snapshot(con, job) == before
    assert con.execute("SELECT COUNT(*) FROM request_ledger WHERE request_id = 'stale-retry'").fetchone() == (0,)


def test_new_request_cannot_republish_old_failed_job_after_success(retry_db):
    con, profile, _, _ = retry_db
    _, job = _failed_add(con, profile)
    with patch("airag.embeddings.embed_documents", side_effect=_vectors) as provider:
        first = api.retry(con, "first-retry", job)
        assert first["ok"], first
        second = api.retry(con, "second-retry", job)
        assert not second["ok"], second
        assert second["error"]["code"] == "CONFLICT_STALE_REVISION"
        provider.assert_called_once()
    assert con.execute("SELECT COUNT(*) FROM generations WHERE status = 'ready'").fetchone() == (1,)


def test_distinct_request_ids_do_not_claim_same_failed_input_concurrently(retry_db):
    con, profile, path, key = retry_db
    _, job = _failed_add(con, profile)
    other = connect.open_encrypted(path, key)
    competing = []

    def during_provider(config, texts, **kwargs):
        with patch("airag.embeddings.embed_documents", side_effect=_vectors) as duplicate_provider:
            result = api.retry(other, "competing-retry", job)
        competing.append(result)
        assert not result["ok"], result
        assert result["error"]["code"] == "IN_PROGRESS"
        duplicate_provider.assert_not_called()
        return _vectors(config, texts, **kwargs)

    try:
        with patch("airag.embeddings.embed_documents", side_effect=during_provider) as provider:
            result = api.retry(con, "first-retry", job)
        assert result["ok"], result
        assert len(competing) == 1
        provider.assert_called_once()
        assert con.execute("SELECT COUNT(*) FROM generations WHERE status = 'ready'").fetchone() == (1,)
        assert con.execute("SELECT COUNT(*) FROM jobs WHERE status = 'running'").fetchone() == (0,)
    finally:
        other.close()


def test_retry_reclaims_its_captured_job_after_restart_and_fences_old_attempt(retry_db):
    con, profile, path, key = retry_db
    _, job = _failed_add(con, profile)
    claimed = store.retry(con, "crashed-retry", job, lease_owner="crashed-worker")
    con.execute("UPDATE jobs SET lease_expires_at_ms = 0 WHERE job_id = ?", (claimed["job_id"],))
    con.commit()
    reopened = connect.open_encrypted(path, key)
    try:
        with patch("airag.embeddings.embed_documents", side_effect=_vectors) as provider:
            result = api.retry(reopened, "crashed-retry", job)
        assert result["ok"], result
        provider.assert_called_once()
        assert result["data"]["generation_id"] != claimed["generation_id"]
        with pytest.raises(store.ApiError) as exc:
            store.fail_generation(con, claimed["generation_id"], "late abandoned attempt")
        assert exc.value.code == "STALE_CLAIM_FENCED"
        assert con.execute("SELECT COUNT(*) FROM jobs").fetchone() == (2,)
        assert con.execute("SELECT COUNT(*) FROM generations WHERE status = 'ready'").fetchone() == (1,)
    finally:
        reopened.close()


@pytest.mark.parametrize("job_id", [True, 0, -1, "1", 1.0, None])
def test_invalid_job_id_is_rejected_before_claim(retry_db, job_id):
    con, profile, _, _ = retry_db
    original = api.add(con, "stored", "docs", "source", b"stored input")
    job = original["data"]["job_id"]
    before = _job_snapshot(con, job)
    result = api.retry(con, "invalid-id", job_id, profile_key=profile)
    assert not result["ok"], result
    assert result["error"]["code"] == "VALIDATION_ERROR"
    assert _job_snapshot(con, job) == before
    assert con.execute("SELECT COUNT(*) FROM generations").fetchone() == (0,)


def test_unknown_profile_does_not_consume_pending_job_or_request_id(retry_db):
    con, profile, _, _ = retry_db
    original = api.add(con, "stored", "docs", "source", b"stored input")
    job = original["data"]["job_id"]
    before = _job_snapshot(con, job)
    invalid = api.retry(con, "process-stored", job, profile_key="missing-profile")
    assert not invalid["ok"], invalid
    assert _job_snapshot(con, job) == before
    assert con.execute("SELECT COUNT(*) FROM request_ledger WHERE request_id = 'process-stored'").fetchone() == (0,)
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        corrected = api.retry(con, "process-stored", job, profile_key=profile)
    assert corrected["ok"], corrected


def test_request_id_cannot_be_rebound_to_another_pending_job(retry_db):
    con, profile, _, _ = retry_db
    first = api.add(con, "first", "docs", "first", b"first input")["data"]["job_id"]
    second = api.add(con, "second", "docs", "second", b"second input")["data"]["job_id"]
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        result = api.retry(con, "one-retry-id", first, profile_key=profile)
    assert result["ok"], result
    before = _job_snapshot(con, second)
    conflict = api.retry(con, "one-retry-id", second, profile_key=profile)
    assert conflict["error"]["code"] == "IDEMPOTENCY_MISMATCH"
    assert _job_snapshot(con, second) == before


@pytest.mark.parametrize("different_profile", [False, True])
def test_retry_never_adopts_an_unrelated_job_for_the_same_revision(retry_db, different_profile):
    con, profile, _, _ = retry_db
    _, failed_job = _failed_add(con, profile)
    competing_profile = None
    if different_profile:
        config = embeddings.EmbeddingSpaceConfig(
            "openai-compatible", "http://localhost:9999/v1", "fixture-embed",
            "different-model-revision", 4,
            tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3",
        )
        registered = api.register_profile(con, {"embedding": asdict(config)})
        assert registered["ok"], registered
        competing_profile = registered["data"]["profile_key"]
    token = api.status(con, "docs", "source")["data"]["revision_token"]
    other = store.update(con, store.UpdateRequest(
        "independent-reprocess", "docs", "source", token, b"original input",
        force_reprocess=True, explicit_profile_key=competing_profile,
    ), profile_key=competing_profile, lease_owner="other-worker")
    if different_profile:
        con.execute("UPDATE jobs SET lease_expires_at_ms = 0 WHERE job_id = ?", (other["job_id"],))
        con.commit()
    before = _job_snapshot(con, other["job_id"])
    with patch("airag.embeddings.embed_documents", side_effect=_vectors) as provider:
        result = api.retry(con, "retry-original", failed_job)
    assert not result["ok"], result
    provider.assert_not_called()
    assert _job_snapshot(con, other["job_id"]) == before


@pytest.mark.parametrize("operation", ["delete", "restore"])
def test_retry_rejects_non_processing_jobs(retry_db, operation):
    con, _, _, _ = retry_db
    added = api.add(con, "stored", "docs", "source", b"stored input")
    deleted = store.delete(con, store.DeleteRequest(
        "delete", "docs", "source", added["data"]["revision_token"],
    ))
    if operation == "restore":
        store.restore(con, store.RestoreRequest("restore", "docs", "source", deleted["revision_token"]))
    job = con.execute("SELECT job_id FROM jobs WHERE kind = ?", (operation,)).fetchone()[0]
    before = _job_snapshot(con, job)
    result = api.retry(con, "retry-non-processing", job)
    assert not result["ok"], result
    assert result["error"]["code"] == "INVALID_JOB_STATE"
    assert _job_snapshot(con, job) == before


def test_installed_cli_retries_pending_and_failed_jobs_with_stable_replay(tmp_path, key_bytes, provider):
    cli = str(Path(sys.executable).with_name("ai-rag"))
    db_path = tmp_path / "cli-retry.db"

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
        config = embeddings.EmbeddingSpaceConfig(
            "openai-compatible", provider, "fixture-embed", "fixture-revision", 4,
            tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3",
        )
        registered = api.register_profile(con, {"embedding": asdict(config)})
        assert registered["ok"], registered
        profile = registered["data"]["profile_key"]
        add_args = ("add", "--db", str(db_path), "--collection", "docs", "--source-key", "pending",
                    "--text", "stored input", "--request-id", "cli-pending")
        call(*add_args)
        original_replay = call(*add_args)
        pending = call("manage", "status", "--db", str(db_path), "--collection", "docs",
                       "--source-key", "pending")["data"]["latest_job"]
        assert pending["status"] == "pending" and pending["profile_key"] is None
        retry_args = ("manage", "retry", "--db", str(db_path), "--job-id", str(pending["job_id"]),
                      "--profile-key", profile, "--request-id", "cli-process-pending")
        processed = call(*retry_args)
        assert processed["data"]["searchable"]
        assert processed["data"]["target_job_id"] == pending["job_id"]
        assert processed["data"]["profile_key"] == profile
        assert call(*retry_args) == processed
        assert call(*add_args) == original_replay

        original_failure, failed_job = _failed_add(con, profile)
        before = _job_snapshot(con, failed_job)
        failed = call("manage", "status", "--db", str(db_path), "--collection", "docs",
                      "--source-key", "source")["data"]["latest_job"]
        assert failed["status"] == "failed" and failed["job_id"] == failed_job
        retry_args = ("manage", "retry", "--db", str(db_path), "--job-id", str(failed_job),
                      "--request-id", "cli-retry-failed")
        retried = call(*retry_args)
        assert retried["data"]["searchable"]
        assert retried["data"]["target_job_id"] == failed_job
        assert retried["data"]["executed_job_id"] != failed_job
        assert retried["data"]["profile_key"] == profile
        assert call(*retry_args) == retried
        assert _job_snapshot(con, failed_job) == before
        assert api.add(con, "original-add", "docs", "source", b"original input",
                       profile_key=profile) == original_failure
    finally:
        con.close()
