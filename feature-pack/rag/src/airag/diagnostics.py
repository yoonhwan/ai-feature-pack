"""Read-only operational inspection. Provider connectivity is never probed."""

from __future__ import annotations

import json
import re
import time
from collections import Counter

from airag import embeddings, profiles
from airag.db import vecext


def _profile_id(value):
    return value if isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) else None


def inspect_runtime() -> dict[str, object]:
    from airag import keys
    from airag.db import connect
    import sqlcipher3
    data = {"scope": "runtime", "read_only": True, "database_checked": False,
            "provider_connectivity": "not_checked", "sqlcipher": {"available": False},
            "fts5": {"available": False}, "vec0": {"available": False},
            "key_providers": {"key_fd": True, "macos_keychain": keys.keychain_available()}}
    con = None
    try:
        con = sqlcipher3.connect(":memory:")
        connect._apply_raw_key(con, keys.generate_key())
        version = connect.cipher_version(con)
        data["sqlcipher"] = {"available": bool(version), "cipher_version": version,
                             "sqlite_version": sqlcipher3.sqlite_version}
        con.execute("CREATE VIRTUAL TABLE runtime_fts_probe USING fts5(x)")
        data["fts5"]["available"] = True
        data["vec0"]["available"] = vecext.try_load_vec0(con)
        if data["vec0"]["available"]:
            data["vec0"]["version"] = vecext.vec_version(con)
    except Exception:
        data["error_code"] = "RUNTIME_PROBE_FAILED"
    finally:
        if con is not None:
            con.close()
    data["healthy"] = all(data[k]["available"] for k in ("sqlcipher", "fts5", "vec0"))
    return data


def inspect_database(con) -> dict[str, object]:
    vec_available = vecext.try_load_vec0(con)
    owns_snapshot = not con.in_transaction
    if owns_snapshot:
        con.execute("BEGIN")
    try:
        return _inspect_snapshot(con, vec_available)
    finally:
        if owns_snapshot:
            con.rollback()


