from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PATCH_DIR = Path(__file__).parent
HEADROOM_SOURCE = Path.home() / ".headroom-venv/lib/python3.12/site-packages/headroom"
HEADROOM_VERSION = next(
    (
        metadata.name.split("-", 1)[1].removesuffix(".dist-info")
        for metadata in HEADROOM_SOURCE.parent.glob("headroom_ai-*.dist-info")
    ),
    "",
)
RETRY_PATCH = (
    PATCH_DIR / "0009-buffered-timeout-retry-contract-033.patch"
    if HEADROOM_VERSION.startswith("0.33.")
    else PATCH_DIR / "0006-buffered-timeout-retry-contract.patch"
)


PATCH_SPECS = (
    (
        RETRY_PATCH,
        Path("headroom/proxy/server.py"),
        "attempt_limit",
    ),
    (
        PATCH_DIR / "0007-compression-cache-stats-key.patch",
        Path("headroom/proxy/server.py"),
        "_compression_cache_tokens_saved",
    ),
    (
        PATCH_DIR / "0008-prefix-tracker-sibling-lineage.patch",
        Path("headroom/cache/prefix_tracker.py"),
        "_lineage_checkpoints",
    ),
)


def _script(*lines: str) -> str:
    return "\n".join(lines) + "\n"


