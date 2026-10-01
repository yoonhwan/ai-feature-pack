"""Synthetic pass child used by the tick tests: ``python _tick_component.py <mode> --config <path>``.

The parent tick appends ``--config``; this script builds the hooks for ``mode`` and calls the real
``_pass_child.child_main``. Underscore-prefixed so pytest does not collect it.
"""

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "src"), str(HERE)]

from airag_consumer._pass_child import child_main  # noqa: E402


KEYLIKE = "AB" * 32  # key-shaped uppercase hex: passes naive code regexes


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
            if mode in ("native", "native-raise"):
                ctypes.CDLL(None).printf(b"MARKER_NATIVE\n")  # libc stdio, deliberately never flushed
                print("MARKER_PY_PRINT")
                os.write(1, b"MARKER_FD_NATIVE\n")
                if mode == "native-raise":
                    raise RuntimeError("inside")
            return SyntheticBridge.publish_pending_windows(lifecycle, scope, core, **kwargs)

    extractor = DecisionExtractor() if mode == "memory" else None
    return RuntimeHooks(bridge=Bridge(), memory_extractor=extractor)


if __name__ == "__main__":
    mode = sys.argv[1]
    raise SystemExit(child_main(sys.argv[2:], hooks=hooks_for(mode)))
