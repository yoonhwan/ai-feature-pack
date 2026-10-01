"""Run from an independent wheel installation using an explicit live profile."""
from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.metadata
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import airag
from airag import api, keys
from airag.db import connect


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    assert Path(airag.__file__).resolve().is_relative_to(Path(sys.prefix).resolve()), airag.__file__
    assert not args.output.exists(), "use a fresh report path"
    db = Path.cwd() / "independent.db"
    key = keys.generate_key()
    report = {"status": "running", "python": sys.version, "prefix": sys.prefix,
              "module": airag.__file__, "cwd": str(Path.cwd()), "trace": [], "key_persisted": False,
              "packages": {d.metadata["Name"]: d.version for d in importlib.metadata.distributions()}}

    def save():
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def call(*argv, binary="ai-rag"):
        r, w = os.pipe()
        os.write(w, key)
        os.close(w)
        started = time.perf_counter()
        try:
            result = subprocess.run([str(Path(sys.executable).with_name(binary)), *argv, "--key-fd", str(r)],
                                    pass_fds=(r,), capture_output=True, text=True, timeout=240)
        finally:
            os.close(r)
        response = json.loads(result.stdout)
        report["trace"].append({"binary": binary, "command": list(argv), "exit_code": result.returncode,
                                "seconds": time.perf_counter() - started, "response": response})
        save()
        assert result.returncode == 0 and response["ok"], response
        print(json.dumps({"command": list(argv[:2]), "ok": True}), flush=True)
        return response

    try:
        call("init", str(db))
        profile = call("manage", "profile", "--db", str(db), "--config", str(args.profile))["data"]["profile_key"]
        original = "해솔도서관은 화요일부터 토요일까지 운영하며 책 5권을 14일 동안 빌릴 수 있다."
        added = call("add", "--db", str(db), "--collection", "installed", "--source-key", "library",
                     "--text", original, "--profile-key", profile, "--request-id", "add-library")
        found = call("search", "--db", str(db), "--collection", "installed", "--query", "책을 몇 권 며칠 빌리나요?",
                     "--profile-key", profile, binary="krb-rag")["data"]
        assert found["results"][0]["source_key"] == "library"
        fetched = call("fetch", "original", "--db", str(db), "--collection", "installed", "--source-key", "library", "--include-bytes")
        assert base64.b64decode(fetched["data"]["content_base64"]).decode() == original
        reindexed = call("manage", "reindex", "--db", str(db), "--collection", "installed", "--source-key", "library",
                         "--expected-revision", added["data"]["revision_token"], "--profile-key", profile,
                         "--request-id", "reindex-library")
        assert reindexed["data"]["revision_id"] == added["data"]["revision_id"]
        history = call("fetch", "manifest", "--db", str(db), "--manifest-id", str(found["manifest_id"]))
        assert history["data"]["results"] == found["results"]
        con = connect.open_encrypted(db, key)
        try:
            pending = api.add(con, "api-pending", "installed", "api-source", b"API source for independent consumer")
            assert pending["ok"], pending
            processed = api.retry(con, "api-process", pending["data"]["job_id"], profile_key=profile)
            assert processed["ok"], processed
            assert api.verify(con)["ok"]
            report["python_api"] = {"pending": pending, "processed": processed}
        finally:
            con.close()
        backup = Path.cwd() / "backup.db"
        restored = Path.cwd() / "restored.db"
        call("manage", "backup", "--db", str(db), "--output", str(backup))
        call("manage", "restore-backup", "--backup", str(backup), "--db", str(restored))
        call("manage", "verify", "--db", str(restored))
        call("manage", "doctor", "--db", str(restored))
        call("manage", "status", "--db", str(restored))
        restored_original = call("fetch", "original", "--db", str(restored), "--collection", "installed",
                                 "--source-key", "library", "--include-bytes", binary="krb-rag")
        for field in ("content_base64", "content_hash", "revision_id", "source_id", "media_type"):
            assert restored_original["data"][field] == fetched["data"][field]
        report["source_original_sha256"] = hashlib.sha256(original.encode()).hexdigest()
        report["status"] = "passed"
    except Exception as exc:
        report["status"] = "failed"
        report["error_type"] = type(exc).__name__
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