def _inspect_snapshot(con, vec_available: bool) -> dict[str, object]:
    checks = []

    def check(code, count):
        checks.append({"code": code, "ok": count == 0, "count": count})

    now = int(time.time() * 1000)
    job_items = []
    counts = dict.fromkeys(("pending", "running", "failed", "done"), 0)
    for row in con.execute(
        "SELECT j.job_id,j.source_id,j.revision_id,j.generation_id,j.profile_key,j.status,"
        "j.lease_expires_at_ms,j.expected_state_version,s.state_version,s.deleted_at_ms,"
        "j.error IS NOT NULL FROM jobs j LEFT JOIN sources s ON s.source_id=j.source_id ORDER BY j.job_id"
    ):
        job_id, source_id, revision_id, generation_id, profile_key, status, lease, expected, state, deleted, error = row
        counts[status] = counts.get(status, 0) + 1
        if status == "done":
            continue
        job_items.append({"job_id": job_id, "source_id": source_id, "revision_id": revision_id,
                          "generation_id": generation_id, "profile_key": _profile_id(profile_key), "status": status,
                          "lease_expired": status == "running" and (lease is None or lease <= now),
                          "obsolete": state is None or expected != state or deleted is not None,
                          "error_present": bool(error)})

    profile_items = []
    for profile_key, space_id, normalizer_json, chunker_json in con.execute(
        "SELECT profile_key,space_id,normalizer_config,chunker_config FROM processing_profiles ORDER BY profile_key"
    ):
        item = {"profile_key": _profile_id(profile_key), "space_id": space_id, "valid": False,
                "embedding": {"endpoint_configured": False}, "llm": {"configured": False, "valid": True}}
        try:
            chunker = json.loads(chunker_json)
            item["llm"]["configured"] = "llm_enrichment" in chunker
            cfg, normalizer = profiles.config_from_profile(con, profile_key)
            embeddings.validate_config(cfg)
            stored_space = con.execute("SELECT fingerprint FROM embedding_spaces WHERE space_id=?", (space_id,)).fetchone()
            if stored_space != (embeddings.fingerprint_space(cfg),):
                raise ValueError("embedding space identity mismatch")
            if not isinstance(normalizer, dict):
                raise ValueError("invalid normalizer")
            if profiles.fingerprint_profile(space_id, json.loads(normalizer_json), chunker) != profile_key:
                raise ValueError("profile identity mismatch")
            profiles.llm_from_profile(con, profile_key)
            item["embedding"] = {"provider": cfg.provider, "model": cfg.model, "revision": cfg.revision,
                                 "dimension": cfg.dimension, "endpoint_configured": bool(cfg.endpoint)}
            item["valid"] = True
        except Exception:
            # Exception text may include endpoint credentials, provider bodies,
            # or malformed configuration values. Only categorical status escapes.
            item["llm"]["valid"] = not item["llm"]["configured"]
        profile_items.append(item)
    check("PROFILE_CONFIGURATION_INVALID", sum(not p["valid"] for p in profile_items))

    def count(sql):
        return con.execute(sql).fetchone()[0]

    check("HEAD_POINTER_MISMATCH", count(
        "SELECT COUNT(*) FROM sources s LEFT JOIN source_revisions r ON r.revision_id=s.head_revision_id "
        "WHERE s.head_revision_id IS NOT NULL AND (r.revision_id IS NULL OR r.source_id!=s.source_id)"))
    check("READY_POINTER_MISMATCH", count(
        "SELECT COUNT(*) FROM sources s LEFT JOIN generations g ON g.generation_id=s.ready_generation_id "
        "LEFT JOIN source_revisions r ON r.revision_id=g.revision_id "
        "WHERE s.ready_generation_id IS NOT NULL AND "
        "(g.generation_id IS NULL OR g.status!='ready' OR r.source_id IS NULL OR r.source_id!=s.source_id)"))
    check("GENERATION_PROFILE_MISSING", count(
        "SELECT COUNT(*) FROM generations g LEFT JOIN processing_profiles p ON p.profile_key=g.profile_key "
        "WHERE p.profile_key IS NULL"))
    check("JOB_PROFILE_MISSING", count(
        "SELECT COUNT(*) FROM jobs j LEFT JOIN processing_profiles p ON p.profile_key=j.profile_key "
        "WHERE j.profile_key IS NOT NULL AND p.profile_key IS NULL"))

    # The previous ready generation may legitimately predate head_revision_id
    # while an update is pending/failed. Only its ownership/status matter here.
    ready_sql = (
        "SELECT c.chunk_id,s.source_id,s.collection_id,c.generation_id,c.text,p.space_id "
        "FROM sources s JOIN generations g ON g.generation_id=s.ready_generation_id "
        "JOIN source_revisions r ON r.revision_id=g.revision_id AND r.source_id=s.source_id "
        "JOIN chunks c ON c.generation_id=g.generation_id "
        "LEFT JOIN processing_profiles p ON p.profile_key=g.profile_key "
        "WHERE s.deleted_at_ms IS NULL AND g.status='ready'"
    )
    ready = con.execute(ready_sql).fetchall()
    expected_fts = Counter((r[0], r[1], r[2], r[4]) for r in ready)
    try:
        actual_fts = Counter(con.execute("SELECT chunk_id,source_id,collection_id,text FROM fts_chunks").fetchall())
        check("FTS_MISSING_ROWS", sum((expected_fts - actual_fts).values()))
        check("FTS_UNEXPECTED_ROWS", sum((actual_fts - expected_fts).values()))
    except Exception:
        check("FTS_UNREADABLE", 1)

    check("VEC0_UNAVAILABLE", int(not vec_available))
    if vec_available:
        for space_id, dimension in con.execute("SELECT space_id,dimension FROM embedding_spaces ORDER BY space_id"):
            table = embeddings.vec_space_table_name(space_id)
            expected = Counter((r[0], r[1], r[2], r[3]) for r in ready if r[5] == space_id)
            exists = con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone()
            if not exists:
                # Vec tables are lazy; an unused registered profile needs none.
                check("VEC_MISSING_ROWS", sum(expected.values()))
                continue
            try:
                actual = Counter(con.execute(
                    f"SELECT chunk_id,source_id,collection_id,generation_id FROM {table} WHERE active=1"
                ).fetchall())
                check("VEC_MISSING_ROWS", sum((expected - actual).values()))
                check("VEC_UNEXPECTED_ROWS", sum((actual - expected).values()))
                invalid = count(
                    f"SELECT COUNT(*) FROM {table} v LEFT JOIN chunks c ON c.chunk_id=v.chunk_id "
                    "LEFT JOIN generations g ON g.generation_id=c.generation_id "
                    "LEFT JOIN source_revisions r ON r.revision_id=g.revision_id "
                    "LEFT JOIN sources s ON s.source_id=r.source_id "
                    "LEFT JOIN processing_profiles p ON p.profile_key=g.profile_key "
                    f"WHERE c.chunk_id IS NULL OR v.generation_id!=c.generation_id OR v.source_id!=s.source_id "
                    f"OR v.collection_id!=s.collection_id OR p.space_id IS NULL OR p.space_id!={int(space_id)} "
                    "OR v.active NOT IN (0,1)")
                check("VEC_ROW_IDENTITY_MISMATCH", invalid)
                check("VEC_DIMENSION_MISMATCH", con.execute(
                    f"SELECT COUNT(*) FROM {table} WHERE vec_length(embedding)!=?", (dimension,)
                ).fetchone()[0])
            except Exception:
                check("VEC_UNREADABLE", 1)
    try:
        check("DATABASE_INTEGRITY_FAILED", int(con.execute("PRAGMA quick_check").fetchall() != [("ok",)]))
        check("FOREIGN_KEY_MISMATCH", len(con.execute("PRAGMA foreign_key_check").fetchall()))
    except Exception:
        check("DATABASE_INTEGRITY_UNREADABLE", 1)
    issues = [{"code": c["code"], "count": c["count"]} for c in checks if not c["ok"]]
    return {"scope": "database", "read_only": True, "provider_connectivity": "not_checked",
            "healthy": not issues, "jobs": {**counts, "items": job_items},
            "profiles": profile_items, "checks": checks, "issues": issues}
