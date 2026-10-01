"""GPU/local chat-completion LLM structured-preprocessing client (D-011
scope): semantic chunk-grouping, per-unit tagging/summary/English
translation, over a document's already-anchored source units — with
strict, code-enforced contracts, never a plausible-shaped-JSON assumption.

Provider-agnostic by construction, same posture as embeddings.py:
`ChatCompletionConfig` is a plain data shape; nothing here is specific to
vLLM/byz-llm, though `count_tokens` currently relies on a vLLM-specific
`/tokenize` endpoint (verified reachable on byz-llm 2026-09-09 — returns a
real server-side token count against the ACTUAL loaded model's own
tokenizer, never assuming a different model's tokenizer, e.g. the local
Qwen embedding tokenizer, fits this one's vocabulary).

Two distinct operations, two distinct prompt-version constants (persisted
alongside any derived artifact so a later re-run under a changed prompt is
never confused with the original):
- `plan_semantic_groups`: the actual LLM semantic chunk-SEPARATION the
  user requested — groups input units (given in document order) into
  CONTIGUOUS, exactly-once-covering, order-preserving groups. The LLM
  chooses group boundaries; it never reorders, drops, or invents a
  unit_id. Larger source units should be deterministically pre-subdivided
  (by chunking.py, for input-size safety) BEFORE this call — this module
  groups whatever units it is given, it does not itself decide where to
  cut a huge document.
- `enrich_units`: per-unit tags/summary/English translation, unit-ID
  coverage validated exactly-once (no group semantics here — this is the
  per-leaf-unit annotation pass, typically run once per semantic group's
  member units or per final chunk).

Every response is validated for: exact model echo (never silently
accepted from an unexpected model), `finish_reason == "stop"` (a
truncated/length-cut, content-filtered, or tool-call-only completion is
REJECTED, never treated as if it were a complete, faithful answer — a
plausible-shaped JSON parse alone does not prove the requested operation
actually completed), and strict JSON parsing (`airag._json.strict_json_
loads` — rejects NaN/Infinity, matching the same contract embeddings.py
and store.py already use elsewhere in this package).

Provenance/pipeline order implemented in pipeline.py: normalize/anchor -> bounded
source units -> `plan_semantic_groups` -> `enrich_units` (tags/summary/
English translation) -> embed the ENGLISH translation text (never the
original-language text) -> fenced atomic publication via
`store.publish_generation_with_content`. The original source-language
text, the semantic grouping plan, the translation, and the summary/tags
are FOUR DISTINCT fields a caller must persist separately — a summary or
translation is a derived artifact, never a substitute for the verbatim
original. A search-time query must go through the SAME English-
translation policy before embedding, with that translation/provenance
recorded in the search manifest.
"""

from __future__ import annotations

from airag import provider_metrics

import json
import math
import re
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, replace

from airag._json import strict_json_loads
from airag import store

DEFAULT_TIMEOUT_S = 60.0
DEFAULT_MAX_TOKENS = 2048
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
MAX_UNITS_PER_CALL = 200
SUPPORTED_PROVIDERS = frozenset({"byz-vllm", "openai-compatible"})
MIN_TAGS, MAX_TAGS = 1, 5
_FENCE_RE = re.compile(r"^```(?:json)?\s*\n(.*?)\n```\s*$", re.DOTALL)

ENRICH_UNITS_PROMPT_VERSION = "airag.llm_enrichment.enrich_units.v3"
_ENRICH_PROMPT_VERSIONS = frozenset({
    "airag.llm_enrichment.enrich_units.v1", "airag.llm_enrichment.enrich_units.v2", ENRICH_UNITS_PROMPT_VERSION,
})
SEMANTIC_GROUPS_PROMPT_VERSION = "airag.llm_enrichment.plan_semantic_groups.v3"
_GROUP_PROMPT_INSTRUCTIONS = {
    "airag.llm_enrichment.plan_semantic_groups.v1": "",
    "airag.llm_enrichment.plan_semantic_groups.v2": (
        "Write every group_summary and every group_tag in English, even when the source is not English. "
        "Preserve the source's meaning: summarize only stated facts, never invent a fact. "
        "Names of people, organizations and places are proper names: transliterate them, do not translate "
        "their literal word meanings or reinterpret them as a different subject. Keep all amounts, dates, "
        "deadlines, prohibitions and eligibility conditions faithful to the source.\n"
    ),
    "airag.llm_enrichment.plan_semantic_groups.v3": (
        "Write every group_summary and every group_tag in English, even when the source is not English. "
        "The purpose of group_summary and group_tags is to identify the TOPIC of the group, not to "
        "restate its detailed facts. Use a brief topic description without proper names, amounts, dates "
        "or detailed requirements. Do not infer extra subjects or claims. Full factual detail and proper "
        "names are preserved separately in the source and its translation.\n"
    ),
}


