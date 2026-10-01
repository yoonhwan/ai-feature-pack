from __future__ import annotations

import json
import os
from unittest.mock import patch

import pytest

from airag import llm_enrichment as le

CFG = le.ChatCompletionConfig(
    provider="byz-vllm", endpoint="http://localhost:8002/v1", model="byz-llm", weights_revision=None,
    context_length=24576,
)


def _chat_payload(content: str, *, model: str = "byz-llm", finish_reason: str = "stop") -> dict[str, object]:
    return {
        "model": model,
        "system_fingerprint": "vllm-0.28.0-6d404153",
        "usage": {"prompt_tokens": 10, "completion_tokens": 10},
        "choices": [{"finish_reason": finish_reason, "message": {"content": content}}],
    }


def _good_units_array(units: dict[str, str]) -> str:
    return json.dumps([
        {"unit_id": uid, "tags": ["t1"], "summary": "s", "translation_en": "en"} for uid in units
    ])


def _good_groups_array(unit_ids: list[str]) -> str:
    return json.dumps([{"unit_ids": unit_ids, "group_summary": "s", "group_tags": ["t1"]}])


@pytest.fixture(autouse=True)
def _patch_tokenize(request: pytest.FixtureRequest):
    # Integration tests exercise the REAL count_tokens (real /tokenize
    # call) — must not be mocked, or they'd never test what they claim to.
    if request.node.get_closest_marker("integration") is not None:
        yield
        return
    with patch.object(le, "count_tokens", return_value=5):
        yield


# ---------------------------------------------------------------- config


def test_validate_config_rejects_max_tokens_ge_context_length() -> None:
    with pytest.raises(ValueError, match="max_tokens"):
        le.validate_config(le.ChatCompletionConfig(
            provider="byz-vllm", endpoint="http://x/v1", model="m", weights_revision=None,
            context_length=100, max_tokens=100,
        ))


def test_validate_config_rejects_unsupported_provider() -> None:
    with pytest.raises(ValueError, match="provider"):
        le.validate_config(le.ChatCompletionConfig(
            provider="unknown", endpoint="http://x/v1", model="m", weights_revision=None, context_length=100,
        ))


def test_validate_units_rejects_too_many() -> None:
    units = {f"u{i}": "x" for i in range(le.MAX_UNITS_PER_CALL + 1)}
    with pytest.raises(ValueError, match="exceeds"):
        le._validate_units(units)


# ------------------------------------------------------------- enrich_units


def test_enrich_units_empty_short_circuits_without_a_call() -> None:
    with patch.object(le, "_post_json") as mock_post:
        results, meta = le.enrich_units(CFG, {})
    assert results == []
    assert meta == {}
    mock_post.assert_not_called()


def test_enrich_units_happy_path_order_and_metadata() -> None:
    units = {"c2": "second", "c1": "first"}
    with patch.object(le, "_post_json", return_value=_chat_payload(_good_units_array(units))):
        results, meta = le.enrich_units(CFG, units)
    assert [r.unit_id for r in results] == ["c2", "c1"]
    assert meta["system_fingerprint_RUNTIME_NOT_WEIGHTS"] == "vllm-0.28.0-6d404153"
    assert meta["configured_weights_revision"] is None
    assert meta["prompt_version"] == le.ENRICH_UNITS_PROMPT_VERSION
    assert meta["finish_reason"] == "stop"


def test_enrich_units_strips_markdown_fence() -> None:
    units = {"c1": "x"}
    fenced = "```json\n" + _good_units_array(units) + "\n```"
    with patch.object(le, "_post_json", return_value=_chat_payload(fenced)):
        results, _ = le.enrich_units(CFG, units)
    assert results[0].unit_id == "c1"


def test_enrich_units_rejects_model_mismatch() -> None:
    units = {"c1": "x"}
    with patch.object(le, "_post_json", return_value=_chat_payload(_good_units_array(units), model="wrong-model")):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "MODEL_MISMATCH"


def test_enrich_units_rejects_non_stop_finish_reason() -> None:
    units = {"c1": "x"}
    with patch.object(le, "_post_json", return_value=_chat_payload(_good_units_array(units), finish_reason="length")):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "INCOMPLETE_COMPLETION"


def test_enrich_units_rejects_tool_calls_only() -> None:
    units = {"c1": "x"}
    payload = _chat_payload("")
    payload["choices"][0]["message"] = {"content": None, "tool_calls": [{"id": "1"}]}
    with patch.object(le, "_post_json", return_value=payload):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_enrich_units_missing_unit_id_is_coverage_mismatch() -> None:
    units = {"c1": "a", "c2": "b"}
    content = json.dumps([{"unit_id": "c1", "tags": ["t"], "summary": "s", "translation_en": "e"}])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "UNIT_COVERAGE_MISMATCH"