def _apply_patch(
    tmp_path: Path,
    target: Path,
    patch_path: Path,
    marker: str,
    *,
    reverse: bool = False,
) -> None:
    target_path = tmp_path / target
    has_marker = marker in target_path.read_text()
    if reverse:
        if not has_marker:
            return
        args = ["patch", "-R", "-p1", "-d", str(tmp_path)]
    else:
        if has_marker:
            return
        args = ["patch", "-p1", "-d", str(tmp_path)]
    result = subprocess.run(
        args,
        input=patch_path.read_text(),
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(result.stdout + result.stderr)


def _package_root(tmp_path: Path, apply_new_patches: bool) -> Path:
    package_root = tmp_path / "headroom"
    shutil.copytree(HEADROOM_SOURCE, package_root)
    for patch_path, target, marker in PATCH_SPECS:
        if patch_path.name.startswith("0008") and not apply_new_patches:
            _apply_patch(tmp_path, target, patch_path, marker, reverse=True)
        else:
            _apply_patch(tmp_path, target, patch_path, marker)
    return package_root


def _run(tmp_path: Path, code: str) -> subprocess.CompletedProcess[str]:
    apply_new_patches = os.environ.get("HEADROOM_CONTRACT_PREPATCH") != "1"
    package_root = _package_root(tmp_path, apply_new_patches)
    env = os.environ.copy()
    env["PYTHONPATH"] = str(package_root.parent)
    return subprocess.run(
        [sys.executable, "-c", code],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


class ProxyContracts(unittest.TestCase):
    def test_cache_stats_report_the_canonical_tokens_saved_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = _run(
                Path(directory),
                _script(
                    "from headroom.cache.compression_cache import CompressionCache",
                    "from headroom.proxy.server import _compression_cache_tokens_saved",
                    "cache = CompressionCache()",
                    "cache.store_compressed('hash', 'compressed', 7)",
                    "stats = cache.get_stats()",
                    "assert _compression_cache_tokens_saved(stats) == 7",
                ),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_buffered_timeout_is_one_attempt_and_typed_504(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = _run(
                Path(directory),
                _script(
                    "import anyio",
                    "import httpx",
                    "from headroom.proxy.server import HeadroomProxy",
                    "class Client:",
                    "    calls = 0",
                    "    async def post(self, url, **kwargs):",
                    "        self.calls += 1",
                    "        raise httpx.ReadTimeout('slow upstream', request=httpx.Request('POST', url))",
                    "client = Client()",
                    "proxy = HeadroomProxy.__new__(HeadroomProxy)",
                    "proxy.config = type('Config', (), {'retry_max_attempts': 3, 'retry_enabled': True, 'retry_base_delay_ms': 0, 'retry_max_delay_ms': 0})()",
                    "proxy.http_client = client",
                    "response = anyio.run(lambda: HeadroomProxy._retry_request(proxy, 'POST', 'http://127.0.0.1:8317/v1/messages', {}, {'model': 'test'}, max_attempts=1, retry_transport_errors=False, deadline=__import__('time').monotonic() + 1))",
                    "assert response.status_code == 504",
                    "assert response.json()['error']['type'] == 'timeout'",
                    "assert client.calls == 1",
                ),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_upstream_error_status_and_body_are_passthrough_without_fallback(self) -> None:
        for status, body in ((429, b"rate-limit-raw"), (500, b"server-error-raw")):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                result = _run(
                    Path(directory),
                    _script(
                        "import anyio",
                        "import httpx",
                        "from headroom.proxy.server import HeadroomProxy",
                        "class Client:",
                        "    calls = 0",
                        "    async def post(self, url, **kwargs):",
                        "        self.calls += 1",
                        f"        return httpx.Response({status}, content={body!r}, request=httpx.Request('POST', url))",
                        "client = Client()",
                        "proxy = HeadroomProxy.__new__(HeadroomProxy)",
                        "proxy.config = type('Config', (), {'retry_max_attempts': 3, 'retry_enabled': True, 'retry_base_delay_ms': 0, 'retry_max_delay_ms': 0})()",
                        "proxy.http_client = client",
                        "response = anyio.run(lambda: HeadroomProxy._retry_request(proxy, 'POST', 'http://127.0.0.1:8317/v1/messages', {}, {'model': 'test'}, max_attempts=1, retry_transport_errors=False))",
                        f"assert response.status_code == {status}",
                        f"assert response.content == {body!r}",
                        "assert client.calls == 1",
                    ),
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_server_side_tool_result_stays_in_sse_conversion(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = _run(
                Path(directory),
                _script(
                    "from headroom.proxy.handlers.streaming import StreamingMixin",
                    "events = StreamingMixin()._response_to_sse({'content': [{'type': 'tool_search_tool_result', 'tool_name': 'search', 'content': 'ok'}]}, 'anthropic')",
                    "assert b'tool_search_tool_result' in b''.join(events)",
                ),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_sibling_hidden_turn_does_not_cold_start_original_claude_session_lineage(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = _run(
                Path(directory),
                _script(
                    "import time",
                    "from headroom.cache.prefix_tracker import PrefixFreezeConfig, SessionTrackerStore",
                    "store = SessionTrackerStore(PrefixFreezeConfig(min_cached_tokens=1))",
                    "base = [{'role': 'system', 'content': 'system'}, {'role': 'user', 'content': 'ancestor'}]",
                    "hidden = base + [{'role': 'assistant', 'content': 'hidden'}]",
                    "real_user = base + [{'role': 'user', 'content': 'real'}]",
                    "maturation_manager = type('Manager', (), {'_matured': {}})()",
                    "ancestor_manager = maturation_manager",
                    "ancestor = store.resolve_tracker('session', 'anthropic', base)",
                    "ancestor.read_maturation_manager = ancestor_manager",
                    "ancestor.update_from_response(100, 0, base, message_token_counts=[10, 10])",
                    "hidden_tracker = store.resolve_tracker('session', 'anthropic', hidden)",
                    "hidden_tracker.update_from_response(100, 0, hidden, message_token_counts=[10, 10, 10])",
                    "checkpoints = getattr(store, '_lineage_checkpoints', {})",
                    "if checkpoints:",
                    "    checkpoint = next(iter(checkpoints['session'].values()))",
                    "    checkpoint.tracker._last_activity = time.time() - 12",
                    "    checkpoint.tracker._idle_seconds_at_fetch = 0",
                    "sibling_tracker = store.resolve_tracker('session', 'anthropic', real_user)",
                    "assert hidden_tracker.get_last_original_messages() == hidden",
                    "assert sibling_tracker is not hidden_tracker",
                    "assert sibling_tracker.get_last_original_messages() == base",
                    "assert sibling_tracker.get_frozen_message_count() == 2, 'sibling cold-started instead of inheriting ancestor cache checkpoint'",
                    "if checkpoints:",
                    "    assert sibling_tracker._idle_seconds_at_fetch >= 10, 'checkpoint branch did not refresh idle clock'",
                    "    assert time.time() - sibling_tracker._last_activity < 2, 'checkpoint branch did not refresh access clock'",
                    "    sibling_tracker.read_maturation_manager._matured['branch'] = True",
                    "    assert 'branch' not in ancestor_manager._matured, 'branch maturation state leaked into ancestor'",
                ),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_response_appended_sibling_keeps_ancestor_bytes_and_excludes_hidden_branch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = _run(
                Path(directory),
                _script(
                    "from headroom.cache.prefix_tracker import PrefixFreezeConfig, SessionTrackerStore, overlay_cached_prefix",
                    "store = SessionTrackerStore(PrefixFreezeConfig(min_cached_tokens=1))",
                    "base = [{'role': 'system', 'content': 'system'}, {'role': 'user', 'content': 'ancestor'}]",
                    "ancestor_assistant = {'role': 'assistant', 'content': 'ancestor-response'}",
                    "hidden_user = {'role': 'user', 'content': 'HIDDEN-BRANCH'}",
                    "hidden_assistant = {'role': 'assistant', 'content': 'hidden-response'}",
                    "real_user = {'role': 'user', 'content': 'REAL-BRANCH'}",
                    "ancestor = store.resolve_tracker('session', 'anthropic', base)",
                    "ancestor.update_from_response(100, 0, base + [ancestor_assistant], original_messages=base + [ancestor_assistant], message_token_counts=[10, 10, 10])",
                    "hidden_input = base + [ancestor_assistant, hidden_user]",
                    "hidden_tracker = store.resolve_tracker('session', 'anthropic', hidden_input)",
                    "hidden_tracker.update_from_response(100, 0, hidden_input + [hidden_assistant], original_messages=hidden_input + [hidden_assistant], message_token_counts=[10, 10, 10, 10, 10])",
                    "sibling_input = base + [ancestor_assistant, real_user]",
                    "sibling_tracker = store.resolve_tracker('session', 'anthropic', sibling_input)",
                    "forwarded = overlay_cached_prefix(sibling_input, sibling_input, sibling_tracker.get_last_original_messages(), sibling_tracker.get_last_forwarded_messages())",
                    "assert sibling_tracker is not hidden_tracker, 'real sibling reused hidden tracker'",
                    "assert sibling_tracker.get_frozen_message_count() == 3, 'response-appended sibling lost ancestor cache checkpoint'",
                    "assert {'role': 'assistant', 'content': 'ancestor-response'} in forwarded, 'ancestor forwarded bytes were lost'",
                    "assert {'role': 'user', 'content': 'HIDDEN-BRANCH'} not in forwarded, 'hidden branch bytes leaked into sibling request'",
                    "assert forwarded[:3] == base + [ancestor_assistant], 'ancestor prefix was not byte-stable'",
                ),
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
