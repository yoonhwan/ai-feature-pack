"""Reproducible bounded acceptance measurements; no production database input."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import resource
import statistics
import struct
import tempfile
import time
from pathlib import Path

from airag import api, embeddings, expansion, keys, profiles, search, store
from airag.db import connect


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def dump(path, result):
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def scale(plan, output):
    limits = plan["scale"]
    report = {"status": "running", "scope": limits["limits"], "provider": limits["provider"],
              "platform": platform.platform(), "python": platform.python_version(), "runs": []}
    dimension = limits["vector_dimension"]
    for count in limits["source_counts"]:
        workdir = Path(tempfile.mkdtemp(prefix="airag-scale-"))
        key = keys.generate_key()
        con = connect.init_db(workdir / "scale.db", key)
        cfg = embeddings.EmbeddingSpaceConfig(
            "openai-compatible", "http://localhost:1/v1", "synthetic-scale", "fixture-v1", dimension,
            tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3",
        )
        con.execute("BEGIN IMMEDIATE")
        space, profile = profiles.register_space_and_profile(con, cfg, {"adapter": "plain_text"})
        con.commit()
        embeddings.ensure_vec_space_table(con, space, dimension)
        vector = struct.pack(f"{dimension}f", 1, *([0] * (dimension - 1)))
        started = time.perf_counter()
        try:
            for index in range(count):
                text = f"Document {index}: bounded index benchmark original evidence."
                accepted = store.add(con, store.AddRequest(f"add-{index}", "scale", f"doc-{index}", text.encode()),
                                     profile_key=profile)
                rows = [{"text": f"{text} Paragraph {part}.", "token_count": 16,
                         "anchor": {"headings": [], "items": []}}
                        for part in range(limits["chunks_per_source"])]
                store.publish_generation_with_content(
                    con, accepted["generation_id"], standard_md=text, structured_json={},
                    chunk_rows=rows, space_id=space, vectors=[vector] * len(rows),
                )
                if (index + 1) % 100 == 0:
                    print(json.dumps({"sources": index + 1, "target": count, "stage": "publication"}), flush=True)
            publication_s = time.perf_counter() - started
            searches, expansions = [], []
            for index in range(limits["queries_per_size"]):
                query = search.SearchQuery("scale", f"Document {index}", f"Document {index}", vector,
                                           space, profile, top_k=5)
                started = time.perf_counter()
                result = search.search(con, query)
                searches.append(time.perf_counter() - started)
                started = time.perf_counter()
                expanded = expansion.expand(con, result["manifest_id"], expansion.ExpansionOptions(
                    max_depth=2, max_chunks=20, max_tokens=16000,
                ))
                expansions.append(time.perf_counter() - started)
                assert result["results"] and expanded["evidence"]["results"]
            con.execute("PRAGMA wal_checkpoint(PASSIVE)")
            rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            rss_mib = rss / (1024 * 1024 if platform.system() == "Darwin" else 1024)
            disk_mib = sum(p.stat().st_size for p in workdir.iterdir() if p.is_file()) / 1024 ** 2
            run = {"sources": count, "chunks": count * limits["chunks_per_source"], "dimension": dimension,
                   "publication_s": publication_s, "search_p50_s": statistics.median(searches),
                   "search_p95_s": percentile(searches, .95), "expansion_p95_s": percentile(expansions, .95),
                   "peak_process_rss_mib": rss_mib, "disk_mib": disk_mib,
                   "search_samples_s": searches, "expansion_samples_s": expansions,
                   "retained_workdir": str(workdir), "key_persisted": False}
            run["passed"] = (run["search_p95_s"] <= limits["search_p95_seconds_max"]
                             and run["expansion_p95_s"] <= limits["expansion_p95_seconds_max"]
                             and rss_mib <= limits["peak_rss_mib_max"]
                             and disk_mib <= limits["disk_mib_max_at_1000_sources"]
                             and publication_s <= limits["publication_seconds_max_at_1000_sources"])
            report["runs"].append(run)
            dump(output, report)
            print(json.dumps({k: v for k, v in run.items() if not isinstance(v, list)}), flush=True)
        finally:
            con.close()
    report["status"] = "passed" if all(r["passed"] for r in report["runs"]) else "failed"
    dump(output, report)
    return report["status"] == "passed"


def quality(plan, output, profile_path):
    config = json.loads(profile_path.read_text(encoding="utf-8"))
    workdir = Path(tempfile.mkdtemp(prefix="airag-quality-"))
    con = connect.init_db(workdir / "quality.db", keys.generate_key())
    report = {"status": "running", "provider": "actual configured embedding and LLM; no mocks",
              "config_sha256": hashlib.sha256(profile_path.read_bytes()).hexdigest(),
              "workdir": str(workdir), "key_persisted": False, "documents": [], "queries": []}
    try:
        registered = api.register_profile(con, config)
        if not registered["ok"]:
            raise RuntimeError(registered["error"]["code"])
        profile = registered["data"]["profile_key"]
        report["profile_key"] = profile
        for doc in plan["quality"]["documents"]:
            started = time.perf_counter()
            result = api.add(con, "quality-" + doc["key"], "quality", doc["key"], doc["text"].encode(), profile_key=profile)
            if not result["ok"]:
                raise RuntimeError(result["error"]["code"])
            artifact = api.fetch_artifact(con, "quality", doc["key"], generation_id=result["data"]["generation_id"])
            report["documents"].append({"key": doc["key"], "seconds": time.perf_counter() - started,
                                        "receipt": result["data"], "artifact": artifact["data"],
                                        "semantic_review": "pending"})
            dump(output, report)
            print(json.dumps({"stage": "quality-ingestion", "key": doc["key"]}), flush=True)
        for doc in plan["quality"]["documents"]:
            for query in doc["questions"]:
                started = time.perf_counter()
                result = api.search(con, "quality", query, profile, top_k=3)
                if not result["ok"]:
                    raise RuntimeError(result["error"]["code"])
                ranked = [r["source_key"] for r in result["data"]["results"]]
                report["queries"].append({"query": query, "expected": doc["key"], "ranked": ranked,
                                           "seconds": time.perf_counter() - started,
                                           "evidence": result["data"]})
                dump(output, report)
        queries = report["queries"]
        report["top_1"] = sum(bool(q["ranked"]) and q["ranked"][0] == q["expected"] for q in queries) / len(queries)
        report["top_3"] = sum(q["expected"] in q["ranked"][:3] for q in queries) / len(queries)
        report["retrieval_passed"] = (report["top_1"] >= plan["quality"]["top_1_minimum"]
                                       and report["top_3"] >= plan["quality"]["top_3_minimum"])
        report["status"] = "semantic_review_required" if report["retrieval_passed"] else "failed"
    except Exception as exc:
        report["status"] = "failed"
        report["error_type"] = type(exc).__name__
        raise
    finally:
        con.close()
        dump(output, report)
    return report.get("retrieval_passed", False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("scale", "quality"))
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile", type=Path)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    if args.output.exists():
        parser.error("output already exists; choose a new report path")
    if args.mode == "quality" and args.profile is None:
        parser.error("quality requires an explicit model profile")
    ok = scale(plan, args.output) if args.mode == "scale" else quality(plan, args.output, args.profile)
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
