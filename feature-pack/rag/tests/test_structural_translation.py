"""Multiline translation preserves native lines, provenance and live claims."""
from __future__ import annotations

import json
from dataclasses import asdict, replace
from unittest.mock import patch

import pytest

from airag import api, llm_enrichment as le, pipeline, profiles
from airag.db import connect


CFG = le.ChatCompletionConfig("byz-vllm", "http://localhost:1/v1", "fixture", "revision", 24576)


def payload(uid, translation):
    return {"model": "fixture", "choices": [{"finish_reason": "stop", "message": {"content": json.dumps([
        {"unit_id": uid, "tags": ["inventory"], "summary": "Inventory and animal information.", "translation_en": translation}
    ])}}]}


def test_mixed_lines_preserve_original_offsets_and_ignore_annotation_rewrite():
    source = "Inventory\r\n\r\nCoffee: 42, Tea: 17\r\n고 양 이 는 잠 을 많이 잡니다.\n"
    requests, renewals = [], []

    def post(cfg, path, body):
        assert len(renewals) == len(requests) + 1
        unit = json.loads(body["messages"][0]["content"].split("Units:\n", 1)[1])
        requests.append(unit)
        if unit["text"] == "고 양 이 는 잠 을 많이 잡니다.":
            return payload(unit["unit_id"], "The cat sleeps a lot.")
        if "The cat sleeps a lot." in unit["text"]:
            return payload(unit["unit_id"], "UNWANTED ANNOTATION REWRITE")
        assert "고 양 이" not in unit["text"]
        return payload(unit["unit_id"], None)

    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", side_effect=post):
        results, metadata = le.enrich_units(CFG, {"group": source}, on_progress=lambda: renewals.append(True))
    assert results[0].translation_en == "Inventory\r\n\r\nCoffee: 42, Tea: 17\r\nThe cat sleeps a lot.\n"
    assert len(requests) == len(renewals) == 4
    assert metadata["prompt_version"] == "airag.llm_enrichment.enrich_units.v3"
    assert metadata["usage"] is None and metadata["usage_complete"] is False
    assert metadata["verbatim_unit_ids"] == []
    unit_meta = metadata["unit_metadata"]["group"]
    assert unit_meta["annotation_translation_used"] is False
    assert [source[x["source_start"]:x["source_end"]] for x in unit_meta["segments"]] == [
        "Inventory", "Coffee: 42, Tea: 17", "고 양 이 는 잠 을 많이 잡니다.",
    ]


def test_multiline_english_preserves_every_character_and_repetition():
    source = "  Café inventory\r\n\r\n" + "Coffee: 42\n" * 45 + "\tEnd.  "
    def post(cfg, path, body):
        item = json.loads(body["messages"][0]["content"].split("Units:\n", 1)[1])
        return payload(item["unit_id"], None)
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", side_effect=post):
        result, meta = le.enrich_units(CFG, {"original": source})
    assert result[0].translation_en == source
    assert meta["verbatim_unit_ids"] == ["original"]


@pytest.mark.parametrize("separator", ["\n", "\r\n", "\r", "\v", "\f", "\x1c", "\x1d", "\x1e", "\x85", "\u2028", "\u2029"])
def test_every_splitlines_separator_is_preserved_after_translation(separator):
    source = "고양이" + separator + "강아지"
    def post(cfg, path, body):
        item = json.loads(body["messages"][0]["content"].split("Units:\n", 1)[1])
        translated = {"고양이": "Cat", "강아지": "Dog"}.get(item["text"])
        return payload(item["unit_id"], translated)
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", side_effect=post):
        result, metadata = le.enrich_units(CFG, {"group": source})
    assert result[0].translation_en == "Cat" + separator + "Dog"
    segments = metadata["unit_metadata"]["group"]["segments"]
    assert [source[x["source_start"]:x["source_end"]] for x in segments] == ["고양이", "강아지"]


def test_lost_claim_aborts_before_the_next_provider_request():
    calls = []
    def heartbeat():
        calls.append(True)
        if len(calls) == 2:
            raise le.LLMError("STALE_CLAIM_FENCED", "replaced", retryable=False)
    def post(cfg, path, body):
        item = json.loads(body["messages"][0]["content"].split("Units:\n", 1)[1])
        return payload(item["unit_id"], None)
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", side_effect=post) as provider:
        with pytest.raises(le.LLMError) as exc:
            le.enrich_units(CFG, {"group": "First line\nSecond line"}, on_progress=heartbeat)
    assert exc.value.code == "STALE_CLAIM_FENCED"
    provider.assert_called_once()


def test_segment_budget_is_checked_before_network_calls():
    with patch.object(le, "_post_json") as provider:
        with pytest.raises(ValueError, match="segment"):
            le.enrich_units(CFG, {"group": "content\n" * (le.MAX_UNITS_PER_CALL + 1)})
    provider.assert_not_called()


def test_segment_failure_cannot_become_partial_translation():
    calls = 0
    def post(cfg, path, body):
        nonlocal calls
        calls += 1
        item = json.loads(body["messages"][0]["content"].split("Units:\n", 1)[1])
        response = payload(item["unit_id"], None)
        if calls == 2:
            response["choices"][0]["finish_reason"] = "length"
        return response
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", side_effect=post):
        with pytest.raises(le.LLMError) as exc:
            le.enrich_units(CFG, {"group": "First line\nSecond line"})
    assert exc.value.code == "INCOMPLETE_COMPLETION" and calls == 2


@pytest.mark.parametrize("version", ["v1", "v2"])
def test_old_profiles_keep_single_call_and_descriptor_shape(version):
    cfg = replace(CFG, enrich_prompt_version="airag.llm_enrichment.enrich_units." + version)
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", return_value=payload("group", "Existing translation")) as provider:
        result, metadata = le.enrich_units(cfg, {"group": "Header\nBody"})
    provider.assert_called_once()
    assert result[0].translation_en == "Existing translation"
    assert "translation_unit_policy" not in metadata
    config = asdict(cfg)
    group_version = config.pop("group_prompt_version")
    enrich_version = config.pop("enrich_prompt_version")
    assert profiles.enrichment_descriptor(cfg) == {
        "config": config, "pipeline_version": "semantic-groups-english-v1",
        "enrich_prompt_version": enrich_version, "group_prompt_version": group_version,
        "source_unit_max_tokens": 512, "semantic_window_units": 4,
    }


def test_new_policy_has_a_new_space_without_rewriting_existing_profiles(tmp_path, key_bytes):
    con = connect.init_db(tmp_path / "profile-versions.db", key_bytes)
    embedding = {"provider": "openai-compatible", "endpoint": "http://localhost:1/v1", "model": "fixture",
                 "revision": "rev", "dimension": 4, "tokenizer_revision": "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"}
    try:
        results, configs = [], []
        for version in ("v1", "v2", "v3"):
            cfg = replace(CFG, enrich_prompt_version="airag.llm_enrichment.enrich_units." + version)
            response = api.register_profile(con, {"embedding": embedding, "llm": asdict(cfg)})
            assert response["ok"], response
            results.append(response["data"])
            configs.append(cfg)
        assert len({x["space_id"] for x in results}) == 3
        for result, cfg in zip(results, configs):
            assert pipeline.PipelineConfig.from_profile(con, result["profile_key"]).llm == cfg
        assert api.verify(con)["ok"]
    finally:
        con.close()
