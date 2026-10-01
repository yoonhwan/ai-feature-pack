from __future__ import annotations

import base64
import threading
import uuid
from pathlib import Path

import pytest

from airag import store
from airag.db import connect


@pytest.fixture
def con(tmp_path: Path, key_bytes: bytes):
    c = connect.init_db(tmp_path / "store.db", key_bytes)
    yield c
    c.close()


def _rid() -> str:
    return str(uuid.uuid4())


# --------------------------------------------------------------------- add


def test_add_creates_source_and_revision(con) -> None:
    resp = store.add(
        con,
        store.AddRequest(_rid(), "docs", "faq.md", b"hello world", media_type="text/plain"),
    )
    assert resp["no_op"] is False
    assert resp["content_changed"] is True
    assert resp["state_version"] == 1
    assert resp["processing_status"] == "pending"
    assert resp["searchable"] is False
    assert isinstance(resp["revision_token"], str) and resp["revision_token"]
    row = con.execute("SELECT COUNT(*) FROM sources").fetchone()
    assert row == (1,)


def test_add_duplicate_active_source_conflicts(con) -> None:
    store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"a"))
    with pytest.raises(store.ApiError) as excinfo:
        store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"b"))
    assert excinfo.value.code == "ALREADY_EXISTS"


def test_add_after_delete_requires_restore_not_add(con) -> None:
    resp = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"a"))
    store.delete(con, store.DeleteRequest(_rid(), "docs", "faq.md", resp["revision_token"]))
    with pytest.raises(store.ApiError) as excinfo:
        store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"a"))
    assert excinfo.value.code == "ALREADY_EXISTS_DELETED"


def test_collection_key_isolation(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "same-key", b"in docs"))
    r2 = store.add(con, store.AddRequest(_rid(), "notes", "same-key", b"in notes"))
    assert r1["source_id"] != r2["source_id"]
    got1 = store.fetch_original(con, "docs", "same-key", include_bytes=True)
    got2 = store.fetch_original(con, "notes", "same-key", include_bytes=True)
    assert got1["content_hash"] != got2["content_hash"]


def test_add_rejects_oversized_content(con) -> None:
    huge = b"x" * (store.MAX_CONTENT_BYTES + 1)
    with pytest.raises(store.ApiError) as excinfo:
        store.add(con, store.AddRequest(_rid(), "docs", "big.bin", huge, media_type="application/octet-stream"))
    assert excinfo.value.code == "PAYLOAD_TOO_LARGE"


def test_add_rejects_invalid_utf8_for_text_media_type(con) -> None:
    with pytest.raises(store.ApiError) as excinfo:
        store.add(con, store.AddRequest(_rid(), "docs", "bad.txt", b"\xff\xfe not utf8", media_type="text/plain"))
    assert excinfo.value.code == "VALIDATION_ERROR"


def test_add_allows_empty_content_explicitly(con) -> None:
    resp = store.add(con, store.AddRequest(_rid(), "docs", "empty.md", b"", media_type="text/plain"))
    assert resp["content_hash"]
    fetched = store.fetch_original(con, "docs", "empty.md", include_bytes=True)
    assert fetched["byte_length"] == 0


def test_add_rejects_bytearray_content(con) -> None:
    """content must be immutable bytes — a bytearray could be mutated
    between hash computation and storage (p02-review1.txt item 2)."""
    with pytest.raises(store.ApiError) as excinfo:
        store.add(con, store.AddRequest(_rid(), "docs", "faq.md", bytearray(b"hello")))
    assert excinfo.value.code == "VALIDATION_ERROR"


def test_add_rejects_nonfinite_json_constants(con) -> None:
    """Python's json module accepts NaN/Infinity by default; strict JSON
    validation must reject them (p02-review1.txt item 2)."""
    with pytest.raises(store.ApiError) as excinfo:
        store.add(
            con,
            store.AddRequest(_rid(), "docs", "bad.json", b'{"x": NaN}', media_type="application/json"),
        )
    assert excinfo.value.code == "VALIDATION_ERROR"


def test_add_accepts_valid_json(con) -> None:
    resp = store.add(
        con, store.AddRequest(_rid(), "docs", "ok.json", b'{"x": 1.5}', media_type="application/json")
    )
    assert resp["content_changed"] is True


# ------------------------------------------------------------------ update


def test_update_no_op_when_content_and_metadata_unchanged(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"same", media_type="text/plain"))
    r2 = store.update(
        con,
        store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"same", media_type="text/plain"),
    )
    assert r2["no_op"] is True
    assert r2["content_changed"] is False
    assert r2["metadata_changed"] is False
    assert r2["state_version"] == 1
    assert r2["revision_id"] == r1["revision_id"]
    count = con.execute("SELECT COUNT(*) FROM source_revisions").fetchone()
    assert count == (1,)


