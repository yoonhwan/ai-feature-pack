"""Real-provider mixed-format lifecycle through the installed CLI."""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from test_documents_live import case
from airag.normalize import CONVERSATION_MEDIA_TYPE


@pytest.mark.integration
@pytest.mark.parametrize("kind", ["pdf", "docx", "xlsx", "hwp", "hwpx", "ocr", "vision", "empty", "long", "ko", "en", "conversation"])
def test_installed_cli_full_format_state_lifecycle(kind, tmp_path, key_bytes):
    revision = os.environ.get("AIRAG_EMBED_REVISION")
    if not revision:
        pytest.skip("explicit actual-provider profile revision required")
    if kind in {"pdf", "docx", "xlsx", "hwp", "hwpx", "ocr", "vision"}:
        media, content, normalizer, query, _ = case(kind)
    else:
        normalizer = None
        media = CONVERSATION_MEDIA_TYPE if kind == "conversation" else "text/plain"
        content = {
            "empty": b"",
            "long": ("Coffee inventory tracks forty-two bags of beans. " * 45).encode(),
            "ko": "커피 원두 재고는 42봉지이다. 차 잎 재고는 17봉지이다.".encode(),
            "en": b"Coffee inventory is forty-two bags. Tea inventory is seventeen bags.",
            "conversation": json.dumps({"turns": [{"role": "user", "text": "커피 재고가 얼마인가요?"},
                                                    {"role": "assistant", "text": "커피 원두는 42봉지입니다."}]}, ensure_ascii=False).encode(),
        }[kind]
        query = "coffee inventory"
    cli = str(Path(sys.executable).with_name("ai-rag"))
    db = tmp_path / "lifecycle.db"
    source = tmp_path / "source-input"
    source.write_bytes(content)
    trace = []

    def call(*args):
        r, w = os.pipe()
        os.write(w, key_bytes)
        os.close(w)
        try:
            process = subprocess.run([cli, *args, "--key-fd", str(r)], pass_fds=(r,), cwd=tmp_path,
                                     capture_output=True, text=True, timeout=240)
        finally:
            os.close(r)
        result = json.loads(process.stdout)
        trace.append({"command": list(args), "exit_code": process.returncode, "response": result})
        assert process.returncode == 0 and result["ok"], result
        return result

    report = {"kind": kind, "status": "running", "provider": "actual BYZ GPU", "trace": trace}
    try:
        call("init", str(db))
        config = {
            "embedding": {"provider": "openai-compatible", "endpoint": os.environ["AIRAG_EMBED_ENDPOINT"],
                          "model": "byz-embed", "revision": revision, "dimension": 1024,
                          "tokenizer_revision": "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3", "timeout_s": 90},
            "llm": {"provider": "byz-vllm", "endpoint": os.environ["AIRAG_LLM_ENDPOINT"], "model": "byz-llm",
                    "weights_revision": os.environ["AIRAG_LLM_REVISION"], "context_length": 24576, "timeout_s": 120},
        }
        if normalizer is not None:
            config["normalizer"] = normalizer
        config_path = tmp_path / "profile.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        profile = call("manage", "profile", "--db", str(db), "--config", str(config_path))["data"]["profile_key"]
        add_args = ("add", "--db", str(db), "--collection", "lifecycle", "--source-key", kind,
                    "--content-file", str(source), "--media-type", media, "--profile-key", profile,
                    "--request-id", "add")
        added = call(*add_args)
        assert call(*add_args) == added
        original = call("fetch", "original", "--db", str(db), "--collection", "lifecycle",
                        "--source-key", kind, "--include-bytes")
        assert base64.b64decode(original["data"]["content_base64"]) == content
        found = None
        if kind != "empty":
            found = call("search", "--db", str(db), "--collection", "lifecycle", "--query", query,
                         "--profile-key", profile, "--expand", "--max-tokens", "64000")["data"]
            assert found["results"] and found["results"][0]["anchor"]
            assert found["expansion"]["evidence"]["results"]
        else:
            assert added["data"]["processing_status"] == "ready_empty"
        unchanged = call("update", "--db", str(db), "--collection", "lifecycle", "--source-key", kind,
                         "--content-file", str(source), "--media-type", media, "--profile-key", profile,
                         "--expected-revision", added["data"]["revision_token"], "--request-id", "noop-update")
        assert unchanged["data"]["no_op"]
        deleted = call("delete", "--db", str(db), "--collection", "lifecycle", "--source-key", kind,
                       "--expected-revision", unchanged["data"]["revision_token"], "--request-id", "delete")
        hidden = call("search", "--db", str(db), "--collection", "lifecycle", "--query", query,
                      "--profile-key", profile)["data"]
        assert hidden["results"] == []
        if found:
            historical = call("fetch", "manifest", "--db", str(db), "--manifest-id", str(found["manifest_id"]))
            assert historical["data"]["results"] == found["results"]
        call("manage", "restore", "--db", str(db), "--collection", "lifecycle", "--source-key", kind,
             "--expected-revision", deleted["data"]["revision_token"], "--request-id", "restore")
        call("manage", "verify", "--db", str(db))
        assert call(*add_args) == added
        report["status"] = "passed"
    finally:
        (tmp_path / "lifecycle-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
