"""One launchd tick: fill the store keys into this process only, run one consumer pass, log a value-free line.

Personal settings (vault references, token file, op path) live in a local credentials file given by
``--credentials``; nothing about them is stored in the repository. Existing environment keys win.
The consumer pass runs in-process (``cli.main``), so keys never appear in any child argv.
Each call is one pass: no loop, no sleep. launchd's next interval is the retry.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from datetime import datetime, timedelta, timezone
import fcntl
from functools import lru_cache
import io
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time
from typing import Callable, Mapping, Sequence, TextIO

from .operations import KEY_NAMES

NAMES = tuple(KEY_NAMES.values())
EXIT_OK, EXIT_SKIPPED, EXIT_CONFIG, EXIT_KEYS, EXIT_RUNTIME, EXIT_INTERNAL = 0, 10, 20, 30, 40, 50
STATUS = {
    EXIT_OK: "ok", EXIT_SKIPPED: "skipped", EXIT_CONFIG: "config_error",
    EXIT_KEYS: "key_error", EXIT_RUNTIME: "runtime_error", EXIT_INTERNAL: "internal_error",
}
DEFAULT_LOG_DIR = Path.home() / ".local" / "share" / "airag" / "logs"
LOG_MAX_BYTES = 1_000_000
LOG_KEEP_DAYS = 14
_KEY = re.compile(r"[0-9a-fA-F]{64}")
_CODE = re.compile(r"[A-Z][A-Z0-9_]{1,100}")
_TYPE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,60}")
# The only environment an `op` child gets besides the service-account token.
OP_ENV_ALLOWLIST = ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR")


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


def load_keys(environment: dict[str, str], credentials: Path | None) -> None:
    """Put the three store keys into ``environment``; keys already there are kept."""
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
            try:
                result = subprocess.run(
                    [op, "read", references[name]], env=child, capture_output=True, text=True, timeout=30,
                )
            except (OSError, subprocess.TimeoutExpired):
                raise TickError(EXIT_KEYS, "OP_READ_UNAVAILABLE") from None
            value = result.stdout.strip()
            if result.returncode or not _KEY.fullmatch(value):
                raise TickError(EXIT_KEYS, "OP_KEY_READ_OR_FORMAT_FAILED")
            return name, value

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


def _counts(data: Mapping[str, object]) -> dict[str, object]:
    """Numbers and flags only: never conversation, memory text, quotes or paths."""
    summary: dict[str, object] = {}
    collected = data.get("collected")
    if isinstance(collected, list):
        rows = [row for row in collected if isinstance(row, dict)]
        summary["sources"] = len(rows)
        summary["accepted"] = sum(row.get("accepted_count", 0) for row in rows if type(row.get("accepted_count")) is int)
        summary["gaps"] = sum(row.get("gap_count", 0) for row in rows if type(row.get("gap_count")) is int)
        for key in ("committed_native_offset", "pending_bytes"):
            summary[f"{key}_total"] = sum(row[key] for row in rows if type(row.get(key)) is int)
        summary["coverage_complete"] = bool(rows) and all(row.get("coverage_complete") is True for row in rows)
    published = data.get("published")
    if isinstance(published, dict):
        for key in ("attempted", "succeeded"):
            if type(published.get(key)) is int:
                summary[f"published_{key}"] = published[key]
    memory = data.get("memory")
    if isinstance(memory, dict):
        summary["memory_enabled"] = memory.get("enabled") is True
        for key in (
            "attempts", "candidate_count", "materialized_count", "awaiting_confirmation_count",
            "unverified_count", "conflict_count", "rejected_count", "batch_message_count",
        ):
            if type(memory.get(key)) is int:
                summary[f"memory_{key}"] = memory[key]
        if isinstance(memory.get("provider_called"), bool):
            summary["memory_provider_called"] = memory["provider_called"]
    if isinstance(data.get("archives"), list):
        summary["archived"] = len(data["archives"])
    backup = data.get("backup")
    if isinstance(backup, dict):
        summary["backup_due"] = backup.get("due") is True
        summary["backup_created"] = backup.get("created") is True
    return summary


@lru_cache(maxsize=1)
def _known_codes() -> frozenset[str]:
    """Reason codes this software really emits: every uppercase literal in its own sources."""
    roots = [Path(__file__).resolve().parent]
    try:
        import airag

        roots.append(Path(airag.__file__).resolve().parent)
    except Exception:
        pass
    found: set[str] = set()
    for root in roots:
        for path in root.rglob("*.py"):
            try:
                found.update(re.findall(r"""["']([A-Z][A-Z0-9_]{1,100})["']""", path.read_text(encoding="utf-8")))
            except OSError:
                continue
    return frozenset(found)


def _safe_code(value: object) -> str:
    """Report a reason code only if it is a known literal; an error message is data, not a code."""
    if isinstance(value, str) and _CODE.fullmatch(value) and value in _known_codes():
        return value
    return "RUNTIME_FAILED"


def _error_fields(stream: str) -> tuple[str, str]:
    try:
        error = json.loads(stream.strip().splitlines()[-1])["error"]
    except (ValueError, KeyError, IndexError, TypeError):
        return "RUNTIME_FAILED", ""
    kind = error.get("type") if isinstance(error, dict) else None
    kind = kind if isinstance(kind, str) and _TYPE.fullmatch(kind) and not re.search(r"[0-9a-fA-F]{16}", kind) else ""
    return _safe_code(error.get("code") if isinstance(error, dict) else None), kind


@contextmanager
def _discard_component_output():
    """Whatever components print during the pass is dropped, at the Python and the file-descriptor level.

    Stream objects held from before the pass are flushed while fds 1 and 2 still point to /dev/null,
    so nothing buffered can surface after the real destinations are restored.
    """
    original = (sys.stdout, sys.stderr)
    for stream in original:
        stream.flush()
    saved: list[int] = []
    null = -1
    try:
        saved.append(os.dup(1))
        saved.append(os.dup(2))
        null = os.open(os.devnull, os.O_WRONLY)
        os.dup2(null, 1)
        os.dup2(null, 2)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            yield
    finally:
        for stream in original:
            try:
                stream.flush()
            except Exception:
                pass
        for number, fd in zip((1, 2), saved):
            os.dup2(fd, number)
            os.close(fd)
        if null >= 0:
            os.close(null)


def main(
    argv: Sequence[str] | None = None, *, environ: Mapping[str, str] | None = None,
    clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    stdout: TextIO | None = None, hooks: object | None = None,
) -> int:
    """Run one tick and return its exit code (see EXIT_*); prints one value-free JSON line."""
    out = sys.stdout if stdout is None else stdout
    now = clock()
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
            load_keys(environment, Path(args.credentials).expanduser() if args.credentials else None)
            from .cli import main as cli_main

            stdout_buffer, stderr_buffer = io.StringIO(), io.StringIO()
            started = time.monotonic()
            with _discard_component_output():
                result = cli_main(
                    ["--config", str(config), "run", "--once"], environ=environment, hooks=hooks,
                    stdout=stdout_buffer, stderr=stderr_buffer,
                )
            if result != 0:
                reason, kind = _error_fields(stderr_buffer.getvalue())
                raise TickError(EXIT_RUNTIME, reason, kind)
            try:
                data = json.loads(stdout_buffer.getvalue())["data"]
            except (ValueError, KeyError, TypeError):
                raise TickError(EXIT_RUNTIME, "RUNTIME_OUTPUT_INVALID") from None
            summary = _counts(data if isinstance(data, dict) else {})
            summary["pass_elapsed_s"] = round(time.monotonic() - started, 3)
            exit_code = EXIT_OK
        finally:
            os.close(lock_fd)
    except TickError as error:
        exit_code, code, kind = error.exit_code, error.code, error.kind
    except Exception as error:  # type only: messages may carry values
        exit_code, code = EXIT_INTERNAL, type(error).__name__
    line = json.dumps({
        "ts": now.astimezone(timezone.utc).isoformat(), "status": STATUS[exit_code], "exit": exit_code,
        **({"code": code} if code else {}), **({"type": kind} if kind else {}),
        **({"summary": summary} if summary else {}),
    }, sort_keys=True, separators=(",", ":"))
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
