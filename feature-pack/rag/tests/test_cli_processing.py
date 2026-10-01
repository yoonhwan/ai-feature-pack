"""Installed CLI contract test using an explicitly synthetic HTTP provider.

This verifies transport, SQLCipher, profile, translation wiring and replay;
the fixture vectors/translation are not evidence of real model quality.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest


@pytest.fixture
def provider():
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            if self.path == "/tokenize":
                assert body["messages"] and body["add_generation_prompt"] is True
                result = {"count": 50}
            elif self.path == "/v1/embeddings":
                result = {"model": "fixture-embed", "data": [
                    {"index": i, "embedding": [1.0, 0.0, 0.0, 0.0]} for i, _ in enumerate(body["input"])
                ]}
            else:
                assert self.path == "/v1/chat/completions"
                prompt = body["messages"][0]["content"]
                units = [json.loads(line[line.index("{"):]) for line in prompt.splitlines() if '{"unit_id":' in line]
                if "Group them" in prompt:
                    content = [{"unit_ids": [u["unit_id"] for u in units], "group_summary": "Cat sleeping habits", "group_tags": ["cats"]}]
                else:
                    content = [{"unit_id": u["unit_id"], "tags": ["cats"], "summary": "Cat sleeping habits", "translation_en": "Cats sleep most of the day."} for u in units]
                result = {"model": "fixture-llm", "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(content)}}]}
            raw = json.dumps(result).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/v1"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_installed_cli_enriched_ingestion_search_historical_fetch_and_replay(tmp_path, key_bytes, provider):
    cli = str(Path(sys.executable).with_name("ai-rag"))
    db = tmp_path / "cli.db"
    def call(*args):
        r, w = os.pipe()
        os.write(w, key_bytes)
        os.close(w)
        try:
            result = subprocess.run([cli, *args, "--key-fd", str(r)], pass_fds=(r,), cwd=tmp_path, capture_output=True, text=True, timeout=30)
        finally:
            os.close(r)
        assert result.stdout, result.stderr
        env = json.loads(result.stdout)
        assert result.returncode == 0 and env["ok"], json.dumps(env, ensure_ascii=False)
        return env

    call("init", str(db))
    config = tmp_path / "profile.json"
    config.write_text(json.dumps({
        "embedding": {"provider": "openai-compatible", "endpoint": provider, "model": "fixture-embed", "revision": "fixture-embed-v1", "dimension": 4, "tokenizer_revision": "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"},
        "llm": {"provider": "byz-vllm", "endpoint": provider, "model": "fixture-llm", "weights_revision": "fixture-llm-v1", "context_length": 24576},
    }), encoding="utf-8")
    profile = call("manage", "profile", "--db", str(db), "--config", str(config))["data"]["profile_key"]
    args = ("add", "--db", str(db), "--collection", "docs", "--source-key", "cats", "--text", "고양이는 하루의 대부분을 잠으로 보낸다.", "--profile-key", profile, "--request-id", "add-cats")
    added = call(*args)
    assert added["data"]["searchable"]
    assert call(*args) == added
    found = call("search", "--db", str(db), "--collection", "docs", "--query", "고양이 수면 습관", "--profile-key", profile)["data"]
    assert found["original_query"] == "고양이 수면 습관"
    assert found["search_query_text"] == "Cats sleep most of the day."
    evidence = found["results"][0]
    assert "고양이" in evidence["original_text"]
    assert evidence["embedded_text"] == "Cats sleep most of the day."
    source = call("fetch", "source", "--db", str(db), "--collection", "docs", "--source-key", "cats", "--generation-id", str(evidence["generation_id"]))
    assert "고양이" in source["data"]["standard_md"]
    chunk = call("fetch", "chunk", "--db", str(db), "--collection", "docs", "--source-key", "cats", "--chunk-id", str(evidence["chunk_id"]))
    assert chunk["data"]["embedded_text"] == evidence["embedded_text"]
    deleted = call("delete", "--db", str(db), "--collection", "docs", "--source-key", "cats", "--request-id", "delete-cats", "--expected-revision", added["data"]["revision_token"])
    replay = call("fetch", "manifest", "--db", str(db), "--manifest-id", str(found["manifest_id"]))["data"]
    assert replay["historical"] is True
    assert replay["results"] == found["results"]
    fresh = call("search", "--db", str(db), "--collection", "docs", "--query", "고양이", "--profile-key", profile)["data"]
    assert fresh["results"] == []
    call("manage", "restore", "--db", str(db), "--collection", "docs", "--source-key", "cats", "--request-id", "restore-cats", "--expected-revision", deleted["data"]["revision_token"])
    restored = call("search", "--db", str(db), "--collection", "docs", "--query", "고양이", "--profile-key", profile)["data"]
    assert restored["results"][0]["chunk_id"] == evidence["chunk_id"]