def test_update_creates_new_revision_when_content_changes(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    r2 = store.update(
        con,
        store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v2"),
    )
    assert r2["no_op"] is False
    assert r2["content_changed"] is True
    assert r2["state_version"] == 2
    assert r2["revision_id"] != r1["revision_id"]
    assert r2["content_hash"] != r1["content_hash"]


def test_force_reprocess_with_unchanged_bytes_keeps_head_revision(con) -> None:
    """D-001: unchanged bytes + a reprocess request is a new processing
    attempt against the SAME revision, never a new revision row
    (p02-review1.txt item 2 — corrects the initial draft's behavior)."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"same"))
    r2 = store.update(
        con,
        store.UpdateRequest(
            _rid(), "docs", "faq.md", r1["revision_token"], b"same", force_reprocess=True
        ),
    )
    assert r2["no_op"] is False
    assert r2["content_changed"] is False
    assert r2["reprocess_queued"] is True
    assert r2["revision_id"] == r1["revision_id"]
    count = con.execute("SELECT COUNT(*) FROM source_revisions").fetchone()
    assert count == (1,)
    jobs = con.execute(
        "SELECT COUNT(*) FROM jobs WHERE revision_id = ? AND kind = 'update'", (r1["revision_id"],)
    ).fetchone()
    assert jobs == (1,)


def test_update_with_unchanged_content_but_changed_metadata_persists_metadata(con) -> None:
    """Identical bytes with a different media_type/origin_uri must not
    silently discard the new metadata (p02-review1.txt item 2)."""
    r1 = store.add(
        con,
        store.AddRequest(_rid(), "docs", "faq.md", b"same", media_type="text/plain", origin_uri="file:///a"),
    )
    r2 = store.update(
        con,
        store.UpdateRequest(
            _rid(), "docs", "faq.md", r1["revision_token"], b"same",
            media_type="text/markdown", origin_uri="file:///b",
        ),
    )
    assert r2["no_op"] is False
    assert r2["content_changed"] is False
    assert r2["metadata_changed"] is True
    assert r2["revision_id"] == r1["revision_id"]  # still no new revision
    assert r2["state_version"] == 2  # but it IS a real state mutation

    status = store.get_status(con, "docs", "faq.md")
    assert status["media_type"] == "text/markdown"
    assert status["origin_uri"] == "file:///b"


def test_content_revert_a_b_a_creates_third_distinct_revision(con) -> None:
    """A->B->A: reverting to a previously-seen hash must create a fresh
    revision row (no UNIQUE(source_id, content_hash) collision) and the
    head pointer must land on that new row, not silently re-point at the
    old one."""
    r_a1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content-A"))
    r_b = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r_a1["revision_token"], b"content-B"))
    r_a2 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r_b["revision_token"], b"content-A"))

    assert r_a2["content_hash"] == r_a1["content_hash"]
    assert r_a2["revision_id"] not in (r_a1["revision_id"], r_b["revision_id"])
    assert r_a2["state_version"] == 3
    count = con.execute("SELECT COUNT(*) FROM source_revisions").fetchone()
    assert count == (3,)

    status = store.get_status(con, "docs", "faq.md")
    assert status["revision_token"] == r_a2["revision_token"]


def test_update_rejects_stale_token(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    _ = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v2"))
    with pytest.raises(store.ApiError) as excinfo:
        store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v3"))
    assert excinfo.value.code == "CONFLICT_STALE_REVISION"
    assert excinfo.value.retryable is True


def test_stale_token_rejected_after_delete_restore_even_with_unchanged_content(con) -> None:
    """The D-009 worked example: a token issued before a delete/restore
    cycle is stale afterward even though the content never changed."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"same-content"))
    r2 = store.delete(con, store.DeleteRequest(_rid(), "docs", "faq.md", r1["revision_token"]))
    r3 = store.restore(con, store.RestoreRequest(_rid(), "docs", "faq.md", r2["revision_token"]))

    assert r3["state_version"] == 3
    with pytest.raises(store.ApiError) as excinfo:
        store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"same-content"))
    assert excinfo.value.code == "CONFLICT_STALE_REVISION"

    r4 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r3["revision_token"], b"same-content"))
    assert r4["no_op"] is True


# ------------------------------------------------------------- delete/restore


def test_delete_then_update_requires_restore_first(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    r2 = store.delete(con, store.DeleteRequest(_rid(), "docs", "faq.md", r1["revision_token"]))
    with pytest.raises(store.ApiError) as excinfo:
        store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r2["revision_token"], b"v2"))
    assert excinfo.value.code == "ALREADY_DELETED"


