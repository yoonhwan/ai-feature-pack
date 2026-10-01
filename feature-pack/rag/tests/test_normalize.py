from __future__ import annotations

import json

import pytest

from airag import normalize


def _items(nd: normalize.NormalizedDocument) -> list[tuple[str, str | None]]:
    return [(type(item).__name__, getattr(item, "text", None)) for item, _ in nd.doc.iterate_items()]


def test_plain_text_single_paragraph_becomes_one_text_item() -> None:
    nd = normalize.build_document("text/plain", b"hello world", name="a.txt")
    assert _items(nd) == [("TextItem", "hello world")]


def test_plain_text_blank_line_separated_paragraphs() -> None:
    content = b"first paragraph.\n\nsecond paragraph.\n\nthird paragraph."
    nd = normalize.build_document("text/plain", content, name="a.txt")
    assert [t for _, t in _items(nd)] == ["first paragraph.", "second paragraph.", "third paragraph."]


def test_plain_text_korean_content_preserved_exactly() -> None:
    content = "고양이는 하루의 대부분을 잠으로 보내는 동물이다.".encode("utf-8")
    nd = normalize.build_document("text/plain", content, name="a.txt")
    assert [t for _, t in _items(nd)] == ["고양이는 하루의 대부분을 잠으로 보내는 동물이다."]


def test_empty_content_yields_zero_items() -> None:
    nd = normalize.build_document("text/plain", b"", name="empty.txt")
    assert list(nd.doc.iterate_items()) == []


def test_plain_text_anchor_span_is_exact_char_offset_into_original() -> None:
    content = "  padded first.\n\n둘째 문단입니다.  \n".encode("utf-8")
    text = content.decode("utf-8")
    nd = normalize.build_document("text/plain", content, name="a.txt")
    items = list(nd.doc.iterate_items())
    for item, _ in items:
        anchor = nd.anchors[item.self_ref]
        assert anchor.unit == "char"
        assert text[anchor.start : anchor.end] == item.text == anchor.original_text


def test_plain_text_repeated_identical_paragraphs_get_distinct_spans() -> None:
    content = b"same line.\n\nsame line.\n\nsame line."
    nd = normalize.build_document("text/plain", content, name="a.txt")
    items = list(nd.doc.iterate_items())
    assert len(items) == 3
    spans = [(nd.anchors[item.self_ref].start, nd.anchors[item.self_ref].end) for item, _ in items]
    assert spans == [(0, 10), (12, 22), (24, 34)]  # each occurrence resolves to its OWN position, not the first


def test_markdown_headings_and_paragraphs() -> None:
    content = b"# Title\n\nIntro paragraph.\n\n## Section A\n\nBody of section A.\n"
    nd = normalize.build_document("text/markdown", content, name="a.md")
    assert _items(nd) == [
        ("TitleItem", "Title"),
        ("TextItem", "Intro paragraph."),
        ("SectionHeaderItem", "Section A"),
        ("TextItem", "Body of section A."),
    ]


def test_markdown_heading_without_blank_line_before_or_after_body() -> None:
    """'# Heading\\nbody' with NO blank line is ordinary valid Markdown —
    must not be flattened into one paragraph (review item 2)."""
    content = b"# Title\nintro right after heading, no blank line.\n## Next\nmore body\n"
    nd = normalize.build_document("text/markdown", content, name="a.md")
    assert _items(nd) == [
        ("TitleItem", "Title"),
        ("TextItem", "intro right after heading, no blank line."),
        ("SectionHeaderItem", "Next"),
        ("TextItem", "more body"),
    ]


def test_markdown_consecutive_headings_each_become_own_item() -> None:
    content = b"# H1\n## H2\n### H3\nbody\n"
    nd = normalize.build_document("text/markdown", content, name="a.md")
    kinds = [(k, t) for k, t in _items(nd)]
    assert kinds == [
        ("TitleItem", "H1"),
        ("SectionHeaderItem", "H2"),
        ("SectionHeaderItem", "H3"),
        ("TextItem", "body"),
    ]


