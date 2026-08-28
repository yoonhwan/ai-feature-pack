from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
WRAPPERS = (
    PROJECT_ROOT / "feature-pack/headroom/templates/claude-hr.sh",
    Path.home() / ".headroom/claude-hr.sh",
)

HEADROOM_URL = "http://localhost:8790"
CLIPROXY_URL = "http://127.0.0.1:8317"

# curl 스텁: 어느 프록시가 살아있는지 URL 로 분기한다. 두 레이어를 독립으로
# 죽여봐야 fail-closed 가 레이어별로 도는지 확인할 수 있다.
CURL_STUB = """#!/bin/zsh
for arg in "$@"; do
  case "$arg" in
    *8790*) [ "$HEADROOM_UP" = "1" ] && exit 0 || exit 7 ;;
    *8317*) [ "$CLIPROXY_UP" = "1" ] && exit 0 || exit 7 ;;
  esac
done
exit 7
"""

# ANTHROPIC_BASE_URL / ANTHROPIC_CUSTOM_HEADERS 를 파일로 뱉는 가짜 claude.
CLAUDE_STUB = """#!/bin/zsh
print -r -- "${ANTHROPIC_BASE_URL:-UNSET}" > "$CLAUDE_CAPTURE"
print -r -- "${ANTHROPIC_CUSTOM_HEADERS:-UNSET}" >> "$CLAUDE_CAPTURE"
"""


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o700)


