from __future__ import annotations

from .models import JsonObject, JsonValue


def render_human(report: JsonObject) -> str:
    lines = [
        "agent-surface-audit dry-run report",
        f"Repo root: {report['repo_root']}",
        "",
        "Codex/OMO skill exposure remains ~/.codex/skills until active load behavior proves otherwise.",
        "~/.agents/skills is compatibility/overlay only.",
        "",
        count_line("Source packages", report["sources"]),
        count_line("Runtime surfaces", report["runtime_surfaces"]),
        count_line("Project surfaces", report["project_surfaces"]),
        count_line("Hooks", report["hooks"]),
        count_line("Duplicate exposure risks", report["duplicates"]),
        count_line("Broken links", report["broken_links"]),
        count_line("Skipped private paths", report["skipped_private"]),
        "",
        "Proposed future actions:",
        *bullet_items(report["proposed_actions"], "action", "path"),
        "",
        "Rollback commands:",
        *plain_items(report["rollback"]),
        "",
        "No live migration, symlink, hook, settings, session, or auth changes were applied.",
    ]
    return "\n".join(lines)


def render_public_safety_human(report: JsonObject) -> str:
    ps = report.get("public_safety", {})
    if not isinstance(ps, dict):
        ps = {}
    lines = [
        "agent-surface-audit public-safety report",
        f"Repo root: {report['repo_root']}",
        "",
        count_line("Tracked safe paths", ps.get("tracked_safe")),
        count_line("Ignored runtime state paths", ps.get("ignored_runtime_state")),
        count_line("Must-not-commit paths", ps.get("must_not_commit")),
        "",
        "Manual review:",
        *plain_items(ps.get("manual_review")),
    ]
    return "\n".join(lines)


def count_line(label: str, value: JsonValue) -> str:
    if isinstance(value, list):
        return f"{label}: {len(value)}"
    return f"{label}: unavailable"


def bullet_items(value: JsonValue, first_key: str, second_key: str) -> list[str]:
    if not isinstance(value, list):
        return ["- none"]
    items: list[str] = []
    for item in value:
        if isinstance(item, dict):
            first = item.get(first_key)
            second = item.get(second_key)
            items.append(f"- {first}: {second}")
    return items or ["- none"]


def plain_items(value: JsonValue) -> list[str]:
    if not isinstance(value, list):
        return ["- none"]
    items = [f"- {item}" for item in value if isinstance(item, str)]
    return items or ["- none"]
