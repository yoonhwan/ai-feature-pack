import json
import sqlite3
from datetime import datetime, timedelta, timezone

import pytest

from airag_consumer.archive import ArchiveReceipt, write_archive
from airag_consumer.events import AccessScope, EventError, parse_event
from airag_consumer.lifecycle import (
    AcceptedEvent,
    AuthenticatedScope,
    Lifecycle,
    LifecycleError,
    reduce_events,
)
from airag_consumer.redaction import redact_event


UTC = timezone.utc


class Clock:
    def __init__(self, value):
        self.value = value

    def __call__(self):
        return self.value


def database():
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


def auth(owner="owner", tenant="tenant", project="project", streams=("stream",)):
    return AuthenticatedScope(owner, tenant, project, streams)


def accepted(
    *, event_id, message_id, version, ordinal, event_type="create",
    occurred_at="2026-01-01T00:00:00+00:00", content="hello", role="user",
    tenant="tenant", project="project", stream="stream", epoch="epoch",
    **extra,
):
    payload = {
        "schema_version": 1,
        "event_id": event_id,
        "stream_id": stream,
        "message_id": message_id,
        "producer_epoch": epoch,
        "source_version": version,
        "source_ordinal": ordinal,
        "event_type": event_type,
        "occurred_at": occurred_at,
        "ingested_at": occurred_at,
        "access_scope": {"tenant_id": tenant, "project_id": project},
        **extra,
    }
    if event_type in {"create", "edit"}:
        payload.update(role=role, content=content)
    event_scope = AccessScope(tenant, project, stream)
    return redact_event(parse_event(json.dumps(payload).encode(), expected_scope=event_scope))


