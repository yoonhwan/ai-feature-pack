"""Pure value-free filters for a consumer pass: summary whitelist and reason-code reporting.

Imports only the standard library and ``reason_codes``; it must never import runtime components.
"""

from __future__ import annotations

from collections import Counter
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
    if "published" in data:
        summary.update(_publish_summary(data["published"]))
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
    "published_failed", "published_failed_other",
    "published_failed_count_1", "published_failed_count_2", "published_failed_count_3",
})
SUMMARY_CODE_KEYS = frozenset({"published_failed_code_1", "published_failed_code_2", "published_failed_code_3"})
SUMMARY_BOOL_KEYS = frozenset({
    "coverage_complete", "memory_enabled", "memory_provider_called", "backup_due", "backup_created",
})
FRAME_KEYS = frozenset({"exit", "summary", "code", "type"})
FRAME_CODES = REASON_CODES | {"RUNTIME_FAILED", "RUNTIME_OUTPUT_INVALID"}


PUBLISH_FALLBACK_CODE = "CORE_PUBLICATION_FAILED"
_SLOTS = (1, 2, 3)


def _publish_failure_code(item: object) -> str:
    """The registered code of one failed publication; anything else is the fallback (never the raw value)."""
    error = item.get("error") if isinstance(item, dict) else None
    code = error.get("code") if isinstance(error, dict) else None
    if isinstance(code, str) and _CODE.fullmatch(code) and code in REASON_CODES:
        return code
    return PUBLISH_FALLBACK_CODE


def _publish_summary(published: object) -> dict[str, object]:
    """Counts and a top-3 failure-code tally for one pass's publications; inconsistent input raises ValueError."""
    if not isinstance(published, dict):
        raise ValueError("published must be an object")
    attempted, succeeded, items = published.get("attempted"), published.get("succeeded"), published.get("items")
    if (
        type(attempted) is not int or type(succeeded) is not int or attempted < 0
        or not 0 <= succeeded <= attempted or not isinstance(items, list)
    ):
        raise ValueError("published counts are malformed")
    failed_items = [item for item in items if not (isinstance(item, dict) and item.get("ok") is True)]
    if len(items) != attempted or len(items) - len(failed_items) != succeeded:
        raise ValueError("published counts disagree with its items")
    tally = sorted(
        Counter(_publish_failure_code(item) for item in failed_items).items(), key=lambda pair: (-pair[1], pair[0]),
    )[:len(_SLOTS)]
    result: dict[str, object] = {
        "published_attempted": attempted, "published_succeeded": succeeded,
        "published_failed": len(failed_items), "published_failed_other": len(failed_items) - sum(n for _, n in tally),
    }
    for slot, (code, count) in zip(_SLOTS, tally):
        result[f"published_failed_code_{slot}"], result[f"published_failed_count_{slot}"] = code, count
    return result


def _publish_group_ok(summary: Mapping[str, object]) -> bool:
    """Relations a diagnostic group must satisfy: all-or-none, arithmetic, contiguous ranks, order, totals."""
    base = ("published_attempted", "published_succeeded", "published_failed", "published_failed_other")
    codes = {slot for slot in _SLOTS if f"published_failed_code_{slot}" in summary}
    counts = {slot for slot in _SLOTS if f"published_failed_count_{slot}" in summary}
    present = [key in summary for key in base]
    if not any(present):
        return not codes and not counts
    if not all(present):
        return False
    attempted, succeeded, failed, other = (summary[key] for key in base)
    if min(attempted, succeeded, failed, other) < 0 or succeeded > attempted or failed != attempted - succeeded:
        return False
    k = len(codes)
    if codes != counts or codes != set(_SLOTS[:k]):
        return False
    tally = [(summary[f"published_failed_count_{slot}"], summary[f"published_failed_code_{slot}"]) for slot in _SLOTS[:k]]
    keys = [(-count, code) for count, code in tally]
    if any(count <= 0 for count, _ in tally) or any(a >= b for a, b in zip(keys, keys[1:])):
        return False
    if len({code for _, code in tally}) != k:  # a code owns one rank, whatever its count
        return False
    if sum(count for count, _ in tally) + other != failed:
        return False
    return not (k < len(_SLOTS) and other != 0) and not (failed == 0 and k != 0)



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
        try:
            summary = summarize(data)
        except ValueError:
            return {"exit": 0, "summary": {}, "code": "RUNTIME_OUTPUT_INVALID", "type": ""}
        return {"exit": 0, "summary": summary, "code": "", "type": ""}
    code, kind = error_fields(stderr_text)
    return {"exit": exit_code, "summary": {}, "code": code, "type": kind}


def validate_frame(frame: object) -> dict[str, object] | None:
    """Strict re-check of a frame; anything outside the closed schema is rejected (None)."""
    if not isinstance(frame, dict) or set(frame) not in (FRAME_KEYS, FRAME_KEYS | OPTIONAL_FRAME_KEYS):
        return None
    if type(frame["exit"]) is not int or not isinstance(frame["summary"], dict):
        return None
    for key, value in frame["summary"].items():
        if not (
            (key in SUMMARY_INT_KEYS and type(value) is int)
            or (key in SUMMARY_BOOL_KEYS and type(value) is bool)
            or (key in SUMMARY_CODE_KEYS and isinstance(value, str) and value in REASON_CODES)
        ):
            return None
    if not _publish_group_ok(frame["summary"]):
        return None
    if not isinstance(frame["code"], str) or (frame["code"] != "" and frame["code"] not in FRAME_CODES):
        return None
    if frame["type"] != "" and _clean_type(frame["type"]) != frame["type"]:
        return None
    if "integrity" in frame and not integrity_valid(frame["integrity"]):
        return {key: value for key, value in frame.items() if key != "integrity"}  # only the field goes
    return frame


# The DB check's record (optional frame field `integrity`, optional top-level field of the tick's log line).
OPTIONAL_FRAME_KEYS = frozenset({"integrity"})
INTEGRITY_VERSION = 1
INTEGRITY_DBS = ("consumer", "projection")
INTEGRITY_OUTCOMES = ("ok", "not_ok", "deadline", "open_error", "identity_error")
INTEGRITY_MAX_BYTES = 512
_INTEGRITY_MS_MAX = 120_000.0


def integrity_valid(record: object) -> bool:
    """The closed schema: ``{"v":1,"dbs":[{"db","out","ms"}, ...]}`` with one entry per database, nothing else."""
    try:
        if type(record) is not dict or set(record) != {"v", "dbs"}:
            return False
        if type(record["v"]) is not int or record["v"] != INTEGRITY_VERSION:
            return False
        entries = record["dbs"]
        if type(entries) is not list or not 1 <= len(entries) <= len(INTEGRITY_DBS):
            return False
        seen: set[str] = set()
        for entry in entries:
            if type(entry) is not dict or set(entry) != {"db", "out", "ms"}:
                return False
            if entry["db"] not in INTEGRITY_DBS or entry["db"] in seen or entry["out"] not in INTEGRITY_OUTCOMES:
                return False
            ms = entry["ms"]
            if not (type(ms) is float and 0.0 <= ms <= _INTEGRITY_MS_MAX):  # NaN fails every comparison
                return False
            seen.add(entry["db"])
        return len(json.dumps(record, sort_keys=True, separators=(",", ":")).encode("utf-8")) <= INTEGRITY_MAX_BYTES
    except Exception:
        return False