class LLMError(store.ApiError):
    code: str
    message: str
    retryable: bool

    def __init__(self, code: str, message: str, *, retryable: bool) -> None:
        super().__init__(code, message, retryable=retryable)
        self.code = code
        self.message = message
        self.retryable = retryable

    def to_dict(self) -> dict[str, object]:
        return {"code": self.code, "message": self.message, "retryable": self.retryable}


@dataclass(frozen=True)
class ChatCompletionConfig:
    provider: str
    endpoint: str
    model: str
    # Honest per gpu-provider-probe.json: a served-model alias/quantization
    # name is NOT a pinned weights revision proof — None is a legitimate,
    # explicit value here (not a silently-assumed one) until a real
    # file-hash-level pin is available.
    weights_revision: str | None
    # The runtime's DECLARED max_model_len (from /v1/models — e.g. byz-llm
    # reports 24576). Required, never assumed — bounds every prompt this
    # module sends via count_tokens' real server-side count.
    context_length: int
    timeout_s: float = DEFAULT_TIMEOUT_S
    max_tokens: int = DEFAULT_MAX_TOKENS  # RESERVED output budget, subtracted from context_length
    group_prompt_version: str = SEMANTIC_GROUPS_PROMPT_VERSION
    enrich_prompt_version: str = ENRICH_UNITS_PROMPT_VERSION


def validate_config(cfg: ChatCompletionConfig) -> None:
    if not isinstance(cfg.enrich_prompt_version, str) or cfg.enrich_prompt_version not in _ENRICH_PROMPT_VERSIONS:
        raise ValueError("unsupported captured enrichment prompt version")
    if not isinstance(cfg.group_prompt_version, str) or cfg.group_prompt_version not in _GROUP_PROMPT_INSTRUCTIONS:
        raise ValueError("unsupported captured grouping prompt version")
    for field_name in ("provider", "endpoint", "model"):
        value = getattr(cfg, field_name)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{field_name} must be a non-empty string")
    if cfg.provider not in SUPPORTED_PROVIDERS:
        raise ValueError(f"unsupported provider {cfg.provider!r} (supported: {sorted(SUPPORTED_PROVIDERS)})")
    if not cfg.endpoint.startswith(("http://", "https://")):
        raise ValueError(f"endpoint must be an http(s) URL, got {cfg.endpoint!r}")
    if isinstance(cfg.timeout_s, bool) or not isinstance(cfg.timeout_s, (int, float)) or not math.isfinite(cfg.timeout_s) or cfg.timeout_s <= 0:
        raise ValueError(f"timeout_s must be a finite positive number, got {cfg.timeout_s!r}")
    for field_name in ("max_tokens", "context_length"):
        value = getattr(cfg, field_name)
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ValueError(f"{field_name} must be a positive int, got {value!r}")
    if cfg.max_tokens >= cfg.context_length:
        raise ValueError(
            f"max_tokens ({cfg.max_tokens}) leaves no room in context_length ({cfg.context_length})"
        )


def _validate_units(units: dict[str, str]) -> None:
    if not isinstance(units, dict):
        raise ValueError("units must be a dict")
    if len(units) > MAX_UNITS_PER_CALL:
        raise ValueError(f"{len(units)} units exceeds the {MAX_UNITS_PER_CALL}-unit-per-call bound")
    for uid, text in units.items():
        if not isinstance(uid, str) or not uid.strip():
            raise ValueError(f"unit id must be a non-empty string, got {uid!r}")
        if not isinstance(text, str) or not text.strip():
            raise ValueError(f"unit {uid!r}: text must be a non-empty string")


