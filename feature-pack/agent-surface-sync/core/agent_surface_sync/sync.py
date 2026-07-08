from __future__ import annotations

import json
from pathlib import Path

from .hook_settings import plan_hook_setting_actions
from .models import (
    JsonObject,
    PlannedAction,
    SyncConfig,
    SyncError,
    is_json_object,
    json_objects,
    string_values,
)

RUNTIME_ALIASES = {
    "agents": "agents",
    "all": "all",
    "claude": "claude-code",
    "claude-code": "claude-code",
    "codex": "codex-cli",
    "codex-cli": "codex-cli",
}


def run_sync(config: SyncConfig) -> JsonObject:
    actions, skipped = plan_actions(config)
    if config.apply:
        apply_actions(actions)
    changed = [action_to_json(action, config) for action in actions if action.changed]
    return {
        "repo_root": compact_path(config.repo_root, config.repo_root, config.home),
        "apply": config.apply,
        "operation_id": config.operation_id,
        "actions": json_objects([action_to_json(action, config) for action in actions]),
        "changed_actions": json_objects(changed),
        "rollback": string_values(
            [rollback_command(action, config) for action in actions if action.changed],
        ),
        "skipped": json_objects(skipped),
    }


def plan_actions(config: SyncConfig) -> tuple[list[PlannedAction], list[JsonObject]]:
    actions: list[PlannedAction] = []
    skipped: list[JsonObject] = []
    for package_root in package_roots(config):
        manifest = read_manifest(package_root / "manifest.json")
        package_name = package_root.name
        actions.extend(plan_command_links(package_root, package_name, manifest, config))
        package_actions, package_skipped = plan_runtime_links(
            package_root,
            package_name,
            manifest,
            config,
        )
        actions.extend(package_actions)
        skipped.extend(package_skipped)
    hooks_root = config.repo_root / "hooks"
    if hooks_root.is_dir():
        actions.append(
            build_action(
                package="shared-hooks",
                runtime="agents",
                kind="hook-source",
                source=hooks_root,
                target=config.home / ".agents" / "hooks",
                config=config,
            ),
        )
    hook_actions, hook_skipped = plan_hook_setting_actions(config)
    actions.extend(hook_actions)
    skipped.extend(hook_skipped)
    return actions, skipped


def package_roots(config: SyncConfig) -> list[Path]:
    feature_pack = config.repo_root / "feature-pack"
    if not feature_pack.is_dir():
        raise SyncError(f"feature-pack directory not found: {feature_pack}")
    filters = set(config.packages or ())
    package_paths: list[Path] = []
    for package in sorted(feature_pack.iterdir()):
        if not package.is_dir():
            continue
        if filters and package.name not in filters:
            continue
        if not (package / "manifest.json").is_file():
            continue
        package_paths.append(package)
    return package_paths


def read_manifest(path: Path) -> JsonObject:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SyncError(f"manifest must be a JSON object: {path}")
    return payload


def plan_command_links(
    package_root: Path,
    package_name: str,
    manifest: JsonObject,
    config: SyncConfig,
) -> list[PlannedAction]:
    command_values = manifest.get("commands")
    if not isinstance(command_values, list):
        return []
    actions: list[PlannedAction] = []
    for entry in command_values:
        if not is_json_object(entry):
            continue
        kind = string_field(entry, "kind")
        name = string_field(entry, "name")
        rel_path = string_field(entry, "path")
        if kind not in {"cli-binary", "cli-support"} or name is None or rel_path is None:
            continue
        source = package_root / rel_path
        actions.append(
            build_action(
                package=package_name,
                runtime="agents",
                kind=kind,
                source=source,
                target=config.home / ".agents" / "bin" / name,
                config=config,
            ),
        )
    return actions


