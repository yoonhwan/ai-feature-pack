"""Pi contract v3: explicit normal termination is the only positive idle evidence."""
import json
import re


def is_pi_file(path):
    with open(path, encoding="utf-8") as stream:
        try:
            head = json.loads(stream.readline())
        except ValueError:
            return False
    return isinstance(head, dict) and head.get("type") == "session"


def error_state(message):
    # Only error fields are inspected; assistant prose cannot prove an error class.
    evidence = json.dumps({k: message[k] for k in ("errorMessage", "error") if k in message}).lower()
    if any(x in evidence for x in ("authentication_failed", "invalid_api_key", "not logged in")):
        return "LOGGEDOUT", "authentication"
    if any(x in evidence for x in ("rate_limit_error", "quota", "usage limit", "would exceed your account's rate limit")):
        return "RATELIMITED", "rate_limit"
    if any(x in evidence for x in ("econnrefused", "timeout", "socket", "dns")):
        return "UNAVAILABLE", "connection"
    if re.search(r"\b(?:503|429)\b", evidence):
        return "UNAVAILABLE", "http_unavailable"
    # r1761 A1: 모델 쪽 일시 오류(OpenGateway·cliproxy) — 결속 실패가 아니라 «모델 일시 오류» 다
    if any(x in evidence for x in ("temporarily unavailable", "overloaded")):
        return "UNAVAILABLE", "model_unavailable"
    return "UNKNOWN", "error_without_class"


def judge(records):
    messages = [r for r in records if r.get("type") == "message" and isinstance(r.get("message"), dict)]
    assistants = [i for i, r in enumerate(messages) if r["message"].get("role") == "assistant"]
    last = assistants[-1] if assistants else -1
    assistant = messages[last]["message"] if last >= 0 else {}
    if assistant.get("stopReason") in ("error", "aborted") or "errorMessage" in assistant or "error" in assistant:
        state, why = error_state(assistant)
        return state, "-", why
    # These are event types, never words found in a message's content.
    retry, queued = False, False
    for record in records:
        if record.get("type") == "retry_start":
            retry = True
        elif record.get("type") == "retry_end":
            retry = False
        elif record.get("type") == "queue-operation":
            queued = record.get("operation") == "enqueue"
    if retry:
        return "WORKING", "-", "retry"
    if messages and messages[-1]["message"].get("role") == "user":
        return "PENDING", "-", "user"
    if queued:
        return "PENDING", "-", "queue"
    after = messages[last + 1:] if last >= 0 else messages
    blocked = any(r["message"].get("role") in ("user", "toolResult") or "errorMessage" in r["message"]
                  or "error" in r["message"] for r in after)
    if last >= 0 and "stopReason" in assistant and assistant["stopReason"] in ("end_turn", "stop", "max_tokens", None) and not blocked:
        end = messages[last].get("timestamp")
        return ("IDLE", end, "-") if isinstance(end, str) and end else ("UNKNOWN", "-", "missing_timestamp")
    if assistant.get("stopReason") == "toolUse" or (messages and messages[-1]["message"].get("role") == "toolResult"):
        return "WORKING", "-", "tool"
    return "UNKNOWN", "-", "no_terminal_evidence"


def file_row(path):
    records, size = [], 0
    with open(path, "rb") as stream:
        for line in stream:
            size += len(line)
            try:
                record = json.loads(line)
            except ValueError:
                raise ValueError("Pi jsonl 불완전/손상 레코드") from None
            if isinstance(record, dict):
                records.append(record)
    state, end, why = judge(records)
    return [state, end, "1" if state == "LOGGEDOUT" else "-", "-", "pi", str(size), "-", why]
