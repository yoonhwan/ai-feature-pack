"""One launchd tick: fill the store keys into this process only, run one consumer pass, log a value-free line.

Personal settings (vault references, token file, op path) live in a local credentials file given by
``--credentials``; nothing about them is stored in the repository. Existing environment keys win.
The consumer pass runs in a child process (``_pass_child``): keys go to it on stdin only, and its
streams never reach this process.
Each call is one pass: no loop, no sleep. launchd's next interval is the retry.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Callable, Mapping, Sequence, TextIO

from ._result import RESULT_MAX_BYTES, _clean_type, validate_frame

# Kept in step with operations.KEY_NAMES by a test: importing operations here would load sqlcipher3 into the tick.
NAMES = ("AIRAG_CONSUMER_KEY_HEX", "AIRAG_PROJECTION_KEY_HEX", "AIRAG_ARCHIVE_KEY_HEX")
EXIT_OK, EXIT_SKIPPED, EXIT_CONFIG, EXIT_KEYS, EXIT_RUNTIME, EXIT_INTERNAL = 0, 10, 20, 30, 40, 50
STATUS = {
    EXIT_OK: "ok", EXIT_SKIPPED: "skipped", EXIT_CONFIG: "config_error",
    EXIT_KEYS: "key_error", EXIT_RUNTIME: "runtime_error", EXIT_INTERNAL: "internal_error",
}
STATUS_DEGRADED = "degraded"  # exit 0, but at least one publication failed this pass
DEFAULT_LOG_DIR = Path.home() / ".local" / "share" / "airag" / "logs"
LOG_MAX_BYTES = 1_000_000
LOG_KEEP_DAYS = 14
_KEY = re.compile(r"[0-9a-fA-F]{64}")
# The only environment an `op` child gets besides the service-account token.
OP_ENV_ALLOWLIST = ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR")
# External-call 7-second rule: per attempt, one retry, whole call (one key) capped.
# 규칙 12 CLI: 기동 고정비 3.5(잠정) + 7.0 / 재시도 포함 총 21.0 ≤ 70
OP_ATTEMPT_TIMEOUT_S = 10.5
OP_CALL_DEADLINE_S = 21.0

# Probe (value-free `probe` field of the log line): per-key `op read` attempt record, closed schema.
PROBE_VERSION = 1
PROBE_MAX_BYTES = 1024  # the probe's own compact JSON; the rest of the line is never capped or cut
PROBE_OUTCOMES = ("ok", "bad_format", "nonzero_rc", "timeout", "exec_error")
PROBE_ERRORS = ("load_unavailable", "collect_failed", "probe_invalid", "probe_too_large")
_PROBE_MIN_ERRORS = ("collect_failed", "probe_invalid", "probe_too_large")
_PROBE_MS_MAX, _PROBE_TOTAL_MAX, _PROBE_LOAD_MAX = 120_000.0, 86_400.0, 10_000.0
TRACE_FILE_NAME = "pass-trace.jsonl"  # the pass child's per-call trace, next to the tick logs (see _pass_trace)


class TickError(Exception):
    """Carries an exit code and a value-free reason code."""

    def __init__(self, exit_code: int, code: str, kind: str = ""):
        super().__init__(code)
        self.exit_code, self.code, self.kind = exit_code, code, kind


class _Parser(argparse.ArgumentParser):
    def error(self, message: str):  # argparse text may echo arguments; keep only a code
        raise TickError(EXIT_CONFIG, "INVALID_ARGUMENTS")


def _parser() -> argparse.ArgumentParser:
    parser = _Parser(prog="airag_consumer.tick", add_help=False)
    parser.add_argument("--config", required=True)
    parser.add_argument("--credentials")
    parser.add_argument("--log-dir", default=str(DEFAULT_LOG_DIR))
    return parser


class _ProbeInvalid(Exception):
    """A raw measurement outside the closed probe schema; carries no value."""


def _is_float(value: object, high: float) -> bool:
    # Exactly `float` (no int/bool/Decimal), finite, in range: checked on the raw value, before any rounding.
    return type(value) is float and math.isfinite(value) and 0.0 <= value <= high


class _ProbeState:
    """What this tick observed for its probe. Every write is best effort and never changes what the tick does."""

    def __init__(self, origin: float | None):
        self.origin = origin
        self.attempts: dict[str, list[tuple[object, object, str]]] = {}
        self.load1: object = None
        self.failed = False  # an attempt record could not be taken

    @staticmethod
    def stamp() -> float | None:
        try:
            return time.monotonic()
        except Exception:
            return None

    def record(self, name: str, began: float, outcome: str, ended: float) -> None:
        """One `op read` attempt as millisecond offsets from the tick start (raw: checked and rounded at build)."""
        assert self.origin is not None
        self.attempts[name].append(((began - self.origin) * 1000.0, (ended - self.origin) * 1000.0, outcome))

    def collect_host(self) -> None:
        try:
            self.load1 = os.getloadavg()[0]
        except Exception:
            self.load1 = None


def _note_attempt(probe: _ProbeState, name: str, began: float | None, outcome: str, ended: float | None) -> None:
    try:
        probe.record(name, began, outcome, ended)  # type: ignore[arg-type]
    except Exception:
        probe.failed = True


def _make_probe(probe: _ProbeState, total_s: object) -> dict[str, object]:
    """Build the normal record from raw observations; raw values are validated first, rounded once after."""
    if not _is_float(total_s, _PROBE_TOTAL_MAX) or set(probe.attempts) - set(NAMES):
        raise _ProbeInvalid
    keys: list[dict[str, object]] = []
    for name in NAMES:
        recorded = probe.attempts.get(name)
        if not recorded:
            continue
        attempts = []
        for item in recorded:
            if not (isinstance(item, tuple) and len(item) == 3):
                raise _ProbeInvalid
            start, end, outcome = item
            if not (_is_float(start, _PROBE_MS_MAX) and _is_float(end, _PROBE_MS_MAX) and end >= start
                    and outcome in PROBE_OUTCOMES):
                raise _ProbeInvalid
            attempts.append({"start_ms": round(start, 3), "end_ms": round(end, 3), "outcome": outcome})
        if len(attempts) > 2:
            raise _ProbeInvalid
        keys.append({"name": name, "attempts": attempts})
    errors: list[str] = []
    load1 = probe.load1
    if _is_float(load1, _PROBE_LOAD_MAX):
        load1 = round(load1, 2)
    else:
        load1 = None
        errors.append("load_unavailable")
    if probe.failed:
        errors.append("collect_failed")
    record: dict[str, object] = {
        "v": PROBE_VERSION, "keys": keys, "tick_total_s": round(total_s, 3), "load1": load1,
    }
    if errors:
        record["probe_error"] = errors
    return record


def _exact(value: object, names: Sequence[str]) -> bool:
    return type(value) is dict and set(value) == set(names)


def _probe_valid(record: object) -> bool:
    """The closed schema (normal and minimal records): exact key sets, exact types, ranges, consistent reasons."""
    try:
        if type(record) is not dict or type(record.get("v")) is not int or record["v"] != PROBE_VERSION:
            return False
        if set(record) == {"v", "keys", "probe_error"}:  # minimal (recovery) record
            reasons = record["probe_error"]
            return record["keys"] == [] and type(reasons) is list and len(reasons) == 1 and reasons[0] in _PROBE_MIN_ERRORS
        required = {"v", "keys", "tick_total_s", "load1"}
        if set(record) not in (required, required | {"probe_error"}):
            return False
        keys = record["keys"]
        if type(keys) is not list or len(keys) > len(NAMES):
            return False
        seen: set[str] = set()
        for key in keys:
            if not _exact(key, ("name", "attempts")) or key["name"] not in NAMES or key["name"] in seen:
                return False
            seen.add(key["name"])
            attempts = key["attempts"]
            if type(attempts) is not list or not 1 <= len(attempts) <= 2:
                return False
            for attempt in attempts:
                if not _exact(attempt, ("start_ms", "end_ms", "outcome")):
                    return False
                if not (_is_float(attempt["start_ms"], _PROBE_MS_MAX) and _is_float(attempt["end_ms"], _PROBE_MS_MAX)
                        and attempt["end_ms"] >= attempt["start_ms"] and attempt["outcome"] in PROBE_OUTCOMES):
                    return False
        if not _is_float(record["tick_total_s"], _PROBE_TOTAL_MAX):
            return False
        load1 = record["load1"]
        if load1 is not None and not _is_float(load1, _PROBE_LOAD_MAX):
            return False
        reasons = record.get("probe_error", [])
        if type(reasons) is not list or (("probe_error" in record) and not reasons):
            return False
        if len(set(reasons)) != len(reasons) or any(r not in PROBE_ERRORS for r in reasons):
            return False
        return (load1 is None) == ("load_unavailable" in reasons)
    except Exception:
        return False


def _probe_text(record: dict[str, object]) -> str:
    return json.dumps(record, sort_keys=True, separators=(",", ":"))


def _minimal_probe(reason: str) -> dict[str, object]:
    record: dict[str, object] = {"v": PROBE_VERSION, "keys": [], "probe_error": [reason]}
    if not _probe_valid(record):
        raise ValueError("minimal probe invalid")
    return record


def _probe_for_line(probe: _ProbeState, total_s: object) -> dict[str, object] | None:
    """Recovery chain: normal record -> minimal record -> None (the line is then the pre-probe line)."""
    reason = "collect_failed"
    try:
        record = _make_probe(probe, total_s)
        reason = "probe_invalid"
        if _probe_valid(record):
            reason = "collect_failed"  # a serialization failure is not a size problem
            if len(_probe_text(record).encode("utf-8")) <= PROBE_MAX_BYTES:
                return record
            reason = "probe_too_large"
    except _ProbeInvalid:
        reason = "probe_invalid"
    except Exception:
        pass  # reason names the stage that failed; no message or value is kept
    try:
        return _minimal_probe(reason)
    except Exception:
        return None


def _compose(payload: dict[str, object], record: dict[str, object]) -> str:
    return json.dumps({**payload, "probe": record}, sort_keys=True, separators=(",", ":"))


def _line_with_probe(payload: dict[str, object], line: str, probe: _ProbeState, total_s: object) -> str:
    """``line`` plus the probe; the last serialization is part of the recovery chain, so a failure steps down to the
    minimal record and then to ``line`` (the pre-probe bytes), never raising."""
    try:
        record = _probe_for_line(probe, total_s)
    except Exception:
        return line
    if record is None:
        return line
    try:
        return _compose(payload, record)
    except Exception:
        pass
    if "tick_total_s" in record:  # the normal record could not be written: try the minimal one
        try:
            return _compose(payload, _minimal_probe("collect_failed"))
        except Exception:
            pass
    return line


def load_keys(environment: dict[str, str], credentials: Path | None, probe: _ProbeState | None = None) -> None:
    """Put the three store keys into ``environment``; keys already there are kept.

    ``probe`` collects the per-key attempt record only; it never changes what is read or retried.
    """
    probe = _ProbeState(_ProbeState.stamp()) if probe is None else probe
    present = {name: environment.get(name, "") for name in NAMES}
    if any(value and not _KEY.fullmatch(value) for value in present.values()):
        raise TickError(EXIT_KEYS, "EXISTING_KEY_FORMAT_INVALID")
    missing = [name for name, value in present.items() if not value]
    fetched: dict[str, str] = {}
    if missing:
        if credentials is None or not credentials.is_file():
            raise TickError(EXIT_CONFIG, "CREDENTIAL_SETTINGS_UNAVAILABLE")
        try:
            settings = json.loads(credentials.read_text(encoding="utf-8"))
            token_file = Path(settings["token_file"]).expanduser()
            references = settings["references"]
            op = settings.get("op") or shutil.which("op", path=environment.get("PATH"))
        except (OSError, ValueError, KeyError, TypeError):
            raise TickError(EXIT_CONFIG, "CREDENTIAL_SETTINGS_INVALID") from None
        if not isinstance(references, dict) or any(
            not isinstance(references.get(name), str) or not references[name].startswith("op://")
            for name in missing
        ):
            raise TickError(EXIT_CONFIG, "CREDENTIAL_SETTINGS_INVALID")
        if not op or not token_file.is_file():
            raise TickError(EXIT_KEYS, "OP_SERVICE_ACCOUNT_UNAVAILABLE")
        try:
            token = token_file.read_text(encoding="utf-8").strip()
        except OSError:
            raise TickError(EXIT_KEYS, "OP_SERVICE_ACCOUNT_UNAVAILABLE") from None
        if not token:
            raise TickError(EXIT_KEYS, "OP_SERVICE_ACCOUNT_TOKEN_EMPTY")
        child = {name: environment[name] for name in OP_ENV_ALLOWLIST if name in environment}
        child["OP_SERVICE_ACCOUNT_TOKEN"] = token

        def read(name: str) -> tuple[str, str]:
            deadline = time.monotonic() + OP_CALL_DEADLINE_S
            timeout = OP_ATTEMPT_TIMEOUT_S
            attempt = 1
            while True:
                began = probe.stamp()
                try:
                    result = subprocess.run(
                        [op, "read", references[name]], env=child, capture_output=True, text=True, timeout=timeout,
                    )
                    finished = probe.stamp()
                    break
                except (OSError, subprocess.TimeoutExpired) as error:  # class name only: timeout vs exec failure
                    _note_attempt(
                        probe, name, began,
                        "timeout" if isinstance(error, subprocess.TimeoutExpired) else "exec_error", time.monotonic(),
                    )
                    kind = _clean_type(type(error).__name__)
                    # Retry once, only for a timeout before any output (emptiness test only; the output is dropped).
                    silent = isinstance(error, subprocess.TimeoutExpired) and not (error.stdout or error.stderr)
                    timeout = min(OP_ATTEMPT_TIMEOUT_S, deadline - time.monotonic())  # now, after recording
                    if attempt == 2 or not silent or timeout <= 0:
                        raise TickError(EXIT_KEYS, "OP_READ_UNAVAILABLE", kind) from None
                    attempt += 1
            value = result.stdout.strip()
            _note_attempt(
                probe, name, began,
                "nonzero_rc" if result.returncode else ("ok" if _KEY.fullmatch(value) else "bad_format"), finished,
            )
            if result.returncode or not _KEY.fullmatch(value):
                raise TickError(EXIT_KEYS, "OP_KEY_READ_OR_FORMAT_FAILED")
            return name, value

        probe.attempts = {name: [] for name in missing}  # one list per key, each written by its own worker only
        with ThreadPoolExecutor(max_workers=3) as pool:
            fetched = dict(pool.map(read, missing))
    combined = {**{k: v for k, v in present.items() if v}, **fetched}
    if len({bytes.fromhex(value) for value in combined.values()}) != len(NAMES):
        raise TickError(EXIT_KEYS, "STORE_KEYS_MUST_BE_DISTINCT")
    environment.update(fetched)


def _open_regular(path: Path, flags: int) -> int:
    """Open without following a final symlink, never block on special files, and require a regular file."""
    fd = os.open(path, flags | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise OSError("not a regular file")
    return fd


def append_log(log_dir: Path, now: datetime, line: str) -> None:
    """Append one line to today's log, rotating first if it would pass the size cap; drop old days."""
    day = now.astimezone(timezone.utc).strftime("%Y%m%d")
    target = log_dir / f"tick-{day}.log"
    data = (line + "\n").encode("utf-8")
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    fd = _open_regular(target, flags)
    try:
        size = os.fstat(fd).st_size
        if size > 0 and size + len(data) > LOG_MAX_BYTES:
            os.close(fd)
            fd = -1
            os.replace(target, log_dir / f"tick-{day}.log.1")
            fd = _open_regular(target, flags)
        view = memoryview(data)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise OSError("log write incomplete")
            view = view[written:]
    finally:
        if fd >= 0:
            os.close(fd)
    oldest = (now.astimezone(timezone.utc) - timedelta(days=LOG_KEEP_DAYS)).strftime("%Y%m%d")
    for path in log_dir.glob("tick-????????.log*"):
        stamp = path.name[5:13]
        if stamp.isdigit() and stamp < oldest:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass


def _run_component(
    config: Path, environment: Mapping[str, str], log_dir: Path, command: Sequence[str],
) -> dict[str, object]:
    """Run one consumer pass in a child process and return its sanitized, re-validated frame.

    The child gets the keys on stdin only; its stdout is an anonymous file in the verified log dir and its
    stderr is discarded. Completion is the child's exit, never EOF, so a forked descendant cannot delay it.
    """
    child_env = {k: v for k, v in environment.items() if k not in NAMES}
    keys = json.dumps({name: environment[name] for name in NAMES})
    argv = [*command, "--config", str(config), "--trace-file", str(log_dir / TRACE_FILE_NAME)]
    try:
        with tempfile.TemporaryFile(dir=log_dir) as result:
            returncode = subprocess.run(
                argv, input=keys, text=True, env=child_env, stdout=result,
                stderr=subprocess.DEVNULL, close_fds=True, check=False,
            ).returncode
            size = os.fstat(result.fileno()).st_size
            data = b""
            if returncode == 0 and 0 < size <= RESULT_MAX_BYTES:
                result.seek(0)
                data = result.read(size)
    except OSError:
        raise TickError(EXIT_RUNTIME, "COMPONENT_PROCESS_UNAVAILABLE") from None
    if returncode == 3 or size > RESULT_MAX_BYTES:
        raise TickError(EXIT_RUNTIME, "RUNTIME_OUTPUT_INVALID")
    if returncode != 0:
        raise TickError(EXIT_RUNTIME, "COMPONENT_PROCESS_FAILED")
    try:
        frame = validate_frame(json.loads(data))
    except ValueError:
        frame = None
    if frame is None:
        raise TickError(EXIT_RUNTIME, "RUNTIME_OUTPUT_INVALID")
    return frame


