from __future__ import annotations

import json
from pathlib import Path

from .models import JsonObject, ManagerError, is_json_object


def load_claude_servers(config_path: Path, overlay_paths: tuple[Path, ...]) -> list[str]:
    payload = read_json_object_file(config_path)
    active = dict(load_server_map(payload, "mcpServers"))
    for name, entry in load_overlay_servers(overlay_paths).items():
        active.setdefault(name, entry)
    for name in load_server_map(payload, "_disabled_mcpServers"):
        active.pop(name, None)
    return sorted(active)


def load_claude_disabled_servers(config_path: Path) -> list[str]:
    payload = read_json_object_file(config_path)
    return sorted(load_server_map(payload, "_disabled_mcpServers"))


def disable_claude_server(
    config_path: Path,
    overlay_paths: tuple[Path, ...],
    disabled_dir: Path,
    backups_dir: Path,
    server: str,
    apply: bool,
) -> JsonObject:
    payload = read_required_json_object(config_path)
    active_store = ensure_server_store(payload, "mcpServers")
    disabled_store = ensure_server_store(payload, "_disabled_mcpServers")
    active = server_entries(active_store)
    disabled = server_entries(disabled_store)
    if server in disabled:
        raise ManagerError(f"server already disabled in claude config: {server}")
    overlay = load_overlay_servers(overlay_paths)
    state = build_disable_state(server, active, overlay)
    backup_path = build_backup_path(backups_dir, f"disable-{server}")
    disabled_path = disabled_dir / f"{server}.json"
    result: JsonObject = {
        "runtime": "claude",
        "server": server,
        "config_path": str(config_path),
        "disabled_path": str(disabled_path),
        "backup_path": str(backup_path),
        "apply": apply,
        "changed": True,
    }
    if not apply:
        return result
    disabled_dir.mkdir(parents=True, exist_ok=True)
    write_backup(config_path, backup_path)
    disabled_store[server] = state_entry(state)
    if state["origin"] == "main":
        del active_store[server]
    disabled_path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_json_object_file(config_path, payload)
    return result


def enable_claude_server(
    config_path: Path,
    overlay_paths: tuple[Path, ...],
    disabled_dir: Path,
    backups_dir: Path,
    server: str,
    apply: bool,
) -> JsonObject:
    payload = read_required_json_object(config_path)
    active_store = ensure_server_store(payload, "mcpServers")
    disabled_store = ensure_server_store(payload, "_disabled_mcpServers")
    active = server_entries(active_store)
    disabled = server_entries(disabled_store)
    if server in active:
        raise ManagerError(f"server already active in claude config: {server}")
    if server not in disabled:
        raise ManagerError(f"server not disabled in claude config: {server}")
    disabled_path = disabled_dir / f"{server}.json"
    state = read_disabled_state(disabled_path)
    origin = infer_origin(state, server, overlay_paths)
    entry = disabled[server]
    backup_path = build_backup_path(backups_dir, f"enable-{server}")
    result: JsonObject = {
        "runtime": "claude",
        "server": server,
        "config_path": str(config_path),
        "disabled_path": str(disabled_path),
        "backup_path": str(backup_path),
        "apply": apply,
        "changed": True,
    }
    if not apply:
        return result
    write_backup(config_path, backup_path)
    if origin == "main":
        active_store[server] = entry
    del disabled_store[server]
    if disabled_path.exists():
        disabled_path.unlink()
    write_json_object_file(config_path, payload)
    return result


def read_json_object_file(path: Path) -> JsonObject:
    if not path.is_file():
        return {}
    return read_required_json_object(path)


def read_required_json_object(path: Path) -> JsonObject:
    if not path.is_file():
        raise ManagerError(f"config file not found: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not is_json_object(payload):
        raise ManagerError(f"config root must be an object: {path}")
    return payload


def write_json_object_file(path: Path, payload: JsonObject) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_server_map(payload: JsonObject, key: str) -> dict[str, JsonObject]:
    return server_entries(ensure_server_store(payload, key))


def ensure_server_store(payload: JsonObject, key: str) -> JsonObject:
    value = payload.get(key)
    if is_json_object(value):
        return value
    store: JsonObject = {}
    payload[key] = store
    return store


def server_entries(store: JsonObject) -> dict[str, JsonObject]:
    servers: dict[str, JsonObject] = {}
    for name, entry in store.items():
        if is_json_object(entry):
            servers[name] = entry
    return servers


def load_overlay_servers(paths: tuple[Path, ...]) -> dict[str, JsonObject]:
    merged: dict[str, JsonObject] = {}
    for path in paths:
        payload = read_json_object_file(path)
        for name, entry in load_server_map(payload, "mcpServers").items():
            merged.setdefault(name, entry)
    return merged


def build_disable_state(
    server: str,
    active: dict[str, JsonObject],
    overlay: dict[str, JsonObject],
) -> JsonObject:
    if server in active:
        return {"origin": "main", "entry": active[server]}
    if server in overlay:
        return {"origin": "overlay", "entry": overlay[server]}
    raise ManagerError(f"server not found in claude config: {server}")


def read_disabled_state(path: Path) -> JsonObject:
    if not path.is_file():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if is_json_object(payload):
        return payload
    raise ManagerError(f"disabled state must be an object: {path}")


def infer_origin(state: JsonObject, server: str, overlay_paths: tuple[Path, ...]) -> str:
    origin = state.get("origin")
    if origin == "main":
        return "main"
    if origin == "overlay":
        return "overlay"
    overlay = load_overlay_servers(overlay_paths)
    if server in overlay:
        return "overlay"
    return "main"


def state_entry(state: JsonObject) -> JsonObject:
    entry = state.get("entry")
    if is_json_object(entry):
        return entry
    raise ManagerError("disabled state entry must be an object")


def build_backup_path(root: Path, label: str) -> Path:
    from datetime import UTC, datetime

    stamp = datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")
    return root / f"{stamp}-{label}.bak"


def write_backup(source_path: Path, backup_path: Path) -> None:
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    backup_path.write_text(source_path.read_text(encoding="utf-8"), encoding="utf-8")