def _classify_http_error(exc: urllib.error.HTTPError) -> tuple[str, bool]:
    if exc.code == 429:
        return "PROVIDER_RATE_LIMITED", True
    if 500 <= exc.code < 600:
        return "PROVIDER_SERVER_ERROR", True
    return "PROVIDER_REQUEST_ERROR", False


def _root_endpoint(cfg: ChatCompletionConfig) -> str:
    """vLLM's own extra endpoints (`/tokenize`, `/detokenize`) are mounted
    at the server ROOT, not under `/v1` like the OpenAI-compatible routes
    — directly verified (2026-09-09) against the real byz-llm server:
    POST .../v1/tokenize -> 404, POST .../tokenize -> 200 with a real
    token count. Do not assume every non-chat/embeddings path lives under
    the same base as the OpenAI-compatible ones."""
    base = cfg.endpoint.rstrip("/")
    if base.endswith("/v1"):
        base = base[: -len("/v1")]
    return base


@provider_metrics.timed_request
def _post_json(cfg: ChatCompletionConfig, path: str, body_obj: dict[str, object], *, base: str | None = None) -> dict[str, object]:
    body = json.dumps(body_obj).encode("utf-8")
    target_base = base if base is not None else cfg.endpoint.rstrip("/")
    req = urllib.request.Request(
        f"{target_base}{path}", data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=cfg.timeout_s) as resp:  # noqa: S310 - operator-configured endpoint
            raw = resp.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as exc:
        code, retryable = _classify_http_error(exc)
        raise LLMError(code, f"{path} provider returned HTTP {exc.code}", retryable=retryable) from exc
    except TimeoutError as exc:
        raise LLMError("PROVIDER_TIMEOUT", f"{path} request timed out", retryable=True) from exc
    except urllib.error.URLError as exc:
        raise LLMError("PROVIDER_UNREACHABLE", f"{path} request failed (connection)", retryable=True) from exc
    if len(raw) > MAX_RESPONSE_BYTES:
        raise LLMError("PROVIDER_BAD_RESPONSE", f"{path} response exceeds {MAX_RESPONSE_BYTES} bytes", retryable=False)
    try:
        payload = strict_json_loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise LLMError("PROVIDER_BAD_RESPONSE", f"{path} returned invalid JSON", retryable=False) from exc
    if not isinstance(payload, dict):
        raise LLMError(
            "PROVIDER_BAD_RESPONSE", f"{path} response is not a JSON object: {type(payload).__name__}", retryable=False
        )
    return payload


def count_tokens(cfg: ChatCompletionConfig, text: str) -> int:
    """Real server-side token count via the runtime's own `/tokenize`
    endpoint (verified reachable on byz-llm 2026-09-09) — never a
    different model's tokenizer used as a stand-in."""
    payload = _post_json(cfg, "/tokenize", {
        "model": cfg.model, "messages": [{"role": "user", "content": text}], "add_generation_prompt": True,
    }, base=_root_endpoint(cfg))
    count = payload.get("count")
    if isinstance(count, bool) or not isinstance(count, int) or count < 0:
        raise LLMError("PROVIDER_BAD_RESPONSE", "/tokenize did not return an integer 'count'", retryable=False)
    return count


def _require_prompt_fits_budget(cfg: ChatCompletionConfig, prompt: str) -> None:
    budget = cfg.context_length - cfg.max_tokens
    n = count_tokens(cfg, prompt)
    if n > budget:
        raise LLMError(
            "PROMPT_TOO_LONG",
            f"prompt is {n} tokens, exceeds the {budget}-token input budget "
            f"(context_length {cfg.context_length} minus reserved max_tokens {cfg.max_tokens})",
            retryable=False,
        )


def _strip_code_fence(text: str) -> str:
    m = _FENCE_RE.match(text.strip())
    return m.group(1) if m else text


