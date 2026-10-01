"""Local OpenAI-compatible embeddings provider client + embedding-space
identity/registration (design D-001/D-010, P-03-B scope; measurements per
docs/artifacts/p03a-provider-probe.json).

Provider-agnostic by construction: `EmbeddingSpaceConfig` is a plain data
shape, and nothing here branches on `provider` — "lmstudio" is one value a
caller can put in that field, never a hardcoded default this module treats
specially. ft-airag-arch-astra 2026-09-09 direction: local Qwen/LM Studio is
NOT being declared the product's committed default provider here; a future
GPU-hosted provider plugs in as just another `EmbeddingSpaceConfig` once its
endpoint is confirmed reachable — no speculative code for an unconfirmed
endpoint.

`fingerprint_space` hashes exactly D-001's identity fields (provider proto-
col/model/revision/dimension/modality/document+query preprocessing) — never
operational knobs like endpoint/timeout/batch size (two callers pointed at
different endpoints for the SAME underlying model/revision are still the
same space). The full identity (including query_task_description, which
participates in the fingerprint) is persisted as a JSON descriptor in
`embedding_spaces.query_preprocessing`, not just a bare template string —
`config_from_space_row` reconstructs an equivalent `EmbeddingSpaceConfig`
from a stored row, so a reload never has to re-derive identity fields from
today's (possibly since-changed) code defaults.

`_validate_and_order` fails CLOSED on anything the OpenAI-compatible
`/v1/embeddings` contract does not strictly satisfy: exact model echo,
exact integer indices (bool is a `int` subclass in Python and is explicitly
rejected), exact numeric (never string-coerced) vector components, full
index coverage/uniqueness, declared dimension, and — critically — that each
value's actual float32 (vec0 storage) representation stays finite and the
vector stays non-zero after that narrowing (a finite float64 component can
silently overflow to +-inf or underflow to 0.0 in float32; this is checked
by round-tripping through the real packed bytes, not by inspecting the
float64 value alone).
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import sqlite3
import struct
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass

from airag import chunking, store
from airag.db import vecext

DEFAULT_TIMEOUT_S = 30.0
DEFAULT_MAX_BATCH = 64
# A DECLARED provider input bound, not a verified server runtime limit —
# the HF model card's own usage example truncates at 8192 (the card's
# architectural max is 32K), and this LM Studio build's /v1/embeddings
# response never reports usage.prompt_tokens (always 0), so there is no API
# signal to confirm what context length is actually loaded. Nothing here
# claims the server "never truncates" — only that THIS caller's own chunk/
# query text never exceeds this configured bound before sending (p03a
# probe's own recommendation). A caller with a way to inspect the loaded
# runtime's actual context window should pass that value in instead.
DEFAULT_MAX_TOKENS = 8192
DEFAULT_QUERY_TEMPLATE = "Instruct: {task}\nQuery:{query}"
DEFAULT_QUERY_TASK = "Given a search query, retrieve relevant passages that answer the query"
SUPPORTED_PROVIDERS = frozenset({"lmstudio", "openai-compatible"})
SUPPORTED_MODALITIES = frozenset({"text"})
SUPPORTED_DOCUMENT_PREPROCESSING = frozenset({"raw"})
# response.read() is bounded — an embedding batch response is small
# (floats for max_batch*dimension numbers plus JSON overhead); anything
# past this is either a misconfigured endpoint or a malicious/broken proxy,
# never a legitimate embeddings payload at this package's batch sizes.
MAX_RESPONSE_BYTES = 64 * 1024 * 1024
_UNPINNED_REVISIONS = frozenset({"main", "master", "latest", "head", ""})
_TEMPLATE_PLACEHOLDER_RE = re.compile(r"\{(\w+)\}")


class EmbeddingError(store.ApiError):
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
class EmbeddingSpaceConfig:
    provider: str
    endpoint: str
    model: str
    revision: str
    dimension: int
    modality: str = "text"
    document_preprocessing: str = "raw"
    query_preprocessing_template: str = DEFAULT_QUERY_TEMPLATE
    query_task_description: str = DEFAULT_QUERY_TASK
    tokenizer_model: str = "Qwen/Qwen3-Embedding-0.6B"
    # No floating default here — see p03-embedding-review.txt item 1: a
    # default of "main" would contradict chunking.py's own pinned-revision
    # requirement for the exact same reason (an unpinned tokenizer ref can
    # silently change what a profile_key claims is immutable). Callers
    # MUST pass an actual pinned commit/tag; validate_config rejects the
    # floating names below if one sneaks in anyway.
    tokenizer_revision: str = ""
    max_tokens: int = DEFAULT_MAX_TOKENS
    timeout_s: float = DEFAULT_TIMEOUT_S
    max_batch: int = DEFAULT_MAX_BATCH
    enrichment_fingerprint: str | None = None

    def identity_fields(self) -> dict[str, object]:
        # Deliberately excludes endpoint/timeout_s/max_batch/tokenizer_* —
        # those are operational configuration, not part of D-001's identity.
        # tokenizer_model/tokenizer_revision belong in the processing
        # profile's chunker_config instead (a normalization/chunking
        # concern) — profiles.py captures them there, alongside
        # endpoint/timeout_s/max_batch, so a reload never has to guess any
        # of this package's own runtime defaults.
        identity = {
            "provider": self.provider,
            "model": self.model,
            "revision": self.revision,
            "dimension": self.dimension,
            "modality": self.modality,
            "document_preprocessing": self.document_preprocessing,
            "query_preprocessing_template": self.query_preprocessing_template,
            "query_task_description": self.query_task_description,
        }
        if self.enrichment_fingerprint is not None:
            identity["enrichment_fingerprint"] = self.enrichment_fingerprint
        return identity


def _require_positive_int(name: str, value: object) -> None:
    # bool IS an int subclass in Python — isinstance(True, int) is True —
    # so it must be excluded explicitly, not just type-checked as int.
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{name} must be a positive int, got {value!r}")


def validate_config(cfg: EmbeddingSpaceConfig) -> None:
    """Raises ValueError for anything register_space/embed_query/
    embed_documents must never silently accept. Called at the start of
    every one of those entrypoints — never assumed to have been called
    already by whoever constructed the config."""
    for field_name in ("provider", "endpoint", "model", "revision", "tokenizer_model"):
        value = getattr(cfg, field_name)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{field_name} must be a non-empty string")
    if cfg.provider not in SUPPORTED_PROVIDERS:
        raise ValueError(f"unsupported provider {cfg.provider!r} (supported: {sorted(SUPPORTED_PROVIDERS)})")
    if cfg.modality not in SUPPORTED_MODALITIES:
        raise ValueError(f"unsupported modality {cfg.modality!r} (supported: {sorted(SUPPORTED_MODALITIES)})")
    if cfg.document_preprocessing not in SUPPORTED_DOCUMENT_PREPROCESSING:
        raise ValueError(
            f"unsupported document_preprocessing {cfg.document_preprocessing!r} "
            f"(supported: {sorted(SUPPORTED_DOCUMENT_PREPROCESSING)}) — embed_documents sends text raw "
            "and must never claim to apply a transform it does not actually perform"
        )
    if cfg.enrichment_fingerprint is not None and not re.fullmatch(r"[0-9a-f]{64}", cfg.enrichment_fingerprint):
        raise ValueError("enrichment_fingerprint must be a SHA-256 hex digest or None")
    if not cfg.endpoint.startswith(("http://", "https://")):
        raise ValueError(f"endpoint must be an http(s) URL, got {cfg.endpoint!r}")
    _require_positive_int("dimension", cfg.dimension)
    _require_positive_int("max_tokens", cfg.max_tokens)
    _require_positive_int("max_batch", cfg.max_batch)
    if isinstance(cfg.timeout_s, bool) or not isinstance(cfg.timeout_s, (int, float)) or not math.isfinite(cfg.timeout_s) or cfg.timeout_s <= 0:
        raise ValueError(f"timeout_s must be a finite positive number, got {cfg.timeout_s!r}")
    if cfg.tokenizer_revision.strip().lower() in _UNPINNED_REVISIONS:
        raise ValueError(
            f"tokenizer_revision {cfg.tokenizer_revision!r} is not a pinned reference — pass an explicit "
            "commit sha or version tag (never 'main'/'latest'/empty), matching chunking.py's own "
            "pinned-revision invariant for processing-profile immutability"
        )
    if not isinstance(cfg.query_task_description, str) or not cfg.query_task_description.strip():
        raise ValueError("query_task_description must be a non-empty string")
    placeholders = set(_TEMPLATE_PLACEHOLDER_RE.findall(cfg.query_preprocessing_template))
    if "query" not in placeholders:
        raise ValueError(
            f"query_preprocessing_template {cfg.query_preprocessing_template!r} does not contain a "
            "'{query}' placeholder — a template that never inserts the query would silently embed "
            "unrelated text for every search"
        )
    if not placeholders <= {"task", "query"}:
        raise ValueError(
            f"query_preprocessing_template contains unsupported placeholder(s): {placeholders - {'task', 'query'}}"
        )


def fingerprint_space(cfg: EmbeddingSpaceConfig) -> str:
    canonical = json.dumps(cfg.identity_fields(), sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _encode_query_preprocessing(cfg: EmbeddingSpaceConfig) -> str:
    return json.dumps(
        {"template": cfg.query_preprocessing_template, "task_description": cfg.query_task_description,
         "enrichment_fingerprint": cfg.enrichment_fingerprint},
        sort_keys=True, separators=(",", ":"), ensure_ascii=True,
    )


def register_space(con: sqlite3.Connection, cfg: EmbeddingSpaceConfig) -> int:
    """Get-or-create by fingerprint. `embedding_spaces` rows are immutable
    once created — caller must already hold the write lock (BEGIN
    IMMEDIATE), matching every other get-or-create in this package
    (store._get_or_create_collection). The full query preprocessing
    identity (template AND task description, both of which feed the
    fingerprint) is persisted as a JSON descriptor — not just the template
    — so `config_from_space_row` can reconstruct an equivalent config
    without needing today's code defaults."""
    validate_config(cfg)
    fp = fingerprint_space(cfg)
    row = con.execute("SELECT space_id FROM embedding_spaces WHERE fingerprint = ?", (fp,)).fetchone()
    if row is not None:
        return row[0]
    now_ms = int(time.time() * 1000)
    cur = con.execute(
        "INSERT INTO embedding_spaces(fingerprint, provider, model, revision, dimension, modality, "
        "document_preprocessing, query_preprocessing, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            fp, cfg.provider, cfg.model, cfg.revision, cfg.dimension, cfg.modality,
            cfg.document_preprocessing, _encode_query_preprocessing(cfg), now_ms,
        ),
    )
    assert cur.lastrowid is not None
    return cur.lastrowid


