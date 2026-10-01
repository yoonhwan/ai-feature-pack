from __future__ import annotations

from typing import Any

import pytest
from docling_core.transforms.chunker.tokenizer.base import BaseTokenizer
from docling_core.types.doc import DoclingDocument, DocItemLabel

from airag import chunking, normalize
from airag.normalize import NormalizedDocument, OriginalAnchor

# Pinned commit sha (2026-09-09, via HfApi().model_info(...).sha) — never
# "main", per ft-airag-arch-astra's fingerprint-stability correction: a
# floating branch ref would let the tokenizer silently change under an
# unchanged profile_key.
QWEN3_EMBEDDING_0_6B_REVISION = "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3"


class _WhitespaceTokenizer(BaseTokenizer):
    """Deterministic, network-free stand-in for pure chunk_document logic
    tests — counts whitespace-split words as tokens."""

    max_tokens: int = 100

    def count_tokens(self, text: str) -> int:
        return len(text.split())

    def get_max_tokens(self) -> int:
        return self.max_tokens

    def get_tokenizer(self) -> Any:
        # semchunk's internal re-splitter (only invoked when a single item
        # itself exceeds the token budget) needs a real callable — a plain
        # whitespace-splitter token counter is enough for these
        # network-free logic tests.
        return lambda s: len(s.split())


def _nd_two_sections() -> NormalizedDocument:
    doc = DoclingDocument(name="t")
    h1 = doc.add_heading("Section One", level=1)
    t1 = doc.add_text(DocItemLabel.TEXT, "first paragraph body")
    h2 = doc.add_heading("Section Two", level=1)
    t2 = doc.add_text(DocItemLabel.TEXT, "second paragraph body")
    anchors = {
        h1.self_ref: OriginalAnchor(kind="text_span", original_text="Section One", unit="char", start=0, end=11),
        t1.self_ref: OriginalAnchor(kind="text_span", original_text="first paragraph body", unit="char", start=12, end=32),
        h2.self_ref: OriginalAnchor(kind="text_span", original_text="Section Two", unit="char", start=33, end=44),
        t2.self_ref: OriginalAnchor(kind="text_span", original_text="second paragraph body", unit="char", start=45, end=66),
    }
    return NormalizedDocument(doc=doc, anchors=anchors)


def test_chunk_document_offline_with_fake_tokenizer_produces_records() -> None:
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    nd = _nd_two_sections()
    records = chunking.chunk_document(nd, chunker)

    assert len(records) == 2
    assert [r.index for r in records] == [0, 1]
    assert records[0].raw_text == "first paragraph body"
    assert "Section One" in records[0].text  # contextualized text includes heading
    assert records[0].anchor["headings"] == ["Section One"]
    item_anchors = records[0].anchor["items"]
    assert len(item_anchors) == 1
    assert item_anchors[0]["granularity"] == "exact"
    assert item_anchors[0]["start"] == 12
    assert item_anchors[0]["end"] == 32
    assert item_anchors[0]["matched_text"] == "first paragraph body"


def test_chunk_document_empty_doc_yields_zero_chunks() -> None:
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    nd = NormalizedDocument(doc=DoclingDocument(name="empty"), anchors={})
    records = chunking.chunk_document(nd, chunker)
    assert records == []


def test_chunk_document_raw_text_never_contains_injected_heading_context() -> None:
    """raw_text must stay verbatim-original even though text (contextualized)
    injects heading context — review item 4's separation requirement."""
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    nd = _nd_two_sections()
    records = chunking.chunk_document(nd, chunker)
    for r in records:
        assert "Section" not in r.raw_text


def test_chunk_document_repeated_identical_paragraphs_resolve_own_span() -> None:
    """A single long DocItem containing two IDENTICAL sentences, split by
    HybridChunker into separate chunks with a tiny token budget: each split
    chunk's anchor must resolve to its OWN occurrence in the source (via the
    monotonic cursor), not both collapsing onto the first occurrence."""
    doc = DoclingDocument(name="t")
    long_text = "same phrase. " * 2 + "same phrase."  # 3 identical sentences
    item = doc.add_text(DocItemLabel.TEXT, long_text)
    nd = NormalizedDocument(
        doc=doc,
        anchors={item.self_ref: OriginalAnchor(kind="text_span", original_text=long_text, unit="char", start=100, end=100 + len(long_text))},
    )
    tiny = _WhitespaceTokenizer(max_tokens=3)
    chunker = chunking.build_chunker(tiny)
    records = chunking.chunk_document(nd, chunker)

    assert len(records) >= 2  # the tiny budget forced a split
    spans = [(a["start"], a["end"]) for r in records for a in r.anchor["items"] if a["granularity"] == "exact"]
    starts = [s for s, _ in spans]
    assert starts == sorted(starts)  # strictly increasing — no two chunks collapsed onto the same start
    assert len(set(spans)) == len(spans)  # every span distinct


