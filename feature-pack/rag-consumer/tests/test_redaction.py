from dataclasses import replace
import json

import pytest

from airag_consumer.events import EventError, parse_event
from airag_consumer.redaction import redact_event, redact_text


def test_injected_blocks_removed_with_public_text_preserved():
    text = "공개 질문 <environment_context>PRIVATE_PATH</environment_context> 답변"
    clean, rules = redact_text(text)
    assert clean == "공개 질문 [REDACTED:environment_context] 답변"
    assert rules == ("environment_context",)
    assert "PRIVATE_PATH" not in clean


@pytest.mark.parametrize("text", [
    "<environment_context>unfinished",
    "</user_shell_command>",
    "<environment_context></user_shell_command>",
    "<environment_context><user_shell_command>x</user_shell_command></environment_context>",
    "<environment_context attr='x'>bad</environment_context>",
    "-----BEGIN PRIVATE KEY----- unfinished",
])
def test_ambiguous_blocks_fail_closed(text):
    with pytest.raises(EventError):
        redact_text(text)


@pytest.mark.parametrize("text,secret,rule", [
    ("Authorization: Bearer SYNTHETIC_TOKEN", "SYNTHETIC_TOKEN", "bearer"),
    ('{"api_key": "SYNTHETIC_KEY"}', "SYNTHETIC_KEY", "named_secret"),
    ("password='SYNTHETIC_PASSWORD'", "SYNTHETIC_PASSWORD", "named_secret"),
    ("https://user:SYNTHETIC_PASSWORD@example.invalid/x", "SYNTHETIC_PASSWORD", "url_credentials"),
    ("https://example.invalid/?token=SYNTHETIC_TOKEN&x=1", "SYNTHETIC_TOKEN", "named_secret"),
    ("-----BEGIN RSA PRIVATE KEY-----\nSYNTHETIC_KEY\n-----END RSA PRIVATE KEY-----", "SYNTHETIC_KEY", "private_key"),
])
def test_secret_rules(text, secret, rule):
    clean, rules = redact_text(text)
    assert secret not in clean and rule in rules


def test_empty_search_body_still_has_redacted_event(payload, scope):
    payload["content"] = "<user_shell_command>private</user_shell_command>"
    raw = parse_event(json.dumps(payload).encode(), expected_scope=scope)
    result = redact_event(raw)
    assert result.event.message_id == "m001"
    assert result.audit_rules == ("user_shell_command",)
    assert result.has_public_text is False
    assert raw.content != result.event.content


def test_user_placeholder_is_public_text_even_next_to_real_redaction(payload, scope):
    payload["content"] = "[REDACTED:environment_context] <environment_context>private</environment_context>"
    raw = parse_event(json.dumps(payload).encode(), expected_scope=scope)
    result = redact_event(raw)
    assert result.has_public_text is True
    assert "private" not in result.event.content


def test_metadata_secrets_are_rejected_without_changing_identity(payload, scope):
    payload["attachment_ref"] = "https://user:PRIVATE@example.invalid/x"
    with pytest.raises(EventError, match="SENSITIVE_EVENT_METADATA"):
        redact_event(parse_event(json.dumps(payload).encode(), expected_scope=scope))


def test_forged_dataclass_cannot_bypass_canonical_validation(payload, scope):
    event = parse_event(json.dumps(payload).encode(), expected_scope=scope)
    with pytest.raises(EventError, match="EVENT_REPRESENTATION_MISMATCH"):
        redact_event(replace(event, content="different from canonical bytes"))