def test_enrich_units_duplicate_unit_id_is_coverage_mismatch() -> None:
    units = {"c1": "a"}
    content = json.dumps([
        {"unit_id": "c1", "tags": ["t"], "summary": "s", "translation_en": "e"},
        {"unit_id": "c1", "tags": ["t2"], "summary": "s2", "translation_en": "e2"},
    ])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "UNIT_COVERAGE_MISMATCH"


def test_enrich_units_unknown_unit_id_is_coverage_mismatch() -> None:
    units = {"c1": "a"}
    content = json.dumps([{"unit_id": "nope", "tags": ["t"], "summary": "s", "translation_en": "e"}])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "UNIT_COVERAGE_MISMATCH"


def test_enrich_units_rejects_too_many_tags() -> None:
    units = {"c1": "a"}
    content = json.dumps([{"unit_id": "c1", "tags": ["a", "b", "c", "d", "e", "f"], "summary": "s", "translation_en": "e"}])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_enrich_units_rejects_empty_tags() -> None:
    units = {"c1": "a"}
    content = json.dumps([{"unit_id": "c1", "tags": [], "summary": "s", "translation_en": "e"}])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_enrich_units_non_array_completion_is_rejected() -> None:
    units = {"c1": "a"}
    content = json.dumps({"unit_id": "c1"})
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, units)
    assert excinfo.value.code == "PROVIDER_BAD_RESPONSE"


def test_enrich_units_rejects_prompt_exceeding_budget() -> None:
    with patch.object(le, "count_tokens", return_value=999_999):
        with pytest.raises(le.LLMError) as excinfo:
            le.enrich_units(CFG, {"c1": "x"})
    assert excinfo.value.code == "PROMPT_TOO_LONG"


# --------------------------------------------------------- semantic groups


def test_plan_semantic_groups_empty_short_circuits() -> None:
    with patch.object(le, "_post_json") as mock_post:
        groups, meta = le.plan_semantic_groups(CFG, {})
    assert groups == []
    assert meta == {}
    mock_post.assert_not_called()


def test_plan_semantic_groups_happy_path_contiguous() -> None:
    units = {"u1": "a", "u2": "b", "u3": "c", "u4": "d"}
    content = json.dumps([
        {"unit_ids": ["u1", "u2"], "group_summary": "s1", "group_tags": ["t1"]},
        {"unit_ids": ["u3", "u4"], "group_summary": "s2", "group_tags": ["t2"]},
    ])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        groups, meta = le.plan_semantic_groups(CFG, units)
    assert [g.unit_ids for g in groups] == [["u1", "u2"], ["u3", "u4"]]
    assert meta["prompt_version"] == le.SEMANTIC_GROUPS_PROMPT_VERSION
    assert meta["input_unit_ids"] == ["u1", "u2", "u3", "u4"]


def test_plan_semantic_groups_rejects_non_contiguous_grouping() -> None:
    """u1 and u3 are not adjacent in the original order — grouping them
    together would require skipping u2, which is forbidden."""
    units = {"u1": "a", "u2": "b", "u3": "c"}
    content = json.dumps([
        {"unit_ids": ["u1", "u3"], "group_summary": "s1", "group_tags": ["t1"]},
        {"unit_ids": ["u2"], "group_summary": "s2", "group_tags": ["t2"]},
    ])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.plan_semantic_groups(CFG, units)
    assert excinfo.value.code == "GROUP_COVERAGE_MISMATCH"


def test_plan_semantic_groups_rejects_missing_unit() -> None:
    units = {"u1": "a", "u2": "b"}
    content = json.dumps([{"unit_ids": ["u1"], "group_summary": "s1", "group_tags": ["t1"]}])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.plan_semantic_groups(CFG, units)
    assert excinfo.value.code == "GROUP_COVERAGE_MISMATCH"


def test_plan_semantic_groups_rejects_duplicate_unit_across_groups() -> None:
    units = {"u1": "a", "u2": "b"}
    content = json.dumps([
        {"unit_ids": ["u1", "u2"], "group_summary": "s1", "group_tags": ["t1"]},
        {"unit_ids": ["u2"], "group_summary": "s2", "group_tags": ["t2"]},
    ])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.plan_semantic_groups(CFG, units)
    assert excinfo.value.code == "GROUP_COVERAGE_MISMATCH"


def test_plan_semantic_groups_rejects_reordered_groups() -> None:
    """Groups cover every unit exactly once but in the WRONG order
    relative to the original sequence — still rejected."""
    units = {"u1": "a", "u2": "b", "u3": "c", "u4": "d"}
    content = json.dumps([
        {"unit_ids": ["u3", "u4"], "group_summary": "s1", "group_tags": ["t1"]},
        {"unit_ids": ["u1", "u2"], "group_summary": "s2", "group_tags": ["t2"]},
    ])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.plan_semantic_groups(CFG, units)
    assert excinfo.value.code == "GROUP_COVERAGE_MISMATCH"


