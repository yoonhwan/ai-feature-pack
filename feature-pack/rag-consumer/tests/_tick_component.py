"""Synthetic pass child used by the tick tests: ``python _tick_component.py <mode> --config <path>``.

The parent tick appends ``--config``; this script builds the hooks for ``mode`` and calls the real
``_pass_child.child_main``. Underscore-prefixed so pytest does not collect it.
"""

import json
import os
import stat
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "src"), str(HERE)]

from airag_consumer._pass_child import child_main  # noqa: E402


NAMES = ("AIRAG_CONSUMER_KEY_HEX", "AIRAG_PROJECTION_KEY_HEX", "AIRAG_ARCHIVE_KEY_HEX")
KEYLIKE = "AB" * 32  # key-shaped uppercase hex: passes naive code regexes


def marker(**values) -> None:
    """Record booleans for the test in the file named by TICK_MARKER (values only, never data)."""
    path = os.environ.get("TICK_MARKER")
    if path:
        Path(path).write_text(json.dumps(values), encoding="utf-8")


def fork_descendant(chatty: bool) -> None:
    """Fork (no exec) a finite-lived grandchild that keeps the inherited fds, then carry on."""
    if os.fork() != 0:
        return
    status = 1
    try:
        if chatty:
            os.write(1, b"MARKER_DESC\n")
            os.write(2, b"MARKER_DESC\n")
        time.sleep(5)  # outlives the rest of the pass even on a loaded machine
        from airag_consumer import _result

        alive = value_free = False
        for fd in range(3, 32):
            try:
                info = os.fstat(fd)
                if info.st_nlink == 0 and stat.S_ISREG(info.st_mode):
                    alive = True
                    frame = _result.validate_frame(json.loads(os.pread(fd, 65_536, 0)))
                    value_free = frame is not None and "MARKER_" not in json.dumps(frame)
            except (OSError, ValueError):
                continue
        marker(alive_nlink0=alive, value_free=value_free)
        status = 0
    finally:
        os._exit(status)


def _failures(lifecycle, scope, codes, *, ok=0, message="MARKER_SECRET"):
    """Claim the pending windows and report them failed with ``codes`` (then ``ok`` successes)."""
    state = lifecycle.refresh(scope)
    out = []
    for index, window_id in enumerate(state["pending_publication_ids"]):
        lifecycle.claim_publication(scope, window_id)
        if index < ok:
            lifecycle.finish_publication(scope, window_id, success=True)
            out.append({"ok": True, "window_id": window_id})
        else:
            code = codes[(index - ok) % len(codes)]
            lifecycle.finish_publication(scope, window_id, success=False, error_code="CORE_PUBLICATION_FAILED")
            out.append({"ok": False, "window_id": window_id,
                        "error": {"code": code, "retryable": True, "message": message}})
    return out


PUBLISH_CASES = {
    "all-unreachable": lambda lc, sc: _failures(lc, sc, ["PROVIDER_UNREACHABLE"]),
    "unknown-code": lambda lc, sc: _failures(lc, sc, ["XX_UNKNOWN_CODE"]),
    "partial": lambda lc, sc: _failures(lc, sc, ["PROVIDER_UNREACHABLE"], ok=1),
    "mismatch": lambda lc, sc: _failures(lc, sc, ["PROVIDER_UNREACHABLE"])[:0] + [
        {"ok": True, "window_id": "w1"}, {"ok": False, "window_id": "w2", "error": {"code": "PROVIDER_UNREACHABLE"}}][:1],
}


