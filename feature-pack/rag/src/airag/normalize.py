"""Text/Markdown/conversation -> DoclingDocument, lightweight adapter layer
(design D-003/D-010, P-03 scope; provenance design per
.fable-team/airag/p03-normalize-review.txt 2026-09-09).

DoclingDocument is built directly via its own `add_*` builder API — never by
exporting Markdown and re-parsing that export (D-003's re-parsing ban).
Text/plain, Markdown and conversation use the lightweight builders here.
Binary formats are dispatched lazily to document_adapters: PDF/DOCX/XLSX
use native Docling conversion, HWP uses the configured hwplib JVM bridge,
and HWPX uses its package spine/XML. Images use explicit OCR/vision modes.

Provenance: a DocItem's `self_ref` only locates it inside the NORMALIZED
DoclingDocument tree — it is not, by itself, a pointer into the original
source bytes. `build_document` therefore returns a `NormalizedDocument`
carrying an explicit `anchors: dict[self_ref -> OriginalAnchor]` registry
built during the SAME single left-to-right parse that creates each item, so
a repeated identical paragraph/turn resolves to its own occurrence (never a
`str.find`-style search over the whole source that would always find the
first one). `OriginalAnchor.start`/`end` for text/markdown are Python `str`
codepoint (character, not byte) offsets into the DECODED source string —
callers needing byte offsets must re-encode and are on notice that this is
character-unit.

Markdown adapter scope (intentionally modest, matches the review): ATX
headings (`#`..`######`) are recognized on any line, WITH or WITHOUT a
blank line before/after (ordinary CommonMark does not require one), and
consecutive headings each become their own item. A line is never read as a
heading while inside a fenced code block (``` or ~~~ toggles fence state;
mismatched fence lengths/styles are not tracked — a known limitation, not a
silent misparse, since anything between two fence-toggle lines is preserved
verbatim as body text either way). Lists/tables are not given structural
representation in P-03 — a list item's source text is preserved verbatim as
part of its enclosing paragraph, deferring real list/table fidelity to P-04.
Empty headings (`#` with no non-whitespace text) and empty
paragraphs/turns never fabricate an item.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any

from docling_core.types.doc import DoclingDocument, DocItemLabel

from airag._json import strict_json_loads

CONVERSATION_MEDIA_TYPE = "application/x-airag-conversation+json"

_ATX_HEADING_RE = re.compile(r"^(#{1,6})[ \t]+(\S.*?)[ \t]*$")
_FENCE_OPEN_RE = re.compile(r"^(`{3,}|~{3,})")


def _split_line_body(line: str) -> str:
    """Strips exactly the trailing line terminator (`\\r\\n` or `\\n`) a
    `str.splitlines(keepends=True)` line carries — CRLF source files must
    not leave a stray `\\r` glued to the line body, which would otherwise
    make `_ATX_HEADING_RE`'s trailing `[ \\t]*$` fail to match (the `\\r` is
    not consumed by `[ \\t]`) and silently misclassify a CRLF heading line
    as an ordinary paragraph."""
    if line.endswith("\r\n"):
        return line[:-2]
    if line.endswith("\n") or line.endswith("\r"):
        return line[:-1]
    return line


@dataclass(frozen=True)
class OriginalAnchor:
    """Where a DocItem's text came from in the ORIGINAL source, not the
    normalized document. Text inputs use start/end or pointer; binary
    inputs use an observed locator and an explicit text_origin. The legacy
    original_text field holds the anchored representation: OCR and vision
    representations are not verbatim original text. Chunk anchors preserve
    that distinction and do not give them fabricated character offsets."""

    kind: str  # "text_span" | "conversation_turn"
    original_text: str
    unit: str | None = None  # "char" (codepoint offsets) for text_span
    start: int | None = None
    end: int | None = None
    pointer: str | None = None  # JSON Pointer, e.g. "/turns/2/text"
    turn_id: str | None = None  # the turn's own "id" field, if the caller supplied one
    locator: dict[str, Any] | None = None
    text_origin: str = "original"
    granularity: str | None = None


@dataclass(frozen=True)
class NormalizedDocument:
    doc: DoclingDocument
    anchors: dict[str, OriginalAnchor]
    artifacts: dict[str, Any] = field(default_factory=dict)


def _build_plain_text(content: bytes, *, name: str) -> NormalizedDocument:
    text = content.decode("utf-8")
    doc = DoclingDocument(name=name)
    anchors: dict[str, OriginalAnchor] = {}
    buf_start: int | None = None
    buf_end: int | None = None
    pos = 0

    def flush() -> None:
        nonlocal buf_start, buf_end
        if buf_start is None:
            return
        span_text = text[buf_start:buf_end]
        item = doc.add_text(DocItemLabel.TEXT, span_text)
        anchors[item.self_ref] = OriginalAnchor(
            kind="text_span", original_text=span_text, unit="char", start=buf_start, end=buf_end
        )
        buf_start = None
        buf_end = None

    for line in text.splitlines(keepends=True):
        line_body = _split_line_body(line)
        line_start = pos
        pos += len(line)
        if line_body.strip() == "":
            flush()
            continue
        if buf_start is None:
            buf_start = line_start + (len(line_body) - len(line_body.lstrip()))
        buf_end = line_start + len(line_body.rstrip())
    flush()
    return NormalizedDocument(doc=doc, anchors=anchors)


def _build_markdown(content: bytes, *, name: str) -> NormalizedDocument:
    text = content.decode("utf-8")
    doc = DoclingDocument(name=name)
    anchors: dict[str, OriginalAnchor] = {}
    title_used = False
    fence_char: str | None = None
    fence_len = 0
    buf_start: int | None = None
    buf_end: int | None = None
    pos = 0

    def flush_paragraph() -> None:
        nonlocal buf_start, buf_end
        if buf_start is None:
            return
        span_text = text[buf_start:buf_end]
        if span_text.strip():
            item = doc.add_text(DocItemLabel.TEXT, span_text)
            anchors[item.self_ref] = OriginalAnchor(
                kind="text_span", original_text=span_text, unit="char", start=buf_start, end=buf_end
            )
        buf_start = None
        buf_end = None

    def accumulate(line_start: int, line_body: str) -> None:
        nonlocal buf_start, buf_end
        stripped_len = len(line_body.strip())
        if stripped_len == 0:
            return
        if buf_start is None:
            buf_start = line_start + (len(line_body) - len(line_body.lstrip()))
        buf_end = line_start + len(line_body.rstrip())

    for line in text.splitlines(keepends=True):
        line_body = _split_line_body(line)
        line_start = pos
        pos += len(line)
        stripped = line_body.strip()

        if fence_char is None:
            m_open = _FENCE_OPEN_RE.match(stripped)
            if m_open:
                fence_char = m_open.group(1)[0]
                fence_len = len(m_open.group(1))
                accumulate(line_start, line_body)
                continue
        else:
            accumulate(line_start, line_body)
            # A closing fence must use the SAME character as the opener and
            # at least as many repeats — a shorter or different-character
            # run (e.g. ``` inside a ```` block, or ~~~ closing a ```
            # block) does not close it, so a `#` line still inside stays
            # body text instead of becoming a heading.
            if stripped and stripped == stripped[0] * len(stripped) and stripped[0] == fence_char and len(stripped) >= fence_len:
                fence_char = None
                fence_len = 0
            continue
        if stripped == "":
            flush_paragraph()
            continue

        m = _ATX_HEADING_RE.match(line_body)
        if m:
            flush_paragraph()
            level = len(m.group(1))
            h_start_in_line, h_end_in_line = m.span(2)
            heading_text = m.group(2)
            h_start = line_start + h_start_in_line
            h_end = line_start + h_end_in_line
            if level == 1 and not title_used:
                item = doc.add_title(heading_text)
                title_used = True
            else:
                item = doc.add_heading(heading_text, level=max(1, level - 1))
            anchors[item.self_ref] = OriginalAnchor(
                kind="text_span", original_text=heading_text, unit="char", start=h_start, end=h_end
            )
            continue

        accumulate(line_start, line_body)

    flush_paragraph()
    return NormalizedDocument(doc=doc, anchors=anchors)


def _build_conversation(content: bytes, *, name: str) -> NormalizedDocument:
    try:
        payload = strict_json_loads(content)
    except (json.JSONDecodeError, ValueError) as exc:
        raise ValueError(f"invalid conversation JSON: {exc}") from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("turns"), list):
        raise ValueError("invalid conversation JSON: expected {'turns': [...]}")

    doc = DoclingDocument(name=name)
    anchors: dict[str, OriginalAnchor] = {}
    for i, turn in enumerate(payload["turns"]):
        if (
            not isinstance(turn, dict)
            or not isinstance(turn.get("role"), str)
            or not turn.get("role")
            or not isinstance(turn.get("text"), str)
        ):
            raise ValueError(f"invalid conversation JSON: turn {i} must have non-empty string 'role' and string 'text'")
        turn_id = turn.get("id")
        if turn_id is not None and not isinstance(turn_id, str):
            raise ValueError(f"invalid conversation JSON: turn {i} 'id' must be a string when present")
        turn_text = turn["text"]
        if not turn_text.strip():
            continue  # empty turn body — do not fabricate a chunk
        role = turn["role"]
        h_item = doc.add_heading(role, level=1)
        anchors[h_item.self_ref] = OriginalAnchor(
            kind="conversation_turn", original_text=role, pointer=f"/turns/{i}/role", turn_id=turn_id
        )
        t_item = doc.add_text(DocItemLabel.TEXT, turn_text)
        anchors[t_item.self_ref] = OriginalAnchor(
            kind="conversation_turn", original_text=turn_text, pointer=f"/turns/{i}/text", turn_id=turn_id
        )
    return NormalizedDocument(doc=doc, anchors=anchors)


_ADAPTERS = {
    "text/plain": _build_plain_text,
    "text/markdown": _build_markdown,
    CONVERSATION_MEDIA_TYPE: _build_conversation,
}


def build_document(media_type: str, content: bytes, *, name: str, config: dict[str, Any] | None = None, vision=None, heartbeat=None) -> NormalizedDocument:
    """Construct a DoclingDocument and observed provenance registry.
    Binary conversion requires a captured documents_v1 configuration.
    Unsupported media and malformed content fail without a plain-text
    fallback; binary adapter failures use the shared structured error."""
    adapter = _ADAPTERS.get(media_type)
    if adapter is None:
        from airag.document_adapters import build_document as build_binary_document
        return build_binary_document(media_type, content, name=name, config=config or {}, vision=vision, heartbeat=heartbeat)
    return adapter(content, name=name)


def export_standard_md(doc: DoclingDocument) -> str:
    return doc.export_to_markdown()


def export_structured(doc: DoclingDocument) -> dict[str, Any]:
    return doc.export_to_dict()
