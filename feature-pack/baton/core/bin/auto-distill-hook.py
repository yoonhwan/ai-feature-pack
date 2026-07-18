#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
# ─── How to run ───
# BYZ_AUTO_DISTILL_DRY_RUN=1 BYZ_AUTO_DISTILL_FORCE=1 python3 auto-distill-hook.py < payload.json
"""Codex hook adapter for a project-local baton auto-distill runner."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import TypeAlias

JsonValue: TypeAlias = None | bool | int | float | str | list["JsonValue"] | dict[str, "JsonValue"]
Payload: TypeAlias = dict[str, JsonValue]

ROOT = Path(os.environ.get("BYZ_AUTO_DISTILL_ROOT", str(Path.cwd()))).resolve()
DISTILL_SCRIPT = ROOT / ".baton/handoff/bin/auto-distill.sh"
STATE_PATH = ROOT / ".baton/handoff/distill/auto-distill-hook-state.json"
LOG_PATH = ROOT / ".baton/handoff/distill/auto-distill-hook.log"
HOOK_EVENTS = {"Stop", "UserPromptSubmit"}


def read_payload() -> Payload:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def as_float(value: JsonValue) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int | float):
        return float(value)
    if isinstance(value, str) and value.strip():
        try:
            return float(value.strip().rstrip("%"))
        except ValueError:
            return None
    return None


def nested(payload: Payload, *keys: str) -> JsonValue:
    current: JsonValue = payload
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def context_percent(payload: Payload) -> float | None:
    keys = [
        ("context_percent",), ("contextPercent",), ("context_percentage",),
        ("contextPercentage",), ("percent_context_used",),
        ("context", "percent"), ("context", "used_percent"),
        ("context", "usage_percent"), ("usage", "context_percent"),
        ("usage", "contextPercent"), ("usage", "percent_context_used"),
        ("usage", "input_percent"), ("token_usage", "context_percent"),
        ("tokenUsage", "contextPercent"),
    ]
    for path in keys:
        value = as_float(nested(payload, *path))
        if value is not None:
            return value * 100 if 0 <= value <= 1 else value
    return None


def text_field(payload: Payload, *keys: str) -> str:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def payload_cwd(payload: Payload) -> Path:
    value = text_field(payload, "cwd", "project_path", "projectPath")
    return Path(value).expanduser().resolve() if value else Path.cwd().resolve()


def transcript_path(payload: Payload) -> Path | None:
    value = text_field(payload, "transcript_path", "transcriptPath")
    if not value:
        return None
    path = Path(value).expanduser()
    return path if path.is_absolute() else payload_cwd(payload) / path


def transcript_size(payload: Payload) -> int | None:
    path = transcript_path(payload)
    if path is None:
        return None
    try:
        return path.stat().st_size
    except OSError:
        return None


def int_env(name: str, default: int) -> int:
    try:
        value = int(os.environ.get(name, ""))
    except ValueError:
        return default
    return value if value >= 0 else default


def float_env(name: str, default: float) -> float:
    value = as_float(os.environ.get(name))
    return default if value is None else value


def load_state() -> Payload:
    try:
        parsed = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


def write_json(path: Path, payload: Payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def log_event(payload: Payload) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    record: Payload = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), **payload}
    with LOG_PATH.open("a", encoding="utf-8") as file:
        file.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def decision(payload: Payload) -> tuple[bool, str, str, Payload]:
    percent = context_percent(payload)
    size = transcript_size(payload)
    percent_limit = float_env("BYZ_AUTO_DISTILL_PERCENT_THRESHOLD", 80.0)
    bytes_limit = int_env("BYZ_AUTO_DISTILL_TRANSCRIPT_BYTES", 1_200_000)
    facts: Payload = {
        "context_percent": percent,
        "transcript_bytes": size,
        "percent_threshold": percent_limit,
        "bytes_threshold": bytes_limit,
    }
    if os.environ.get("BYZ_AUTO_DISTILL_FORCE") == "1" or payload.get("byz_auto_distill_force") is True:
        return True, "auto-hook-force", "forced", facts
    if percent is not None and percent >= percent_limit:
        return True, "auto-hook-context-percent", f"{percent:.0f}", facts
    if size is not None and size >= bytes_limit:
        ratio = round(size / bytes_limit * percent_limit)
        return True, "auto-hook-transcript-pressure", f"approx-{min(99, ratio)}", facts
    return False, "below-threshold", f"{percent:.0f}" if percent is not None else "unknown", facts


def main() -> int:
    payload = read_payload()
    event = text_field(payload, "hook_event_name", "hookEventName", "event", "name")
    dry_run = os.environ.get("BYZ_AUTO_DISTILL_DRY_RUN") == "1"
    if payload_cwd(payload) != ROOT or (event and event not in HOOK_EVENTS):
        return 0
    if not DISTILL_SCRIPT.is_file():
        return 0
    should_trigger, reason, percent, facts = decision(payload)
    if not should_trigger:
        log_event({"action": "skip", "reason": reason, "event": event, **facts})
        return 0
    size = facts.get("transcript_bytes")
    bucket = None if not isinstance(size, int) else size // max(1, int_env("BYZ_AUTO_DISTILL_SIGNATURE_BYTES", 250_000))
    signature = f"{event}|{reason}|{percent}|{transcript_path(payload) or 'no-transcript'}|{bucket}"
    state = load_state()
    now = int(time.time())
    last_triggered_at = state.get("last_triggered_at")
    last_seconds = last_triggered_at if isinstance(last_triggered_at, int) and not isinstance(last_triggered_at, bool) else 0
    cooldown = int_env("BYZ_AUTO_DISTILL_COOLDOWN_SECONDS", 1800)
    if not dry_run and state.get("last_signature") == signature and now - last_seconds < cooldown:
        log_event({"action": "skip", "reason": "cooldown", "event": event, "signature": signature, **facts})
        return 0
    command = [str(DISTILL_SCRIPT), "--reason", reason, "--percent", percent]
    if dry_run:
        log_event({"action": "dry-run", "event": event, "signature": signature, "command": " ".join(command), **facts})
        return 0
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    write_json(STATE_PATH, {"last_signature": signature, "last_triggered_at": now, "last_reason": reason, "last_percent": percent, "last_event": event, "last_returncode": result.returncode})
    log_event({"action": "trigger", "event": event, "signature": signature, "returncode": result.returncode, "stdout_tail": result.stdout[-1000:], "stderr_tail": result.stderr[-1000:], **facts})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