def plan_runtime_links(
    package_root: Path,
    package_name: str,
    manifest: JsonObject,
    config: SyncConfig,
) -> tuple[list[PlannedAction], list[JsonObject]]:
    runtime_targets = manifest.get("runtime_targets")
    if not isinstance(runtime_targets, list):
        return [], []
    actions: list[PlannedAction] = []
    skipped: list[JsonObject] = []
    for entry in runtime_targets:
        if not is_json_object(entry):
            continue
        status = string_field(entry, "status")
        runtime_name = normalize_runtime(string_field(entry, "runtime"))
        kind = string_field(entry, "kind")
        target_value = string_field(entry, "target")
        if status != "installable" or runtime_name is None or kind is None or target_value is None:
            continue
        if not matches_runtime_filter(runtime_name, config.runtime):
            continue
        if not target_value.startswith("~/"):
            skipped.append(skip_entry(package_name, runtime_name, kind, target_value, "target-not-home-path"))
            continue
        if not runtime_available(config.home, runtime_name):
            skipped.append(skip_entry(package_name, runtime_name, kind, target_value, "runtime-not-installed"))
            continue
        source = resolve_runtime_source(package_root, manifest, entry, runtime_name, kind)
        if source is None:
            skipped.append(skip_entry(package_name, runtime_name, kind, target_value, "source-unresolved"))
            continue
        target = expand_home_target(config.home, target_value)
        source, target = normalize_target_pair(source, target, kind)
        if target.parent.is_symlink():
            skipped.append(skip_entry(package_name, runtime_name, kind, target_value, "target-parent-symlink"))
            continue
        actions.append(
            build_action(
                package=package_name,
                runtime=runtime_name,
                kind=kind,
                source=source,
                target=target,
                config=config,
            ),
        )
    return collapse_nested_actions(actions, skipped)


def resolve_runtime_source(
    package_root: Path,
    manifest: JsonObject,
    entry: JsonObject,
    runtime_name: str,
    kind: str,
) -> Path | None:
    source_value = string_field(entry, "source")
    if source_value is not None:
        return package_root / source_value
    match kind:
        case "skill":
            return resolve_skill_source(package_root, manifest, runtime_name)
        case "commands":
            return resolve_runtime_command_source(package_root, manifest, runtime_name)
        case _:
            return None


def resolve_skill_source(package_root: Path, manifest: JsonObject, runtime_name: str) -> Path | None:
    skill_values = manifest.get("skill_surfaces")
    if not isinstance(skill_values, list):
        return None
    for entry in skill_values:
        if not is_json_object(entry):
            continue
        if normalize_runtime(string_field(entry, "runtime")) != runtime_name:
            continue
        rel_path = string_field(entry, "path")
        if rel_path is not None:
            return package_root / rel_path
    return None


def resolve_runtime_command_source(
    package_root: Path,
    manifest: JsonObject,
    runtime_name: str,
) -> Path | None:
    command_values = manifest.get("commands")
    if not isinstance(command_values, list):
        return None
    for entry in command_values:
        if not is_json_object(entry):
            continue
        if normalize_runtime(string_field(entry, "runtime")) != runtime_name:
            continue
        rel_path = string_field(entry, "path")
        if rel_path is not None:
            return package_root / rel_path
    return None


def build_action(
    package: str,
    runtime: str,
    kind: str,
    source: Path,
    target: Path,
    config: SyncConfig,
) -> PlannedAction:
    if not source.exists():
        raise SyncError(f"source path not found: {source}")
    state = classify_target(target, source)
    backup_path = (
        build_backup_path(config, target)
        if (target.exists() or target.is_symlink()) and state != "up-to-date"
        else None
    )
    return PlannedAction(package, runtime, kind, source, target, state, backup_path)


def classify_target(target: Path, source: Path) -> str:
    if target.is_symlink():
        if target.resolve(strict=False) == source.resolve(strict=False):
            return "up-to-date"
        return "relink"
    if target.exists():
        return "replace-existing"
    return "install"


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


def apply_actions(actions: list[PlannedAction]) -> None:
    for action in actions:
        if not action.changed:
            continue
        if action.kind == "hook-config":
            apply_hook_config_action(action)
        else:
            apply_link_action(action)


def apply_link_action(action: PlannedAction) -> None:
    target = action.target
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink() or target.exists():
        if action.backup_path is None:
            raise SyncError(f"backup path missing for target: {target}")
        action.backup_path.parent.mkdir(parents=True, exist_ok=True)
        target.rename(action.backup_path)
    target.symlink_to(action.source)