def hooks_for(mode: str):
    import ctypes

    from airag_consumer.runtime import RuntimeHooks
    from test_runtime import DecisionExtractor, SyntheticBridge

    class Bridge(SyntheticBridge):
        @staticmethod
        def publish_pending_windows(lifecycle, scope, core, **kwargs):
            if mode == "keylike":
                raise RuntimeError(KEYLIKE)
            if mode == "short":
                raise RuntimeError("SHORT_SECRET_VALUE")
            if mode == "chatty":
                print("MARKER_BODY_PRINT")
                sys.stderr.write("MARKER_QUOTE_STDERR\n")
                os.write(1, b"MARKER_FD_STDOUT\n")
                os.write(2, b"MARKER_FD_STDERR\n")
            if mode == "huge-raw":
                print("MARKER_HUGE_RAW" * 350_000)  # ~5 MiB on the child's /dev/null stdout
                sys.stderr.write("MARKER_HUGE_RAW" * 350_000)
            if mode == "envname":
                raise RuntimeError("OP_SERVICE_ACCOUNT_TOKEN")
            if mode == "declared":
                raise RuntimeError("SYMLINK_PATH_REJECTED")  # a code the sources declare
            if mode.startswith("publish:"):
                # publish:<name> -> a list result of failing windows, built from PUBLISH_CASES
                return PUBLISH_CASES[mode.split(":", 1)[1]](lifecycle, scope)
            if mode in ("fork-descendant", "fork-descendant-chatty"):
                fork_descendant(chatty=mode.endswith("chatty"))
            if mode == "env-probe":
                import subprocess

                grand = subprocess.run(
                    [sys.executable, "-c", "import os,sys;sys.exit(int(any(n in os.environ for n in sys.argv[1:])))",
                     *NAMES], check=False,
                ).returncode
                marker(own_has_names=any(name in os.environ for name in NAMES), grandchild_has_names=bool(grand))
            if mode in ("native", "native-raise"):
                ctypes.CDLL(None).printf(b"MARKER_NATIVE\n")  # libc stdio, deliberately never flushed
                print("MARKER_PY_PRINT")
                os.write(1, b"MARKER_FD_NATIVE\n")
                if mode == "native-raise":
                    raise RuntimeError("inside")
            return SyntheticBridge.publish_pending_windows(lifecycle, scope, core, **kwargs)

    extractor = DecisionExtractor() if mode == "memory" else None
    return RuntimeHooks(bridge=Bridge(), memory_extractor=extractor)


def raw_mode(mode: str) -> int | None:
    """Modes that never call child_main: the protocol itself is what is under test."""
    if mode == "crash":
        import signal

        os.kill(os.getpid(), signal.SIGKILL)
    if mode == "bad-protocol":
        os.write(1, b"MARKER_GARBAGE not json")
        return 0
    if mode == "bad-protocol-large":
        os.write(1, b"x" * (1 << 20))
        return 0
    if mode.startswith("forged-code-"):
        code = {"list": ["MARKER_CODE"], "dict": {"MARKER_CODE": 1}, "null": None, "int": 7}[mode[len("forged-code-"):]]
        os.write(1, json.dumps({"exit": 0, "summary": {}, "code": code, "type": ""}).encode())
        return 0
    if mode in ("forged-frame", "forged-extra-key"):
        frame = {"exit": 40, "summary": {}, "code": "ZZ_FORGED_CODE", "type": ""}
        if mode == "forged-extra-key":
            frame = {"exit": 0, "summary": {}, "code": "", "type": "", "body": "MARKER_FORGED"}
        os.write(1, json.dumps(frame).encode())
        return 0
    return None


def import_probe_main(argv) -> int:
    """Record whether fds 1 and 2 are /dev/null at the moment airag_consumer.cli is first imported."""
    import importlib.abc

    class Probe(importlib.abc.MetaPathFinder):
        def find_spec(self, name, path=None, target=None):
            if name == "airag_consumer.cli":
                null = os.stat(os.devnull)
                same = all(os.fstat(fd).st_rdev == null.st_rdev and os.fstat(fd).st_ino == null.st_ino
                           for fd in (1, 2))
                marker(fds_are_devnull=same)
                raise ImportError("probe")
            return None

    sys.meta_path.insert(0, Probe())
    return child_main(argv)


if __name__ == "__main__":
    mode = sys.argv[1]
    early = raw_mode(mode)
    if early is not None:
        raise SystemExit(early)
    if mode == "import-probe":
        raise SystemExit(import_probe_main(sys.argv[2:]))
    if mode == "oversize-frame":
        from airag_consumer import _result

        _result.RESULT_MAX_BYTES = 10
        raise SystemExit(child_main(sys.argv[2:], hooks=hooks_for("normal")))
    if mode in ("huge-cli-stdout", "huge-cli-stderr"):
        # A synthetic CLI that fills the StringIO it is really handed: raw output far over the result limit.
        import types

        def cli_main(argv, *, environ=None, hooks=None, stdout=None, stderr=None):
            big = "MARKER_HUGE_CLI" * 350_000  # ~5 MiB, not JSON
            if mode == "huge-cli-stdout":
                stdout.write(big)
                return 0
            stderr.write(big)
            return 2

        fake = types.ModuleType("airag_consumer.cli")
        fake.main = cli_main
        sys.modules["airag_consumer.cli"] = fake
        raise SystemExit(child_main(sys.argv[2:]))
    if mode == "body-in-output":
        from airag_consumer.runtime import AIRAGRuntime

        original = AIRAGRuntime.run_once

        def run_once(self, **kwargs):
            data = original(self, **kwargs)
            data["note"] = "MARKER_BODY"
            data["details"] = [{"quote": "MARKER_QUOTE", "path": "/synthetic/path"}]
            return data

        AIRAGRuntime.run_once = run_once
        mode = "normal"
    raise SystemExit(child_main(sys.argv[2:], hooks=hooks_for(mode)))
