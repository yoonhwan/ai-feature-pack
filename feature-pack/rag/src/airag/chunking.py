"""HybridChunker wrapper (design D-010, P-03 scope; anchor-granularity
design per .fable-team/airag/p03-normalize-review.txt item 4).

Chunks a `normalize.NormalizedDocument` via the REAL docling-core
HybridChunker — never a hand-rolled splitter. Each ChunkRecord's `text` is
the chunker's own `contextualize()` output (heading context folded in)
since that is the exact string a caller must embed; `raw_text` is the
chunk's bare serialized text without injected context. For binary
documents it may be extraction/OCR/inference; each anchor records that
origin instead of claiming a verbatim substring of original bytes.

Anchor granularity (review item 4): a DocItem's `self_ref` alone locates a
whole paragraph/turn, not necessarily the exact substring a chunk covers —
HybridChunker's semantic sub-chunker can split one long paragraph DocItem
across several chunks. For each doc_item a chunk covers:
- if the chunk includes that item's FULL original text (the common case:
  either a single un-split item, or several whole sibling items merged into
  one chunk by `merge_peers`), the anchor is `granularity="exact"` using
  that item's own recorded original span/pointer directly — no search
  needed.
- if the chunk's raw_text is a strict SUBSTRING of one item's original text
  (a long-paragraph split), the exact sub-span is located by a
  MONOTONIC per-self_ref cursor search (never a global/first-match search —
  splits are produced in left-to-right, non-overlapping order, so searching
  forward from the end of the previous match is provably correct here,
  unlike the whole-document `str.find` the review flagged as wrong for
  repeated identical paragraphs).
- if that substring cannot be located (should not happen; defensive only),
  the anchor falls back to `granularity="paragraph"`/`"turn"` using the
  item's own coarse span — never a fabricated fine-grained offset.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import Any

from docling_core.transforms.chunker.hybrid_chunker import HybridChunker
from docling_core.transforms.chunker.tokenizer.base import BaseTokenizer
from docling_core.transforms.chunker.tokenizer.huggingface import HuggingFaceTokenizer

from airag.normalize import NormalizedDocument, OriginalAnchor


@dataclass(frozen=True)
class ChunkRecord:
    index: int
    text: str  # contextualized text — what gets embedded
    raw_text: str  # bare serialized text; original/extracted/OCR/inferred origin is in the anchors
    anchor: dict[str, Any]
    token_count: int


@lru_cache(maxsize=8)
def _cached_hf_tokenizer(model_name: str, revision: str, max_tokens: int) -> HuggingFaceTokenizer:
    # Loading a HF tokenizer touches disk (and network on first use); this
    # cache means a long-lived process pays that cost once per (model,
    # revision, max_tokens) triple, not once per document processed.
    # `revision` MUST be an explicit, pinned git ref (a commit sha, or at
    # minimum a version tag) — never the floating default "main" branch.
    # ft-airag-arch-astra 2026-09-09: a processing_profile fingerprint that
    # only records `model_name` would silently start producing different
    # chunks/tokens the moment the upstream "main" tokenizer files change,
    # even though the profile_key on disk never changed. Pinning `revision`
    # here (and the caller folding it into the profile fingerprint, plus
    # docling-core's own version) is what makes a profile actually
    # immutable, matching D-010's processing-profile-immutability
    # invariant. Only small tokenizer/config files are ever downloaded this
    # way — never model weights.
    return HuggingFaceTokenizer.from_pretrained(model_name, revision=revision, max_tokens=max_tokens)


def get_tokenizer(model_name: str, revision: str, max_tokens: int) -> HuggingFaceTokenizer:
    """Public accessor for the same cached tokenizer `build_hf_chunker`
    uses — embeddings.py's token counting/truncation guard reuses THIS
    exact tokenizer (same model+revision+max_tokens triple) rather than a
    second one, since the processing profile's chunker is configured
    against the embedding model's own tokenizer/limit specifically."""
    return _cached_hf_tokenizer(model_name, revision, max_tokens)


