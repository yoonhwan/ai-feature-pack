from __future__ import annotations

import tomllib
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from .claude_runtime import (
    disable_claude_server,
    enable_claude_server,
    load_claude_disabled_servers,
    load_claude_servers,
)
from .models import JsonObject, JsonValue, ManagerError, json_objects, string_values


@dataclass(frozen=True, slots=True)
class RuntimePaths:
    home: Path

    @property
    def claude_settings(self) -> Path:
        return self.home / ".claude" / "settings.json"

    @property
    def claude_config(self) -> Path:
        return self.home / ".claude.json"

    @property
    def claude_overlay_paths(self) -> tuple[Path, ...]:
        return (
            self.home / ".claude" / ".mcp.json",
            self.home / ".claude" / "mcp.json",
        )

    @property
    def codex_config(self) -> Path:
        return self.home / ".codex" / "config.toml"

    @property
    def state_root(self) -> Path:
        return self.home / ".agents" / "state" / "mcp-manager"

    def disabled_dir(self, runtime: str) -> Path:
        return self.state_root / "disabled" / runtime

    def backups_dir(self, runtime: str) -> Path:
        return self.state_root / "backups" / runtime


def list_status(home: Path, runtime: str) -> JsonObject:
    paths = RuntimePaths(home)
    runtimes = ["claude", "codex"] if runtime == "all" else [runtime]
    reports = json_objects([runtime_status(paths, item) for item in runtimes])
    return {"home": str(home), "runtimes": reports}


def runtime_status(paths: RuntimePaths, runtime: str) -> JsonObject:
    if runtime == "claude":
        active = load_claude_servers(paths.claude_config, paths.claude_overlay_paths)
        disabled = load_claude_disabled_servers(paths.claude_config)
        config_path = paths.claude_config
    elif runtime == "codex":
        active = load_codex_servers(paths.codex_config)
        disabled = sorted(
            path.stem
            for path in paths.disabled_dir(runtime).glob("*.toml")
            if path.is_file()
        )
        config_path = paths.codex_config
    else:
        raise ManagerError(f"unsupported runtime: {runtime}")
    return {
        "runtime": runtime,
        "config_path": str(config_path),
        "config_exists": config_path.exists(),
        "active_servers": string_values(active),
        "disabled_servers": string_values(disabled),
    }


def load_codex_servers(config_path: Path) -> list[str]:
    if not config_path.exists():
        return []
    payload = tomllib.loads(config_path.read_text(encoding="utf-8"))
    servers = payload.get("mcp_servers")
    if not isinstance(servers, dict):
        return []
    return sorted(name for name in servers if isinstance(name, str))


def disable_server(home: Path, runtime: str, server: str, apply: bool) -> JsonObject:
    paths = RuntimePaths(home)
    if runtime == "claude":
        return disable_claude_server(
            paths.claude_config,
            paths.claude_overlay_paths,
            paths.disabled_dir(runtime),
            paths.backups_dir(runtime),
            server,
            apply,
        )
    if runtime != "codex":
        raise ManagerError(f"unsupported runtime: {runtime}")
    current_text = read_required_file(paths.codex_config)
    updated_text, removed_block = remove_codex_server(current_text, server)
    disabled_path = paths.disabled_dir(runtime) / f"{server}.toml"
    backup_path = build_backup_path(paths.backups_dir(runtime), f"disable-{server}")
    result: JsonObject = {
        "runtime": runtime,
        "server": server,
        "config_path": str(paths.codex_config),
        "disabled_path": str(disabled_path),
        "backup_path": str(backup_path),
        "apply": apply,
        "changed": removed_block != "",
    }
    if not apply:
        return result
    paths.disabled_dir(runtime).mkdir(parents=True, exist_ok=True)
    write_backup(paths.codex_config, backup_path)
    disabled_path.write_text(removed_block, encoding="utf-8")
    paths.codex_config.write_text(updated_text, encoding="utf-8")
    return result


