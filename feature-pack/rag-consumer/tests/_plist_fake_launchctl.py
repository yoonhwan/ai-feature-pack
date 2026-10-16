"""A fake `launchctl` for the plist-edit tests: read-only subcommands only, never the real launchd.

Every call is appended to $FAKE_LC_STATE/calls.txt (all arguments joined by spaces). Switches (environment):
  FAKE_LC_LOADED=1        `list` shows com.airag.consumer as a loaded job
  FAKE_LC_ENABLED=1       `print-disabled` reports com.airag.consumer => enabled
  FAKE_LC_NO_ENTRY=1      `print-disabled` has no line for com.airag.consumer
  FAKE_LC_LIST_FAIL=1     `list` exits 1 / FAKE_LC_DISABLED_FAIL=1 `print-disabled` exits 1
  FAKE_LC_LIST_GARBAGE=1  `list` exits 0 with output that has no header line
  FAKE_LC_SLEEP=<s>       every call hangs this long first
Any other subcommand is recorded and fails with exit 99 (the script under test must never issue one).
"""

from __future__ import annotations

import os
from pathlib import Path
import sys
import time

STATE = Path(os.environ["FAKE_LC_STATE"])


def main(argv: list[str]) -> int:
    STATE.mkdir(parents=True, exist_ok=True)
    with open(STATE / "calls.txt", "a", encoding="utf-8") as handle:
        handle.write(" ".join(argv) + "\n")
    if os.environ.get("FAKE_LC_SLEEP"):
        time.sleep(float(os.environ["FAKE_LC_SLEEP"]))
    command = argv[0] if argv else ""
    if command == "list":
        if os.environ.get("FAKE_LC_LIST_FAIL") == "1":
            return 1
        if os.environ.get("FAKE_LC_LIST_GARBAGE") == "1":
            sys.stdout.write("something unexpected\n")
            return 0
        sys.stdout.write("PID\tStatus\tLabel\n-\t0\tcom.apple.example.agent\n123\t0\tcom.example.other\n")
        if os.environ.get("FAKE_LC_LOADED") == "1":
            sys.stdout.write("-\t0\tcom.airag.consumer\n")
        return 0
    if command == "print-disabled":
        if os.environ.get("FAKE_LC_DISABLED_FAIL") == "1":
            return 1
        sys.stdout.write("disabled services = {\n\t\"com.example.other\" => enabled\n")
        if os.environ.get("FAKE_LC_NO_ENTRY") != "1":
            value = "enabled" if os.environ.get("FAKE_LC_ENABLED") == "1" else "disabled"
            sys.stdout.write(f'\t"com.airag.consumer" => {value}\n')
        sys.stdout.write("}\n")
        return 0
    sys.stderr.write("unsupported verb\n")
    return 99


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