def test_chunk_document_merged_sibling_items_each_get_own_exact_anchor() -> None:
    """merge_peers merges two SEPARATE small sibling text items into one
    chunk — each contributing item keeps its own whole-item exact anchor,
    not a fabricated combined span."""
    doc = DoclingDocument(name="t")
    doc.add_heading("Sec", level=1)
    t1 = doc.add_text(DocItemLabel.TEXT, "alpha")
    t2 = doc.add_text(DocItemLabel.TEXT, "beta")
    nd = NormalizedDocument(
        doc=doc,
        anchors={
            t1.self_ref: OriginalAnchor(kind="text_span", original_text="alpha", unit="char", start=0, end=5),
            t2.self_ref: OriginalAnchor(kind="text_span", original_text="beta", unit="char", start=10, end=14),
        },
    )
    chunker = chunking.build_chunker(_WhitespaceTokenizer(max_tokens=100))
    records = chunking.chunk_document(nd, chunker)
    merged = [r for r in records if len(r.anchor["items"]) > 1]
    assert merged, "expected merge_peers to combine the two small siblings into one chunk"
    entries = {e["self_ref"]: e for e in merged[0].anchor["items"]}
    assert entries[t1.self_ref]["granularity"] == "exact"
    assert entries[t1.self_ref]["start"] == 0 and entries[t1.self_ref]["end"] == 5
    assert entries[t2.self_ref]["granularity"] == "exact"
    assert entries[t2.self_ref]["start"] == 10 and entries[t2.self_ref]["end"] == 14


def test_chunk_document_title_only_document_still_produces_one_chunk() -> None:
    """A document consisting of ONLY a title (no body text) must not lose
    its content entirely — HybridChunker itself emits 0 chunks for this
    (verified empirically), so chunk_document must recover it."""
    nd = normalize.build_document("text/markdown", b"# Title Only\n", name="a.md")
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    records = chunking.chunk_document(nd, chunker)
    assert len(records) == 1
    assert records[0].raw_text == "Title Only"
    assert records[0].text == "Title Only"
    assert records[0].anchor["items"][0]["granularity"] == "exact"
    assert records[0].anchor["items"][0]["matched_text"] == "Title Only"


def test_chunk_document_section_only_document_still_produces_one_chunk() -> None:
    nd = normalize.build_document("text/markdown", b"# T\n\n## Section Only\n", name="a.md")
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    records = chunking.chunk_document(nd, chunker)
    texts = sorted(r.raw_text for r in records)
    assert texts == ["Section Only", "T"]


def test_chunk_document_consecutive_headings_only_all_recovered_in_order() -> None:
    nd = normalize.build_document("text/markdown", b"# H1\n## H2\n### H3\n", name="a.md")
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    records = chunking.chunk_document(nd, chunker)
    assert [r.raw_text for r in records] == ["H1", "H2", "H3"]


def test_chunk_document_title_plus_body_is_still_a_single_normal_chunk() -> None:
    """The presence of the heading-recovery pass must not double-count a
    heading that DOES have real body content."""
    nd = normalize.build_document("text/markdown", b"# Title\n\nbody text here\n", name="a.md")
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    records = chunking.chunk_document(nd, chunker)
    assert len(records) == 1
    assert records[0].raw_text == "body text here"
    assert "Title" in records[0].text


def test_chunk_document_mixed_covered_and_uncovered_headings_all_present_in_order() -> None:
    content = b"# H1\n\nbody under h1\n\n## H2 empty\n\n### H3\n\nbody under h3\n"
    nd = normalize.build_document("text/markdown", content, name="a.md")
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    records = chunking.chunk_document(nd, chunker)
    assert [r.raw_text for r in records] == ["body under h1", "H2 empty", "body under h3"]


def test_chunk_document_unknown_self_ref_falls_back_to_unknown_granularity() -> None:
    doc = DoclingDocument(name="t")
    doc.add_text(DocItemLabel.TEXT, "orphan text, no anchor registered")
    nd = NormalizedDocument(doc=doc, anchors={})  # deliberately empty registry
    chunker = chunking.build_chunker(_WhitespaceTokenizer())
    records = chunking.chunk_document(nd, chunker)
    assert records[0].anchor["items"][0]["granularity"] == "unknown"


@pytest.mark.integration
def test_chunk_document_with_real_qwen_tokenizer_korean_and_english() -> None:
    chunker = chunking.build_hf_chunker("Qwen/Qwen3-Embedding-0.6B", QWEN3_EMBEDDING_0_6B_REVISION, max_tokens=8192)
    nd = normalize.build_document(
        "text/markdown",
        "# 제목\n\n한글 본문 문단입니다.\n\n## Section\n\nEnglish paragraph body.\n".encode("utf-8"),
        name="a.md",
    )
    records = chunking.chunk_document(nd, chunker)
    assert len(records) == 2
    assert all(r.token_count > 0 for r in records)
    assert all(r.token_count <= chunker.tokenizer.get_max_tokens() for r in records)
    assert "한글 본문 문단입니다." in records[0].raw_text
    assert "English paragraph body." in records[1].raw_text
    assert records[0].anchor["items"][0]["granularity"] == "exact"
    assert records[1].anchor["items"][0]["granularity"] == "exact"


@pytest.mark.integration
def test_chunk_document_real_tokenizer_long_paragraph_split_gets_exact_subspans() -> None:
    chunker = chunking.build_hf_chunker("Qwen/Qwen3-Embedding-0.6B", QWEN3_EMBEDDING_0_6B_REVISION, max_tokens=24)
    long_para = " ".join(f"문장{i}번입니다." for i in range(40))
    nd = normalize.build_document("text/markdown", f"# T\n\n{long_para}\n".encode("utf-8"), name="a.md")
    records = chunking.chunk_document(nd, chunker)
    assert len(records) > 1
    body_records = [r for r in records if r.anchor["headings"] and "T" not in r.raw_text]
    exact_spans = [
        (a["start"], a["end"])
        for r in body_records
        for a in r.anchor["items"]
        if a["granularity"] == "exact"
    ]
    assert len(exact_spans) >= 2
    starts = [s for s, _ in exact_spans]
    assert starts == sorted(starts)
    assert len(set(exact_spans)) == len(exact_spans)
