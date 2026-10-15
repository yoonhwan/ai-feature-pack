"""A fake `launchctl` for the probe's --selftest: a few subcommands, state in $FAKE_LC_STATE, never the real launchd.

bootstrap starts the plist's ProgramArguments as the "job" with the plist's EnvironmentVariables plus the
"ambient" launchd environment (JSON in $FAKE_LC_AMBIENT_JSON) — a real launchd job may inherit variables the
wrapper never saw. bootout stops only that job process (not its descendants). Switches (environment):
  FAKE_LC_BOOTOUT_FAIL=1             bootout fails and leaves the job loaded
  FAKE_LC_BOOTSTRAP_SIGNAL=INT       bootstrap succeeds, then signals its parent (the probe script)
  FAKE_LC_BOOTSTRAP_SLEEP=<s>        bootstrap hangs this long before doing anything
  FAKE_LC_BOOTOUT_SLEEP=<s>          bootout hangs this long before doing anything
  FAKE_LC_PRINT_SLEEP_WHEN_LOADED=<s> `print` of a loaded probe label hangs this long
  FAKE_LC_PRINT_ERROR_ALWAYS=1       `print` of the probe label fails with an unrelated error
  FAKE_LC_PRINT_ERROR_WHEN_LOADED=1  `print` of the probe label fails with an unrelated error while it is loaded
  FAKE_LC_FOREIGN=1                  every probe label already exists, started by somebody else (foreign arguments)
  FAKE_LC_FOREIGN_AFTER_BOOTSTRAP=1  after our bootstrap the label shows foreign arguments (same name, not our job)
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
import time

STATE = Path(os.environ["FAKE_LC_STATE"])
NOT_FOUND = 'Could not find service "{}" in domain for user gui: 501'
FOREIGN = "arguments = {\n\t/other/python\n\t--run\n\t/other/place/not-ours\n}\npath = /other/place/job.plist\n"


def note(line: str) -> None:
    with open(STATE / "calls.txt", "a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def fail(message: str, rc: int) -> int:
    sys.stderr.write(message + "\n")
    return rc


def nap(name: str) -> None:
    seconds = os.environ.get(name)
    if seconds:
        time.sleep(float(seconds))


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
        path = STATE / f"{label}.json"
        loaded = path.exists()
        if os.environ.get("FAKE_LC_FOREIGN") == "1":
            sys.stdout.write(FOREIGN)
            return 0
        if os.environ.get("FAKE_LC_PRINT_ERROR_ALWAYS") == "1" or (
                loaded and os.environ.get("FAKE_LC_PRINT_ERROR_WHEN_LOADED") == "1"):
            return fail("Operation not permitted while System Integrity Protection is engaged", 1)
        if loaded:
            nap("FAKE_LC_PRINT_SLEEP_WHEN_LOADED")
            if os.environ.get("FAKE_LC_FOREIGN_AFTER_BOOTSTRAP") == "1":
                sys.stdout.write(FOREIGN)
                return 0
            info = json.loads(path.read_text(encoding="utf-8"))
            sys.stdout.write("state = running\narguments = {\n\t" + "\n\t".join(info["args"])
                             + "\n}\npath = " + info["plist"] + "\n")
            return 0
        return fail(NOT_FOUND.format(label), 113)
    if command == "bootstrap":
        nap("FAKE_LC_BOOTSTRAP_SLEEP")
        with open(argv[2], "rb") as handle:
            plist = plistlib.load(handle)
        env = {**plist.get("EnvironmentVariables", {}), **json.loads(os.environ.get("FAKE_LC_AMBIENT_JSON", "{}"))}
        job = subprocess.Popen(
            plist["ProgramArguments"], env=env, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )
        (STATE / f"{plist['Label']}.json").write_text(
            json.dumps({"pid": job.pid, "args": plist["ProgramArguments"], "plist": argv[2]}), encoding="utf-8")
        if os.environ.get("FAKE_LC_BOOTSTRAP_SIGNAL") == "INT":  # like Ctrl-C: the whole foreground group
            os.killpg(os.getpgid(0), signal.SIGINT)
        return 0
    if command == "bootout":
        nap("FAKE_LC_BOOTOUT_SLEEP")
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
