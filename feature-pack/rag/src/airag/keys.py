"""Key-provider boundary (design §4.2). Never accept/emit key bytes via argv or logs."""

from __future__ import annotations

import os

KEY_LEN = 32


def generate_key() -> bytes:
    return os.urandom(KEY_LEN)


def read_key_from_fd(fd: int) -> bytes:
    """Read exactly KEY_LEN raw bytes from an already-open file descriptor.

    For automation/tests only. Caller owns the fd's lifecycle (this does not
    close it); the key never touches argv, env dumps, or log output.

    Uses bounded raw os.read() calls rather than a buffered fdopen() wrapper:
    a buffered reader's underlying read may pull more than KEY_LEN bytes off
    the fd into its internal buffer in one syscall, and those extra bytes
    are lost when that temporary wrapper is discarded — silently consuming
    data the caller placed on the fd after the key.
    """
    data = b""
    while len(data) < KEY_LEN:
        chunk = os.read(fd, KEY_LEN - len(data))
        if not chunk:
            break
        data += chunk
    if len(data) != KEY_LEN:
        raise ValueError(f"expected {KEY_LEN} bytes from fd {fd}, got {len(data)}")
    return data


class KeychainUnavailable(Exception):
    """macOS Keychain key provider is not implemented in phase 1."""


def keychain_available() -> bool:
    return False


def read_key_from_keychain(service: str, account: str) -> bytes:
    _ = (service, account)  # accepted for the future real provider's signature
    raise KeychainUnavailable(
        "macOS Keychain key provider is not implemented in phase 1 — use --key-fd"
    )
