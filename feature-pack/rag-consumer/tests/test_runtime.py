from __future__ import annotations

from dataclasses import asdict
from datetime import datetime, timedelta, timezone
from io import StringIO
import fcntl
import json
import os
from pathlib import Path
import subprocess
import struct
import sys
from unittest.mock import patch

import pytest

from airag import api, embeddings
from airag.db import connect
from airag_consumer import bridge, reference
from airag_consumer.cli import main
from airag_consumer.ledger import open_ledger
from airag_consumer.operations import OperationsError
from airag_consumer.runtime import (
    AIRAGRuntime,
    PROFILE_SOURCE_KEY_ENV,
    RuntimeConfig,
    RuntimeError,
    RuntimeHooks,
    managed_backup_root,
    runtime_child_environment,
)


UTC = timezone.utc
CONSUMER_KEY = b"c" * 32
PROJECTION_KEY = b"p" * 32
ARCHIVE_KEY = b"a" * 32
PROFILE_SOURCE_KEY = b"s" * 32
REFERENCE_SOURCE_KEY = b"r" * 32
SESSION = "synthetic-session-01"
COLLECTION = "airag-session-v1"
TOKENIZER_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


class Clock:
    def __init__(self, value):
        self.value = value

    def __call__(self):
        return self.value


def embedding_config():
    return embeddings.EmbeddingSpaceConfig(
        "openai-compatible", "http://127.0.0.1:9/v1", "synthetic-fixture-embed",
        "synthetic-fixture-revision", 4, tokenizer_revision=TOKENIZER_REVISION,
    )


def vectors(_config, texts, **_kwargs):
    return [struct.pack("4f", 1, 0, 0, 0) for _ in texts]


def native_line(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode() + b"\n"


def rollout(path: Path, *, content: str, occurred_at: str):
    meta = {
        "timestamp": occurred_at, "ordinal": 0, "type": "session_meta",
        "payload": {"id": SESSION},
    }
    message = {
        "timestamp": occurred_at, "ordinal": 1, "type": "response_item",
        "payload": {
            "type": "message", "id": "message-1", "role": "user",
            "content": [{"type": "input_text", "text": content}],
        },
    }
    data = native_line(meta) + native_line(message)
    path.write_bytes(data)
    return data


def environment():
    return {
        "AIRAG_CONSUMER_KEY_HEX": CONSUMER_KEY.hex(),
        "AIRAG_PROJECTION_KEY_HEX": PROJECTION_KEY.hex(),
        "AIRAG_ARCHIVE_KEY_HEX": ARCHIVE_KEY.hex(),
        PROFILE_SOURCE_KEY_ENV: PROFILE_SOURCE_KEY.hex(),
        "AIRAG_REFERENCE_SOURCE_KEY_HEX": REFERENCE_SOURCE_KEY.hex(),
        "AIRAG_MEMORY_API_KEY": "synthetic-provider-key",
        "PATH": "/usr/bin:/bin",
    }


def project(
    tmp_path: Path, *, now: datetime, content: str = "durable synthetic history",
    occurred_at: str | None = None, memory: bool = False,
    with_reference: bool = False,
):
    root = tmp_path / "project"
    root.mkdir()
    profile_source = root / "captured-profile.db"
    source_con = connect.init_db(profile_source, PROFILE_SOURCE_KEY)
    registered = api.register_profile(
        source_con, {"embedding": asdict(embedding_config())},
    )
    assert registered["ok"], registered
    profile_key = registered["data"]["profile_key"]
    source_con.close()
    source = root / "synthetic-rollout.jsonl"
    original = rollout(
        source, content=content,
        occurred_at=occurred_at or (now - timedelta(days=1)).isoformat(),
    )
    config = {
        "schema_version": 1,
        "project_root": str(root),
        "owner_id": "synthetic-owner",
        "tenant_id": "synthetic-tenant",
        "project_id": "synthetic-project",
        "consumer_db": str(root / "consumer.db"),
        "projection_db": str(root / "projection.db"),
        "archive_root": str(root / "archives"),
        "backup_root": str(root / "backups"),
        "profile_source_db": str(profile_source),
        "profile_key": profile_key,
        "collection": COLLECTION,
        "sources": [{
            "path": str(source), "session_id": SESSION,
            "source_id": "synthetic-rollout",
        }],
        "token_mode": "estimated",
        "allow_gaps": False,
        "memory_enabled": memory,
        "poll_seconds": 1,
    }
    if memory:
        config.update(
            memory_endpoint="http://127.0.0.1:9/v1",
            memory_model="synthetic-memory-fixture",
        )
    reference_path = None
    reference_original = None
    if with_reference:
        reference_path = root / "original-tour-reference.db"
        reference_con = connect.init_db(reference_path, REFERENCE_SOURCE_KEY)
        reference_profile = api.register_profile(
            reference_con, {"embedding": asdict(embedding_config())},
        )["data"]["profile_key"]
        with patch("airag.embeddings.embed_documents", side_effect=vectors):
            added = api.add(
                reference_con, "synthetic-reference-add", "tour-text", "library-en.txt",
                b"existing tour reference marker", profile_key=reference_profile,
            )
        assert added["ok"], added
        reference_con.close()
        reference_original = reference_path.read_bytes()
        config["reference"] = {
            "source_db": str(reference_path),
            "source_key_env": "AIRAG_REFERENCE_SOURCE_KEY_HEX",
            "source_allowlist": [list(item) for item in reference.ALLOWED_TOUR_SOURCES],
            "snapshot_root": str(root / "reference-snapshots"),
        }
    config_path = root / "runtime.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    return {
        "root": root, "config": config_path, "config_data": config,
        "source": source, "original": original, "profile_key": profile_key,
        "reference_source": reference_path, "reference_original": reference_original,
    }


