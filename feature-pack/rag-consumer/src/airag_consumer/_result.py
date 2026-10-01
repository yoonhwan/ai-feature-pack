"""Pure value-free filters for a consumer pass: summary whitelist and reason-code reporting.

Imports only the standard library and ``reason_codes``; it must never import runtime components.
"""

from __future__ import annotations

import json
import re
from typing import Mapping

from .reason_codes import REASON_CODES

_CODE = re.compile(r"[A-Z][A-Z0-9_]{1,100}")
_TYPE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,60}")


def summarize(data: Mapping[str, object]) -> dict[str, object]:
    """Numbers and flags only: never conversation, memory text, quotes or paths."""
    summary: dict[str, object] = {}
    collected = data.get("collected")
    if isinstance(collected, list):
        rows = [row for row in collected if isinstance(row, dict)]
        summary["sources"] = len(rows)
        summary["accepted"] = sum(row.get("accepted_count", 0) for row in rows if type(row.get("accepted_count")) is int)
        summary["gaps"] = sum(row.get("gap_count", 0) for row in rows if type(row.get("gap_count")) is int)
        for key in ("committed_native_offset", "pending_bytes"):
            summary[f"{key}_total"] = sum(row[key] for row in rows if type(row.get(key)) is int)
        summary["coverage_complete"] = bool(rows) and all(row.get("coverage_complete") is True for row in rows)
    published = data.get("published")
    if isinstance(published, dict):
        for key in ("attempted", "succeeded"):
            if type(published.get(key)) is int:
                summary[f"published_{key}"] = published[key]
    memory = data.get("memory")
    if isinstance(memory, dict):
        summary["memory_enabled"] = memory.get("enabled") is True
        for key in (
            "attempts", "candidate_count", "materialized_count", "awaiting_confirmation_count",
            "unverified_count", "conflict_count", "rejected_count", "batch_message_count",
        ):
            if type(memory.get(key)) is int:
                summary[f"memory_{key}"] = memory[key]
        if isinstance(memory.get("provider_called"), bool):
            summary["memory_provider_called"] = memory["provider_called"]
    if isinstance(data.get("archives"), list):
        summary["archived"] = len(data["archives"])
    backup = data.get("backup")
    if isinstance(backup, dict):
        summary["backup_due"] = backup.get("due") is True
        summary["backup_created"] = backup.get("created") is True
    return summary


def _safe_code(value: object) -> str:
    """Report a reason code only if it is a known one; an error message is data, not a code."""
    if isinstance(value, str) and _CODE.fullmatch(value) and value in REASON_CODES:
        return value
    return "RUNTIME_FAILED"


def error_fields(stream: str) -> tuple[str, str]:
    try:
        error = json.loads(stream.strip().splitlines()[-1])["error"]
    except (ValueError, KeyError, IndexError, TypeError):
        return "RUNTIME_FAILED", ""
    kind = error.get("type") if isinstance(error, dict) else None
    kind = kind if isinstance(kind, str) and _TYPE.fullmatch(kind) and not re.search(r"[0-9a-fA-F]{16}", kind) else ""
    return _safe_code(error.get("code") if isinstance(error, dict) else None), kind


RESULT_MAX_BYTES = 64 * 1024
SUMMARY_INT_KEYS = frozenset({
    "sources", "accepted", "gaps", "committed_native_offset_total", "pending_bytes_total",
    "published_attempted", "published_succeeded", "memory_attempts", "memory_candidate_count",
    "memory_materialized_count", "memory_awaiting_confirmation_count", "memory_unverified_count",
    "memory_conflict_count", "memory_rejected_count", "memory_batch_message_count", "archived",
})
SUMMARY_BOOL_KEYS = frozenset({
    "coverage_complete", "memory_enabled", "memory_provider_called", "backup_due", "backup_created",
})
FRAME_KEYS = frozenset({"exit", "summary", "code", "type"})
FRAME_CODES = REASON_CODES | {"RUNTIME_FAILED", "RUNTIME_OUTPUT_INVALID"}


def _clean_type(value: object) -> str:
    return value if isinstance(value, str) and _TYPE.fullmatch(value) and not re.search(r"[0-9a-fA-F]{16}", value) else ""


def build_frame(exit_code: int, stdout_text: str, stderr_text: str) -> dict[str, object]:
    """Reduce a pass's raw CLI output to ``{exit, summary, code, type}``: numbers, flags, known codes."""
    if exit_code == 0:
        try:
            data = json.loads(stdout_text)["data"]
        except (ValueError, KeyError, TypeError):
            data = None
        if not isinstance(data, dict):
            return {"exit": 0, "summary": {}, "code": "RUNTIME_OUTPUT_INVALID", "type": ""}
        return {"exit": 0, "summary": summarize(data), "code": "", "type": ""}
    code, kind = error_fields(stderr_text)
    return {"exit": exit_code, "summary": {}, "code": code, "type": kind}


def validate_frame(frame: object) -> dict[str, object] | None:
    """Strict re-check of a frame; anything outside the closed schema is rejected (None)."""
    if not isinstance(frame, dict) or set(frame) != FRAME_KEYS:
        return None
    if type(frame["exit"]) is not int or not isinstance(frame["summary"], dict):
        return None
    for key, value in frame["summary"].items():
        if not (
            (key in SUMMARY_INT_KEYS and type(value) is int)
            or (key in SUMMARY_BOOL_KEYS and type(value) is bool)
        ):
            return None
    if frame["code"] != "" and frame["code"] not in FRAME_CODES:
        return None
    if frame["type"] != "" and _clean_type(frame["type"]) != frame["type"]:
        return None
    return frame
