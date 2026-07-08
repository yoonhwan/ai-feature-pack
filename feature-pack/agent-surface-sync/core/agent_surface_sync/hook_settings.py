from __future__ import annotations

import json
from pathlib import Path

from .models import (
    JsonObject,
    JsonValue,
    PlannedAction,
    SyncConfig,
    SyncError,
    is_json_object,
    json_objects,
)


def plan_hook_setting_actions(
    config: SyncConfig,
) -> tuple[list[PlannedAction], list[JsonObject]]:
    hooks_root = config.repo_root / "hooks"
    manifest_root = hooks_root / "manifests"
    if not manifest_root.is_dir():
        return [], []
    manifests = load_manifests(manifest_root)
    actions: list[PlannedAction] = []
    skipped: list[JsonObject] = []
    for runtime_name, snippet in hook_snippets(manifests).items():
        if config.runtime not in {"all", runtime_name}:
            continue
        target = hook_target(config.home, runtime_name)
        if target is None:
            skipped.append(
                {
                    "package": "shared-hooks",
                    "runtime": runtime_name,
                    "kind": "hook-config",
                    "target": runtime_name,
                    "reason": "runtime-not-installed",
                },
            )
            continue
        action = build_hook_action(config, hooks_root, runtime_name, target, snippet)
        if action is not None:
            actions.append(action)
    return actions, skipped


def load_manifests(manifest_root: Path) -> list[JsonObject]:
    manifests: list[JsonObject] = []
    for path in sorted(manifest_root.glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise SyncError(f"hook manifest must be a JSON object: {path}")
        manifests.append(payload)
    return manifests


def hook_snippets(manifests: list[JsonObject]) -> dict[str, JsonObject]:
    hooks_by_runtime: dict[str, dict[str, list[JsonObject]]] = {}
    for manifest in manifests:
        runtime_hooks = manifest.get("runtime_hooks")
        if not isinstance(runtime_hooks, list):
            continue
        for hook in runtime_hooks:
            if not is_json_object(hook):
                continue
            runtime_name = get_string(hook.get("runtime"))
            event = get_string(hook.get("event"))
            adapter = get_string(hook.get("adapter"))
            level = get_string(hook.get("level"))
            if runtime_name is None or event is None or adapter is None or level is None:
                continue
            command_entry: JsonObject = {
                "type": "command",
                "command": f"$HOME/.agents/hooks/adapters/{adapter} {level}",
                "timeout": 5,
            }
            status_message = get_string(hook.get("status_message"))
            if runtime_name == "codex-cli" and status_message is not None:
                command_entry["statusMessage"] = status_message
            hooks_by_runtime.setdefault(runtime_name, {}).setdefault(event, []).append(
                command_entry,
            )
    snippets: dict[str, JsonObject] = {}
    for runtime_name, by_event in hooks_by_runtime.items():
        hooks: dict[str, JsonValue] = {}
        for event, commands in sorted(by_event.items()):
            hooks[event] = [{"hooks": json_objects(commands)}]
        snippets[runtime_name] = {"hooks": hooks}
    return snippets


def hook_target(home: Path, runtime_name: str) -> Path | None:
    match runtime_name:
        case "claude-code":
            root = home / ".claude"
            return root / "settings.json" if root.is_dir() else None
        case "codex-cli":
            root = home / ".codex"
            return root / "hooks.json" if root.is_dir() else None
        case _:
            return None


def build_hook_action(
    config: SyncConfig,
    hooks_root: Path,
    runtime_name: str,
    target: Path,
    snippet: JsonObject,
) -> PlannedAction | None:
    current_root = read_json_object(target) if target.exists() else {}
    merged_root = merge_hook_snippet(current_root, snippet)
    rendered_content = normalize_json_text(merged_root)
    if target.exists():
        current_content = normalize_json_text(current_root)
        state = "up-to-date" if current_content == rendered_content else "merge"
    else:
        state = "install"
    backup_path = (
        build_backup_path(config, target)
        if target.exists() and state != "up-to-date"
        else None
    )
    notes = tuple(sorted(get_hook_events(snippet)))
    return PlannedAction(
        package="shared-hooks",
        runtime=runtime_name,
        kind="hook-config",
        source=hooks_root,
        target=target,
        state=state,
        backup_path=backup_path,
        notes=notes,
        rendered_content=rendered_content,
    )


def merge_hook_snippet(current_root: JsonObject, snippet: JsonObject) -> JsonObject:
    merged_root = dict(current_root)
    existing_hooks = merged_root.get("hooks")
    hooks_root: JsonObject
    if is_json_object(existing_hooks):
        hooks_root = dict(existing_hooks)
    else:
        hooks_root = {}
    snippet_hooks = snippet.get("hooks")
    if not is_json_object(snippet_hooks):
        raise SyncError("hook snippet missing hooks object")
    for event, incoming_value in snippet_hooks.items():
        incoming_groups = get_group_list(incoming_value)
        existing_value = hooks_root.get(event)
        existing_groups = get_group_list(existing_value)
        hooks_root[event] = dedupe_groups(existing_groups, incoming_groups)
    merged_root["hooks"] = hooks_root
    return merged_root


def get_group_list(value: JsonValue | None) -> list[JsonObject]:
    if not isinstance(value, list):
        return []
    groups: list[JsonObject] = []
    for item in value:
        if is_json_object(item):
            groups.append(item)
    return groups


def dedupe_groups(existing: list[JsonObject], incoming: list[JsonObject]) -> list[JsonValue]:
    merged: list[JsonValue] = []
    seen: set[str] = set()
    for group in [*existing, *incoming]:
        key = json.dumps(group, sort_keys=True, ensure_ascii=False)
        if key in seen:
            continue
        seen.add(key)
        merged.append(group)
    return merged


def read_json_object(path: Path) -> JsonObject:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SyncError(f"hook config must be a JSON object: {path}")
    return payload


def normalize_json_text(payload: JsonObject) -> str:
    return json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def get_hook_events(snippet: JsonObject) -> set[str]:
    hooks = snippet.get("hooks")
    if not is_json_object(hooks):
        return set()
    return set(hooks)


def get_string(value: JsonValue | None) -> str | None:
    if isinstance(value, str):
        return value
    return None


def build_backup_path(config: SyncConfig, target: Path) -> Path:
    safe_name = "__".join(target.expanduser().parts[1:])
    return (
        config.home
        / ".agents"
        / "state"
        / "agent-surface-sync"
        / "backups"
        / config.operation_id
        / safe_name
    )
