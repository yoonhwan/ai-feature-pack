"""ft 2.0 keeper 멈춤 갈래 — pi 세션 끝 줄 판독과 오류 종류 (r1921 · keeper_stall.py 300줄 상한 → 이 파일로 나눔).

오류 종류 낱말·순서 = 1.x ft_seat_pi_turn.error_state 와 같다(ft2 는 1.x 를 import 하지 않는다 · 표는 이 파일 머리 1곳).
"""
import datetime, json, re  # noqa: E401

TAIL, AUTH = 262144, ("authentication_failed", "invalid_api_key", "not logged in")
# 출처 = ft_seat_pi_turn.error_state · «connection reset by peer» = 1.x 밖 추가 · r1921
ERRORS = (("LOGGEDOUT", AUTH), ("RATELIMITED", ("rate_limit_error", "quota", "usage limit", "would exceed your account's rate limit")),
          ("UNAVAILABLE", ("econnrefused", "timeout", "socket", "dns", "temporarily unavailable", "overloaded", "connection reset by peer")))
HTTP = re.compile(r"\b(?:503|429)\b")


def records(path):
    """pi 세션 jsonl 끝 256KB 의 message 줄(바깥 줄 그대로) · 깨진 줄 = None."""
    with open(path, "rb") as fh:
        size = fh.seek(0, 2)
        fh.seek(max(0, size - TAIL))
        raw = fh.read().decode("utf-8", "replace").splitlines()
    rows = []
    for i, line in enumerate(raw):
        try:
            rec = json.loads(line)
        except ValueError:
            if i == 0 and size > TAIL:
                continue
            return None
        if isinstance(rec, dict) and rec.get("type") == "message" and isinstance(rec.get("message"), dict):
            rows.append(rec)
    return rows


def is_error(message):
    return message.get("stopReason") in ("error", "aborted") or "errorMessage" in message or "error" in message


def why(message):
    """오류 칸(errorMessage·error)만 본다 — assistant 본문은 오류 종류의 근거가 아니다."""
    return json.dumps({k: message[k] for k in ("errorMessage", "error") if k in message}).lower()


def error_turn(path):
    """마지막 assistant 가 오류면 (종류, 그 줄 바깥 timestamp epoch | None) · 아니면 None."""
    recs = [r for r in records(path) or () if r["message"].get("role") == "assistant"][-1:]
    if not recs or not is_error(recs[0]["message"]):
        return None
    text = why(recs[0]["message"])
    kind = next((n for n, words in ERRORS if any(w in text for w in words) or (n == "UNAVAILABLE" and HTTP.search(text))), "UNKNOWN")
    try:
        return kind, datetime.datetime.fromisoformat(str(recs[0].get("timestamp")).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return kind, None