def apply_hook_config_action(action: PlannedAction) -> None:
    if action.rendered_content is None:
        raise SyncError(f"rendered content missing for hook config: {action.target}")
    target = action.target
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if action.backup_path is None:
            raise SyncError(f"backup path missing for target: {target}")
        action.backup_path.parent.mkdir(parents=True, exist_ok=True)
        target.rename(action.backup_path)
    target.write_text(action.rendered_content, encoding="utf-8")


def action_to_json(action: PlannedAction, config: SyncConfig) -> JsonObject:
    return {
        "package": action.package,
        "runtime": action.runtime,
        "kind": action.kind,
        "source": compact_path(action.source, config.repo_root, config.home),
        "target": compact_path(action.target, config.repo_root, config.home),
        "state": action.state,
        "changed": action.changed,
        "backup_path": (
            compact_path(action.backup_path, config.repo_root, config.home)
            if action.backup_path is not None
            else None
        ),
        "notes": string_values(list(action.notes)),
    }


def rollback_command(action: PlannedAction, config: SyncConfig) -> str:
    target = compact_path(action.target, config.repo_root, config.home)
    if action.backup_path is None:
        return f"rm -rf {target}"
    backup = compact_path(action.backup_path, config.repo_root, config.home)
    return f"rm -rf {target} && mv {backup} {target}"


def skip_entry(package: str, runtime: str, kind: str, target: str, reason: str) -> JsonObject:
    return {
        "package": package,
        "runtime": runtime,
        "kind": kind,
        "target": target,
        "reason": reason,
    }


def normalize_target_pair(source: Path, target: Path, kind: str) -> tuple[Path, Path]:
    if kind == "skill" and target.name == "SKILL.md" and target.parent.is_symlink():
        return source.parent, target.parent
    return source, target


def collapse_nested_actions(
    actions: list[PlannedAction],
    skipped: list[JsonObject],
) -> tuple[list[PlannedAction], list[JsonObject]]:
    dropped: set[int] = set()
    for parent_index, parent in enumerate(actions):
        for child_index, child in enumerate(actions):
            if parent_index == child_index or child_index in dropped:
                continue
            if not is_nested_target(child.target, parent.target):
                continue
            if parent.kind in {"commands", "support-files"} and child.kind == "skill":
                dropped.add(child_index)
                skipped.append(
                    skip_entry(
                        child.package,
                        child.runtime,
                        child.kind,
                        str(child.target),
                        "covered-by-parent-target",
                    ),
                )
    filtered = [action for index, action in enumerate(actions) if index not in dropped]
    return filtered, skipped


def is_nested_target(child: Path, parent: Path) -> bool:
    try:
        _ = child.relative_to(parent)
    except ValueError:
        return False
    return child != parent


def runtime_available(home: Path, runtime_name: str) -> bool:
    match runtime_name:
        case "agents":
            return True
        case "claude-code":
            return (home / ".claude").is_dir()
        case "codex-cli":
            return (home / ".codex").is_dir()
        case "cairn-runtime":
            return (home / ".cairn" / "current").exists()
        case "hermes":
            return (home / ".hermes").is_dir()
        case _:
            return False


def matches_runtime_filter(runtime_name: str, runtime_filter: str) -> bool:
    return runtime_filter == "all" or runtime_name == runtime_filter


def normalize_runtime(value: str | None) -> str | None:
    if value is None:
        return None
    return RUNTIME_ALIASES.get(value, value)


def expand_home_target(home: Path, value: str) -> Path:
    return home / value.removeprefix("~/")


def string_field(payload: JsonObject, key: str) -> str | None:
    value = payload.get(key)
    if isinstance(value, str):
        return value
    return None


def compact_path(path: Path, repo_root: Path, home: Path) -> str:
    resolved = path.expanduser()
    try:
        return str(resolved.relative_to(repo_root))
    except ValueError:
        pass
    try:
        return "$HOME/" + str(resolved.relative_to(home))
    except ValueError:
        pass
    return str(resolved)
