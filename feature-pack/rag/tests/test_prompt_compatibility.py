"""Stored prompt versions select their original behavior and identity."""
from __future__ import annotations

import json
from dataclasses import asdict
from unittest.mock import patch

import pytest

from airag import api, embeddings, llm_enrichment as le, pipeline, profiles
from airag.db import connect


@pytest.mark.parametrize("version", ["v1", "v2", "v3"])
def test_saved_prompt_version_loads_and_selects_its_original_prompt(tmp_path, key_bytes, version):
    con = connect.init_db(tmp_path / "versions.db", key_bytes)
    prompt_version = "airag.llm_enrichment.plan_semantic_groups." + version
    cfg = le.ChatCompletionConfig("byz-vllm", "http://localhost:1/v1", "fixture", "weights-v1", 24576,
                                  group_prompt_version=prompt_version)
    embed = embeddings.EmbeddingSpaceConfig("openai-compatible", "http://localhost:1/v1", "fixture-embed", "rev", 4,
                                            tokenizer_revision="97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3")
    try:
        con.execute("BEGIN IMMEDIATE")
        space, profile = profiles.register_space_and_profile(con, embed, {}, llm=cfg)
        con.commit()
        saved = con.execute("SELECT chunker_config FROM processing_profiles WHERE profile_key=?", (profile,)).fetchone()[0]
        descriptor = json.loads(saved)["llm_enrichment"]
        assert descriptor["group_prompt_version"] == prompt_version
        assert "group_prompt_version" not in descriptor["config"]
        restored = pipeline.PipelineConfig.from_profile(con, profile)
        assert restored.llm == cfg
        assert restored.space_id == space
        captured = []

        def response(_cfg, path, body, **kwargs):
            if path == "/tokenize":
                return {"count": 20}
            captured.append(body["messages"][0]["content"])
            return {"model": "fixture", "choices": [{"finish_reason": "stop", "message": {"content": json.dumps([
                {"unit_ids": ["u1"], "group_summary": "Clinic appointment information.", "group_tags": ["appointments"]}
            ])}}]}

        with patch.object(le, "_post_json", side_effect=response):
            _, metadata = le.plan_semantic_groups(restored.llm, {"u1": "나무의원 예약 안내"})
        assert metadata["prompt_version"] == prompt_version
        assert ("TOPIC of the group" in captured[0]) == (version == "v3")
        assert ("transliterate them" in captured[0]) == (version == "v2")
        assert con.execute("SELECT chunker_config FROM processing_profiles WHERE profile_key=?", (profile,)).fetchone()[0] == saved
    finally:
        con.close()


def test_different_prompt_versions_create_distinct_spaces_and_do_not_rewrite_old_profiles(tmp_path, key_bytes):
    con = connect.init_db(tmp_path / "identity.db", key_bytes)
    cfg = {"embedding": {"provider": "openai-compatible", "endpoint": "http://localhost:1/v1", "model": "fixture",
                         "revision": "rev", "dimension": 4, "tokenizer_revision": "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"},
           "llm": {"provider": "byz-vllm", "endpoint": "http://localhost:1/v1", "model": "fixture",
                   "weights_revision": "weights-v1", "context_length": 24576}}
    try:
        results = []
        for version in ("v1", "v2", "v3"):
            cfg["llm"]["group_prompt_version"] = "airag.llm_enrichment.plan_semantic_groups." + version
            result = api.register_profile(con, cfg)
            assert result["ok"], result
            results.append(result["data"])
        assert len({r["space_id"] for r in results}) == 3
        assert len({r["profile_key"] for r in results}) == 3
        assert api.verify(con)["ok"]
    finally:
        con.close()