def test_markdown_heading_levels_preserved() -> None:
    content = b"# H1\n\n## H2\n\n### H3\n\nbody text\n"
    nd = normalize.build_document("text/markdown", content, name="a.md")
    headers = [item.level for item, _ in nd.doc.iterate_items() if type(item).__name__ == "SectionHeaderItem"]
    assert headers == [1, 2]  # H1 becomes the document title, H2/H3 map to level-1/2 under it


def test_markdown_hash_inside_fenced_code_is_not_a_heading() -> None:
    content = b"# Title\n\n```python\n# this is a comment, not a heading\nx = 1\n```\n\nafter code.\n"
    nd = normalize.build_document("text/markdown", content, name="a.md")
    kinds = _items(nd)
    assert kinds[0] == ("TitleItem", "Title")
    # the fenced block (including its fence markers) is preserved verbatim as one text item
    assert "# this is a comment, not a heading" in kinds[1][1]
    assert "```python" in kinds[1][1]
    assert kinds[2] == ("TextItem", "after code.")


def test_markdown_four_backtick_fence_survives_nested_three_backtick_line() -> None:
    """A 4-backtick fence containing a literal 3-backtick line must not be
    closed by that shorter run — a '#' line still inside must stay body
    text, not become a heading (review regression request)."""
    content = (
        b"# Title\n\n"
        b"````\n"
        b"```\n"
        b"# not a heading, still inside the outer fence\n"
        b"````\n\n"
        b"after.\n"
    )
    nd = normalize.build_document("text/markdown", content, name="a.md")
    kinds = _items(nd)
    assert kinds[0] == ("TitleItem", "Title")
    assert "# not a heading, still inside the outer fence" in kinds[1][1]
    assert not any(k in ("TitleItem", "SectionHeaderItem") and t == "not a heading, still inside the outer fence" for k, t in kinds)
    assert kinds[-1] == ("TextItem", "after.")


def test_markdown_tilde_fence_not_closed_by_backtick_line() -> None:
    content = b"~~~\n```\nstill inside\n~~~\n\nafter.\n"
    nd = normalize.build_document("text/markdown", content, name="a.md")
    kinds = _items(nd)
    assert "```" in kinds[0][1] and "still inside" in kinds[0][1]
    assert kinds[-1] == ("TextItem", "after.")


def test_markdown_crlf_heading_recognized_and_span_exact() -> None:
    content = b"# Title\r\n\r\nbody line.\r\n"
    text = content.decode("utf-8")
    nd = normalize.build_document("text/markdown", content, name="a.md")
    kinds = _items(nd)
    assert kinds == [("TitleItem", "Title"), ("TextItem", "body line.")]
    title_item = next(item for item, _ in nd.doc.iterate_items() if type(item).__name__ == "TitleItem")
    anchor = nd.anchors[title_item.self_ref]
    assert text[anchor.start : anchor.end] == "Title"


def test_markdown_empty_heading_does_not_fabricate_item() -> None:
    content = b"#\n\nreal body.\n"
    nd = normalize.build_document("text/markdown", content, name="a.md")
    kinds = _items(nd)
    assert ("TitleItem", "") not in kinds
    assert not any(k in ("TitleItem", "SectionHeaderItem") for k, _ in kinds)


def test_markdown_roundtrip_export_contains_original_text() -> None:
    content = "# 제목\n\n한글 본문입니다.\n".encode("utf-8")
    nd = normalize.build_document("text/markdown", content, name="a.md")
    exported = normalize.export_standard_md(nd.doc)
    assert "제목" in exported
    assert "한글 본문입니다." in exported


def test_markdown_heading_anchor_is_exact_span_of_text_only() -> None:
    content = "## 한글 섹션 제목\n\nbody\n".encode("utf-8")
    text = content.decode("utf-8")
    nd = normalize.build_document("text/markdown", content, name="a.md")
    heading_item = next(item for item, _ in nd.doc.iterate_items() if type(item).__name__ in ("TitleItem", "SectionHeaderItem"))
    anchor = nd.anchors[heading_item.self_ref]
    assert text[anchor.start : anchor.end] == "한글 섹션 제목" == heading_item.text