def _validate_response_envelope(cfg: ChatCompletionConfig, payload: dict[str, object]) -> tuple[str, dict[str, object]]:
    """Shared validation for both enrich_units and plan_semantic_groups:
    exact model echo, a single complete (finish_reason='stop', no tool
    calls) choice, non-empty string content. Returns (raw_content,
    base_metadata) — callers still need to strict-JSON-parse `content`
    themselves (after stripping a markdown fence) and validate their own
    response shape on top."""
    echoed_model = payload.get("model")
    if not isinstance(echoed_model, str) or echoed_model != cfg.model:
        raise LLMError(
            "MODEL_MISMATCH", f"provider echoed model {echoed_model!r}, expected {cfg.model!r}", retryable=False
        )
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        raise LLMError("PROVIDER_BAD_RESPONSE", "no choices in chat completion response", retryable=False)
    choice = choices[0]
    if not isinstance(choice, dict):
        raise LLMError("PROVIDER_BAD_RESPONSE", "choice is not an object", retryable=False)
    finish_reason = choice.get("finish_reason")
    if finish_reason != "stop":
        raise LLMError(
            "INCOMPLETE_COMPLETION",
            f"finish_reason={finish_reason!r}, expected 'stop' — refusing a truncated/content-filtered/"
            "tool-call completion: a plausible-shaped JSON parse does not prove the operation completed",
            retryable=False,
        )
    message = choice.get("message")
    if not isinstance(message, dict):
        raise LLMError("PROVIDER_BAD_RESPONSE", "choice.message is not an object", retryable=False)
    if message.get("tool_calls"):
        raise LLMError("PROVIDER_BAD_RESPONSE", "tool-call-only output is not supported by this contract", retryable=False)
    content = message.get("content")
    if not isinstance(content, str) or not content.strip():
        raise LLMError("PROVIDER_BAD_RESPONSE", "empty completion content", retryable=False)
    metadata: dict[str, object] = {
        "model_echoed": echoed_model,
        "finish_reason": finish_reason,
        "system_fingerprint_RUNTIME_NOT_WEIGHTS": payload.get("system_fingerprint"),
        "usage": payload.get("usage"),
        "configured_weights_revision": cfg.weights_revision,
    }
    return content, metadata


def _parse_strict_json_content(content: str) -> object:
    stripped = _strip_code_fence(content)
    try:
        return strict_json_loads(stripped)
    except (ValueError, json.JSONDecodeError) as exc:
        raise LLMError("PROVIDER_BAD_RESPONSE", f"completion content is not valid strict JSON: {exc}", retryable=False) from exc


def _validate_tags(uid: str, tags: object) -> list[str]:
    if not isinstance(tags, list) or not (MIN_TAGS <= len(tags) <= MAX_TAGS) or not all(
        isinstance(t, str) and t.strip() for t in tags
    ):
        raise LLMError(
            "PROVIDER_BAD_RESPONSE",
            f"unit {uid!r}: tags must be a list of {MIN_TAGS}-{MAX_TAGS} non-empty strings, got {tags!r}",
            retryable=False,
        )
    return tags


@dataclass(frozen=True)
class UnitEnrichment:
    unit_id: str
    tags: list[str]
    summary: str
    translation_en: str


def _structured_array_format(name: str, properties: dict, *, min_items: int, max_items: int) -> dict:
    return {
        "type": "json_schema",
        "json_schema": {
            "name": name, "strict": True,
            "schema": {
                "type": "array", "minItems": min_items, "maxItems": max_items,
                "items": {
                    "type": "object", "additionalProperties": False,
                    "required": list(properties), "properties": properties,
                },
            },
        },
    }