def main(
    argv: Sequence[str] | None = None, *, environ: Mapping[str, str] | None = None,
    clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    stdout: TextIO | None = None, component: Sequence[str] | None = None,
) -> int:
    """Run one tick and return its exit code (see EXIT_*); prints one value-free JSON line."""
    out = sys.stdout if stdout is None else stdout
    probe = _ProbeState(_ProbeState.stamp())
    now = clock()
    probe.collect_host()
    log_dir: Path | None = None
    summary: dict[str, object] = {}
    code = kind = ""
    exit_code = EXIT_INTERNAL
    try:
        args = _parser().parse_args(list(sys.argv[1:] if argv is None else argv))
        config = Path(args.config).expanduser()
        candidate = Path(args.log_dir).expanduser()
        candidate.mkdir(mode=0o700, parents=True, exist_ok=True)
        if candidate.is_symlink() or not candidate.is_dir():
            raise TickError(EXIT_CONFIG, "LOG_DIR_UNSAFE")
        log_dir = candidate  # from here on, and only from here on, this directory may be logged to
        if not config.is_file():
            raise TickError(EXIT_CONFIG, "CONFIG_FILE_UNAVAILABLE")
        try:
            lock_fd = _open_regular(log_dir / "tick.lock", os.O_RDWR | os.O_CREAT)
        except OSError:
            raise TickError(EXIT_CONFIG, "LOCK_FILE_UNSAFE") from None
        try:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise TickError(EXIT_SKIPPED, "PREVIOUS_TICK_RUNNING") from None
            environment = dict(os.environ if environ is None else environ)
            load_keys(environment, Path(args.credentials).expanduser() if args.credentials else None, probe)
            started = time.monotonic()
            frame = _run_component(
                config, environment, log_dir,
                component if component is not None else [sys.executable, "-m", "airag_consumer._pass_child"],
            )
            if frame["exit"] != 0:
                raise TickError(EXIT_RUNTIME, frame["code"] or "RUNTIME_FAILED", frame["type"])
            if frame["code"] == "RUNTIME_OUTPUT_INVALID":
                raise TickError(EXIT_RUNTIME, "RUNTIME_OUTPUT_INVALID")
            summary = dict(frame["summary"])
            summary["pass_elapsed_s"] = round(time.monotonic() - started, 3)
            exit_code = EXIT_OK
        finally:
            os.close(lock_fd)
    except TickError as error:
        exit_code, code, kind = error.exit_code, error.code, error.kind
    except Exception as error:  # type only: messages may carry values
        exit_code, code = EXIT_INTERNAL, type(error).__name__
    ended = probe.stamp()
    total_s = None if ended is None or probe.origin is None else float(ended - probe.origin)
    payload = {
        "ts": now.astimezone(timezone.utc).isoformat(), "status": (
            STATUS_DEGRADED if exit_code == EXIT_OK and summary.get("published_failed", 0) > 0 else STATUS[exit_code]
        ), "exit": exit_code,
        **({"code": code} if code else {}), **({"type": kind} if kind else {}),
        **({"summary": summary} if summary else {}),
    }
    line = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    line = _line_with_probe(payload, line, probe, total_s)
    out.write(line + "\n")
    if log_dir is None:
        sys.stderr.write("tick log_unavailable\n")
    else:
        try:
            append_log(log_dir, now, line)
        except OSError:
            sys.stderr.write("tick log_write_failed\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
