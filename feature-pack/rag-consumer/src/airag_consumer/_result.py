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
