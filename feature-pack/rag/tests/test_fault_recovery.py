from __future__ import annotations

import json
import os
import selectors
import struct
import subprocess
import sys
import time
from dataclasses import asdict
from pathlib import Path
from unittest.mock import patch

import pytest

from airag import api, embeddings, store
from airag.db import connect


_CHILD = Path(__file__).parent / "helpers" / "fault_child.py"


def _vectors(cfg, texts, **kwargs):
    return [struct.pack(f"{cfg.dimension}f", 1, *([0] * (cfg.dimension - 1))) for _ in texts]


def _invoke(con, event):
    if event["command"] == "retry":
        return api.retry(con, event["request_id"], event["job_id"])
    if event["command"] == "reindex":
        return api.reindex(con, event["request_id"], "docs", event["source_key"], event["token"], profile_key=event["profile"])
    return api.add(con, event["request_id"], "docs", event["source_key"], event["content"].encode(), profile_key=event["profile"])


def _start(path, key, barrier_fd=None):
    key_read, key_write = os.pipe()
    os.write(key_write, key)
    os.close(key_write)
    argv = [sys.executable, str(_CHILD), "--db", str(path), "--key-fd", str(key_read)]
    inherited = [key_read]
    if barrier_fd is not None:
        argv += ["--barrier-fd", str(barrier_fd)]
        inherited.append(barrier_fd)
    try:
        return subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                pass_fds=inherited, env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
    finally:
        os.close(key_read)


def _finish(proc, payload=None):
    try:
        return proc.communicate(None if payload is None else json.dumps(payload).encode(), timeout=60)
    except subprocess.TimeoutExpired:
        proc.kill()  # Only this test's own child process is terminated.
        proc.communicate(timeout=10)
        raise


def _crash(path, key, event, code):
    proc = _start(path, key)
    stdout, stderr = _finish(proc, event)
    assert proc.returncode == code, stderr.decode()
    assert stdout == b""
    assert key.hex().encode() not in stderr