def config_from_space_row(
    con: sqlite3.Connection, space_id: int, *, endpoint: str, tokenizer_model: str, tokenizer_revision: str,
    max_tokens: int, timeout_s: float = DEFAULT_TIMEOUT_S, max_batch: int = DEFAULT_MAX_BATCH,
) -> EmbeddingSpaceConfig:
    """Reconstructs a config from a stored `embedding_spaces` row plus the
    operational fields a caller supplies (normally read from the owning
    processing_profile's chunker_config — see profiles.py — never from this
    module's own current-code defaults, which could have changed since the
    space was registered)."""
    row = con.execute(
        "SELECT provider, model, revision, dimension, modality, document_preprocessing, query_preprocessing "
        "FROM embedding_spaces WHERE space_id = ?", (space_id,),
    ).fetchone()
    if row is None:
        raise ValueError(f"embedding space {space_id} not found")
    provider, model, revision, dimension, modality, document_preprocessing, query_preprocessing_json = row
    qp = json.loads(query_preprocessing_json)
    return EmbeddingSpaceConfig(
        provider=provider, endpoint=endpoint, model=model, revision=revision, dimension=dimension,
        modality=modality, document_preprocessing=document_preprocessing,
        query_preprocessing_template=qp["template"], query_task_description=qp["task_description"],
        tokenizer_model=tokenizer_model, tokenizer_revision=tokenizer_revision, max_tokens=max_tokens,
        timeout_s=timeout_s, max_batch=max_batch,
        enrichment_fingerprint=qp.get("enrichment_fingerprint"),
    )