def insert(con, item, *, source_id="source"):
    event = item.event
    scope = event.scope
    row = con.execute("SELECT next_offset FROM sources WHERE source_id=?", (source_id,)).fetchone()
    if row is None:
        con.execute(
            "INSERT INTO sources VALUES (?,?,?,?,?,?,0,'')",
            (source_id, "incarnation", scope.tenant_id, scope.project_id, scope.stream_id, "r1"),
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


def publish(runtime, scope, window_id):
    claim = runtime.claim_publication(scope, window_id)
    assert claim["idempotency_key"] == window_id
    runtime.finish_publication(scope, window_id, success=True)


def test_reducer_orders_corrections_without_implicit_resurrection():
    scope = auth()
    create = accepted(event_id="e1", message_id="m", version=1, ordinal=1, content="one")
    edit_before_delete = accepted(
        event_id="e2", message_id="m", version=2, ordinal=2,
        event_type="edit", content="two",
    )
    delete = accepted(event_id="e3", message_id="m", version=3, ordinal=3, event_type="delete")
    late_edit = accepted(
        event_id="e4", message_id="m", version=4, ordinal=4,
        event_type="edit", content="four",
    )
    deleted = reduce_events(
        [late_edit, delete, create, edit_before_delete], scope=scope,
        now=datetime(2026, 1, 2, tzinfo=UTC),
    ).messages[0]
    assert deleted.content == "four"
    assert deleted.visible is False
    assert deleted.created_at == "2026-01-01T00:00:00+00:00"

    restore = accepted(event_id="e5", message_id="m", version=5, ordinal=5, event_type="restore")
    restored = reduce_events(
        [restore, late_edit, create, delete, edit_before_delete], scope=scope,
        now=datetime(2026, 1, 2, tzinfo=UTC),
    ).messages[0]
    assert restored.visible is True and restored.content == "four"
    assert [item["event_type"] for item in restored.history] == [
        "create", "edit", "delete", "edit", "restore",
    ]


def test_duplicate_input_is_idempotent_but_ambiguous_version_is_rejected():
    scope = auth()
    create = accepted(event_id="e1", message_id="m", version=1, ordinal=1)
    result = reduce_events(
        [create, create], scope=scope, now=datetime(2026, 1, 2, tzinfo=UTC),
    )
    assert len(result.messages) == 1
    ambiguous = accepted(
        event_id="e2", message_id="m", version=1, ordinal=2,
        event_type="edit", content="different",
    )
    with pytest.raises(EventError, match="AMBIGUOUS_MESSAGE_VERSION"):
        reduce_events([create, ambiguous], scope=scope, now=datetime(2026, 1, 2, tzinfo=UTC))


def test_open_tail_uses_oldest_age_and_continuous_messages_do_not_reset_it():
    con = database()
    clock = Clock(datetime(2026, 1, 1, 0, 4, 59, tzinfo=UTC))
    scope = auth()
    insert(con, accepted(event_id="e1", message_id="m1", version=1, ordinal=1))
    runtime = Lifecycle(con, clock=clock)
    assert runtime.refresh(scope)["created_window_ids"] == []
    insert(con, accepted(
        event_id="e2", message_id="m2", version=1, ordinal=2,
        occurred_at="2026-01-01T00:04:59+00:00", content="new",
    ))
    assert runtime.refresh(scope)["created_window_ids"] == []
    clock.value = datetime(2026, 1, 1, 0, 5, tzinfo=UTC)
    first = runtime.refresh(scope)
    assert len(first["created_window_ids"]) == 1
    window_id = first["created_window_ids"][0]
    assert first["windows"][0]["close_reason"] == "open_tail_age"
    again = runtime.refresh(scope)
    assert again["created_window_ids"] == []
    assert again["pending_publication_ids"] == [window_id]


def test_stable_window_publication_is_retryable_after_crash_and_failure():
    con = database()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    scope = auth()
    insert(con, accepted(event_id="e1", message_id="m1", version=1, ordinal=1))
    runtime = Lifecycle(con, clock=clock, token_mode="exact", tokenizer=lambda text: 1)
    window_id = runtime.refresh(scope, explicit_save=True)["created_window_ids"][0]
    first = runtime.claim_publication(scope, window_id)
    second = runtime.claim_publication(scope, window_id)
    assert first["window_id"] == second["window_id"] == window_id
    assert first["document"] == second["document"]
    assert second["attempt"] == 2
    runtime.finish_publication(scope, window_id, success=False, error_code="EMBEDDING_FAILED")
    assert runtime.state(scope)["pending_publication_ids"] == [window_id]
    assert runtime.claim_publication(scope, window_id)["attempt"] == 3
    runtime.finish_publication(scope, window_id, success=True)
    assert runtime.claim_publication(scope, window_id)["already_published"] is True
    assert runtime.refresh(scope)["created_window_ids"] == []


def test_correction_invalidates_stale_window_and_dependent_memory():
    con = database()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    scope = auth()
    insert(con, accepted(event_id="e1", message_id="m1", version=1, ordinal=1))
    runtime = Lifecycle(con, clock=clock)
    state = runtime.refresh(scope, explicit_save=True)
    old_window = state["created_window_ids"][0]
    publish(runtime, scope, old_window)
    anchor = state["reduction"]["eligible_message_keys"][0]
    memory = runtime.create_memory(
        scope, kind="decision", text="Use the verified path", anchor_ids=[anchor],
    )
    assert memory["approval_state"] == "rule_checked"

    insert(con, accepted(
        event_id="e2", message_id="m1", version=2, ordinal=2,
        event_type="edit", content="corrected",
    ))
    state = runtime.refresh(scope)
    assert state["windows"][0]["publication_state"] == "invalidated"
    assert len(state["created_window_ids"]) == 1
    assert state["created_window_ids"][0] != old_window
    assert state["visible_memory_ids"] == []
    assert state["memories"][0]["invalidated_reason"] == "source_changed"


def test_verified_solution_requires_proof_and_reopen_hides_it():
    con = database()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    scope = auth()
    insert(con, accepted(event_id="e1", message_id="m1", version=1, ordinal=1))
    runtime = Lifecycle(con, clock=clock)
    state = runtime.refresh(scope, explicit_save=True)
    anchor = state["reduction"]["eligible_message_keys"][0]
    with pytest.raises(EventError, match="VERIFIED_SOLUTION_PROOF_REQUIRED"):
        runtime.create_memory(
            scope, kind="verified_solution", text="fixed", anchor_ids=[anchor],
        )
    solution = runtime.create_memory(
        scope, kind="verified_solution", text="fixed", anchor_ids=[anchor],
        proof_anchor_ids=[anchor],
    )
    runtime.reopen_solution(scope, solution["memory_id"])
    state = runtime.state(scope)
    assert solution["memory_id"] not in state["visible_memory_ids"]
    assert state["memories"][0]["invalidated_reason"] == "solution_reopened"


def test_long_term_memory_requires_explicit_confirmation():
    con = database()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    scope = auth()
    insert(con, accepted(event_id="e1", message_id="m1", version=1, ordinal=1))
    runtime = Lifecycle(con, clock=clock)
    state = runtime.refresh(scope)
    anchor = state["reduction"]["eligible_message_keys"][0]
    with pytest.raises(EventError, match="EXPLICIT_MEMORY_CONFIRMATION_REQUIRED"):
        runtime.create_memory(scope, kind="preference", text="Prefer terse output", anchor_ids=[anchor])
    memory = runtime.create_memory(
        scope, kind="preference", text="Prefer terse output", anchor_ids=[anchor],
        explicit_confirmation=True,
    )
    assert memory["approval_state"] == "human_validated"
    with pytest.raises(EventError, match="AUTOMATIC_MEMORY_CANNOT_CLAIM_HUMAN_VALIDATION"):
        runtime.create_memory(
            scope, kind="progress", text="half done", anchor_ids=[anchor],
            explicit_confirmation=True,
        )


def test_scope_and_owner_isolation_are_fail_closed():
    con = database()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    first = auth(owner="alice")
    insert(con, accepted(event_id="e1", message_id="m1", version=1, ordinal=1))
    runtime = Lifecycle(con, clock=clock)
    window_id = runtime.refresh(first, explicit_save=True)["created_window_ids"][0]
    publish(runtime, first, window_id)
    other_owner = auth(owner="bob")
    assert runtime.state(other_owner)["searchable_window_ids"] == []
    runtime.refresh(other_owner)
    with pytest.raises(EventError, match="WINDOW_NOT_FOUND_OR_SCOPE_DENIED"):
        runtime.finish_publication(other_owner, window_id, success=True)

    foreign = accepted(
        event_id="foreign", message_id="foreign", version=1, ordinal=1,
        project="other-project",
    )
    insert(con, foreign, source_id="foreign-source")
    state = runtime.refresh(first)
    assert len(state["reduction"]["messages"]) == 1


def test_recent_four_are_separate_from_older_still_searchable_windows():
    con = database()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    scope = auth()
    runtime = Lifecycle(con, clock=clock)
    window_ids = []
    for number in range(6):
        insert(con, accepted(
            event_id=f"e{number}", message_id=f"m{number}", version=1,
            ordinal=number + 1, content=f"message {number}",
        ))
        state = runtime.refresh(scope, explicit_save=True)
        window_id = state["created_window_ids"][0]
        publish(runtime, scope, window_id)
        window_ids.append(window_id)
    state = runtime.state(scope)
    assert state["older_searchable_window_ids"] == window_ids[:2]
    assert state["active_window_ids"] == window_ids[2:]
    assert state["archive_only_expiry_candidates"] == []


def test_current_time_restore_gate_expires_old_windows_and_pinned_memory_c15(tmp_path):
    con = database()
    created = datetime(2026, 1, 1, tzinfo=UTC)
    clock = Clock(created + timedelta(days=89))
    scope = auth()
    insert(con, accepted(
        event_id="e1", message_id="m1", version=1, ordinal=1,
        occurred_at=created.isoformat(),
    ))
    runtime = Lifecycle(con, clock=clock)
    state = runtime.refresh(scope, explicit_save=True)
    window_id = state["created_window_ids"][0]
    publish(runtime, scope, window_id)
    anchor = state["reduction"]["eligible_message_keys"][0]
    memory = runtime.create_memory(
        scope, kind="decision", text="keep this", anchor_ids=[anchor], pinned=True,
    )
    assert memory["memory_id"] in runtime.state(scope)["visible_memory_ids"]

    # Simulate restoring a backup that still considered the record active.
    clock.value = created + timedelta(days=91)
    stale = runtime.state(scope)
    assert stale["read_gate"]["open"] is False
    assert stale["read_gate"]["closed_reason"] == "retention_boundary_reached"
    assert stale["searchable_window_ids"] == []
    assert stale["visible_memory_ids"] == []
    with pytest.raises(EventError, match="CURRENT_TIME_EXPIRY_PASS_REQUIRED"):
        runtime.claim_publication(scope, window_id)

    reconciled = runtime.refresh(scope)
    assert reconciled["read_gate"]["open"] is True
    assert reconciled["searchable_window_ids"] == []
    assert reconciled["visible_memory_ids"] == []
    assert reconciled["memories"][0]["pinned"] is True
    assert reconciled["memories"][0]["invalidated_reason"] == "source_expired"
    candidates = reconciled["archive_only_expiry_candidates"]
    assert {item["entity_type"] for item in candidates} == {"message", "memory"}
    assert {item["lookup_mode"] for item in candidates} == {"explicit_archive_only"}
    assert all(
        set(item["record"]) == {"kind", "id", "scope", "payload"}
        for item in candidates
    )
    records = sorted((item["record"] for item in candidates), key=lambda item: item["id"])
    archive_scope = candidates[0]["archive_scope"]
    with pytest.raises(EventError, match="ARCHIVE_RECEIPT_CONTENT_MISMATCH"):
        runtime.confirm_archive(
            scope, candidate_ids=[item["candidate_id"] for item in candidates],
            receipt=ArchiveReceipt("0" * 64, "/archive/fake.db", len(records), "1" * 64),
        )
    receipt = write_archive(
        tmp_path, b"a" * 32, AccessScope(*archive_scope), records,
    )
    runtime.confirm_archive(
        scope, candidate_ids=[item["candidate_id"] for item in candidates],
        receipt=receipt,
    )
    assert con.execute("SELECT count(*) FROM events").fetchone() == (1,)


def test_read_gate_closes_when_ledger_checkpoint_changes_until_refresh():
    con = database()
    clock = Clock(datetime(2026, 1, 2, tzinfo=UTC))
    scope = auth()
    insert(con, accepted(event_id="e1", message_id="m1", version=1, ordinal=1))
    runtime = Lifecycle(con, clock=clock)
    window_id = runtime.refresh(scope, explicit_save=True)["created_window_ids"][0]
    publish(runtime, scope, window_id)
    insert(con, accepted(event_id="e2", message_id="m2", version=1, ordinal=2))
    state = runtime.state(scope)
    assert state["read_gate"] == {
        "open": False,
        "closed_reason": "ledger_checkpoint_changed",
        "reconciled_at": "2026-01-02T00:00:00+00:00",
        "expiry_valid_until": "2026-04-01T00:00:00+00:00",
    }
    assert state["searchable_window_ids"] == []
    assert runtime.refresh(scope)["read_gate"]["open"] is True


def test_exact_token_mode_requires_callback():
    con = database()
    with pytest.raises(LifecycleError, match="EXACT_TOKENIZER_REQUIRED"):
        Lifecycle(con, clock=lambda: datetime.now(UTC), token_mode="exact")