def test_conversation_turns_become_heading_plus_text() -> None:
    content = json.dumps(
        {"turns": [{"role": "user", "text": "안녕하세요"}, {"role": "assistant", "text": "네, 안녕하세요!"}]}
    ).encode("utf-8")
    nd = normalize.build_document(normalize.CONVERSATION_MEDIA_TYPE, content, name="conv.json")
    assert _items(nd) == [
        ("SectionHeaderItem", "user"),
        ("TextItem", "안녕하세요"),
        ("SectionHeaderItem", "assistant"),
        ("TextItem", "네, 안녕하세요!"),
    ]


def test_conversation_turn_anchors_use_json_pointer_and_turn_id() -> None:
    content = json.dumps(
        {"turns": [{"role": "user", "text": "hi", "id": "t-1"}, {"role": "user", "text": "hi", "id": "t-2"}]}
    ).encode("utf-8")
    nd = normalize.build_document(normalize.CONVERSATION_MEDIA_TYPE, content, name="conv.json")
    text_items = [item for item, _ in nd.doc.iterate_items() if type(item).__name__ == "TextItem"]
    assert len(text_items) == 2
    anchors = [nd.anchors[item.self_ref] for item in text_items]
    # identical role+text turns still resolve to their OWN turn index/id, not a shared/first-match locator
    assert [a.pointer for a in anchors] == ["/turns/0/text", "/turns/1/text"]
    assert [a.turn_id for a in anchors] == ["t-1", "t-2"]


def test_conversation_empty_turn_text_yields_no_chunk_for_that_turn() -> None:
    content = json.dumps({"turns": [{"role": "user", "text": "   "}, {"role": "user", "text": "real"}]}).encode("utf-8")
    nd = normalize.build_document(normalize.CONVERSATION_MEDIA_TYPE, content, name="conv.json")
    assert _items(nd) == [("SectionHeaderItem", "user"), ("TextItem", "real")]


def test_conversation_empty_turns_yields_zero_items() -> None:
    content = json.dumps({"turns": []}).encode("utf-8")
    nd = normalize.build_document(normalize.CONVERSATION_MEDIA_TYPE, content, name="conv.json")
    assert list(nd.doc.iterate_items()) == []


def test_conversation_malformed_json_raises_value_error() -> None:
    with pytest.raises(ValueError, match="conversation"):
        normalize.build_document(normalize.CONVERSATION_MEDIA_TYPE, b"not json", name="conv.json")


def test_conversation_nonfinite_number_rejected_by_strict_json_loader() -> None:
    """Proves the SAME strict loader as store.strict_json_loads is used here
    (review item 3), not a second permissive json.loads: a bare Infinity
    token is a Python json.loads extension normally accepted silently."""
    with pytest.raises(ValueError, match="conversation"):
        normalize.build_document(
            normalize.CONVERSATION_MEDIA_TYPE,
            b'{"turns": [{"role": "user", "text": "hi", "score": Infinity}]}',
            name="conv.json",
        )


def test_conversation_missing_role_rejected() -> None:
    with pytest.raises(ValueError, match="conversation"):
        normalize.build_document(normalize.CONVERSATION_MEDIA_TYPE, b'{"turns": [{"text": "hi"}]}', name="conv.json")


def test_unsupported_media_type_raises_value_error() -> None:
    with pytest.raises(ValueError, match="media_type"):
        normalize.build_document("application/x-unsupported-format", b"unknown", name="a.bin")


def test_export_structured_dict_is_json_serializable() -> None:
    nd = normalize.build_document("text/markdown", b"# T\n\nbody\n", name="a.md")
    structured = normalize.export_structured(nd.doc)
    reloaded = json.loads(json.dumps(structured))
    assert isinstance(reloaded, dict)
