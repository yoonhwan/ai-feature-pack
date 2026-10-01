"""Bridge lifecycle windows to the existing encrypted AIRAG core.

The bridge never creates databases, selects production paths, or opens an
archive lookup. Callers own connections, keys, scheduling, and runtime gates.
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
import sqlite3
from collections.abc import Mapping

from airag import api as core_api
from airag import profiles
from airag import search as core_search

from .lifecycle import AuthenticatedScope, Lifecycle


_WINDOW_ID = re.compile(r"win:[0-9a-f]{64}\Z")
_PROFILE_KEY = re.compile(r"[0-9a-f]{64}\Z")
_PARTITION_SIZE = 100
_BRIDGE_RRF_K = 60
_CONVERSATION_MEDIA_TYPE = "application/x-airag-conversation+json"


class BridgeError(ValueError):
    """A fail-closed profile, publication, scope, or search bridge error."""


def _canonical(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")


def _require_text(name: str, value: object) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        raise BridgeError(f"INVALID_{name.upper()}")
    return value


def _request_id(kind: str, *parts: object) -> str:
    digest = hashlib.sha256(_canonical([kind, *parts])).hexdigest()
    return f"airag-bridge-{kind}-{digest}"


def source_key_for_window(window_id: str) -> str:
    """Return the exact one-to-one core source key for a lifecycle window."""
    if not isinstance(window_id, str) or _WINDOW_ID.fullmatch(window_id) is None:
        raise BridgeError("INVALID_WINDOW_ID")
    return window_id


def install_captured_profile(
    source_con: sqlite3.Connection,
    target_con: sqlite3.Connection,
    profile_key: str,
    *,
    endpoint_override: str | None = None,
) -> dict[str, object]:
    """Install one exact captured core profile into a caller-created DB.

    Current core ingestion/search APIs do not accept a per-call endpoint
    override. A different override is therefore rejected instead of being
    persisted under a silently different profile fingerprint.
    """
    if not isinstance(profile_key, str) or _PROFILE_KEY.fullmatch(profile_key) is None:
        raise BridgeError("INVALID_PROFILE_KEY")
    embedding, normalizer = profiles.config_from_profile(source_con, profile_key)
    llm = profiles.llm_from_profile(source_con, profile_key)
    if endpoint_override is not None:
        _require_text("endpoint_override", endpoint_override)
        if endpoint_override != embedding.endpoint:
            raise BridgeError("ENDPOINT_OVERRIDE_UNSUPPORTED_BY_CORE_API")
    row = source_con.execute(
        "SELECT chunker_config FROM processing_profiles WHERE profile_key=?",
        (profile_key,),
    ).fetchone()
    if row is None:
        raise BridgeError("CAPTURED_PROFILE_NOT_FOUND")
    try:
        captured_chunker = json.loads(row[0])
        chunker_name = captured_chunker["chunker"]
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        raise BridgeError("INVALID_CAPTURED_PROFILE") from None
    if not isinstance(chunker_name, str) or not chunker_name:
        raise BridgeError("INVALID_CAPTURED_PROFILE")

    target_con.execute("BEGIN IMMEDIATE")
    try:
        space_id, installed_key = profiles.register_space_and_profile(
            target_con, embedding, normalizer, chunker=chunker_name, llm=llm,
        )
        if installed_key != profile_key:
            raise BridgeError("PROFILE_KEY_MISMATCH")
        installed_embedding, installed_normalizer = profiles.config_from_profile(
            target_con, installed_key,
        )
        installed_llm = profiles.llm_from_profile(target_con, installed_key)
        installed_row = target_con.execute(
            "SELECT chunker_config FROM processing_profiles WHERE profile_key=?",
            (installed_key,),
        ).fetchone()
        if (
            installed_embedding != embedding
            or installed_normalizer != normalizer
            or installed_llm != llm
            or installed_row is None
            or json.loads(installed_row[0]) != captured_chunker
        ):
            raise BridgeError("CAPTURED_PROFILE_DESCRIPTOR_MISMATCH")
        target_con.commit()
    except BaseException:
        target_con.rollback()
        raise
    return {
        "profile_key": installed_key,
        "space_id": space_id,
        "llm_enrichment": llm is not None,
    }


def _window_content(claim: Mapping[str, object], scope: AuthenticatedScope) -> tuple[bytes, str]:
    document = claim.get("document")
    if not isinstance(document, dict):
        raise BridgeError("WINDOW_DOCUMENT_REQUIRED")
    if document.get("window_id") != claim.get("window_id"):
        raise BridgeError("WINDOW_IDENTITY_MISMATCH")
    provenance = document.get("provenance")
    if not isinstance(provenance, dict):
        raise BridgeError("WINDOW_SCOPE_MISMATCH")
    original_scope = provenance.get("scope")
    if (
        not isinstance(original_scope, dict)
        or any(original_scope.get(field) != getattr(scope, field)
               for field in ("owner_id", "tenant_id", "project_id"))
        or provenance.get("stream_id") not in scope.enrolled_streams
    ):
        raise BridgeError("WINDOW_SCOPE_MISMATCH")
    encoded_document = _canonical(document)
    if hashlib.sha256(encoded_document).hexdigest() != claim.get("document_sha256"):
        raise BridgeError("WINDOW_DOCUMENT_FENCE_MISMATCH")
    media_type = document.get("media_type")
    content = document.get("content")
    if media_type != _CONVERSATION_MEDIA_TYPE or not isinstance(content, dict):
        raise BridgeError("INVALID_WINDOW_DOCUMENT")
    turns = content.get("turns")
    if not isinstance(turns, list):
        raise BridgeError("INVALID_WINDOW_DOCUMENT")
    return _canonical(content), media_type


def _core_status(
    core_con: sqlite3.Connection, collection: str, source_key: str,
) -> dict[str, object] | None:
    response = core_api.status(core_con, collection, source_key)
    if response["ok"]:
        return response["data"]
    error = response.get("error") or {}
    if error.get("code") == "NOT_FOUND":
        return None
    raise BridgeError(f"CORE_STATUS_FAILED:{error.get('code', 'UNKNOWN')}")


def _assert_source_fence(
    core_con: sqlite3.Connection,
    collection: str,
    source_key: str,
    content: bytes,
    media_type: str,
) -> None:
    response = core_api.fetch_original(
        core_con, collection, source_key, include_bytes=True,
    )
    if not response["ok"]:
        error = response.get("error") or {}
        raise BridgeError(f"CORE_SOURCE_FENCE_FAILED:{error.get('code', 'UNKNOWN')}")
    data = response["data"]
    try:
        stored = base64.b64decode(data["content_base64"], validate=True)
    except (KeyError, TypeError, ValueError):
        raise BridgeError("CORE_SOURCE_FENCE_INVALID") from None
    if (
        stored != content
        or data.get("media_type") != media_type
        or data.get("origin_uri") != f"airag-window:{source_key}"
    ):
        raise BridgeError("CORE_SOURCE_FENCE_MISMATCH")


def _assert_ready_profile(
    core_con: sqlite3.Connection, status: Mapping[str, object], profile_key: str,
) -> None:
    generation_id = status.get("ready_generation_id")
    revision_id = status.get("ready_revision_id")
    if (
        isinstance(generation_id, bool) or not isinstance(generation_id, int)
        or isinstance(revision_id, bool) or not isinstance(revision_id, int)
    ):
        raise BridgeError("CORE_READY_RECEIPT_INVALID")
    row = core_con.execute(
        "SELECT profile_key FROM generations WHERE generation_id=? AND revision_id=?",
        (generation_id, revision_id),
    ).fetchone()
    if row != (profile_key,):
        raise BridgeError("CORE_READY_PROFILE_MISMATCH")


def _finish_failed(
    lifecycle: Lifecycle,
    scope: AuthenticatedScope,
    window_id: str,
    error: Mapping[str, object],
) -> None:
    code = error.get("code")
    if not isinstance(code, str) or re.fullmatch(r"[A-Z][A-Z0-9_]{0,127}", code) is None:
        code = "CORE_PUBLICATION_FAILED"
    lifecycle.finish_publication(
        scope, window_id, success=False,
        error_code=code,
    )


def _publish_window(
    lifecycle: Lifecycle,
    scope: AuthenticatedScope,
    core_con: sqlite3.Connection,
    *,
    collection: str,
    profile_key: str,
    window_id: str,
) -> dict[str, object]:
    claim = lifecycle.claim_publication(scope, window_id)
    if claim.get("already_published") is True:
        return {
            "ok": True, "window_id": window_id,
            "source_key": source_key_for_window(window_id),
            "consumer_replay": True, "core": None,
        }
    content, media_type = _window_content(claim, scope)
    source_key = source_key_for_window(window_id)
    status = _core_status(core_con, collection, source_key)
    add_request_id = _request_id(
        "add", window_id, claim["document_sha256"], profile_key,
    )

    if status is None:
        response = core_api.add(
            core_con, add_request_id, collection, source_key, content,
            media_type=media_type, origin_uri=f"airag-window:{source_key}",
            profile_key=profile_key,
        )
        action = "add"
    else:
        _assert_source_fence(
            core_con, collection, source_key, content, media_type,
        )
        if status.get("searchable") is True and status.get("processing_status") == "ready":
            response = {
                "ok": True, "request_id": add_request_id,
                "data": {**status, "profile_key": profile_key, "replayed": True},
                "error": None,
            }
            action = "ready_replay"
        else:
            latest = status.get("latest_job")
            latest_status = latest.get("status") if isinstance(latest, dict) else None
            if latest_status in {"failed", "pending", "running"}:
                job_id = latest.get("job_id")
                attempt = claim.get("attempt")
                if (
                    isinstance(job_id, bool) or not isinstance(job_id, int)
                    or isinstance(attempt, bool) or not isinstance(attempt, int)
                ):
                    raise BridgeError("INVALID_CORE_RETRY_IDENTITY")
                failed_response = None
                if latest_status == "failed":
                    row = core_con.execute(
                        "SELECT final_response_json FROM jobs WHERE job_id=?", (job_id,),
                    ).fetchone()
                    if row is None or row[0] is None:
                        raise BridgeError("CORE_FAILURE_RECEIPT_MISSING")
                    try:
                        receipt = json.loads(row[0])
                    except (ValueError, TypeError):
                        raise BridgeError("INVALID_CORE_FAILURE_RECEIPT") from None
                    if not isinstance(receipt, dict) or not isinstance(receipt.get("error"), dict):
                        raise BridgeError("INVALID_CORE_FAILURE_RECEIPT")
                    if receipt["error"].get("retryable") is False:
                        failed_response = {"ok": False, "error": receipt["error"],
                                           "request_id": receipt.get("request_id")}
                if failed_response is not None:
                    response = failed_response
                    action = "terminal_failure"
                else:
                    retry_request_id = _request_id(
                        "retry", window_id, profile_key, job_id, attempt,
                    )
                    response = core_api.retry(
                        core_con, retry_request_id, job_id, profile_key=profile_key,
                    )
                    action = "retry"
            else:
                response = core_api.add(
                    core_con, add_request_id, collection, source_key, content,
                    media_type=media_type, origin_uri=f"airag-window:{source_key}",
                    profile_key=profile_key,
                )
                action = "add_replay"

    if not response["ok"]:
        error = response.get("error") or {"code": "CORE_PUBLICATION_FAILED"}
        _finish_failed(lifecycle, scope, window_id, error)
        return {
            "ok": False, "window_id": window_id, "source_key": source_key,
            "action": action, "core_request_id": response.get("request_id"),
            "error": error,
        }
    if response["data"].get("searchable") is not True:
        error = {"code": "CORE_NOT_SEARCHABLE", "retryable": True}
        _finish_failed(lifecycle, scope, window_id, error)
        return {
            "ok": False, "window_id": window_id, "source_key": source_key,
            "action": action, "core_request_id": response.get("request_id"),
            "error": error,
        }

    ready = _core_status(core_con, collection, source_key)
    if (
        ready is None or ready.get("searchable") is not True
        or ready.get("processing_status") != "ready"
    ):
        raise BridgeError("CORE_READY_RECEIPT_MISSING")
    _assert_source_fence(core_con, collection, source_key, content, media_type)
    _assert_ready_profile(core_con, ready, profile_key)

    current = lifecycle.refresh(scope)
    window = next(
        (item for item in current["windows"] if item["window_id"] == window_id),
        None,
    )
    if (
        window is None
        or window.get("invalidated_reason") is not None
        or window.get("document_sha256") != claim.get("document_sha256")
        or window_id not in current["pending_publication_ids"]
    ):
        return {
            "ok": False, "window_id": window_id, "source_key": source_key,
            "action": action, "core_request_id": response.get("request_id"),
            "error": {
                "code": "WINDOW_INELIGIBLE_AFTER_CORE_PUBLICATION",
                "retryable": False,
            },
        }
    lifecycle.finish_publication(scope, window_id, success=True)
    return {
        "ok": True, "window_id": window_id, "source_key": source_key,
        "action": action, "core_request_id": response.get("request_id"),
        "core": response["data"],
    }


def publish_pending_windows(
    lifecycle: Lifecycle,
    scope: AuthenticatedScope,
    core_con: sqlite3.Connection,
    *,
    collection: str,
    profile_key: str,
    task_completed: bool = False,
    explicit_save: bool = False,
) -> list[dict[str, object]]:
    """Refresh and publish every currently pending authorized window."""
    _require_text("collection", collection)
    if not isinstance(profile_key, str) or _PROFILE_KEY.fullmatch(profile_key) is None:
        raise BridgeError("INVALID_PROFILE_KEY")
    if type(task_completed) is not bool or type(explicit_save) is not bool:
        raise BridgeError("INVALID_CLOSE_TRIGGER")
    state = lifecycle.refresh(
        scope, task_completed=task_completed, explicit_save=explicit_save,
    )
    return [
        _publish_window(
            lifecycle, scope, core_con, collection=collection,
            profile_key=profile_key, window_id=window_id,
        )
        for window_id in state["pending_publication_ids"]
    ]


def verify_projection_links(
    lifecycle_state: Mapping[str, object],
    core_con: sqlite3.Connection,
    *,
    collection: str,
    profile_key: str,
) -> dict[str, dict[str, object]]:
    """Verify restored searchable windows map to ready core receipts."""
    _require_text("collection", collection)
    if not isinstance(profile_key, str) or _PROFILE_KEY.fullmatch(profile_key) is None:
        raise BridgeError("INVALID_PROFILE_KEY")
    window_ids = lifecycle_state.get("searchable_window_ids")
    if (
        not isinstance(window_ids, list)
        or len(window_ids) != len(set(window_ids))
        or any(not isinstance(item, str) for item in window_ids)
    ):
        raise BridgeError("INVALID_LIFECYCLE_STATE")
    result = {}
    for window_id in window_ids:
        source_key = source_key_for_window(window_id)
        status = _core_status(core_con, collection, source_key)
        if (
            status is None
            or status.get("deleted") is not False
            or status.get("searchable") is not True
            or status.get("processing_status") != "ready"
        ):
            raise BridgeError("RESTORED_PROJECTION_LINK_MISSING")
        source_id = status.get("source_id")
        revision_id = status.get("ready_revision_id")
        generation_id = status.get("ready_generation_id")
        if any(
            isinstance(value, bool) or not isinstance(value, int) or value <= 0
            for value in (source_id, revision_id, generation_id)
        ):
            raise BridgeError("RESTORED_PROJECTION_LINK_INVALID")
        generation = core_con.execute(
            "SELECT profile_key FROM generations WHERE generation_id=? AND revision_id=?",
            (generation_id, revision_id),
        ).fetchone()
        if generation != (profile_key,):
            raise BridgeError("RESTORED_PROJECTION_PROFILE_MISMATCH")
        original = core_api.fetch_original(
            core_con, collection, source_key, revision_id=revision_id,
        )
        if not original["ok"]:
            raise BridgeError("RESTORED_PROJECTION_REVISION_MISSING")
        data = original["data"]
        if (
            data.get("origin_uri") != f"airag-window:{window_id}"
            or data.get("media_type") != _CONVERSATION_MEDIA_TYPE
        ):
            raise BridgeError("RESTORED_PROJECTION_SOURCE_MISMATCH")
        result[window_id] = {
            "source_key": source_key, "source_id": source_id,
            "revision_id": revision_id, "generation_id": generation_id,
            "profile_key": profile_key, "content_hash": data.get("content_hash"),
        }
    return result


def _message_anchors(anchor: object) -> list[dict[str, object]]:
    if not isinstance(anchor, dict) or not isinstance(anchor.get("items"), list):
        return []
    anchors = []
    for item in anchor["items"]:
        if not isinstance(item, dict) or not isinstance(item.get("turn_id"), str):
            continue
        anchors.append({
            "turn_id": item["turn_id"], "pointer": item.get("pointer"),
            "kind": item.get("kind"), "granularity": item.get("granularity"),
        })
    return anchors


def _decorate_hit(hit: Mapping[str, object], manifest_id: int) -> dict[str, object]:
    return {
        **hit,
        "window_id": hit.get("source_key"),
        "message_anchors": _message_anchors(hit.get("anchor")),
        "core_receipt": {
            "manifest_id": manifest_id,
            "source_id": hit.get("source_id"),
            "revision_id": hit.get("revision_id"),
            "generation_id": hit.get("generation_id"),
            "content_hash": hit.get("content_hash"),
            "profile_key": None,
        },
    }


def search_history(
    lifecycle: Lifecycle,
    scope: AuthenticatedScope,
    core_con: sqlite3.Connection,
    *,
    collection: str,
    profile_key: str,
    query: str,
    top_k: int = 5,
) -> dict[str, object]:
    """Search all current authorized windows through core hybrid retrieval."""
    _require_text("collection", collection)
    _require_text("query", query)
    if not isinstance(profile_key, str) or _PROFILE_KEY.fullmatch(profile_key) is None:
        raise BridgeError("INVALID_PROFILE_KEY")
    if isinstance(top_k, bool) or not isinstance(top_k, int) or not 1 <= top_k <= core_search.MAX_TOP_K:
        raise BridgeError("INVALID_TOP_K")

    before = lifecycle.refresh(scope)
    window_ids = tuple(before["searchable_window_ids"])
    verify_projection_links(
        before, core_con, collection=collection, profile_key=profile_key,
    )
    if not window_ids:
        after = lifecycle.refresh(scope)
        if tuple(after["searchable_window_ids"]) != window_ids:
            raise BridgeError("ELIGIBILITY_CHANGED_DURING_SEARCH")
        return {
            "scope": scope.to_dict(), "collection": collection,
            "profile_key": profile_key, "query": query,
            "eligible_window_ids": [], "core_manifests": [], "results": [],
            "ranking": {"mode": "core_hybrid", "limitations": []},
        }

    partitions = [
        window_ids[index:index + _PARTITION_SIZE]
        for index in range(0, len(window_ids), _PARTITION_SIZE)
    ]
    manifests = []
    ranked = []
    for partition_index, source_keys in enumerate(partitions):
        response = core_api.search(
            core_con, collection, query, profile_key, top_k=top_k,
            request_id=_request_id(
                "search", profile_key, query, partition_index, source_keys,
            ),
            source_keys=source_keys,
        )
        if not response["ok"]:
            error = response.get("error") or {}
            raise BridgeError(f"CORE_SEARCH_FAILED:{error.get('code', 'UNKNOWN')}")
        data = response["data"]
        eligible = data.get("eligible", {})
        if eligible.get("count") != len(source_keys):
            raise BridgeError("CORE_SEARCH_ELIGIBILITY_MISMATCH")
        if data.get("profile_key") != profile_key:
            raise BridgeError("CORE_SEARCH_PROFILE_MISMATCH")
        manifest_id = data.get("manifest_id")
        if isinstance(manifest_id, bool) or not isinstance(manifest_id, int):
            raise BridgeError("INVALID_CORE_SEARCH_RECEIPT")
        manifests.append({
            "partition": partition_index, "manifest_id": manifest_id,
            "source_keys": list(source_keys),
            "profile_key": data.get("profile_key"),
            "eligible": eligible,
        })
        for rank, hit in enumerate(data.get("results", ()), start=1):
            if not isinstance(hit, dict) or hit.get("source_key") not in source_keys:
                raise BridgeError("CORE_SEARCH_SCOPE_VIOLATION")
            decorated = _decorate_hit(hit, manifest_id)
            decorated["core_receipt"]["profile_key"] = profile_key
            decorated["partition"] = partition_index
            decorated["partition_rank"] = rank
            decorated["bridge_rrf_score"] = 1.0 / (_BRIDGE_RRF_K + rank)
            ranked.append(decorated)

    after = lifecycle.refresh(scope)
    if tuple(after["searchable_window_ids"]) != window_ids:
        raise BridgeError("ELIGIBILITY_CHANGED_DURING_SEARCH")
    verify_projection_links(
        after, core_con, collection=collection, profile_key=profile_key,
    )
    ranked.sort(key=lambda item: (
        -item["bridge_rrf_score"], item["partition"],
        item.get("chunk_id") if isinstance(item.get("chunk_id"), int) else 0,
    ))
    limitations = []
    mode = "core_hybrid"
    if len(partitions) > 1:
        mode = "partitioned_core_hybrid_bridge_rrf"
        limitations.append(
            "Core source_keys are limited to 100; each bounded partition uses "
            "actual core hybrid retrieval, then equal-weight reciprocal-rank "
            "fusion combines partition-local ranks. Scores are not a single "
            "global core ranking."
        )
    return {
        "scope": scope.to_dict(), "collection": collection,
        "profile_key": profile_key, "query": query,
        "eligible_window_ids": list(window_ids),
        "core_manifests": manifests, "results": ranked[:top_k],
        "ranking": {"mode": mode, "limitations": limitations},
    }
