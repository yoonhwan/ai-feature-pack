"""Per-call trace of one consumer pass: one value-free JSON line per external call, appended as it happens.

The pass child writes a line when a provider call (or a published window) starts and another when it ends,
so a pass that never finishes still leaves "started, no end" behind: the tick's own log line is only
written after the pass returns. Nothing here may change what the pass does. A trace failure is swallowed,
a business exception passes through as the same object, and no value (URL, body, prompt, key, path) is
recorded. Design: r17 section 4, errata 1 sections 2-3, errata 2 sections 1, 2 and 6.

A line with no matching end is a call without a completion line, not a proven cut-off call: the end line may
be missing because of a lock race, the size budget or a write error. Read a file that ends without a newline,
holds a dropped line (``d``) or a stop line (``x``), or stops near the size cap as "trace incomplete".
"""

from __future__ import annotations

import functools
import inspect
import itertools
import json
import math
import os
import stat
import threading
import time
from typing import Callable

TRACE_VERSION = 1
LINE_MAX_BYTES = 192  # a trace line, newline included
FILE_MAX_BYTES = 384 * 1024
LINES_MAX = 2048
# The last 8 lines and 1 KiB are reserved for the stop line alone.
EVENT_LINES_MAX = LINES_MAX - 8
EVENT_BYTES_MAX = FILE_MAX_BYTES - 1024
STOP_LINE_MAX_BYTES = 96  # the stop line, leading newline included
CALL_NAMES = ("llm", "embed", "other")
CALL_OUTCOMES = ("ok", "timeout", "http_error", "unreachable", "error")
WINDOW_OUTCOMES = ("ok", "fail", "error")
STOP_REASONS = ("cap_lines", "cap_bytes", "write_error", "init_error")
_T_MAX = 86_400.0
_REQUIRED = {  # phase -> the exact key set (the optional dropped counter ``d`` is allowed on every phase)
    "b": ("v", "n", "ph", "name", "tok", "t"),
    "e": ("v", "n", "ph", "name", "tok", "t", "out"),
    "wb": ("v", "i", "ph", "t"),
    "we": ("v", "i", "ph", "t", "out"),
    "x": ("v", "ph", "t", "rsn"),
}
# Classification by the error's own code string (lower-cased); the exception object is never changed or printed.
_OUTCOME_BY_CODE = {
    "provider_timeout": "timeout",
    "provider_unreachable": "unreachable", "provider_unavailable": "unreachable",
    "provider_http_error": "http_error", "provider_rate_limited": "http_error",
    "provider_server_error": "http_error", "provider_request_error": "http_error",
}
TOKENIZE_PATH = "/tokenize"


def _int_in(value: object, low: int, high: int) -> bool:
    return type(value) is int and low <= value <= high


def _valid(record: object) -> bool:
    """The closed schema: exact key set per phase, exact types, ranges."""
    try:
        if type(record) is not dict:
            return False
        phase = record.get("ph")
        if type(phase) is not str or phase not in _REQUIRED:
            return False
        keys = set(record)
        keys.discard("d")
        if keys != set(_REQUIRED[phase]):
            return False
        if "d" in record and not _int_in(record["d"], 1, 99_999):
            return False
        t = record["t"]
        if not (_int_in(record["v"], TRACE_VERSION, TRACE_VERSION)
                and type(t) is float and math.isfinite(t) and 0.0 <= t <= _T_MAX):
            return False
        if phase in ("b", "e"):
            if not (_int_in(record["n"], 0, 99_999) and record["name"] in CALL_NAMES and type(record["tok"]) is bool):
                return False
            return phase == "b" or record["out"] in CALL_OUTCOMES
        if phase in ("wb", "we"):
            if not _int_in(record["i"], 0, 9_999):
                return False
            return phase == "wb" or record["out"] in WINDOW_OUTCOMES
        return record["rsn"] in STOP_REASONS
    except Exception:
        return False