def wrap_query(cfg: EmbeddingSpaceConfig, query: str) -> str:
    return cfg.query_preprocessing_template.format(task=cfg.query_task_description, query=query)


def _tokenizer(cfg: EmbeddingSpaceConfig):  # -> chunking.HuggingFaceTokenizer
    return chunking.get_tokenizer(cfg.tokenizer_model, cfg.tokenizer_revision, cfg.max_tokens)


def count_tokens(cfg: EmbeddingSpaceConfig, text: str) -> int:
    return _tokenizer(cfg).count_tokens(text)


def _classify_http_error(exc: urllib.error.HTTPError) -> tuple[str, bool]:
    status = exc.code
    if status == 429:
        return "PROVIDER_RATE_LIMITED", True
    if 500 <= status < 600:
        return "PROVIDER_SERVER_ERROR", True
    # Permanent config/auth/model errors (400/401/403/404/422/...) — never
    # worth retrying without the caller changing something first. Never
    # includes the response body in the message (may carry request
    # echoes or provider-side auth text).
    return "PROVIDER_REQUEST_ERROR", False


def _post_embeddings(cfg: EmbeddingSpaceConfig, texts: list[str]) -> dict[str, object]:
    if not texts:
        raise ValueError("embed: at least one text is required")
    if len(texts) > cfg.max_batch:
        raise EmbeddingError(
            "BATCH_TOO_LARGE", f"{len(texts)} texts exceeds max_batch={cfg.max_batch}", retryable=False
        )
    body = json.dumps({"model": cfg.model, "input": texts}).encode("utf-8")
    req = urllib.request.Request(
        f"{cfg.endpoint.rstrip('/')}/embeddings",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=cfg.timeout_s) as resp:  # noqa: S310 - local/operator-configured endpoint
            raw = resp.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as exc:
        code, retryable = _classify_http_error(exc)
        raise EmbeddingError(code, f"embedding provider returned HTTP {exc.code}", retryable=retryable) from exc
    except TimeoutError as exc:
        # Covers a read-phase timeout — urlopen's own connect-phase timeout
        # surfaces as urllib.error.URLError(TimeoutError) below, but a
        # timeout during resp.read() on an already-open connection can
        # raise this directly, and must be classified as retryable too.
        raise EmbeddingError("PROVIDER_TIMEOUT", "embedding provider request timed out", retryable=True) from exc
    except urllib.error.URLError as exc:
        raise EmbeddingError(
            "PROVIDER_UNREACHABLE", "embedding provider request failed (connection)", retryable=True
        ) from exc
    if len(raw) > MAX_RESPONSE_BYTES:
        raise EmbeddingError(
            "PROVIDER_BAD_RESPONSE", f"embedding provider response exceeds {MAX_RESPONSE_BYTES} bytes",
            retryable=False,
        )
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise EmbeddingError(
            "PROVIDER_BAD_RESPONSE", f"embedding provider returned invalid JSON: {exc}", retryable=False
        ) from exc
    if not isinstance(payload, dict):
        raise EmbeddingError(
            "PROVIDER_BAD_RESPONSE", f"embedding provider response is not a JSON object: {type(payload).__name__}",
            retryable=False,
        )
    return payload


