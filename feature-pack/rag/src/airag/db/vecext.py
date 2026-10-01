"""sqlite-vec (vec0) extension loading — load only while required, then disable.

Best-effort: ImportError or a load failure returns False rather than raising,
so callers (doctor/tests) can report vec0 unavailable instead of crashing.
"""

from __future__ import annotations

import sqlite3


def try_load_vec0(con: sqlite3.Connection) -> bool:
    # Re-registering an already loaded extension can fail while the
    # connection has active statements. Reuse its existing registration.
    try:
        cursor = con.execute("SELECT vec_version()")
        try:
            if cursor.fetchone():
                con.enable_load_extension(False)
                return True
        finally:
            cursor.close()
    except Exception:
        pass
    try:
        import sqlite_vec
    except ImportError:
        return False
    try:
        con.enable_load_extension(True)
        sqlite_vec.load(con)
    except Exception:
        return False
    finally:
        con.enable_load_extension(False)
    return True


def vec_version(con: sqlite3.Connection) -> str | None:
    if not try_load_vec0(con):
        return None
    row = con.execute("SELECT vec_version()").fetchone()
    return row[0] if row else None