def _encode(record: dict[str, object]) -> bytes | None:
    """The line as bytes (newline included), or None when it is outside the schema or too long."""
    if not _valid(record):
        return None
    data = (json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    return data if len(data) <= LINE_MAX_BYTES else None


class Trace:
    """The trace file of one pass. Every public method is best effort; none of them reports a value."""

    def __init__(self, path: str | os.PathLike[str], *, clock: Callable[[], float] = time.monotonic):
        self._clock = clock
        self._origin = clock()
        # Writes are serialized by this lock, taken without waiting: a business thread never queues behind a write.
        self._lock = threading.Lock()
        self._calls = itertools.count()
        self._windows = itertools.count()
        self._drops: list[None] = []  # one entry per line that was not written (append is atomic)
        self._fd = -1
        self._off = True
        self._lines = 0
        self._bytes = 0
        self._open(os.fspath(path))

    @property
    def active(self) -> bool:
        return not self._off

    def disable(self) -> None:
        self._off = True

    def _open(self, target: str) -> None:
        try:
            try:
                info = os.lstat(target)
            except FileNotFoundError:
                info = None  # the very first pass: nothing to rotate
            if info is not None:
                if not stat.S_ISREG(info.st_mode):  # a link or another kind of object: no trace this pass
                    return
                os.replace(target, target + ".prev")  # keep one generation of an interrupted pass
            fd = os.open(
                target, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600,
            )
        except OSError:
            return
        self._fd = fd
        self._off = False
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1:
                raise OSError("unsafe trace file")
            if info.st_mode & 0o077:
                os.fchmod(fd, 0o600)
            self._bytes = info.st_size
        except OSError:
            self._stop("init_error")

    def _t(self) -> float:
        return round(self._clock() - self._origin, 3)

    def _stop(self, reason: str) -> None:
        """Write the stop line once (best effort, always behind a newline so a torn line stays its own line)."""
        try:
            record: dict[str, object] = {"v": TRACE_VERSION, "ph": "x", "t": self._t(), "rsn": reason}
            if self._drops:
                record["d"] = min(len(self._drops), 99_999)
            data = _encode(record)
            if data is not None and len(data) + 1 <= STOP_LINE_MAX_BYTES:
                os.write(self._fd, b"\n" + data)
        except Exception:
            pass
        self._off = True
        try:
            os.close(self._fd)
        except OSError:
            pass

    def _emit(self, record: dict[str, object]) -> None:
        if self._off:
            return
        if not self._lock.acquire(blocking=False):
            self._drops.append(None)
            return
        try:
            if self._off:
                return
            if self._drops:
                record["d"] = min(len(self._drops), 99_999)
            data = _encode(record)
            if data is None:
                self._drops.append(None)
                return
            if self._lines >= EVENT_LINES_MAX:
                self._stop("cap_lines")
                return
            if self._bytes + len(data) > EVENT_BYTES_MAX:
                self._stop("cap_bytes")
                return
            try:
                written = os.write(self._fd, data)
            except OSError:
                self._stop("write_error")
                return
            self._lines += 1
            self._bytes += max(written, 0)
            if written != len(data):  # a torn line: stop here, the stop line starts with a newline
                self._stop("write_error")
        finally:
            self._lock.release()

    def begin_call(self, name: str, tokenize: bool) -> tuple[int, str, bool]:
        number = next(self._calls)
        self._emit({"v": TRACE_VERSION, "n": number, "ph": "b", "name": name, "tok": tokenize, "t": self._t()})
        return number, name, tokenize

    def end_call(self, token: tuple[int, str, bool], outcome: str) -> None:
        number, name, tokenize = token
        self._emit({
            "v": TRACE_VERSION, "n": number, "ph": "e", "name": name, "tok": tokenize, "t": self._t(), "out": outcome,
        })

    def begin_window(self) -> int:
        index = next(self._windows)
        self._emit({"v": TRACE_VERSION, "i": index, "ph": "wb", "t": self._t()})
        return index

    def end_window(self, index: int, outcome: str) -> None:
        self._emit({"v": TRACE_VERSION, "i": index, "ph": "we", "t": self._t(), "out": outcome})


def _classify(error: BaseException) -> str:
    code = getattr(error, "code", None)
    return _OUTCOME_BY_CODE.get(code.lower(), "error") if type(code) is str else "error"


def _begin_call(
    trace: Trace, name: str, signature: inspect.Signature | None, args: tuple[object, ...], kwargs: dict[str, object],
) -> tuple[int, str, bool] | None:
    try:
        tokenize = False
        if signature is not None:
            path = signature.bind(*args, **kwargs).arguments.get("path")  # the bound value, by position or keyword
            tokenize = type(path) is str and path == TOKENIZE_PATH
        return trace.begin_call(name, tokenize)
    except Exception:
        trace.disable()  # this call cannot be told apart (or recorded): stop tracing, never touch the call
        return None


def _end_call(trace: Trace, token: tuple[int, str, bool] | None, error: BaseException | None) -> None:
    if token is None:
        return
    try:
        trace.end_call(token, "ok" if error is None else _classify(error))
    except Exception:
        pass


def wrap_call(trace: Trace, owner: object, attr: str, name: str, *, tokenize: bool = False) -> bool:
    """Replace ``owner.attr`` by a pass-through that records the start and the end of each whole call."""
    original = getattr(owner, attr, None)
    if not callable(original):
        return False
    signature = None
    if tokenize:
        try:
            signature = inspect.signature(original)
        except (TypeError, ValueError):
            return False
        if "path" not in signature.parameters:
            return False

    @functools.wraps(original)
    def wrapper(*args, **kwargs):
        token = _begin_call(trace, name, signature, args, kwargs)
        try:
            result = original(*args, **kwargs)
        except BaseException as error:
            _end_call(trace, token, error)
            raise
        _end_call(trace, token, None)
        return result

    setattr(owner, attr, wrapper)
    return True


def _begin_window(trace: Trace) -> int | None:
    try:
        return trace.begin_window()
    except Exception:
        return None


def _end_window(trace: Trace, index: int | None, outcome: str) -> None:
    if index is None:
        return
    try:
        trace.end_window(index, outcome)
    except Exception:
        pass


def wrap_window(trace: Trace, owner: object, attr: str) -> bool:
    """Replace the window publisher by a pass-through that records one start/end pair per window."""
    original = getattr(owner, attr, None)
    if not callable(original):
        return False

    @functools.wraps(original)
    def wrapper(*args, **kwargs):
        index = _begin_window(trace)
        try:
            result = original(*args, **kwargs)
        except BaseException:
            _end_window(trace, index, "error")
            raise
        _end_window(trace, index, "ok" if isinstance(result, dict) and result.get("ok") is True else "fail")
        return result

    setattr(owner, attr, wrapper)
    return True


def install(path: str | os.PathLike[str]) -> Trace | None:
    """Trace the three provider adapters and the window publisher of this process; None when it cannot be done.

    Either every target is present in the expected shape or nothing is wrapped (and no file is touched).
    """
    try:
        from airag import embeddings, llm_enrichment

        from . import bridge, memory

        extractor = memory.OpenAICompatibleMemoryExtractor
        targets = (
            (llm_enrichment, "_post_json"), (embeddings, "_post_embeddings"), (extractor, "__call__"),
            (bridge, "_publish_window"),
        )
        if not all(callable(getattr(owner, attr, None)) for owner, attr in targets):
            return None
        if "path" not in inspect.signature(llm_enrichment._post_json).parameters:
            return None
        trace = Trace(path)
        if not trace.active:
            return None
        wrap_call(trace, llm_enrichment, "_post_json", "llm", tokenize=True)
        wrap_call(trace, embeddings, "_post_embeddings", "embed")
        wrap_call(trace, extractor, "__call__", "llm")
        wrap_window(trace, bridge, "_publish_window")
        return trace
    except Exception:
        return None
