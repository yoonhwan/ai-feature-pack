from __future__ import annotations

import os
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
WRAPPERS = (
    PROJECT_ROOT / "feature-pack/headroom/templates/claude-hr.sh",
    Path.home() / ".headroom/claude-hr.sh",
)


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o700)


class ClaudeHeadroomWrapperContract(unittest.TestCase):
    def _run(
        self, wrapper: Path, *, health_ok: bool, disabled: bool = False
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            bin_dir = root / "bin"
            capture = root / "claude-env.txt"
            (home / ".headroom").mkdir(parents=True)
            (home / ".local/bin").mkdir(parents=True)
            bin_dir.mkdir()

            (home / ".headroom/always-route").write_text("canonical\n", encoding="utf-8")
            if disabled:
                (home / ".headroom/disabled-projects.json").write_text(
                    json.dumps([str(PROJECT_ROOT)]),
                    encoding="utf-8",
                )

            _write_executable(
                bin_dir / "curl",
                "#!/bin/zsh\n" + ("exit 0\n" if health_ok else "exit 7\n"),
            )
            _write_executable(
                home / ".local/bin/claude",
                "#!/bin/zsh\n"
                "print -r -- \"${ANTHROPIC_BASE_URL:-UNSET}\" > \"$CLAUDE_CAPTURE\"\n"
                "print -r -- \"${ANTHROPIC_CUSTOM_HEADERS:-UNSET}\" >> \"$CLAUDE_CAPTURE\"\n",
            )

            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(home),
                    "PATH": f"{bin_dir}:{env['PATH']}",
                    "CLAUDE_CAPTURE": str(capture),
                    "HEADROOM_ALWAYS_ROUTE": "",
                    "ANTHROPIC_BASE_URL": "http://stale-direct-or-wrong:1",
                }
            )
            result = subprocess.run(
                ["zsh", str(wrapper), "-p", "wrapper-contract"],
                cwd=PROJECT_ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            captured = capture.read_text(encoding="utf-8") if capture.exists() else ""
            return result, captured

    def test_canonical_route_errors_instead_of_direct_fallback_when_headroom_down(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, health_ok=False)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("canonical route requested", result.stderr)
                self.assertEqual(captured, "")

    def test_canonical_route_uses_headroom_when_healthy(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, health_ok=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("http://localhost:8790", captured)

    def test_explicit_project_disable_is_not_a_health_fallback(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, health_ok=False, disabled=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(captured.splitlines()[0], "UNSET")


if __name__ == "__main__":
    unittest.main()
