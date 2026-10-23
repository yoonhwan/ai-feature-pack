"""r829 — claude-hr.sh 살아 있음 탐침의 7초 룰 계약.

탐침(_headroom_up · _cliproxy_up)은 시도당 7초 + 재시도 1(총 16초 안)이다.
부하로 프록시 응답이 2초를 넘어도 살아 있으면 claude 가 떠야 하고,
정말 죽었으면 지금처럼 직결 폴백을 거부해야 한다.

실 8317·8790 0 · 실 claude 0 — 가짜 HTTP 서버(임시 포트·지연 조절)와
URL 만 바꿔 진짜 curl 로 넘기는 shim 으로 curl -m 의미를 그대로 잰다.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[3]
WRAPPER = Path(
    os.environ.get("R829_WRAPPER")
    or PROJECT_ROOT / "feature-pack/headroom/templates/claude-hr.sh"
)

TOTAL_DEADLINE_S = 16.0
HANG_S = 9.0  # 시도당 상한(7초)보다 길게 무응답

# 래퍼의 고정 URL 을 가짜 서버 포트로 바꿔 진짜 curl 로 넘긴다(시도마다 한 줄 기록).
CURL_SHIM = """#!/bin/zsh
args=()
for a in "$@"; do
  case "$a" in
    http://localhost:8790*) a="http://127.0.0.1:${FAKE_HR_PORT}${a#http://localhost:8790}" ;;
    http://127.0.0.1:8317*) a="http://127.0.0.1:${FAKE_CP_PORT}${a#http://127.0.0.1:8317}" ;;
  esac
  args+=("$a")
