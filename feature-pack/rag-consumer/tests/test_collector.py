from __future__ import annotations

from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path

import pytest

import airag_consumer.collector as collector
from airag_consumer.collector import CONTENT_PART_SEPARATOR, collect_codex_rollout
from airag_consumer.events import AccessScope, EventError
from airag_consumer.ledger import open_ledger


KEY = b"c" * 32
SESSION = "synthetic-session-01"


def native_line(record: dict) -> bytes:
    return json.dumps(record, ensure_ascii=False, separators=(",", ":")).encode() + b"\n"


def session_meta(*, session_id: str = SESSION, ordinal: int = 0) -> dict:
    return {
        "timestamp": "2026-09-27T00:00:00Z",
        "ordinal": ordinal,
        "type": "session_meta",
        "payload": {"id": session_id},
    }


def message(
    ordinal: int, message_id: str, role: str, texts: list[str], *,
    phase: str | None = None, timestamp: str = "2026-09-27T00:00:01.123Z",
    part_type: str | None = None,
) -> dict:
    payload = {
        "type": "message",
        "id": message_id,
        "role": role,
        "content": [
            {"type": part_type or ("input_text" if role == "user" else "output_text"), "text": text}
            for text in texts
        ],
    }
    if phase is not None:
        payload["phase"] = phase
    return {"timestamp": timestamp, "ordinal": ordinal, "type": "response_item", "payload": payload}


@pytest.fixture
def collector_scope():
    return AccessScope("synthetic", "airag-collector", SESSION)


def write_rollout(path: Path, *records: dict) -> bytes:
    data = b"".join(native_line(record) for record in records)
    path.write_bytes(data)
    return data


def run_collect(ledger, path: Path, scope: AccessScope, **kwargs):
    return collect_codex_rollout(
        ledger,
        source_path=path,
        allowed_real_paths=(path,),
        source_id="synthetic-rollout",
        expected_session_id=SESSION,
        expected_scope=scope,
        clock=lambda: datetime(2026, 9, 27, 1, 2, 3, tzinfo=timezone.utc),
        **kwargs,
    )


def stored_events(ledger) -> list[dict]:
    events = [json.loads(row[0]) for row in ledger._con.execute(
        "SELECT redacted_json FROM events"
    ).fetchall()]
    return sorted(events, key=lambda event: event["source_ordinal"])


