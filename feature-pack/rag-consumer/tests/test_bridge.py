from __future__ import annotations

import json
import os
import sqlite3
import struct
from dataclasses import asdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import pytest

from airag import api, embeddings, llm_enrichment
from airag.db import connect
from airag_consumer import bridge
from airag_consumer.events import AccessScope, parse_event
from airag_consumer.lifecycle import AuthenticatedScope, Lifecycle
from airag_consumer.redaction import redact_event


UTC = timezone.utc
TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"
COLLECTION = "airag-session-v1"


class Clock:
    def __init__(self, value: datetime) -> None:
        self.value = value

    def __call__(self) -> datetime:
        return self.value


def lifecycle_database() -> sqlite3.Connection:
    con = sqlite3.connect(":memory:", isolation_level=None)
    con.execute(
        """CREATE TABLE sources (
            source_id TEXT PRIMARY KEY, incarnation TEXT NOT NULL,
            tenant_id TEXT NOT NULL, project_id TEXT NOT NULL, stream_id TEXT NOT NULL,
            policy_version TEXT NOT NULL, next_offset INTEGER NOT NULL,
            chain_digest TEXT NOT NULL)"""
    )
    con.execute(
        """CREATE TABLE events (
            redacted_json BLOB NOT NULL, audit_rules TEXT NOT NULL,
            has_public_text INTEGER NOT NULL)"""
    )
    return con


def auth(
    owner: str = "owner", tenant: str = "tenant", project: str = "project",
    streams: tuple[str, ...] = ("stream",),
) -> AuthenticatedScope:
    return AuthenticatedScope(owner, tenant, project, streams)


def accepted(
    *, event_id: str, message_id: str, ordinal: int, content: str,
    occurred_at: str = "2026-01-01T00:00:00+00:00",
    tenant: str = "tenant", project: str = "project", stream: str = "stream",
):
    value = {
        "schema_version": 1, "event_id": event_id, "stream_id": stream,
        "message_id": message_id, "producer_epoch": "epoch",
        "source_version": 1, "source_ordinal": ordinal, "event_type": "create",
        "occurred_at": occurred_at, "ingested_at": occurred_at,
        "access_scope": {"tenant_id": tenant, "project_id": project},
        "role": "user", "content": content,
    }
    scope = AccessScope(tenant, project, stream)
    return redact_event(parse_event(json.dumps(value).encode(), expected_scope=scope))


def insert(con: sqlite3.Connection, item, *, source_id: str = "source") -> None:
    event = item.event
    row = con.execute(
        "SELECT next_offset FROM sources WHERE source_id=?", (source_id,),
    ).fetchone()
    if row is None:
        con.execute(
            "INSERT INTO sources VALUES (?,?,?,?,?,?,0,'')",
            (
                source_id, "incarnation", event.scope.tenant_id,
                event.scope.project_id, event.scope.stream_id, "r1",
            ),
        )
        offset = 0
    else:
        offset = row[0]
    con.execute(
        "INSERT INTO events VALUES (?,?,?)",
        (event.canonical_json, json.dumps(item.audit_rules), int(item.has_public_text)),
    )
    con.execute(
        "UPDATE sources SET next_offset=?,chain_digest=? WHERE source_id=?",
        (offset + 1, f"chain-{offset + 1}", source_id),
    )


def embedding_config() -> embeddings.EmbeddingSpaceConfig:
    return embeddings.EmbeddingSpaceConfig(
        "openai-compatible", "http://127.0.0.1:9/v1", "fixture-embed",
        "fixture-revision", 4, tokenizer_revision=TOKENIZER_REVISION,
    )


def vectors(_config, texts, **_kwargs):
    return [struct.pack("4f", 1, 0, 0, 0) for _ in texts]


def projection(tmp_path: Path, name: str = "projection"):
    key = os.urandom(32)
    source_path = tmp_path / f"{name}-profile-source.db"
    source = connect.init_db(source_path, key)
    registered = api.register_profile(
        source, {"embedding": asdict(embedding_config())},
    )
    assert registered["ok"], registered
    profile_key = registered["data"]["profile_key"]
    source.close()
    readonly = connect.open_readonly(source_path, key)
    target = connect.init_db(tmp_path / f"{name}.db", os.urandom(32))
    installed = bridge.install_captured_profile(readonly, target, profile_key)
    readonly.close()
    assert installed["profile_key"] == profile_key
    return target, profile_key


