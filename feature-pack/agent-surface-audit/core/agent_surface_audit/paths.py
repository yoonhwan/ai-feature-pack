from __future__ import annotations

from pathlib import Path

from .models import JsonObject

PRIVATE_NAMES = frozenset(
    {
        ".omc",
        ".omo",
        ".omx",
        ".baton",
        ".fable-team",
        ".pytest_cache",
        "__pycache__",
        ".cache",
        "cache",
        "caches",
        "log",
        "logs",
        "session",
        "sessions",
        "auth",
        "token",
        "tokens",
        "settings",
        "settings.json",
        "hooks.json",
    },
)


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


def is_private_path(path: Path) -> bool:
    names = {part.lower() for part in path.parts}
    if names & PRIVATE_NAMES:
        return True
    lowered = path.name.lower()
    return "token" in lowered or "auth" in lowered or lowered.endswith(".log")


def private_path_class(path: Path) -> str:
    lowered_parts = {part.lower() for part in path.parts}
    name = path.name.lower()
    if "settings.json" in lowered_parts or "hooks.json" in lowered_parts:
        return "settings/hook config"
    if ".omc" in lowered_parts or ".omo" in lowered_parts or ".omx" in lowered_parts:
        return "generated runtime state"
    if ".baton" in lowered_parts or ".fable-team" in lowered_parts:
        return "agent session state"
    if "log" in lowered_parts or "logs" in lowered_parts or name.endswith(".log"):
        return "logs"
    if "auth" in lowered_parts or "token" in lowered_parts:
        return "auth/token-like"
    if ".pytest_cache" in lowered_parts or "__pycache__" in lowered_parts:
        return "cache"
    return "private/local runtime"


def skipped_private_entry(path: Path, repo_root: Path, home: Path) -> JsonObject:
    return {
        "path": compact_path(path, repo_root, home),
        "path_class": private_path_class(path),
        "content_read": False,
    }