class ClaudeHeadroomWrapperContract(unittest.TestCase):
    """claude-hr.sh 라우팅 매트릭스 계약.

    headroom / cliproxy 두 레이어를 독립 토글하며, 경유가 요청된 레이어가
    죽어 있으면 직결로 몰래 새지 않고 중단한다(fail-closed).
    """

    def _run(
        self,
        wrapper: Path,
        *,
        routing: dict | None,
        headroom_up: bool = True,
        cliproxy_up: bool = True,
        env_extra: dict[str, str] | None = None,
        argv: tuple[str, ...] = ("-p", "wrapper-contract"),
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            bin_dir = root / "bin"
            capture = root / "claude-env.txt"
            (home / ".headroom").mkdir(parents=True)
            (home / ".local/bin").mkdir(parents=True)
            bin_dir.mkdir()

            if routing is not None:
                (home / ".headroom/routing.json").write_text(
                    json.dumps(routing), encoding="utf-8"
                )

            _write_executable(bin_dir / "curl", CURL_STUB)
            _write_executable(home / ".local/bin/claude", CLAUDE_STUB)

            env = os.environ.copy()
            for stale in ("HEADROOM_ROUTE", "CLIPROXY_ROUTE"):
                env.pop(stale, None)
            env.update(
                {
                    "HOME": str(home),
                    "PATH": f"{bin_dir}:{env['PATH']}",
                    "CLAUDE_CAPTURE": str(capture),
                    "HEADROOM_UP": "1" if headroom_up else "0",
                    "CLIPROXY_UP": "1" if cliproxy_up else "0",
                    # 래퍼가 껐어야 할 stale 값 — 직결 경로에서 반드시 지워져야 한다.
                    "ANTHROPIC_BASE_URL": "http://stale-direct-or-wrong:1",
                }
            )
            env.update(env_extra or {})

            result = subprocess.run(
                ["zsh", str(wrapper), *argv],
                cwd=PROJECT_ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            captured = capture.read_text(encoding="utf-8") if capture.exists() else ""
            return result, captured

    @staticmethod
    def _routing(headroom: bool, cliproxy: bool) -> dict:
        return {"default": {"headroom": headroom, "cliproxy": cliproxy}, "projects": {}}

    # ── 매트릭스 4칸 ────────────────────────────────────────────────

    def test_both_on_routes_through_headroom_with_workspace_header(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, routing=self._routing(True, True))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                lines = captured.splitlines()
                self.assertEqual(lines[0], HEADROOM_URL)
                # x-headroom-cwd 없으면 headroom 이 workspace 를 못 풀어
                # track_compression 을 건너뛴다(fail-closed) — 절약이 0으로 보인다.
                self.assertIn("x-headroom-cwd:", lines[1])

    def test_cliproxy_only_routes_direct_to_8317_without_headroom_header(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, routing=self._routing(False, True))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                lines = captured.splitlines()
                self.assertEqual(lines[0], CLIPROXY_URL)
                self.assertEqual(lines[1], "UNSET")

    def test_both_off_clears_stale_base_url(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, routing=self._routing(False, False))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(captured.splitlines(), ["UNSET", "UNSET"])

    def test_headroom_on_with_cliproxy_off_is_refused(self) -> None:
        """headroom 의 upstream 은 plist 로 cliproxy 에 고정 — 우회 불가능한 조합."""
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, routing=self._routing(True, False))
                self.assertEqual(result.returncode, 78, result.stdout + result.stderr)
                self.assertEqual(captured, "")

    # ── fail-closed (레이어별) ──────────────────────────────────────

    def test_headroom_route_errors_instead_of_direct_fallback_when_down(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(
                    wrapper, routing=self._routing(True, True), headroom_up=False
                )
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("직결", result.stderr)
                self.assertEqual(captured, "")

    def test_cliproxy_route_errors_instead_of_direct_fallback_when_down(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(
                    wrapper, routing=self._routing(False, True), cliproxy_up=False
                )
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(captured, "")

    def test_disabled_route_is_not_a_health_fallback(self) -> None:
        """둘 다 off 는 '프록시가 죽어서' 가 아니라 '끄기로 했으니' 직결이다."""
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(
                    wrapper,
                    routing=self._routing(False, False),
                    headroom_up=False,
                    cliproxy_up=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(captured.splitlines()[0], "UNSET")

    # ── 우선순위 ────────────────────────────────────────────────────

    def test_project_entry_overrides_default(self) -> None:
        routing = {
            "default": {"headroom": False, "cliproxy": False},
            "projects": {str(PROJECT_ROOT): {"headroom": False, "cliproxy": True}},
        }
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, routing=routing)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(captured.splitlines()[0], CLIPROXY_URL)

    def test_env_override_beats_config(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(
                    wrapper,
                    routing=self._routing(False, True),
                    env_extra={"HEADROOM_ROUTE": "1"},
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(captured.splitlines()[0], HEADROOM_URL)

    def test_missing_routing_file_defaults_to_direct(self) -> None:
        """설정이 없으면 프록시를 태우지 않는다 — opt-in 이 기본."""
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(wrapper, routing=None)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(captured.splitlines(), ["UNSET", "UNSET"])

    # ── 스위처 CLI ──────────────────────────────────────────────────

    def test_route_status_reports_effective_target(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                result, captured = self._run(
                    wrapper, routing=self._routing(False, True), argv=("route", "status")
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(CLIPROXY_URL, result.stdout)
                self.assertEqual(captured, "", "status 는 claude 를 띄우지 않는다")

    def test_route_toggle_persists_to_routing_json(self) -> None:
        for wrapper in WRAPPERS:
            with self.subTest(wrapper=wrapper):
                with tempfile.TemporaryDirectory() as directory:
                    home = Path(directory) / "home"
                    (home / ".headroom").mkdir(parents=True)
                    routing_file = home / ".headroom/routing.json"
                    routing_file.write_text(
                        json.dumps(self._routing(False, False)), encoding="utf-8"
                    )

                    env = os.environ.copy()
                    env.update({"HOME": str(home)})
                    result = subprocess.run(
                        ["zsh", str(wrapper), "route", "cliproxy", "on", "--global"],
                        cwd=PROJECT_ROOT,
                        env=env,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    written = json.loads(routing_file.read_text(encoding="utf-8"))
                    self.assertTrue(written["default"]["cliproxy"])
                    self.assertFalse(written["default"]["headroom"])


if __name__ == "__main__":
    unittest.main()