def test_exact_profile_copy_preserves_llm_descriptor_and_rejects_override(tmp_path):
    key = os.urandom(32)
    source_path = tmp_path / "source.db"
    source = connect.init_db(source_path, key)
    llm = llm_enrichment.ChatCompletionConfig(
        "openai-compatible", "http://127.0.0.1:9/v1", "fixture-llm",
        "weights-sha", 4096,
    )
    registered = api.register_profile(source, {
        "embedding": asdict(embedding_config()),
        "llm": asdict(llm),
        "normalizer": {"conversation": "captured"},
    })
    assert registered["ok"], registered
    profile_key = registered["data"]["profile_key"]
    source_row = source.execute(
        "SELECT normalizer_config,chunker_config FROM processing_profiles WHERE profile_key=?",
        (profile_key,),
    ).fetchone()
    source.close()

    readonly = connect.open_readonly(source_path, key)
    target = connect.init_db(tmp_path / "target.db", os.urandom(32))
    receipt = bridge.install_captured_profile(readonly, target, profile_key)
    assert receipt["profile_key"] == profile_key
    assert receipt["llm_enrichment"] is True
    assert target.execute(
        "SELECT normalizer_config,chunker_config FROM processing_profiles WHERE profile_key=?",
        (profile_key,),
    ).fetchone() == source_row
    assert bridge.install_captured_profile(
        readonly, target, profile_key,
        endpoint_override=embedding_config().endpoint,
    )["profile_key"] == profile_key
    with pytest.raises(bridge.BridgeError, match="ENDPOINT_OVERRIDE_UNSUPPORTED"):
        bridge.install_captured_profile(
            readonly, target, profile_key,
            endpoint_override="http://127.0.0.1:9999/v1",
        )
    readonly.close()
    target.close()


def test_profile_copy_rolls_back_when_target_space_id_would_change_key(tmp_path):
    key = os.urandom(32)
    source_path = tmp_path / "source-shift.db"
    source = connect.init_db(source_path, key)
    registered = api.register_profile(
        source, {"embedding": asdict(embedding_config())},
    )
    profile_key = registered["data"]["profile_key"]
    source.close()
    readonly = connect.open_readonly(source_path, key)

    target = connect.init_db(tmp_path / "target-shift.db", os.urandom(32))
    different = embedding_config()
    shifted = embeddings.EmbeddingSpaceConfig(
        different.provider, different.endpoint, "different-model",
        "different-revision", different.dimension,
        tokenizer_revision=different.tokenizer_revision,
    )
    occupied = api.register_profile(target, {"embedding": asdict(shifted)})
    assert occupied["ok"], occupied
    assert occupied["data"]["profile_key"] == profile_key  # DB-local space_id collision
    before_spaces = target.execute("SELECT COUNT(*) FROM embedding_spaces").fetchone()
    before_profiles = target.execute("SELECT COUNT(*) FROM processing_profiles").fetchone()
    before_collision = target.execute(
        "SELECT space_id,normalizer_config,chunker_config FROM processing_profiles "
        "WHERE profile_key=?", (profile_key,),
    ).fetchone()
    with pytest.raises(bridge.BridgeError, match="PROFILE_KEY_MISMATCH"):
        bridge.install_captured_profile(readonly, target, profile_key)
    assert target.execute("SELECT COUNT(*) FROM embedding_spaces").fetchone() == before_spaces
    assert target.execute("SELECT COUNT(*) FROM processing_profiles").fetchone() == before_profiles
    assert target.execute(
        "SELECT space_id,normalizer_config,chunker_config FROM processing_profiles "
        "WHERE profile_key=?", (profile_key,),
    ).fetchone() == before_collision
    readonly.close()
    target.close()


