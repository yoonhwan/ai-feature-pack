from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path


def run_cli(package_root: Path, home: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            str(package_root / "core" / "bin" / "mcp-manager"),
            *args,
            "--home",
            str(home),
            "--format",
            "json",
        ],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )


def make_fixture(tmp_path: Path) -> Path:
    home = tmp_path / "home"
    (home / ".codex").mkdir(parents=True)
    (home / ".claude").mkdir(parents=True)
    (home / ".claude.json").write_text(
        json.dumps(
            {
                "mcpServers": {
                    "context": {"command": "npx", "args": ["-y", "@upstash/context7-mcp"]},
                    "filesystem": {
                        "command": "npx",
                        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                    },
                    "gemini": {"command": "npx", "args": ["-y", "gemini-mcp-tool"]},
                },
                "_disabled_mcpServers": {
                    "obsidian-mcp-server": {"command": "obsidian"},
                },
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (home / ".claude" / ".mcp.json").write_text(
        json.dumps(
            {
                "mcpServers": {
                    "notebooklm-mcp": {"command": "notebooklm-mcp"},
                    "obsidian-mcp-server": {"command": "obsidian"},
                }
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (home / ".codex" / "config.toml").write_text(
        """
approval_policy = "never"

[mcp_servers.filesystem]
command = "fs"

[mcp_servers.playwright]
command = "pw"

[mcp_servers.playwright.env]
FOO = "bar"

[mcp_servers.think]
command = "think"
""".strip()
        + "\n",
        encoding="utf-8",
    )
    (home / ".claude" / "settings.json").write_text("{}", encoding="utf-8")
    return home


def test_list_reports_active_servers_without_secret_dump(tmp_path: Path) -> None:
    package_root = Path(__file__).resolve().parents[1]
    home = make_fixture(tmp_path)
    result = run_cli(package_root, home, "list")
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    claude = next(item for item in payload["runtimes"] if item["runtime"] == "claude")
    codex = next(item for item in payload["runtimes"] if item["runtime"] == "codex")
    assert claude["active_servers"] == ["context", "filesystem", "gemini", "notebooklm-mcp"]
    assert claude["disabled_servers"] == ["obsidian-mcp-server"]
    assert codex["active_servers"] == ["filesystem", "playwright", "think"]


def test_disable_apply_removes_server_and_saves_fragment(tmp_path: Path) -> None:
    package_root = Path(__file__).resolve().parents[1]
    home = make_fixture(tmp_path)
    result = run_cli(package_root, home, "disable", "playwright", "--apply")
    assert result.returncode == 0, result.stderr
    config_text = (home / ".codex" / "config.toml").read_text(encoding="utf-8")
    assert "[mcp_servers.playwright]" not in config_text
    disabled_path = home / ".agents" / "state" / "mcp-manager" / "disabled" / "codex" / "playwright.toml"
    assert disabled_path.is_file()
    assert "[mcp_servers.playwright]" in disabled_path.read_text(encoding="utf-8")


def test_disable_apply_moves_claude_server_to_disabled_overlay(tmp_path: Path) -> None:
    package_root = Path(__file__).resolve().parents[1]
    home = make_fixture(tmp_path)
    result = run_cli(package_root, home, "disable", "gemini", "--runtime", "claude", "--apply")
    assert result.returncode == 0, result.stderr
    payload = json.loads((home / ".claude.json").read_text(encoding="utf-8"))
    assert "gemini" not in payload["mcpServers"]
    assert "gemini" in payload["_disabled_mcpServers"]
    disabled_path = home / ".agents" / "state" / "mcp-manager" / "disabled" / "claude" / "gemini.json"
    assert disabled_path.is_file()


def test_enable_apply_restores_disabled_fragment(tmp_path: Path) -> None:
    package_root = Path(__file__).resolve().parents[1]
    home = make_fixture(tmp_path)
    disable_result = run_cli(package_root, home, "disable", "playwright", "--apply")
    assert disable_result.returncode == 0, disable_result.stderr
    enable_result = run_cli(package_root, home, "enable", "playwright", "--apply")
    assert enable_result.returncode == 0, enable_result.stderr
    config_text = (home / ".codex" / "config.toml").read_text(encoding="utf-8")
    assert "[mcp_servers.playwright]" in config_text
    disabled_path = home / ".agents" / "state" / "mcp-manager" / "disabled" / "codex" / "playwright.toml"
    assert not disabled_path.exists()


def test_enable_apply_restores_claude_server_to_active_map(tmp_path: Path) -> None:
    package_root = Path(__file__).resolve().parents[1]
    home = make_fixture(tmp_path)
    disable_result = run_cli(package_root, home, "disable", "gemini", "--runtime", "claude", "--apply")
    assert disable_result.returncode == 0, disable_result.stderr
    enable_result = run_cli(package_root, home, "enable", "gemini", "--runtime", "claude", "--apply")
    assert enable_result.returncode == 0, enable_result.stderr
    payload = json.loads((home / ".claude.json").read_text(encoding="utf-8"))
    assert "gemini" in payload["mcpServers"]
    assert "gemini" not in payload["_disabled_mcpServers"]
    disabled_path = home / ".agents" / "state" / "mcp-manager" / "disabled" / "claude" / "gemini.json"
    assert not disabled_path.exists()


def test_prune_dry_run_keeps_requested_servers_only_in_plan(tmp_path: Path) -> None:
    package_root = Path(__file__).resolve().parents[1]
    home = make_fixture(tmp_path)
    result = run_cli(package_root, home, "prune", "--keep", "filesystem")
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert [item["server"] for item in payload["disable"]] == ["playwright", "think"]
    config_text = (home / ".codex" / "config.toml").read_text(encoding="utf-8")
    assert "[mcp_servers.playwright]" in config_text


def test_prune_apply_disables_non_kept_claude_servers(tmp_path: Path) -> None:
    package_root = Path(__file__).resolve().parents[1]
    home = make_fixture(tmp_path)
    result = run_cli(
        package_root,
        home,
        "prune",
        "--runtime",
        "claude",
        "--keep",
        "context,filesystem",
        "--apply",
    )
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert [item["server"] for item in payload["disable"]] == ["gemini", "notebooklm-mcp"]
    claude_payload = json.loads((home / ".claude.json").read_text(encoding="utf-8"))
    assert sorted(claude_payload["mcpServers"]) == ["context", "filesystem"]
    assert sorted(claude_payload["_disabled_mcpServers"]) == [
        "gemini",
        "notebooklm-mcp",
        "obsidian-mcp-server",
    ]


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as first_tmp:
        test_list_reports_active_servers_without_secret_dump(Path(first_tmp))
    with tempfile.TemporaryDirectory() as second_tmp:
        test_disable_apply_removes_server_and_saves_fragment(Path(second_tmp))
    with tempfile.TemporaryDirectory() as third_tmp:
        test_disable_apply_moves_claude_server_to_disabled_overlay(Path(third_tmp))
    with tempfile.TemporaryDirectory() as fourth_tmp:
        test_enable_apply_restores_disabled_fragment(Path(fourth_tmp))
    with tempfile.TemporaryDirectory() as fifth_tmp:
        test_enable_apply_restores_claude_server_to_active_map(Path(fifth_tmp))
    with tempfile.TemporaryDirectory() as sixth_tmp:
        test_prune_dry_run_keeps_requested_servers_only_in_plan(Path(sixth_tmp))
    with tempfile.TemporaryDirectory() as seventh_tmp:
        test_prune_apply_disables_non_kept_claude_servers(Path(seventh_tmp))
    raise SystemExit(0)
