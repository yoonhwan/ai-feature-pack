#!/usr/bin/env python3
"""AutoResearch infrastructure setup — run once, idempotent.

Usage: uv run prepare.py

Customize the check_* functions for your project's infrastructure.
"""
from __future__ import annotations

import json
import socket
import subprocess
import sys
import time


def _check_port(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        return s.connect_ex(("127.0.0.1", port)) == 0


def _run(cmd: str, timeout: int = 10) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


# === CUSTOMIZE THESE FOR YOUR PROJECT ===

def check_runtime() -> bool:
    """Check your project's runtime is available.

    Examples:
      - ML: check GPU availability (nvidia-smi)
      - Web: check server alive (localhost:8000/health)
      - CLI: check binary exists (which mytool)
    """
    # TODO: Replace with your project's runtime check
    print("  [skip] check_runtime — customize for your project")
    return True


def check_data() -> bool:
    """Check required data/models are present.

    Examples:
      - ML: check dataset downloaded, tokenizer trained
      - Web: check browser/CDP available
      - CLI: check test fixtures exist
    """
    # TODO: Replace with your project's data check
    print("  [skip] check_data — customize for your project")
    return True


# === END CUSTOMIZATION ===


def main() -> None:
    print("=== AutoResearch prepare.py ===\n")

    checks = [
        ("runtime", check_runtime),
        ("data", check_data),
    ]

    results: dict[str, bool] = {}
    for name, fn in checks:
        results[name] = fn()

    print()
    all_ok = all(results.values())
    output = {"ready": all_ok, **{k: "ok" if v else "fail" for k, v in results.items()}}
    print(json.dumps(output))
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
