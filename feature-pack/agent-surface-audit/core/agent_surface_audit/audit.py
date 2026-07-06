from __future__ import annotations

from pathlib import Path

from .findings import (
    find_duplicates,
    json_objects,
    propose_actions,
    rollback_commands,
    string_values,
)
from .models import AuditConfig, JsonObject, SurfaceRoot
from .paths import compact_path, is_private_path, skipped_private_entry


def build_report(config: AuditConfig) -> JsonObject:
    source_names, sources, skipped = scan_sources(config)
    runtime_surfaces = scan_surfaces(runtime_roots(config), source_names, config)
    project_surfaces = scan_surfaces(project_roots(config), source_names, config)
    hooks = scan_hooks(config, skipped)
    broken_links = [
        entry
        for entry in [*runtime_surfaces, *project_surfaces]
        if entry["classification"] == "broken-link"
    ]
    duplicates = find_duplicates(source_names, runtime_surfaces, project_surfaces)
    proposed_actions = propose_actions(duplicates, broken_links)
    public_safety: JsonObject = {
        "tracked_safe": string_values([entry["path"] for entry in sources]),
        "ignored_runtime_state": string_values(
            [
                entry["path"]
                for entry in skipped
                if entry["path_class"] != "settings/hook config"
            ],
        ),
        "must_not_commit": string_values(
            [
                entry["path"]
                for entry in skipped
                if entry["path_class"] == "settings/hook config"
            ],
        ),
        "manual_review": [
            "Review duplicate exposure risks before generating live links.",
            "Review hook config paths by metadata only before any installer writes.",
        ],
    }
    return {
        "repo_root": compact_path(config.repo_root, config.repo_root, config.home),
        "public_safety": public_safety,
        "sources": json_objects(sources),
        "runtime_surfaces": json_objects(runtime_surfaces),
        "project_surfaces": json_objects(project_surfaces),
        "hooks": json_objects(hooks),
        "duplicates": json_objects(duplicates),
        "broken_links": json_objects(broken_links),
        "proposed_actions": json_objects(proposed_actions),
        "rollback": string_values(rollback_commands(proposed_actions)),
        "skipped_private": json_objects(skipped),
    }


def scan_sources(config: AuditConfig) -> tuple[set[str], list[JsonObject], list[JsonObject]]:
    feature_pack = config.repo_root / "feature-pack"
    source_names: set[str] = set()
    sources: list[JsonObject] = []
    skipped: list[JsonObject] = []
    if not feature_pack.is_dir():
        return source_names, sources, skipped
    for package in sorted(feature_pack.iterdir()):
        if not package.is_dir() or is_private_path(package):
            continue
        source_names.add(package.name)
        sources.append(
            {
                "name": package.name,
                "path": compact_path(package, config.repo_root, config.home),
                "classification": "source-owned",
                "has_manifest": (package / "manifest.json").is_file(),
                "has_readme": (package / "README.md").is_file(),
            },
        )
        for child in sorted(package.rglob("*")):
            if is_private_path(child):
                skipped.append(skipped_private_entry(child, config.repo_root, config.home))
    return source_names, sources, dedupe_by_path(skipped)


def runtime_roots(config: AuditConfig) -> list[SurfaceRoot]:
    return [
        SurfaceRoot("claude", config.home / ".claude" / "skills", "user-runtime"),
        SurfaceRoot("codex", config.home / ".codex" / "skills", "user-runtime"),
        SurfaceRoot("agents", config.home / ".agents" / "skills", "compatibility"),
    ]


def project_roots(config: AuditConfig) -> list[SurfaceRoot]:
    return [
        SurfaceRoot("claude", config.repo_root / ".claude" / "skills", "project-overlay"),
        SurfaceRoot("codex", config.repo_root / ".codex" / "skills", "project-overlay"),
        SurfaceRoot("agents", config.repo_root / ".agents" / "skills", "project-overlay"),
    ]


def scan_surfaces(
    roots: list[SurfaceRoot],
    source_names: set[str],
    config: AuditConfig,
) -> list[JsonObject]:
    entries: list[JsonObject] = []
    for root in roots:
        if not root.path.exists():
            continue
        for entry_path in sorted(root.path.iterdir()):
            classification = classify_surface(entry_path, root, source_names, config)
            entries.append(
                {
                    "name": entry_path.name,
                    "path": compact_path(entry_path, config.repo_root, config.home),
                    "runtime": root.runtime,
                    "surface_type": root.surface_type,
                    "classification": classification,
                    "load_behavior": "present, load behavior unverified",
                    "target": link_target(entry_path, config),
                },
            )
    return entries


def classify_surface(
    path: Path,
    root: SurfaceRoot,
    source_names: set[str],
    config: AuditConfig,
) -> str:
    if path.is_symlink() and not path.exists():
        return "broken-link"
    target = symlink_target(path)
    if target is not None and is_under(target, config.repo_root / "feature-pack"):
        return "symlink-to-source"
    if path.name in source_names:
        return "generated-runtime-install-surface"
    if root.runtime == "codex" and root.surface_type == "user-runtime":
        return "native-runtime-skill"
    return "private-local-only"


def symlink_target(path: Path) -> Path | None:
    if not path.is_symlink():
        return None
    return path.resolve(strict=False)


def link_target(path: Path, config: AuditConfig) -> str | None:
    target = symlink_target(path)
    if target is None:
        return None
    return compact_path(target, config.repo_root, config.home)


def is_under(path: Path, root: Path) -> bool:
    try:
        _ = path.resolve(strict=False).relative_to(root.resolve(strict=False))
    except ValueError:
        return False
    return True


def scan_hooks(config: AuditConfig, skipped: list[JsonObject]) -> list[JsonObject]:
    hooks: list[JsonObject] = []
    for path in [
        config.home / ".claude" / "settings.json",
        config.home / ".codex" / "hooks.json",
    ]:
        if path.exists():
            skipped.append(skipped_private_entry(path, config.repo_root, config.home))
            hooks.append(
                {
                    "path": compact_path(path, config.repo_root, config.home),
                    "path_class": "settings/hook config",
                    "exists": True,
                    "content_read": False,
                },
            )
    repo_hooks = config.repo_root / "hooks"
    if repo_hooks.exists():
        hooks.append(
            {
                "path": compact_path(repo_hooks, config.repo_root, config.home),
                "path_class": "repo hook source",
                "exists": True,
                "content_read": False,
            },
        )
    return hooks


def dedupe_by_path(entries: list[JsonObject]) -> list[JsonObject]:
    seen: set[str] = set()
    deduped: list[JsonObject] = []
    for entry in entries:
        path = entry["path"]
        if isinstance(path, str) and path not in seen:
            deduped.append(entry)
            seen.add(path)
    return deduped