def enable_server(home: Path, runtime: str, server: str, apply: bool) -> JsonObject:
    paths = RuntimePaths(home)
    if runtime == "claude":
        return enable_claude_server(
            paths.claude_config,
            paths.claude_overlay_paths,
            paths.disabled_dir(runtime),
            paths.backups_dir(runtime),
            server,
            apply,
        )
    if runtime != "codex":
        raise ManagerError(f"unsupported runtime: {runtime}")
    current_text = read_required_file(paths.codex_config)
    disabled_path = paths.disabled_dir(runtime) / f"{server}.toml"
    if server in load_codex_servers(paths.codex_config):
        raise ManagerError(f"server already active in codex config: {server}")
    if not disabled_path.is_file():
        raise ManagerError(f"disabled fragment not found: {disabled_path}")
    fragment = disabled_path.read_text(encoding="utf-8").strip()
    backup_path = build_backup_path(paths.backups_dir(runtime), f"enable-{server}")
    updated_text = append_fragment(current_text, fragment)
    result: JsonObject = {
        "runtime": runtime,
        "server": server,
        "config_path": str(paths.codex_config),
        "disabled_path": str(disabled_path),
        "backup_path": str(backup_path),
        "apply": apply,
        "changed": True,
    }
    if not apply:
        return result
    write_backup(paths.codex_config, backup_path)
    paths.codex_config.write_text(updated_text, encoding="utf-8")
    disabled_path.unlink()
    return result


def prune_servers(home: Path, runtime: str, keep: tuple[str, ...], apply: bool) -> JsonObject:
    paths = RuntimePaths(home)
    if runtime == "claude":
        active_servers = load_claude_servers(paths.claude_config, paths.claude_overlay_paths)
    elif runtime == "codex":
        active_servers = load_codex_servers(paths.codex_config)
    else:
        raise ManagerError(f"unsupported runtime: {runtime}")
    targets = [server for server in active_servers if server not in keep]
    disable_results: list[JsonValue] = [
        disable_server(home, runtime, server, apply) for server in targets
    ]
    return {
        "runtime": runtime,
        "keep": string_values(list(keep)),
        "disable": disable_results,
        "changed": bool(targets),
        "apply": apply,
    }


def read_required_file(path: Path) -> str:
    if not path.is_file():
        raise ManagerError(f"config file not found: {path}")
    return path.read_text(encoding="utf-8")


def remove_codex_server(text: str, server: str) -> tuple[str, str]:
    kept: list[str] = []
    removed: list[str] = []
    removing = False
    found = False
    for line in text.splitlines(keepends=True):
        header = parse_section_header(line.strip())
        if header == "__other__":
            removing = False
        elif header is not None:
            removing = header == server
            found = found or removing
        if removing:
            removed.append(line)
        else:
            kept.append(line)
    if not found:
        raise ManagerError(f"server not found in codex config: {server}")
    return normalize_text("".join(kept)), normalize_text("".join(removed))


def parse_section_header(line: str) -> str | None:
    if not line.startswith("[") or not line.endswith("]"):
        return None
    if not line.startswith("[mcp_servers."):
        return "__other__"
    tail = line[len("[mcp_servers.") : -1]
    if tail.startswith('"'):
        end = tail.find('"', 1)
        if end == -1:
            return "__other__"
        return tail[1:end]
    return tail.split(".", 1)[0]


def normalize_text(text: str) -> str:
    return text.rstrip() + "\n"


def append_fragment(current_text: str, fragment: str) -> str:
    return current_text.rstrip() + "\n\n" + fragment.rstrip() + "\n"


def build_backup_path(root: Path, label: str) -> Path:
    stamp = datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")
    return root / f"{stamp}-{label}.bak"


def write_backup(source_path: Path, backup_path: Path) -> None:
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    backup_path.write_text(source_path.read_text(encoding="utf-8"), encoding="utf-8")