def enrich_units(cfg: ChatCompletionConfig, units: dict[str, str], *, on_progress: Callable[[], None] | None = None) -> tuple[list[UnitEnrichment], dict[str, object]]:
    """`units`: {unit_id: source_text}. Returns (results in the SAME order
    as `units`, metadata). Raises LLMError(code='UNIT_COVERAGE_MISMATCH')
    if the response does not reference every unit_id EXACTLY once."""
    validate_config(cfg)
    _validate_units(units)
    if not units:
        return [], {}
    if cfg.enrich_prompt_version == "airag.llm_enrichment.enrich_units.v3":
        return _enrich_structural_lines(cfg, units, on_progress=on_progress)
    if on_progress is not None:
        on_progress()
    unit_ids = list(units.keys())
    numbered = "\n".join(
        json.dumps({"unit_id": uid, "text": text}, ensure_ascii=False) for uid, text in units.items()
    )
    verbatim_protocol = cfg.enrich_prompt_version == "airag.llm_enrichment.enrich_units.v2"
    translation_contract = (
        "translation_en (JSON null if the unit is already English; otherwise the complete English translation). "
        "For already-English input return null, NOT a generated copy: the application will preserve the exact "
        "original text, including repetition. For other languages translate all content without summarizing, "
        "adding repetition, or continuing the source.\n"
        if verbatim_protocol else
        "translation_en (English translation of the unit's text; if the text is already English, return it unchanged).\n"
    )
    prompt = (
        "You are a structured data extraction system. For EACH unit below, produce one JSON object with "
        f"EXACTLY these fields: unit_id (copy verbatim from the input), tags (array of {MIN_TAGS}-{MAX_TAGS} "
        "short lowercase tags), summary (one sentence in English), " + translation_contract +
        "Return a single JSON ARRAY containing EXACTLY one object per unit below, covering EVERY unit_id "
        "EXACTLY once, in any order. Return ONLY the JSON array — no markdown code fence, no prose before "
        "or after it.\n\nUnits:\n" + numbered
    )
    _require_prompt_fits_budget(cfg, prompt)
    payload = _post_json(cfg, "/chat/completions", {
        "model": cfg.model, "messages": [{"role": "user", "content": prompt}], "max_tokens": cfg.max_tokens, "temperature": 0,
        "response_format": _structured_array_format(
            "airag_unit_enrichment",
            {
                "unit_id": {"type": "string", "enum": unit_ids},
                "tags": {"type": "array", "minItems": MIN_TAGS, "maxItems": MAX_TAGS,
                         "items": {"type": "string"}},
                "summary": {"type": "string"},
                "translation_en": {"type": ["string", "null"] if verbatim_protocol else "string"},
            },
            min_items=len(unit_ids), max_items=len(unit_ids),
        ),
    })
    content, metadata = _validate_response_envelope(cfg, payload)
    parsed = _parse_strict_json_content(content)
    if not isinstance(parsed, list):
        raise LLMError("PROVIDER_BAD_RESPONSE", "completion JSON is not an array", retryable=False)

    by_id: dict[str, UnitEnrichment] = {}
    verbatim_unit_ids: list[str] = []
    for item in parsed:
        if not isinstance(item, dict):
            raise LLMError("PROVIDER_BAD_RESPONSE", "completion array item is not an object", retryable=False)
        uid = item.get("unit_id")
        if not isinstance(uid, str) or uid not in units:
            raise LLMError(
                "UNIT_COVERAGE_MISMATCH", f"response references an unknown/invalid unit_id: {uid!r}", retryable=False
            )
        if uid in by_id:
            raise LLMError("UNIT_COVERAGE_MISMATCH", f"duplicate unit_id in response: {uid!r}", retryable=False)
        tags = _validate_tags(uid, item.get("tags"))
        summary, translation_en = item.get("summary"), item.get("translation_en")
        if not isinstance(summary, str) or not summary.strip():
            raise LLMError("PROVIDER_BAD_RESPONSE", f"unit {uid!r}: summary must be a non-empty string", retryable=False)
        if verbatim_protocol and "translation_en" in item and translation_en is None:
            # An explicit provider decision, never a fallback for missing,
            # malformed, or truncated output. Source text is not regenerated.
            translation_en = units[uid]
            verbatim_unit_ids.append(uid)
        if not isinstance(translation_en, str) or not translation_en.strip():
            raise LLMError(
                "PROVIDER_BAD_RESPONSE", f"unit {uid!r}: translation_en must be a non-empty string", retryable=False
            )
        by_id[uid] = UnitEnrichment(unit_id=uid, tags=tags, summary=summary, translation_en=translation_en)

    missing = [uid for uid in unit_ids if uid not in by_id]
    if missing:
        raise LLMError("UNIT_COVERAGE_MISMATCH", f"response is missing unit_id(s): {missing}", retryable=False)

    metadata["prompt_version"] = cfg.enrich_prompt_version
    metadata["input_unit_ids"] = unit_ids
    if verbatim_protocol:
        metadata["verbatim_unit_ids"] = [uid for uid in unit_ids if uid in verbatim_unit_ids]
    return [by_id[uid] for uid in unit_ids], metadata