def build_hf_chunker(model_name: str, revision: str, max_tokens: int) -> HybridChunker:
    return HybridChunker(tokenizer=_cached_hf_tokenizer(model_name, revision, max_tokens))


def build_chunker(tokenizer: BaseTokenizer) -> HybridChunker:
    return HybridChunker(tokenizer=tokenizer)


def _whole_item_anchor(base: OriginalAnchor) -> dict[str, Any]:
    if base.kind not in ("text_span", "conversation_turn"):
        return {
            "kind": base.kind, "granularity": base.granularity or "document",
            "locator": base.locator, "text_origin": base.text_origin,
            "extracted_text": base.original_text, "matched_text": None,
        }
    if base.kind == "text_span":
        return {
            "granularity": "exact",
            "kind": "text_span",
            "unit": base.unit,
            "start": base.start,
            "end": base.end,
            "matched_text": base.original_text,
        }
    return {
        "granularity": "exact",
        "kind": "conversation_turn",
        "pointer": base.pointer,
        "turn_id": base.turn_id,
        "matched_text": base.original_text,
    }


def _coarse_fallback_anchor(base: OriginalAnchor) -> dict[str, Any]:
    if base.kind not in ("text_span", "conversation_turn"):
        return _whole_item_anchor(base)
    granularity = "turn" if base.kind == "conversation_turn" else "paragraph"
    if base.kind == "text_span":
        return {
            "granularity": granularity,
            "kind": "text_span",
            "unit": base.unit,
            "start": base.start,
            "end": base.end,
            "matched_text": None,
        }
    return {
        "granularity": granularity,
        "kind": "conversation_turn",
        "pointer": base.pointer,
        "turn_id": base.turn_id,
        "matched_text": None,
    }


def _sub_span_anchor(base: OriginalAnchor, sub_text: str, cursors: dict[str, int], self_ref: str) -> dict[str, Any]:
    search_from = cursors.get(self_ref, 0)
    idx = base.original_text.find(sub_text, search_from)
    if idx == -1:
        idx = base.original_text.find(sub_text)  # last-resort: content may have been re-ordered; still explicit
    if idx == -1:
        return _coarse_fallback_anchor(base)
    cursors[self_ref] = idx + len(sub_text)
    if base.kind == "text_span":
        assert base.start is not None
        return {
            "granularity": "exact",
            "kind": "text_span",
            "unit": base.unit,
            "start": base.start + idx,
            "end": base.start + idx + len(sub_text),
            "matched_text": sub_text,
        }
    return {
        "granularity": "exact",
        "kind": "conversation_turn",
        "pointer": base.pointer,
        "turn_id": base.turn_id,
        "matched_text": sub_text,
    }


_HEADING_TYPE_NAMES = frozenset({"TitleItem", "SectionHeaderItem"})


def _chunk_real_content(nd: NormalizedDocument, chunker: HybridChunker) -> list[ChunkRecord]:
    tokenizer = chunker.tokenizer
    max_tokens = tokenizer.get_max_tokens()
    records: list[ChunkRecord] = []
    cursors: dict[str, int] = {}

    for i, c in enumerate(chunker.chunk(nd.doc)):
        contextualized = chunker.contextualize(c)
        token_count = tokenizer.count_tokens(contextualized)
        if token_count > max_tokens:
            # HybridChunker's own job is to keep every chunk within budget;
            # a violation here is a chunker/tokenizer mismatch bug, not
            # something to silently truncate and embed anyway.
            raise ValueError(
                f"chunk {i} exceeds tokenizer max_tokens ({token_count} > {max_tokens}) "
                "after contextualization — refusing to embed a silently truncated chunk"
            )

        doc_items = c.meta.doc_items
        item_anchors: list[dict[str, Any]] = []
        for di in doc_items:
            base = nd.anchors.get(di.self_ref)
            if base is None:
                item_anchors.append({"self_ref": di.self_ref, "granularity": "unknown", "matched_text": None})
                continue
            if len(doc_items) == 1 and c.text == base.original_text:
                anchor_entry = _whole_item_anchor(base)
            elif len(doc_items) > 1:
                # merge_peers merges whole sibling items, never fragments —
                # each item contributes its own full original text.
                anchor_entry = _whole_item_anchor(base)
            elif base.kind == "text_span" and c.text and c.text in base.original_text:
                anchor_entry = _sub_span_anchor(base, c.text, cursors, di.self_ref)
            else:
                anchor_entry = _coarse_fallback_anchor(base)
            anchor_entry["self_ref"] = di.self_ref
            item_anchors.append(anchor_entry)

        anchor = {"headings": list(c.meta.headings or []), "items": item_anchors}
        records.append(
            ChunkRecord(index=i, text=contextualized, raw_text=c.text, anchor=anchor, token_count=token_count)
        )
    return records


