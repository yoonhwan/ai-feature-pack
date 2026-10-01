from __future__ import annotations

import os
from collections.abc import Callable

import pytest

from airag import keys


def test_generate_key_length() -> None:
    assert len(keys.generate_key()) == keys.KEY_LEN


def test_generate_key_random() -> None:
    assert keys.generate_key() != keys.generate_key()


def test_read_key_from_fd_exact(key_fd_factory: Callable[[bytes], int]) -> None:
    data = os.urandom(32)
    fd = key_fd_factory(data)
    assert keys.read_key_from_fd(fd) == data


def test_read_key_from_fd_short_raises(key_fd_factory: Callable[[bytes], int]) -> None:
    fd = key_fd_factory(os.urandom(10))
    with pytest.raises(ValueError, match="expected 32 bytes"):
        _ = keys.read_key_from_fd(fd)


def test_read_key_from_fd_does_not_overread_trailing_bytes(
    key_fd_factory: Callable[[bytes], int],
) -> None:
    """A buffered reader could pull the whole pipe (key + trailer) into an
    internal buffer on one read() and silently drop the trailer when
    discarded. read_key_from_fd must consume exactly KEY_LEN bytes and leave
    the rest on the fd for the caller."""
    key = os.urandom(32)
    trailer = b"EXTRA-DATA-AFTER-THE-KEY"
    fd = key_fd_factory(key + trailer)

    got = keys.read_key_from_fd(fd)
    assert got == key

    rest = os.read(fd, len(trailer))
    assert rest == trailer


def test_keychain_unavailable_in_phase1() -> None:
    assert keys.keychain_available() is False
    with pytest.raises(keys.KeychainUnavailable):
        _ = keys.read_key_from_keychain("airag", "test")
