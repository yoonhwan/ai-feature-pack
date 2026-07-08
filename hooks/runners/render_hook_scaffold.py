from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from hooks.runners.hook_scaffold_support import (
    HookScaffoldError,
    Report,
    build_report,
    render_human,
    write_json_report,
)


class OutputFormat(StrEnum):
    HUMAN = "human"
    JSON = "json"


@dataclass(frozen=True, slots=True)
class RenderConfig:
    repo_root: Path
    hooks_root: Path
    output_format: OutputFormat
    runtime_filter: str
    json_path: Path | None


def main() -> int:
    try:
        config = parse_args(sys.argv[1:])
        report = build_report(config.repo_root, config.hooks_root, config.runtime_filter)
        write_json_report(report, config.json_path)
        emit_report(report, config.output_format)
    except HookScaffoldError as error:
        print(f"render-hook-scaffold: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"render-hook-scaffold: runtime error: {error}", file=sys.stderr)
        return 1
    return 0


def parse_args(args: list[str]) -> RenderConfig:
    repo_root = Path(__file__).resolve().parents[2]
    hooks_root = repo_root / "hooks"
    output_format = OutputFormat.HUMAN
    runtime_filter = "all"
    json_path: Path | None = None
    dry_run = False
    index = 0
    while index < len(args):
        token = args[index]
        match token:
            case "--dry-run":
                dry_run = True
                index += 1
            case "--repo-root":
                repo_root, index = read_path_value(args, index, "--repo-root")
            case "--hooks-root":
                hooks_root, index = read_path_value(args, index, "--hooks-root")
            case "--format":
                output_format, index = read_format_value(args, index)
            case "--runtime":
                runtime_filter, index = read_runtime_value(args, index)
            case "--json":
                json_path, index = read_path_value(args, index, "--json")
            case "--help" | "-h":
                raise HookScaffoldError(usage())
            case _:
                raise HookScaffoldError(f"unknown argument: {token}\n{usage()}")
    if not dry_run:
        raise HookScaffoldError("--dry-run is required; this renderer is read-only by contract.")
    repo_root = repo_root.expanduser().resolve()
    hooks_root = hooks_root.expanduser().resolve()
    if not repo_root.is_dir():
        raise HookScaffoldError(f"--repo-root must be an existing directory: {repo_root}")
    if not hooks_root.is_dir():
        raise HookScaffoldError(f"--hooks-root must be an existing directory: {hooks_root}")
    return RenderConfig(repo_root, hooks_root, output_format, runtime_filter, json_path)


def read_path_value(args: list[str], index: int, flag: str) -> tuple[Path, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise HookScaffoldError(f"{flag} requires a path value")
    value = args[value_index]
    if value.startswith("--"):
        raise HookScaffoldError(f"{flag} requires a path value")
    return Path(value), index + 2


def read_format_value(args: list[str], index: int) -> tuple[OutputFormat, int]:
    value, next_index = read_string_value(args, index, "--format")
    try:
        return OutputFormat(value), next_index
    except ValueError as error:
        raise HookScaffoldError("--format must be human or json") from error


def read_runtime_value(args: list[str], index: int) -> tuple[str, int]:
    value, next_index = read_string_value(args, index, "--runtime")
    normalized = {"claude": "claude-code", "codex": "codex-cli"}.get(value, value)
    if normalized not in {"all", "claude-code", "codex-cli"}:
        raise HookScaffoldError("--runtime must be all, claude, claude-code, codex, or codex-cli")
    return normalized, next_index


def read_string_value(args: list[str], index: int, flag: str) -> tuple[str, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise HookScaffoldError(f"{flag} requires a value")
    value = args[value_index]
    if value.startswith("--"):
        raise HookScaffoldError(f"{flag} requires a value")
    return value, index + 2


def emit_report(report: Report, output_format: OutputFormat) -> None:
    match output_format:
        case OutputFormat.HUMAN:
            print(render_human(report))
        case OutputFormat.JSON:
            print(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False))


def usage() -> str:
    return (
        "Usage: render-hook-scaffold --dry-run [--runtime all|claude|claude-code|codex|codex-cli] "
        "[--format human|json] [--json PATH] [--repo-root PATH] [--hooks-root PATH]"
    )


if __name__ == "__main__":
    raise SystemExit(main())
