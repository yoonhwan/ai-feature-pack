from __future__ import annotations

import importlib.util
import sys
from dataclasses import asdict
from pathlib import Path
from unittest.mock import patch

import pytest

from airag import api, embeddings
from airag.db import connect


_SPEC = importlib.util.spec_from_file_location(
    "explicit_consumer_example", Path(__file__).resolve().parents[1] / "examples" / "explicit_consumer.py"
)
_EXAMPLE = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = _EXAMPLE
_SPEC.loader.exec_module(_EXAMPLE)
SourceEvent, handle_event = _EXAMPLE.SourceEvent, _EXAMPLE.handle_event


@pytest.fixture
def consumer_db(tmp_path, key_bytes):
    con = connect.init_db(tmp_path / "consumer.db", key_bytes)
    yield con
    con.close()


def _rows(con):
    return tuple(con.execute(f"SELECT * FROM {table}").fetchall()
                 for table in ("sources", "source_revisions", "jobs", "generations", "request_ledger"))


def test_explicit_events_preserve_identity_and_external_file(consumer_db, tmp_path):
    con = consumer_db
    external = tmp_path / "external.txt"
    external.write_text("consumer-owned file", encoding="utf-8")
    added = handle_event(con, SourceEvent("e1", "add", "docs", "stable-id", b"first", origin_uri=external.as_uri()))
    assert added["ok"], added
    changed = handle_event(con, SourceEvent("e2", "update", "docs", "stable-id", b"changed",
                                           expected_revision=added["data"]["revision_token"], origin_uri=external.as_uri()))
    assert changed["ok"], changed
    assert changed["data"]["source_id"] == added["data"]["source_id"]
    deleted = handle_event(con, SourceEvent("e3", "delete", "docs", "stable-id",
                                           expected_revision=changed["data"]["revision_token"]))
    assert deleted["ok"], deleted
    assert api.status(con, "docs", "stable-id")["data"]["deleted"]
    assert external.read_text() == "consumer-owned file"
    restored = handle_event(con, SourceEvent("e4", "restore", "docs", "stable-id",
                                            expected_revision=deleted["data"]["revision_token"]))
    assert restored["ok"], restored
    assert not api.status(con, "docs", "stable-id")["data"]["deleted"]
    assert con.execute("SELECT COUNT(*) FROM source_revisions").fetchone() == (2,)


@pytest.mark.parametrize("observation", ["unavailable", "incomplete_listing", "missing"])
def test_observations_never_become_mutation_or_deletion(consumer_db, observation):
    con = consumer_db
    assert handle_event(con, SourceEvent("add", "add", "docs", "source", b"retained"))["ok"]
    before = _rows(con)
    with patch("airag.api.delete", side_effect=AssertionError("implicit delete forbidden")), \
         patch("airag.api.update", side_effect=AssertionError("implicit update forbidden")), \
         patch("airag.api.add", side_effect=AssertionError("implicit add forbidden")):
        result = handle_event(con, SourceEvent("observation", observation, "docs", "source"))
    assert result["ok"] and result["data"]["ignored"]
    assert _rows(con) == before


def test_event_id_replay_is_immutable_and_reuse_for_new_content_is_rejected(consumer_db):
    con = consumer_db
    event = SourceEvent("stable-event-id", "add", "docs", "source", b"original")
    first = handle_event(con, event)
    assert first["ok"]
    before = _rows(con)
    replay = handle_event(con, event)
    assert replay["ok"] and replay["data"].pop("idempotent_replay") is True
    assert replay == first
    assert _rows(con) == before
    conflict = handle_event(con, SourceEvent("stable-event-id", "add", "docs", "source", b"different"))
    assert not conflict["ok"] and conflict["error"]["code"] == "IDEMPOTENCY_MISMATCH"
    assert _rows(con) == before


def test_stale_revision_event_is_not_silently_refreshed(consumer_db):
    con = consumer_db
    first = handle_event(con, SourceEvent("add", "add", "docs", "source", b"original"))
    old_token = first["data"]["revision_token"]
    changed = handle_event(con, SourceEvent("change", "update", "docs", "source", b"new", expected_revision=old_token))
    assert changed["ok"]
    before = _rows(con)
    result = handle_event(con, SourceEvent("stale-delete", "delete", "docs", "source", expected_revision=old_token))
    assert not result["ok"]
    assert _rows(con) == before
    assert not api.status(con, "docs", "source")["data"]["deleted"]


def test_tombstone_cannot_be_revived_by_add_update_retry_or_reindex(consumer_db):
    con = consumer_db
    cfg = embeddings.EmbeddingSpaceConfig("openai-compatible", "http://localhost:9999/v1", "fixture", "rev", 4,
                                           tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3")
    profile = api.register_profile(con, {"embedding": asdict(cfg)})["data"]["profile_key"]
    added = handle_event(con, SourceEvent("add", "add", "docs", "source", b"original"))
    deleted = handle_event(con, SourceEvent("delete", "delete", "docs", "source", expected_revision=added["data"]["revision_token"]))
    assert deleted["ok"]
    token = deleted["data"]["revision_token"]
    before = _rows(con)
    with patch("airag.embeddings.embed_documents", side_effect=AssertionError("deleted source processing forbidden")):
        attempts = [
            handle_event(con, SourceEvent("new-add", "add", "docs", "source", b"new", profile_key=profile)),
            handle_event(con, SourceEvent("new-update", "update", "docs", "source", b"new", expected_revision=token, profile_key=profile)),
            api.retry(con, "retry", added["data"]["job_id"], profile_key=profile),
            api.reindex(con, "reindex", "docs", "source", token, profile_key=profile),
        ]
    assert all(not result["ok"] for result in attempts), attempts
    assert _rows(con) == before
    assert api.status(con, "docs", "source")["data"]["deleted"]
    restored = handle_event(con, SourceEvent("explicit-restore", "restore", "docs", "source", expected_revision=token))
    assert restored["ok"]
    assert not api.status(con, "docs", "source")["data"]["deleted"]


def test_missing_or_unknown_event_data_does_not_infer_add_or_delete(consumer_db):
    con = consumer_db
    before = _rows(con)
    unknown = handle_event(con, SourceEvent("unknown", "scan-diff", "docs"))
    absent_content = handle_event(con, SourceEvent("bad-add", "add", "docs", "source"))
    absent_revision = handle_event(con, SourceEvent("bad-delete", "delete", "docs", "source"))
    assert not unknown["ok"] and not absent_content["ok"] and not absent_revision["ok"]
    assert _rows(con) == before


@pytest.mark.parametrize("event_id", [None, 1, [], "", "   "])
def test_observation_requires_valid_event_identity(consumer_db, event_id):
    con = consumer_db
    before = _rows(con)
    result = handle_event(con, SourceEvent(event_id, "missing", "docs", "source"))
    assert not result["ok"] and result["error"]["code"] == "VALIDATION_ERROR"
    assert _rows(con) == before
