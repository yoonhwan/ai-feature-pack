"""P03-A reproduction script: sqlite-vec pre-filter (metadata columns applied
BEFORE the k-limit) probe on a REAL disposable SQLCipher-encrypted DB opened
through airag.db.connect.init_db. Standalone, package source unchanged.

This DB is intentionally NOT deleted after the run (2026-09-09 correction
from ft-airag-arch-astra: keep reproduction evidence, do not clean up mid
review) — every run creates a fresh unique path under a mkdtemp() directory
and the script prints/records that path. The encryption key is a FIXED
constant (not randomly generated per run) purely so this throwaway synthetic
probe DB stays openable with the same key printed here; it is not a real
user key and holds no real content (D-001's key-secrecy invariant is about
production keys, not this disposable synthetic probe).

Run with: .venv/bin/python docs/artifacts/p03a-vec-probe.py (from feature-pack/rag/,
using the package's own venv where `airag` is installed — no sys.path hack).
"""
import json
import math
import os
import tempfile

from airag.db import connect

FIXED_PROBE_KEY_HEX = "b03a" * 16  # 32 bytes, fixed — synthetic probe DB only, see module docstring
DIM = 8


def unit_vec(seed_idx, dim=DIM):
    v = [0.0] * dim
    v[seed_idx % dim] = 1.0
    return v


# Exact literal vectors used (noise pre-baked in, not re-derived from a live
# RNG call at read time) so this file alone reproduces the run byte-for-byte
# regardless of Python/random-module version drift.
NOISE_A = [0.0146, -0.0078, 0.0031, -0.0112, 0.0087, -0.0054, 0.0163, -0.0021]
NOISE_A2 = [-0.0033, 0.0091, -0.0145, 0.0062, -0.0177, 0.0104, -0.0018, 0.0139]
NOISE_A3 = [0.0122, -0.0166, 0.0057, -0.0089, 0.0014, 0.0178, -0.0102, 0.0045]
NOISE_B = [-0.0142, 0.0119, -0.0067, 0.0155, -0.0033, 0.0088, -0.0176, 0.0021]
NOISE_B2 = [0.0164, -0.0091, 0.0128, -0.0055, 0.0173, -0.0119, 0.0042, -0.0187]
NOISE_B3 = [-0.0108, 0.0173, -0.0044, 0.0091, -0.0159, 0.0026, 0.0137, -0.0083]
NOISE_A_TINY = [0.0031, -0.0018, 0.0009, -0.0027, 0.0021, -0.0013, 0.0038, -0.0005]


def add(base, noise):
    return [b + n for b, n in zip(base, noise)]


baseA = unit_vec(0)
baseB = unit_vec(1)

ROWS = [
    (100, add(baseA, NOISE_A), "colA", 1),
    (101, add(baseA, NOISE_A2), "colA", 1),
    (102, add(baseA, NOISE_A3), "colA", 1),
    (199, unit_vec(0), "colA", 0),  # inactive distractor, EXACTLY at query vector
    (200, add(baseB, NOISE_B), "colB", 1),
    (201, add(baseB, NOISE_B2), "colB", 1),
    (202, add(baseB, NOISE_B3), "colB", 1),
    (299, add(baseA, NOISE_A_TINY), "colB", 0),  # inactive cross-collection distractor
]

QUERY = unit_vec(0)


def cosine_dist(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return 1.0 - dot / (na * nb)


if __name__ == "__main__":
    key = bytes.fromhex(FIXED_PROBE_KEY_HEX)
    tmp_dir = tempfile.mkdtemp(prefix="airag-p03a-vec-probe-")
    db_path = os.path.join(tmp_dir, "probe.db")

    con = connect.init_db(db_path, key)
    con.enable_load_extension(True)
    import sqlite_vec
    sqlite_vec.load(con)
    con.enable_load_extension(False)

    from airag.db import vecext
    ver = vecext.vec_version(con)
    print("vec0 version:", ver, "cipher_version:", connect.cipher_version(con))

    con.execute("""
    CREATE VIRTUAL TABLE probe_vec0 USING vec0(
        embedding_id INTEGER PRIMARY KEY,
        embedding FLOAT[8] distance_metric=cosine,
        collection TEXT,
        active INTEGER
    )
    """)
    for rid, vec, coll, active in ROWS:
        con.execute(
            "INSERT INTO probe_vec0(embedding_id, embedding, collection, active) VALUES (?, ?, ?, ?)",
            (rid, json.dumps(vec), coll, active),
        )
    con.commit()

    unfiltered = con.execute(
        "SELECT embedding_id, collection, active, distance FROM probe_vec0 "
        "WHERE embedding MATCH ? AND k = 4 ORDER BY distance",
        (json.dumps(QUERY),),
    ).fetchall()
    print("\nUNFILTERED top-4:")
    for r in unfiltered:
        print("  ", r)

    filtered = con.execute(
        "SELECT embedding_id, collection, active, distance FROM probe_vec0 "
        "WHERE embedding MATCH ? AND k = 4 AND collection = 'colA' AND active = 1 "
        "ORDER BY distance",
        (json.dumps(QUERY),),
    ).fetchall()
    print("\nFILTERED (collection='colA' AND active=1) top-4:")
    for r in filtered:
        print("  ", r)

    filtered_ids = {r[0] for r in filtered}
    unfiltered_ids = {r[0] for r in unfiltered}

    try:
        con.execute(
            "SELECT embedding_id FROM probe_vec0 WHERE embedding MATCH ? AND k = 4 AND collection IN ('colA','colB')",
            (json.dumps(QUERY),),
        ).fetchall()
        in_op_supported = True
        op_error = None
    except Exception as exc:
        in_op_supported = False
        op_error = str(exc)

    manual_check = [
        {"id": rid, "manual_cosine_dist_to_query": round(cosine_dist(QUERY, vec), 6)}
        for rid, vec, coll, active in ROWS
    ]

    result = {
        "db_path_RETAINED_NOT_DELETED": db_path,
        "db_key_hex_FIXED_SYNTHETIC_ONLY": FIXED_PROBE_KEY_HEX,
        "distance_metric": "cosine",
        "sqlite_vec_version": ver,
        "cipher_version": connect.cipher_version(con),
        "dim": DIM,
        "literal_rows": [
            {"id": rid, "vector": vec, "collection": coll, "active": active} for rid, vec, coll, active in ROWS
        ],
        "literal_query_vector": QUERY,
        "manual_cosine_cross_check": manual_check,
        "unfiltered_topk": [{"id": r[0], "collection": r[1], "active": r[2], "distance": r[3]} for r in unfiltered],
        "filtered_topk": [{"id": r[0], "collection": r[1], "active": r[2], "distance": r[3]} for r in filtered],
        "distractor_would_win_without_filter": 199 in unfiltered_ids,
        "distractor_correctly_excluded_with_filter": 199 not in filtered_ids,
        "filtered_rows_all_colA_active": all(r[1] == "colA" and r[2] == 1 for r in filtered),
        "filtered_count_matches_eligible_rows": len(filtered) == 3,
        "metadata_column_IN_operator_supported": in_op_supported,
        "metadata_column_IN_operator_error": op_error,
    }
    with open(os.path.join(tmp_dir, "p03a-vec-probe.out.json"), "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    con.close()
    print("\nWROTE", os.path.join(tmp_dir, "p03a-vec-probe.out.json"))
    print("DB RETAINED (not deleted) at:", db_path)