def test_crash_during_retry_recovers_after_lease_expiry(tmp_path):
    core, profile_key = projection(tmp_path, "retry-crash")
    ledger = lifecycle_database()
    scope = auth()
    insert(ledger, accepted(event_id="e1", message_id="m1", ordinal=1, content="retry crash"))
    runtime = Lifecycle(ledger, clock=Clock(datetime(2026, 1, 2, tzinfo=UTC)),
                        token_mode="exact", tokenizer=lambda _: 1)
    failure = embeddings.EmbeddingError("PROVIDER_UNREACHABLE", "synthetic", retryable=True)
    with patch("airag.embeddings.embed_documents", side_effect=failure):
        first = bridge.publish_pending_windows(runtime, scope, core, collection=COLLECTION,
                                               profile_key=profile_key, explicit_save=True)
    assert not first[0]["ok"]
    with patch("airag.pipeline.process_and_publish", side_effect=RuntimeError("retry interrupted")):
        with pytest.raises(RuntimeError, match="retry interrupted"):
            bridge.publish_pending_windows(runtime, scope, core, collection=COLLECTION,
                                           profile_key=profile_key)
    core.execute("UPDATE jobs SET lease_expires_at_ms=0 WHERE status='running'")
    core.commit()
    with patch("airag.embeddings.embed_documents", side_effect=vectors) as provider:
        recovered = bridge.publish_pending_windows(runtime, scope, core, collection=COLLECTION,
                                                   profile_key=profile_key)
        calls = provider.call_count
        replay = bridge.publish_pending_windows(runtime, scope, core, collection=COLLECTION,
                                                profile_key=profile_key)
    assert recovered[0]["ok"] and recovered[0]["action"] == "retry"
    assert calls > 0 and replay == []
    assert runtime.state(scope)["searchable_window_ids"]


def test_new_stream_enrollment_does_not_reject_existing_window(tmp_path):
    core, profile_key = projection(tmp_path, "enrollment")
    ledger = lifecycle_database()
    first_scope = auth()
    insert(ledger, accepted(event_id="e1", message_id="m1", ordinal=1, content="old enrolled stream"))
    runtime = Lifecycle(ledger, clock=Clock(datetime(2026, 1, 2, tzinfo=UTC)),
                        token_mode="exact", tokenizer=lambda _: 1)
    runtime.refresh(first_scope, explicit_save=True)
    expanded = AuthenticatedScope(
        first_scope.owner_id, first_scope.tenant_id, first_scope.project_id,
        (*first_scope.enrolled_streams, "new-enrolled-stream"),
    )
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        result = bridge.publish_pending_windows(runtime, expanded, core, collection=COLLECTION,
                                                profile_key=profile_key)
    assert result and all(item["ok"] for item in result)


def test_crash_after_core_publish_replays_without_duplicate_or_provider_call(
    tmp_path, monkeypatch,
):
    core, profile_key = projection(tmp_path, "crash")
    ledger = lifecycle_database()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    scope = auth()
    insert(ledger, accepted(
        event_id="e1", message_id="m1", ordinal=1, content="durable history",
    ))
    runtime = Lifecycle(ledger, clock=clock, token_mode="exact", tokenizer=lambda _: 1)

    def crash(*_args, **_kwargs):
        raise RuntimeError("synthetic crash after core publish")

    monkeypatch.setattr(runtime, "finish_publication", crash)
    with patch("airag.embeddings.embed_documents", side_effect=vectors) as provider:
        with pytest.raises(RuntimeError, match="synthetic crash"):
            bridge.publish_pending_windows(
                runtime, scope, core, collection=COLLECTION,
                profile_key=profile_key, explicit_save=True,
            )
    provider.assert_called_once()
    monkeypatch.undo()

    with patch(
        "airag.embeddings.embed_documents",
        side_effect=AssertionError("provider replayed after completed core publish"),
    ) as provider:
        replay = bridge.publish_pending_windows(
            runtime, scope, core, collection=COLLECTION, profile_key=profile_key,
        )
    provider.assert_not_called()
    assert replay[0]["ok"] and replay[0]["action"] == "ready_replay"
    window_id = replay[0]["window_id"]
    assert replay[0]["source_key"] == bridge.source_key_for_window(window_id) == window_id
    assert core.execute("SELECT COUNT(*) FROM sources").fetchone() == (1,)
    assert core.execute("SELECT COUNT(*) FROM source_revisions").fetchone() == (1,)
    assert core.execute("SELECT COUNT(*) FROM generations").fetchone() == (1,)
    links = bridge.verify_projection_links(
        runtime.state(scope), core, collection=COLLECTION, profile_key=profile_key,
    )
    assert links[window_id]["source_key"] == window_id
    core.close()