def test_plan_semantic_groups_rejects_unknown_unit_id() -> None:
    units = {"u1": "a"}
    content = json.dumps([{"unit_ids": ["not-real"], "group_summary": "s", "group_tags": ["t"]}])
    with patch.object(le, "_post_json", return_value=_chat_payload(content)):
        with pytest.raises(le.LLMError) as excinfo:
            le.plan_semantic_groups(CFG, units)
    assert excinfo.value.code == "GROUP_COVERAGE_MISMATCH"


# ------------------------------------------------------- live integration
#
# Requires the tunnel to byz-agents-gce-llm-dev:8000 -> localhost:8002
# (started this session, per gpu-provider-probe.json). Skipped by default.


@pytest.mark.integration
def test_count_tokens_against_real_byz_llm_tokenize_endpoint() -> None:
    real_cfg = le.ChatCompletionConfig(
        provider="byz-vllm", endpoint=os.environ.get("AIRAG_LLM_ENDPOINT", "http://localhost:8002/v1"),
        model="byz-llm", weights_revision=os.environ.get("AIRAG_LLM_REVISION"),
        context_length=24576,
    )
    n = le.count_tokens(real_cfg, "hello world test")
    raw = le._post_json(real_cfg, "/tokenize", {"model": real_cfg.model, "prompt": "hello world test"},
                        base=le._root_endpoint(real_cfg))["count"]
    assert n > raw  # Include chat-template overhead in the actual request budget.
    assert le.count_tokens(real_cfg, "hello world test " * 20) > n


@pytest.mark.integration
def test_enrich_units_against_real_byz_llm_small_scale() -> None:
    real_cfg = le.ChatCompletionConfig(
        provider="byz-vllm", endpoint=os.environ.get("AIRAG_LLM_ENDPOINT", "http://localhost:8002/v1"),
        model="byz-llm", weights_revision=os.environ.get("AIRAG_LLM_REVISION"),
        context_length=24576,
    )
    units = {
        "u1": "고양이는 하루의 대부분을 잠으로 보내는 동물이다.",
        "u2": "오늘 서울의 날씨는 맑고 기온은 25도이다.",
        "u3": "SQLite is a lightweight relational database.",
    }
    results, meta = le.enrich_units(real_cfg, units)
    assert [r.unit_id for r in results] == list(units.keys())
    for r in results:
        assert le.MIN_TAGS <= len(r.tags) <= le.MAX_TAGS
        assert r.summary.strip() and r.translation_en.strip()
    u1 = next(r for r in results if r.unit_id == "u1")
    assert "cat" in u1.translation_en.lower() or "sleep" in u1.translation_en.lower()
    assert meta["model_echoed"] == "byz-llm"
    assert meta["finish_reason"] == "stop"
    assert meta["usage"]["prompt_tokens"] > 0


@pytest.mark.integration
def test_plan_semantic_groups_against_real_byz_llm_small_scale() -> None:
    real_cfg = le.ChatCompletionConfig(
        provider="byz-vllm", endpoint=os.environ.get("AIRAG_LLM_ENDPOINT", "http://localhost:8002/v1"),
        model="byz-llm", weights_revision=os.environ.get("AIRAG_LLM_REVISION"),
        context_length=24576,
    )
    units = {
        "p1": "Cats are animals that spend most of the day sleeping.",
        "p2": "Most cats also enjoy napping in sunny spots near windows.",
        "p3": "SQLite is a lightweight relational database engine.",
        "p4": "It stores an entire database as a single cross-platform file.",
    }
    groups, meta = le.plan_semantic_groups(real_cfg, units)
    flat = [uid for g in groups for uid in g.unit_ids]
    assert flat == list(units.keys())  # exact coverage/order/contiguity, real model output
    assert [g.unit_ids for g in groups] == [["p1", "p2"], ["p3", "p4"]]
    assert meta["prompt_version"] == le.SEMANTIC_GROUPS_PROMPT_VERSION


def test_strict_schema_is_sent_and_does_not_replace_coverage_validation():
    units = {"u0": "source with quotes and JSON-like content", "u1": "second"}
    with patch.object(le, "_post_json", return_value=_chat_payload(_good_units_array(units))) as provider:
        le.enrich_units(CFG, units)
    schema = provider.call_args.args[2]["response_format"]["json_schema"]
    assert schema["strict"] is True
    assert schema["schema"]["items"]["additionalProperties"] is False
    assert schema["schema"]["items"]["properties"]["unit_id"]["enum"] == list(units)
    invalid = _good_groups_array(["u1", "u0"])
    with patch.object(le, "_post_json", return_value=_chat_payload(invalid)) as provider:
        with pytest.raises(le.LLMError) as error:
            le.plan_semantic_groups(CFG, units)
    assert error.value.code == "GROUP_COVERAGE_MISMATCH"
    assert provider.call_args.args[2]["response_format"]["json_schema"]["strict"] is True
