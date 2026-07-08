from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path


def run_cli(repo_root: Path, home: Path, *args: str) -> subprocess.CompletedProcess[str]:
    package_root = Path(__file__).resolve().parents[1]
    return subprocess.run(
        [
            str(package_root / "core" / "bin" / "agent-surface-sync"),
            "--repo-root",
            str(repo_root),
            "--home",
            str(home),
            "--format",
            "json",
            *args,
        ],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )


def make_fixture(tmp_path: Path) -> tuple[Path, Path]:
    repo_root = tmp_path / "repo"
    home = tmp_path / "home"
    (repo_root / "feature-pack" / "sample" / "skill").mkdir(parents=True)
    (repo_root / "feature-pack" / "sample" / "core" / "bin").mkdir(parents=True)
    (repo_root / "hooks" / "manifests").mkdir(parents=True)
    (repo_root / "hooks" / "adapters").mkdir(parents=True)
    (home / ".claude" / "skills" / "sample").mkdir(parents=True)
    (home / ".codex").mkdir(parents=True)
    (repo_root / "feature-pack" / "sample" / "skill" / "SKILL.md").write_text(
        "# sample\n",
        encoding="utf-8",
    )
    (repo_root / "feature-pack" / "sample" / "core" / "bin" / "sample").write_text(
        "#!/usr/bin/env bash\n",
        encoding="utf-8",
    )
    (repo_root / "feature-pack" / "sample" / "manifest.json").write_text(
        json.dumps(
            {
                "name": "sample",
                "runtime_targets": [
                    {
                        "runtime": "claude-code",
                        "kind": "skill",
                        "target": "~/.claude/skills/sample/SKILL.md",
                        "status": "installable",
                    }
                ],
                "skill_surfaces": [
                    {
                        "runtime": "claude-code",
                        "kind": "skill",
                        "path": "skill/SKILL.md",
                    }
                ],
                "hook_adapters": [],
                "commands": [
                    {
                        "name": "sample",
                        "kind": "cli-binary",
                        "path": "core/bin/sample",
                    }
                ],
            },
        )
        + "\n",
        encoding="utf-8",
    )
    (repo_root / "hooks" / "adapters" / "claude-sample.sh").write_text(
        "#!/usr/bin/env bash\n",
        encoding="utf-8",
    )
    (repo_root / "hooks" / "adapters" / "codex-sample.sh").write_text(
        "#!/usr/bin/env bash\n",
        encoding="utf-8",
    )
    (repo_root / "hooks" / "manifests" / "sample.json").write_text(
        json.dumps(
            {
                "name": "sample",
                "runtime_hooks": [
                    {
                        "runtime": "claude-code",
                        "event": "UserPromptSubmit",
                        "adapter": "claude-sample.sh",
                        "level": "warning",
                    },
                    {
                        "runtime": "codex-cli",
                        "event": "UserPromptSubmit",
                        "adapter": "codex-sample.sh",
                        "level": "warning",
                        "status_message": "sample",
                    },
                ],
            },
        )
        + "\n",
        encoding="utf-8",
    )
    (home / ".claude" / "settings.json").write_text(
        json.dumps(
            {
                "hooks": {
                    "SessionStart": [
                        {
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": "echo existing-start",
                                    "timeout": 1,
                                },
                            ],
                        },
                    ],
                },
            },
        )
        + "\n",
        encoding="utf-8",
    )
    (home / ".codex" / "hooks.json").write_text(
        json.dumps(
            {
                "hooks": {
                    "SessionStart": [
                        {
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": "echo codex-start",
                                    "timeout": 1,
                                },
                            ],
                        },
                    ],
                },
            },
        )
        + "\n",
        encoding="utf-8",
    )
    (home / ".agents").mkdir(parents=True)
    return repo_root, home


def test_dry_run_reports_installable_actions(tmp_path: Path) -> None:
    repo_root, home = make_fixture(tmp_path)
    result = run_cli(repo_root, home, "--package", "sample")
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert len(payload["actions"]) == 5
    assert [entry["target"] for entry in payload["changed_actions"]] == [
        "$HOME/.agents/bin/sample",
        "$HOME/.claude/skills/sample/SKILL.md",
        "$HOME/.agents/hooks",
        "$HOME/.claude/settings.json",
        "$HOME/.codex/hooks.json",
    ]


def test_apply_relinks_existing_targets_and_creates_backups(tmp_path: Path) -> None:
    repo_root, home = make_fixture(tmp_path)
    stale_target = home / ".claude" / "skills" / "sample" / "SKILL.md"
    stale_target.write_text("stale\n", encoding="utf-8")
    hooks_target = home / ".agents" / "hooks"
    hooks_target.mkdir(parents=True)
    (hooks_target / "old.txt").write_text("old\n", encoding="utf-8")
    result = run_cli(repo_root, home, "--package", "sample", "--apply")
    assert result.returncode == 0, result.stderr
    assert stale_target.is_symlink()
    assert stale_target.resolve(strict=False) == (
        repo_root / "feature-pack" / "sample" / "skill" / "SKILL.md"
    ).resolve(strict=False)
    assert hooks_target.is_symlink()
    claude_settings = json.loads((home / ".claude" / "settings.json").read_text(encoding="utf-8"))
    codex_hooks = json.loads((home / ".codex" / "hooks.json").read_text(encoding="utf-8"))
    assert "SessionStart" in claude_settings["hooks"]
    assert "UserPromptSubmit" in claude_settings["hooks"]
    assert "UserPromptSubmit" in codex_hooks["hooks"]
    second_result = run_cli(repo_root, home, "--package", "sample", "--apply")
    assert second_result.returncode == 0, second_result.stderr
    second_payload = json.loads(second_result.stdout)
    assert second_payload["changed_actions"] == []
    backup_root = home / ".agents" / "state" / "agent-surface-sync" / "backups"
    assert backup_root.exists()


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as first_tmp:
        test_dry_run_reports_installable_actions(Path(first_tmp))
    with tempfile.TemporaryDirectory() as second_tmp:
        test_apply_relinks_existing_targets_and_creates_backups(Path(second_tmp))
    raise SystemExit(0)