def test_selects_messages_and_audits_excluded_native_records(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    write_rollout(
        path,
        session_meta(),
        {"timestamp": "2026-09-27T00:00:01Z", "ordinal": 1, "type": "event_msg", "payload": {}},
        {"timestamp": "2026-09-27T00:00:02Z", "ordinal": 2, "type": "response_item", "payload": {"type": "reasoning", "summary": "must not persist"}},
        message(3, "developer-1", "developer", ["must not persist"]),
        message(4, "user-1", "user", ["hello"]),
        message(5, "assistant-1", "assistant", ["world"], phase="final_answer"),
        message(6, "assistant-2", "assistant", ["progress"], phase="commentary"),
        {"timestamp": "2026-09-27T00:00:07Z", "ordinal": 7, "type": "token_usage_record", "payload": {"private": "must not persist"}},
        {"timestamp": "2026-09-27T00:00:08Z", "ordinal": 8, "type": "inter_agent_communication_metadata", "payload": {"private": "must not persist"}},
    )
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        result = run_collect(ledger, path, collector_scope)
        assert (result.accepted_count, result.skipped_count, result.gap_count) == (3, 6, 0)
        assert result.complete_through_snapshot
        assert result.coverage_complete
        assert [event["message_id"] for event in stored_events(ledger)] == [
            "user-1", "assistant-1", "assistant-2",
        ]
        durable = " ".join(
            str(value)
            for row in ledger._con.execute(
                "SELECT reason_code,event_id,message_id FROM airag_rollout_collector_plans"
            ).fetchall()
            for value in row if value is not None
        )
        assert "must not persist" not in durable


@pytest.mark.parametrize("phase", [None, "analysis", "final"])
def test_unverified_assistant_phase_fails_closed(tmp_path, collector_scope, phase):
    path = tmp_path / "rollout.jsonl"
    write_rollout(path, session_meta(), message(1, "assistant-1", "assistant", ["body"], phase=phase))
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        with pytest.raises(EventError, match="UNVERIFIED_ASSISTANT_PHASE"):
            run_collect(ledger, path, collector_scope)
        assert ledger._con.execute("SELECT count(*) FROM events").fetchone() == (0,)


def test_preserves_original_timestamp_and_content_part_boundaries(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    stamp = "2026-09-27T12:34:56.789+09:00"
    write_rollout(path, session_meta(), message(1, "user-1", "user", ["first", "second"], timestamp=stamp))
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        run_collect(ledger, path, collector_scope)
        event = stored_events(ledger)[0]
        assert event["occurred_at"] == stamp
        assert event["ingested_at"] == "2026-09-27T01:02:03Z"
        assert event["content"] == f"first{CONTENT_PART_SEPARATOR}second"
        expected_id = hashlib.sha256(json.dumps(
            [SESSION, event["producer_epoch"], "user-1", "create", 1],
            ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        ).encode()).hexdigest()
        assert event["event_id"] == expected_id and event["source_ordinal"] == 1


def test_partial_utf8_and_unterminated_tail_remain_pending(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    meta = native_line(session_meta())
    second = native_line(message(1, "user-1", "user", ["한글 body"]))
    path.write_bytes(meta + second)
    split = len(meta) + second.index("한".encode()) + 1
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        first = run_collect(ledger, path, collector_scope, captured_byte_limit=split)
        assert first.accepted_count == 0 and first.pending_bytes == split - len(meta)
        assert first.committed_native_offset == len(meta)
        second_result = run_collect(ledger, path, collector_scope)
        assert second_result.accepted_count == 1 and second_result.pending_bytes == 0


def test_restart_after_ledger_commit_replays_stable_pending_plan(tmp_path, collector_scope, monkeypatch):
    path = tmp_path / "rollout.jsonl"
    write_rollout(path, session_meta(), message(1, "user-1", "user", ["durable body"]))
    original = collector._finalize_plan
    failed = False

    def lose_ack(ledger, fd, source, plan, expected_scope, opened):
        nonlocal failed
        if plan.disposition == "accepted" and not failed:
            failed = True
            raise RuntimeError("synthetic lost ack")
        return original(ledger, fd, source, plan, expected_scope, opened)

    monkeypatch.setattr(collector, "_finalize_plan", lose_ack)
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        with pytest.raises(RuntimeError, match="lost ack"):
            run_collect(ledger, path, collector_scope)
        assert ledger._con.execute("SELECT count(*) FROM events").fetchone() == (1,)
        plan = ledger._con.execute(
            "SELECT state,first_seen_at,normalized_sha256 FROM airag_rollout_collector_plans WHERE disposition='accepted'"
        ).fetchone()
        assert plan[0] == "planned"
    monkeypatch.setattr(collector, "_finalize_plan", original)
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        result = run_collect(ledger, path, collector_scope)
        replayed = ledger._con.execute(
            "SELECT state,first_seen_at,normalized_sha256 FROM airag_rollout_collector_plans WHERE disposition='accepted'"
        ).fetchone()
        assert replayed == ("finalized", plan[1], plan[2])
        assert result.accepted_count == 1
        assert ledger._con.execute("SELECT count(*) FROM events").fetchone() == (1,)


def test_detects_committed_prefix_rewrite_and_truncation(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    meta = native_line(session_meta())
    original = native_line(message(1, "user-1", "user", ["AAAA"]))
    path.write_bytes(meta + original)
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        run_collect(ledger, path, collector_scope)
        changed = native_line(message(1, "user-1", "user", ["BBBB"]))
        assert len(changed) == len(original)
        path.write_bytes(meta + changed)
        with pytest.raises(EventError, match="SOURCE_PREFIX_REWRITTEN"):
            run_collect(ledger, path, collector_scope)
        path.write_bytes(meta)
        with pytest.raises(EventError, match="SOURCE_TRUNCATED"):
            run_collect(ledger, path, collector_scope)


def test_detects_file_replacement_even_when_bytes_match(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    original = write_rollout(path, session_meta(), message(1, "user-1", "user", ["body"]))
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        run_collect(ledger, path, collector_scope)
        replacement = tmp_path / "replacement.jsonl"
        replacement.write_bytes(original)
        os.replace(replacement, path)
        with pytest.raises(EventError, match="COLLECTOR_SOURCE_BINDING_MISMATCH"):
            run_collect(ledger, path, collector_scope)


def test_stale_cursor_and_session_scope_are_rejected(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    data = write_rollout(path, session_meta(), message(1, "user-1", "user", ["body"]))
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        run_collect(ledger, path, collector_scope)
        with pytest.raises(EventError, match="STALE_COLLECTOR_CURSOR"):
            run_collect(ledger, path, collector_scope, expected_native_offset=0)
        assert ledger.checkpoint("synthetic-rollout:codex-rollout-normalized") is not None
        assert path.read_bytes() == data
    wrong_path = tmp_path / "wrong.jsonl"
    write_rollout(wrong_path, session_meta(session_id="other"))
    with open_ledger(tmp_path / "other.db", KEY) as ledger:
        with pytest.raises(EventError, match="SESSION_SCOPE_MISMATCH"):
            run_collect(ledger, wrong_path, collector_scope)


def test_concurrent_collectors_converge_on_one_receipt(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    write_rollout(path, session_meta(), message(1, "user-1", "user", ["body"]))
    ledger_path = tmp_path / "ledger.db"
    with open_ledger(ledger_path, KEY):
        pass

    def collect_once():
        with open_ledger(ledger_path, KEY) as ledger:
            return run_collect(ledger, path, collector_scope)

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = [job.result(timeout=10) for job in (pool.submit(collect_once), pool.submit(collect_once))]
    assert all(result.accepted_count == 1 for result in results)
    with open_ledger(ledger_path, KEY) as ledger:
        assert ledger._con.execute("SELECT count(*) FROM events").fetchone() == (1,)
        assert ledger._con.execute(
            "SELECT count(*) FROM airag_rollout_collector_plans WHERE state='finalized'"
        ).fetchone() == (2,)


def test_malformed_record_requires_explicit_gap_authorization(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    path.write_bytes(
        native_line(session_meta()) + b'{"broken"}\n' +
        native_line(message(2, "user-2", "user", ["after gap"]))
    )
    with open_ledger(tmp_path / "strict.db", KEY) as ledger:
        with pytest.raises(EventError, match="INVALID_NATIVE_JSON"):
            run_collect(ledger, path, collector_scope)
        assert ledger._con.execute(
            "SELECT count(*) FROM airag_rollout_collector_plans WHERE disposition='gap'"
        ).fetchone() == (0,)
    with open_ledger(tmp_path / "gaps.db", KEY) as ledger:
        result = run_collect(ledger, path, collector_scope, allow_gaps=True)
        assert (result.accepted_count, result.gap_count) == (1, 1)
        assert result.complete_through_snapshot
        assert not result.coverage_complete
        assert result.coverage_gaps[0].reason_code == "INVALID_NATIVE_JSON"
        assert ledger.rejection_count("synthetic-rollout:codex-rollout-normalized") == 1
        assert ledger._con.execute("SELECT reason_code,validation_code FROM rejections").fetchone() == (
            "INVALID_NATIVE_JSON", "MISSING_EVENT_FIELDS",
        )


def test_unknown_rich_part_is_gap_not_silent_partial_message(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    rich = message(1, "user-1", "user", ["public"])
    rich["payload"]["content"].append({"type": "image", "url": "private://not-stored"})
    write_rollout(path, session_meta(), rich)
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        result = run_collect(ledger, path, collector_scope, allow_gaps=True)
        assert result.accepted_count == 0 and result.gap_count == 1
        assert result.coverage_gaps[0].reason_code == "UNKNOWN_MESSAGE_CONTENT_PART"
        assert ledger._con.execute("SELECT count(*) FROM events").fetchone() == (0,)


def test_redaction_failure_can_only_continue_as_explicit_gap(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    write_rollout(path, session_meta(), message(1, "user-1", "user", ["<environment_context>unterminated"]))
    with open_ledger(tmp_path / "strict.db", KEY) as ledger:
        with pytest.raises(EventError, match="UNBALANCED_INJECTED_BLOCK"):
            run_collect(ledger, path, collector_scope)
    with open_ledger(tmp_path / "gap.db", KEY) as ledger:
        result = run_collect(ledger, path, collector_scope, allow_gaps=True)
        assert result.gap_count == 1 and result.accepted_count == 0


def test_adapter_tables_never_store_native_secret_body_and_source_is_unchanged(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    secret = "TOP_SECRET_9f8e7d"
    original = write_rollout(
        path, session_meta(), message(1, "user-1", "user", [f"password={secret} safe tail"]),
    )
    before = path.stat()
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        result = run_collect(ledger, path, collector_scope)
        assert result.accepted_count == 1
        values: list[str] = []
        for table in ("airag_rollout_collector_sources", "airag_rollout_collector_plans"):
            for row in ledger._con.execute(f"SELECT * FROM {table}").fetchall():
                values.extend(str(value) for value in row if value is not None)
        assert secret not in " ".join(values)
        assert secret not in stored_events(ledger)[0]["content"]
        assert "[REDACTED:named_secret]" in stored_events(ledger)[0]["content"]
    after = path.stat()
    assert path.read_bytes() == original
    assert (after.st_size, after.st_mtime_ns, after.st_mode) == (
        before.st_size, before.st_mtime_ns, before.st_mode,
    )


def test_exact_allowlist_and_symlink_are_enforced(tmp_path, collector_scope):
    path = tmp_path / "rollout.jsonl"
    write_rollout(path, session_meta())
    alias = tmp_path / "alias.jsonl"
    alias.symlink_to(path)
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        with pytest.raises(EventError, match="UNENROLLED_SOURCE_PATH"):
            collect_codex_rollout(
                ledger, source_path=path, allowed_real_paths=(tmp_path / "other.jsonl",),
                source_id="x", expected_session_id=SESSION, expected_scope=collector_scope,
            )
        with pytest.raises(EventError, match="SYMLINK_SOURCE_REJECTED"):
            collect_codex_rollout(
                ledger, source_path=alias, allowed_real_paths=(alias,), source_id="x",
                expected_session_id=SESSION, expected_scope=collector_scope,
            )


@pytest.mark.parametrize("pause_ordinal", [None, 1, "gap"])
def test_lagging_collector_replays_after_peer_finishes(tmp_path, collector_scope, monkeypatch, pause_ordinal):
    from threading import Event, current_thread

    path = tmp_path / "rollout.jsonl"
    write_rollout(path, session_meta(), message(1, "user-1", "user", ["first"]),
                  message(2, "user-2", "user", ["second"]))
    if pause_ordinal == "gap":
        write_rollout(path, session_meta(), {"broken": True},
                      message(2, "user-1", "user", ["first"]),
                      message(3, "user-2", "user", ["second"]))
    ledger_path = tmp_path / "ledger.db"
    with open_ledger(ledger_path, KEY):
        pass
    paused, resume = Event(), Event()
    original = collector._deliver_plan

    def delayed(ledger, source, plan, classified, expected_scope):
        target = (plan.disposition == "skipped" if pause_ordinal is None else
                  plan.disposition == "gap" if pause_ordinal == "gap" else
                  plan.ordinal == pause_ordinal)
        if current_thread().name.startswith("lagging") and target and not paused.is_set():
            paused.set()
            assert resume.wait(10)
        return original(ledger, source, plan, classified, expected_scope)

    monkeypatch.setattr(collector, "_deliver_plan", delayed)

    def collect_once():
        with open_ledger(ledger_path, KEY) as ledger:
            return run_collect(ledger, path, collector_scope, allow_gaps=pause_ordinal == "gap")

    with ThreadPoolExecutor(max_workers=1, thread_name_prefix="lagging") as pool:
        lagging = pool.submit(collect_once)
        try:
            assert paused.wait(10)
            assert collect_once().accepted_count == 2
        finally:
            resume.set()
        assert lagging.result(timeout=10).accepted_count == 2
    with open_ledger(ledger_path, KEY) as ledger:
        assert ledger._con.execute("SELECT count(*) FROM events").fetchone() == (2,)


GOLDEN_INCARNATION = "codex-rollout:2e4f85f21c4005db065505d6c5462ccc05b7578b57919e8b0e3083ffd0c6435d"


def test_incarnation_matches_the_golden_value_and_the_stored_row(tmp_path, collector_scope):
    """Structure-only guard: the incarnation seed (path, session, device, inode) never changes its output."""
    assert collector._incarnation("/synthetic/rollout.jsonl", SESSION, "16777231", "1186756666") == GOLDEN_INCARNATION
    path = tmp_path / "rollout.jsonl"
    write_rollout(path, session_meta(), message(1, "user-1", "user", ["body"]))
    info = os.stat(path)
    with open_ledger(tmp_path / "ledger.db", KEY) as ledger:
        run_collect(ledger, path, collector_scope)
        stored = ledger._con.execute("SELECT incarnation FROM airag_rollout_collector_sources").fetchone()[0]
    assert stored == collector._incarnation(os.path.realpath(path), SESSION, str(info.st_dev), str(info.st_ino))