def _enrich_structural_lines(cfg: ChatCompletionConfig, units: dict[str, str], *, on_progress=None):
    """Translate structural lines independently, then annotate the assembled English.

    Native headings/tables and OCR paragraphs may share a semantic group.
    Translating that concatenation can omit its English part or misread its
    OCR subjects. v3 keeps the group and its original anchors intact, but
    prevents one line's language/context from replacing another line's facts.
    The final annotation call may supply tags/summary, never replacement text.
    v1/v2 profiles continue to use their original single-call protocol.
    """
    inner = replace(cfg, enrich_prompt_version="airag.llm_enrichment.enrich_units.v2")
    line_sets = {uid: text.splitlines(keepends=True) for uid, text in units.items()}
    nonempty = {uid: sum(bool(line.strip()) for line in lines) for uid, lines in line_sets.items()}
    if not any(count > 1 for count in nonempty.values()):
        results, metadata = enrich_units(inner, units, on_progress=on_progress)
        return results, {**metadata, "prompt_version": cfg.enrich_prompt_version,
                         "translation_unit_policy": "structural-lines-v1", "segmented_unit_ids": []}
    if sum(nonempty.values()) > MAX_UNITS_PER_CALL:
        raise ValueError("structural translation segments exceed the per-call unit bound")

    results = []
    unit_metadata = {}
    calls = []
    verbatim = []
    segmented = []
    for uid, original in units.items():
        if nonempty[uid] <= 1:
            annotated, metadata = enrich_units(inner, {uid: original}, on_progress=on_progress)
            calls.append(metadata)
            results.append(annotated[0])
            unit_metadata[uid] = {"segmented": False, "metadata": metadata}
            if uid in metadata.get("verbatim_unit_ids", []):
                verbatim.append(uid)
            continue
        translated = []
        segments = []
        offset = 0
        all_verbatim = True
        for index, line in enumerate(line_sets[uid]):
            body = line.rstrip("\r\n\v\f\x1c\x1d\x1e\x85\u2028\u2029")
            suffix = line[len(body):]
            if not body.strip():
                translated.append(line)
                offset += len(line)
                continue
            segment_id = f"{uid}/line-{index}"
            annotated, metadata = enrich_units(inner, {segment_id: body}, on_progress=on_progress)
            calls.append(metadata)
            text = annotated[0].translation_en
            is_verbatim = segment_id in metadata.get("verbatim_unit_ids", [])
            all_verbatim = all_verbatim and is_verbatim
            translated.append(text + suffix)
            segments.append({"source_start": offset, "source_end": offset + len(body),
                             "translation_en": text, "verbatim": is_verbatim, "metadata": metadata})
            offset += len(line)
        assembled = "".join(translated)
        annotations, metadata = enrich_units(inner, {uid: assembled}, on_progress=on_progress)
        calls.append(metadata)
        results.append(UnitEnrichment(uid, annotations[0].tags, annotations[0].summary, assembled))
        unit_metadata[uid] = {"segmented": True, "segments": segments, "annotation_metadata": metadata,
                              "annotation_translation_used": False}
        segmented.append(uid)
        if all_verbatim:
            assert assembled == original
            verbatim.append(uid)
    usages = [m["usage"] for m in calls if isinstance(m.get("usage"), dict)]
    usage = {key: sum(m.get(key, 0) for m in usages if type(m.get(key, 0)) is int)
             for key in ("prompt_tokens", "completion_tokens", "total_tokens")}
    metadata = {"model_echoed": cfg.model, "finish_reason": "stop", "usage": usage if usages else None,
                "usage_complete": len(usages) == len(calls),
                "configured_weights_revision": cfg.weights_revision, "prompt_version": cfg.enrich_prompt_version,
                "input_unit_ids": list(units), "verbatim_unit_ids": verbatim,
                "translation_unit_policy": "structural-lines-v1", "segmented_unit_ids": segmented,
                "unit_metadata": unit_metadata}
    return results, metadata


@dataclass(frozen=True)
class SemanticGroup:
    unit_ids: list[str]  # a CONTIGUOUS subsequence of the input order
    group_summary: str
    group_tags: list[str]


