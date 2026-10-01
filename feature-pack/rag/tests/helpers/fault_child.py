"""Fault injection in a real disposable test process; encryption keys use a pipe."""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys
from unittest.mock import patch

from airag import api, backups, keys, pipeline
from airag.db import connect


def invoke(con, event):
    common = (con, event["request_id"])
    command = event["command"]
    if command == "retry":
        return api.retry(*common, event["job_id"])
    if command == "delete":
        return api.delete(*common, "docs", event["source_key"], event["token"])
    if command == "reindex":
        return api.reindex(*common, "docs", event["source_key"], event["token"], profile_key=event["profile"])
    if command == "update":
        return api.update(*common, "docs", event["source_key"], event["token"], event["content"].encode())
    return api.add(*common, "docs", event["source_key"], event["content"].encode(), profile_key=event["profile"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--key-fd", required=True, type=int)
    parser.add_argument("--barrier-fd", type=int)
    args = parser.parse_args()
    key = keys.read_key_from_fd(args.key_fd)
    os.close(args.key_fd)
    event = json.loads(sys.stdin.buffer.read())
    if event["phase"] == "backup_before_publish":
        real_verify = backups._verified_counts
        calls = 0

        def crash_verification(con):
            nonlocal calls
            calls += 1
            if calls == 2:
                os._exit(74)
            return real_verify(con)

        with patch("airag.backups._verified_counts", side_effect=crash_verification):
            api.backup_database(args.db, event["target"], key)
        raise AssertionError("backup fault point was not reached")

    con = connect.open_encrypted(args.db, key)
    if args.barrier_fd is not None:
        print("READY", flush=True)
        if os.read(args.barrier_fd, 1) != b"G":
            raise AssertionError("parent did not release the barrier")
        os.close(args.barrier_fd)
    real_process = pipeline.process_and_publish

    def process(*args, **kwargs):
        if event["phase"] == "staged":
            os._exit(71)
        result = real_process(*args, **kwargs)
        if event["phase"] == "response_lost":
            os._exit(72)
        return result

    if event["phase"] == "mid_publish":
        def trace(sql):
            if sql.startswith("UPDATE sources SET ready_generation_id"):
                # SQLite invokes the trace callback before executing this
                # statement, after the earlier transactional FTS/vec inserts.
                os._exit(73)
        con.set_trace_callback(trace)

    def vectors(cfg, texts, **kwargs):
        return [struct.pack(f"{cfg.dimension}f", 1, *([0] * (cfg.dimension - 1))) for _ in texts]

    with patch("airag.pipeline.process_and_publish", side_effect=process), \
         patch("airag.embeddings.embed_documents", side_effect=vectors):
        result = invoke(con, event)
    con.close()
    if event["phase"] != "none":
        raise AssertionError("mutation fault point was not reached")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
