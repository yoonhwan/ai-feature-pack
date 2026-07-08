from __future__ import annotations

import json
from pathlib import Path
from typing import Final, TypedDict

from hooks.runners.hook_manifest_support import (
    HookScaffoldError,
    JsonValue,
    ManifestPayload,
    load_manifests,
)

INSTALL_ROOT: Final[str] = "$HOME/.agents/hooks"
BACKUP_SUFFIX: Final[str] = "<timestamp>"

HookCommandEntry = TypedDict(
    "HookCommandEntry",
    {"type": str, "command": str, "timeout": int, "statusMessage": str},
    total=False,
)
HookEventGroup = TypedDict("HookEventGroup", {"hooks": list[HookCommandEntry]})
HookSnippet = TypedDict("HookSnippet", {"hooks": dict[str, list[HookEventGroup]]})
RuntimeOutput = TypedDict(
    "RuntimeOutput",
    {
        "runtime": str,
        "target": str,
        "backup_target": str,
        "merge_strategy": str,
        "snippet": HookSnippet,
    },
)
InstallFile = TypedDict("InstallFile", {"source": str, "target": str})
ManifestSummary = TypedDict(
    "ManifestSummary",
    {
        "name": str,
        "safety_class": str,
        "measurement": str,
        "thresholds": list[JsonValue],
        "runtime_hooks": list[JsonValue],
    },
)
Report = TypedDict(
    "Report",
    {
        "repo_root": str,
        "hooks_root": str,
        "install_root": str,
        "manifests": list[ManifestSummary],
        "proposed_install_files": list[InstallFile],
        "runtime_outputs": list[RuntimeOutput],
        "rollback": list[str],
        "notes": list[str],
    },
)

def build_report(repo_root: Path, hooks_root: Path, runtime_filter: str) -> Report:
    manifests = load_manifests(hooks_root)
    runtime_outputs = build_runtime_outputs(manifests, runtime_filter)
    if not runtime_outputs:
        raise HookScaffoldError(f"no runtime outputs matched filter: {runtime_filter}")
    install_files = collect_install_files(repo_root, manifests)
    return {
        "repo_root": str(repo_root),
        "hooks_root": str(hooks_root),
        "install_root": INSTALL_ROOT,
        "manifests": manifest_summaries(manifests),
        "proposed_install_files": install_files,
        "runtime_outputs": runtime_outputs,
        "rollback": build_rollback(install_files),
        "notes": [
            "Dry-run only: no edits are applied to ~/.claude/settings.json or ~/.codex/hooks.json.",
            "Commands point at the planned shared install root under $HOME/.agents/hooks/.",
            "Hooks only warn and prepare. Session rollover and fanout remain user-triggered follow-up commands.",
            "session-rollover and session-fanout are still pending implementation in this repository.",
        ],
    }


def manifest_summaries(manifests: list[ManifestPayload]) -> list[ManifestSummary]:
    summaries: list[ManifestSummary] = []
    for manifest in manifests:
        thresholds = manifest.get("thresholds")
        runtime_hooks = manifest.get("runtime_hooks")
        if not isinstance(thresholds, list) or not isinstance(runtime_hooks, list):
            continue
        name = manifest.get("name")
        safety_class = manifest.get("safety_class")
        measurement = manifest.get("measurement")
        if (
            not isinstance(name, str)
            or not isinstance(safety_class, str)
            or not isinstance(measurement, str)
        ):
            continue
        summaries.append(
            {
                "name": name,
                "safety_class": safety_class,
                "measurement": measurement,
                "thresholds": thresholds,
                "runtime_hooks": runtime_hooks,
            },
        )
    return summaries


