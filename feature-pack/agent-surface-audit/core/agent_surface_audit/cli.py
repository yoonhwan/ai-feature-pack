from __future__ import annotations

import json
import sys
from pathlib import Path

from .audit import build_report
from .models import AuditConfig, AuditError, JsonObject, OutputFormat
from .render import render_human, render_public_safety_human


def main() -> int:
    try:
        config = parse_args(sys.argv[1:])
        report = build_report(config)
        if config.public_safety_only:
            report = {
                "repo_root": report["repo_root"],
                "public_safety": report["public_safety"],
            }
        write_json_report(report, config.json_path)
        emit_report(report, config.output_format, config.public_safety_only)
    except AuditError as error:
        print(f"agent-surface-audit: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"agent-surface-audit: runtime error: {error}", file=sys.stderr)
        return 1
    return 0


def parse_args(args: list[str]) -> AuditConfig:
    repo_root = Path.cwd()
    home = Path.home()
    dry_run = False
    json_path: Path | None = None
    output_format = OutputFormat.HUMAN
    public_safety_only = False
    index = 0
    while index < len(args):
        token = args[index]
        match token:
            case "--dry-run":
                dry_run = True
                index += 1
            case "--public-safety":
                public_safety_only = True
                index += 1
            case "--repo-root":
                repo_root, index = read_path_value(args, index, "--repo-root")
            case "--home":
                home, index = read_path_value(args, index, "--home")
            case "--json":
                json_path, index = read_path_value(args, index, "--json")
            case "--format":
                output_format, index = read_format_value(args, index)
            case "--help" | "-h":
                raise AuditError(usage())
            case _:
                raise AuditError(f"unknown argument: {token}\n{usage()}")
    if not dry_run:
        raise AuditError("--dry-run is required; this tool is read-only by contract.")
    repo_root = repo_root.expanduser().resolve()
    home = home.expanduser().resolve()
    if not repo_root.is_dir():
        raise AuditError(f"--repo-root must be an existing directory: {repo_root}")
    if not home.is_dir():
        raise AuditError(f"--home must be an existing directory: {home}")
    return AuditConfig(repo_root, home, dry_run, output_format, json_path, public_safety_only)


def read_path_value(args: list[str], index: int, flag: str) -> tuple[Path, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise AuditError(f"{flag} requires a path value")
    value = args[value_index]
    if value.startswith("--"):
        raise AuditError(f"{flag} requires a path value")
    return Path(value), index + 2


def read_format_value(args: list[str], index: int) -> tuple[OutputFormat, int]:
    value_index = index + 1
    if value_index >= len(args):
        raise AuditError("--format requires human or json")
    value = args[value_index]
    try:
        return OutputFormat(value), index + 2
    except ValueError as error:
        raise AuditError("--format must be human or json") from error


def write_json_report(report: JsonObject, json_path: Path | None) -> None:
    if json_path is None:
        return
    json_path.parent.mkdir(parents=True, exist_ok=True)
    _ = json_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def emit_report(
    report: JsonObject,
    output_format: OutputFormat,
    public_safety_only: bool = False,
) -> None:
    match output_format:
        case OutputFormat.HUMAN:
            if public_safety_only:
                _ = print(render_public_safety_human(report))
            else:
                _ = print(render_human(report))
        case OutputFormat.JSON:
            _ = print(json.dumps(report, indent=2, sort_keys=True))


def usage() -> str:
    return (
        "Usage: agent-surface-audit --dry-run [--public-safety] [--repo-root PATH] "
        "[--home PATH] [--json PATH] [--format human|json]"
    )


if __name__ == "__main__":
    raise SystemExit(main())