def test_provider_failure_uses_core_retry_job_and_becomes_searchable(tmp_path):
    core, profile_key = projection(tmp_path, "retry")
    ledger = lifecycle_database()
    scope = auth()
    insert(ledger, accepted(
        event_id="e1", message_id="m1", ordinal=1, content="retry history",
    ))
    runtime = Lifecycle(
        ledger, clock=Clock(datetime(2026, 1, 2, tzinfo=UTC)),
        token_mode="exact", tokenizer=lambda _: 1,
    )
    failure = embeddings.EmbeddingError(
        "PROVIDER_UNREACHABLE", "synthetic provider failure", retryable=True,
    )
    with patch("airag.embeddings.embed_documents", side_effect=failure):
        failed = bridge.publish_pending_windows(
            runtime, scope, core, collection=COLLECTION,
            profile_key=profile_key, explicit_save=True,
        )
    assert failed[0]["ok"] is False
    assert failed[0]["error"]["code"] == "PROVIDER_UNREACHABLE"
    assert runtime.state(scope)["windows"][0]["publication_state"] == "failed"

    with patch("airag.embeddings.embed_documents", side_effect=vectors) as provider:
        recovered = bridge.publish_pending_windows(
            runtime, scope, core, collection=COLLECTION, profile_key=profile_key,
        )
    provider.assert_called_once()
    assert recovered[0]["ok"] and recovered[0]["action"] == "retry"
    assert core.execute("SELECT COUNT(*) FROM sources").fetchone() == (1,)
    assert core.execute("SELECT COUNT(*) FROM source_revisions").fetchone() == (1,)
    assert core.execute("SELECT COUNT(*) FROM jobs").fetchone() == (2,)
    assert runtime.state(scope)["searchable_window_ids"] == [recovered[0]["window_id"]]
    core.close()


def test_actual_core_hybrid_search_includes_older_history_and_excludes_foreign(
    tmp_path,
):
    core, profile_key = projection(tmp_path, "search")
    ledger = lifecycle_database()
    scope = auth()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    runtime = Lifecycle(
        ledger, clock=clock, active_window_count=1,
        token_mode="exact", tokenizer=lambda _: 1,
    )
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        insert(ledger, accepted(
            event_id="e1", message_id="m1", ordinal=1,
            content="first-history-marker resolved",
        ))
        first = bridge.publish_pending_windows(
            runtime, scope, core, collection=COLLECTION,
            profile_key=profile_key, explicit_save=True,
        )[0]["window_id"]
        insert(ledger, accepted(
            event_id="e2", message_id="m2", ordinal=2,
            content="recent unrelated note",
        ))
        second = bridge.publish_pending_windows(
            runtime, scope, core, collection=COLLECTION,
            profile_key=profile_key, explicit_save=True,
        )[0]["window_id"]
        foreign = "win:" + "f" * 64
        foreign_add = api.add(
            core, "foreign-add", COLLECTION, foreign,
            json.dumps({"turns": [{"id": "foreign", "role": "user",
                                  "text": "first-history-marker foreign"}]}).encode(),
            media_type="application/x-airag-conversation+json",
            origin_uri=f"airag-window:{foreign}", profile_key=profile_key,
        )
        assert foreign_add["ok"], foreign_add

    state = runtime.state(scope)
    assert state["older_searchable_window_ids"] == [first]
    assert state["active_window_ids"] == [second]
    with patch(
        "airag.embeddings.embed_query",
        return_value=struct.pack("4f", 1, 0, 0, 0),
    ):
        result = bridge.search_history(
            runtime, scope, core, collection=COLLECTION,
            profile_key=profile_key, query="first-history-marker", top_k=5,
        )
    assert result["ranking"]["mode"] == "core_hybrid"
    assert result["eligible_window_ids"] == [first, second]
    assert all(item["source_key"] != foreign for item in result["results"])
    assert any(item["source_key"] == first for item in result["results"])
    hit = next(item for item in result["results"] if item["source_key"] == first)
    assert hit["message_anchors"]
    assert hit["message_anchors"][0]["turn_id"].startswith("msg:")
    assert hit["core_receipt"]["manifest_id"] == result["core_manifests"][0]["manifest_id"]
    core.close()