def invoke(args, *, env, clock, hooks=None):
    stdout, stderr = StringIO(), StringIO()
    code = main(
        args, environ=env, clock=clock, hooks=hooks,
        stdout=stdout, stderr=stderr,
    )
    output = stdout.getvalue() if code == 0 else stderr.getvalue()
    return code, json.loads(output)


def test_cli_help_is_fast_lazy_and_exits_zero_without_error_json():
    child_env = {
        **os.environ,
        "PYTHONPATH": str(Path(__file__).resolve().parents[1] / "src"),
    }
    result = subprocess.run(
        [sys.executable, "-m", "airag_consumer.cli", "--help"],
        text=True, capture_output=True, timeout=5, check=False, env=child_env,
    )
    assert result.returncode == 0
    assert "usage: airag-consumer" in result.stdout
    assert "INTERRUPTED" not in result.stdout + result.stderr
    assert "transformers" not in result.stdout + result.stderr
    invalid = subprocess.run(
        [sys.executable, "-m", "airag_consumer.cli"],
        text=True, capture_output=True, timeout=5, check=False, env=child_env,
    )
    assert invalid.returncode == 2 and invalid.stdout == ""
    assert json.loads(invalid.stderr)["error"]["code"] == "INVALID_ARGUMENTS"
    assert "Traceback" not in invalid.stderr and "transformers" not in invalid.stderr


