from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Final, TypeAlias, override

JsonValue: TypeAlias = (
    str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]
)
JsonObject: TypeAlias = dict[str, JsonValue]

PERCENT_KEYS: Final[tuple[str, ...]] = (
    "consumed_context_percent",
    "context_used_percent",
    "used_percent",
)
ENV_PERCENT_KEYS: Final[tuple[str, ...]] = (
    "AGENTS_CONTEXT_USED_PERCENT",
    "HOOK_CONTEXT_USED_PERCENT",
)


@dataclass(frozen=True, slots=True)
class PercentRange:
    min_percent: int
    max_percent: int

    def includes(self, value: int) -> bool:
        return self.min_percent <= value <= self.max_percent


@dataclass(frozen=True, slots=True)
class Threshold:
    level: str
    percent_range: PercentRange
    message: str
    recommendation: str


@dataclass(frozen=True, slots=True)
class ContextPressureError(Exception):
    message: str

    @override
    def __str__(self) -> str:
        return self.message


def main() -> int:
    try:
        runtime, level, dry_run, used_percent = parse_args(sys.argv[1:])
        threshold = load_threshold(level)
        resolved_percent = used_percent if used_percent is not None else discover_percent()
        triggered = resolved_percent is not None and threshold.percent_range.includes(
            resolved_percent,
        )
        message = render_message(threshold)
        if dry_run:
            print(
                json.dumps(
                    {
                        "runtime": runtime,
                        "level": level,
                        "used_percent": resolved_percent,
                        "triggered": triggered,
                        "message": message,
                    },
                    indent=2,
                    sort_keys=True,
                ),
            )
            return 0
        if not triggered:
            return 0
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "UserPromptSubmit",
                        "additionalContext": message,
                    },
                },
                ensure_ascii=False,
            ),
        )
    except ContextPressureError as error:
        print(f"context-pressure: {error}", file=sys.stderr)
        return 2
    return 0


def parse_args(args: list[str]) -> tuple[str, str, bool, int | None]:
    runtime = "claude-code"
    level = "boundary"
    dry_run = False
    used_percent: int | None = None
    index = 0
    while index < len(args):
        token = args[index]
        match token:
            case "--runtime":
                runtime, index = read_string_value(args, index, "--runtime")
            case "--level":
                level, index = read_string_value(args, index, "--level")
            case "--used-percent":
                used_percent, index = read_int_value(args, index, "--used-percent")
            case "--dry-run":
                dry_run = True
                index += 1
            case "--help" | "-h":
                raise ContextPressureError(usage())
            case _:
                raise ContextPressureError(f"unknown argument: {token}\n{usage()}")
    if runtime not in {"claude-code", "codex-cli"}:
        raise ContextPressureError("--runtime must be claude-code or codex-cli")
    if level not in {"boundary", "warning"}:
        raise ContextPressureError("--level must be boundary or warning")
    return runtime, level, dry_run, used_percent


def read_string_value(args: list[str], index: int, flag: str) -> tuple[str, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise ContextPressureError(f"{flag} requires a value")
    value = args[value_index]
    if value.startswith("--"):
        raise ContextPressureError(f"{flag} requires a value")
    return value, index + 2


def read_int_value(args: list[str], index: int, flag: str) -> tuple[int, int]:
    value, next_index = read_string_value(args, index, flag)
    try:
        return int(value), next_index
    except ValueError as error:
        raise ContextPressureError(f"{flag} must be an integer") from error


def load_manifest_payload(manifest_path: Path) -> JsonObject:
    payload = normalize_json_value(json.loads(manifest_path.read_text(encoding="utf-8")))
    if not isinstance(payload, dict):
        raise ContextPressureError(f"manifest must be a JSON object: {manifest_path}")
    return payload


def normalize_json_value(value: object) -> JsonValue:
    match value:
        case None | str() | int() | float() | bool():
            return value
        case list() as raw_list:
            return [normalize_json_value(item) for item in list(raw_list)]
        case dict() as raw_dict:
            normalized: JsonObject = {}
            for key, item in dict(raw_dict).items():
                if not isinstance(key, str):
                    raise ContextPressureError("manifest keys must be strings")
                normalized[key] = normalize_json_value(item)
            return normalized
        case _:
            raise ContextPressureError("manifest contains unsupported JSON value")


def load_threshold(level: str) -> Threshold:
    manifest_path = Path(__file__).resolve().parents[1] / "manifests" / "context-pressure.json"
    payload = load_manifest_payload(manifest_path)
    thresholds = payload.get("thresholds")
    if not isinstance(thresholds, list):
        raise ContextPressureError("manifest thresholds are missing")
    for item in thresholds:
        if not isinstance(item, dict):
            continue
        if item.get("id") != level:
            continue
        percent = item.get("consumed_context_percent")
        if not isinstance(percent, dict):
            break
        min_percent = percent.get("min")
        max_percent = percent.get("max")
        if not isinstance(min_percent, int) or not isinstance(max_percent, int):
            break
        message = item.get("message")
        recommendation = item.get("recommendation")
        if not isinstance(message, str) or not isinstance(recommendation, str):
            break
        return Threshold(
            level=level,
            percent_range=PercentRange(min_percent, max_percent),
            message=message,
            recommendation=recommendation,
        )
    raise ContextPressureError(f"threshold not found for level: {level}")


def discover_percent() -> int | None:
    for env_key in ENV_PERCENT_KEYS:
        value = os.environ.get(env_key)
        if value is None:
            continue
        try:
            return int(value)
        except ValueError:
            continue
    stdin_payload = sys.stdin.read()
    if not stdin_payload.strip():
        return None
    try:
        data = json.loads(stdin_payload)
    except json.JSONDecodeError:
        return None
    return find_percent(data)


def find_percent(value: JsonValue) -> int | None:
    match value:
        case int() as number:
            return number if 0 <= number <= 100 else None
        case dict() as mapping:
            for key in PERCENT_KEYS:
                candidate = mapping.get(key)
                if isinstance(candidate, int) and 0 <= candidate <= 100:
                    return candidate
            for nested in mapping.values():
                candidate = find_percent(nested)
                if candidate is not None:
                    return candidate
        case list() as items:
            for item in items:
                candidate = find_percent(item)
                if candidate is not None:
                    return candidate
        case _:
            return None
    return None


def render_message(threshold: Threshold) -> str:
    return (
        f"[context-pressure:{threshold.level}] {threshold.message} "
        f"권장: {threshold.recommendation}. "
        "후속 명령: 세션증류/증류/세션만들기/신규세션, 분리."
    )


def usage() -> str:
    return (
        "Usage: context-pressure.sh --runtime claude-code|codex-cli "
        "--level boundary|warning [--used-percent N] [--dry-run]"
    )


if __name__ == "__main__":
    raise SystemExit(main())
