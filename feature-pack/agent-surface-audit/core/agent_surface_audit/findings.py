from __future__ import annotations

from .models import JsonObject, JsonValue


def find_duplicates(
    source_names: set[str],
    runtime_surfaces: list[JsonObject],
    project_surfaces: list[JsonObject],
) -> list[JsonObject]:
    names = sorted(
        {
            entry["name"]
            for entry in [*runtime_surfaces, *project_surfaces]
            if isinstance(entry["name"], str) and entry["name"] in source_names
        },
    )
    duplicates: list[JsonObject] = []
    for name in names:
        exposures = [
            entry["path"]
            for entry in [*runtime_surfaces, *project_surfaces]
            if entry["name"] == name
        ]
        if exposures:
            duplicates.append(
                {
                    "name": name,
                    "classification": "duplicate-exposure-risk",
                    "source": f"feature-pack/{name}",
                    "exposures": string_values(exposures),
                },
            )
    return duplicates


def propose_actions(
    duplicates: list[JsonObject],
    broken_links: list[JsonObject],
) -> list[JsonObject]:
    actions: list[JsonObject] = []
    for duplicate in duplicates:
        actions.append(
            {
                "action": "review-duplicate-exposure",
                "path": duplicate["source"],
                "reason": "Multiple runtime or project skill surfaces expose this source name.",
            },
        )
    for broken in broken_links:
        actions.append(
            {
                "action": "remove-or-repoint-broken-link",
                "path": broken["path"],
                "reason": "Symlink target does not exist.",
            },
        )
    return actions


def rollback_commands(actions: list[JsonObject]) -> list[str]:
    commands: list[str] = []
    for action in actions:
        path = action["path"]
        if isinstance(path, str):
            commands.append(f"# rollback future action for {path}: restore previous link/file")
    return commands


def json_objects(entries: list[JsonObject]) -> list[JsonValue]:
    values: list[JsonValue] = []
    values.extend(entries)
    return values


def string_values(values: list[JsonValue] | list[str]) -> list[JsonValue]:
    strings: list[JsonValue] = []
    for value in values:
        if isinstance(value, str):
            strings.append(value)
    return strings
