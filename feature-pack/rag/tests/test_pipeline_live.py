"""Opt-in real BYZ GPU ingestion/search roundtrip; no mocked model calls.

Set AIRAG_EMBED_REVISION to the operator's declared model revision. This
value is an assertion, not automatic attestation of served model weights.
Endpoint overrides permit using the operator's current IAP tunnel ports.
"""
from __future__ import annotations

import os

import pytest

from airag import api
from airag.db import connect


@pytest.mark.integration
def test_live_gpu_enrichment_embedding_search_and_manifest(tmp_path, key_bytes):
    revision = os.environ.get("AIRAG_EMBED_REVISION")
    if not revision:
        pytest.skip("set AIRAG_EMBED_REVISION to an explicit operator-declared revision")
    con = connect.init_db(tmp_path / "live-gpu.db", key_bytes)
    try:
        registered = api.register_profile(con, {
            "embedding": {
                "provider": "openai-compatible", "endpoint": os.environ.get("AIRAG_EMBED_ENDPOINT", "http://127.0.0.1:18810/v1"),
                "model": os.environ.get("AIRAG_EMBED_MODEL", "byz-embed"), "revision": revision, "dimension": 1024,
                "tokenizer_revision": "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3", "max_tokens": 8192, "timeout_s": 60,
            },
            "llm": {
                "provider": "byz-vllm", "endpoint": os.environ.get("AIRAG_LLM_ENDPOINT", "http://localhost:8002/v1"),
                "model": os.environ.get("AIRAG_LLM_MODEL", "byz-llm"), "weights_revision": os.environ.get("AIRAG_LLM_REVISION"),
                "context_length": 24576, "timeout_s": 90,
            },
        })
        assert registered["ok"], registered
        profile = registered["data"]["profile_key"]
        corpus = {
            "cats": "고양이는 하루에 열두 시간에서 열여섯 시간 정도 잠을 잔다. 새벽과 해 질 무렵에 활발하다.",
            "weather": "오늘 서울은 맑고 따뜻하다. 낮 최고 기온은 섭씨 이십오 도로 예상된다.",
        }
        receipts = {}
        for name, text in corpus.items():
            result = api.add(con, f"live-{name}", "synthetic", name, text.encode(), profile_key=profile)
            assert result["ok"] and result["data"]["searchable"], result
            receipts[name] = result
        result = api.search(con, "synthetic", "고양이는 하루에 얼마나 자나요?", profile)
        assert result["ok"], result
        evidence = result["data"]["results"][0]
        assert evidence["source_id"] == receipts["cats"]["data"]["source_id"]
        assert "고양이" in evidence["original_text"]
        assert evidence["anchor"]["llm_enrichment"]["translation_en"]
        deleted = api.delete(con, "live-delete", "synthetic", "cats", receipts["cats"]["data"]["revision_token"])
        assert deleted["ok"], deleted
        replay = api.fetch_manifest(con, result["data"]["manifest_id"])
        assert replay["data"]["historical"] is True
        assert replay["data"]["results"] == result["data"]["results"]
    finally:
        con.close()