@pytest.fixture
def fault_db(tmp_path, key_bytes):
    path = tmp_path / "process-fault.db"
    con = connect.init_db(path, key_bytes)
    profiles = []
    for revision in ("old", "new"):
        cfg = embeddings.EmbeddingSpaceConfig("openai-compatible", "http://localhost:9999/v1", "fixture", revision, 4,
                                               tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3")
        profiles.append(api.register_profile(con, {"embedding": asdict(cfg)})["data"]["profile_key"])
    with patch("airag.embeddings.embed_documents", side_effect=_vectors):
        added = api.add(con, "original", "docs", "source", b"original content", profile_key=profiles[0])
    assert added["ok"], added
    con.close()
    return path, key_bytes, profiles, added


def _event(fixture, command, phase):
    path, key, profiles, added = fixture
    event = {"command": command, "phase": phase, "request_id": "crashed-" + command,
             "source_key": "new-source" if command == "add" else "source", "content": "fresh original",
             "profile": profiles[1], "token": added["data"]["revision_token"]}
    if command == "retry":
        con = connect.open_encrypted(path, key)
        try:
            with patch("airag.embeddings.embed_documents", side_effect=embeddings.EmbeddingError("PROVIDER_UNREACHABLE", "fixture outage", retryable=True)):
                failed = api.reindex(con, "failed-reindex", "docs", "source", event["token"], profile_key=profiles[1])
            assert not failed["ok"]
            event["job_id"] = con.execute("SELECT MAX(job_id) FROM jobs").fetchone()[0]
        finally:
            con.close()
    return event


@pytest.mark.parametrize("command", ["add", "retry", "reindex"])
def test_actual_exit_after_staging_reclaims_once_and_fences_old_attempt(fault_db, command):
    path, key, profiles, added = fault_db
    event = _event(fault_db, command, "staged")
    _crash(path, key, event, 71)
    con = connect.open_encrypted(path, key)
    try:
        job_id, old_generation, old_epoch = con.execute("SELECT job_id,generation_id,claim_epoch FROM jobs WHERE status='running'").fetchone()
        live = _invoke(con, event)
        assert not live["ok"] and live["error"]["code"] == "IN_PROGRESS"
        con.execute("UPDATE jobs SET lease_expires_at_ms=0 WHERE job_id=?", (job_id,))
        with patch("airag.embeddings.embed_documents", side_effect=_vectors) as provider:
            result = _invoke(con, event)
        assert result["ok"], result
        provider.assert_called_once()
        assert result["data"]["generation_id"] != old_generation
        assert con.execute("SELECT claim_epoch FROM jobs WHERE job_id=?", (job_id,)).fetchone() == (old_epoch + 1,)
        assert con.execute("SELECT status FROM generations WHERE generation_id=?", (old_generation,)).fetchone() == ("failed",)
        with pytest.raises(store.ApiError) as fenced:
            store.fail_generation(con, old_generation, "late old attempt")
        assert fenced.value.code == "STALE_CLAIM_FENCED"
        with patch("airag.embeddings.embed_documents", side_effect=AssertionError("duplicate processing")):
            assert _invoke(con, event) == result
        assert api.verify(con)["ok"]
    finally:
        con.close()


@pytest.mark.parametrize("command", ["add", "retry", "reindex"])
def test_actual_exit_after_publication_replays_response_after_later_change(fault_db, command):
    path, key, profiles, added = fault_db
    event = _event(fault_db, command, "response_lost")
    _crash(path, key, event, 72)
    con = connect.open_encrypted(path, key)
    try:
        executed_job_id, final_json = con.execute("SELECT job_id,final_response_json FROM jobs ORDER BY job_id DESC LIMIT 1").fetchone()
        assert final_json is not None
        stored = json.loads(final_json)
        if command in ("retry", "reindex"):
            stored["profile_key"] = profiles[1]
        if command == "retry":
            stored.update(target_job_id=event["job_id"], executed_job_id=executed_job_id)
        with patch("airag.embeddings.embed_documents", side_effect=AssertionError("publication already committed")):
            replay = _invoke(con, event)
        assert replay["ok"] and replay["data"] == stored
        current = api.status(con, "docs", event["source_key"])["data"]
        changed = api.update(con, "later-update", "docs", event["source_key"], current["revision_token"], b"later input")
        assert changed["ok"]
        con.close()
        con = connect.open_encrypted(path, key)
        with patch("airag.embeddings.embed_documents", side_effect=AssertionError("immutable replay only")):
            assert _invoke(con, event) == replay
        assert api.verify(con)["ok"]
    finally:
        con.close()


def test_exit_inside_publish_rolls_back_fts_vector_and_ready_pointer(fault_db):
    path, key, profiles, added = fault_db
    event = _event(fault_db, "reindex", "mid_publish")
    _crash(path, key, event, 73)
    con = connect.open_encrypted(path, key)
    try:
        assert api.status(con, "docs", "source")["data"]["ready_generation_id"] == added["data"]["generation_id"]
        assert api.verify(con)["ok"]
        abandoned = con.execute("SELECT generation_id FROM jobs WHERE status='running'").fetchone()[0]
        assert con.execute("SELECT COUNT(*) FROM chunks WHERE generation_id=?", (abandoned,)).fetchone() == (0,)
        assert con.execute("SELECT COUNT(*) FROM normalized_documents WHERE generation_id=?", (abandoned,)).fetchone() == (0,)
        con.execute("UPDATE jobs SET lease_expires_at_ms=0 WHERE status='running'")
        with patch("airag.embeddings.embed_documents", side_effect=_vectors):
            recovered = _invoke(con, event)
        assert recovered["ok"] and recovered["data"]["generation_id"] != abandoned
        assert api.verify(con)["ok"]
    finally:
        con.close()


def test_separate_process_update_delete_race_has_one_cas_winner(fault_db):
    path, key, profiles, added = fault_db
    children = []
    try:
        for command in ("update", "delete"):
            read_fd, write_fd = os.pipe()
            try:
                proc = _start(path, key, read_fd)
            finally:
                os.close(read_fd)
            children.append((proc, write_fd))
            event = {"command": command, "phase": "none", "request_id": "race-" + command,
                     "source_key": "source", "token": added["data"]["revision_token"], "content": "concurrent change"}
            proc.stdin.write(json.dumps(event).encode())
            proc.stdin.close()
            proc.stdin = None
        with selectors.DefaultSelector() as selector:
            for proc, _ in children:
                selector.register(proc.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + 60
            while selector.get_map():
                events = selector.select(max(0, deadline - time.monotonic()))
                assert events, "child did not reach the CAS barrier"
                for key_info, _ in events:
                    assert key_info.fileobj.readline() == b"READY\n"
                    selector.unregister(key_info.fileobj)
        for _, write_fd in children:
            os.write(write_fd, b"G")
        results = []
        for proc, _ in children:
            stdout, stderr = _finish(proc)
            assert proc.returncode == 0, stderr.decode()
            results.append(json.loads(stdout))
        assert sum(r["ok"] for r in results) == 1, results
        loser = next(r for r in results if not r["ok"])
        assert loser["error"]["code"] in ("CONFLICT_STALE_REVISION", "ALREADY_DELETED")
        con = connect.open_encrypted(path, key)
        try:
            assert con.execute("SELECT state_version FROM sources WHERE source_id=1").fetchone() == (added["data"]["state_version"] + 1,)
            assert con.execute("SELECT COUNT(*) FROM request_ledger WHERE request_id LIKE 'race-%'").fetchone() == (1,)
            assert con.execute("SELECT COUNT(*) FROM jobs").fetchone() == (2,)
            assert api.verify(con)["ok"]
        finally:
            con.close()
    finally:
        for proc, write_fd in children:
            os.close(write_fd)
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=10)


def test_process_exit_before_backup_publication_keeps_target_absent(fault_db, tmp_path):
    path, key, profiles, added = fault_db
    target = tmp_path / "never-published.db"
    _crash(path, key, {"phase": "backup_before_publish", "target": str(target)}, 74)
    assert not target.exists()
    partials = list(tmp_path.glob(".airag-snapshot-*.partial"))
    assert len(partials) == 1
    for retained in (path, partials[0]):
        con = connect.open_readonly(retained, key)
        try:
            assert api.verify(con)["ok"]
            assert api.status(con, "docs", "source")["data"]["ready_generation_id"] == added["data"]["generation_id"]
        finally:
            con.close()
    assert b"original content" not in partials[0].read_bytes()
