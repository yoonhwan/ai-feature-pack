"""Versioned, fail-closed redaction before consumer durable writes."""

from __future__ import annotations

from dataclasses import dataclass
import json
import re

from .events import Event, EventError, parse_event


POLICY_VERSION = "airag-local-redaction-r1"
_TAGS = re.compile(r"</?(user_shell_command|environment_context)\s*>", re.IGNORECASE)
_TAG_LIKE = re.compile(r"</?(?:user_shell_command|environment_context)\b", re.IGNORECASE)
_RULES = (
    ("private_key", re.compile(
        r"-----BEGIN (?P<label>(?:[A-Z0-9]+ )*PRIVATE KEY)-----.*?"
        r"-----END (?P=label)-----", re.DOTALL,
    )),
    ("bearer", re.compile(r"\bBearer[ \t]+[A-Za-z0-9._~+/=-]+", re.IGNORECASE)),
    ("named_secret", re.compile(
        r"""\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|secret)\b["']?\s*[:=]\s*(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s&,;<>]+)""",
        re.IGNORECASE,
    )),
    ("url_credentials", re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s/@]+:[^\s/@]+@", re.IGNORECASE)),
)


@dataclass(frozen=True)
class RedactedEvent:
    event: Event
    audit_rules: tuple[str, ...]
    has_public_text: bool


def _redact_text(text: str, *, public_only: bool = False) -> tuple[str, tuple[str, ...]]:
    parts = []
    cursor = 0
    opened: tuple[str, int] | None = None
    rules = []
    for match in _TAGS.finditer(text):
        closing = match.group().startswith("</")
        tag = match.group(1).lower()
        if not closing:
            if opened is not None:
                raise EventError("AMBIGUOUS_INJECTED_BLOCK")
            parts.append(text[cursor:match.start()])
            opened = (tag, match.start())
        else:
            if opened is None or opened[0] != tag:
                raise EventError("UNBALANCED_INJECTED_BLOCK")
            parts.append("" if public_only else f"[REDACTED:{tag}]")
            rules.append(tag)
            cursor = match.end()
            opened = None
    if opened is not None:
        raise EventError("UNBALANCED_INJECTED_BLOCK")
    parts.append(text[cursor:])
    output = "".join(parts)
    # Attribute-bearing or otherwise malformed versions must not leak through.
    if _TAG_LIKE.search(output):
        raise EventError("MALFORMED_INJECTED_BLOCK")
    for rule, pattern in _RULES:
        output, count = pattern.subn("" if public_only else f"[REDACTED:{rule}]", output)
        if count:
            rules.append(rule)
    if re.search(r"-----BEGIN [^\r\n]*PRIVATE KEY-----", output):
        raise EventError("INCOMPLETE_PRIVATE_KEY")
    return output, tuple(sorted(set(rules)))


def redact_text(text: str) -> tuple[str, tuple[str, ...]]:
    """Redact known rules, not a claim of comprehensive secret detection."""
    return _redact_text(text)


def redact_event(event: Event) -> RedactedEvent:
    """Revalidate even manually constructed Event objects before storage."""
    validated = parse_event(event.canonical_json, expected_scope=event.scope)
    if validated != event:
        raise EventError("EVENT_REPRESENTATION_MISMATCH")
    payload = json.loads(validated.canonical_json)
    rules = ()
    has_public_text = False
    if validated.content is not None:
        payload["content"], rules = redact_text(validated.content)
        public, _ = _redact_text(validated.content, public_only=True)
        has_public_text = bool(public.strip())
    # Opaque identity/reference metadata cannot be rewritten without breaking
    # anchors. Reject recognized secrets there instead of persisting them.
    def check_metadata(value: object) -> None:
        if isinstance(value, str):
            clean, hits = redact_text(value)
            if hits or clean != value:
                raise EventError("SENSITIVE_EVENT_METADATA")
        elif isinstance(value, dict):
            for item in value.values():
                check_metadata(item)
    for key, value in payload.items():
        if key != "content":
            check_metadata(value)
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return RedactedEvent(parse_event(encoded, expected_scope=event.scope), rules, has_public_text)
