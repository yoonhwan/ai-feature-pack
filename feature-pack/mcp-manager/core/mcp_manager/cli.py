from __future__ import annotations

import json
import sys
from pathlib import Path

from .models import (
    JsonObject,
    JsonValue,
    ListConfig,
    ManagerError,
    MutateConfig,
    OutputFormat,
    PruneConfig,
    is_json_object,
)
from .runtime import disable_server, enable_server, list_status, prune_servers


def main() -> int:
    try:
        action, config = parse_args(sys.argv[1:])
        result = run_action(action, config)
        emit(result, config.output_format)
    except ManagerError as error:
        print(f"mcp-manager: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"mcp-manager: runtime error: {error}", file=sys.stderr)
        return 1
    return 0


def parse_args(args: list[str]) -> tuple[str, ListConfig | MutateConfig | PruneConfig]:
    if not args:
        raise ManagerError(usage())
    action = args[0]
    if action == "list":
        return action, parse_list_config(args[1:])
    if action in {"disable", "enable"}:
        return action, parse_mutate_config(action, args[1:])
    if action == "prune":
        return action, parse_prune_config(args[1:])
    raise ManagerError(f"unknown action: {action}\n{usage()}")


def parse_list_config(args: list[str]) -> ListConfig:
    home = Path.home()
    output_format = OutputFormat.HUMAN
    runtime = "all"
    index = 0
    while index < len(args):
        token = args[index]
        match token:
            case "--home":
                home, index = read_path_value(args, index, "--home")
            case "--format":
                output_format, index = read_format_value(args, index)
            case "--runtime":
                runtime, index = read_runtime_value(args, index, allow_all=True)
            case "--help" | "-h":
                raise ManagerError(usage())
            case _:
                raise ManagerError(f"unknown argument: {token}\n{usage()}")
    return ListConfig(home.expanduser().resolve(), output_format, runtime)


def parse_mutate_config(action: str, args: list[str]) -> MutateConfig:
    if not args:
        raise ManagerError(f"{action} requires a server name")
    server = args[0]
    home = Path.home()
    output_format = OutputFormat.HUMAN
    runtime = "codex"
    apply = False
    index = 1
    while index < len(args):
        token = args[index]
        match token:
            case "--home":
                home, index = read_path_value(args, index, "--home")
            case "--format":
                output_format, index = read_format_value(args, index)
            case "--runtime":
                runtime, index = read_runtime_value(args, index, allow_all=False)
            case "--apply":
                apply = True
                index += 1
            case "--dry-run":
                apply = False
                index += 1
            case "--help" | "-h":
                raise ManagerError(usage())
            case _:
                raise ManagerError(f"unknown argument: {token}\n{usage()}")
    return MutateConfig(home.expanduser().resolve(), output_format, runtime, server, apply)


def parse_prune_config(args: list[str]) -> PruneConfig:
    home = Path.home()
    output_format = OutputFormat.HUMAN
    runtime = "codex"
    apply = False
    keep: tuple[str, ...] | None = None
    index = 0
    while index < len(args):
        token = args[index]
        match token:
            case "--home":
                home, index = read_path_value(args, index, "--home")
            case "--format":
                output_format, index = read_format_value(args, index)
            case "--runtime":
                runtime, index = read_runtime_value(args, index, allow_all=False)
            case "--keep":
                value, index = read_string_value(args, index, "--keep")
                keep = tuple(item for item in value.split(",") if item)
            case "--apply":
                apply = True
                index += 1
            case "--dry-run":
                apply = False
                index += 1
            case "--help" | "-h":
                raise ManagerError(usage())
            case _:
                raise ManagerError(f"unknown argument: {token}\n{usage()}")
    if not keep:
        raise ManagerError("prune requires --keep server1,server2")
    return PruneConfig(home.expanduser().resolve(), output_format, runtime, keep, apply)


def read_path_value(args: list[str], index: int, flag: str) -> tuple[Path, int]:
    value, next_index = read_string_value(args, index, flag)
    return Path(value), next_index


def read_string_value(args: list[str], index: int, flag: str) -> tuple[str, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise ManagerError(f"{flag} requires a value")
    value = args[value_index]
    if value.startswith("--"):
        raise ManagerError(f"{flag} requires a value")
    return value, index + 2


def read_format_value(args: list[str], index: int) -> tuple[OutputFormat, int]:
    value, next_index = read_string_value(args, index, "--format")
    try:
        return OutputFormat(value), next_index
    except ValueError as error:
        raise ManagerError("--format must be human or json") from error


def read_runtime_value(args: list[str], index: int, allow_all: bool) -> tuple[str, int]:
    value, next_index = read_string_value(args, index, "--runtime")
    normalized = {"claude-code": "claude", "codex-cli": "codex"}.get(value, value)
    allowed = {"claude", "codex"}
    if allow_all:
        allowed.add("all")
    if normalized not in allowed:
        raise ManagerError("--runtime must be claude, codex, or all")
    return normalized, next_index


def run_action(
    action: str,
    config: ListConfig | MutateConfig | PruneConfig,
) -> JsonObject:
    if action == "list" and isinstance(config, ListConfig):
        return list_status(config.home, config.runtime)
    if action == "disable" and isinstance(config, MutateConfig):
        return disable_server(config.home, config.runtime, config.server, config.apply)
    if action == "enable" and isinstance(config, MutateConfig):
        return enable_server(config.home, config.runtime, config.server, config.apply)
    if action == "prune" and isinstance(config, PruneConfig):
        return prune_servers(config.home, config.runtime, config.keep, config.apply)
    raise ManagerError(f"unsupported action/config combination: {action}")


def emit(result: JsonObject, output_format: OutputFormat) -> None:
    if output_format == OutputFormat.JSON:
        print(json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False))
        return
    print(render_human(result))


def render_human(result: JsonObject) -> str:
    runtimes = result.get("runtimes")
    if isinstance(runtimes, list):
        lines = ["mcp-manager status"]
        for runtime in runtimes:
            if is_json_object(runtime):
                active_servers = get_string_list(runtime.get("active_servers"))
                disabled_servers = get_string_list(runtime.get("disabled_servers"))
                runtime_name = get_string_value(runtime.get("runtime")) or "unknown"
                lines.append(
                    f"- {runtime_name}: active={len(active_servers)} "
                    f"disabled={len(disabled_servers)}",
                )
                lines.append(f"  active: {', '.join(active_servers) or '(none)'}")
                lines.append(f"  disabled: {', '.join(disabled_servers) or '(none)'}")
        return "\n".join(lines)
    lines = [f"action runtime={result.get('runtime')} changed={result.get('changed')}"]
    for key in ("server", "config_path", "disabled_path", "backup_path", "apply"):
        if key in result:
            lines.append(f"{key}: {result[key]}")
    disabled = result.get("disable")
    if isinstance(disabled, list):
        count = len(disabled)
        lines.append(f"disable_count: {count}")
    return "\n".join(lines)


def get_string_value(value: JsonValue | None) -> str | None:
    if isinstance(value, str):
        return value
    return None


def get_string_list(value: JsonValue | None) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def usage() -> str:
    return (
        "Usage: mcp-manager list [--runtime all|claude|codex] [--format human|json] [--home PATH]\n"
        "       mcp-manager disable <server> [--runtime claude|codex] [--dry-run|--apply] [--format human|json] [--home PATH]\n"
        "       mcp-manager enable <server> [--runtime claude|codex] [--dry-run|--apply] [--format human|json] [--home PATH]\n"
        "       mcp-manager prune --keep a,b,c [--runtime claude|codex] [--dry-run|--apply] [--format human|json] [--home PATH]"
    )


if __name__ == "__main__":
    raise SystemExit(main())
