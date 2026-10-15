"""A fake `launchctl` for the probe's --selftest: a few subcommands, state in $FAKE_LC_STATE, never the real launchd.

bootstrap starts the plist's ProgramArguments (with only the plist's EnvironmentVariables) as the "job";
bootout stops only that job process (not its descendants). Switches (environment):
  FAKE_LC_BOOTOUT_FAIL=1             bootout fails and leaves the job loaded
  FAKE_LC_BOOTSTRAP_SIGNAL=INT       bootstrap succeeds, then signals its parent (the probe script)
  FAKE_LC_PRINT_ERROR_ALWAYS=1       `print` of the probe label fails with an unrelated error
  FAKE_LC_PRINT_ERROR_WHEN_LOADED=1  `print` of the probe label fails with an unrelated error while it is loaded
  FAKE_LC_CONSUMER_LOADED=1          `print` of com.airag.consumer reports it as loaded
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys

STATE = Path(os.environ["FAKE_LC_STATE"])
NOT_FOUND = 'Could not find service "{}" in domain for user gui: 501'


def note(line: str) -> None:
    with open(STATE / "calls.txt", "a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def fail(message: str, rc: int) -> int:
    sys.stderr.write(message + "\n")
    return rc


def main(argv: list[str]) -> int:
    STATE.mkdir(parents=True, exist_ok=True)
    command = argv[0] if argv else ""
    note(" ".join(argv[:2]))
    if command == "print-disabled":
        sys.stdout.write('disabled services = {\n\t"com.airag.consumer" => disabled\n}\n')
        return 0
    if command == "print":
        label = argv[1].rsplit("/", 1)[-1]
        if label == "com.airag.consumer":
            if os.environ.get("FAKE_LC_CONSUMER_LOADED") == "1":
                return 0
            return fail(NOT_FOUND.format(label), 113)
        loaded = (STATE / f"{label}.json").exists()
        if os.environ.get("FAKE_LC_PRINT_ERROR_ALWAYS") == "1" or (
                loaded and os.environ.get("FAKE_LC_PRINT_ERROR_WHEN_LOADED") == "1"):
            return fail("Operation not permitted while System Integrity Protection is engaged", 1)
        if loaded:
            sys.stdout.write("state = running\n")
            return 0
        return fail(NOT_FOUND.format(label), 113)
    if command == "bootstrap":
        with open(argv[2], "rb") as handle:
            plist = plistlib.load(handle)
        job = subprocess.Popen(
            plist["ProgramArguments"], env=plist.get("EnvironmentVariables", {}), stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )
        (STATE / f"{plist['Label']}.json").write_text(json.dumps({"pid": job.pid}), encoding="utf-8")
        if os.environ.get("FAKE_LC_BOOTSTRAP_SIGNAL") == "INT":
            os.kill(os.getppid(), signal.SIGINT)
        return 0
    if command == "bootout":
        label = argv[1].rsplit("/", 1)[-1]
        if os.environ.get("FAKE_LC_BOOTOUT_FAIL") == "1":
            return fail("Boot-out failed: 5: Input/output error", 5)
        path = STATE / f"{label}.json"
        if not path.exists():
            return fail(NOT_FOUND.format(label), 113)
        try:
            os.kill(json.loads(path.read_text(encoding="utf-8"))["pid"], signal.SIGTERM)
        except ProcessLookupError:
            pass
        path.unlink()
        return 0
    return fail("unsupported fake subcommand", 64)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
