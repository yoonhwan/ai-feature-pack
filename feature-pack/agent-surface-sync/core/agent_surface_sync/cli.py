from __future__ import annotations

import json
import sys
from datetime import UTC, datetime
from pathlib import Path

from .models import JsonObject, JsonValue, OutputFormat, SyncConfig, SyncError, is_json_object
from .sync import run_sync


def main() -> int:
    try:
        config = parse_args(sys.argv[1:])
        report = run_sync(config)
        write_json_report(report, config.json_path)
        emit(report, config.output_format)
    except SyncError as error:
        print(f"agent-surface-sync: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"agent-surface-sync: runtime error: {error}", file=sys.stderr)
        return 1
    return 0


def parse_args(args: list[str]) -> SyncConfig:
    repo_root = Path.cwd()
    home = Path.home()
    apply = False
    json_path: Path | None = None
    output_format = OutputFormat.HUMAN
    packages: tuple[str, ...] | None = None
    runtime = "all"
    index = 0
    while index < len(args):
        token = args[index]
        match token:
            case "--apply":
                apply = True
                index += 1
            case "--dry-run":
                apply = False
                index += 1
            case "--repo-root":
                repo_root, index = read_path_value(args, index, "--repo-root")
            case "--home":
                home, index = read_path_value(args, index, "--home")
            case "--json":
                json_path, index = read_path_value(args, index, "--json")
            case "--format":
                output_format, index = read_format_value(args, index)
            case "--package":
                packages, index = read_packages_value(args, index)
            case "--runtime":
                runtime, index = read_runtime_value(args, index)
            case "--help" | "-h":
                raise SyncError(usage())
            case _:
                raise SyncError(f"unknown argument: {token}\n{usage()}")
    repo_root = repo_root.expanduser().resolve()
    home = home.expanduser().resolve()
    if not repo_root.is_dir():
        raise SyncError(f"--repo-root must be an existing directory: {repo_root}")
    if not home.is_dir():
        raise SyncError(f"--home must be an existing directory: {home}")
    operation_id = datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")
    return SyncConfig(
        repo_root=repo_root,
        home=home,
        apply=apply,
        output_format=output_format,
        json_path=json_path,
        packages=packages,
        runtime=runtime,
        operation_id=operation_id,
    )


def read_path_value(args: list[str], index: int, flag: str) -> tuple[Path, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise SyncError(f"{flag} requires a path value")
    value = args[value_index]
    if value.startswith("--"):
        raise SyncError(f"{flag} requires a path value")
    return Path(value), index + 2


def read_packages_value(args: list[str], index: int) -> tuple[tuple[str, ...], int]:
    value_index = index + 1
    if value_index >= len(args):
        raise SyncError("--package requires a comma-separated value")
    value = args[value_index]
    if value.startswith("--"):
        raise SyncError("--package requires a comma-separated value")
    packages = tuple(item for item in value.split(",") if item)
    if not packages:
        raise SyncError("--package requires at least one package name")
    return packages, index + 2


def read_format_value(args: list[str], index: int) -> tuple[OutputFormat, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise SyncError("--format requires human or json")
    value = args[value_index]
    try:
        return OutputFormat(value), index + 2
    except ValueError as error:
        raise SyncError("--format must be human or json") from error


def read_runtime_value(args: list[str], index: int) -> tuple[str, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise SyncError("--runtime requires a value")
    value = args[value_index]
    normalized = {
        "agents": "agents",
        "all": "all",
        "claude": "claude-code",
        "claude-code": "claude-code",
        "codex": "codex-cli",
        "codex-cli": "codex-cli",
    }.get(value)
    if normalized is None:
        raise SyncError("--runtime must be all, agents, claude-code, or codex-cli")
    return normalized, index + 2


def write_json_report(report: JsonObject, json_path: Path | None) -> None:
    if json_path is None:
        return
    json_path.parent.mkdir(parents=True, exist_ok=True)
    _ = json_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def emit(report: JsonObject, output_format: OutputFormat) -> None:
    if output_format == OutputFormat.JSON:
        print(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False))
        return
    print(render_human(report))


def render_human(report: JsonObject) -> str:
    actions = get_json_list(report.get("actions"))
    changed_actions = get_json_list(report.get("changed_actions"))
    skipped = get_json_list(report.get("skipped"))
    lines = [
        f"agent-surface-sync {'apply' if report.get('apply') else 'dry-run'}",
        f"repo_root: {report.get('repo_root')}",
        f"operation_id: {report.get('operation_id')}",
        f"actions: {len(actions)}",
        f"changed_actions: {len(changed_actions)}",
        f"skipped: {len(skipped)}",
        "",
        "planned changes:",
    ]
    for action in changed_actions:
        lines.append(
            "- "
            + " ".join(
                [
                    get_string(action.get("package")) or "unknown",
                    get_string(action.get("runtime")) or "unknown",
                    get_string(action.get("kind")) or "unknown",
                    get_string(action.get("state")) or "unknown",
                    get_string(action.get("target")) or "unknown",
                ],
            ),
        )
    if not changed_actions:
        lines.append("- none")
    lines.append("")
    lines.append("skipped:")
    for entry in skipped:
        lines.append(
            "- "
            + " ".join(
                [
                    get_string(entry.get("package")) or "unknown",
                    get_string(entry.get("runtime")) or "unknown",
                    get_string(entry.get("kind")) or "unknown",
                    get_string(entry.get("reason")) or "unknown",
                    get_string(entry.get("target")) or "unknown",
                ],
            ),
        )
    if not skipped:
        lines.append("- none")
    return "\n".join(lines)


def get_json_list(value: JsonValue | None) -> list[JsonObject]:
    if not isinstance(value, list):
        return []
    return [item for item in value if is_json_object(item)]


def get_string(value: JsonValue | None) -> str | None:
    if isinstance(value, str):
        return value
    return None


def usage() -> str:
    return (
        "Usage: agent-surface-sync [--dry-run|--apply] [--repo-root PATH] [--home PATH] "
        "[--json PATH] [--format human|json] [--package a,b] "
        "[--runtime all|agents|claude-code|codex-cli]"
    )


if __name__ == "__main__":
    raise SystemExit(main())