def collect_install_files(repo_root: Path, manifests: list[ManifestPayload]) -> list[InstallFile]:
    seen: set[str] = set()
    outputs: list[InstallFile] = []
    for manifest in manifests:
        name = manifest.get("name")
        runner = manifest.get("runner")
        if not isinstance(name, str) or not isinstance(runner, str):
            continue
        paths = [str(Path("manifests") / f"{name}.json"), runner]
        support_files = manifest.get("support_files")
        if isinstance(support_files, list):
            paths.extend(item for item in support_files if isinstance(item, str))
        runtime_hooks = manifest.get("runtime_hooks")
        if isinstance(runtime_hooks, list):
            for item in runtime_hooks:
                if isinstance(item, dict):
                    adapter = item.get("adapter")
                    if isinstance(adapter, str):
                        paths.append(str(Path("adapters") / adapter))
        for relative in sorted({str(Path("hooks") / Path(path).as_posix()) for path in paths}):
            if relative in seen:
                continue
            seen.add(relative)
            outputs.append(
                {
                    "source": str(repo_root / relative),
                    "target": f"{INSTALL_ROOT}/{relative.removeprefix('hooks/')}",
                },
            )
    return outputs


def build_runtime_outputs(
    manifests: list[ManifestPayload],
    runtime_filter: str,
) -> list[RuntimeOutput]:
    outputs: list[RuntimeOutput] = []
    for runtime in ("claude-code", "codex-cli"):
        if runtime_filter not in {"all", runtime}:
            continue
        hooks_by_event: dict[str, list[HookCommandEntry]] = {}
        for manifest in manifests:
            runtime_hooks = manifest.get("runtime_hooks")
            if not isinstance(runtime_hooks, list):
                continue
            for hook in runtime_hooks:
                if not isinstance(hook, dict) or hook.get("runtime") != runtime:
                    continue
                event = hook.get("event")
                adapter = hook.get("adapter")
                level = hook.get("level")
                status_message = hook.get("status_message")
                if not isinstance(event, str) or not isinstance(adapter, str) or not isinstance(level, str):
                    continue
                entry: HookCommandEntry = {
                    "type": "command",
                    "command": f"{INSTALL_ROOT}/adapters/{adapter} {level}",
                    "timeout": 5,
                }
                if runtime == "codex-cli" and isinstance(status_message, str):
                    entry["statusMessage"] = status_message
                hooks_by_event.setdefault(event, []).append(entry)
        target = "~/.claude/settings.json" if runtime == "claude-code" else "~/.codex/hooks.json"
        outputs.append(
            {
                "runtime": runtime,
                "target": target,
                "backup_target": f"{target}.bak.{BACKUP_SUFFIX}",
                "merge_strategy": "append generated hook entries under hooks.<event> without deleting existing hooks",
                "snippet": build_hook_snippet(hooks_by_event),
            },
        )
    return outputs


def build_hook_snippet(hooks_by_event: dict[str, list[HookCommandEntry]]) -> HookSnippet:
    return {"hooks": {event: [{"hooks": entries}] for event, entries in sorted(hooks_by_event.items())}}


def build_rollback(install_files: list[InstallFile]) -> list[str]:
    rollback = [
        f'cp "$HOME/.claude/settings.json.bak.{BACKUP_SUFFIX}" "$HOME/.claude/settings.json"',
        f'cp "$HOME/.codex/hooks.json.bak.{BACKUP_SUFFIX}" "$HOME/.codex/hooks.json"',
    ]
    for file_entry in install_files:
        rollback.append(f'rm -f "{file_entry["target"]}"')
    return rollback


def write_json_report(report: Report, json_path: Path | None) -> None:
    if json_path is None:
        return
    json_path.parent.mkdir(parents=True, exist_ok=True)
    _ = json_path.write_text(
        json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def render_human(report: Report) -> str:
    lines = [
        "hook scaffold dry-run report",
        f"Repo root: {report['repo_root']}",
        f"Hooks root: {report['hooks_root']}",
        f"Install root: {report['install_root']}",
        "",
        f"Manifests: {len(report['manifests'])}",
        f"Install files: {len(report['proposed_install_files'])}",
        f"Runtime outputs: {len(report['runtime_outputs'])}",
        "",
        "Runtime targets:",
    ]
    for item in report["runtime_outputs"]:
        lines.append(f"- {item['runtime']}: {item['target']}")
    lines.extend(
        [
            "",
            "Notes:",
            *[f"- {note}" for note in report["notes"]],
            "",
            "No live hook install, settings merge, or session action was applied.",
        ],
    )
    return "\n".join(lines)