def chunk_document(nd: NormalizedDocument, chunker: HybridChunker) -> list[ChunkRecord]:
    """Real content is chunked by HybridChunker as usual, THEN merged with a
    document-order pass that synthesizes a standalone ChunkRecord for any
    heading/title item that has no chunked content between it and the next
    heading (or end of document) — HybridChunker never emits a chunk for a
    heading's own text by itself (verified empirically: a document
    consisting only of headings produces zero chunks from
    `chunker.chunk()`), so without this pass a real, non-empty heading with
    no body silently vanishes from search entirely. The synthesized
    record's text is the heading's own real text (never a fabricated
    placeholder) with its already-tracked exact original anchor — never a
    hash/placeholder vector. Detection is by DocItem self_ref identity
    (never by heading text string), so two different headings that happen
    to share identical text are still told apart correctly."""
    tokenizer = chunker.tokenizer
    max_tokens = tokenizer.get_max_tokens()
    real_records = _chunk_real_content(nd, chunker)

    covered_self_refs = {e["self_ref"] for r in real_records for e in r.anchor["items"] if "self_ref" in e}
    record_starts: dict[str, list[int]] = {}
    for idx, r in enumerate(real_records):
        first_ref = r.anchor["items"][0]["self_ref"] if r.anchor["items"] else None
        if first_ref is not None:
            record_starts.setdefault(first_ref, []).append(idx)

    output: list[ChunkRecord] = []
    consumed: set[int] = set()
    pending_heading: Any = None

    def flush_pending() -> None:
        nonlocal pending_heading
        if pending_heading is None:
            return
        base = nd.anchors.get(pending_heading.self_ref)
        if base is not None:
            text = pending_heading.text
            token_count = tokenizer.count_tokens(text)
            if token_count > max_tokens:
                raise ValueError(
                    f"heading-only chunk exceeds tokenizer max_tokens ({token_count} > {max_tokens}) — "
                    "refusing to embed a silently truncated chunk"
                )
            item_anchor = _whole_item_anchor(base)
            item_anchor["self_ref"] = pending_heading.self_ref
            output.append(
                ChunkRecord(
                    index=len(output),
                    text=text,
                    raw_text=text,
                    anchor={"headings": [], "items": [item_anchor]},
                    token_count=token_count,
                )
            )
        pending_heading = None

    for item, _level in nd.doc.iterate_items():
        if type(item).__name__ in _HEADING_TYPE_NAMES:
            flush_pending()  # the PREVIOUS heading (if any) had nothing under it
            pending_heading = item
            continue
        self_ref = getattr(item, "self_ref", None)
        if self_ref in covered_self_refs:
            pending_heading = None
            for idx in record_starts.get(self_ref, []):
                if idx not in consumed:
                    consumed.add(idx)
                    r = real_records[idx]
                    output.append(ChunkRecord(index=len(output), text=r.text, raw_text=r.raw_text, anchor=r.anchor, token_count=r.token_count))
    flush_pending()  # a trailing heading at end-of-document with nothing after it

    for idx, r in enumerate(real_records):
        if idx not in consumed:
            output.append(ChunkRecord(index=len(output), text=r.text, raw_text=r.raw_text, anchor=r.anchor, token_count=r.token_count))
    return output
