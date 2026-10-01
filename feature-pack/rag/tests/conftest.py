from __future__ import annotations

import os
import tempfile
from collections.abc import Callable, Iterator
from pathlib import Path

import pytest

from airag import keys


@pytest.hookimpl(tryfirst=True)
def pytest_configure(config: pytest.Config) -> None:
    """A plain `pytest` invocation with no explicit --basetemp must never
    reuse pytest's own numbered tmp dirs (pytest-NNN under the system temp
    root) — that mechanism retains only the last few and DELETES older ones
    at collection time, which is exactly the auto-cleanup the P-03(-B)
    dispatch forbids for retained evidence DBs (mkdtemp with no
    auto-cleanup, per-run unique --basetemp). So: no explicit --basetemp ->
    assign a fresh tempfile.mkdtemp() here, every run, before pytest's own
    tmp_path machinery reads the option. An explicitly-passed --basetemp
    that already exists and is non-empty is refused outright rather than
    reused — reusing it would let pytest's own retention logic inside that
    tree delete whatever a previous run left there."""
    if config.option.basetemp is None:
        config.option.basetemp = tempfile.mkdtemp(prefix="airag-pytest-")
        return
    basetemp = Path(config.option.basetemp)
    if basetemp.exists() and any(basetemp.iterdir()):
        raise pytest.UsageError(
            f"--basetemp {basetemp} already exists and is not empty — refusing to reuse it "
            "(pytest's own retention policy would prune/reuse paths under it, which can "
            "delete previously retained evidence DBs). Pass a fresh, empty, or nonexistent "
            "--basetemp."
        )


@pytest.fixture
def key_bytes() -> bytes:
    return keys.generate_key()


@pytest.fixture
def key_fd_factory() -> Iterator[Callable[[bytes], int]]:
    """Yields a factory that writes `data` to a pipe and returns the read fd.

    The write end is closed immediately after writing (matches how a real
    caller would hand off a pre-opened fd), so the returned fd behaves like
    keys.read_key_from_fd expects: exactly KEY_LEN bytes then EOF.
    """
    created_read_fds: list[int] = []

    def _make(data: bytes) -> int:
        r, w = os.pipe()
        _ = os.write(w, data)
        os.close(w)
        created_read_fds.append(r)
        return r

    yield _make

    for fd in created_read_fds:
        try:
            os.close(fd)
        except OSError:
            pass