done
print -r -- "$*" >> "$CURL_LOG"
exec /usr/bin/curl "${args[@]}"
"""

CLAUDE_STUB = """#!/bin/zsh
print -r -- "${ANTHROPIC_BASE_URL:-UNSET}" >> "$CLAUDE_CAPTURE"
"""

# 레이어별: (라우팅, 탐침 경로)
LAYERS = {
    "cliproxy": ({"headroom": False, "cliproxy": True}, "/v1/models"),
    "headroom": ({"headroom": True, "cliproxy": True}, "/health"),
}


class _FakeProxy:
    """요청 순번마다 지연(초)을 정하는 가짜 서버. 목록이 끝나면 마지막 값을 쓴다."""

    def __init__(self, delays: list[float]) -> None:
        self.delays = delays
        self.hits = 0
        lock = threading.Lock()
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802
                with lock:
                    idx = outer.hits
                    outer.hits += 1
                time.sleep(outer.delays[min(idx, len(outer.delays) - 1)])
                body = b'{"data":[]}'
                try:
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                except OSError:
                    pass  # curl 이 상한으로 먼저 끊은 연결

            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()


def _closed_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o700)


class ClaudeHrProbeSevenSecondRule(unittest.TestCase):
    def _run(self, layer: str, port: int) -> tuple[subprocess.CompletedProcess[str], list[str], int, float]:
        routing, _ = LAYERS[layer]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, bin_dir = root / "home", root / "bin"
            capture, curl_log = root / "claude.txt", root / "curl.log"
            (home / ".headroom").mkdir(parents=True)
            (home / ".local/bin").mkdir(parents=True)
            bin_dir.mkdir()
            (home / ".headroom/routing.json").write_text(
                json.dumps({"default": routing, "projects": {}}), encoding="utf-8"
            )
            _write_executable(bin_dir / "curl", CURL_SHIM)
            _write_executable(home / ".local/bin/claude", CLAUDE_STUB)

            env = os.environ.copy()
            for stale in ("HEADROOM_ROUTE", "CLIPROXY_ROUTE"):
                env.pop(stale, None)
            env.update(
                {
                    "HOME": str(home),
                    "PATH": f"{bin_dir}:{env['PATH']}",
                    "CLAUDE_CAPTURE": str(capture),
                    "CURL_LOG": str(curl_log),
                    "FAKE_HR_PORT": str(port),
                    "FAKE_CP_PORT": str(port),
                }
            )
            started = time.monotonic()
            result = subprocess.run(
                ["zsh", str(WRAPPER), "-p", "r829"],
                cwd=PROJECT_ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
                timeout=60,
            )
            elapsed = time.monotonic() - started
            claude_runs = capture.read_text(encoding="utf-8").splitlines() if capture.exists() else []
            attempts = len(curl_log.read_text(encoding="utf-8").splitlines()) if curl_log.exists() else 0
            return result, claude_runs, attempts, elapsed

    def _run_with_server(self, layer: str, delays: list[float]):
        proxy = _FakeProxy(delays)
        try:
            return self._run(layer, proxy.port)
        finally:
            proxy.close()

    def _report(self, label: str, layer: str, out: tuple[subprocess.CompletedProcess[str], list[str], int, float]) -> str:
        result, claude_runs, attempts, elapsed = out
        line = (f"R829 {label} layer={layer} rc={result.returncode} claude={len(claude_runs)} "
                f"attempts={attempts} elapsed={elapsed:.2f}s")
        print(line)
        return line + "\n" + result.stderr

    # ⓐ 응답 3초 지연 — 2초 탐침은 «죽었다» 로 오판, 7초 탐침은 통과
    def test_a_slow_but_alive_proxy_launches_claude(self) -> None:
        for layer in LAYERS:
            with self.subTest(layer=layer):
                out = self._run_with_server(layer, [3.0])
                msg = self._report("a", layer, out)
                result, claude_runs, _, _ = out
                self.assertEqual(result.returncode, 0, msg)
                self.assertEqual(len(claude_runs), 1, msg)
                self.assertNotIn("직결 폴백을 거부", result.stderr, msg)

    # ⓑ 첫 시도 7초 넘게 무응답 · 둘째 시도 1초 응답 → 재시도 1로 통과
    def test_b_first_attempt_hangs_retry_succeeds(self) -> None:
        for layer in LAYERS:
            with self.subTest(layer=layer):
                out = self._run_with_server(layer, [HANG_S, 1.0])
                msg = self._report("b", layer, out)
                result, claude_runs, attempts, elapsed = out
                self.assertEqual(result.returncode, 0, msg)
                self.assertEqual(len(claude_runs), 1, msg)
                self.assertEqual(attempts, 2, msg)
                self.assertLessEqual(elapsed, TOTAL_DEADLINE_S, msg)

    # ⓒ 두 시도 모두 무응답 → 폴백 거부(문구 그대로) · 총 16초 안
    def test_c_both_attempts_hang_refuses_within_deadline(self) -> None:
        for layer in LAYERS:
            with self.subTest(layer=layer):
                out = self._run_with_server(layer, [HANG_S])
                msg = self._report("c", layer, out)
                result, claude_runs, _, elapsed = out
                self.assertEqual(result.returncode, 69, msg)
                self.assertIn("직결 폴백을 거부한다", result.stderr, msg)
                self.assertEqual(claude_runs, [], msg)
                self.assertLessEqual(elapsed, TOTAL_DEADLINE_S, msg)

    # ⓓ 포트 닫힘(연결 거부) → 즉시 실패 2회 → 폴백 거부 · 7초를 기다리지 않는다
    def test_d_connection_refused_fails_fast_twice(self) -> None:
        for layer in LAYERS:
            with self.subTest(layer=layer):
                out = self._run(layer, _closed_port())
                msg = self._report("d", layer, out)
                result, claude_runs, attempts, elapsed = out
                self.assertEqual(result.returncode, 69, msg)
                self.assertIn("직결 폴백을 거부한다", result.stderr, msg)
                self.assertEqual(claude_runs, [], msg)
                self.assertEqual(attempts, 2, msg)
                self.assertLess(elapsed, 2.0, msg)


if __name__ == "__main__":
    unittest.main()