def _check_float32_safe(idx: int, floats: list[float]) -> bytes:
    """Packs to the EXACT bytes vec0 will store and round-trips them — a
    finite float64 component can silently overflow to +-inf or underflow
    to 0.0 once narrowed to float32, and struct.pack itself does not raise
    on either (verified: struct.pack('f', 1e39) succeeds and yields inf).
    Returns the packed bytes so callers never re-pack (and risk drifting
    from what was actually validated)."""
    packed = struct.pack(f"{len(floats)}f", *floats)
    unpacked = struct.unpack(f"{len(floats)}f", packed)
    if not all(math.isfinite(x) for x in unpacked):
        raise EmbeddingError(
            "NON_FINITE_VECTOR", f"embedding at index {idx} overflows float32 vec0 storage representation",
            retryable=False,
        )
    if all(x == 0.0 for x in unpacked):
        raise EmbeddingError(
            "ZERO_VECTOR", f"embedding at index {idx} underflows to an all-zero float32 vector", retryable=False
        )
    return packed


def _validate_and_pack(cfg: EmbeddingSpaceConfig, payload: dict[str, object], expected_count: int) -> list[bytes]:
    """Validates the OpenAI-compatible response contract strictly and
    returns each embedding as its final float32-packed bytes (the exact
    representation that will be stored/queried), in request order."""
    echoed_model = payload.get("model")
    if not isinstance(echoed_model, str) or echoed_model != cfg.model:
        raise EmbeddingError(
            "MODEL_MISMATCH", f"provider echoed model {echoed_model!r}, expected {cfg.model!r}", retryable=False
        )
    data = payload.get("data")
    if not isinstance(data, list) or len(data) != expected_count:
        got = len(data) if isinstance(data, list) else type(data).__name__
        raise EmbeddingError(
            "PROVIDER_BAD_RESPONSE", f"expected {expected_count} embeddings, got {got}", retryable=False
        )
    ordered: list[bytes | None] = [None] * expected_count
    seen: set[int] = set()
    for item in data:
        if not isinstance(item, dict):
            raise EmbeddingError("PROVIDER_BAD_RESPONSE", "embedding item is not an object", retryable=False)
        idx = item.get("index")
        vec = item.get("embedding")
        # bool is a subclass of int — isinstance(True, int) is True — so
        # `type(idx) is int` (not isinstance) is the correct exact check.
        if type(idx) is not int or not (0 <= idx < expected_count):
            raise EmbeddingError("PROVIDER_BAD_RESPONSE", f"invalid or out-of-range index: {idx!r}", retryable=False)
        if idx in seen:
            raise EmbeddingError("PROVIDER_BAD_RESPONSE", f"duplicate index {idx} in response", retryable=False)
        seen.add(idx)
        if not isinstance(vec, list) or len(vec) != cfg.dimension:
            got_dim = len(vec) if isinstance(vec, list) else type(vec).__name__
            raise EmbeddingError(
                "DIMENSION_MISMATCH", f"embedding at index {idx} has {got_dim} dims, expected {cfg.dimension}",
                retryable=False,
            )
        floats: list[float] = []
        for component in vec:
            # Strict: an actual JSON number, never a bool (subclass of
            # int) and never a numeric string coerced via float().
            if isinstance(component, bool) or not isinstance(component, (int, float)):
                raise EmbeddingError(
                    "PROVIDER_BAD_RESPONSE",
                    f"embedding at index {idx} contains a non-numeric component: {component!r}",
                    retryable=False,
                )
            floats.append(float(component))
        if not all(math.isfinite(x) for x in floats):
            raise EmbeddingError(
                "NON_FINITE_VECTOR", f"embedding at index {idx} contains a non-finite value", retryable=False
            )
        if all(x == 0.0 for x in floats):
            raise EmbeddingError("ZERO_VECTOR", f"embedding at index {idx} is an all-zero vector", retryable=False)
        ordered[idx] = _check_float32_safe(idx, floats)
    if len(seen) != expected_count:
        raise EmbeddingError(
            "PROVIDER_BAD_RESPONSE", "response did not cover every requested index", retryable=False
        )
    return [v for v in ordered if v is not None]  # every slot filled — len(seen) check above guarantees it