def test_double_delete_rejected(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    r2 = store.delete(con, store.DeleteRequest(_rid(), "docs", "faq.md", r1["revision_token"]))
    with pytest.raises(store.ApiError) as excinfo:
        store.delete(con, store.DeleteRequest(_rid(), "docs", "faq.md", r2["revision_token"]))
    assert excinfo.value.code == "ALREADY_DELETED"


def test_restore_preserves_original_content_and_history(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"original bytes"))
    r2 = store.delete(con, store.DeleteRequest(_rid(), "docs", "faq.md", r1["revision_token"]))
    r3 = store.restore(con, store.RestoreRequest(_rid(), "docs", "faq.md", r2["revision_token"]))
    assert r3["deleted"] is False

    fetched = store.fetch_original(con, "docs", "faq.md", include_bytes=True)
    assert base64.b64decode(fetched["content_base64"]) == b"original bytes"
    assert fetched["deleted"] is False


def test_restore_requires_currently_deleted(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    with pytest.raises(store.ApiError) as excinfo:
        store.restore(con, store.RestoreRequest(_rid(), "docs", "faq.md", r1["revision_token"]))
    assert excinfo.value.code == "NOT_DELETED"


def test_deleted_source_never_searchable_even_with_ready_pointer(con) -> None:
    """p02-review1.txt item 4: deleted always not searchable, regardless of
    a ready generation existing."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    gen = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    store.publish_generation(con, gen["generation_id"])
    status = store.get_status(con, "docs", "faq.md")
    assert status["searchable"] is True

    r2 = store.delete(con, store.DeleteRequest(_rid(), "docs", "faq.md", status["revision_token"]))
    assert r2["searchable"] is False
    status2 = store.get_status(con, "docs", "faq.md")
    assert status2["searchable"] is False
    assert status2["processing_status"] == "not_indexed"


# ------------------------------------------------------------------ idempotency


def test_exact_retry_returns_cached_result_without_duplicate_work(con) -> None:
    rid = _rid()
    r1 = store.add(con, store.AddRequest(rid, "docs", "faq.md", b"hello"))
    r2 = store.add(con, store.AddRequest(rid, "docs", "faq.md", b"hello"))
    assert r2["source_id"] == r1["source_id"]
    assert r2.get("idempotent_replay") is True
    count = con.execute("SELECT COUNT(*) FROM sources").fetchone()
    assert count == (1,)


def test_idempotency_mismatch_on_same_request_id_different_payload(con) -> None:
    rid = _rid()
    store.add(con, store.AddRequest(rid, "docs", "faq.md", b"hello"))
    with pytest.raises(store.ApiError) as excinfo:
        store.add(con, store.AddRequest(rid, "docs", "faq.md", b"different content"))
    assert excinfo.value.code == "IDEMPOTENCY_MISMATCH"


def test_idempotent_retry_of_update_succeeds_even_with_now_stale_token(con) -> None:
    """'Do not apply a stale expected token before recognizing an
    identical completed retry.' A caller retries the exact same update
    request after the source has moved on further — the retry must return
    the cached result, not a stale-token conflict."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    update_rid = _rid()
    req = store.UpdateRequest(update_rid, "docs", "faq.md", r1["revision_token"], b"v2")
    r2 = store.update(con, req)
    assert r2["state_version"] == 2

    r3 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r2["revision_token"], b"v3"))
    assert r3["state_version"] == 3

    retry = store.update(con, req)
    assert retry.get("idempotent_replay") is True
    assert retry["state_version"] == r2["state_version"]
    assert retry["revision_id"] == r2["revision_id"]

    status = store.get_status(con, "docs", "faq.md")
    assert status["state_version"] == 3


def test_concurrent_identical_retries_replay_cleanly_not_as_a_race(
    con, tmp_path: Path, key_bytes: bytes
) -> None:
    """Two threads submit the SAME request_id + SAME payload at once. Under
    the fix (idempotency checked inside BEGIN IMMEDIATE, not before it),
    exactly one does the real work and the other, once it acquires the
    lock behind the first, sees the ledger row and replays — never a raw
    UNIQUE-constraint IntegrityError or SQLITE_BUSY leaking out."""
    db_path = tmp_path / "idem-race.db"
    con0 = connect.init_db(db_path, key_bytes)
    con0.close()

    rid = _rid()
    barrier = threading.Barrier(2)
    results: list[tuple[str, object]] = []
    lock = threading.Lock()

    def _attempt() -> None:
        c = connect.open_encrypted(db_path, key_bytes)
        try:
            _ = barrier.wait(timeout=5)
            resp = store.add(c, store.AddRequest(rid, "docs", "faq.md", b"same payload"))
            with lock:
                results.append(("ok", resp))
        except Exception as exc:  # pragma: no cover - asserted below
            with lock:
                results.append((type(exc).__name__, exc))
        finally:
            c.close()

    threads = [threading.Thread(target=_attempt) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=10)

    kinds = [r[0] for r in results]
    assert kinds == ["ok", "ok"], results
    source_ids = {r[1]["source_id"] for r in results}
    assert len(source_ids) == 1

    con_final = connect.open_encrypted(db_path, key_bytes)
    try:
        count = con_final.execute("SELECT COUNT(*) FROM sources").fetchone()
        assert count == (1,)
    finally:
        con_final.close()


