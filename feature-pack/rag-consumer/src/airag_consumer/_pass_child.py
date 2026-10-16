"""One consumer pass in its own process, so nothing a component prints can reach the tick's streams.

Protocol (the tick is the parent): the three store keys arrive as one JSON object on stdin; the parent's
stdout is an anonymous result file, which is duplicated and then kept private while fds 1 and 2 are
permanently pointed at /dev/null *before* any component code is imported. The only thing written to the
result file is one sanitized frame (see ``_result``). Exit 0 = frame delivered, 2 = protocol failure,
3 = frame too large.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
from typing import Sequence

from . import _pass_gate, _pass_trace, _result
from .tick import NAMES

_STDIN_LIMIT = 64 * 1024
_KEY = re.compile(r"[0-9a-fA-F]{64}")


def _read_keys() -> dict[str, str] | None:
    raw = sys.stdin.buffer.read(_STDIN_LIMIT + 1)
    if len(raw) > _STDIN_LIMIT:
        return None
    try:
        keys = json.loads(raw)
    except ValueError:
        return None
    if not isinstance(keys, dict) or set(keys) != set(NAMES):
        return None
    values = []
    for name in NAMES:
        value = keys[name]
        if not isinstance(value, str) or _KEY.fullmatch(value) is None:  # exact hex: fromhex alone accepts spaces
            return None
        values.append(bytes.fromhex(value))
    if len(set(values)) != len(NAMES):
        return None
    return keys


def _write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            raise OSError("result write incomplete")
        view = view[written:]


def child_main(argv: Sequence[str] | None = None, *, hooks: object | None = None) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--config", required=True)
    parser.add_argument("--trace-file")
    parser.add_argument("--state-file")
    try:
        args = parser.parse_args(list(sys.argv[1:] if argv is None else argv))
    except SystemExit:
        return 2
    keys = _read_keys()
    if keys is None:
        return 2
    try:
        result_fd = os.dup(1)
        null = os.open(os.devnull, os.O_WRONLY)
        os.dup2(null, 1)
        os.dup2(null, 2)
        os.close(null)
    except OSError:
        return 2
    # From here on fds 1 and 2 are /dev/null for good; component imports and output go there.
    if args.trace_file:
        try:
            _pass_trace.install(args.trace_file)  # records provider calls; never changes the pass
        except Exception:
            pass
    stdout_buffer, stderr_buffer = io.StringIO(), io.StringIO()
    gate = _pass_gate.Gate()
    started = False
    try:
        if args.state_file:  # the read-only DB check and the running/clean mark come before the pass
            gate = _pass_gate.before_pass(
                args.config, args.state_file, bytes.fromhex(keys[NAMES[0]]), bytes.fromhex(keys[NAMES[1]]),
            )
        else:  # no state path, no gate, so no pass: there is never work without the check and the running mark
            gate = _pass_gate.Gate(None, None, {"code": "PASS_STATE_UNAVAILABLE", "type": "pass_state"})
        if gate.refusal is not None:
            code = 1  # no pass: the frame below carries the refusal
        else:
            from .cli import main as cli_main

            environ = {**os.environ, **keys}
            started = True
            code = cli_main(
                ["--config", args.config, "run", "--once"], environ=environ, hooks=hooks,
                stdout=stdout_buffer, stderr=stderr_buffer,
            )
    except BaseException as error:
        code = 2
        stdout_buffer = io.StringIO()
        stderr_buffer = io.StringIO(json.dumps(
            {"ok": False, "error": {"code": "RUNTIME_FAILED", "type": type(error).__name__}},
        ))
    if started:  # the pass ended on its own (normally or by an exception); a forced kill never gets here
        _pass_gate.after_pass(gate, args.state_file)
    if gate.refusal is not None:
        frame = {"exit": 1, "summary": {}, "code": gate.refusal["code"], "type": gate.refusal["type"]}
    else:
        frame = _result.build_frame(code, stdout_buffer.getvalue(), stderr_buffer.getvalue())
    if gate.integrity is not None:
        frame["integrity"] = gate.integrity
    payload = json.dumps(frame, sort_keys=True, separators=(",", ":")).encode("utf-8")
    if len(payload) > _result.RESULT_MAX_BYTES:
        os.close(result_fd)
        return 3
    try:
        _write_all(result_fd, payload)
    except OSError:
        return 2
    finally:
        os.close(result_fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(child_main())
