"""Shared, bounded local-file reading for CLI/batch content input
(p02-cli-review.txt item 4). Used by both the single-item CLI path
(--content-file) and the batch item path (content_file) so the guarantees
are identical either way:

- the size guard applies DURING the read (reads at most limit+1 bytes),
  never after an unbounded read_bytes() call — a caller pointing at a
  multi-GB file must not make this process try to load it all into memory
  before rejecting it.
- only a regular file is read; a directory or a FIFO/socket/device is
  refused up front (Path.is_file() follows symlinks and is False for all
  of those) — opening a FIFO with no writer can block this process
  indefinitely, so it must never be attempted.
- a single read: the file is captured exactly once, never re-read to,
  say, separately compute a hash and then store the bytes.
"""

from __future__ import annotations

import mimetypes
from pathlib import Path

_KNOWN_UTF8_TEXT_EXTENSIONS = {".md", ".txt", ".markdown"}


def read_bounded_regular_file(path_str: str, limit: int) -> bytes:
    p = Path(path_str)
    if not p.is_file():
        raise OSError(f"{p} is not a regular file")
    with p.open("rb") as fh:
        data = fh.read(limit + 1)
    if len(data) > limit:
        raise OSError(f"{p} exceeds the {limit}-byte content guard")
    return data


def guess_media_type(path_str: str) -> str:
    """Infers a media type from a file's extension via the standard
    mimetypes mapping. Falls back to application/octet-stream (never
    text/plain) for anything unrecognized — defaulting an unknown/binary
    file to text/plain would force a UTF-8 validation that has no reason to
    pass (p02-cli-review.txt item 4)."""
    p = Path(path_str)
    if p.suffix.lower() in {".hwp", ".hwpx"}:
        return "application/x-hwp" if p.suffix.lower() == ".hwp" else "application/hwp+zip"
    if p.suffix.lower() in _KNOWN_UTF8_TEXT_EXTENSIONS:
        return "text/markdown" if p.suffix.lower() in (".md", ".markdown") else "text/plain"
    guessed, _ = mimetypes.guess_type(path_str)
    return guessed or "application/octet-stream"


def default_origin_uri(path_str: str) -> str:
    return Path(path_str).resolve().as_uri()