# --------------------------------------------------------------- staging/publish


def test_stage_and_publish_generation(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    staged = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    assert staged["status"] == "staged"
    published = store.publish_generation(con, staged["generation_id"])
    assert published["status"] == "ready"
    status = store.get_status(con, "docs", "faq.md")
    assert status["processing_status"] == "ready"
    assert status["searchable"] is True


def test_stage_rejects_non_head_revision(con) -> None:
    """Staging a superseded (non-head) revision is refused outright, not
    silently accepted (p02-review1.txt item 3)."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    r2 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v2"))
    with pytest.raises(store.ApiError) as excinfo:
        store.stage_generation(con, r1["revision_id"], "profile-v1", r2["revision_token"])
    assert excinfo.value.code == "STALE_REVISION"


def test_stage_rejects_stale_expected_revision(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v2"))
    with pytest.raises(store.ApiError) as excinfo:
        store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    assert excinfo.value.code in ("CONFLICT_STALE_REVISION", "STALE_REVISION")


def test_publish_uses_staged_state_not_caller_supplied_fresh_token(con) -> None:
    """The gap this review closed: publish_generation no longer accepts a
    caller-supplied expected_revision at all — it can ONLY use the state
    captured at staging time. Stage against v1, update the source to v2
    (making the generation's captured state stale), and publish must fail
    even though a "fresh" v2 token exists and is available to the caller."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    staged = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    r2 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v2"))
    assert r2["state_version"] == 2  # a "fresh" token exists now, but publish_generation cannot take it

    with pytest.raises(store.ApiError) as excinfo:
        store.publish_generation(con, staged["generation_id"])
    assert excinfo.value.code in ("CONFLICT_STALE_REVISION", "STALE_REVISION")

    status = store.get_status(con, "docs", "faq.md")
    assert status["searchable"] is False


def test_publish_rejects_already_ready_generation(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    staged = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    store.publish_generation(con, staged["generation_id"])
    with pytest.raises(store.ApiError) as excinfo:
        store.publish_generation(con, staged["generation_id"])
    assert excinfo.value.code == "INVALID_GENERATION_STATE"


def test_publish_stale_cas_leaves_previous_ready_pointer_unchanged(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    gen_a = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    pub_a = store.publish_generation(con, gen_a["generation_id"])
    assert pub_a["status"] == "ready"
    # publish_generation itself advances state_version (see store.py) —
    # r1's token is stale the moment gen_a publishes; use pub_a's token.

    r2 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", pub_a["revision_token"], b"v2"))
    gen_b = store.stage_generation(con, r2["revision_id"], "profile-v1", r2["revision_token"])
    # gen_b staged successfully against r2's state; force genuine staleness
    # by mutating again after staging, before gen_b gets a chance to publish.
    r3 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r2["revision_token"], b"v3"))
    assert r3["state_version"] == 4  # 1 (add) -> 2 (publish gen_a) -> 3 (update v2) -> 4 (update v3)

    with pytest.raises(store.ApiError) as excinfo:
        store.publish_generation(con, gen_b["generation_id"])
    assert excinfo.value.code in ("CONFLICT_STALE_REVISION", "STALE_REVISION")

    row = con.execute(
        "SELECT ready_generation_id FROM sources WHERE source_id = ?", (r1["source_id"],)
    ).fetchone()
    assert row[0] == gen_a["generation_id"]
    status = store.get_status(con, "docs", "faq.md")
    assert status["processing_status"] == "stale_ready"
    assert status["searchable"] is True