def test_current_clock_change_during_actual_search_rejects_stale_results(tmp_path):
    core, profile_key = projection(tmp_path, "expiry")
    ledger = lifecycle_database()
    created = datetime(2026, 1, 1, tzinfo=UTC)
    clock = Clock(created + timedelta(days=1))
    scope = auth()
    insert(ledger, accepted(
        event_id="e1", message_id="m1", ordinal=1, content="expiring history",
        occurred_at=created.isoformat(),
    ))
    runtime = Lifecycle(ledger, clock=clock, token_mode="exact", tokenizer=lambda _: 1)
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        published = bridge.publish_pending_windows(
            runtime, scope, core, collection=COLLECTION,
            profile_key=profile_key, explicit_save=True,
        )
    assert published[0]["ok"]
    real_search = bridge.core_api.search

    def search_then_expire(*args, **kwargs):
        result = real_search(*args, **kwargs)
        clock.value = created + timedelta(days=91)
        return result

    with patch.object(bridge.core_api, "search", side_effect=search_then_expire), patch(
        "airag.embeddings.embed_query",
        return_value=struct.pack("4f", 1, 0, 0, 0),
    ):
        with pytest.raises(bridge.BridgeError, match="ELIGIBILITY_CHANGED"):
            bridge.search_history(
                runtime, scope, core, collection=COLLECTION,
                profile_key=profile_key, query="expiring", top_k=5,
            )
    assert runtime.state(scope)["searchable_window_ids"] == []
    core.close()


def test_partitioned_search_uses_bounded_labelled_core_api_double(monkeypatch):
    """The double isolates the >100 partition policy; other tests use real core."""
    window_ids = ["win:" + f"{index:064x}" for index in range(205)]
    scope = auth()

    class FakeLifecycle:
        def refresh(self, _scope):
            return {"searchable_window_ids": list(window_ids)}

    calls = []

    def fake_search(
        _con, collection, query, profile_key, *, top_k, request_id, source_keys,
    ):
        calls.append(tuple(source_keys))
        index = len(calls)
        return {
            "ok": True, "request_id": request_id, "error": None,
            "data": {
                "manifest_id": index, "profile_key": profile_key,
                "eligible": {"count": len(source_keys), "sources": []},
                "results": [{
                    "chunk_id": index, "source_key": source_keys[0],
                    "source_id": index, "revision_id": index,
                    "generation_id": index, "content_hash": str(index),
                    "anchor": {"items": []},
                }],
            },
        }

    monkeypatch.setattr(bridge, "verify_projection_links", lambda *_args, **_kwargs: {})
    monkeypatch.setattr(bridge.core_api, "search", fake_search)
    result = bridge.search_history(
        FakeLifecycle(), scope, object(), collection=COLLECTION,
        profile_key="a" * 64, query="bounded", top_k=3,
    )
    assert [len(call) for call in calls] == [100, 100, 5]
    assert {item for call in calls for item in call} == set(window_ids)
    assert result["ranking"]["mode"] == "partitioned_core_hybrid_bridge_rrf"
    assert result["ranking"]["limitations"]


def test_nonretryable_publication_waits_for_explicit_core_retry(tmp_path):
    core, profile_key = projection(tmp_path, "terminal")
    ledger = lifecycle_database()
    scope = auth()
    insert(ledger, accepted(event_id="e1", message_id="m1", ordinal=1, content="terminal history"))
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    runtime = Lifecycle(ledger, clock=clock, token_mode="exact", tokenizer=lambda _: 1)
    failure = embeddings.EmbeddingError("PROVIDER_BAD_RESPONSE", "synthetic invalid response", retryable=False)
    with patch("airag.embeddings.embed_documents", side_effect=failure):
        first = bridge.publish_pending_windows(runtime, scope, core, collection=COLLECTION,
                                               profile_key=profile_key, explicit_save=True)
    assert first[0]["ok"] is False
    snapshot = core.execute("SELECT job_id,final_response_json FROM jobs").fetchone()
    restarted = Lifecycle(ledger, clock=clock, token_mode="exact", tokenizer=lambda _: 1)
    with patch("airag.embeddings.embed_documents", side_effect=AssertionError("terminal retry")) as provider:
        blocked = bridge.publish_pending_windows(restarted, scope, core, collection=COLLECTION,
                                                 profile_key=profile_key)
    provider.assert_not_called()
    assert blocked[0]["action"] == "terminal_failure"
    assert blocked[0]["error"]["retryable"] is False
    assert core.execute("SELECT count(*) FROM jobs").fetchone() == (1,)
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        repaired = api.retry(core, "explicit-operator-retry", snapshot[0], profile_key=profile_key)
    assert repaired["ok"], repaired
    recovered = bridge.publish_pending_windows(restarted, scope, core, collection=COLLECTION,
                                                profile_key=profile_key)
    assert recovered[0]["ok"] and recovered[0]["action"] == "ready_replay"
    assert core.execute("SELECT final_response_json FROM jobs WHERE job_id=?", (snapshot[0],)).fetchone()[0] == snapshot[1]
    core.close()
