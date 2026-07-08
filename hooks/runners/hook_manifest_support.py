from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import TypeAlias, override

JsonValue: TypeAlias = (
    str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]
)
ManifestPayload: TypeAlias = dict[str, JsonValue]


@dataclass(frozen=True, slots=True)
class HookScaffoldError(Exception):
    message: str

    @override
    def __str__(self) -> str:
        return self.message


def load_manifests(hooks_root: Path) -> list[ManifestPayload]:
    manifest_dir = hooks_root / "manifests"
    manifest_paths = sorted(manifest_dir.glob("*.json"))
    if not manifest_paths:
        raise HookScaffoldError(f"no manifest files found under {manifest_dir}")
    manifests: list[ManifestPayload] = []
    for path in manifest_paths:
        payload = normalize_json_value(json.loads(path.read_text(encoding="utf-8")), path)
        if not isinstance(payload, dict):
            raise HookScaffoldError(f"manifest must be a JSON object: {path}")
        validate_manifest(hooks_root, path, payload)
        manifests.append(payload)
    return manifests


def normalize_json_value(value: object, path: Path) -> JsonValue:
    match value:
        case None | str() | int() | float() | bool():
            return value
        case list() as raw_list:
            return [normalize_json_value(item, path) for item in list(raw_list)]
        case dict() as raw_dict:
            normalized: ManifestPayload = {}
            for key, item in dict(raw_dict).items():
                if not isinstance(key, str):
                    raise HookScaffoldError(f"manifest keys must be strings: {path}")
                normalized[key] = normalize_json_value(item, path)
            return normalized
        case _:
            raise HookScaffoldError(f"manifest contains unsupported JSON value: {path}")


def validate_manifest(hooks_root: Path, path: Path, payload: ManifestPayload) -> None:
    name = payload.get("name")
    runner = payload.get("runner")
    support_files = payload.get("support_files")
    runtime_hooks = payload.get("runtime_hooks")
    if not isinstance(name, str) or not name:
        raise HookScaffoldError(f"manifest name missing: {path}")
    if not isinstance(runner, str) or not (hooks_root / runner).is_file():
        raise HookScaffoldError(f"manifest runner missing or invalid: {path}")
    if not isinstance(support_files, list) or not support_files:
        raise HookScaffoldError(f"manifest support_files missing: {path}")
    for item in support_files:
        if not isinstance(item, str) or not (hooks_root / item).is_file():
            raise HookScaffoldError(f"manifest support file missing: {path}")
    if not isinstance(runtime_hooks, list) or not runtime_hooks:
        raise HookScaffoldError(f"manifest runtime_hooks missing: {path}")
    for item in runtime_hooks:
        if not isinstance(item, dict):
            raise HookScaffoldError(f"manifest runtime hook invalid: {path}")
        adapter = item.get("adapter")
        if not isinstance(adapter, str) or not (hooks_root / "adapters" / adapter).is_file():
            raise HookScaffoldError(f"manifest adapter missing: {path}")