def test_fail_generation_preserves_previous_ready_content(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    gen_a = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    pub_a = store.publish_generation(con, gen_a["generation_id"])

    r2 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", pub_a["revision_token"], b"v2"))
    gen_b = store.stage_generation(con, r2["revision_id"], "profile-v2", r2["revision_token"])
    failed = store.fail_generation(con, gen_b["generation_id"], "synthetic embedding failure")
    assert failed["status"] == "failed"

    status = store.get_status(con, "docs", "faq.md")
    assert status["ready_generation_id"] == gen_a["generation_id"]
    assert status["processing_status"] == "stale_ready"
    assert status["searchable"] is True


def test_retry_after_failed_generation_creates_new_attempt_not_update(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    attempt1 = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    store.fail_generation(con, attempt1["generation_id"], "boom")
    attempt2 = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    assert attempt1["generation_id"] != attempt2["generation_id"]
    published = store.publish_generation(con, attempt2["generation_id"])
    assert published["status"] == "ready"


def test_stage_rejects_reclaiming_an_already_completed_job(con) -> None:
    """A job that has already been claimed (linked to a generation, and
    that generation has since been published) must never be silently
    reassigned to a new staging attempt — that would rewrite its
    completion status back to 'running' and destroy the prior generation's
    provenance link (independently reproduced against a real encrypted DB:
    a second stage_generation call against a 'done' job overwrote it)."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    job_id = con.execute(
        "SELECT job_id FROM jobs WHERE revision_id = ? AND kind = 'add'", (r1["revision_id"],)
    ).fetchone()[0]
    staged = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"], job_id=job_id)
    pub = store.publish_generation(con, staged["generation_id"])
    # publish_generation advances state_version — use ITS returned token so
    # this test reaches the job-reuse check itself, not an (also-correct
    # but different) CAS rejection on r1's now-stale token.
    current_token = pub["revision_token"]

    job_row_before = con.execute("SELECT status, generation_id FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
    assert job_row_before == ("done", staged["generation_id"])

    with pytest.raises(store.ApiError) as excinfo:
        store.stage_generation(con, r1["revision_id"], "profile-v2", current_token, job_id=job_id)
    assert excinfo.value.code == "INVALID_JOB_STATE"

    job_row_after = con.execute("SELECT status, generation_id FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
    assert job_row_after == job_row_before  # untouched by the rejected attempt


def test_stage_rejects_job_for_a_different_revision(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    job_id = con.execute(
        "SELECT job_id FROM jobs WHERE revision_id = ? AND kind = 'add'", (r1["revision_id"],)
    ).fetchone()[0]
    r2 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v2"))
    other_job_id = con.execute(
        "SELECT job_id FROM jobs WHERE revision_id = ? AND kind = 'update'", (r2["revision_id"],)
    ).fetchone()[0]
    with pytest.raises(store.ApiError) as excinfo:
        # job_id belongs to revision r1, but we're staging revision r2.
        store.stage_generation(con, r2["revision_id"], "profile-v1", r2["revision_token"], job_id=job_id)
    assert excinfo.value.code == "VALIDATION_ERROR"
    assert other_job_id != job_id  # sanity: they really are different jobs


def test_add_job_expected_state_version_is_populated(con) -> None:
    """jobs.expected_state_version must actually carry a value, not just
    exist in the schema (p02-final-probes.txt item 2)."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    row = con.execute(
        "SELECT expected_state_version FROM jobs WHERE revision_id = ? AND kind = 'add'", (r1["revision_id"],)
    ).fetchone()
    assert row == (1,)


def test_update_job_expected_state_version_is_populated(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    r2 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v2"))
    row = con.execute(
        "SELECT expected_state_version FROM jobs WHERE revision_id = ? AND kind = 'update'", (r2["revision_id"],)
    ).fetchone()
    assert row == (2,)


def test_stage_links_job_and_publish_completes_it_atomically(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    job_id = con.execute(
        "SELECT job_id FROM jobs WHERE revision_id = ? AND kind = 'add'", (r1["revision_id"],)
    ).fetchone()[0]
    staged = store.stage_generation(
        con, r1["revision_id"], "profile-v1", r1["revision_token"], job_id=job_id
    )
    job_status_after_stage = con.execute(
        "SELECT status, generation_id FROM jobs WHERE job_id = ?", (job_id,)
    ).fetchone()
    assert job_status_after_stage == ("running", staged["generation_id"])

    store.publish_generation(con, staged["generation_id"])
    job_status_after_publish = con.execute(
        "SELECT status FROM jobs WHERE job_id = ?", (job_id,)
    ).fetchone()
    assert job_status_after_publish == ("done",)


# --------------------------------------------------- P-03-B inline staging


def test_add_with_profile_key_stages_generation_atomically(con) -> None:
    resp = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"), profile_key="profile-v1")
    assert resp["job_id"] is not None
    assert resp["generation_id"] is not None
    job_row = con.execute(
        "SELECT status, profile_key, generation_id FROM jobs WHERE job_id = ?", (resp["job_id"],)
    ).fetchone()
    assert job_row == ("running", "profile-v1", resp["generation_id"])
    gen_row = con.execute(
        "SELECT status, profile_key FROM generations WHERE generation_id = ?", (resp["generation_id"],)
    ).fetchone()
    assert gen_row == ("staged", "profile-v1")


def test_add_without_profile_key_leaves_job_pending_unstaged(con) -> None:
    resp = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    assert resp["job_id"] is not None
    assert resp["generation_id"] is None
    job_row = con.execute("SELECT status, generation_id FROM jobs WHERE job_id = ?", (resp["job_id"],)).fetchone()
    assert job_row == ("pending", None)


def test_update_content_changed_with_profile_key_stages_generation(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    r2 = store.update(
        con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"v2"), profile_key="profile-v1"
    )
    assert r2["job_id"] is not None
    assert r2["generation_id"] is not None
    gen_row = con.execute(
        "SELECT revision_id, status FROM generations WHERE generation_id = ?", (r2["generation_id"],)
    ).fetchone()
    assert gen_row == (r2["revision_id"], "staged")


def test_retry_with_same_request_id_ignores_new_default_profile(con) -> None:
    """A retry (same request_id, same fingerprint — explicit_profile_key is
    None on both calls) must replay the ORIGINAL cached response, including
    its already-captured job_id/generation_id, even though this second call
    passes a DIFFERENT resolved `profile_key` (simulating the configured
    default having changed between the two calls)."""
    rid = _rid()
    r1 = store.add(con, store.AddRequest(rid, "docs", "faq.md", b"content"), profile_key="profile-v1")
    r2 = store.add(con, store.AddRequest(rid, "docs", "faq.md", b"content"), profile_key="profile-v2-new-default")
    assert r2["job_id"] == r1["job_id"]
    assert r2["generation_id"] == r1["generation_id"]
    assert r2.get("idempotent_replay") is True
    # The generation actually staged in the DB is still profile-v1 — the
    # new "default" passed on retry never touched anything.
    gen_row = con.execute(
        "SELECT profile_key FROM generations WHERE generation_id = ?", (r1["generation_id"],)
    ).fetchone()
    assert gen_row == ("profile-v1",)


def test_explicit_profile_key_change_on_retry_is_idempotency_mismatch(con) -> None:
    """A caller's OWN explicit override (not the resolved default) IS part
    of the fingerprint — retrying the same request_id with a different
    explicit choice is a genuinely different request, not a replay."""
    rid = _rid()
    _ = store.add(
        con,
        store.AddRequest(rid, "docs", "faq.md", b"content", explicit_profile_key="profile-a"),
        profile_key="profile-a",
    )
    with pytest.raises(store.ApiError) as excinfo:
        store.add(
            con,
            store.AddRequest(rid, "docs", "faq.md", b"content", explicit_profile_key="profile-b"),
            profile_key="profile-b",
        )
    assert excinfo.value.code == "IDEMPOTENCY_MISMATCH"


def test_renew_lease_extends_deadline_and_rejects_stale_epoch(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"), profile_key="profile-v1")
    job_id = r1["job_id"]
    before = con.execute("SELECT lease_expires_at_ms, claim_epoch FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
    assert before[1] == 1

    store.renew_lease(con, job_id, 1, lease_ms=999_999)
    after = con.execute("SELECT lease_expires_at_ms FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
    assert after[0] >= before[0]

    with pytest.raises(store.ApiError) as excinfo:
        store.renew_lease(con, job_id, 2, lease_ms=999_999)  # wrong epoch
    assert excinfo.value.code == "STALE_CLAIM_FENCED"


def test_renew_lease_after_reclaim_is_fenced_for_old_epoch(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"), profile_key="profile-v1")
    job_id = r1["job_id"]
    con.execute("UPDATE jobs SET lease_expires_at_ms = 0 WHERE job_id = ?", (job_id,))
    con.commit()
    reclaimed = store.reclaim_stale_job(con, job_id)

    with pytest.raises(store.ApiError) as excinfo:
        store.renew_lease(con, job_id, 1, lease_ms=999_999)  # old epoch, now stale
    assert excinfo.value.code == "STALE_CLAIM_FENCED"

    store.renew_lease(con, job_id, reclaimed["claim_epoch"], lease_ms=999_999)  # new epoch works


# ------------------------------------------------------- lease/claim fencing


def _job_id_for(con, revision_id: int, kind: str = "add") -> int:
    row = con.execute(
        "SELECT job_id FROM jobs WHERE revision_id = ? AND kind = ?", (revision_id, kind)
    ).fetchone()
    assert row is not None
    return row[0]


def _expire_lease(con, job_id: int) -> None:
    """Test-only: simulate a crashed worker by backdating the lease past
    its deadline, without waiting out DEFAULT_LEASE_MS in real time."""
    con.execute("UPDATE jobs SET lease_expires_at_ms = 0 WHERE job_id = ?", (job_id,))
    con.commit()


def test_reclaim_rejects_a_job_whose_lease_has_not_expired(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    job_id = _job_id_for(con, r1["revision_id"])
    store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"], job_id=job_id)

    with pytest.raises(store.ApiError) as excinfo:
        store.reclaim_stale_job(con, job_id)
    assert excinfo.value.code == "LEASE_NOT_EXPIRED"


def test_reclaim_after_lease_expiry_fails_old_generation_and_starts_new_one(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    job_id = _job_id_for(con, r1["revision_id"])
    old_gen = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"], job_id=job_id)
    _expire_lease(con, job_id)

    reclaimed = store.reclaim_stale_job(con, job_id)
    assert reclaimed["previous_generation_id"] == old_gen["generation_id"]
    assert reclaimed["generation_id"] != old_gen["generation_id"]
    assert reclaimed["claim_epoch"] == 2  # epoch 1 at first claim, 2 after reclaim

    old_row = con.execute(
        "SELECT status, error FROM generations WHERE generation_id = ?", (old_gen["generation_id"],)
    ).fetchone()
    assert old_row == ("failed", "lease_expired_reclaimed_by_new_attempt")
    new_row = con.execute(
        "SELECT status, profile_key FROM generations WHERE generation_id = ?", (reclaimed["generation_id"],)
    ).fetchone()
    assert new_row == ("staged", "profile-v1")
    job_row = con.execute(
        "SELECT status, generation_id, profile_key, claim_epoch FROM jobs WHERE job_id = ?", (job_id,)
    ).fetchone()
    assert job_row == ("running", reclaimed["generation_id"], "profile-v1", 2)


def test_late_old_owner_publish_after_reclaim_is_fenced(con) -> None:
    """The exact race dispatch/review flags: a worker whose lease already
    expired finishes its outside-the-transaction model call AFTER someone
    else reclaimed the job — its publish of the ABANDONED generation must
    be rejected, never silently accepted or allowed to clobber the new
    attempt's ready pointer."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    job_id = _job_id_for(con, r1["revision_id"])
    old_gen = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"], job_id=job_id)
    _expire_lease(con, job_id)
    reclaimed = store.reclaim_stale_job(con, job_id)

    with pytest.raises(store.ApiError) as excinfo:
        store.publish_generation(con, old_gen["generation_id"])
    assert excinfo.value.code == "STALE_CLAIM_FENCED"

    with pytest.raises(store.ApiError) as excinfo2:
        store.fail_generation(con, old_gen["generation_id"], "late failure from abandoned attempt")
    assert excinfo2.value.code == "STALE_CLAIM_FENCED"

    # The NEW attempt is unaffected and can still publish normally.
    published = store.publish_generation(con, reclaimed["generation_id"])
    assert published["status"] == "ready"
    status = store.get_status(con, "docs", "faq.md")
    assert status["ready_generation_id"] == reclaimed["generation_id"]


def test_reclaim_rejects_profile_key_drift_by_construction(con) -> None:
    """reclaim_stale_job takes no profile_key argument at all — it always
    reuses the job's own originally-captured jobs.profile_key, so a caller
    cannot reinterpret a stuck job under a different profile on reclaim."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content"))
    job_id = _job_id_for(con, r1["revision_id"])
    store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"], job_id=job_id)
    _expire_lease(con, job_id)

    reclaimed = store.reclaim_stale_job(con, job_id)
    row = con.execute(
        "SELECT profile_key FROM generations WHERE generation_id = ?", (reclaimed["generation_id"],)
    ).fetchone()
    assert row == ("profile-v1",)


def test_reclaim_rejects_source_state_drift_since_job_creation(con) -> None:
    """A metadata edit (or delete/restore) bumps sources.state_version
    without changing head_revision_id — reclaim must refuse to resume
    processing against a source that moved on since this job's own
    expected_state_version was captured, rather than spending a model call
    on stale intent."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"content", media_type="text/plain"))
    job_id = _job_id_for(con, r1["revision_id"])
    store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"], job_id=job_id)
    _expire_lease(con, job_id)

    # Metadata-only update: same content (no new revision/job), but bumps
    # state_version — exactly the drift the CAS check must catch.
    store.update(
        con,
        store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"content", origin_uri="file:///new"),
    )

    with pytest.raises(store.ApiError) as excinfo:
        store.reclaim_stale_job(con, job_id)
    assert excinfo.value.code == "CONFLICT_STALE_REVISION"


# --------------------------------------------------------------------- reads


def test_list_sources_respects_deleted_filter(con) -> None:
    store.add(con, store.AddRequest(_rid(), "docs", "a.md", b"a"))
    r2 = store.add(con, store.AddRequest(_rid(), "docs", "b.md", b"b"))
    store.delete(con, store.DeleteRequest(_rid(), "docs", "b.md", r2["revision_token"]))

    active = store.list_sources(con, "docs")
    assert [s["source_key"] for s in active["sources"]] == ["a.md"]

    everything = store.list_sources(con, "docs", include_deleted=True)
    assert sorted(s["source_key"] for s in everything["sources"]) == ["a.md", "b.md"]


def test_fetch_original_default_excludes_bytes(con) -> None:
    store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"secret-ish content"))
    result = store.fetch_original(con, "docs", "faq.md")
    assert "content_base64" not in result


def test_fetch_original_can_retrieve_historical_revision_after_update(con) -> None:
    """p02-review1.txt item 5: after an update, the OLD original must
    still be retrievable byte-for-byte via explicit revision_id, alongside
    the new head."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"old bytes", origin_uri="file:///old"))
    r2 = store.update(
        con, store.UpdateRequest(_rid(), "docs", "faq.md", r1["revision_token"], b"new bytes", origin_uri="file:///new")
    )

    old = store.fetch_original(con, "docs", "faq.md", revision_id=r1["revision_id"], include_bytes=True)
    new = store.fetch_original(con, "docs", "faq.md", revision_id=r2["revision_id"], include_bytes=True)
    assert base64.b64decode(old["content_base64"]) == b"old bytes"
    assert base64.b64decode(new["content_base64"]) == b"new bytes"
    assert old["is_head"] is False
    assert new["is_head"] is True
    assert old["origin_uri"] == "file:///old"
    assert new["origin_uri"] == "file:///new"

    default = store.fetch_original(con, "docs", "faq.md", include_bytes=True)
    assert default["revision_id"] == r2["revision_id"]


def test_fetch_original_rejects_foreign_revision_id(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "a.md", b"a"))
    store.add(con, store.AddRequest(_rid(), "docs", "b.md", b"b"))
    with pytest.raises(store.ApiError) as excinfo:
        # b.md's revision_id used against a.md's identity.
        b_revision_id = con.execute(
            "SELECT head_revision_id FROM sources s JOIN collections c ON s.collection_id = c.collection_id "
            "WHERE c.name='docs' AND s.source_key='b.md'"
        ).fetchone()[0]
        store.fetch_original(con, "docs", "a.md", revision_id=b_revision_id)
    assert excinfo.value.code == "NOT_FOUND"


def test_get_status_not_found(con) -> None:
    with pytest.raises(store.ApiError) as excinfo:
        store.get_status(con, "docs", "nope.md")
    assert excinfo.value.code == "NOT_FOUND"


def test_pending_update_keeps_serving_old_ready_revision_status(con) -> None:
    """p02-review1.txt item 4: a pending (unpublished) newer head must not
    be reported as 'ready' — but the old ready generation is still
    searchable, labeled 'stale_ready', not silently dropped to
    not_indexed."""
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    gen_a = store.stage_generation(con, r1["revision_id"], "profile-v1", r1["revision_token"])
    pub_a = store.publish_generation(con, gen_a["generation_id"])

    r2 = store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", pub_a["revision_token"], b"v2"))
    status = store.get_status(con, "docs", "faq.md")
    assert status["head_revision_id"] == r2["revision_id"]
    assert status["ready_revision_id"] == r1["revision_id"]
    assert status["processing_status"] == "stale_ready"
    assert status["searchable"] is True


# ---------------------------------------------------------------- CAS token


def test_revision_token_roundtrip() -> None:
    token = store.encode_revision_token(42, 7)
    assert store.decode_revision_token(token) == (42, 7)


def test_revision_token_is_not_a_content_hash() -> None:
    token_a = store.encode_revision_token(1, 1)
    token_b = store.encode_revision_token(2, 1)
    assert token_a != token_b


def test_malformed_revision_token_rejected_cleanly(con) -> None:
    r1 = store.add(con, store.AddRequest(_rid(), "docs", "faq.md", b"v1"))
    with pytest.raises(store.ApiError) as excinfo:
        store.update(con, store.UpdateRequest(_rid(), "docs", "faq.md", "not-a-real-token", b"v2"))
    assert excinfo.value.code == "INVALID_REVISION_TOKEN"
