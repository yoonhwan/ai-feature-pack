"""Verbatim decisions are explicit, versioned, and preserve input exactly."""
from __future__ import annotations

import json
from dataclasses import asdict, replace
from unittest.mock import patch

import pytest

from airag import api, llm_enrichment as le, profiles, pipeline
from airag.db import connect


CFG = le.ChatCompletionConfig("byz-vllm", "http://localhost:1/v1", "fixture", "rev", 24576,
                              enrich_prompt_version="airag.llm_enrichment.enrich_units.v2")
V1 = "airag.llm_enrichment.enrich_units.v1"
V2 = "airag.llm_enrichment.enrich_units.v2"


def _response(items, finish="stop"):
    return {"model": "fixture", "choices": [{"finish_reason": finish, "message": {"content": json.dumps(items)}}]}


def _item(uid, translation):
    return {"unit_id": uid, "tags": ["inventory"], "summary": "Inventory information.", "translation_en": translation}


def test_explicit_verbatim_preserves_repetition_unicode_whitespace_and_unit_order():
    original = "Café inventory: 42 bags.\n\n" * 45 + "  End.\n"
    units = {"english": original, "korean": "재고는 42봉지입니다."}
    payload = _response([_item("korean", "Inventory is 42 bags."), _item("english", None)])
    with patch.object(le, "count_tokens", return_value=900), patch.object(le, "_post_json", return_value=payload):
        result, metadata = le.enrich_units(CFG, units)
    assert [x.unit_id for x in result] == ["english", "korean"]
    assert result[0].translation_en == original
    assert result[0].translation_en.count("42 bags") == 45
    assert result[1].translation_en == "Inventory is 42 bags."
    assert metadata["verbatim_unit_ids"] == ["english"]
    assert metadata["prompt_version"] == V2


@pytest.mark.parametrize("bad", ["missing", "empty", "number", "bool", "array"])
def test_malformed_translation_never_falls_back_to_original(bad):
    item = _item("unit", {"empty": "", "number": 3, "bool": False, "array": []}.get(bad))
    if bad == "missing":
        item.pop("translation_en")
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", return_value=_response([item])):
        with pytest.raises(le.LLMError) as exc:
            le.enrich_units(CFG, {"unit": "original"})
    assert exc.value.code == "PROVIDER_BAD_RESPONSE"


def test_null_from_old_prompt_is_invalid_and_old_string_prompt_is_unchanged():
    cfg = replace(CFG, enrich_prompt_version=V1)
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", return_value=_response([_item("unit", None)])):
        with pytest.raises(le.LLMError):
            le.enrich_units(cfg, {"unit": "original"})
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", return_value=_response([_item("unit", "original")])) as post:
        result, metadata = le.enrich_units(cfg, {"unit": "original"})
    assert result[0].translation_en == "original"
    assert metadata["prompt_version"] == V1 and "verbatim_unit_ids" not in metadata
    prompt = post.call_args.args[2]["messages"][0]["content"]
    assert "if the text is already English, return it unchanged" in prompt
    assert "JSON null" not in prompt


def test_truncated_verbatim_response_still_fails_closed():
    with patch.object(le, "count_tokens", return_value=20), patch.object(le, "_post_json", return_value=_response([_item("unit", None)], "length")):
        with pytest.raises(le.LLMError) as exc:
            le.enrich_units(CFG, {"unit": "original"})
    assert exc.value.code == "INCOMPLETE_COMPLETION"


def test_old_descriptor_shape_and_fingerprint_survive_new_default(tmp_path, key_bytes):
    cfg = replace(CFG, enrich_prompt_version=V1)
    original_config = asdict(cfg)
    original_config.pop("group_prompt_version")
    original_config.pop("enrich_prompt_version")
    descriptor = {"config": original_config, "pipeline_version": "semantic-groups-english-v1",
                  "enrich_prompt_version": V1, "group_prompt_version": cfg.group_prompt_version,
                  "source_unit_max_tokens": 512, "semantic_window_units": 4}
    assert profiles.enrichment_descriptor(cfg) == descriptor
    con = connect.init_db(tmp_path / "versions.db", key_bytes)
    embed = {"provider": "openai-compatible", "endpoint": "http://localhost:1/v1", "model": "fixture",
             "revision": "rev", "dimension": 4, "tokenizer_revision": "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"}
    try:
        old = api.register_profile(con, {"embedding": embed, "llm": asdict(cfg)})
        assert old["ok"], old
        before = con.execute("SELECT * FROM processing_profiles WHERE profile_key=?", (old["data"]["profile_key"],)).fetchone()
        new = api.register_profile(con, {"embedding": embed, "llm": asdict(CFG)})
        assert new["ok"], new
        assert old["data"]["profile_key"] != new["data"]["profile_key"]
        assert old["data"]["space_id"] != new["data"]["space_id"]
        assert pipeline.PipelineConfig.from_profile(con, old["data"]["profile_key"]).llm == cfg
        assert con.execute("SELECT * FROM processing_profiles WHERE profile_key=?", (old["data"]["profile_key"],)).fetchone() == before
        assert api.verify(con)["ok"]
    finally:
        con.close()