def embed_query(cfg: EmbeddingSpaceConfig, query: str) -> bytes:
    """Returns the query embedding as float32-packed bytes, ready to bind
    directly into a vec0 `MATCH ?` query."""
    validate_config(cfg)
    wrapped = wrap_query(cfg, query)
    n_tokens = count_tokens(cfg, wrapped)
    if n_tokens > cfg.max_tokens:
        raise EmbeddingError(
            "QUERY_TOO_LONG",
            f"query is {n_tokens} tokens (after instruction wrapping), exceeds max_tokens={cfg.max_tokens} "
            "— refusing to silently truncate",
            retryable=False,
        )
    payload = _post_embeddings(cfg, [wrapped])
    return _validate_and_pack(cfg, payload, 1)[0]


def embed_documents(
    cfg: EmbeddingSpaceConfig, texts: list[str], *, on_batch: Callable[[int, int], None] | None = None
) -> list[bytes]:
    """Documents are passed raw (no instruction wrapper, per the model
    card) — `document_preprocessing` is validated to be exactly "raw"
    (validate_config) so this behavior can never silently diverge from
    what a registered space's identity claims. Each text is defensively
    re-checked against max_tokens even though the caller's HybridChunker
    should already guarantee this — chunking.py's own chunker raises on a
    budget violation before a chunk ever reaches here, so this is belt-
    and-suspenders, never the primary guard. Batches at cfg.max_batch; a
    batch failure raises without embedding any further batches (never a
    partial silent skip). `on_batch(completed_count, total_count)`, if
    given, is invoked after each batch succeeds — the pipeline's lease
    design uses this hook to renew a long-running job's claim between
    provider round-trips, never inside this module (which has no concept
    of jobs/leases)."""
    validate_config(cfg)
    if not texts:
        return []
    for i, text in enumerate(texts):
        n_tokens = count_tokens(cfg, text)
        if n_tokens > cfg.max_tokens:
            raise EmbeddingError(
                "DOCUMENT_TOO_LONG", f"document text {i} is {n_tokens} tokens, exceeds max_tokens={cfg.max_tokens}",
                retryable=False,
            )
    all_vectors: list[bytes] = []
    for start in range(0, len(texts), cfg.max_batch):
        batch = texts[start : start + cfg.max_batch]
        payload = _post_embeddings(cfg, batch)
        all_vectors.extend(_validate_and_pack(cfg, payload, len(batch)))
        if on_batch is not None:
            on_batch(len(all_vectors), len(texts))
    return all_vectors


def vec_space_table_name(space_id: int) -> str:
    # Only ever constructed from an internal validated int primary key
    # (never user text) — safe to interpolate into DDL/DML (schema.py's
    # module docstring: "only internal validated IDs construct table
    # names").
    return f"vec_space_{int(space_id)}"


def ensure_vec_space_table(con: sqlite3.Connection, space_id: int, dimension: int) -> str:
    if not vecext.try_load_vec0(con):
        raise EmbeddingError("VEC0_UNAVAILABLE", "sqlite_vec extension could not be loaded", retryable=False)
    table = vec_space_table_name(space_id)
    con.execute(
        f"CREATE VIRTUAL TABLE IF NOT EXISTS {table} USING vec0("
        f"chunk_id INTEGER PRIMARY KEY, embedding FLOAT[{int(dimension)}] distance_metric=cosine, "
        f"source_id INTEGER, collection_id INTEGER, generation_id INTEGER, active INTEGER)"
    )
    return table