def plan_semantic_groups(
    cfg: ChatCompletionConfig, units: dict[str, str]
) -> tuple[list[SemanticGroup], dict[str, object]]:
    """`units` MUST be given in DOCUMENT ORDER (dict insertion order is
    the authoritative sequence). The model chooses semantic group
    boundaries; it NEVER reorders, drops, or invents a unit_id — validated
    by requiring the concatenation of all returned groups' unit_ids to
    equal the input sequence EXACTLY (this single check simultaneously
    proves exactly-once coverage, no reordering, AND contiguity: any
    non-contiguous or reordered grouping could not reconstruct the
    original sequence when concatenated in the groups' own returned
    order). Larger source units should already have been deterministically
    pre-subdivided (by chunking.py) for input-size safety BEFORE this
    call — this function groups whatever units it is given."""
    validate_config(cfg)
    _validate_units(units)
    if not units:
        return [], {}
    unit_ids = list(units.keys())
    numbered = "\n".join(
        f"[{i}] " + json.dumps({"unit_id": uid, "text": text}, ensure_ascii=False)
        for i, (uid, text) in enumerate(units.items())
    )
    prompt = (
        "The following units are given in their ORIGINAL DOCUMENT ORDER, numbered [0], [1], .... Group them "
        "into semantically coherent, CONTIGUOUS groups: each group must be one unbroken run of consecutive "
        "units in their original order. Do NOT skip a unit, reorder units, split one unit across groups, "
        "or invent a new unit_id. Every unit must appear in EXACTLY one group.\n"
        + _GROUP_PROMPT_INSTRUCTIONS[cfg.group_prompt_version] +
        "Return a JSON array of groups, each an object with EXACTLY: unit_ids (array of that group's "
        "unit_id strings, copied verbatim, in original order), group_summary (one sentence in English), "
        f"group_tags (array of {MIN_TAGS}-{MAX_TAGS} short lowercase tags). Return ONLY the JSON array — "
        "no markdown code fence, no prose.\n\nUnits:\n" + numbered
    )
    _require_prompt_fits_budget(cfg, prompt)
    payload = _post_json(cfg, "/chat/completions", {
        "model": cfg.model, "messages": [{"role": "user", "content": prompt}], "max_tokens": cfg.max_tokens, "temperature": 0,
        "response_format": _structured_array_format(
            "airag_semantic_groups",
            {
                "unit_ids": {"type": "array", "minItems": 1, "maxItems": len(unit_ids),
                             "items": {"type": "string", "enum": unit_ids}},
                "group_summary": {"type": "string"},
                "group_tags": {"type": "array", "minItems": MIN_TAGS, "maxItems": MAX_TAGS,
                               "items": {"type": "string"}},
            },
            min_items=1, max_items=len(unit_ids),
        ),
    })
    content, metadata = _validate_response_envelope(cfg, payload)
    parsed = _parse_strict_json_content(content)
    if not isinstance(parsed, list) or not parsed:
        raise LLMError("PROVIDER_BAD_RESPONSE", "grouping response is not a non-empty array", retryable=False)

    groups: list[SemanticGroup] = []
    flat: list[str] = []
    for item in parsed:
        if not isinstance(item, dict):
            raise LLMError("PROVIDER_BAD_RESPONSE", "group array item is not an object", retryable=False)
        group_unit_ids = item.get("unit_ids")
        if not isinstance(group_unit_ids, list) or not group_unit_ids or not all(
            isinstance(u, str) and u in units for u in group_unit_ids
        ):
            raise LLMError(
                "GROUP_COVERAGE_MISMATCH", f"group has an empty/invalid/unknown unit_ids list: {group_unit_ids!r}",
                retryable=False,
            )
        group_summary = item.get("group_summary")
        if not isinstance(group_summary, str) or not group_summary.strip():
            raise LLMError("PROVIDER_BAD_RESPONSE", "group_summary must be a non-empty string", retryable=False)
        group_tags = _validate_tags("<group>", item.get("group_tags"))
        groups.append(SemanticGroup(unit_ids=group_unit_ids, group_summary=group_summary, group_tags=group_tags))
        flat.extend(group_unit_ids)

    if flat != unit_ids:
        raise LLMError(
            "GROUP_COVERAGE_MISMATCH",
            "groups do not exactly partition the input in original order — a missing, duplicated, "
            "reordered, or non-contiguous unit_id was detected",
            retryable=False,
        )

    metadata["prompt_version"] = cfg.group_prompt_version
    metadata["input_unit_ids"] = unit_ids
    return groups, metadata
