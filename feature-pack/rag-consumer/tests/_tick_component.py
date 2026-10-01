"""Synthetic pass child used by the tick tests: ``python _tick_component.py <mode> --config <path>``.

The parent tick appends ``--config``; this script builds the hooks for ``mode`` and calls the real
``_pass_child.child_main``. Underscore-prefixed so pytest does not collect it.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "src"), str(HERE)]

from airag_consumer._pass_child import child_main  # noqa: E402


def hooks_for(mode: str):
    from airag_consumer.runtime import RuntimeHooks
    from test_runtime import DecisionExtractor, SyntheticBridge

    if mode == "memory":
        return RuntimeHooks(bridge=SyntheticBridge(), memory_extractor=DecisionExtractor())
    return RuntimeHooks(bridge=SyntheticBridge())


if __name__ == "__main__":
    mode = sys.argv[1]
    raise SystemExit(child_main(sys.argv[2:], hooks=hooks_for(mode)))
