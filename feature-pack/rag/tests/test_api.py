from __future__ import annotations

import uuid
from pathlib import Path

from airag import api
from airag.db import connect


def _rid() -> str:
    return str(uuid.uuid4())


def test_real_lock_contention_is_mapped_not_escaped(tmp_path: Path, key_bytes: bytes) -> None:
    """sqlcipher3 raises its OWN OperationalError class — NOT a subclass of
    stdlib sqlite3.OperationalError. A regression here must use two real
    sqlcipher3 connections to a real encrypted DB, not a hand-constructed
    stdlib exception standing in for it (p02-final-probes.txt item 1)."""
    db_path = tmp_path / "lock.db"
    con0 = connect.init_db(db_path, key_bytes)
    con0.close()

    holder = connect.open_encrypted(db_path, key_bytes)
    contender = connect.open_encrypted(db_path, key_bytes)
    # Keep the real 5s busy_timeout from a hanging this test — the
    # contention itself is what's under test, not how long it waits.
    _ = contender.execute("PRAGMA busy_timeout = 200")
    try:
        _ = holder.execute("BEGIN IMMEDIATE")
        _ = holder.execute(
            "INSERT INTO collections(name) VALUES ('docs')"
        )  # a real write, holding the write lock open

        env = api.add(contender, _rid(), "docs", "faq.md", b"content")
        assert env["ok"] is False, env
        assert env["error"]["code"] in ("DB_BUSY", "DB_OPERATIONAL_ERROR")
        assert "locked" in env["error"]["message"].lower() or "busy" in env["error"]["message"].lower()
        if env["error"]["code"] == "DB_BUSY":
            assert env["error"]["retryable"] is True
    finally:
        holder.rollback()
        holder.close()
        contender.close()

    # After the lock is released, a normal add succeeds cleanly.
    con_final = connect.open_encrypted(db_path, key_bytes)
    try:
        env2 = api.add(con_final, _rid(), "docs", "faq.md", b"content")
        assert env2["ok"] is True, env2
    finally:
        con_final.close()