def test_missing_keys_fail_before_lock_directory_or_store_creation(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    item = project(tmp_path, now=now)
    root = item["root"]
    code, output = invoke(
        ["--config", str(item["config"]), "init"],
        env={"AIRAG_CONSUMER_KEY_HEX": CONSUMER_KEY.hex()}, clock=Clock(now),
    )
    assert code == 2
    assert output["error"]["code"] == "MISSING_OR_INVALID_STORE_KEY"
    assert not (root / ".airag-runtime.lock").exists()
    assert not (root / "consumer.db").exists()
    assert not (root / "projection.db").exists()
    assert not (root / "archives").exists()
    assert not (root / "backups").exists()
    child_source = {**environment(), "AIRAG_FUTURE_KEY_HEX": "secret"}
    assert runtime_child_environment(child_source) == {"PATH": "/usr/bin:/bin"}


def test_profile_bootstrap_key_is_distinct_and_not_needed_after_verified_install(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(tmp_path, now=now)
    missing = environment()
    missing.pop(PROFILE_SOURCE_KEY_ENV)
    with pytest.raises(RuntimeError, match="MISSING_OR_INVALID_PROFILE_SOURCE_KEY"):
        AIRAGRuntime(RuntimeConfig.load(item["config"]), environ=missing, clock=clock)
    assert not (item["root"] / ".airag-runtime.lock").exists()
    bad = {**environment(), PROFILE_SOURCE_KEY_ENV: PROJECTION_KEY.hex()}
    with pytest.raises(RuntimeError, match="PROFILE_SOURCE_KEY_MUST_BE_DISTINCT"):
        AIRAGRuntime(RuntimeConfig.load(item["config"]), environ=bad, clock=clock)
    assert not (item["root"] / "consumer.db").exists()
    assert not (item["root"] / "projection.db").exists()

    args = ["--config", str(item["config"])]
    assert invoke([*args, "init"], env=environment(), clock=clock)[0] == 0
    item["root"].joinpath("captured-profile.db").unlink()
    reopened_env = environment()
    reopened_env.pop(PROFILE_SOURCE_KEY_ENV)
    code, reopened = invoke([*args, "init"], env=reopened_env, clock=clock)
    assert code == 0
    assert reopened["data"]["profile"]["reused_verified_target"] is True


def test_exact_token_mode_requires_injected_tokenizer(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    item = project(tmp_path, now=now)
    exact = dict(item["config_data"], token_mode="exact")
    item["config"].write_text(json.dumps(exact), encoding="utf-8")
    with pytest.raises(RuntimeError, match="EXACT_TOKENIZER_REQUIRED"):
        AIRAGRuntime(
            RuntimeConfig.load(item["config"]), environ=environment(), clock=Clock(now),
        )
    runtime = AIRAGRuntime(
        RuntimeConfig.load(item["config"]), environ=environment(), clock=Clock(now),
        tokenizer=lambda text: len(text.split()), hooks=RuntimeHooks(bridge=SyntheticBridge()),
    )
    assert runtime.config.token_mode == "exact"


def test_exact_managed_backup_root_is_only_allowed_external_output(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    item = project(tmp_path, now=now)
    managed = dict(
        item["config_data"],
        backup_root=str(managed_backup_root("synthetic-project")),
    )
    item["config"].write_text(json.dumps(managed), encoding="utf-8")
    loaded = RuntimeConfig.load(item["config"])
    assert loaded.backup_root == managed_backup_root("synthetic-project")
    arbitrary = dict(managed, backup_root=str(Path.home() / "arbitrary-airag-backup"))
    item["config"].write_text(json.dumps(arbitrary), encoding="utf-8")
    with pytest.raises(RuntimeError, match="OUTPUT_PATH_OUTSIDE_PROJECT"):
        RuntimeConfig.load(item["config"])


def test_actual_core_init_run_restart_search_backup_and_verify(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(tmp_path, now=now, content="durable synthetic history marker")
    args = ["--config", str(item["config"])]

    code, initialized = invoke([*args, "init"], env=environment(), clock=clock)
    assert code == 0 and initialized["data"]["profile"]["profile_key"] == item["profile_key"]

    with patch("airag.embeddings.embed_documents", side_effect=vectors) as provider:
        code, first = invoke([*args, "run", "--once", "--save"], env=environment(), clock=clock)
    assert code == 0, first
    provider.assert_called_once()
    assert first["data"]["published"]["succeeded"] == 1
    assert first["data"]["backup"]["created"] is True
    backup_id = Path(first["data"]["backup"]["path"]).name
    assert item["source"].read_bytes() == item["original"]
    assert "durable synthetic history marker" not in json.dumps(first)

    with patch(
        "airag.embeddings.embed_documents",
        side_effect=AssertionError("no-new-data replayed provider"),
    ) as provider:
        code, replay = invoke([*args, "run", "--once"], env=environment(), clock=clock)
    assert code == 0, replay
    provider.assert_not_called()
    assert replay["data"]["published"]["attempted"] == 0
    assert replay["data"]["backup"]["created"] is False

    with patch(
        "airag.embeddings.embed_query",
        return_value=struct.pack("4f", 1, 0, 0, 0),
    ):
        code, searched = invoke(
            [*args, "search", "history marker"], env=environment(), clock=clock,
        )
    assert code == 0, searched
    assert searched["data"]["ranking"]["mode"] == "core_hybrid"
    assert searched["data"]["results"][0]["message_anchors"][0]["turn_id"].startswith("msg:")

    code, verified = invoke(
        [*args, "verify", backup_id], env=environment(), clock=clock,
    )
    assert code == 0 and verified["data"]["verified"] is True
    code, status = invoke([*args, "status"], env=environment(), clock=clock)
    assert code == 0 and status["data"]["indexed"] == 1
    assert status["data"]["coverage_complete"] is True
    assert status["data"]["backup_count"] == 1
    assert status["data"]["verified_backup_ids"] == [backup_id]
    assert "durable synthetic history marker" not in json.dumps(status)


def test_reference_config_requires_exact_allowlist_and_separate_source_key(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    item = project(tmp_path, now=now, with_reference=True)
    missing = environment()
    missing.pop("AIRAG_REFERENCE_SOURCE_KEY_HEX")
    with pytest.raises(RuntimeError, match="MISSING_OR_INVALID_REFERENCE_SOURCE_KEY"):
        AIRAGRuntime(RuntimeConfig.load(item["config"]), environ=missing, clock=Clock(now))
    reused = {
        **environment(), "AIRAG_REFERENCE_SOURCE_KEY_HEX": PROJECTION_KEY.hex(),
    }
    with pytest.raises(RuntimeError, match="REFERENCE_SOURCE_KEY_MUST_BE_DISTINCT"):
        AIRAGRuntime(RuntimeConfig.load(item["config"]), environ=reused, clock=Clock(now))
    invalid = dict(item["config_data"])
    invalid["reference"] = dict(
        json.loads(item["config"].read_text())["reference"],
        source_allowlist=[list(reference.ALLOWED_TOUR_SOURCES[0])],
    )
    item["config"].write_text(json.dumps(invalid), encoding="utf-8")
    with pytest.raises(RuntimeError, match="REFERENCE_SOURCE_ALLOWLIST_MISMATCH"):
        RuntimeConfig.load(item["config"])


def test_combined_query_returns_separate_conversation_and_reference_groups(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(
        tmp_path, now=now, content="conversation group marker", with_reference=True,
    )
    configured = json.loads(item["config"].read_text())
    configured["reference"]["embedding_endpoint_override"] = "http://127.0.0.1:18712/v1"
    item["config"].write_text(json.dumps(configured), encoding="utf-8")
    args = ["--config", str(item["config"])]
    assert invoke([*args, "init"], env=environment(), clock=clock)[0] == 0
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        assert invoke(
            [*args, "run", "--once", "--save"], env=environment(), clock=clock,
        )[0] == 0
    before = item["reference_source"].read_bytes()
    routed_endpoints = []

    def query_vector(config, _text):
        routed_endpoints.append(config.endpoint)
        return struct.pack("4f", 1, 0, 0, 0)

    with patch("airag.embeddings.embed_query", side_effect=query_vector):
        code, combined = invoke(
            [*args, "search", "reference marker"], env=environment(), clock=clock,
        )
    assert code == 0, combined
    data = combined["data"]
    assert data["label"] == "combined_query"
    assert data["ranking"]["global_merge"] is False
    assert [group["label"] for group in data["groups"]] == [
        "conversation_memory", "existing_tour_reference",
    ]
    assert data["conversation"]["ranking"]["mode"] == "core_hybrid"
    assert data["reference"]["label"] == "existing_tour_reference"
    assert len(data["reference"]["allowed_source_pairs"]) == 17
    assert any(
        "library-en.txt" in group["source_keys"]
        for group in data["reference"]["groups"]
    )
    snapshot = Path(data["reference"]["snapshot"]["path"])
    assert snapshot.exists() and snapshot.parent == item["root"] / "reference-snapshots"
    assert item["reference_source"].read_bytes() == before == item["reference_original"]
    assert "http://127.0.0.1:18712/v1" in routed_endpoints

    with patch(
        "airag.embeddings.embed_query",
        return_value=struct.pack("4f", 1, 0, 0, 0),
    ):
        second = invoke(
            [*args, "search", "reference marker"], env=environment(), clock=clock,
        )[1]["data"]
    assert second["reference"]["snapshot"]["path"] != str(snapshot)
    status = invoke([*args, "status"], env=environment(), clock=clock)[1]["data"]
    assert status["reference_enabled"] is True
    assert status["reference_source_count"] == 17
    assert status["reference_snapshot_count"] == 2


def test_provider_failure_stays_visible_then_retry_succeeds(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(tmp_path, now=now, content="provider retry history")
    args = ["--config", str(item["config"])]
    assert invoke([*args, "init"], env=environment(), clock=clock)[0] == 0
    failure = embeddings.EmbeddingError(
        "PROVIDER_UNREACHABLE", "synthetic fixture failure", retryable=True,
    )
    with patch("airag.embeddings.embed_documents", side_effect=failure):
        code, failed = invoke([*args, "run", "--once", "--save"], env=environment(), clock=clock)
    assert code == 0
    assert failed["data"]["published"]["items"][0]["error"]["code"] == "PROVIDER_UNREACHABLE"
    assert invoke([*args, "status"], env=environment(), clock=clock)[1]["data"]["failed"] == 1
    with patch("airag.embeddings.embed_documents", side_effect=vectors) as provider:
        code, recovered = invoke([*args, "run", "--once"], env=environment(), clock=clock)
    assert code == 0 and recovered["data"]["published"]["succeeded"] == 1
    provider.assert_called_once()
    assert invoke([*args, "status"], env=environment(), clock=clock)[1]["data"]["indexed"] == 1


def test_expiry_archives_and_requires_explicit_historical_lookup(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(
        tmp_path, now=now, content="historic resolution marker",
        occurred_at=(now - timedelta(days=91)).isoformat(),
    )
    args = ["--config", str(item["config"])]
    assert invoke([*args, "init"], env=environment(), clock=clock)[0] == 0
    code, run = invoke([*args, "run", "--once", "--save"], env=environment(), clock=clock)
    assert code == 0, run
    assert run["data"]["published"]["attempted"] == 0
    assert len(run["data"]["archives"]) == 1
    code, normal = invoke(
        [*args, "search", "historic resolution"], env=environment(), clock=clock,
    )
    assert code == 0 and normal["data"]["results"] == []
    code, historical = invoke(
        [*args, "archive-search", "historic resolution"],
        env=environment(), clock=clock,
    )
    assert code == 0
    assert historical["data"]["label"] == "historical_archive_audit_only"
    assert historical["data"]["explicit_request"] is True
    assert len(historical["data"]["results"]) == 1
    status = invoke([*args, "status"], env=environment(), clock=clock)[1]["data"]
    assert status["expired"] == 1 and status["indexed"] == 0
    assert status["archive_pending"] == 0
    with open_ledger(item["root"] / "consumer.db", CONSUMER_KEY) as ledger:
        row = ledger._con.execute(
            "SELECT entity_type,entity_id,archive_receipt_json FROM airag_lifecycle_archive_queue"
        ).fetchone()
        receipt = json.loads(row[2])
        receipt["path"] = str(tmp_path / "untrusted-archive.db")
        ledger._con.execute(
            """UPDATE airag_lifecycle_archive_queue SET archive_receipt_json=?
               WHERE entity_type=? AND entity_id=?""",
            (json.dumps(receipt), row[0], row[1]),
        )
    code, rejected = invoke(
        [*args, "archive-search", "historic"], env=environment(), clock=clock,
    )
    assert code == 2 and rejected["error"]["code"] == "UNTRUSTED_ARCHIVE_RECEIPT_PATH"


def test_gap_status_separates_byte_completion_from_coverage(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(tmp_path, now=now, content="after explicit gap")
    timestamp = (now - timedelta(days=1)).isoformat()
    meta = {
        "timestamp": timestamp, "ordinal": 0, "type": "session_meta",
        "payload": {"id": SESSION},
    }
    message = {
        "timestamp": timestamp, "ordinal": 2, "type": "response_item",
        "payload": {
            "type": "message", "id": "message-2", "role": "user",
            "content": [{"type": "input_text", "text": "after explicit gap"}],
        },
    }
    item["source"].write_bytes(native_line(meta) + b'{"broken"}\n' + native_line(message))
    hooks = RuntimeHooks(bridge=SyntheticBridge())
    args = ["--config", str(item["config"])]
    assert invoke([*args, "init"], env=environment(), clock=clock, hooks=hooks)[0] == 0
    code, run = invoke(
        [*args, "run", "--once", "--save", "--allow-gaps"],
        env=environment(), clock=clock, hooks=hooks,
    )
    assert code == 0, run
    collected = run["data"]["collected"][0]
    assert collected["complete_through_snapshot"] is True
    assert collected["coverage_complete"] is False
    status = invoke([*args, "status"], env=environment(), clock=clock, hooks=hooks)[1]["data"]
    assert status["gaps"] == 1 and status["coverage_complete"] is False
    assert status["collector_sources"][0]["complete_through_current_snapshot"] is True
    assert status["collector_sources"][0]["coverage_complete"] is False


class SyntheticBridge:
    """Labelled runtime orchestration double; core behavior is tested above."""

    synthetic_test_double = True

    @staticmethod
    def install_captured_profile(source, target, profile_key, endpoint_override=None):
        return bridge.install_captured_profile(
            source, target, profile_key, endpoint_override=endpoint_override,
        )

    @staticmethod
    def publish_pending_windows(lifecycle, scope, core, **_kwargs):
        state = lifecycle.refresh(scope)
        result = []
        for window_id in state["pending_publication_ids"]:
            lifecycle.claim_publication(scope, window_id)
            lifecycle.finish_publication(scope, window_id, success=True)
            result.append({"ok": True, "window_id": window_id, "synthetic_test_double": True})
        return result

    @staticmethod
    def verify_projection_links(state, core, **_kwargs):
        return {
            window_id: {"synthetic_test_double": True}
            for window_id in state["searchable_window_ids"]
        }

    @staticmethod
    def search_history(lifecycle, scope, core, **kwargs):
        return {
            "scope": scope.to_dict(), "query": kwargs["query"],
            "results": [], "synthetic_test_double": True,
        }


class PreferenceExtractor:
    synthetic_test_double = True

    def __init__(self):
        self.calls = 0

    def __call__(self, request):
        self.calls += 1
        message = request.messages[0]
        return {"candidates": [{
            "kind": "preference", "text": "Prefer concise answers",
            "anchor_ids": [message.anchor_id], "proof_anchor_ids": [],
            "supporting_quotes": [{
                "anchor_id": message.anchor_id, "quote": "prefer concise answers",
            }],
            "conflict": False,
        }]}


class EmptyExtractor:
    synthetic_test_double = True

    def __init__(self):
        self.calls = 0

    def __call__(self, _request):
        self.calls += 1
        return {"candidates": []}


class UnauthenticatedMemoryModule:
    synthetic_test_double = True
    saw_provider = "unset"

    class OpenAICompatibleMemoryConfig:
        def __init__(self, *, endpoint, model, api_key_provider):
            UnauthenticatedMemoryModule.saw_provider = api_key_provider

    class OpenAICompatibleMemoryExtractor:
        def __init__(self, config):
            self.config = config

    class Result:
        def to_dict(self):
            return {
                "state": "source_complete", "provider_called": False,
                "continuation_required": False, "source_complete": True,
            }

    @staticmethod
    def extract_memories(*_args, **_kwargs):
        return UnauthenticatedMemoryModule.Result()


def test_memory_extraction_restart_and_explicit_confirmation(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(
        tmp_path, now=now, content="I prefer concise answers for reports.", memory=True,
    )
    extractor = PreferenceExtractor()
    hooks = RuntimeHooks(bridge=SyntheticBridge(), memory_extractor=extractor)
    args = ["--config", str(item["config"])]
    assert invoke([*args, "init"], env=environment(), clock=clock, hooks=hooks)[0] == 0
    code, first = invoke(
        [*args, "run", "--once", "--save"], env=environment(), clock=clock, hooks=hooks,
    )
    assert code == 0 and first["data"]["memory"]["awaiting_confirmation_count"] == 1
    assert first["data"]["memory"]["batch_input_limit_bytes"] == 4096
    assert first["data"]["memory"]["max_messages_per_batch"] == 4
    assert extractor.calls == 1
    code, second = invoke(
        [*args, "run", "--once"], env=environment(), clock=clock, hooks=hooks,
    )
    assert code == 0 and second["data"]["memory"]["provider_called"] is False
    assert extractor.calls == 1
    status = invoke([*args, "status"], env=environment(), clock=clock, hooks=hooks)[1]["data"]
    candidate_id = status["memory_awaiting_confirmation_ids"][0]
    code, confirmed = invoke(
        [*args, "memory-confirm", candidate_id],
        env=environment(), clock=clock, hooks=hooks,
    )
    assert code == 0 and confirmed["data"]["state"] == "materialized"
    status = invoke([*args, "status"], env=environment(), clock=clock, hooks=hooks)[1]["data"]
    assert status["visible_memories"] == 1
    assert status["memory_awaiting_confirmation_ids"] == []


def test_memory_processes_one_sealed_batch_per_poll_and_reports_continuation(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(tmp_path, now=now, content="x" * 6_000, memory=True)
    extractor = EmptyExtractor()
    hooks = RuntimeHooks(bridge=SyntheticBridge(), memory_extractor=extractor)
    args = ["--config", str(item["config"])]
    assert invoke([*args, "init"], env=environment(), clock=clock, hooks=hooks)[0] == 0
    first = invoke(
        [*args, "run", "--once", "--save"], env=environment(), clock=clock, hooks=hooks,
    )[1]["data"]["memory"]
    assert first["provider_called"] is True
    assert first["continuation_required"] is True and first["source_complete"] is False
    assert first["batch_message_count"] == 1 and first["batch_input_bytes"] <= 4096
    assert first["batch_input_limit_bytes"] == 4096
    assert first["max_messages_per_batch"] == 4
    second = invoke(
        [*args, "run", "--once"], env=environment(), clock=clock, hooks=hooks,
    )[1]["data"]["memory"]
    assert second["provider_called"] is True
    assert second["source_complete"] is True and second["continuation_required"] is False
    assert extractor.calls == 2
    third = invoke(
        [*args, "run", "--once"], env=environment(), clock=clock, hooks=hooks,
    )[1]["data"]["memory"]
    assert third["provider_called"] is False and third["source_complete"] is True
    assert extractor.calls == 2


def test_memory_provider_key_is_optional_for_unauthenticated_local_server(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(tmp_path, now=now, content="local memory input", memory=True)
    env = environment()
    env.pop("AIRAG_MEMORY_API_KEY")
    hooks = RuntimeHooks(bridge=SyntheticBridge(), memory=UnauthenticatedMemoryModule())
    args = ["--config", str(item["config"])]
    assert invoke([*args, "init"], env=env, clock=clock, hooks=hooks)[0] == 0
    code, run = invoke(
        [*args, "run", "--once", "--save"], env=env, clock=clock, hooks=hooks,
    )
    assert code == 0, run
    assert UnauthenticatedMemoryModule.saw_provider is None
    assert run["data"]["memory"]["source_complete"] is True


def test_backup_schedule_restore_prune_and_clock_regression_guard(tmp_path):
    old = datetime(2026, 7, 1, 4, tzinfo=UTC)
    clock = Clock(old)
    item = project(tmp_path, now=old, content="backup schedule history")
    hooks = RuntimeHooks(bridge=SyntheticBridge())
    config = RuntimeConfig.load(item["config"])
    runtime = AIRAGRuntime(config, environ=environment(), clock=clock, hooks=hooks)
    runtime.init()
    first = runtime.run_once(explicit_save=True)["backup"]
    first_path = Path(first["path"])
    assert first_path.exists()
    clock.value = old + timedelta(days=31)
    second = runtime.run_once()["backup"]
    assert second["created"] is True
    assert str(first_path) in second["pruned"] and not first_path.exists()
    clock.value = old
    with pytest.raises(OperationsError, match="BACKUP_CLOCK_REGRESSION"):
        runtime.run_once()
    assert Path(second["path"]).exists()


def test_backup_validation_failure_never_prunes_or_records_success(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(tmp_path, now=now)
    hooks = RuntimeHooks(bridge=SyntheticBridge())
    runtime = AIRAGRuntime(
        RuntimeConfig.load(item["config"]), environ=environment(), clock=clock, hooks=hooks,
    )
    runtime.init()
    with patch(
        "airag_consumer.runtime.create_backup_set",
        side_effect=OperationsError("RESTORE_RECONCILIATION_FAILED"),
    ), patch("airag_consumer.runtime.prune_backup_sets") as prune:
        with pytest.raises(OperationsError, match="RESTORE_RECONCILIATION_FAILED"):
            runtime.backup(force=True)
    prune.assert_not_called()
    assert runtime.status()["last_verified_backup"] is None


def test_actor_binding_lock_and_config_path_guards(tmp_path):
    now = datetime(2026, 9, 27, 4, tzinfo=UTC)
    clock = Clock(now)
    item = project(tmp_path, now=now)
    hooks = RuntimeHooks(bridge=SyntheticBridge())
    config = RuntimeConfig.load(item["config"])
    runtime = AIRAGRuntime(config, environ=environment(), clock=clock, hooks=hooks)
    runtime.init()

    changed = dict(item["config_data"], owner_id="other-owner")
    other_path = item["root"] / "other-runtime.json"
    other_path.write_text(json.dumps(changed), encoding="utf-8")
    other = AIRAGRuntime(
        RuntimeConfig.load(other_path), environ=environment(), clock=clock, hooks=hooks,
    )
    with pytest.raises(RuntimeError, match="RUNTIME_BINDING_MISMATCH"):
        other.status()

    with (item["root"] / ".airag-runtime.lock").open("r+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with pytest.raises(RuntimeError, match="PROJECT_BUSY"):
            runtime.status()

    outside = dict(item["config_data"], consumer_db=str(tmp_path / "outside.db"))
    outside_path = item["root"] / "outside-runtime.json"
    outside_path.write_text(json.dumps(outside), encoding="utf-8")
    with pytest.raises(RuntimeError, match="OUTPUT_PATH_OUTSIDE_PROJECT"):
        RuntimeConfig.load(outside_path)

    alias = item["root"] / "source-alias.jsonl"
    alias.symlink_to(item["source"])
    symlinked = dict(item["config_data"])
    symlinked["sources"] = [{
        "path": str(alias), "session_id": SESSION, "source_id": "alias-source",
    }]
    symlink_path = item["root"] / "symlink-runtime.json"
    symlink_path.write_text(json.dumps(symlinked), encoding="utf-8")
    with pytest.raises(RuntimeError, match="SYMLINK_PATH_REJECTED"):
        RuntimeConfig.load(symlink_path)


def test_real_backup_restore_reconciles_expired_conversation_and_memory(tmp_path):
    created = datetime(2026, 6, 1, 4, tzinfo=UTC)
    clock = Clock(created + timedelta(days=89))
    item = project(tmp_path, now=clock.value, occurred_at=created.isoformat())
    config = RuntimeConfig.load(item["config"])
    runtime = AIRAGRuntime(config, environ=environment(), clock=clock)
    runtime.init()
    with patch("airag.embeddings.embed_documents", side_effect=vectors):
        runtime.run_once(explicit_save=True)
    with open_ledger(config.consumer_db, CONSUMER_KEY) as ledger:
        lifecycle = runtime._lifecycle(ledger)
        state = lifecycle.refresh(config.scope)
        assert state["searchable_window_ids"]
        anchor = state["reduction"]["eligible_message_keys"][0]
        memory = lifecycle.create_memory(
            config.scope, kind="decision", text="retention evidence",
            anchor_ids=[anchor], pinned=True,
        )
        assert memory["memory_id"] in lifecycle.state(config.scope)["visible_memory_ids"]
    backup = runtime.backup(force=True)
    backup_path = Path(backup["path"])
    before = {p.name: p.read_bytes() for p in backup_path.glob("*.bin")}
    assert set(before) == {"consumer.bin", "projection.bin"}
    clock.value = created + timedelta(days=91)
    states = []
    original = bridge.verify_projection_links

    def inspect_restored(state, *args, **kwargs):
        states.append(state)
        return original(state, *args, **kwargs)

    with patch("airag_consumer.bridge.verify_projection_links", side_effect=inspect_restored):
        verified = runtime.verify_backup(backup_path.name)
    assert verified["verified"] is True
    assert len(states) == 1
    restored = states[0]
    assert restored["read_gate"]["open"] is True
    assert restored["searchable_window_ids"] == []
    assert restored["visible_memory_ids"] == []
    assert {x["entity_type"] for x in restored["archive_only_expiry_candidates"]} == {"message", "memory"}
    for name, contents in before.items():
        assert (backup_path / name).read_bytes() == contents
